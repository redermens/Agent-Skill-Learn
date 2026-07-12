# Coverage Iteration Skill

## Subagent Architecture

Use subagents to isolate context — main agent only orchestrates and keeps summaries.

```
main_agent
  ├── @fixer  : PipelineRunner     (runs bash script P1–P6, returns paths + metrics)
  ├── @oracle : CoverageAnalyzer   (reads JSON + source, produces analysis plan)
  ├─┬ @fixer  : TestWriter         (writes HWTEST_F cases + updates BUILD.gn)
  │ └─┬ ...   : TestWriter         (one per file, in parallel)
  ├── @fixer  : CoverageVerifier   (re-runs pipeline, returns delta)
  └── loop ←─ until target reached
```

### Subagent Definitions

#### 1. PipelineRunner (@fixer)

| Aspect | Detail |
|--------|--------|
| **Input** | `part_name, device_ip:port, product_form, devtest_dir, ohos_root, [baseline_info_path]` |
| **Command** | `cd <devtest_dir> && ./cicd/coverage_pipeline.sh -p <part> -d <ip:port> -P <product> [-b <baseline>]` |
| **Output** | Paths: P6 JSON report, lcov .info, HTML dir. Summary metrics: line% and branch% |
| **Note** | Pure script execution. Capture stdout/stderr, extract key metrics from the summary block. Do NOT return full build logs. |
| **File-level** | Pass `-f <relative_path>` to focus on a single file. Example: `-f foundation/graphic/graphic_2d/src/rect.cpp` |

**Prompt template:**

```
Run the coverage pipeline for part {part_name}.

Working directory: {devtest_dir}
Command: cd {devtest_dir} && ./cicd/coverage_pipeline.sh -p {part_name} -d {device_ip_port} -P {product_form} [-b {baseline_path}] [-f {target_file_path}]
Timeout: 3600 seconds

After completion, return ONLY:
1. Did it succeed? (yes/no — check for "Pipeline Complete" in output)
2. Line coverage percentage (e.g. "72.3%")
3. Branch coverage percentage (e.g. "65.0%")
4. Path to P6 uncovered report JSON
5. Path to lcov .info file
6. Path to HTML report directory

Do NOT return the full build/test output.
```

---

#### 2. CoverageAnalyzer (@oracle)

| Aspect | Detail |
|--------|--------|
| **Input** | P6 JSON report path, OHOS root, part name, devtest dir |
| **Task** | Read JSON, sort files by uncovered count, read source code for top-N files, read existing test files |
| **Output** | Structured plan: for each file → list of (branch line, condition, function, suggested test approach) |

**Prompt template:**

```
Analyze the coverage uncovered report at {p6_report_path}.

OHOS root: {ohos_root}
Part: {part_name}

The JSON contains per-file uncovered branches. Each has:
  - file: path relative to OHOS root
  - line: source line of the branch
  - function: function name
  - code: the branching code

Your job:
1. Read the JSON
2. Sort files by uncovered_line_count descending
3. For the top files (those with most uncovered branches):
   a. Read the source file at <ohos_root>/<file>
   b. Read each function containing uncovered branches
   c. Find the existing test file (look for *_test.cpp in the same directory or a tests/ subdirectory)
   d. Read the existing test file to understand the test suite name and style

Return a structured plan:
```json
{
  "files": [
    {
      "source_file": "foundation/graphic/graphic_2d/src/rect.cpp",
      "test_file": "foundation/graphic/graphic_2d/test/unittest/rect_test.cpp",
      "test_suite": "RectTest",
      "uncovered": [
        {
          "line": 42,
          "function": "Rect::IsValid",
          "condition": "width_ > 0 && height_ > 0",
          "false_branch": "when width_ <= 0 OR height_ <= 0",
          "suggested_test": "Create a Rect with zero/invalid dimensions and call IsValid(), assert false",
          "context_code_snippet": "bool Rect::IsValid() const {\n    if (width_ > 0 && height_ > 0) {\n        return true;\n    }\n    return false;\n}"
        }
      ]
    }
  ]
}
```

Limit to files that would give the most coverage gain per written test.
```

---

#### 3. TestWriter (@fixer)

| Aspect | Detail |
|--------|--------|
| **Input** | Analysis for ONE file (source file, test file path, test suite name, uncovered branches list) |
| **Task** | Write HWTEST_F test cases covering each branch |
| **Output** | Confirmation of what was written + which files changed |
| **Isolation** | One subagent per file — runs in parallel |

**Prompt template:**

```
Write test cases for uncovered branches in {source_file}.

Test file: {test_file}
Test suite: {test_suite}
Existing test style follows rs_canvas_node_test.cpp conventions.

Uncovered branches to cover:
{uncovered_json_array}

For each uncovered branch:
1. Read the source code at {source_file} around the branch line
2. Read the existing test file at {test_file}
3. Add a new HWTEST_F test case following this exact pattern:

```cpp
/**
 * @tc.name: <FunctionName><3digit>
 * @tc.desc: Cover: <condition description>
 * @tc.type:FUNC
 */
HWTEST_F(<TestSuite>, <FunctionName><3digit>, TestSize.Level1)
{
    /**
     * @tc.steps: step1. setup
     */
    // Arrange

    /**
     * @tc.steps: step2. trigger
     */
    // Act

    /**
     * @tc.steps: step3. verify
     */
    // Assert
}
```

Conventions (from rs_canvas_node_test.cpp):
- #include "gtest/gtest.h" with quotes
- using namespace testing::ext;
- Namespace styling matches the source file's namespace
- Test case naming: <Action><3-digit>, e.g. Create001, IsValid001, InvalidWidth001
- Use constexpr static for boundary constants
- Each branch variation gets its own 3-digit number
- Next available number: check the last test in the file and increment

If the test file doesn't exist yet, create it at {test_file} and add it to the BUILD.gn sources list (look for BUILD.gn in the test directory).

Return what files were modified and what test cases were added.
```

---

#### 4. CoverageVerifier (@fixer)

| Aspect | Detail |
|--------|--------|
| **Input** | Same as PipelineRunner + previous .info path as baseline |
| **Task** | Re-run pipeline with -b baseline to measure delta |
| **Output** | New metrics + delta from previous run |

**Prompt template:**

```
Re-run the coverage pipeline to verify coverage improvement.

Working directory: {devtest_dir}
Command: cd {devtest_dir} && ./cicd/coverage_pipeline.sh -p {part_name} -d {device_ip_port} -P {product_form} -b {previous_info_path}
Timeout: 3600 seconds

After completion, return ONLY:
1. Did it succeed?
2. New line coverage percentage
3. New branch coverage percentage
4. Delta from baseline (both line and branch)
5. Path to new P6 uncovered report
```

---

## Main Agent Flow

### Part-level: cover entire part

```
1. Parse user request
   ├── part_name (required), e.g. graphic_2d
   ├── [optional] target_file — if user says "提升某个文件", set this
   ├── device_ip:port
   ├── target_coverage (default: 95%)
   ├── product_form (default: rk3568)
   └── ohos_root (resolve from devtest_dir)
```

### File-level: cover a single source file

If the user wants to improve coverage of **one specific file** (e.g. `rect.cpp` in graphic_2d):

- Set `target_file` to the file path relative to OHOS_ROOT
- The pipeline still builds + pushes + runs tests for the **whole part** (P1–P3 are part-level)
- But P6 analysis only reports uncovered branches in **that one file**
- The main agent's flow loop is the same, just focused

File-level is useful when:
- A new file was just added with low coverage
- You want to incrementally improve coverage one file at a time
- The part is large and you want to make focused progress

```
2. Verify prerequisites
   ├── devtest_dir/<ohos_root> exists
   ├── config/user_config.xml has device config (or -d was given)
   ├── all_subsystem_config.json has the part
   └── hdc connected

3. Loop until coverage >= target or no progress after iteration
   ↓
   ┌────────────────────────────────────────────────────────────┐
   │ 3a. PipelineRunner  →  get metrics + report paths          │
   │     (pass -f target_file if file-level)                    │
   │     ↓                                                      │
   │ 3b. CoverageAnalyzer →  get analysis plan                  │
   │     ↓                                                      │
   │ 3c. TestWriter × N  →  all files in parallel               │
   │     (one subagent per file, wait for all)                  │
   │     ↓                                                      │
   │ 3d. CoverageVerifier →  get new metrics + delta            │
   │     ↓                                                      │
   │ 3e. Check: coverage >= target? → break                     │
   │     Check: delta < 0.5% improvement? → warn and break      │
   │     Otherwise → loop                                        │
   └────────────────────────────────────────────────────────────┘

4. Report final summary
   ├── Final coverage metrics
   ├── Total test cases written
   ├── Files modified
   └── Time taken
```

## Important

- Each subagent runs as `task(..., background: true)` so main agent stays responsive
- Only the **main agent** calls subagents — subagents never call other subagents
- Subagent outputs are compact summaries, not full logs
- If `system_part_service.json` is missing, the pipeline pauses for manual intervention — inform user

## Prompt Template (for the main agent to use)

### Part-level
When the user says "提升 <part> 的覆盖率到 X%", load this skill and orchestrate as above.
When the user says "提升 <part> 的覆盖率" without a target, default to 95%.

Example:
```
@skills coverage-iter 提升 graphic_2d 的覆盖率到 95%，设备 192.168.1.100:8710
```

### File-level
When the user says "提升 <part> 中的 <relative_path> 文件的覆盖率":

Example:
```
@skills coverage-iter 提升 graphic_2d 中 foundation/graphic/graphic_2d/src/rect.cpp 的覆盖率
```

The main agent should:
1. Parse the `target_file` from the user message
2. Pass `-f <target_file>` to PipelineRunner and CoverageVerifier  
3. The CoverageAnalyzer and TestWriter naturally focus on the single file since the P6 JSON only contains that file's data
