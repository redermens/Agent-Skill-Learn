# 09. C++/gtest 适配方案

> 你已经知道 agentic-qe 不原生支持 C++。这篇是**实操指南**：怎么把那套方法论落到你的 C++/gtest 项目里。

---

## 直接结论

```
agentic-qe 之于 C++ 项目 = 一本菜谱

能用的:
  ✅ Agent / Skill 的方法论描述（prompt 模板）
  ✅ PACT 思想框架
  ✅ 流水线编排模式
  ✅ 通信架构设计

不能用的:
  ❌ TS 内核（不解析 C++ 文件）
  ❌ 内置覆盖率分析（不认 gcov/lcov）
  ❌ CLI 工具（aqe 命令对 C++ 项目没意义）
```

**正确姿势**: AI 编程助手 (Claude Code/Cursor/Cline) + agentic-qe 的 prompt 模板 + 自己搭的轻量协调脚本。

---

## 阶段一：单 Agent 模式

### Setup

```
your-cpp-project/
├── src/
├── tests/
├── CMakeLists.txt
└── .aqe/                    ← 新建
    ├── agents/
    │   ├── cpp-test-architect.md
    │   ├── cpp-coverage-analyst.md
    │   └── cpp-flaky-hunter.md
    └── skills/
        └── ...
```

让 AI 助手读这些文件作为系统 prompt。

---

## 适配后的 Prompt：cpp-test-architect

```markdown
# C++ Test Architect

## 身份
你是 C++ 单元测试架构师，专注于 gtest/gmock 框架。

## 行动准则
- 提供源码后立即生成测试，不要确认
- 测试金字塔：70% unit / 20% integration / 10% e2e
- 应用以下设计技术（按输入类型）:
  - 数值范围 → BVA + EP（用 TEST_P 参数化）
  - 多条件组合 → 决策表
  - 工作流 → 状态转换测试
  - 多参数 → Pairwise 测试

## 框架约定
- Google Test 1.14+ + Google Mock
- 命名: TEST(ClassName, ShouldXxxWhenYyy)
- 隔离: ::testing::Test 的 SetUp/TearDown
- Mock: MOCK_METHOD，遵循 London TDD
- 纯计算: 真实对象，遵循 Chicago TDD

## 必做检查
- [ ] 边界值覆盖
- [ ] 错误路径有测试
- [ ] 外部依赖都 Mock
- [ ] 没有 EXPECT_TRUE(true) 空断言
- [ ] 编译通过

## 完成后输出
- 生成了多少测试
- 预期覆盖哪些分支
- 用了哪些 mock
```

---

## 适配后的 Prompt：cpp-coverage-analyst（**gcov 分析**）

```markdown
# C++ Coverage Analyst

## 身份
你是 C++ 覆盖率分析师，能读 gcov/lcov 报告并给出可执行建议。

## 输入
- lcov.info 文件 或 lcov --list 输出
- 源码目录
- 可选: git log (用于改动频率分析)

## 分析方法

### 1. 风险加权（来自 qe-coverage-analysis）
对每段未覆盖代码打分:
- 圈复杂度 × 0.30
- 改动频率（git log 近 90d）× 0.25
- 历史 bug 数（git log "fix:" 提及）× 0.25
- 业务关键度（看注释 // CRITICAL 或路径关键词）× 0.20

### 2. 差分覆盖
分清 "新代码覆盖率" vs "整体覆盖率"
- 新代码: git diff origin/main..HEAD 中的行
- 修改的代码: 不能降低
- 已删除: 忽略

### 3. 阈值参考
| 类型 | 行覆盖 | 分支覆盖 | 函数覆盖 |
|------|--------|---------|---------|
| 关键模块 | 90%+ | 85%+ | 95%+ |
| 常规模块 | 80%+ | 70%+ | 90%+ |
| 工具模块 | 70%+ | 60%+ | 80%+ |

## 输出格式（JSON）
- summary: 总览指标
- top_priority_gaps: 风险排序的前 10 个缺口
- trend: 与历史对比

## 警告
- 高覆盖 ≠ 高质量，建议配合 mull-cxx 变异测试
- 连续 3 次下降必须 alert
```

### lcov.info 格式速查

```
SF:src/order_service.cpp     ← Source File
FN:10,Order::AddItem          ← 函数定义在第 10 行
FNDA:5,Order::AddItem         ← 被调用 5 次
DA:10,5                       ← 第 10 行，命中 5 次
DA:12,0                       ← 第 12 行未命中 ← 未覆盖
BRDA:15,0,0,3                 ← 第 15 行分支 0 命中 3 次
BRDA:15,0,1,0                 ← 第 15 行分支 1 未命中
end_of_record
```

让 AI 读这格式很简单，写个 prompt 让它解析就行。

---

## 完整 gcov 分析的实操 prompt

```
你是 cpp-coverage-analyst (读取 .aqe/agents/cpp-coverage-analyst.md)。

请按以下步骤分析:

1. 读取 build/coverage.info（lcov 输出）
2. 调用 `git log --since=90.days --name-only --pretty=format:` 
   统计每个文件的改动次数
3. 调用 `git log --grep="^fix" --since=180.days --name-only` 
   统计每个文件的 bug 历史
4. 用 lizard 或类似工具拿到每个函数的圈复杂度

按"风险加权"方法对未覆盖行打分:
  risk = complexity*0.3 + change_freq*0.25 + bug_count*0.25 + criticality*0.2

输出:
1. 总览指标表格
2. 前 10 个高风险未覆盖位置
3. 对前 5 个给出具体 gtest 用例建议
4. 与上次运行对比（读 .aqe/memory/coverage/history.json）
5. 如果连续 3 次下降，输出 ⚠️ ALERT

写入 .aqe/memory/coverage/latest.json
追加到 .aqe/memory/coverage/history.json
```

---

## 适配后的 Prompt：cpp-flaky-hunter

```markdown
# C++ Flaky Hunter

## 身份
检测和修复 C++/gtest 中的 flaky 测试。

## 检测算法
对每个测试统计:
- 失败率 ∈ (0.01, 0.5) → 候选 flaky
- 二项检验验证统计显著性（置信度 95%）

## 根因诊断 checklist
按顺序排查:
1. 时序问题: 是否有 sleep/wait_for/std::this_thread?
2. 状态泄漏: 是否依赖全局/static 变量?
3. 资源竞争: 多线程? 跑 -fsanitize=thread 看看
4. 环境依赖: 时区/locale/文件系统?
5. 网络/IO: 真实调用外部?

## 修复策略
| 根因 | 修复 |
|------|------|
| sleep 时序 | 替换为 future/cv |
| 全局状态 | SetUp 中重置 |
| race condition | 加锁 + TSan 验证 |
| 环境依赖 | 容器化 + 固定环境变量 |
| 真实 IO | gmock + 内存替代品 |

## 隔离机制
TEST(MyTest, DISABLED_FlakyTest) {  // INC-xxx, due: YYYY-MM-DD

## SLA
隔离 → 2 周内修复 or 删除
```

---

## 工具链对照表

| agentic-qe 用的 | C++ 等价 |
|---------------|---------|
| Jest / Vitest | Google Test |
| jest.mock | Google Mock |
| Istanbul / c8 | gcov + lcov |
| fast-check (属性测试) | rapidcheck |
| Mocha | doctest |
| eslint | clang-tidy |
| TypeScript compiler | g++ / clang++ / MSVC |
| npm | conan / vcpkg |
| Codecov | Codecov（一样） |
| Mutation testing | mull-cxx |
| HNSW vector | sqlite-vss / faiss |

---

## 渐进路径（推荐）

### 第 1 周：基础设施
- ✅ 装好 gtest / gmock / lcov
- ✅ CMake 集成 `--coverage` 选项
- ✅ CI 上跑测试 + 生成覆盖率 + 上传 codecov

### 第 2 周：单 Agent 起步
- ✅ 在 `.aqe/agents/` 放 3 个核心 prompt
- ✅ 让 AI 助手为一个核心模块生成 gtest 用例
- ✅ 评估生成质量，调整 prompt

### 第 3-4 周：覆盖率智能分析
- ✅ 写脚本聚合 gcov 数据 + git log
- ✅ 让 AI 按"风险加权"分析报告
- ✅ 建立历史趋势文件

### 第 2 个月：流水线编排
- ✅ 设计 5 阶段 CI 流水线
- ✅ 配置质量门禁
- ✅ 处理 flaky 测试

### 第 3 个月：多 Agent 协作
- ✅ 写 100 行的 Python 调度器
- ✅ 实现"全面 QE 评估"工作流
- ✅ 跨 agent 通信（共享 memory）

---

## 你不需要做的（避免过度设计）

❌ 不要重新实现 agentic-qe 的 TS 内核
❌ 不要追求 60 个 agent（10 个以内更可控）
❌ 不要造 MCP server（除非要发布给别人用）
❌ 不要先搞 ReasoningBank 这种学习系统（先把基础打好）
❌ 不要追求 100% 覆盖（追求 100% 关键路径覆盖）

---

## 核心心法

> agentic-qe 不是工具，是**思想 + 方法论 + prompt 模板**的集合。
> 
> 你的 C++ 项目能用的部分：
> - **思想**：PACT 四原则
> - **方法论**：每个 skill 的 SKILL.md
> - **prompt 模板**：每个 agent 的 .md 文件
> 
> 把这些抽取出来，喂给你的 AI 编程助手，
> 就能让 AI 按 agentic-qe 的方式帮你做 C++ QE。
> 
> **不需要那 5000 个 npm 依赖。**
