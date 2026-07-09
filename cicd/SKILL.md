# Coverage Iteration Skill

Use when the user wants to improve code coverage of an OpenHarmony part by analyzing an uncovered-branch report and writing new UT test cases.

## Workflow Overview

```
P1–P5  →  P6  →  P7  →  repeat
script     tool    you     (re-run pipeline)
```

- **P1–P5**: Automated by `cicd/coverage_pipeline.sh` (build → push → run → pull → report)
- **P6**: `cicd/extract_uncovered.py` produces a JSON report of uncovered branches
- **P7**: **You read the JSON report, write new test cases** ← your main job
- Repeat: re-run the pipeline to verify coverage improvement, iterate to target

## Prerequisites

Before running the pipeline, verify:

1. **Device configured** in `config/user_config.xml`, or pass `-d ip:port` to the pipeline (which auto-writes it)
2. **Part registered** in `local_coverage/all_subsystem_config.json` — add if missing:
   ```json
   "your_part_name": {
     "name": "your_part_name",
     "path": ["foundation/your_subsystem/your_component"]
   }
   ```
3. **HDC connected**: `hdc -s <ip>:<port> list targets` shows the device

The pipeline will check all three and prompt/interrupt if something is wrong.

## Step-by-step

### 1. Run the pipeline (once, to get report)

```bash
# From <OHOS_ROOT>/test/testfwk/developer_test/
./cicd/coverage_pipeline.sh -p <part_name> -d <device_ip>:8710
```

This produces:
- HTML report: `local_coverage/code_coverage/results/coverage/reports/cxx/html/index.html`
- Lcov info: `local_coverage/code_coverage/results/coverage/reports/cxx/ohos_codeCoverage.info`
- P6 analysis: `reports/coverage_analysis/uncovered_report_<timestamp>.json`

### 2. Read the P6 JSON report

The report is structured like this:

```json
{
  "summary": {
    "line_rate": "72.3%",
    "branch_rate": "65.0%",
    "uncovered_branches": 350,
    "branch_total": 1000,
    "branch_hit": 650
  },
  "files": [
    {
      "file": "foundation/graphic/graphic_2d/src/rect.cpp",
      "uncovered_branches": [
        {
          "line": 42,
          "block": 1,
          "branch": 0,
          "function": "Rect::IsValid",
          "code": "    if (width_ > 0 && height_ > 0) {",
          "context_before": ["bool Rect::IsValid() const {"],
          "context_after": ["      return true;", "    }"]
        }
      ],
      "uncovered_line_count": 12
    }
  ],
  "baseline_delta": {
    "line_delta_pct": "+5.2%",
    "branch_delta_pct": "+3.8%",
    "uncovered_branches_delta": -42
  }
}
```

### 3. Prioritize files

Sort `files` by `uncovered_line_count` descending. Start with the file that has the most uncovered lines — it gives the biggest coverage gain per effort.

### 4. For each uncovered branch

1. **Find the source file** — path is relative to `OHOS_ROOT`
2. **Understand the logic** — read enough of the function to understand what the branch checks
3. **Locate the existing test file** — look for `<function>_test.cpp` or `<subcomponent>_test.cpp` in the test directory of that part
4. **Write a test case** following this exact pattern:

```cpp
/**
 * @tc.name: <Action><3digit>
 * @tc.desc: Cover <condition description>
 * @tc.type:FUNC
 */
HWTEST_F(<SuiteName>, <Action><3digit>, TestSize.Level1)
{
    /**
     * @tc.steps: step1. <setup>
     */
    // Arrange: create objects, set up state
    auto node = RSCanvasNode::Create();
    ASSERT_NE(node, nullptr);

    /**
     * @tc.steps: step2. <trigger condition>
     */
    // Act: call the function that triggers the uncovered branch

    /**
     * @tc.steps: step3. <verify>
     */
    // Assert: verify the expected outcome
    EXPECT_TRUE(...);
    EXPECT_EQ(...);
}
```

**Naming conventions** (from `rs_canvas_node_test.cpp`):
- Test suite class: `<Component><Type>Test` (PascalCase, e.g. `RSCanvasNodeTest`)
- Test case name: `<Action><3-digit>` (e.g. `Create001`, `SetandGetBounds001`, `LifeCycle001`)
- Test file: `<function>_test.cpp` (snake_case)
- Each variant (edge case) gets its own `NNN` number
- Use `constexpr static float` constants for boundary values

**Common annotations** (consistent with rs_canvas_node_test.cpp):
```cpp
/**
 * @tc.name: <TestName>
 * @tc.desc:
 * @tc.type:FUNC
 */
```

### 5. Update BUILD.gn

If you created a new test file, add it to the `sources` list in the nearest `BUILD.gn`:

```gn
ohos_unittest("<SuiteName>") {
  ...
  sources = [
    "existing_test.cpp",
    "your_new_test.cpp",    # <-- add
  ]
}
```

### 6. Iterate

After writing tests, re-run the pipeline:

```bash
./cicd/coverage_pipeline.sh -p <part> -d <ip>:8710 -b <prev_info_file>
```

The `-b` flag compares against the previous `.info` file so you can see the delta.

Repeat until line coverage reaches the target (default: 95%).

## Constraints & Gotchas

- **Only modify files under the target part's source tree**, not in `testfwk_developer_test` itself
- **C++ test files** must use `HWTEST_F` (not `HWTEST`, `HWMTEST_F`, or `HWTEST_P`) for fixtures; `HWTEST` for stateless
- **`@tc.require`** is optional in some parts (e.g. graphic) — check existing tests in the same directory for the convention. rs_canvas_node_test.cpp omits it.
- **Use `#include "gtest/gtest.h"`** with quotes, matching the project style
- If `system_part_service.json` is missing, the pipeline pauses and asks the user to manually pull `.gcda` files
- Build is incremental: only recompiles changed files, so iterations are fast
