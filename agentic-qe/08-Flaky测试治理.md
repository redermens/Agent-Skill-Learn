# 08. Flaky 测试治理

> Flaky test = 时好时坏的测试。它是自动化测试**最阴险的敌人**，比直接失败更糟。

---

## 为什么 Flaky 测试是 P0 问题

| 影响 | 后果 |
|------|------|
| 团队信任崩塌 | "测试又挂了，retry 一下吧" → 真 bug 被忽略 |
| CI 浪费时间 | 平均每个 PR 多 2-3 次 retry |
| Debug 困难 | 复现率低，定位成本高 |
| 隐藏并发问题 | 表现为 flaky，本质是 race condition |

agentic-qe 宣称把 flaky 率从 **8-12% 降到 0.3%**，CI 可靠性从 **92% 提升到 99.7%**。

---

## Flaky 测试的五类根因

| 类型 | 症状 | 典型例子 |
|------|------|---------|
| **时序问题** | 有时早有时晚 | `sleep(100)` 不够、缺等待 |
| **状态泄漏** | 顺序依赖 | 上一个测试改了全局状态 |
| **资源竞争** | 多线程偶现 | Race condition、死锁 |
| **环境依赖** | 本地过 CI 挂 | 时区、locale、文件路径 |
| **网络/IO** | 远程不可控 | 真实 HTTP 调用、DNS 抖动 |

---

## Flaky Hunter Agent 的能力

**qe-flaky-hunter** 是专门治理 flaky 的 agent：

```typescript
const flakyHunter = await fleet.spawnAgent('flaky-test-hunter', {
  proactive: {
    analyzePatterns: true,
    predictFailures: true,
    preventBefore: 'production'
  }
});

await flakyHunter.execute({
  lookback: '30-days',     // 看过去 30 天的运行
  confidence: 0.85,        // 85% 统计置信度才标记
  autoFix: true            // 自动应用修复策略
});
```

**关键设计**：用**统计学方法**而非单次失败来判定 flaky。

### 检测算法

```python
def is_flaky(test_history, threshold=0.95):
    """
    test_history: 最近 N 次运行结果列表 [True, True, False, True, ...]
    threshold: 置信度
    
    判定: 失败率 ∈ (0, 1) 且统计显著
    """
    n = len(test_history)
    fail_rate = sum(1 for r in test_history if not r) / n
    
    # 既不是全过(稳定)也不是全失败(真坏)
    if 0.01 < fail_rate < 0.5:
        # 二项检验，置信度判断
        from scipy.stats import binomtest
        result = binomtest(sum(r for r in test_history), n, p=0.5)
        if result.pvalue < (1 - threshold):
            return True
    return False
```

---

## 检测 → 隔离 → 修复 三步法

### Step 1: 检测

```bash
# 配置 (原文)
detection:
  enabled: true
  threshold: 0.1      # 失败率 > 10% 即标记
  window: 100         # 看最近 100 次
```

**C++/gtest 实现**:

```bash
# 跑测试 N 次，统计每个测试的失败率
for i in {1..20}; do
  ./my_test --gtest_output=xml:result_$i.xml
done

# Python 脚本聚合
python detect_flaky.py result_*.xml --threshold 0.1
```

### Step 2: 隔离

发现 flaky 立即从主套件移到 quarantine：

```cpp
// 方法 1: DISABLED_ 前缀（gtest 原生）
TEST(MyTest, DISABLED_FlakyTest) {  // INC-123: 待修复
  // ...
}

// 方法 2: 条件跳过
TEST(MyTest, ConditionalFlaky) {
  if (std::getenv("RUN_FLAKY") == nullptr) {
    GTEST_SKIP() << "Quarantined: INC-123";
  }
  // ...
}

// 方法 3: 单独 label
add_test(NAME flaky_test_1 COMMAND ...)
set_tests_properties(flaky_test_1 PROPERTIES LABELS "flaky")

# CI 默认跳过
ctest -LE flaky
```

### Step 3: 修复

**重试策略**（治标）:

```cpp
// gtest 自带 --gtest_repeat
./my_test --gtest_repeat=3 --gtest_filter=FlakyTest*

// 或者在测试代码里 retry
TEST(NetworkTest, GetData) {
  for (int retry = 0; retry < 3; ++retry) {
    auto result = FetchData();
    if (result.ok()) {
      EXPECT_EQ(result.value(), "expected");
      return;
    }
    std::this_thread::sleep_for(std::chrono::seconds(1));
  }
  FAIL() << "Failed after 3 retries";
}
```

**根治策略**（治本）:

| 根因 | 修复 |
|------|------|
| 时序 | 用 condition variable / future，不要 sleep |
| 状态泄漏 | SetUp/TearDown 清理，禁用全局变量 |
| 资源竞争 | 加锁、用 ThreadSanitizer 排查 |
| 环境依赖 | 容器化 + 固定 locale/时区 |
| 网络 IO | Mock + WireMock |

---

## ⚠️ 2 周 SLA 原则

```
隔离 → 设置 due date 2 周
↓
2 周内未修复 → 删掉
↓
保留 flaky test 是技术债，删比留好
```

**原文档原话**:
> Flaky tests quarantined but never fixed is technical debt — 
> set a 2-week SLA to fix or delete

---

## CI/CD 集成

### Flaky 仪表盘

```typescript
interface FlakyReport {
  testId: string;
  flakeRate: number;            // 失败率
  lastFailed: Date;
  occurrences: number;
  rootCause: 'timing' | 'state' | 'race' | 'env' | 'network';
  fixSuggestion: string;
  quarantineAge: number;        // 隔离天数
  slaStatus: 'within' | 'overdue';
}
```

### GitHub Actions 示例

```yaml
flaky-detection:
  runs-on: ubuntu-latest
  steps:
    - name: Run tests 10 times
      run: |
        for i in {1..10}; do
          ./build/tests --gtest_output=xml:run_$i.xml || true
        done
    
    - name: Detect flaky
      run: python detect_flaky.py run_*.xml > flaky_report.json
    
    - name: Comment on PR
      uses: actions/github-script@v7
      with:
        script: |
          const report = require('./flaky_report.json');
          if (report.newFlaky.length > 0) {
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: `⚠️ 检测到新 flaky 测试:\n${report.newFlaky.join('\n')}`
            });
          }
```

---

## Flaky Test 给 C++ 项目的实操清单

### 立即可做

1. ✅ **跑 10 次取并集** —— 发现现有 flaky 测试
2. ✅ **建立 quarantine 机制** —— DISABLED_ 前缀 + issue 追踪
3. ✅ **CI 上跑测试 3 次** —— 不退 retry，3 次都过才算稳定

### 中期改进

4. ✅ **统计学检测** —— 写脚本看历史数据
5. ✅ **每周生成 flaky 报告** —— 团队周会过一遍
6. ✅ **2 周 SLA** —— Quarantine 时设 due date

### 长期建设

7. ⚠️ **变异测试验证测试质量** —— mull-cxx
8. ⚠️ **ThreadSanitizer / AddressSanitizer** —— 抓 race condition
9. ⚠️ **Mock 所有外部依赖** —— 网络/数据库/文件

---

## 反模式

| ❌ 反模式 | 💀 后果 |
|---------|---------|
| 加 `sleep` 来"修" flaky | 治标不治本，下次环境变了又坏 |
| 设置无限重试 | 真 bug 被掩盖 |
| 把 flaky 注释掉但不删 | 永远不会被修，纯技术债 |
| 把 flaky 删掉，问题不查 | 失去了发现并发 bug 的机会 |
| 让 CI 忽略 flaky 失败 | 团队对测试失去信任 |

---

## 核心心得

> **Flaky 不是"测试问题"，是"代码问题的指示器"。**
> 
> 一个 flaky test 八成意味着：
> - 你的代码有 race condition
> - 你的代码对环境敏感
> - 你的测试边界不清晰
> 
> 修 flaky 测试 = 在修代码。**不要绕开它。**
