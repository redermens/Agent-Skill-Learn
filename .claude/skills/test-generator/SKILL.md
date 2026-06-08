---
name: "C++ Test Generator"
description: "Generates gtest/gmock unit tests for C++ source files with London school mock strategy. Analyzes C++ headers and sources to identify methods, branches, dependencies, and error paths, then generates compilable test code targeting specific uncovered branches. Use when writing unit tests for C++ code, filling coverage gaps, or iterating toward 100% branch coverage."
---

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
