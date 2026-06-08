# Sprint 1: test-generator + coverage-checker 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 构建 C++ UT Builder 系统的两个核心 Skill——test-generator（gtest/gmock 测试代码生成）和 coverage-checker（gcov.html 解析 + 覆盖率 delta 分析），打通从源码到测试到覆盖率分析的关键通路。

**Architecture:** 两个独立的 Skill，各司其职。test-generator 输入 .h/.cpp 源码 + 未覆盖分支列表，输出 gtest/gmock 测试代码。coverage-checker 输入 .cpp.gcov.html + 基线覆盖率数据，输出结构化覆盖率 delta。两者通过 JSON 数据契约关联，可独立测试。

**Tech Stack:** C++ (gtest/gmock 1.14+), gcov HTML 报告解析, YAML frontmatter (Skill 规范), CMake 构建

**Spec:** [docs/superpowers/specs/2026-06-09-ut-builder-system-design.md](../specs/2026-06-09-ut-builder-system-design.md)

---

## 文件结构总览

```
.claude/
├── skills/
│   ├── test-generator/           ← 新建：C++ gtest/gmock 测试生成
│   │   ├── SKILL.md              # Skill 定义（YAML frontmatter + Markdown body）
│   │   └── schemas/
│   │       └── output.json       # JSON Schema：输出校验
│   └── coverage-checker/         ← 新建：gcov.html 解析 + delta 分析
│       ├── SKILL.md              # Skill 定义
│       └── schemas/
│           └── output.json       # JSON Schema：输出校验
└── agents/
    └── testing/
        └── ut-builder.md         ← 后续 Sprint：编排上述 Skill 的 Agent prompt

agentic-qe/
├── 01-test-builder.md            ← 现有：参考模板（不改）
└── 03-coverage-analyst.md        ← 现有：参考模板（不改）
```

---

## Task 1: test-generator Skill — 目录结构与 YAML 前端

**Files:**
- Create: `.claude/skills/test-generator/SKILL.md`
- Create: `.claude/skills/test-generator/schemas/output.json`

- [ ] **Step 1: 创建目录结构**

```bash
mkdir -p .claude/skills/test-generator/schemas
```

- [ ] **Step 2: 编写 SKILL.md 的 YAML 前端**

文件：`.claude/skills/test-generator/SKILL.md`

```markdown
---
name: "C++ Test Generator"
description: "Generates gtest/gmock unit tests for C++ source files with London school mock strategy. Analyzes C++ headers and sources to identify methods, branches, dependencies, and error paths, then generates compilable test code targeting specific uncovered branches. Use when writing unit tests for C++ code, filling coverage gaps, or iterating toward 100% branch coverage."
---
```

- [ ] **Step 3: 创建 JSON Schema**

文件：`.claude/skills/test-generator/schemas/output.json`

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "TestGeneratorOutput",
  "type": "object",
  "required": ["generated_tests", "coverage_expectation"],
  "properties": {
    "generated_tests": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["file", "content", "test_count", "targeted_branches"],
        "properties": {
          "file": { "type": "string", "description": "测试文件名" },
          "content": { "type": "string", "description": "完整测试代码" },
          "test_count": { "type": "integer", "minimum": 1 },
          "targeted_branches": {
            "type": "array",
            "items": { "type": "string" },
            "description": "目标覆盖的分支ID列表"
          },
          "test_cases": {
            "type": "array",
            "items": {
              "type": "object",
              "required": ["name", "target_branch"],
              "properties": {
                "name": { "type": "string" },
                "target_branch": { "type": "string" },
                "expected_behavior": { "type": "string" }
              }
            }
          }
        }
      }
    },
    "coverage_expectation": {
      "type": "object",
      "required": ["expected_new_branch_coverage", "branches_still_uncovered"],
      "properties": {
        "expected_new_branch_coverage": { "type": "number" },
        "expected_new_line_coverage": { "type": "number" },
        "branches_still_uncovered": {
          "type": "array",
          "items": { "type": "string" }
        },
        "notes": { "type": "string" }
      }
    },
    "source_modification_suggestions": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["file", "line", "reason", "suggestion"],
        "properties": {
          "file": { "type": "string" },
          "line": { "type": "integer" },
          "reason": { "type": "string" },
          "suggestion": { "type": "string" }
        }
      }
    }
  }
}
```

- [ ] **Step 4: Commit**

```bash
git add .claude/skills/test-generator/
git commit -m "feat: add test-generator skill directory structure and output schema"
```

---

## Task 2: test-generator Skill — Markdown Body（工作流定义）

**Files:**
- Modify: `.claude/skills/test-generator/SKILL.md`

- [ ] **Step 1: 追加 Skill 的完整工作流到 SKILL.md**

在 YAML frontmatter 之后追加以下内容（追加到已有 SKILL.md 文件的 `---` 闭合之后）：

```markdown
# C++ Test Generator

## Purpose

Generate gtest/gmock unit tests for C++ source files, targeting specific uncovered branches. Designed for iterative coverage improvement — each invocation processes ONE function's uncovered branches to stay within context window limits.

## Activation

- When generating unit tests for C++ code with gtest/gmock
- When filling specific uncovered branches identified by coverage-checker
- When iterating toward 100% branch coverage
- When converting branch gap data into concrete test cases

## Input Contract

You will receive a JSON input with this structure:

```jsonc
{
  "source": {
    "header": "path/to/class.h",        // 头文件路径
    "cpp": "path/to/class.cpp"          // 源文件路径
  },
  "target": {
    "function": "ProcessRefund",         // 目标函数名
    "uncovered_branches": [              // 该函数未覆盖的分支
      {
        "line": 45,
        "description": "else branch: amount < 0",
        "type": "error_path"
      },
      {
        "line": 67,
        "description": "if (retry_count > MAX_RETRIES)",
        "type": "boundary"
      }
    ]
  },
  "context": {
    "existing_tests": [],                // 已有测试文件路径（可选）
    "mock_strategy": "london",           // london | chicago | hybrid
    "test_file_path": "tests/unit/test_class.cpp"  // 输出路径
  },
  "iteration": {
    "round": 2,
    "max_rounds": 3                     // 该函数最多迭代 3 轮
  }
}
```

## Workflow

### Phase 1: Read and Analyze Source

1. Read the header file to understand:
   - Class declaration and public interface
   - Method signatures, parameter types, return types
   - Include dependencies and forward declarations

2. Read the source file to understand:
   - Method implementations
   - Internal helper functions
   - Dependency injection points (constructor params, setter methods)

### Phase 2: Analyze Target Function

For the target function, extract:
- All branch conditions (if/else, switch/case, ternary, exception paths)
- External dependencies called within the function
- Input parameter constraints and edge cases
- Error handling paths

### Phase 3: Select Test Design Technique

Based on the input type of the function:

| Input Type | Technique | gtest Feature |
|-----------|-----------|---------------|
| Numeric range (age, count, amount) | BVA + EP | TEST_P (parameterized) |
| Multi-condition (if a&&b\|\|c) | Decision Table | TEST_F with sub-cases |
| State machine | State Transition | TEST_F with sequence |
| Multi-parameter combinations | Pairwise | TEST_P with ::testing::Combine |
| Error paths | Negative Testing | TEST_F with EXPECT_THROW |
| Pure computation | Chicago (real objects) | TEST (no fixture needed) |
| External dependency heavy | London (mocks) | TEST_F with MOCK_METHOD |

### Phase 4: Generate Test Code

Generate compilable gtest/gmock test code following these rules:

**Naming Convention:** `TEST_F(ClassNameTest, ShouldXxxWhenYyy)`

**Fixture Pattern:**
```cpp
class ClassNameTest : public ::testing::Test {
protected:
  void SetUp() override {
    // Create mocks
    // Create test target
  }
  void TearDown() override {
    // Clean up if needed
  }
  // Mock objects as members
  // Test target as member
};
```

**Mock Pattern (London school):**
```cpp
class MockDependency : public IDependency {
public:
  MOCK_METHOD(ReturnType, MethodName, (ParamType param), (override));
};
```

**Test Case Pattern:**
```cpp
TEST_F(ClassNameTest, ShouldReturnErrorWhenAmountIsNegative) {
  // Arrange
  double negativeAmount = -1.0;

  // Act
  auto result = service_->ProcessRefund(negativeAmount);

  // Assert
  EXPECT_FALSE(result.ok());
  EXPECT_EQ(result.error_code(), ErrorCode::InvalidAmount);
}
```

**Critical Rules:**
- Every test MUST have at least one meaningful assertion
- NO `EXPECT_TRUE(true)` — this is a placeholder, not a test
- Use `EXPECT_CALL` to verify mock interactions
- External dependencies (DB, network, file I/O, external services) MUST be mocked
- Pure computation functions (no side effects, no external deps) use real objects (Chicago)
- Private methods: expose via `friend` declaration in test, or test through public API
- For parameterized tests, use `INSTANTIATE_TEST_SUITE_P`

**Include Guard:**
```cpp
#include <gtest/gtest.h>
#include <gmock/gmock.h>
#include "path/to/header.h"

using ::testing::_;
using ::testing::Return;
using ::testing::NiceMock;
using ::testing::StrictMock;
```

### Phase 5: Output

Output MUST include:

1. **Test code** — Complete, compilable test code as a string in the `content` field
2. **Test metadata** — test_count, targeted_branches, test_cases array
3. **Coverage expectation** — expected coverage after these tests are added
4. **Source modification suggestions** — if any branches appear unreachable (dead code, defensive checks that can never trigger)

## Output Format

```jsonc
{
  "generated_tests": [
    {
      "file": "tests/unit/test_order_service.cpp",
      "content": "// Full compilable test code here...",
      "test_count": 3,
      "targeted_branches": [
        "order_service.cpp:45 - else branch (amount < 0)",
        "order_service.cpp:67 - if (retry_count > MAX_RETRIES)",
        "order_service.cpp:89 - default case in switch"
      ],
      "test_cases": [
        {
          "name": "ShouldReturnErrorWhenAmountIsNegative",
          "target_branch": "order_service.cpp:45 - else branch (amount < 0)",
          "expected_behavior": "Returns InvalidAmount error code for negative amount input"
        },
        {
          "name": "ShouldRetryWhenRetryCountBelowMax",
          "target_branch": "order_service.cpp:67 - if (retry_count > MAX_RETRIES)",
          "expected_behavior": "Executes retry logic when retry_count equals MAX_RETRIES"
        },
        {
          "name": "ShouldHandleUnknownOrderStatus",
          "target_branch": "order_service.cpp:89 - default case in switch",
          "expected_behavior": "Returns UnknownStatus error for unhandled enum values"
        }
      ]
    }
  ],
  "coverage_expectation": {
    "expected_new_branch_coverage": 78.5,
    "expected_new_line_coverage": 85.0,
    "branches_still_uncovered": [
      "order_service.cpp:147 - concurrent stock depletion (needs integration test)",
      "order_service.cpp:201 - unreachable: null check after dereference"
    ],
    "notes": "Branch at line 201 appears unreachable — pointer is dereferenced before null check at line 198"
  },
  "source_modification_suggestions": [
    {
      "file": "order_service.cpp",
      "line": 201,
      "reason": "Dead code: null check on ptr after it was already dereferenced at line 198. This branch can never be reached.",
      "suggestion": "Either remove the redundant null check, or move the null check before the first dereference at line 198"
    }
  ]
}
```

## Important Constraints

1. **Single function only** — process exactly one function per invocation to stay within context limits
2. **Incremental generation** — generate ONLY the new tests for uncovered branches, not all tests for the function
3. **Do NOT modify existing tests** — append new test cases, don't touch existing ones
4. **Compilability is mandatory** — every `#include` must correspond to a real header file
5. **No imaginary APIs** — only use methods/functions that exist in the provided headers
6. **CMakeLists.txt** — if the test file is new, also output the `add_executable` / `target_link_libraries` snippet

## Anti-Patterns (DO NOT DO)

- ❌ Generating tests for header-only classes (.h files without .cpp) — we only test .cpp files
- ❌ `EXPECT_TRUE(true)` or `ASSERT_TRUE(true)` — these are placeholder assertions
- ❌ Testing private methods directly — test through public API or use `friend` class
- ❌ Mocking the class under test — mock only external dependencies
- ❌ Hardcoding file paths in test code — use relative paths or test fixtures
- ❌ Assuming third-party libraries exist — only use gtest/gmock standard API
```

- [ ] **Step 2: Commit**

```bash
git add .claude/skills/test-generator/SKILL.md
git commit -m "feat: add test-generator skill workflow and prompt body"
```

---

## Task 3: coverage-checker Skill — 目录结构与 YAML 前端

**Files:**
- Create: `.claude/skills/coverage-checker/SKILL.md`
- Create: `.claude/skills/coverage-checker/schemas/output.json`

- [ ] **Step 1: 创建目录结构**

```bash
mkdir -p .claude/skills/coverage-checker/schemas
```

- [ ] **Step 2: 编写 SKILL.md 的 YAML 前端**

文件：`.claude/skills/coverage-checker/SKILL.md`

```markdown
---
name: "C++ Coverage Checker"
description: "Parses gcov HTML coverage reports for C++ source files, extracts branch coverage data, compares against baseline, and produces structured delta reports organized by function. Use when analyzing .cpp.gcov.html files, checking coverage improvement after adding new tests, or identifying remaining uncovered branches grouped by function for iterative test generation."
---
```

- [ ] **Step 3: 创建 JSON Schema**

文件：`.claude/skills/coverage-checker/schemas/output.json`

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "CoverageCheckerOutput",
  "type": "object",
  "required": ["file", "summary", "functions"],
  "properties": {
    "file": { "type": "string", "description": "源文件名" },
    "summary": {
      "type": "object",
      "required": ["line_coverage_pct", "branch_coverage_pct", "total_branches", "covered_branches", "uncovered_branches"],
      "properties": {
        "line_coverage_pct": { "type": "number" },
        "branch_coverage_pct": { "type": "number" },
        "total_branches": { "type": "integer" },
        "covered_branches": { "type": "integer" },
        "uncovered_branches": { "type": "integer" }
      }
    },
    "delta": {
      "type": "object",
      "properties": {
        "branch_coverage_delta": { "type": "number" },
        "line_coverage_delta": { "type": "number" },
        "newly_covered_branches": { "type": "integer" },
        "newly_uncovered_branches": { "type": "integer" }
      }
    },
    "functions": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["name", "line_range", "uncovered_branches"],
        "properties": {
          "name": { "type": "string" },
          "line_range": { "type": "string", "description": "e.g. '45-120'" },
          "uncovered_branches": {
            "type": "array",
            "items": {
              "type": "object",
              "required": ["line", "description", "type"],
              "properties": {
                "line": { "type": "integer" },
                "description": { "type": "string" },
                "type": {
                  "type": "string",
                  "enum": ["if_else", "switch_case", "ternary", "loop_condition", "exception_path", "early_return", "other"]
                }
              }
            }
          }
        }
      }
    }
  }
}
```

- [ ] **Step 4: Commit**

```bash
git add .claude/skills/coverage-checker/
git commit -m "feat: add coverage-checker skill directory structure and output schema"
```

---

## Task 4: coverage-checker Skill — Markdown Body（工作流定义）

**Files:**
- Modify: `.claude/skills/coverage-checker/SKILL.md`

- [ ] **Step 1: 追加 Skill 的完整工作流到 SKILL.md**

在 YAML frontmatter 之后追加：

```markdown
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
```

- [ ] **Step 2: Commit**

```bash
git add .claude/skills/coverage-checker/SKILL.md
git commit -m "feat: add coverage-checker skill workflow and prompt body"
```

---

## Task 5: 验证 — 创建示例数据测试 coverage-checker 解析逻辑

**Files:**
- Create: `tests/fixtures/sample.cpp.gcov.html`
- Create: `tests/fixtures/sample.cpp`

- [ ] **Step 1: 创建示例 gcov HTML 文件**

文件：`tests/fixtures/sample.cpp.gcov.html`

```html
<!DOCTYPE html>
<html>
<head>
  <title>gcov - sample.cpp</title>
</head>
<body>
  <pre class="source">
    10  : #include "sample.h"
    10  : 
    10  : int Calculator::Add(int a, int b) {
    10  :   return a + b;
    10  : }
    10  : 
    10  : int Calculator::Divide(int a, int b) {
    10  :   if (b == 0) {
#####  :     return -1;  // error: division by zero
    10  :   }
    8   :   if (a < 0) {
    2   :     return -2;  // negative numerator
    8   :   }
#####  :   if (a > 1000) {
#####  :     return -3;  // overflow guard
#####  :   }
    6   :   return a / b;
    10  : }
    10  : 
    10  : bool Calculator::IsPrime(int n) {
    10  :   if (n <= 1) {
    3   :     return false;
    10  :   }
    7   :   if (n == 2) {
    1   :     return true;
    7   :   }
    6   :   if (n % 2 == 0) {
    3   :     return false;
    6   :   }
#####  :   for (int i = 3; i * i <= n; i += 2) {
#####  :     if (n % i == 0) {
#####  :       return false;
#####  :     }
#####  :   }
    3   :   return true;
    10  : }
  </pre>
</body>
</html>
```

- [ ] **Step 2: 创建对应源文件**

文件：`tests/fixtures/sample.cpp`

```cpp
#include "sample.h"

int Calculator::Add(int a, int b) {
  return a + b;
}

int Calculator::Divide(int a, int b) {
  if (b == 0) {
    return -1;  // error: division by zero
  }
  if (a < 0) {
    return -2;  // negative numerator
  }
  if (a > 1000) {
    return -3;  // overflow guard
  }
  return a / b;
}

bool Calculator::IsPrime(int n) {
  if (n <= 1) {
    return false;
  }
  if (n == 2) {
    return true;
  }
  if (n % 2 == 0) {
    return false;
  }
  for (int i = 3; i * i <= n; i += 2) {
    if (n % i == 0) {
      return false;
    }
  }
  return true;
}
```

- [ ] **Step 3: 创建预期输出**

文件：`tests/fixtures/expected-coverage-output.json`

```json
{
  "file": "sample.cpp",
  "summary": {
    "line_coverage_pct": 75.0,
    "branch_coverage_pct": 37.5,
    "total_branches": 8,
    "covered_branches": 3,
    "uncovered_branches": 5
  },
  "functions": [
    {
      "name": "Add",
      "line_range": "5-7",
      "uncovered_branches": []
    },
    {
      "name": "Divide",
      "line_range": "9-22",
      "uncovered_branches": [
        {
          "line": 10,
          "description": "if (b == 0) — division by zero error path",
          "type": "if_else"
        },
        {
          "line": 18,
          "description": "if (a > 1000) — overflow guard",
          "type": "if_else"
        }
      ]
    },
    {
      "name": "IsPrime",
      "line_range": "24-41",
      "uncovered_branches": [
        {
          "line": 35,
          "description": "for loop — loop body never executed",
          "type": "loop_condition"
        },
        {
          "line": 36,
          "description": "if (n % i == 0) — divisor check inside loop",
          "type": "if_else"
        }
      ]
    }
  ]
}
```

- [ ] **Step 4: 创建快速验证脚本**

文件：`tests/fixtures/verify-coverage-parser.sh`

```bash
#!/bin/bash
# 验证 coverage-checker 能正确解析 gcov HTML
# 用法: 将 sample.cpp.gcov.html 喂给 coverage-checker skill，
#       对比输出与 expected-coverage-output.json

echo "=== Coverage Checker Verification ==="
echo ""
echo "Input:  tests/fixtures/sample.cpp.gcov.html"
echo "Expect: branch_coverage_pct = 37.5% (3/8 branches covered)"
echo "        Divide(): 2 uncovered branches (line 10, line 18)"
echo "        IsPrime(): 2 uncovered branches (line 35, line 36)"
echo "        Add(): 0 uncovered branches"
echo ""
echo "To verify: invoke the coverage-checker skill with the gcov HTML file"
echo "and compare the JSON output against expected-coverage-output.json"
```

- [ ] **Step 5: Commit**

```bash
git add tests/fixtures/
git commit -m "feat: add sample gcov HTML and expected output for coverage-checker validation"
```

---

## Task 6: 验证 — 创建 test-generator 的示例输入/输出

**Files:**
- Create: `tests/fixtures/test-generator-input.json`
- Create: `tests/fixtures/test-generator-expected-output.json`

- [ ] **Step 1: 创建 test-generator 示例输入**

文件：`tests/fixtures/test-generator-input.json`

```json
{
  "source": {
    "header": "tests/fixtures/sample.h",
    "cpp": "tests/fixtures/sample.cpp"
  },
  "target": {
    "function": "Divide",
    "uncovered_branches": [
      {
        "line": 10,
        "description": "if (b == 0) — division by zero error path",
        "type": "error_path"
      },
      {
        "line": 18,
        "description": "if (a > 1000) — overflow guard",
        "type": "boundary"
      }
    ]
  },
  "context": {
    "existing_tests": [],
    "mock_strategy": "chicago",
    "test_file_path": "tests/unit/test_sample.cpp"
  },
  "iteration": {
    "round": 1,
    "max_rounds": 3
  }
}
```

- [ ] **Step 2: 创建对应的头文件**

文件：`tests/fixtures/sample.h`

```cpp
#pragma once

class Calculator {
public:
  int Add(int a, int b);
  int Divide(int a, int b);
  bool IsPrime(int n);
};
```

- [ ] **Step 3: 创建 test-generator 预期输出**

文件：`tests/fixtures/test-generator-expected-output.json`

```json
{
  "generated_tests": [
    {
      "file": "tests/unit/test_sample.cpp",
      "test_count": 2,
      "targeted_branches": [
        "sample.cpp:10 - if (b == 0)",
        "sample.cpp:18 - if (a > 1000)"
      ],
      "test_cases": [
        {
          "name": "ShouldReturnErrorWhenDivisorIsZero",
          "target_branch": "sample.cpp:10 - if (b == 0)",
          "expected_behavior": "Returns -1 for division by zero"
        },
        {
          "name": "ShouldReturnErrorWhenNumeratorExceedsLimit",
          "target_branch": "sample.cpp:18 - if (a > 1000)",
          "expected_behavior": "Returns -3 for overflow guard"
        }
      ]
    }
  ],
  "coverage_expectation": {
    "expected_new_branch_coverage": 62.5,
    "expected_new_line_coverage": 85.0,
    "branches_still_uncovered": [
      "sample.cpp:35 - for loop body (IsPrime)",
      "sample.cpp:36 - if (n % i == 0) inside loop (IsPrime)"
    ],
    "notes": "Divide function should reach 100% branch coverage. IsPrime loop branches need separate iteration."
  },
  "source_modification_suggestions": []
}
```

- [ ] **Step 4: Commit**

```bash
git add tests/fixtures/
git commit -m "feat: add test-generator sample input/output for validation"
```

---

## Task 7: 端到端验证 — 手动跑通 test-generator → coverage-checker 通路

**Files:**
- Create: `tests/fixtures/e2e-verification-guide.md`

- [ ] **Step 1: 编写端到端验证指南**

文件：`tests/fixtures/e2e-verification-guide.md`

```markdown
# Sprint 1 端到端验证指南

## 验证目标

确认 test-generator + coverage-checker 两个 Skill 能正确协作：

```
coverage-checker (分析基线覆盖率)
    → 输出: 按函数分组的未覆盖分支
    → test-generator (针对 Divide 函数生成测试)
    → 输出: 可编译的 gtest 测试代码
    → coverage-checker (重新分析覆盖率)
    → 输出: delta 报告，确认覆盖率提升
```

## 验证步骤

### Step 1: 模拟初始覆盖率分析

将 `tests/fixtures/sample.cpp.gcov.html` 作为输入，调用 coverage-checker skill，
确认输出与 `tests/fixtures/expected-coverage-output.json` 一致。

验证点:
- [ ] branch_coverage_pct = 37.5%
- [ ] Divide() 有 2 个未覆盖分支 (line 10, line 18)
- [ ] IsPrime() 有 2 个未覆盖分支 (line 35, line 36)
- [ ] Add() 有 0 个未覆盖分支

### Step 2: 调用 test-generator 生成测试

以 coverage-checker 输出中 Divide() 的未覆盖分支作为输入，
调用 test-generator skill。

验证点:
- [ ] 生成了 2 个测试用例（对应 2 个未覆盖分支）
- [ ] 测试代码包含 `ShouldReturnErrorWhenDivisorIsZero`
- [ ] 测试代码包含 `ShouldReturnErrorWhenNumeratorExceedsLimit`
- [ ] 测试代码使用 gtest 标准 API（TEST_F, EXPECT_EQ 等）
- [ ] 没有 `EXPECT_TRUE(true)` 空断言

### Step 3: 模拟编译验证

将 test-generator 生成的测试代码保存到 `tests/unit/test_sample.cpp`，
与 `tests/fixtures/sample.cpp` 一起编译。

```bash
# 在 Linux 编译服务器上:
clang++ -std=c++17 \
  -fprofile-instr-generate -fcoverage-mapping \
  tests/fixtures/sample.cpp \
  tests/unit/test_sample.cpp \
  -lgtest -lgtest_main -lgmock -pthread \
  -o build/test_sample

# 运行测试
./build/test_sample

# 生成覆盖率报告
llvm-profdata merge -sparse default.profraw -o default.profdata
llvm-cov show ./build/test_sample -instr-profile=default.profdata \
  -format=html -output-dir=coverage_html \
  tests/fixtures/sample.cpp
```

验证点:
- [ ] 编译成功（0 errors, 0 warnings）
- [ ] 新增的 2 个测试通过
- [ ] 生成新的 `sample.cpp.gcov.html`

### Step 4: 重新分析覆盖率

将新的 `sample.cpp.gcov.html` + 基线数据（Step 1 的输出）作为输入，
调用 coverage-checker skill。

验证点:
- [ ] branch_coverage_delta > 0 (覆盖率提升)
- [ ] Divide() 的未覆盖分支 = 0 (全部覆盖)
- [ ] IsPrime() 的未覆盖分支仍然存在 (等待下一轮迭代)

### Step 5: 模拟第二轮迭代

以 Step 4 输出中 IsPrime() 的未覆盖分支作为输入，
调用 test-generator skill，针对 IsPrime 函数生成测试。

验证点:
- [ ] 生成针对 for 循环的测试用例（需要输入 ≥ 9 的奇数才能进入循环）
- [ ] 生成针对循环内 if 分支的测试用例（需要输入合数，如 9）
```

- [ ] **Step 2: Commit**

```bash
git add tests/fixtures/e2e-verification-guide.md
git commit -m "docs: add sprint 1 end-to-end verification guide"
```

---

## 自检清单

### 1. Spec Coverage Check

| Spec 要求 | 对应 Task |
|-----------|----------|
| test-generator: 输入契约 (source + target + context + iteration) | Task 2 (Workflow 定义) |
| test-generator: 输出契约 (generated_tests + coverage_expectation + source_modification_suggestions) | Task 1 (JSON Schema) + Task 2 |
| test-generator: London 学派 mock 外部依赖 | Task 2 (Phase 4 Mock Pattern) |
| test-generator: 按函数迭代，一次只处理一个函数 | Task 2 (Important Constraints #1) |
| test-generator: 增量生成，不重复已覆盖分支 | Task 2 (Important Constraints #2) |
| coverage-checker: 解析 gcov.html (##### 标记) | Task 4 (gcov HTML Format Reference) |
| coverage-checker: 按函数分组未覆盖分支 | Task 4 (Phase 5) |
| coverage-checker: delta 计算 (对比基线) | Task 4 (Phase 4 + Delta Calculation Example) |
| coverage-checker: 只分析 .cpp 文件 | Task 4 (Important Constraints #1) |
| 数据契约 JSON Schema 校验 | Task 1 + Task 3 (schemas/output.json) |
| 示例数据验证 | Task 5 + Task 6 |
| 端到端验证 | Task 7 |

### 2. Placeholder Scan

- ✅ 所有 Task 都有完整代码和文件路径
- ✅ 无 "TBD"、"TODO"、"implement later"
- ✅ 所有 JSON 示例都是完整可用的
- ✅ 所有 bash 命令都是可执行的

### 3. Type Consistency

- ✅ 输入契约字段在 test-generator SKILL.md (Task 2) 和 test-generator-input.json (Task 6) 中一致
- ✅ 输出契约字段在 JSON Schema (Task 1/3) 和 SKILL.md body (Task 2/4) 中一致
- ✅ `uncovered_branches` 类型在 coverage-checker 输出和 test-generator 输入间一致
- ✅ 函数名使用一致的命名（PascalCase for C++ functions）

---

## 执行说明

实现这些 Skill 时，注意：

1. **Skill 文件位置必须正确** — `.claude/skills/<skill-name>/SKILL.md`，子目录命名用 kebab-case
2. **YAML frontmatter 必须在最顶部** — `---` 开头和结尾，`name` 和 `description` 是必填字段
3. **SKILL.md 是 Claude Code 自动发现的** — 不需要手动注册，重启 Claude Code 后自动加载
4. **JSON Schema 用于输出校验** — 当 Skill 被调用时，输出会被 schema 校验
5. **先验证 coverage-checker** — 因为它有明确的输入（gcov.html）和可预期的输出，容易验证
6. **再验证 test-generator** — 它的输出质量依赖于 prompt 调优，需要反复测试
```

- [ ] **Step 3: 验证文件创建成功**

```bash
ls -la .claude/skills/test-generator/SKILL.md
ls -la .claude/skills/coverage-checker/SKILL.md
ls -la tests/fixtures/
```

- [ ] **Step 4: Commit all remaining files**

```bash
git add -A
git status
```

