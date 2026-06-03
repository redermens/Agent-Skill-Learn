# 04. automation-orchestrator — 自动化流程 Agent

## 角色

把测试相关的所有步骤串成可重复执行的 pipeline。
不写 CI yaml，是**生成 CI yaml 的 agent**。

---

## 适用场景

- 帮你写 GitHub Actions / GitLab CI / Jenkinsfile
- 设计本地的 `make test` / `make ci` 目标
- 整理散落的测试脚本成统一入口
- 加质量门禁（覆盖率阈值、测试通过率等）

---

## 输入

| 输入项 | 必填 | 说明 |
|--------|------|------|
| 项目类型 | ✅ | 比如：C++ + CMake + gtest |
| CI 平台 | ✅ | GitHub Actions / GitLab CI / Jenkins / local-only |
| 现有 test 命令 | ⬜ | 比如：`ctest --test-dir build` |
| 覆盖率工具 | ⬜ | lcov / gcovr / OpenCppCoverage |
| 质量门禁要求 | ⬜ | 比如：覆盖率 ≥80%、测试全过 |
| 多平台需求 | ⬜ | 比如：Linux + Windows + macOS |

---

## 五阶段标准模板

```
┌──────────┐   ┌────────┐   ┌─────────┐   ┌────────┐   ┌────────────┐
│ 1.静态检查│→ │ 2.构建  │→ │ 3.单元测试│→│ 4.集成测试│→ │5.覆盖率上报│
└──────────┘   └────────┘   └─────────┘   └────────┘   └────────────┘
   30s            2min          5min         10min         1min
```

每阶段的标配：
- **超时设置**（防止挂死）
- **失败立刻停**（除非显式标 continue-on-error）
- **artifact 上传**（编译产物、测试报告、覆盖率）
- **缓存复用**（依赖、构建产物）

---

## 输出格式

### 1. 主要：CI 配置文件

根据 CI 平台输出对应格式：

#### GitHub Actions
```yaml
# .github/workflows/ci.yml
name: C++ CI
on: [push, pull_request]

jobs:
  static-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: clang-tidy
        run: |
          cmake -B build
          run-clang-tidy -p build src/
      - name: cppcheck
        run: cppcheck --enable=all --error-exitcode=1 src/

  build:
    needs: static-check
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/cache@v4
        with:
          path: build
          key: build-${{ hashFiles('**/CMakeLists.txt') }}
      - run: cmake -B build -DCMAKE_BUILD_TYPE=Debug -DCODE_COVERAGE=ON
      - run: cmake --build build -j$(nproc)
      - uses: actions/upload-artifact@v4
        with:
          name: build-artifacts
          path: build/

  unit-test:
    needs: build
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@v4
      - uses: actions/download-artifact@v4
        with: { name: build-artifacts, path: build/ }
      - name: Run unit tests
        run: |
          chmod +x build/tests/*
          ctest --test-dir build -L unit -j$(nproc) \
            --output-on-failure --output-junit unit-results.xml
      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: unit-test-results
          path: unit-results.xml

  coverage:
    needs: unit-test
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/download-artifact@v4
        with: { name: build-artifacts, path: build/ }
      - name: Generate coverage
        run: |
          lcov --capture --directory build --output-file coverage.info
          lcov --remove coverage.info '/usr/*' '*/tests/*' \
            --output-file coverage.info
      - name: Coverage gate
        run: |
          PERCENTAGE=$(lcov --summary coverage.info 2>&1 | \
            grep "lines" | awk '{print $2}' | tr -d '%')
          if (( $(echo "$PERCENTAGE < 80" | bc -l) )); then
            echo "❌ 覆盖率 $PERCENTAGE% 低于 80%"
            exit 1
          fi
          echo "✅ 覆盖率 $PERCENTAGE%"
      - uses: codecov/codecov-action@v4
        with: { files: coverage.info }
```

### 2. 次要：本地 Makefile 入口

```makefile
.PHONY: ci test test-unit test-integration coverage clean

ci: static-check build test coverage

static-check:
	clang-tidy src/*.cpp -- -Iinclude
	cppcheck --enable=all --error-exitcode=1 src/

build:
	cmake -B build -DCMAKE_BUILD_TYPE=Debug -DCODE_COVERAGE=ON
	cmake --build build -j$(shell nproc)

test: test-unit test-integration

test-unit:
	ctest --test-dir build -L unit -j$(shell nproc) --output-on-failure

test-integration:
	ctest --test-dir build -L integration --output-on-failure

coverage:
	lcov --capture --directory build --output-file coverage.info
	lcov --remove coverage.info '/usr/*' '*/tests/*' --output-file coverage.info
	genhtml coverage.info --output-directory coverage_html
	@echo "报告: file://$(PWD)/coverage_html/index.html"

clean:
	rm -rf build coverage_html coverage.info
```

### 3. 总结报告

```json
{
  "ci_platform": "github-actions",
  "files_generated": [
    ".github/workflows/ci.yml",
    "Makefile"
  ],
  "stages": [
    {"name": "static-check", "duration_estimate": "30s"},
    {"name": "build", "duration_estimate": "2-5min", "with_cache": true},
    {"name": "unit-test", "duration_estimate": "5min", "parallel": true},
    {"name": "coverage", "duration_estimate": "1min", "gate": "≥80%"}
  ],
  "quality_gates": [
    {"metric": "all_tests_pass", "blocking": true},
    {"metric": "line_coverage", "threshold": 80, "blocking": true},
    {"metric": "branch_coverage", "threshold": 70, "blocking": false}
  ],
  "estimated_total_duration": "10-15 min",
  "next_steps": [
    "提交 .github/workflows/ci.yml 后第一次跑可能慢（无缓存）",
    "建议先在 staging 分支验证一次再合入 main"
  ]
}
```

---

## 完整 Prompt（喂给 AI）

```
你是 automation-orchestrator agent。

# 任务
为给定项目生成 CI/CD 自动化配置。

# 输入
- 项目类型: <C++ + CMake + gtest>
- CI 平台: <github-actions / gitlab-ci / jenkins / local>
- 测试命令: <ctest 命令>
- 覆盖率工具: <lcov / gcovr / 无>
- 门禁要求: <覆盖率阈值、其他>

# 五阶段模板（按需裁剪）
1. 静态检查: clang-tidy / cppcheck（30s 内）
2. 构建: cmake + make（带缓存）
3. 单元测试: ctest -L unit（并行）
4. 集成测试: ctest -L integration
5. 覆盖率: lcov 生成 + 阈值检查 + Codecov 上传

# 必须遵守
- 每个阶段设 timeout-minutes
- 失败立即停（除非显式 continue-on-error）
- 关键 artifact 上传（编译产物 / 测试报告 / 覆盖率）
- 用缓存避免重复构建
- 质量门禁要明确 blocking 与否

# 输出
1. CI 配置文件（按平台）
2. 本地 Makefile 入口（make ci 一键跑全套）
3. JSON 总结报告

# 禁止
- 不要把 secret 写在 yaml 里（用 ${{ secrets.xxx }}）
- 不要在 CI 里 git push（除非显式要求）
- 不要让任何步骤"静默失败"（continue-on-error 必须配 if: always() upload artifact）
- 不要超过 30 分钟（超时会被 CI 平台 kill）
```

---

## 实战示例

```
# 你说：
automation-orchestrator，为我的 C++ 项目生成 GitHub Actions CI。
- gtest 测试在 tests/unit 和 tests/integration
- 用 lcov 收集覆盖率
- 门禁: 测试全过 + 行覆盖 ≥85%
- 跨平台: Linux + Windows

# AI 会生成:
- .github/workflows/ci-linux.yml
- .github/workflows/ci-windows.yml（用 OpenCppCoverage）
- Makefile + ci.bat
- 总结报告
```

---

## 注意事项

1. **首次跑会慢** —— 没缓存，要 10-20 分钟。第二次开始快
2. **Windows 覆盖率** —— 不能用 lcov，要用 OpenCppCoverage
3. **macOS** —— Clang `--coverage` 行为和 GCC 略有差异
4. **flaky 测试会污染 CI** —— 配合 `--gtest_repeat=3` 自动重试
5. **覆盖率门禁要渐进** —— 别一上来就 90%，先 70 再 80 再 90
