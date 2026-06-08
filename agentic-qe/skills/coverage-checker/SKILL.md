---
name: "C++ Coverage Checker"
description: "Parses gcov HTML coverage reports for C++ source files, extracts branch coverage data, compares against baseline, and produces structured delta reports organized by function. Use when analyzing .cpp.gcov.html files, checking coverage improvement after adding new tests, or identifying remaining uncovered branches grouped by function for iterative test generation."
---

# C++ Coverage Checker

## Purpose

Parse gcov HTML coverage reports for C++ source files, extract branch coverage data by function, compare against baseline, and produce structured output for iterative test generation. Designed to feed into test-generator for targeted branch coverage improvement.

## Activation

- When analyzing a `.cpp.gcov.html` file after running tests
- When checking if newly added tests improved coverage
- When preparing input for test-generator (grouping uncovered branches by function)
- When comparing coverage between two test runs (delta analysis)

## Input Contract

You will receive:

```jsonc
{
  "gcov_html_path": "path/to/class.cpp.gcov.html",  // gcov HTML 报告路径
  "source_cpp_path": "path/to/class.cpp",            // 对应源文件路径
  "baseline": {                                      // 可选：基线覆盖率数据
    "line_coverage_pct": 45.2,
    "branch_coverage_pct": 32.1,
    "total_branches": 50,
    "covered_branches": 16,
    "uncovered_branches": 34
  }
}
```

## gcov HTML Format Reference

gcov generates HTML with a `<pre class="source">` block. Each line has:
- A **hit count** prefix (number or `#####` for uncovered)
- Line number
- Source code

```html
<pre class="source">
   12  :    int ProcessRefund(double amount) {
   12  :      if (amount <= 0) {
   #####:        return Error::InvalidAmount;    ← ##### means NOT covered
   12  :      }
   12  :      if (amount > max_amount) {
   3   :        return Error::ExceedsLimit;
   12  :      }
   #####:      if (retry_count > MAX_RETRIES) {   ← NOT covered
   #####:        return Error::TooManyRetries;
   #####:      }
   12  :      return OK;
   12  :    }
</pre>
```

**Key marker:** `#####` prefix on a line = branch/line was NOT executed during tests.

## Workflow

### Phase 1: Parse gcov HTML

1. Read the gcov HTML file
2. Locate the `<pre class="source">` block
3. Parse each line to extract:
   - Line number
   - Hit count (number = covered, `#####` = uncovered)
   - Source code text

### Phase 2: Identify Functions and Their Branches

1. Scan source lines for function definitions:
   - Match patterns like `ReturnType FunctionName(params) {`
   - Record function name and start line

2. Within each function, identify branch points:
   - `if` / `else if` / `else` — each clause is a branch
   - `switch` / `case` / `default` — each case is a branch
   - `?:` ternary operator — true/false branches
   - `for` / `while` / `do-while` — loop entry/exit branches
   - `try` / `catch` — exception handling branches
   - Early `return` statements — control flow branches

3. For each branch point, check if the line has `#####` (uncovered) or a number (covered)

### Phase 3: Compute Coverage Summary

Count:
- `total_branches` — all branch points identified
- `covered_branches` — branches with hit count > 0
- `uncovered_branches` — branches with `#####` marker

Calculate percentages:
- `branch_coverage_pct` = (covered_branches / total_branches) × 100
- `line_coverage_pct` = (covered_lines / total_lines) × 100

### Phase 4: Compute Delta (if baseline provided)

If baseline data was provided:
- `branch_coverage_delta` = current branch_coverage_pct - baseline.branch_coverage_pct
- `newly_covered_branches` = branches now covered that were previously uncovered
- `newly_uncovered_branches` = branches now uncovered that were previously covered (regression!)

### Phase 5: Group Uncovered Branches by Function

For each function, collect uncovered branches with:
- Line number
- Description (human-readable: "else branch at line 45: amount < 0")
- Type classification (if_else, switch_case, ternary, loop_condition, exception_path, early_return, other)

This grouping enables test-generator to process one function at a time.

## Output Format

```jsonc
{
  "file": "order_service.cpp",
  "summary": {
    "line_coverage_pct": 67.5,
    "branch_coverage_pct": 45.0,
    "total_branches": 40,
    "covered_branches": 18,
    "uncovered_branches": 22
  },
  "delta": {
    "branch_coverage_delta": 12.9,
    "line_coverage_delta": 22.3,
    "newly_covered_branches": 5,
    "newly_uncovered_branches": 0
  },
  "functions": [
    {
      "name": "CreateOrder",
      "line_range": "30-85",
      "uncovered_branches": [
        {
          "line": 42,
          "description": "if (amount <= 0) — error path for invalid amount",
          "type": "if_else"
        },
        {
          "line": 56,
          "description": "else branch: payment gateway timeout fallback",
          "type": "exception_path"
        }
      ]
    },
    {
      "name": "ProcessRefund",
      "line_range": "87-150",
      "uncovered_branches": [
        {
          "line": 95,
          "description": "if (refund_amount > original_amount) — over-refund guard",
          "type": "if_else"
        },
        {
          "line": 112,
          "description": "default case in switch(status) — unknown status handler",
          "type": "switch_case"
        },
        {
          "line": 134,
          "description": "while (retry_count < MAX_RETRIES) — retry loop condition",
          "type": "loop_condition"
        }
      ]
    },
    {
      "name": "GetOrderStatus",
      "line_range": "152-165",
      "uncovered_branches": []
    }
  ]
}
```

## Delta Calculation Example

```
Baseline: branch_coverage_pct = 32.1%, covered_branches = 16
Current:  branch_coverage_pct = 45.0%, covered_branches = 18

Delta:
  branch_coverage_delta = 45.0 - 32.1 = +12.9
  newly_covered_branches = 18 - 16 = 2 (but need to match specific branches)
  newly_uncovered_branches = 0
```

## Important Constraints

1. **Only analyze .cpp files** — .h files are ignored for coverage analysis
2. **One .gcov.html per .cpp** — the file naming convention is `<filename>.cpp.gcov.html`
3. **Group by function** — always group uncovered branches by their containing function
4. **Skip trivial getters/setters** — single-line getters/setters (e.g., `return member_;`) are low priority; flag them but don't include in top priority list
5. **Flag unreachable branches** — if a branch appears to be dead code, note it explicitly
6. **Regression detection** — if newly_uncovered_branches > 0, this is a REGRESSION and should be flagged prominently

## Anti-Patterns (DO NOT DO)

- ❌ Trying to parse gcov HTML by reading the entire file as a single string — parse line by line
- ❌ Confusing `#####` (uncovered) with `0` (executed 0 times but reachable) — in gcov, both mean uncovered
- ❌ Counting template instantiations as separate functions — group by template definition
- ❌ Including third-party or generated code in coverage analysis
- ❌ Skipping the delta calculation when baseline is provided — this is critical for iterative improvement
