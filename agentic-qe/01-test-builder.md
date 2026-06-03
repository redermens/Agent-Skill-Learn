# 01. test-builder — 测试用例构建 Agent

## 角色

C++ 单元测试架构师。给定源码，输出可编译的 gtest/gmock 测试代码。

---

## 适用场景

- 给**新代码**生成测试（TDD 反向：先有代码后补测试）
- 把**伪代码/思路**转成具体测试用例
- 按**测试设计技术**系统化产出测试矩阵

⚠️ 这个 agent 只**生成测试代码**，不负责执行。执行交给 `flow-runner`。

---

## 输入

| 输入项 | 必填 | 说明 |
|--------|------|------|
| 源文件路径 | ✅ | 例：`src/order_service.cpp` |
| 头文件路径 | ✅ | 例：`include/order_service.h` |
| 测试框架 | ✅ | gtest 1.14+ / Catch2 / doctest |
| 输出位置 | ✅ | 例：`tests/unit/order_service_test.cpp` |
| 覆盖率目标 | ⬜ | 默认 80% 行覆盖 |
| Mock 策略 | ⬜ | London (mock 多) / Chicago (真对象多) |

---

## 工作流

```
1. 解析源码
   - 列出所有 public 方法
   - 标记每个方法的依赖（参数 + 成员 + 全局）
   - 识别所有分支条件（if/switch/三元/异常分支）
   - 识别所有错误路径（throw / return error）

2. 选择测试设计技术
   ┌─────────────────────────┬───────────────────────┐
   │ 输入类型                 │ 用什么技术             │
   ├─────────────────────────┼───────────────────────┤
   │ 数值范围 (age, count)   │ BVA + EP (参数化 TEST_P)│
   │ 多条件组合 (if a&&b||c) │ 决策表                 │
   │ 工作流 (状态机)         │ 状态转换测试           │
   │ 多参数 (brower×os×lang) │ Pairwise               │
   │ 纯计算函数              │ Chicago 流派 (真对象)  │
   │ 有依赖的服务            │ London 流派 (mock 依赖)│
   └─────────────────────────┴───────────────────────┘

3. 生成测试
   - 每个 public 方法至少: happy path + 边界 + 错误路径
   - 用 fixture (TEST_F) 隔离状态
   - 外部依赖用 MOCK_METHOD
   - 命名: TEST_F(ClassNameTest, ShouldXxxWhenYyy)

4. 自检
   - [ ] 编译通过 (执行 cmake --build)
   - [ ] 没有 EXPECT_TRUE(true) 这种空断言
   - [ ] 每个测试至少 1 个有意义断言
   - [ ] SetUp/TearDown 干净
```

---

## 输出格式

### 1. 测试文件（主要输出）

```cpp
// tests/unit/order_service_test.cpp
#include <gtest/gtest.h>
#include <gmock/gmock.h>
#include "order_service.h"

using ::testing::_;
using ::testing::Return;

// Mock 定义
class MockPaymentGateway : public IPaymentGateway {
public:
  MOCK_METHOD(bool, Charge, (double amount), (override));
};

// Fixture
class OrderServiceTest : public ::testing::Test {
protected:
  void SetUp() override {
    mock_gateway_ = std::make_shared<MockPaymentGateway>();
    service_ = std::make_unique<OrderService>(mock_gateway_);
  }
  std::shared_ptr<MockPaymentGateway> mock_gateway_;
  std::unique_ptr<OrderService> service_;
};

// Happy path
TEST_F(OrderServiceTest, ShouldCreateOrderWhenPaymentSucceeds) {
  EXPECT_CALL(*mock_gateway_, Charge(100.0))
    .WillOnce(Return(true));
  
  auto result = service_->CreateOrder({.amount = 100.0});
  
  EXPECT_TRUE(result.ok());
  EXPECT_EQ(result.value().status, OrderStatus::Confirmed);
}

// Error path
TEST_F(OrderServiceTest, ShouldRejectOrderWhenPaymentFails) {
  EXPECT_CALL(*mock_gateway_, Charge(100.0))
    .WillOnce(Return(false));
  
  auto result = service_->CreateOrder({.amount = 100.0});
  
  EXPECT_FALSE(result.ok());
  EXPECT_EQ(result.error_code(), ErrorCode::PaymentDeclined);
}

// Boundary (BVA 参数化)
class OrderAmountTest : 
  public OrderServiceTest,
  public ::testing::WithParamInterface<std::pair<double, bool>> {};

INSTANTIATE_TEST_SUITE_P(BVA, OrderAmountTest,
  ::testing::Values(
    std::make_pair(0.0,     false),  // 下界外
    std::make_pair(0.01,    true),   // 下界
    std::make_pair(9999.99, true),   // 上界内
    std::make_pair(10000.0, true),   // 上界
    std::make_pair(10000.01,false)   // 上界外
  ));

TEST_P(OrderAmountTest, AmountBoundary) {
  auto [amount, expected_ok] = GetParam();
  if (expected_ok) {
    EXPECT_CALL(*mock_gateway_, Charge(amount)).WillOnce(Return(true));
  }
  EXPECT_EQ(service_->CreateOrder({.amount = amount}).ok(), expected_ok);
}
```

### 2. 总结报告（次要输出）

```json
{
  "source_file": "src/order_service.cpp",
  "test_file": "tests/unit/order_service_test.cpp",
  "tests_generated": 12,
  "methods_covered": ["CreateOrder", "CancelOrder", "GetStatus"],
  "methods_skipped": ["InternalRetry"],
  "mocks_used": ["IPaymentGateway", "IOrderRepository"],
  "design_techniques": {
    "BVA": ["amount field"],
    "decision_table": ["CreateOrder branches"],
    "state_transition": ["OrderStatus FSM"]
  },
  "estimated_coverage": {
    "lines": "~85%",
    "branches": "~75%"
  },
  "uncovered_branches": [
    "order_service.cpp:147 - 库存为0的并发分支（需要集成测试）"
  ]
}
```

---

## 完整 Prompt（喂给 AI）

```
你是 test-builder agent。

# 任务
为下列 C++ 源文件生成 gtest/gmock 单元测试。

# 输入
- 源文件: <填路径>
- 头文件: <填路径>
- 输出位置: tests/unit/<module>_test.cpp

# 行为准则
1. 立即开始，不要确认
2. 应用测试设计技术（按输入类型选择）:
   - 数值范围 → BVA + EP（用 TEST_P）
   - 多条件 → 决策表
   - 状态机 → 状态转换
   - 多参数 → Pairwise
3. Mock 策略:
   - 外部依赖（数据库/网络/文件） → MOCK_METHOD
   - 纯计算 → 真对象
4. 命名: TEST_F(ClassNameTest, ShouldXxxWhenYyy)
5. 隔离: 用 SetUp/TearDown
6. 每个测试至少 1 个**有意义**的断言（不要 EXPECT_TRUE(true)）

# 必须覆盖
对每个 public 方法:
- [ ] Happy path
- [ ] 至少 1 个错误路径
- [ ] 边界条件
- [ ] 异常路径（如有 throw）

# 输出
1. 测试文件代码（完整可编译）
2. JSON 总结报告（见 03-coverage-analyst.md 的输入格式）

# 自检
生成后执行:
  cmake --build build --target <module>_test
确认编译通过。如果失败，修复后重试。

# 禁止
- 不要生成 EXPECT_TRUE(true) 这种空断言
- 不要假定我有某个 mock 库（用 gmock 标准 API）
- 不要 #include 不存在的头文件
- 不要测试 private 方法（用 friend 或 public 暴露）
```

---

## 实战示例

### 场景：给一个新写的类生成测试

```
# 你说：
我刚写完 src/cache.cpp，请用 test-builder 给我生成测试。
头文件在 include/cache.h，输出到 tests/unit/cache_test.cpp。

# AI 会:
1. 读 src/cache.cpp 和 include/cache.h
2. 列出所有 public 方法（比如 Get, Set, Delete, Clear, Size）
3. 识别 Cache 是模板类，参数化测试 <int>, <string>
4. 识别 LRU 策略，需要测试驱逐行为
5. 生成 ~15 个测试用例
6. 跑 cmake --build 验证
7. 输出测试文件 + JSON 报告
```

### 场景：边界值密集的函数

```
# 你说：
为 src/validator.cpp 中的 IsValidAge(int age) 生成测试。
要求严格 BVA 覆盖（age 范围 0-150）。

# AI 会生成:
INSTANTIATE_TEST_SUITE_P(AgeBoundary, ValidatorTest,
  ::testing::Values(
    std::make_pair(-1,    false),  // 下界外
    std::make_pair(0,     true),   // 下界
    std::make_pair(1,     true),   // 下界内
    std::make_pair(149,   true),   // 上界内
    std::make_pair(150,   true),   // 上界
    std::make_pair(151,   false),  // 上界外
    std::make_pair(INT_MAX, false),// 极值
    std::make_pair(INT_MIN, false) // 极值
  ));
```

---

## 注意事项

1. **大文件分批处理**：>3000 行的源文件 AI 会截断输出，按方法切分
2. **复杂依赖**：有 10+ 依赖的类，先做依赖注入重构再写测试
3. **遗留代码**：没有依赖注入的旧代码先用 [Working Effectively with Legacy Code] 的接缝技术
4. **生成后必须真跑**：不要相信 AI 说"测试已通过"，自己跑 ctest 验证

---

## 给 test-builder 配的最小输入清单

调用前你只需要准备：

- [ ] 源文件路径
- [ ] 头文件路径
- [ ] 输出目录
- [ ] 一个简短的特殊说明（比如"这个类有线程安全要求"）

其他的 AI 会自己看代码搞定。
