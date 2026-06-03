# 02. flow-runner — 流程执行 Agent

## 角色

按预定义的步骤序列执行测试，能驱动 shell 命令、HTTP 调用、**web 浏览器操作**。
是 agentic-qe 中 `e2e-flow-verifier` + `qe-browser` 两个 skill 的合体。

---

## 适用场景

| 场景 | 例子 |
|------|------|
| **CLI 工具的端到端测试** | 跑 `./mytool input.txt` 验证 stdout/退出码/输出文件 |
| **服务的 HTTP 接口测试** | 启动服务 → 发请求 → 验证响应 → 关服务 |
| **Web 网页流程测试** | 打开页面 → 登录 → 点按钮 → 验证跳转和文本 |
| **混合流程** | 启动后端 → 操作前端页面 → 验证后端日志 |

---

## 核心引擎：Vibium（agentic-qe 推荐）

### 为什么是 Vibium 不是 Playwright

| 维度 | Vibium | Playwright |
|------|--------|-----------|
| 安装大小 | ~10 MB | ~300 MB |
| 协议 | WebDriver BiDi (W3C 标准) | CDP (Chrome 私有) |
| 跨浏览器 | Firefox/Safari 友好 | 主打 Chromium |
| JSON 输出 | 每个命令都支持 `--json` | 需要写 reporter |
| MCP 集成 | 内置 `npx vibium mcp` | 无 |
| 语义定位 | `find text|label|placeholder|testid|role|alt` | 需要自己写 |

### 安装

```bash
npm install -g vibium
vibium --headless go https://example.com    # 验证安装
```

Windows 直接装就行。容器环境记得加 `--headless`。

---

## 三种流程类型

### 类型 A：纯 CLI 流程（最简单）

```bash
# flows/cli-smoke.sh
set -e
./build/mytool --input fixtures/sample.txt --output /tmp/result.json
[ -f /tmp/result.json ] || { echo "输出文件未生成"; exit 1; }
jq -e '.status == "ok"' /tmp/result.json
```

### 类型 B：HTTP 服务流程

```bash
# flows/api-flow.sh
set -e

# 启动服务
./build/myserver &
SERVER_PID=$!
trap "kill $SERVER_PID" EXIT
sleep 2

# 调用
curl -fs http://localhost:8080/health
TOKEN=$(curl -fs -X POST http://localhost:8080/login \
  -d '{"user":"test","pass":"123"}' | jq -r .token)

curl -fs http://localhost:8080/api/data \
  -H "Authorization: Bearer $TOKEN" \
  | jq -e '.items | length > 0'
```

### 类型 C：Web 浏览器流程（Vibium）

#### 方式 1：脚本式（最直接）

```bash
# flows/login-flow.sh
set -e

vibium --headless go https://app.example.com/login
vibium fill 'input[name=email]' 'test@example.com'
vibium fill 'input[name=password]' 'secret'
vibium click 'button[type=submit]'
vibium wait url '/dashboard'

# 断言
vibium assert url-contains '/dashboard'
vibium assert text-visible 'Welcome'
```

#### 方式 2：JSON batch（更结构化，推荐）

```json
// flows/login-flow.json
[
  {"action": "go",        "url": "https://app.example.com/login"},
  {"action": "wait_load"},
  {"action": "fill",      "selector": "input[name=email]",    "text": "test@example.com"},
  {"action": "fill",      "selector": "input[name=password]", "text": "secret"},
  {"action": "click",     "selector": "button[type=submit]"},
  {"action": "wait_url",  "pattern": "/dashboard"},
  {"action": "assert",    "checks": [
    {"kind": "url_contains",     "text": "/dashboard"},
    {"kind": "selector_visible", "selector": "[data-testid=dashboard]"},
    {"kind": "no_console_errors"},
    {"kind": "no_failed_requests"}
  ]}
]
```

```bash
vibium batch --steps @flows/login-flow.json
```

#### 16 种断言类型（Vibium 内置）

| 类型 | 用途 |
|------|------|
| `url_contains` / `url_equals` | URL 验证 |
| `text_visible` / `text_hidden` | 文本可见性 |
| `selector_visible` / `selector_hidden` | 元素可见性 |
| `value_equals` | 输入框值验证 |
| `attribute_equals` | 属性验证 |
| `no_console_errors` | 无 JS 报错 |
| `no_failed_requests` | 无失败的网络请求 |
| `response_status` | 后端响应码 |
| `request_url_seen` | 验证某个请求被发出 |
| `console_message_matches` | 日志匹配 |
| `element_count` | 元素数量（`>=` / `<=` / `==`） |
| `title_matches` | 页面标题 |
| `page_source_contains` | 源码包含 |

---

## 证据收集（出问题时救命）

```bash
# 录制全过程
vibium record start --screenshots --snapshots --name "login-flow"

# ... 跑流程 ...

vibium record stop -o "results/login-flow/evidence.zip"
# 产出: 截图 + DOM 快照 + 网络日志 + 控制台日志
```

CI 失败时把 evidence.zip 作为 artifact 上传，本地下载就能复盘。

---

## 完整 Prompt（喂给 AI）

```
你是 flow-runner agent。

# 任务
按以下流程脚本执行测试，验证每一步，输出结构化结果。

# 输入
- 流程定义: <填路径或粘贴 JSON/Shell>
- 类型: cli / http / web / mixed
- 环境变量: <如有>

# 执行规则
1. 严格按步骤顺序执行
2. 任一步失败立即停止（除非显式标 continue_on_failure）
3. Web 流程统一用 Vibium，不要用 Playwright/Selenium
4. CLI 流程用 set -e 让 shell 自己抛错
5. HTTP 用 curl -fs，自动处理 4xx/5xx

# Web 流程额外要求
- 必开 --headless（CI 环境）
- 用 data-testid 选择器优先，CSS 类名次之
- DOM 变化后先 vibium diff map 看变化，再继续
- 关键流程用 vibium record 收集证据

# 输出格式（JSON）
{
  "flow_name": "login",
  "status": "passed" | "failed" | "skipped",
  "steps_total": 8,
  "steps_passed": 7,
  "steps_failed": 1,
  "duration_sec": 12.3,
  "failure": {
    "step_index": 5,
    "step_action": "wait_url",
    "expected": "/dashboard",
    "actual": "/login?error=invalid",
    "screenshot": "results/login/step5.png"
  },
  "evidence_path": "results/login/evidence.zip",
  "next_actions": [
    "用户密码可能错了，检查 fixtures/users.json",
    "或登录接口改了，检查最近的提交"
  ]
}

# 失败时
不要继续后续步骤。立即:
1. 截图当前页面
2. 导出 DOM
3. 保存 console/network 日志
4. 输出失败的步骤和上下文
```

---

## 实战示例

### 示例 1：跑一组 gtest 用例

```
# 你说：
flow-runner，跑 tests/unit 下所有测试，生成 XML 报告。
失败立即停，输出哪个用例失败。

# AI 会执行：
ctest --test-dir build -L unit --output-on-failure \
  --output-junit results/unit.xml

# 解析 XML，输出结构化结果
```

### 示例 2：网页登录流程

```
# 你说：
flow-runner，执行 flows/login.json，环境 staging。
失败要给我截图和 console 日志。

# AI 会执行：
vibium record start --name login-staging
vibium batch --steps @flows/login.json \
  --env BASE_URL=https://staging.example.com
RESULT=$?
vibium record stop -o results/login-staging/evidence.zip

# 解析结果，提取关键信息
```

### 示例 3：混合流程

```
# 你说：
flow-runner，按这个流程跑:
1. 启动 ./build/server
2. 等它监听 8080
3. 用 Vibium 打开 http://localhost:8080
4. 点 "Submit" 按钮
5. 验证服务日志里出现 "POST /api/submit"

# AI 会:
- shell 启动 server，trap kill 兜底
- curl 等端口 ready
- vibium go + click
- tail -f server.log | grep + 超时
- 全部串起来，任一失败就停
```

---

## 给 web 测试的实战 tips

1. **优先 `data-testid`**：CSS 类名一改就坏
   ```html
   <button data-testid="submit-order">下单</button>
   ```
2. **DOM 变化后重新 map**：`vibium diff map` 看变化
3. **认证状态复用**：登录一次保存，后续直接恢复
   ```bash
   vibium storage -o auth.json              # 保存
   vibium storage restore auth.json         # 恢复
   ```
4. **慢页面用显式 wait**：`vibium wait load` / `wait url ...` / `wait selector ...`
5. **不要 sleep**：用 `wait` 系列命令，flaky 杀手

---

## 用 Vibium 还是其他

| 场景 | 推荐 |
|------|------|
| 简单 CLI 测试 | bash + curl |
| HTTP API 测试 | curl + jq |
| Web E2E | **Vibium**（首选） |
| 复杂 web 自动化 | Playwright（如果团队已有积累） |
| 移动端测试 | Appium |

**对你来说：装 Vibium，省 290 MB 还多个 BiDi 标准。**

---

## 注意事项

1. **flaky 是 web 测试的天敌** —— 详见 agentic-qe 的 flaky 治理（这里没展开）
2. **CI 上一定 headless** —— 环境变量 `QE_BROWSER_HEADED=0` 强制
3. **证据 ZIP 会膨胀** —— CI 上只保留失败的，N 天后清理
4. **selectors 写在外部** —— 别写在测试代码里，方便集中维护
