# Agent & Skill 分类报告：C++ QE (gtest/gmock + lcov/gcovr + CMake)

> 生成日期: 2026-06-04 | 基于 `.claude/agents/` (~177 agents) 和 `.claude/skills/` (118 skills)

---

## 一、总体概览

| 分级 | Agent 数量 | Skill 数量 | 说明 |
|------|-----------|-----------|------|
| 🔴 HIGH | ~14 | ~43 | 可直接用于 C++ QE pipeline |
| 🟡 MEDIUM | ~8 | ~36 | 需适配后使用 |
| 🟢 LOW | ~18 | ~19 | 边缘相关 |
| ⚪ NONE | ~47 | ~20 | 不相关（Web/移动/n8n/Flow Nexus/V3 内部） |

---

## 二、HIGH 相关性 —— 可直接用于 C++ QE

### 2.1 Agents（14 个）

| Agent | 位置 | 用途 | 对应 Pipeline |
|-------|------|------|---------------|
| **tester** | agents/core/ | 综合测试与QA，AI驱动测试生成，支持单元/集成/E2E/性能/安全测试 | test-builder, flow-runner |
| **coder** | agents/core/ | 代码实现专家，干净高效代码编写 | test-builder |
| **code-analyzer** | agents/analysis/ | 高级代码质量分析，全面代码审查 | ut-gap-filler, coverage-analyst |
| **analyze-code-quality** | agents/analysis/ | 代码质量分析 | ut-gap-filler |
| **ops-cicd-github** | agents/devops/ | GitHub Actions CI/CD pipeline 创建和优化 | automation-orchestrator |
| **planner** | agents/core/ | 战略规划和任务编排 | automation-orchestrator |
| **reviewer** | agents/core/ | 代码审查和质量保证 | ut-gap-filler |
| **sparc-coder** | agents/templates/ | 将规格转换为工作代码，TDD 实践 | test-builder |
| **tdd-london-swarm** | agents/testing/ | London 学派 TDD（mock 驱动）Swarm 协调 | test-builder |
| **production-validator** | agents/testing/ | 生产验证，确保应用完整实现且可部署 | flow-runner |
| **arch-system-design** | agents/architecture/ | 系统架构设计、模式、高层技术决策 | automation-orchestrator |
| **specification** | agents/sparc/ | SPARC 规范阶段，需求分析 | ut-gap-filler |
| **refinement** | agents/sparc/ | SPARC 细化阶段，迭代改进 | coverage-analyst |
| **researcher** | agents/core/ | 深度研究和信息收集 | ut-gap-filler |

### 2.2 Skills（43 个）

#### 🔧 覆盖率分析（对应 coverage-analyst）

| Skill | 描述 |
|-------|------|
| **coverage-drop-investigator** | 覆盖率回归调查，追踪到具体 commit 和文件 |
| **coverage-guard** | 开发时防止覆盖率退化，低于阈值自动告警 |
| **qe-coverage-analysis** | 风险加权覆盖率缺口检测，支持 lcov/Istanbul/c8 |

#### 🧪 测试生成（对应 test-builder）

| Skill | 描述 |
|-------|------|
| **qe-test-generation** | 从代码分析生成单元/集成/E2E 测试，含分支覆盖和边界条件 |
| **tdd-london-chicago** | London (mock) 和 Chicago (状态) 两种 TDD 学派 |
| **strict-tdd** | 强制 TDD 纪律：无失败测试不允许写生产代码 |
| **test-design-techniques** | BVA、等价类划分、决策表、状态转换测试设计 |
| **mutation-testing** | 变异测试评估测试套件有效性 |

#### 🚀 测试执行（对应 flow-runner）

| Skill | 描述 |
|-------|------|
| **qe-test-execution** | 并行 sharding、智能重试、实时报告的测试编排 |
| **qe-iterative-loop** | 自主 red-green-refactor 循环，直到测试通过/覆盖率达标 |
| **iterative-loop** | 持续 build-test-fix 循环直到成功标准满足 |
| **debug-loop** | 假设驱动的调试，系统化根因消除 |
| **test-failure-investigator** | 测试失败根因分析：flaky/环境/真实回归 |
| **no-skip** | 禁止 `.skip()` `.only()` 进入测试文件 |
| **freeze-tests** | 重构时冻结测试文件，保证行为不变化 |
| **security-watch** | 实时扫描 secret/eval/innerHTML 等危险模式 |

#### ⚙️ CI/CD 自动化（对应 automation-orchestrator）

| Skill | 描述 |
|-------|------|
| **cicd-pipeline-qe-orchestrator** | CI/CD pipeline 各阶段质量工程编排 |
| **test-automation-strategy** | 测试自动化框架设计、金字塔模式、CI/CD 集成 |
| **github-workflow-automation** | GitHub Actions 工作流自动化，AI swarm 协调 |

#### 📊 代码质量与分析（对应 ut-gap-filler）

| Skill | 描述 |
|-------|------|
| **qe-code-intelligence** | 语义代码索引、依赖图、智能代码搜索 |
| **code-review-quality** | 上下文驱动的代码审查：质量、可测试性、可维护性 |
| **brutal-honesty-review** | 不妥协的技术批评，精准指出问题 |
| **sherlock-review** | 基于证据的侦查式代码审查，演绎推理 |
| **refactoring-patterns** | 安全重构模式，不改变行为改善结构 |
| **bug-reporting-excellence** | 高质量 bug 报告标准 |

#### 🎯 测试策略与质量度量

| Skill | 描述 |
|-------|------|
| **agentic-quality-engineering** | AQE 核心：PACT 原则、fleet 配置、agent 编排 |
| **holistic-testing-pact** | PACT 全面测试模型（主动/自主/协作/定向） |
| **shift-left-testing** | 测试左移：TDD/BDD/CI/CD 早期质量实践 |
| **quality-metrics** | DORA 指标、缺陷密度、测试有效性比率 |
| **test-metrics-dashboard** | 测试历史查询、flaky 率分析、MTTR 追踪 |
| **test-reporting-analytics** | 高级测试报告、预测分析、趋势分析 |
| **risk-based-testing** | 基于风险的测试优先级排序 |
| **regression-testing** | 变更驱动的回归测试选择、影响分析 |
| **validation-pipeline** | 多阶段验证门禁，带评分和通过/失败判定 |
| **verification-quality** | Agent 输出验证、Truth Scoring、质量门禁 |
| **api-testing-patterns** | API 合约测试、REST/GraphQL 测试模式 |
| **performance-testing** | k6/Artillery/JMeter 负载/压力/浸泡测试 |
| **test-data-management** | 测试数据生成、管理、隐私合规 |
| **test-environment-management** | Docker/K8s 测试环境、基础设施即代码 |

#### 🏗️ QCSD Swarm（质量管理全流程）

| Skill | 描述 |
|-------|------|
| **qcsd-development-swarm** | Sprint 内代码质量：TDD 遵守检查、复杂度、覆盖率缺口 |
| **qcsd-cicd-swarm** | CI/CD 质量门禁：回归分析、flaky 检测、部署就绪 |
| **qcsd-ideation-swarm** | PI/Sprint 规划：HTSM v6.3 质量标准、风险头脑风暴 |
| **qcsd-refinement-swarm** | Sprint 细化：SFDIPOT 产品因素、BDD 场景生成 |

#### 🛠️ 工具与基础设施

| Skill | 描述 |
|-------|------|
| **skill-builder** | 创建自定义 Skill，含 YAML frontmatter 和目录结构 |

---

## 三、MEDIUM 相关性 —— 需适配后使用

### 3.1 Agents（8 个）

| Agent | 位置 | 用途 |
|-------|------|------|
| **dev-backend-api** | agents/development/ | 后端 API 开发（可用于测试 API 构建） |
| **sparc-coordinator** | agents/templates/ | SPARC 方法论编排 |
| **orchestrator-task** | agents/templates/ | 任务分解和执行规划 |
| **memory-coordinator** | agents/templates/ | 跨会话持久记忆管理 |
| **base-template-generator** | agents/templates/ | 基础模板/样板代码生成 |
| **coordinator-swarm-init** | agents/templates/ | Swarm 初始化和拓扑优化 |
| **hierarchical-coordinator** | agents/swarm/ | 层级 Swarm 协调 |
| **mesh-coordinator** | agents/swarm/ | P2P 网状网络 Swarm |

### 3.2 Skills（36 个）

| Skill | 领域 | 适配说明 |
|-------|------|---------|
| **qe-quality-assessment** | 质量评估 | 复杂度/lint/代码异味分析，语言无关 |
| **qe-defect-intelligence** | 缺陷预测 | ML 预测缺陷，可用于 C++ 项目 |
| **qe-learning-optimization** | 学习优化 | 跨项目迁移学习、超参数调优 |
| **qe-requirements-validation** | 需求验证 | BDD 场景生成，可适配 gtest |
| **chaos-engineering-resilience** | 混沌工程 | 故障注入、韧性测试 |
| **contract-testing** | 合约测试 | API 合约验证 |
| **database-testing** | 数据库 | Schema 验证、迁移测试 |
| **testability-scoring** | 可测试性 | 10 原则可测试性评估 |
| **test-idea-rewriting** | 测试设计 | 被动→主动测试描述转换 |
| **sfdipot-product-factors** | 需求分析 | HTSM 产品因素分析 |
| **context-driven-testing** | 测试方法论 | 上下文驱动原则 |
| **exploratory-testing-advanced** | 探索测试 | SBTM、RST 启发式 |
| **six-thinking-hats** | 方法论 | 六顶思考帽多视角分析 |
| **xp-practices** | 敏捷实践 | XP：配对、TDD、CI |
| **consultancy-practices** | 专业实践 | 质量咨询方法论 |
| **technical-writing** | 文档 | 测试计划/策略文档撰写 |
| **pair-programming** | 协作 | AI 辅助配对编程 + TDD |
| **swarm-advanced** | 编排 | 分布式 Swarm 研究/开发/测试 |
| **swarm-orchestration** | 编排 | 多 agent swarm 并行执行 |
| **stream-chain** | 工作流 | 多 agent pipeline 流式链接 |
| **sparc-methodology** | 方法论 | SPARC 开发方法论 |
| **reasoningbank-agentdb** | 学习 | 自适应学习模式存储 |
| **reasoningbank-intelligence** | 学习 | 元认知、持续改进 |
| **agentdb-memory-patterns** | 记忆 | Agent 持久记忆模式 |
| **agentdb-advanced** | 基础设施 | 分布式 AgentDB、QUIC 同步 |
| **agentdb-vector-search** | 搜索 | 语义向量搜索 |
| **agentdb-optimization** | 优化 | HNSW 索引、量化优化 |
| **agentdb-learning** | 学习 | 9 种强化学习算法 |
| **hooks-automation** | 自动化 | Pre/post task hooks 自动协调 |
| **github-code-review** | GitHub | Swarm 协调代码审查 |
| **github-project-management** | GitHub | Issue 跟踪、项目面板 |
| **github-release-management** | GitHub | 发布编排 |
| **pr-review** | 审查 | PR 质量审查工作流 |
| **release** | 发布 | npm 发布工作流 |
| **skill-stats** | 分析 | Skill 使用统计 |

---

## 四、LOW 相关性 —— 边缘相关

### 4.1 Agents（~18 个）

主要是 Consensus 协议类（byzantine-coordinator, raft-manager, gossip-coordinator, crdt-synchronizer）、Payments（agentic-payments, claims-authorizer）、Data、Sona、Flow Nexus 等领域的 agent。

### 4.2 Skills（19 个）

| Skill | 原因 |
|-------|------|
| qe-browser, qe-visual-accessibility, qe-chaos-resilience | Web 浏览器相关 |
| accessibility-testing, a11y-ally | WCAG 无障碍测试 |
| visual-testing-advanced, security-visual-testing | 视觉回归测试 |
| security-testing, pentest-validation | Web 安全测试（XSS/SQL注入） |
| compatibility-testing, mobile-testing, localization-testing | 跨平台/移动/国际化 |
| e2e-flow-verifier | Web E2E 流程 |
| observability-testing-patterns | 仪表盘/告警 |
| compliance-testing | GDPR/HIPAA/PCI-DSS |
| enterprise-integration-testing, middleware-testing-patterns, wms-testing-patterns | SAP/WMS/ESB |
| shift-right-testing | 生产环境测试 |

---

## 五、NONE 相关性 —— 不适用

### 5.1 Agents（~47 个）

n8n 系列（~24个）、Flow Nexus 系列（~10个）、Sublinear 算法类（matrix-optimizer, pagerank-analyzer, trading-predictor）、Browser agent、Payments、Security 架构类（security-architect-aidefence）、Sona learning、V3 集成类。

### 5.2 Skills（20 个）

| Skill | 原因 |
|-------|------|
| browser | Web 浏览器自动化 |
| flow-nexus-neural, flow-nexus-platform, flow-nexus-swarm | Flow Nexus 平台专用 |
| n8n-expression-testing, n8n-integration-testing-patterns, n8n-security-testing, n8n-trigger-testing-strategies, n8n-workflow-testing-fundamentals | n8n 工作流专用 |
| v3-cli-modernization, v3-core-implementation, v3-ddd-architecture, v3-integration-deep, v3-mcp-optimization, v3-memory-unification, v3-performance-optimization, v3-security-overhaul, v3-swarm-coordination | V3 内部实现 |
| qcsd-production-swarm | 生产后阶段（DORA/根因分析） |
| github-multi-repo | 多仓库协调 |

---

## 六、映射到 5-Agent QE Pipeline

```
┌─────────────────────────────────────────────────────────────────┐
│                    C++ Agentic QE Pipeline                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  [ut-gap-filler] ─────────────────────────┐                      │
│  Agents: code-analyzer, reviewer,          │                      │
│          analyze-code-quality,             │                      │
│          specification, researcher          │                      │
│  Skills: qe-code-intelligence,             │                      │
│          code-review-quality,              │                      │
│          brutal-honesty-review,            │──► 输出: 缺口清单    │
│          sherlock-review,                  │                      │
│          refactoring-patterns,             │                      │
│          bug-reporting-excellence          │                      │
│                                            │                      │
│  [coverage-analyst] ───────────────────────┤                      │
│  Agents: code-analyzer, refinement         │                      │
│  Skills: qe-coverage-analysis,             │                      │
│          coverage-drop-investigator,       │                      │
│          coverage-guard                    │                      │
│                                            │                      │
│              ↓ (依赖)                       │                      │
│                                            │                      │
│  [test-builder] ───────────────────────────┤                      │
│  Agents: tester, coder, sparc-coder,       │                      │
│          tdd-london-swarm                  │                      │
│  Skills: qe-test-generation,               │                      │
│          tdd-london-chicago,               │                      │
│          strict-tdd,                       │──► 输出: 测试用例    │
│          test-design-techniques,           │                      │
│          mutation-testing,                 │                      │
│          test-data-management              │                      │
│                                            │                      │
│              ↓ (依赖)                       │                      │
│                                            │                      │
│  [automation-orchestrator] ────────────────┤                      │
│  Agents: ops-cicd-github, planner,         │                      │
│          arch-system-design                │                      │
│  Skills: cicd-pipeline-qe-orchestrator,    │──► 输出: CI 配置    │
│          test-automation-strategy,         │                      │
│          github-workflow-automation,       │                      │
│          risk-based-testing,               │                      │
│          regression-testing                │                      │
│                                            │                      │
│              ↓ (依赖)                       │                      │
│                                            │                      │
│  [flow-runner] ────────────────────────────┘                      │
│  Agents: tester, production-validator      │                      │
│  Skills: qe-test-execution,                │                      │
│          qe-iterative-loop,                │──► 输出: 执行结果    │
│          iterative-loop,                   │    + 覆盖率报告      │
│          debug-loop,                       │                      │
│          test-failure-investigator,        │                      │
│          no-skip, freeze-tests,            │                      │
│          security-watch,                   │                      │
│          performance-testing               │                      │
│                                                                  │
├─────────────────────────────────────────────────────────────────┤
│  跨阶段支撑:                                                      │
│  Skills: agentic-quality-engineering, holistic-testing-pact,     │
│          shift-left-testing, quality-metrics,                    │
│          test-metrics-dashboard, test-reporting-analytics,       │
│          validation-pipeline, verification-quality               │
│  QCSD:  qcsd-development-swarm, qcsd-cicd-swarm,                │
│          qcsd-ideation-swarm, qcsd-refinement-swarm              │
│  Swarm: swarm-advanced, swarm-orchestration, stream-chain        │
└─────────────────────────────────────────────────────────────────┘
```

---

## 七、关键发现与建议

### 7.1 对你要构建的 3 个自定义 Agent/Skill 的建议

根据你的需求（UT 用例构建 + 测试执行 + 覆盖率分析），现有资源已覆盖大部分能力：

| 你的需求 | 可直接复用的 Agent | 可直接复用的 Skill | 需要新建的内容 |
|---------|-------------------|-------------------|---------------|
| **UT 用例构建** | tester, coder, sparc-coder, tdd-london-swarm | qe-test-generation, tdd-london-chicago, strict-tdd, test-design-techniques | C++ gtest/gmock 专用 prompt 模板 |
| **测试执行** | tester, production-validator | qe-test-execution, qe-iterative-loop, debug-loop, test-failure-investigator | CMake/ctest 集成 + lcov 报告解析 |
| **覆盖率分析** | code-analyzer, refinement | qe-coverage-analysis, coverage-drop-investigator, coverage-guard | lcov.info JSON 解析器 + 风险加权排序 |

### 7.2 调度系统建议

现有 swarm 基础设施已经很强大了：
- **swarm-advanced** + **swarm-orchestration** 提供多 agent 并行编排
- **stream-chain** 提供 pipeline 流式链接
- **cicd-pipeline-qe-orchestrator** 提供 CI/CD 质量门禁编排

你主要需要做的：
1. 创建 C++ 专用的 3 个自定义 agent prompt（基于现有 agent 模板改造）
2. 创建 1 个调度编排 skill，利用现有 swarm 能力协调并行执行
3. 定义 agent 间的数据契约（JSON schema），确保 pipeline 可串联

### 7.3 重点推荐的 Skill（Top 15）

按对 C++ QE 的直接价值排序：

1. ⭐ **agentic-quality-engineering** — AQE 核心，理解整个体系的基础
2. ⭐ **qe-coverage-analysis** — 直接支持 lcov，覆盖率分析核心
3. ⭐ **qe-test-generation** — 测试生成核心
4. ⭐ **qe-test-execution** — 测试执行编排核心
5. ⭐ **qe-code-intelligence** — C++ 代码库理解
6. ⭐ **coverage-drop-investigator** — 覆盖率回归调查
7. ⭐ **cicd-pipeline-qe-orchestrator** — CI/CD 编排
8. **qe-iterative-loop** — 自主测试修复循环
9. **tdd-london-chicago** — TDD 方法论
10. **mutation-testing** — 测试质量验证
11. **test-design-techniques** — 系统化测试设计
12. **debug-loop** — 测试失败调试
13. **code-review-quality** — 代码审查
14. **holistic-testing-pact** — 全面测试策略
15. **swarm-advanced** — 并行执行调度
