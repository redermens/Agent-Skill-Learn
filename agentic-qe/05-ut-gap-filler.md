# 05. ut-gap-filler — 现有 UT 分析并补充 Agent

## 角色

读你**已经写好的 gtest 测试代码**，找出测试薄弱点，针对性补充用例。
和 `test-builder` 的区别：test-builder 是从源码 0 到 1 生成，ut-gap-filler 是从现有测试 1 到 N 加强。

---

## 适用场景

| 场景 | 例子 |
|------|------|
| 接手遗留项目 | 已有 100 个测试，但不知道好不好，让 AI 分析 |
| 覆盖率上不去 | 加了很多测试还是 60%，让 AI 看哪里有冗余 |
| Mutation Score 低 | 测试都过但变异测试发现假阳性，让 AI 加边界 |
| Bug 漏测 | 线上出了 bug，让 AI 分析为啥测试没抓到 |

---

## 输入

| 输入项 | 必填 | 说明 |
|--------|------|------|
| 现有测试文件 | ✅ | 比如 `tests/unit/order_test.cpp` |
| 对应源文件 | ✅ | 比如 `src/order.cpp` |
| 覆盖率报告 | ⬜ | 有的话精度更高 |
| 已知 bug 列表 | ⬜ | 比如 git log "fix:" |
| Mutation 报告 | ⬜ | 来自 mull-cxx |

---

## 工作流

```
1. 读现有测试
   - 解析所有 TEST/TEST_F/TEST_P
   - 提取每个测试的：被测函数 / 输入 / 断言
   - 识别 fixture、mock 用法
   - 找重复/相似测试

2. 读源码
   - 列出所有 public 方法
   - 标注每个方法的分支、错误路径、边界

3. 交叉比对（关键步骤）
   - 哪些方法完全没测？        → P0 缺口
   - 哪些方法只测了 happy path？ → P1 缺口（缺错误路径）
   - 哪些分支没覆盖？           → P2 缺口
   - 哪些边界没覆盖？           → P3 缺口

4. 现有测试质量评估
   - 断言强度（EXPECT_EQ vs EXPECT_TRUE(true)）
   - 测试隔离（有没有共享状态）
   - 命名规范（描述性 vs 神秘缩写）
   - 重复度（多个测试在测同一件事）

5. 输出建议
   - 补充哪些测试（按 P0→P3 排序）
   - 删除哪些冗余测试
   - 重构哪些薄弱测试
```

---

## 输出格式

```json
{
  "source_file": "src/order_service.cpp",
  "test_file": "tests/unit/order_service_test.cpp",
  "existing_tests": {
    "total": 15,
    "by_quality": {
      "strong": 8,
      "weak": 5,
      "redundant": 2
    }
  },
  "method_coverage_matrix": [
    {
      "method": "CreateOrder",
      "tested": true,
      "scenarios_covered": ["happy_path", "validation_error"],
      "scenarios_missing": ["payment_timeout", "concurrent_create", "amount_boundary"],
      "priority": "P1"
    },
    {
      "method": "RefundOrder",
      "tested": false,
      "priority": "P0",
      "complexity": 8
    }
  ],
  "p0_gaps": [
    {
      "method": "RefundOrder",
      "reason": "完全没有测试，但圈复杂度 8 + 是关键业务",
      "suggested_tests": [
        {
          "name": "RefundFullAmount_ShouldSucceed",
          "scenario": "正常退款",
          "code_sketch": "EXPECT_CALL(*gateway_, Refund(100.0)).WillOnce(Return(true)); ..."
        },
        {
          "name": "RefundExceedsOriginal_ShouldReject",
          "scenario": "退款超原金额",
          "code_sketch": "..."
        }
      ]
    }
  ],
  "weak_tests_to_improve": [
    {
      "test": "OrderServiceTest::ShouldWork",
      "issues": ["名称无意义", "只有 EXPECT_TRUE(result)，没验证内容"],
      "suggestion": "改名为 ShouldReturnOrderIdWhenValidInput，断言改为 EXPECT_EQ(result.id, expected_id)"
    }
  ],
  "redundant_tests_to_remove": [
    {
      "tests": ["TestAdd_1", "TestAdd_2", "TestAdd_3"],
      "reason": "三个都在测同样的 Add(1, 2) = 3，合并为参数化测试"
    }
  ],
  "summary": {
    "p0_count": 3,
    "p1_count": 7,
    "p2_count": 12,
    "p3_count": 5,
    "estimated_coverage_after_fix": "85% → 92%"
  }
}
```

---

## 完整 Prompt（喂给 AI）

```
你是 ut-gap-filler agent。

# 任务
分析现有 gtest 测试代码 + 对应源文件，找出测试缺口，给出补充建议。

# 输入
- 测试文件: <tests/unit/xxx_test.cpp>
- 源文件: <src/xxx.cpp>
- 头文件: <include/xxx.h>
- 覆盖率（可选）: <coverage.json 或 lcov.info>

# 分析维度

## 维度 1: 方法覆盖矩阵
对源文件每个 public 方法判断:
  - 是否有测试？
  - 测了哪些场景？（happy/error/boundary/concurrent）
  - 缺哪些场景？
  - 优先级 P0~P3

P0: 完全没测
P1: 只测 happy path，缺错误路径
P2: 测试了主要路径，缺分支覆盖
P3: 缺边界条件

## 维度 2: 现有测试质量
对每个测试评估:
  - 断言强度: EXPECT_TRUE(true) 这种零分；EXPECT_EQ(具体值) 满分
  - 隔离度: 是否依赖测试顺序、全局状态
  - 命名: 是否清晰表达意图
  - 维护性: 是否过于脆弱（硬编码、magic number）

## 维度 3: 冗余检测
- 多个测试测同一个场景 → 合并
- 多个相似输入的独立测试 → 改参数化

# 输出
JSON 格式，按 P0→P3 排序的缺口列表 + 每个缺口的修复建议
对 P0/P1 缺口要给出具体的 gtest code sketch（不要完整代码，只给关键骨架）

# 禁止
- 不要建议测试 trivial getter/setter
- 不要建议测试 private 方法
- 不要建议"提高覆盖率"这种空话
- 不要给出无法编译的 code sketch
```

---

## 实战示例

### 场景：接手遗留项目，先体检

```
# 你说：
ut-gap-filler，分析 tests/unit/order_test.cpp 和 src/order.cpp。
告诉我现有 15 个测试质量怎么样，缺什么。

# AI 输出：
{
  "existing_tests": {
    "total": 15,
    "strong": 6,
    "weak": 7,
    "redundant": 2
  },
  "p0_gaps": [
    "RefundOrder 方法完全没测",
    "CancelOrder 错误路径没测"
  ],
  "weak_tests": [
    "TestOrder 这种名字应改为 CreateOrder_ShouldXxx",
    "几个测试用 sleep(100) 等异步，应改为 future.wait()"
  ],
  "redundant": [
    "TestAdd1/2/3 应合并为 TEST_P 参数化"
  ]
}
```

### 场景：覆盖率上不去

```
# 你说：
ut-gap-filler，覆盖率卡在 75% 上不去，分析下原因。
报告在 coverage.json，源在 src/，测试在 tests/。

# AI 会:
1. 读 coverage.json 找未覆盖行
2. 反向追溯：这些行属于哪个函数
3. 看现有测试覆盖了哪些函数
4. 输出: "未覆盖的多是错误路径和异常处理，
        建议补 12 个测试可以提到 88%"
```

### 场景：线上出了 bug

```
# 你说：
ut-gap-filler，刚修了一个 bug（提交 abc123），
分析为啥之前的测试没抓到，建议补什么测试。

# AI 会:
1. git show abc123 看改了啥
2. 读相关测试文件
3. 分析: "改动在 payment.cpp:67-89，
         测试覆盖了 happy path 但没测
         金额为负数的边界。建议补 TEST_F(PaymentTest,
         RejectsNegativeAmount)"
```

---

## 注意事项

1. **不要相信"我已经测过了"** —— AI 看到 TEST_F 不代表实际覆盖到，要看断言
2. **大文件分模块分析** —— 一次别喂超过 1000 行的测试代码
3. **配合 mutation testing** —— mull-cxx 给的"假阳性测试"列表是 ut-gap-filler 的金矿
4. **删除建议要谨慎** —— AI 觉得冗余的测试可能有你不知道的历史原因
5. **优先级要倒着看** —— 先解决 P0，P3 可以延后
