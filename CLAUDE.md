# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 这是什么

一个 C++ 测试质量工程的 AI agent 知识库。包含 5 个 agent 的 prompt 模板，每个 agent 解决 C++ 项目测试生命周期中的一个环节。这些 agent 可独立使用，也可按依赖关系串联成 pipeline。

## Agent 体系

| Agent | 文档 | 职责 | 输入 → 输出 |
|-------|------|------|-------------|
| **test-builder** | [01-test-builder.md](agentic-qe/01-test-builder.md) | 从 C++ 源码生成 gtest/gmock 单元测试 | 源文件 + 头文件 → 可编译的测试代码 + JSON 报告 |
| **flow-runner** | [02-flow-runner.md](agentic-qe/02-flow-runner.md) | 按预定义步骤执行测试（CLI/HTTP/Web） | 流程脚本 → 结构化执行结果 + 证据 |
| **coverage-analyst** | [03-coverage-analyst.md](agentic-qe/03-coverage-analyst.md) | 分析覆盖率报告，风险加权排序补测建议 | lcov/gcovr 报告 → 优先级补测清单 |
| **automation-orchestrator** | [04-automation-orchestrator.md](agentic-qe/04-automation-orchestrator.md) | 生成 CI/CD pipeline 配置 | 项目描述 → CI yaml + Makefile |
| **ut-gap-filler** | [05-ut-gap-filler.md](agentic-qe/05-ut-gap-filler.md) | 分析现有测试质量，找出缺口并补充 | 现有测试 + 源码 → 缺口清单 + code sketch |

## Agent 间的依赖关系

```
ut-gap-filler ─────────┐
coverage-analyst ──────┤── 输出: 缺口列表
                       │
         ↓ (依赖)
                       │
test-builder ──────────┤── 输出: 新增测试用例
                       │
         ↓ (依赖)
                       │
automation-orchestrator─┤── 输出: CI 流水线配置
                       │
         ↓ (依赖)
                       │
flow-runner ───────────┘── 输出: 执行结果 + 覆盖率
```

## 技术栈约定

- **测试框架**: gtest/gmock 1.14+
- **覆盖率**: lcov + gcovr（Linux），OpenCppCoverage（Windows）
- **Web E2E**: Vibium（首选，WebDriver BiDi 协议），非 Playwright
- **构建系统**: CMake
- **Mock 策略**: London 流派（外部依赖 mock），Chicago 流派（纯计算用真对象）
- **命名规范**: `TEST_F(ClassNameTest, ShouldXxxWhenYyy)`

## 每个 Agent 文档的统一结构

1. 角色定义（一行说清）
2. 输入要求（必填/可选）
3. 工作流程（步骤化）
4. 输出格式（JSON 为主）
5. 完整 Prompt（可直接喂给 AI）
6. 实战示例

## 覆盖率阈值

| 模块类型 | 行覆盖 | 分支覆盖 | 函数覆盖 |
|---------|--------|---------|---------|
| 关键业务 | ≥ 90% | ≥ 85% | ≥ 95% |
| 核心逻辑 | ≥ 80% | ≥ 70% | ≥ 90% |
| 工具代码 | ≥ 70% | ≥ 60% | ≥ 80% |
| 第三方/生成 | 豁免 | 豁免 | 豁免 |

## 重要约束

- agentic-qe 原生不支持 C++/gtest，所有 prompt 模板已做适配
- coverage-analyst 是为本项目新设计的 agent（agentic-qe 原生没有）
- 覆盖率报告优先用 JSON/lcov.info 文本格式喂 AI，不要直接喂 HTML（token 消耗大一个数量级）
- Web 测试优先 `data-testid` 选择器，CSS 类名次之
- 所有测试生成后必须真跑验证，不要相信 AI 说"测试已通过"
