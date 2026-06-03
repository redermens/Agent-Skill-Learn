# Agentic QE 学习笔记

> 整理自 `npm install -g agentic-qe@3.10.1` 的官方 agent/skill 定义。
> 整理时间：2026-06-04
> 目标：把 agentic-qe 中**语言无关的方法论**抽取出来，方便迁移到 **C++/gtest** 项目。

---

## 写在前面：关键事实

| 问题 | 答案 |
|------|------|
| agentic-qe 内核支持 C++/gtest 吗？ | ❌ 不支持。源码 `dist/shared/types/test-frameworks.js` 中明确支持的语言只有 10 种（TS/JS/Python/Java/C#/Go/Rust/Swift/Kotlin/Dart） |
| 有 gcov/lcov 报告分析能力吗？ | ❌ 完全没有。全代码库搜索 `gcov`/`lcov` 零命中 |
| 那 npm 装的那一坨是什么？ | TS 工程 + Agent prompt 模板 + Skill 方法论文档 |
| 对你有用的是什么？ | **Agent/Skill 的方法论描述**——这些是 prompt，语言无关，可以让你的 AI 助手按这套思路写 C++ 测试 |

---

## 你的核心需求 → 对应文档

| 需求 | 文档 | 关键 agent/skill |
|------|------|-----------------|
| 1. UT 构造 | [01-单元测试生成.md](./01-单元测试生成.md) | qe-test-architect, qe-test-generation, test-design-techniques, tdd-london-chicago |
| 2. 自动化测试 | [02-自动化测试.md](./02-自动化测试.md) | qe-test-execution, test-automation-strategy |
| 3. 覆盖率分析 | [03-覆盖率分析.md](./03-覆盖率分析.md) | qe-coverage-analysis, qe-coverage-specialist |
| 4. 顺序流水线 | [04-CICD流水线编排.md](./04-CICD流水线编排.md) | cicd-pipeline-qe-orchestrator |
| 5. Agent 间通信 | [05-Agent通信机制.md](./05-Agent通信机制.md) | memory namespace, event bus |
| 6. 统一调度系统 | [06-统一调度系统.md](./06-统一调度系统.md) | qe-queen-coordinator, qe-fleet-commander |

## 推荐你也看的

| 文档 | 为什么重要 |
|------|----------|
| [07-PACT方法论.md](./07-PACT方法论.md) | 整个框架的思想内核，4 条原则贯穿所有设计 |
| [08-Flaky测试治理.md](./08-Flaky测试治理.md) | 你以后写自动化测试一定会踩坑的领域 |
| [09-Cpp-gtest适配方案.md](./09-Cpp-gtest适配方案.md) | **重点**——给你的 C++ 项目套这套方法论的具体路径 |

---

## 目录结构

```
agentic-qe/
├── 00-README.md                    ← 你正在看
├── 01-单元测试生成.md
├── 02-自动化测试.md
├── 03-覆盖率分析.md
├── 04-CICD流水线编排.md
├── 05-Agent通信机制.md
├── 06-统一调度系统.md
├── 07-PACT方法论.md
├── 08-Flaky测试治理.md
└── 09-Cpp-gtest适配方案.md         ← 你最该看的实操指南
```

---

## 怎么用这些笔记

1. **不熟 agentic-qe** → 先读 07（思想）→ 06（架构）→ 09（落地）
2. **要给 C++ 项目搭 QE 体系** → 直接跳 09
3. **想理解某个具体能力** → 看对应编号文档
4. **每个文档结构都是**：
   - **它是什么** —— agent/skill 的定义和职责
   - **核心方法** —— 怎么干活
   - **C++/gtest 适配** —— 如何在你的项目里实践
   - **关键代码片段** —— 原文摘录
