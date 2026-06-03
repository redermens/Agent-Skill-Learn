# 03. coverage-analyst — 覆盖率报告分析 Agent

## 角色

读取 gcov/lcov 生成的 HTML 报告（或 lcov.info 文本），输出可执行的"补哪些测试"建议清单。

## 适用场景

- CI 跑完测试后，把 `coverage/index.html` 喂给它，让它告诉你**最该补的 10 个测试**
- PR review 时，分析 diff coverage（新代码 vs 整体）
- 周报数据：覆盖率趋势 + 高风险未覆盖热点

⚠️ agentic-qe **原生没有这个 agent**，是我按你的需求新设计的（参考 qe-coverage-analysis 的方法论）。

---

## 输入：三种格式

### 格式 1：lcov HTML 报告（最常见）

```
coverage/
├── index.html           ← 总入口
├── amber.png
├── gcov.css
├── src/
│   ├── index.html       ← src 目录覆盖率
│   ├── order_service.cpp.gcov.html  ← 单文件详细报告
│   └── ...
```

你给 AI 喂 `coverage/index.html` 即可，它会自动跟进单文件页面。

### 格式 2：lcov.info 文本（更精确）

```
SF:src/order_service.cpp
FN:10,Order::AddItem
FNDA:5,Order::AddItem
DA:10,5
DA:12,0          ← 第 12 行未覆盖
BRDA:15,0,0,3
BRDA:15,0,1,0    ← 第 15 行分支 1 未覆盖
end_of_record
```

### 格式 3：gcovr JSON（最易解析）

```bash
gcovr -r . --json -o coverage.json
```

推荐用 JSON，结构化最清晰。

---

## 工作流

```
1. 读取报告（HTML / lcov.info / JSON 都支持）

2. 提取未覆盖点
   - 未覆盖的行号
   - 未覆盖的分支（最重要）
   - 未调用的函数

3. 风险加权打分
   对每个未覆盖点计算风险分：
   
   risk = complexity * 0.30      ← 圈复杂度（用 lizard 拿）
        + change_freq * 0.25     ← git log 近 90d 改动次数
        + bug_density * 0.25     ← git log --grep="^fix" 提及次数
        + criticality * 0.20     ← 看路径/注释关键词

4. 生成补测建议
   - 按风险分排序
   - 对前 N 个输出具体的 gtest 用例思路
   - 标注这个用例需要 mock 什么

5. 趋势对比
   - 读上次运行结果（.aqe/coverage/history.json）
   - 计算 delta，连续下降报警
```

---

## 阈值参考表

| 模块类型 | 行覆盖 | 分支覆盖 | 函数覆盖 | 说明 |
|---------|--------|---------|---------|------|
| 关键业务 | ≥ 90% | ≥ 85% | ≥ 95% | payment, auth, billing |
| 核心逻辑 | ≥ 80% | ≥ 70% | ≥ 90% | service, model |
| 工具代码 | ≥ 70% | ≥ 60% | ≥ 80% | utils, helpers |
| 第三方/生成 | 豁免 | 豁免 | 豁免 | third_party/, *_generated.cpp |

---

## 输出格式（JSON）

```json
{
  "timestamp": "2026-06-04T10:30:00Z",
  "summary": {
    "lines":     { "covered": 1234, "total": 1447, "percentage": 85.3 },
    "branches":  { "covered": 892,  "total": 1237, "percentage": 72.1 },
    "functions": { "covered": 456,  "total": 505,  "percentage": 90.2 }
  },
  "trend": {
    "vs_last_run": -1.2,
    "consecutive_drops": 2,
    "alert": false
  },
  "top_priority_gaps": [
    {
      "rank": 1,
      "file": "src/payment.cpp",
      "function": "ProcessRefund",
      "uncovered_lines": [45, 67, "89-93"],
      "uncovered_branches": [{"line": 56, "branch": "else (amount < 0)"}],
      "risk_score": 87,
      "risk_breakdown": {
        "complexity": 12,
        "change_freq_90d": 5,
        "bug_count_180d": 2,
        "criticality": "high (payment domain)"
      },
      "suggested_tests": [
        "测试退款金额为负数时的返回值",
        "测试 payment gateway 超时时的回滚逻辑",
        "测试部分退款的状态转移"
      ],
      "mocks_needed": ["IPaymentGateway", "ITransactionLog"]
    }
  ],
  "low_priority_gaps": {
    "count": 47,
    "summary": "多为打印函数、to_string 等辅助代码"
  }
}
```

---

## 完整 Prompt（喂给 AI）

```
你是 coverage-analyst agent。

# 任务
分析覆盖率报告，输出按风险加权排序的补测建议。

# 输入
- 报告路径: <coverage/index.html 或 lcov.info 或 coverage.json>
- 源码根目录: <src/>
- 历史文件: .aqe/coverage/history.json（可选）

# 处理步骤
1. 解析报告，提取总览指标 + 每个文件的未覆盖明细
2. 对每个未覆盖点计算风险分:
   - 圈复杂度 (lizard 或 AI 自己估)        × 0.30
   - git log --since=90.days 改动次数      × 0.25
   - git log --grep="^fix" 提及次数         × 0.25
   - 业务关键度 (路径/注释/// CRITICAL)    × 0.20
3. 按风险分排序，取前 10 输出
4. 对前 5 个生成具体 gtest 用例思路（不写代码，写测试意图）
5. 读 history.json，计算趋势
6. 写入 .aqe/coverage/latest.json
7. 追加到 .aqe/coverage/history.json

# 输出
JSON 格式，结构见文档

# 警告规则
- 连续 3 次下降 → 输出 ⚠️ ALERT
- 整体覆盖率 < 70% → 警告
- 高分支覆盖差距（line 90%+ 但 branch <70%） → 提示加边界测试

# 禁止
- 不要给"提高覆盖率"这种废话建议
- 不要建议测试 trivial getter/setter
- 不要把第三方代码算进去
```

---

## 实战示例：分析 lcov HTML 报告

```
# 你说：
coverage-analyst，分析 build/coverage/index.html，
告诉我最该补的 5 个测试。

# AI 会:
1. 打开 build/coverage/index.html，读总览
2. 找到覆盖率最低的几个文件，打开它们的 .gcov.html
3. 提取未覆盖的行和分支
4. 对每个未覆盖点跑风险加权
5. 输出 top 5 + 具体测试思路

# 输出示例：
{
  "summary": {
    "lines": "82.4%",
    "branches": "68.1%",
    "functions": "91.3%"
  },
  "trend": "比上次 -1.5%，⚠️ 连续 2 次下降",
  "top_5_priority_gaps": [
    {
      "rank": 1,
      "file": "src/order/refund.cpp",
      "issue": "ProcessRefund 函数 line 45-67 完全未覆盖",
      "risk_score": 92,
      "why_high_risk": "退款是关键路径，近 30 天改了 8 次，圈复杂度 14",
      "suggested_tests": [
        "Test_RefundFullAmount_Succeeds",
        "Test_RefundPartial_StateTransition",
        "Test_RefundExceedsOriginal_Rejected",
        "Test_GatewayTimeout_RollsBack"
      ],
      "mocks_needed": ["IPaymentGateway", "ITransactionLog"]
    },
    ...
  ]
}
```

---

## HTML 报告解析 tips

### lcov 生成的 HTML 结构

```html
<table class="overall">
  <tr class="overall">
    <td>Lines:</td>
    <td>1234 / 1447</td>
    <td>85.3 %</td>
  </tr>
</table>
```

让 AI 用 BeautifulSoup / cheerio 解析，或直接让大模型读 HTML 文本（小报告可行，大报告会爆 token）。

### gcov 生成的 HTML（更复杂）

```html
<pre class="source">
   12  :    if (amount &lt; 0) {              ← 命中 12 次
   ####:        return Error::InvalidAmount;  ← #### 表示未命中
   ...
</pre>
```

`####` 是 gcov 的"未命中"标记。让 AI 识别这个即可。

### 推荐做法：先转 JSON

```bash
# 别让 AI 直接读 HTML，先转 JSON 再分析
gcovr -r . --json -o coverage.json
# 或
lcov --list coverage.info > coverage.txt
```

然后把 JSON/txt 喂 AI，token 消耗小一个数量级。

---

## 给 C++ 项目的完整配套脚本

```bash
#!/bin/bash
# scripts/coverage-analyze.sh
set -e

# 1. 生成覆盖率数据（假设已经跑过测试）
cd build
lcov --capture --directory . --output-file coverage.info
lcov --remove coverage.info '/usr/*' '*/tests/*' '*/third_party/*' \
  --output-file coverage.info

# 2. HTML 报告
genhtml coverage.info --output-directory coverage_html

# 3. JSON 报告（给 AI 用）
gcovr -r .. --json --json-pretty -o ../coverage.json

# 4. 调用 AI agent
cd ..
claude -p "请按 D:\WorkSpace\learning\agentic-qe\03-coverage-analyst.md 的角色定义，
分析 coverage.json，输出补测建议 JSON 到 .aqe/coverage/latest.json"

# 5. 显示报告
cat .aqe/coverage/latest.json | jq '.top_priority_gaps[:5]'
```

---

## 注意事项

1. **HTML 报告可能很大** —— 优先用 JSON/lcov.info 文本格式喂 AI
2. **风险分需要 git 历史** —— shallow clone 会拿不到改动频率
3. **圈复杂度工具**：[lizard](https://github.com/terryyin/lizard)（Python，支持 C++）
4. **不要每次都全量分析** —— PR 维度做差分覆盖（diff coverage）更有用
5. **高覆盖 ≠ 高质量** —— 配合 mutation testing（mull-cxx）验证测试有效性
