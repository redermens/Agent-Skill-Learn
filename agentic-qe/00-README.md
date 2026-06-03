# Agentic QE for C++ 项目 — 我的 5 个 Agent

> 整理自 agentic-qe v3.10.1 的核心 agent/skill，按你的实际需求裁剪。
> 整理时间：2026-06-04
> 工作目录：D:\WorkSpace\learning\agentic-qe

---

## 目标 → Agent 映射

| 你的需求 | Agent 名 | 文档 |
|---------|---------|------|
| 1. 构建测试用例 | **test-builder** | [01-test-builder.md](./01-test-builder.md) |
| 2. 按流程执行测试（可能操作 web） | **flow-runner** | [02-flow-runner.md](./02-flow-runner.md) |
| 3. gcov/lcov HTML 覆盖率报告分析 | **coverage-analyst** | [03-coverage-analyst.md](./03-coverage-analyst.md) |
| 4. 自动化流程 | **automation-orchestrator** | [04-automation-orchestrator.md](./04-automation-orchestrator.md) |
| 5. 现有 UT 分析并补充 | **ut-gap-filler** | [05-ut-gap-filler.md](./05-ut-gap-filler.md) |

---

## 怎么用这套文档

### 阶段一：单 agent 独立使用（你现在的阶段）

每个 `.md` 文件就是一份 **prompt 模板**，可以直接喂给 AI 编程助手（Claude Code / Cursor / Cline）：

```
# 在 Claude Code 里：
读取 D:\WorkSpace\learning\agentic-qe\01-test-builder.md 作为你的角色定义。
然后为 src/order_service.cpp 生成 gtest 单元测试。
```

### 阶段二：5 个 agent 组成调度系统（后续）

5 个 agent 都跑通后，再考虑用 Python/Shell 串起来。典型工作流：

```
ut-gap-filler          ┐
                       │── 输出: 缺口列表
coverage-analyst       ┘

       ↓ (依赖)

test-builder           ── 输出: 新增测试用例

       ↓ (依赖)

automation-orchestrator── 输出: CI 流水线配置

       ↓ (依赖)

flow-runner            ── 输出: 执行结果 + 覆盖率
```

调度的事不急，先把单 agent 用顺。

---

## 每个 Agent 文档的结构

```
1. 角色定义        ← 一行说清是谁
2. 输入要求        ← 用之前给它什么
3. 工作流程        ← 它会怎么干
4. 输出格式        ← 你会拿到什么
5. 完整 Prompt     ← 复制粘贴给 AI 用
6. 实战示例        ← 真实场景演示
```

---

## 重要事实

- **agentic-qe 原生不支持 C++/gtest** — 但 prompt 模板可以适配
- **agentic-qe 没有 gcov/lcov 分析 agent** — 我帮你设计了一个
- **web 自动化用 Vibium**（agentic-qe 内置）— 比 Playwright 轻 30 倍
