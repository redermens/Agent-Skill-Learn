# C++ UT Builder 系统设计文档

> 生成日期: 2026-06-09 | 状态: Draft | 版本: v1.0

---

## 一、项目目标

构建一个 C++ 单元测试自动生成系统，最终目标：**源码分支覆盖率 100%**。如果存在无法覆盖的分支，输出源码修改建议。

## 二、工具链与环境

| 组件 | 环境 | 说明 |
|------|------|------|
| 编译器 | Linux 服务器 (clang) | 编译时加 coverage 选项注入 lcov 兼容数据 |
| CI/CD | Jenkins | 触发编译、调度测试任务 |
| 测试执行 | 内部 Web 平台 | 上传 lz4 压缩包 → 获取测试链接 → 查看进度/结果 |
| 覆盖率报告 | gcov.html (每个 .cpp 对应一个 .cpp.gcov.html) | 源码 + 行级分支覆盖信息 |
| 跨设备通信 | SSH | PC ↔ Linux 服务器，文件传输 |
| 测试框架 | gtest/gmock 1.14+ | London 学派 mock 外部依赖 |
| 构建系统 | CMake | — |

### 关键约束

- **覆盖率只针对 .cpp 文件**（.h 文件中无函数实现）
- **每个 .cpp 对应一个 .gcov.html**（如 `demo.cpp` → `demo.cpp.gcov.html`）
- **覆盖率报告优先用文本格式**（lcov.info / JSON），避免直接喂 HTML（token 消耗大一个数量级）
- **所有测试生成后必须真跑验证**，不信任 AI 自述"测试已通过"

## 三、整体架构

```
┌─────────────────────────────────────────────────────────────────────┐
│              UT Builder Agent 内部架构                                │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌─────────────────┐                                                │
│  │  UT Builder      │  ← 一个 Agent 实例 = 处理 一个 .cpp 文件        │
│  │  (Agent Prompt)  │                                                │
│  └───────┬─────────┘                                                │
│          │                                                           │
│          ├──► Skill: gap-analyzer      ← 解析 .gcov.html，按函数分组   │
│          │    输入: demo.cpp + demo.cpp.gcov.html                     │
│          │    输出: [{ function: "foo", uncovered_branches: [...] },  │
│          │           { function: "bar", uncovered_branches: [...] }]  │
│          │                                                           │
│          ├──► Skill: test-generator    ← 针对单个函数的未覆盖分支生成   │
│          │    输入: 源码 + 一个 function 的 uncovered_branches         │
│          │    输出: 该函数的补充测试代码 (增量，非全量)                  │
│          │    策略: London 学派 mock 外部依赖                          │
│          │                                                           │
│          ├──► Skill: build-verifier    ← SSH → Linux → clang 编译     │
│          │    输入: 补充测试代码 + CMakeLists.txt 片段                  │
│          │    输出: 编译成功/失败 + 错误信息                            │
│          │                                                           │
│          └──► Skill: coverage-checker  ← 解析新 .gcov.html，对比基线   │
│               输入: 新 demo.cpp.gcov.html + 基线数据                   │
│               输出: { new_coverage_pct, still_uncovered: [...],       │
│                       delta: +X% }                                   │
│                                                                      │
│  迭代策略:                                                            │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │  Round 0: gap-analyzer → 全部未覆盖函数列表                    │   │
│  │  Round 1: test-generator(函数A) → build-verifier →            │   │
│  │            coverage-checker → 函数A 覆盖 ✓                    │   │
│  │  Round 2: test-generator(函数B) → build-verifier →            │   │
│  │            coverage-checker → 函数B 覆盖 ✓                    │   │
│  │  ...                                                          │   │
│  │  Round N: 全部函数覆盖 → 输出最终报告                           │   │
│  │                                                               │   │
│  │  若某函数迭代 3 轮仍无法 100%:                                  │   │
│  │    → 标记为 "unreachable"，输出 source_modification_suggestions │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

## 四、4 个 Skill 职责边界

| Skill | 职责 | 输入 | 输出 |
|-------|------|------|------|
| **gap-analyzer** | 解析 gcov.html，按函数分组未覆盖分支 | .cpp + .gcov.html | `[{function, uncovered_branches[]}]` |
| **test-generator** | 针对**单个函数**生成补充测试 | 函数源码 + uncovered_branches | 测试代码片段（增量） |
| **build-verifier** | SSH 远程编译验证 | 测试代码 + CMake 片段 | 编译结果 |
| **coverage-checker** | 对比新旧覆盖率，判断收敛 | 新 .gcov.html + 基线 | delta + still_uncovered |

### 为什么拆成 4 个 Skill？

1. **上下文聚焦** — 每个 Skill 的 prompt 很短，不会因处理整个文件而超出窗口
2. **按函数迭代** — test-generator 一次只处理一个函数，符合"分块补充"策略
3. **独立可测试** — 每个 Skill 可单独调试和优化
4. **并行预留** — 未来多个 test-generator 可并行处理同一个 .cpp 的不同函数

## 五、输入/输出数据契约

### 输入契约（UT Builder Agent 接收）

```jsonc
{
  "sources": [
    { "header": "path/to/class.h",   "source": "path/to/class.cpp" },
    { "header": "path/to/other.h",   "source": "path/to/other.cpp" }
  ],
  "existing_tests": [                    // 可选：已有手工 UT
    { "file": "path/to/test_class.cpp" }
  ],
  "baseline_coverage": {                // 可选：当前覆盖率基线
    "format": "gcov.html",              // 或 "lcov.info" / "json"
    "path": "path/to/gcov.html",
    "summary": {                        // agent 解析后的结构化数据
      "line_coverage_pct": 45.2,
      "branch_coverage_pct": 32.1,
      "total_branches": 284,
      "covered_branches": 91,
      "uncovered_branches": 193
    }
  },
  "iteration": {
    "round": 0,                         // 0 = 初始, N = 第 N 轮迭代
    "max_rounds": 10,                   // 防止无限循环
    "previous_gaps": [...]              // 上一轮未覆盖的分支列表
  },
  "config": {
    "target_branch_coverage": 100,
    "mock_strategy": "london",          // london | chicago | hybrid
    "test_framework": "gtest/gmock 1.14+",
    "build_system": "cmake"
  }
}
```

### 输出契约（UT Builder Agent 产出）

```jsonc
{
  "generated_tests": [
    {
      "file": "test_class.cpp",
      "content": "// 完整的测试代码",
      "test_count": 12,
      "targeted_branches": ["branch_id_1", "branch_id_2"],
      "test_cases": [
        {
          "name": "ShouldReturnZeroWhenInputIsNull",
          "target_branch": "null check at class.cpp:42",
          "expected_behavior": "returns 0 for null input"
        }
      ]
    }
  ],
  "coverage_expectation": {
    "expected_new_branch_coverage": 58.5,
    "expected_new_line_coverage": 67.0,
    "branches_still_uncovered": ["unreachable?", "needs source change?"],
    "notes": "3 branches appear unreachable due to defensive checks that may be dead code"
  },
  "source_modification_suggestions": [  // 当发现无法覆盖的代码时
    {
      "file": "class.cpp",
      "line": 156,
      "reason": "Dead code: this branch can never be reached because...",
      "suggestion": "Remove or refactor to make testable"
    }
  ]
}
```

## 六、覆盖率阈值

| 模块类型 | 行覆盖 | 分支覆盖 | 函数覆盖 |
|---------|--------|---------|---------|
| 关键业务 | ≥ 90% | ≥ 85% | ≥ 95% |
| 核心逻辑 | ≥ 80% | ≥ 70% | ≥ 90% |
| 工具代码 | ≥ 70% | ≥ 60% | ≥ 80% |
| 第三方/生成 | 豁免 | 豁免 | 豁免 |

## 七、并行扩展设计（预留）

### 当前阶段（Phase 1）：单文件串行

```
1 agent / 1 cpp → 按函数顺序迭代
```

### 扩展阶段（Phase 2）：多文件并行

```
N agents / N cpp files → 并行处理
Coordinator 汇总结果
```

### 扩展阶段（Phase 3）：单文件多 agent 分片

```
N agents / 1 cpp (超大文件) → 按函数分片并行
预留接口: sources 数组中支持 "split_strategy": "by_function"
```

## 八、实现优先级

按用户指定的顺序：

| # | 组件 | 说明 | 状态 |
|---|------|------|------|
| 1 | **test-generator** skill | C++ gtest/gmock 测试代码生成（核心） | 待实现 |
| 2 | **coverage-checker** skill | gcov.html 解析 + 覆盖率 delta 分析 | 待实现 |
| 3 | **gap-analyzer** skill | 按函数分组未覆盖分支 | 待实现 |
| 4 | **build-verifier** skill | SSH 远程编译验证 | 待实现 |
| 5 | **UT Builder agent** | 编排上述 4 个 skill 的 agent prompt | 待实现 |
| 6 | **测试执行 agent/skill** | SSH → lz4 → Web 平台 → 爬虫 → 测试结果 | 待设计 |
| 7 | **调度系统** | 并行编排多个 agent | 待设计 |

### 当前 Sprint：先实现 test-generator + coverage-checker

验证通路中最关键的两个步骤：
1. test-generator 能否生成可编译的 gtest/gmock 测试代码
2. coverage-checker 能否正确解析 gcov.html 并输出结构化数据

## 九、命名规范

- **测试用例**: `TEST_F(ClassNameTest, ShouldXxxWhenYyy)`
- **测试文件**: `test_<source_filename>.cpp`
- **Skill 文件**: `<skill-name>.md`（YAML frontmatter + Markdown body）
- **Agent 文件**: `<agent-name>.md`（YAML frontmatter + Markdown body）
