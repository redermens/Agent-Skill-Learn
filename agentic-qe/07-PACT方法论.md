# 07. PACT 方法论

> 这是 agentic-qe 的**思想内核**。理解了 PACT，整个框架的设计就豁然开朗。

---

## PACT 是什么

```
P - Proactive   主动     | 预防 > 反应
A - Autonomous  自主     | 团队自治 > QA 把关
C - Collaborative 协作    | 全员质量 > QA 孤岛
T - Targeted    目标     | 风险驱动 > 全面覆盖
```

四个字母对应四种**思维转变**，每个都对应 QE 工作中的一个旧反模式。

---

## P - Proactive（主动）

### 核心
不等 bug 找上门，在它出现前预测它。

### 反模式 vs 正确做法

| ❌ 旧 | ✅ 新 |
|------|------|
| 写完代码再考虑测试 | 设计阶段就问"怎么验证它工作" |
| Bug 出现后 root cause | 通过 mutation testing 主动找弱点 |
| 用户反馈才知道性能差 | 用 chaos engineering 主动注入故障 |
| 上线后才知道资源不够 | 部署前做风险预测 |

### 实践示例（原文）

```javascript
// 在 API 设计阶段就问："负载高时怎么知道它超时了？"
// 从一开始就把可观测性建进去
await Task("Risk Analysis", {
  phase: 'refinement',
  question: 'What could go wrong and how will we know?'
}, "qe-requirements-validator");
```

### 给 C++ 的具体动作

- 写函数前先写测试（TDD Red 阶段）
- 用 `[[nodiscard]]`、`std::expected` 让错误**必须被处理**
- compile-time check：concepts, static_assert
- 跑 mutation testing（`mull-cxx`）验证你的测试质量

---

## A - Autonomous（自主）

### 核心
**团队自己拥有质量，不需要 QA 把关**。

### 反模式 vs 正确做法

| ❌ 旧 | ✅ 新 |
|------|------|
| QA 是部署前的 manual gate | CI 自动门禁，全过即可部署 |
| 开发提交 → QA 跑测试 → 反馈 | 开发本地就能跑完整套件 |
| 测试环境 ticket 申请 | 自助式测试环境 |
| 部署窗口期 | 多次/天部署 |

### Autonomous 检查清单（原文）

- [ ] 开发者**本地能跑完整测试套件**
- [ ] CI **快速失败**且诊断清晰
- [ ] **没有手动部署审批**
- [ ] **自助式测试环境**

### 给 C++ 的具体动作

```bash
# 让开发者一行命令跑全套
make test                    # 全套
make test-unit               # 仅单元
make test-fast               # 跳过慢测试
make coverage                # 含覆盖率
```

- CMake preset 模板化常用配置
- 容器化测试环境（Docker Compose）
- 预提交钩子跑静态检查 (clang-tidy)

---

## C - Collaborative（协作）

### 核心
**质量是全团队责任，不是 QA 一个部门的事**。

### 反模式 vs 正确做法

| ❌ 旧 | ✅ 新 |
|------|------|
| QA 单独工作 | QA 参与所有会议（需求/设计/复盘） |
| Dev 写代码，QA 写测试 | Three Amigos（产品/开发/QA）共同精化每个 user story |
| 测试代码 QA 维护 | 测试代码全员所有权 |
| 复杂场景 QA 探索 | Ensemble Testing（多人结对测试） |

### 实践

```
Three Amigos 会议:
  - 产品: "用户想要什么"
  - 开发: "技术上怎么实现"  
  - QA:   "怎么验证它工作"
  
  → 三方对齐，写出明确的验收标准
```

### 给 C++ 团队的具体动作

- Pull Request 模板里**强制**包含测试说明
- Code review 检查**测试质量**，不只看实现代码
- 测试代码和生产代码同 review 标准
- 周会包含质量数据回顾（不只是进度）

---

## T - Targeted（目标）

### 核心
**测重要的，跳过不重要的**。100% 覆盖不是目标。

### 反模式 vs 正确做法

| ❌ 旧 | ✅ 新 |
|------|------|
| 追求 100% 覆盖 | 关键路径 95%，admin 页面 50% |
| 所有 PR 跑全套 | 智能选择受影响的测试 |
| 测试越多越好 | 删掉无价值的测试 |
| 把所有 bug 同等对待 | 按业务影响分级 |

### 实践（原文）

```javascript
// 电商 checkout? 厚测。
// 管理面板月用 2 次? 薄测。
await Task("Risk-Based Planning", {
  critical: ['checkout', 'payment'],
  light: ['admin-panel', 'settings']
}, "qe-regression-risk-analyzer");
```

### 风险评分模型

```
风险分 = 复杂度 × 0.3 
       + 改动频率 × 0.25  
       + 历史 bug 数 × 0.25  
       + 业务关键度 × 0.2
```

### 给 C++ 的具体动作

- 关键模块加 `// COVERAGE: critical` 注释
- CMakeLists.txt 中按重要性给测试加 label
  ```cmake
  add_test(NAME core_payment COMMAND payment_test)
  set_tests_properties(core_payment PROPERTIES LABELS "critical")
  ```
- CI 配置不同 label 不同阈值

---

## PACT 四象限测试覆盖

agentic-qe 借用了 Marick Quadrants：

```
                  支持团队            批判产品
                  (Supporting)        (Critique)
                  
   面向技术      ┌──────────────┬──────────────┐
   (Technology)  │  单元测试     │ 性能测试      │
                 │  组件测试     │ 安全测试      │
                 │  集成测试     │ 混沌工程      │
                 │  TDD          │ 容量测试      │
                 └──────────────┴──────────────┘
   面向业务      ┌──────────────┬──────────────┐
   (Business)    │  BDD/ATDD     │ 探索测试      │
                 │  验收测试     │ 可用性测试    │
                 │  示例映射     │ A/B 测试      │
                 └──────────────┴──────────────┘
```

| 象限 | 用途 | 例子 |
|------|------|------|
| 技术+支持 | 快速反馈 | 单元/组件/集成 |
| 技术+批判 | 找极限 | 性能/安全/混沌 |
| 业务+支持 | 共同理解 | BDD/验收测试 |
| 业务+批判 | 发现未知 | 探索/可用性 |

**C++ 项目重点关注**：技术象限（左上 + 右上）。业务象限多半要 Web/UI 团队配合。

---

## 成功信号（PACT 落地是否成功）

来自原文档的指标：

- ✅ 功能**每天部署多次**
- ✅ Bug 逃逸率**持续下降**
- ✅ 团队**自然讨论质量**（不需要提醒）
- ✅ 开发**主动写测试**（不需要被催）
- ✅ **发布很无聊**（because everything just works）

---

## PACT 评估表（自我体检）

| 维度 | 0分 (旧 QA) | 5分 (Hybrid) | 10分 (PACT) |
|------|-----------|---------------|-------------|
| **Proactive** | 等 bug 找你 | 部分主动检查 | 设计阶段就考虑可测性 |
| **Autonomous** | QA 手动门禁 | CI 自动但有 manual approval | 全自动门禁，团队自主部署 |
| **Collaborative** | QA 独立部门 | QA 参与一部分会议 | QA 嵌入团队，全员质量 |
| **Targeted** | 追求 100% | 看重点模块 | 风险驱动+智能选择 |

**给自己打分** → 找最低的那项先改进。

---

## 评估 PACT 成熟度的命令（原文）

```bash
aqe assessment pact
# 输出当前团队的 PACT 成熟度报告
```

虽然你不一定会用这个 CLI，但**这个评估维度本身**很有价值。

---

## 核心思想凝练

如果只能记一句话：

> **质量是建出来的，不是测出来的。**
> 
> 团队拥有质量，QA 赋能不把关，测重要的不测全部。
> 
> 用 agent 做规模化的 PACT 实施，让人专注判断。

---

## 给 C++ 团队的 PACT 起步路径

1. **先做 Targeted** —— 列出关键模块，设差别化覆盖率目标
2. **再做 Proactive** —— TDD + mutation testing
3. **然后 Autonomous** —— 让 CI 全自动，去掉所有手动 approval
4. **最后 Collaborative** —— 文化建设，需要时间

**最容易做的：T 和 P。最难做的：A 和 C（涉及流程和文化）。**
