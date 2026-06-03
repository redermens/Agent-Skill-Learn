# 05. Agent 间通信机制

## 核心机制：共享内存命名空间 (Memory Namespace)

agentic-qe 的 agent 不直接互相调用，而是通过 **命名空间隔离的键值存储** 通信。

```
aqe/
├── test-generation/           ← qe-test-architect 的私有空间
│   ├── results/
│   ├── status/
│   └── outcomes/
│
├── coverage-analysis/         ← qe-coverage-specialist 的私有空间
│   ├── gaps/
│   └── reports/
│
├── pipeline/                  ← 流水线协调空间
│   ├── phase-results/         ← 阶段间传递结果
│   ├── quality-gates/
│   └── orchestration-plan/
│
├── swarm/                     ← 跨 agent 协作空间
│   └── test-gen/
│
└── v3/queen/                  ← Queen Coordinator 的全局空间
    ├── tasks/
    └── fleet/
```

---

## 命名空间的 R/W 权限设计

以 `qe-test-architect` 为例（原文）:

```
Reads (读取):
  - aqe/test-requirements/*               测试需求和约束
  - aqe/code-analysis/{MODULE}/*          代码复杂度和依赖分析
  - aqe/coverage-targets/*                覆盖率目标
  - aqe/learning/patterns/test-generation/*  历史成功模式

Writes (写入):
  - aqe/test-generation/results/*         生成的测试套件
  - aqe/test-files/{SUITE}/*              测试文件内容
  - aqe/coverage-analysis/*               预期覆盖结果
  - aqe/test-metrics/*                    生成性能指标

Coordination (协调):
  - aqe/test-generation/status/*          当前进度
  - aqe/swarm/test-gen/*                  跨 agent 协调
  - aqe/v3/queen/tasks/*                  Queen 任务队列
```

**核心设计原则**：
1. **私有写区**: 自己的命名空间只有自己写
2. **共享读区**: 大家都能读 learning 和 coverage-targets
3. **协调区**: swarm/* 是多 agent 共同读写的协作区
4. **任务队列**: queen/* 是顶层调度的入口

---

## CLI 操作示例

agentic-qe 提供了 `aqe memory` CLI:

```bash
# 写入
aqe memory store \
  --key "test-generation/outcome-2026-06-04" \
  --namespace "learning" \
  --value '{"coverage": 92, "duration": 8.2, "tests_generated": 42}' \
  --json

# 读取
aqe memory get \
  --key "test-generation/patterns" \
  --namespace "learning" \
  --json

# 搜索
aqe memory search \
  --query "queen orchestration patterns" \
  --namespace "learning" \
  --json
# semantic: true 时用 HNSW 向量搜索；否则是 glob 匹配

# 共享给其他 agent
aqe memory share \
  --key "coverage/gaps" \
  --target-agent qe-test-architect

# 用量统计
aqe memory usage

# 删除
aqe memory delete --key "outdated-pattern"
```

---

## 事件总线 (Event Bus)

除了 KV 存储，还有事件驱动通信。原文档提到的关键事件：

| 事件 | 触发源 | 订阅者 | 用途 |
|------|--------|--------|------|
| `phase:commit:complete` | qe-fleet-commander | Build 阶段 agents | 阶段间衔接 |
| `coverage:gap:detected` | qe-coverage-specialist | qe-test-architect | 触发补测 |
| `security:finding:critical` | qe-security-scanner | qe-quality-gate | 阻断流程 |
| `quality:gate:evaluated` | qe-quality-gate | qe-fleet-commander | 报告决策 |
| `task:completed` | 任意 agent | learning system | 学习更新 |

### 事件订阅模式（AQE Hooks 系统）

```typescript
class QEAgent extends BaseAgent {
  // 任务前：保存上下文到共享记忆
  protected async onPreTask(data: TaskData): Promise<void> {
    await this.memoryStore.store(`task/${this.id}/context`, data);
  }

  // 任务后：广播结果 + 学习到的模式
  protected async onPostTask(result: TaskResult): Promise<void> {
    await this.eventBus.emit('task:completed', {
      agentId: this.id,
      result: result,
      learnings: this.extractPatterns(result)
    });
  }

  // 任务出错：自动回滚
  protected async onTaskError(error: Error): Promise<void> {
    await this.rollbackManager.recover(this.id, error);
  }
}
```

**性能宣称**: 0.8ms 平均消息延迟，100-500x 快于 bash hook。

---

## 跨 Phase 信号 (Cross-Phase Signals)

QCSD (Quality-Centric Software Development) 反馈循环。

来自 `qe-test-architect` 原文的协议：

```typescript
// 启动时查询 operational 信号
const result = await aqe.memory.search({ json: true });

for (const signal of result.signals) {
  // 应用 flaky 模式学习
  if (signal.flakyPatterns) {
    for (const flaky of signal.flakyPatterns) {
      addAntiPattern(flaky.pattern, flaky.fix);
    }
  }
  
  // 应用反模式建议
  if (signal.recommendations?.antiPatterns) {
    applyAntiPatterns(signal.recommendations.antiPatterns);
  }
}
```

**信号流**:
- 生产者: `qe-quality-gate` (从 CI/CD 失败中学到的)
- 消费者: `qe-test-architect` (避免重蹈覆辙)
- 命名空间: `aqe/cross-phase/operational/test-health`

---

## 三种 Agent 协作拓扑

### 1. Hierarchical（层级 - 默认）

```
        Queen Coordinator
              │
   ┌──────────┼──────────┐
   │          │          │
 Test Gen  Coverage  Security
   │          │          │
 Sub1 Sub2  Sub1 Sub2  Sub1 Sub2
```

**适用**: 大多数场景。Queen 拆任务，下发给 domain coordinator，再下发给具体 agent。

### 2. Mesh（网状）

```
   Test Gen ←──→ Coverage
       ↑↘       ↗↑
       │  ╲   ╱  │
       │   ╳    │
       │  ╱  ╲  │
       ↓↙      ↘↓
   Security ←──→ Quality
```

**适用**: agent 之间频繁双向通信，例如 TDD 的红绿重构循环。

### 3. Sequential（顺序）

```
Test Gen → Test Exec → Coverage → Quality Gate
```

**适用**: 流水线场景，每个 agent 的输出是下一个的输入。

---

## C++ 项目的"轻量版" Agent 通信实现

如果你想自己搭，最小可行设计：

### 方案 1：基于文件系统 + JSON

```bash
project/
├── .aqe/
│   ├── memory/
│   │   ├── test-generation/
│   │   │   ├── results.json
│   │   │   └── status.json
│   │   ├── coverage/
│   │   │   └── gaps.json
│   │   └── pipeline/
│   │       └── phase-results.json
│   └── events/                 # 简单事件日志
│       └── 2026-06-04.jsonl
```

让多个 AI agent prompt 都遵守这套目录结构，相互读写。

### 方案 2：基于 SQLite

```python
# 轻量协调器
import sqlite3, json, time

conn = sqlite3.connect('.aqe/memory.db')
conn.execute('''
  CREATE TABLE IF NOT EXISTS memory (
    namespace TEXT, 
    key TEXT, 
    value TEXT,
    agent_id TEXT,
    timestamp INTEGER,
    PRIMARY KEY (namespace, key)
  )
''')
conn.execute('''
  CREATE TABLE IF NOT EXISTS events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    event_type TEXT,
    payload TEXT,
    source_agent TEXT,
    timestamp INTEGER
  )
''')

# Agent A 存
def store(namespace, key, value, agent_id):
    conn.execute('INSERT OR REPLACE INTO memory VALUES (?,?,?,?,?)',
                 (namespace, key, json.dumps(value), agent_id, int(time.time())))
    conn.commit()

# Agent B 读
def get(namespace, key):
    row = conn.execute('SELECT value FROM memory WHERE namespace=? AND key=?',
                       (namespace, key)).fetchone()
    return json.loads(row[0]) if row else None

# Event 发布订阅
def emit(event_type, payload, source):
    conn.execute('INSERT INTO events (event_type, payload, source_agent, timestamp) VALUES (?,?,?,?)',
                 (event_type, json.dumps(payload), source, int(time.time())))
    conn.commit()

def subscribe(event_type, since_ts):
    return conn.execute('SELECT * FROM events WHERE event_type=? AND timestamp>?',
                        (event_type, since_ts)).fetchall()
```

这就是个最小可用版本。agentic-qe 实际用的是 `better-sqlite3` + HNSW 向量索引，本质类似。

---

## 给你的设计建议

1. **命名空间隔离写权限** —— 每个 agent 只写自己的目录，避免互相覆盖
2. **共享读区放公共信息** —— learning patterns, coverage targets 等
3. **事件用 append-only 日志** —— 便于回放和调试
4. **重要状态写盘** —— 不要只放内存，session 崩溃会丢
5. **明确的 schema** —— 每个 namespace 的 value 结构要文档化，不然 agent 互相读不懂

---

## 最重要的一句话

> **多个 AI agent 协作的本质，是它们共享一个能读写的"白板"。**
> 
> Agent 不是直接 RPC 调用，而是：
> 1. A 把结果写到白板
> 2. B 从白板读取
> 3. 谁有新发现就广播事件
> 4. 想协调时去看共享的任务队列

这套范式在 C++ 项目里完全可以复制。不需要 agentic-qe 的 TS 内核。
