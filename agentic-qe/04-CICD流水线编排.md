# 04. CI/CD 流水线编排 (Sequential Pipeline)

## 核心 Skill: cicd-pipeline-qe-orchestrator

agentic-qe **顺序流水线**的官方实践指南，分 5 个阶段。

---

## 五阶段模型（核心）

```
┌──────────┐   ┌────────┐   ┌─────────┐   ┌────────┐   ┌────────────┐
│ Commit   │→  │ Build  │→  │  Test   │→  │Staging │→  │ Production │
│Shift-Left│   │        │   │Integ.   │   │        │   │Shift-Right │
└──────────┘   └────────┘   └─────────┘   └────────┘   └────────────┘
   60s            5min         15min         30min       持续运行
```

### Phase ↔ Agent 矩阵

| 阶段 | 主力 Agent | 关键 Skill | 阻塞门禁 |
|------|-----------|-----------|---------|
| **Commit** | qe-test-generator, qe-requirements-validator | tdd-london-chicago, shift-left | 单元覆盖 > 80% |
| **Build** | qe-test-executor, qe-coverage-analyzer, qe-flaky-test-hunter | test-automation, mutation-testing | 全测试通过 |
| **Test** | qe-api-contract-validator, qe-performance-tester, qe-security-scanner | api-testing, performance, security | 无破坏性变更, p95<200ms, 0 严重漏洞 |
| **Staging** | qe-chaos-engineer, qe-visual-tester, qe-deployment-readiness | chaos, accessibility | Readiness > 85% |
| **Production** | qe-production-intelligence, qe-quality-analyzer | shift-right, compliance | 错误率 < 0.1% |

---

## 完整流水线示例（原文）

```javascript
// Phase 1: Commit
Task("TDD Generation", "Generate tests for new features", "qe-test-generator")
Task("Requirements", "Validate BDD scenarios", "qe-requirements-validator")

// Phase 2: Build
Task("Execute Tests", "Full suite with coverage", "qe-test-executor")
Task("Coverage", "Analyze gaps", "qe-coverage-analyzer")
Task("Flaky Hunt", "Stabilize flaky tests", "qe-flaky-test-hunter")

// Phase 3: Integration
Task("API Contracts", "Check breaking changes", "qe-api-contract-validator")
Task("Performance", "1000 user load test", "qe-performance-tester")
Task("Security", "SAST/DAST scans", "qe-security-scanner")

// Phase 4: Staging
Task("Chaos", "Fault injection testing", "qe-chaos-engineer")
Task("Visual", "Visual regression", "qe-visual-tester")
Task("Readiness", "Deployment assessment", "qe-deployment-readiness")

// Phase 5: Production
Task("Intelligence", "Convert incidents", "qe-production-intelligence")
Task("Quality Gate", "Final validation", "qe-quality-gate")
```

**Task() 是 Claude Code 的内置工具**，第一个参数是任务名，第二个是 prompt，第三个是 agent 类型。

---

## 质量门禁配置（关键设计）

```json
{
  "commit": {
    "gates": [
      { "metric": "unit_coverage", "threshold": 80, "blocking": true },
      { "metric": "static_analysis_critical", "max": 0, "blocking": true }
    ]
  },
  "build": {
    "gates": [
      { "metric": "all_tests_passed", "threshold": 100, "blocking": true },
      { "metric": "mutation_score", "threshold": 70, "blocking": false }
    ]
  },
  "integration": {
    "gates": [
      { "metric": "api_breaking_changes", "max": 0, "blocking": true },
      { "metric": "performance_p95_ms", "threshold": 200, "blocking": true },
      { "metric": "security_critical", "max": 0, "blocking": true }
    ]
  }
}
```

**核心字段**:
- `blocking: true` → 失败则阻塞合并
- `blocking: false` → 警告但不阻塞
- `threshold` / `max` / `min` → 阈值类型

---

## 顺序流水线 vs 并行执行

```
顺序（sequential）—— 阶段间有依赖
   Commit → Build → Test → Staging → Production

并行（parallel）—— 阶段内的 agent
   Phase 3 (Integration):
     ├── API Contracts    ┐
     ├── Performance Test ┼── 同时跑
     └── Security Scan    ┘
```

**经验**: 阶段间**严格顺序**（前阶段失败立刻停），阶段内**最大并行**。

---

## 自适应策略（按风险调整）

| 风险等级 | 策略 | Agent 数量 |
|---------|------|-----------|
| Critical | 全阶段 + 手动审批 | 全套（40+） |
| High | 自动门禁 + 全面测试 | 10+ |
| Medium | 智能选择 + 风险驱动 | 5-8 |
| Low | 最小回归 + 快速反馈 | 2-3 |

**判断风险的输入**: PR 改动行数 / 修改的文件路径 / 业务模块标签 / 历史 bug 集中度。

### 按应用类型选择重点

| 应用类型 | 重点 Skill | 主力 Agent |
|---------|-----------|-----------|
| API | api-testing, contract, performance | api-contract-validator, performance-tester |
| Web UI | visual-testing, accessibility | visual-tester, accessibility |
| Mobile | mobile-testing, compatibility | performance-tester, visual-tester |
| **Backend (C++ 多半属于这类)** | database-testing, security | security-scanner, performance-tester |

---

## 阶段间事件通信 (Blackboard Events)

agentic-qe 设计的阶段间事件：

| 事件 | 触发时机 | 订阅者 |
|------|---------|--------|
| `phase:commit:complete` | Commit 阶段完成 | Build 阶段的 agents |
| `coverage:gap:detected` | 发现覆盖缺口 | qe-test-generator |
| `security:finding:critical` | 严重漏洞 | qe-quality-gate |
| `quality:gate:evaluated` | 门禁判定完成 | qe-fleet-commander |

**实现机制**: 共享内存命名空间 `aqe/pipeline/*`（详见 05 章）

---

## C++/gtest 顺序流水线模板（GitHub Actions）

```yaml
name: C++ QE Pipeline
on: [push, pull_request]

jobs:
  # ========== Phase 1: Commit (Shift-Left) ==========
  static-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: clang-tidy
        run: |
          cmake -B build && \
          run-clang-tidy -p build src/ > clang-tidy-report.txt
      - name: cppcheck
        run: cppcheck --enable=all --error-exitcode=1 src/
      # 门禁：无 critical static issue

  # ========== Phase 2: Build ==========
  build:
    needs: static-check
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Configure (with coverage)
        run: cmake -B build -DCMAKE_BUILD_TYPE=Debug -DCODE_COVERAGE=ON
      - name: Build
        run: cmake --build build -j$(nproc)
      - uses: actions/cache/save@v4
        with:
          path: build
          key: build-${{ github.sha }}

  # ========== Phase 2.5: Unit Tests + Coverage ==========
  unit-test:
    needs: build
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/cache/restore@v4
        with: { path: build, key: build-${{ github.sha }} }
      - name: Run unit tests
        run: ctest --test-dir build -L unit -j$(nproc) --output-on-failure
      - name: Coverage
        run: |
          lcov --capture --directory build --output-file coverage.info
          lcov --list coverage.info
      - uses: codecov/codecov-action@v4
      # 门禁：测试全过 + 覆盖率 > 80%

  # ========== Phase 3: Integration ==========
  integration-test:
    needs: unit-test
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:15
    steps:
      - name: Run integration tests
        run: ctest --test-dir build -L integration --output-on-failure
      # 门禁：集成测试全过

  # ========== Phase 3.5: Quality Scans (并行) ==========
  security-scan:
    needs: build
    runs-on: ubuntu-latest
    steps:
      - name: SAST with cppcheck + flawfinder
        run: |
          flawfinder --error-level=4 src/
      # 门禁：0 严重漏洞

  performance-test:
    needs: build
    runs-on: ubuntu-latest
    steps:
      - name: Google Benchmark
        run: ./build/benchmarks --benchmark_format=json > bench.json
      - name: Compare with baseline
        run: |
          python compare_bench.py baseline.json bench.json --threshold 5
      # 门禁：性能退化 < 5%

  # ========== Phase 4: Staging (手动触发) ==========
  staging-deploy:
    needs: [integration-test, security-scan, performance-test]
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    steps:
      - name: Deploy to staging
        run: ./deploy.sh staging
      - name: Smoke test
        run: ./tests/smoke/run.sh staging
```

---

## 故障排查表

| 症状 | 原因 | 解决 |
|------|------|------|
| 测试时 OOM | 全套并行跑 | 改成分批执行 |
| 流水线太慢 | 每个 commit 都跑全套 | 智能测试选择 |
| 门禁老是失败 | 阈值太严 | 看趋势再调整 |

---

## 给你的实操建议

1. **从 5 阶段简化版开始**：Commit (静态分析) → Build → Unit Test → Integration → Staging
2. **门禁要"先警告再阻塞"**：新阈值上线先 warning 一周，看实际数据再开 blocking
3. **关键阶段并行，关键阶段间顺序**：阶段内能并行就并行
4. **每个阶段都要有 artifact**：报告、日志、coverage 数据都要存
5. **手动 staging 部署**：production 流量大，不要 push 即部署
