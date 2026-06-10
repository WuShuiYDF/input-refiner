# Input Refiner — 设计规格

## 概述

输入预处理代理层，位于 ccswitch 与上游 LLM API 之间。用户输入的原始文字先经本地模型（llama.cpp, `:8080`）精炼，再转发给主模型。统一覆盖 Claude Code / Codex / Gemini 等所有通过 ccswitch 的工具。

## 架构

```
[Claude Code / Codex / Gemini ...]
              │
              ▼
      [ccswitch proxy :15721]
              │
              ▼
      [input-refiner :18888]   ← 本项目
              │
       ┌──────┴──────┐
       ▼              ▼
  [本地模型 :8080]  [DeepSeek / Bailian / 火山 / ...]
   (精炼用)         (上游 LLM)
```

- **端口**: `18888`（可配置）
- **协议**: 透传 Anthropic Messages API（OpenAI-compatible 也支持）
- **语言**: Python 3（轻量部署，改 prompt 不用编译）

## 核心流程

```
1. 收到 HTTP POST /v1/messages
2. 解析请求体，提取 messages[]
3. 找到最后一条 role=user 的消息
4. 检查 content 是否以 "!!!" 开头
   ├── 是 → 去掉 "!!!"，跳过精炼
   └── 否 → 调本地模型精炼
5. 精炼结果替换原 user message
6. 精炼前后对比写入日志 + 通知 HUD
7. 转发请求到上游 LLM
8. 流式透传响应
```

## 模型切换

```
$ refiner models                    # 列出 models_dir 下所有 gguf
$ refiner switch <name>             # 重启 Docker 容器，加载指定模型
$ refiner status                    # 当前运行中的模型 + 健康状态
```

实现方式：
1. 扫描 `models_dir` 下所有 `.gguf` 文件
2. 用户选一个 → stop 当前容器 → 重新 `docker run` 换 `--model`
3. 等待 `/health` 返回 ok → 恢复服务

## 配置文件: `config.yaml`

```yaml
# ── 精炼模型 ──
refiner:
  endpoint: http://localhost:8080/v1/chat/completions
  models_dir: /home/wushuiydf/models        # gguf 文件目录
  current_model: auto                         # auto=当前运行中的模型
  timeout: 5                                  # 秒
  max_tokens: 256                             # 精炼输出上限

# ── System Prompt ──
prompt: |
  你是输入精炼器。接收用户原始输入，输出一条清晰完整的指令。

  规则：
  - 去除闲聊、客套、重复、口头禅
  - 补全模糊指代（"那个项目""上次的bug"→具体描述）
  - 保留所有技术细节（文件名、命令、参数、版本号）
  - 不回答、不评价、不解释，只输出精炼后的指令
  - 输入已足够清晰 → 原样输出

# ── 跳过标记 ──
skip_prefix: "!!!"

# ── 上游 LLM ──
upstream: auto                # auto=从请求头推断，或填固定 URL

# ── 适用范围（字符串匹配，空=全部） ──
scope:
  apps: []                    # 白名单，如 ["claude", "codex"]，空=全部

# ── 日志 ──
log:
  path: /home/wushuiydf/.cc-switch/logs/refiner.log
  max_lines: 2000

# ── HUD 集成 ──
hud:
  enabled: true
  status_file: /tmp/refiner-status.txt   # claude-hud 读取此文件
  max_display_len: 80
```

## 可配置项汇总

| 配置点 | 能力 |
|--------|------|
| `prompt` | 随时改 system prompt，无需重启 |
| `skip_prefix` | 自定义跳过标记 |
| `scope.apps` | 只对特定工具生效（空=全部） |
| `refiner.models_dir` | 模型目录，自动扫描 gguf |
| `refiner.timeout` | 本地模型超时策略 |
| `hud.*` | HUD 展示开关/格式 |
| `refiner switch` | 便捷命令行切换模型 + 热重启 |

## 容错

| 情况 | 行为 |
|------|------|
| 本地模型无响应/超时 | 原样透传，不阻塞 |
| 精炼结果为空字符串 | 原样透传 |
| 上游返回错误 | 原样透传状态码和错误体 |
| `.yaml` 配置缺失 | 使用内置默认值运行 |
| 并发请求 | 每个请求独立精炼，不阻塞 |

## HUD 集成方式

1. refiner 写完精炼结果到 `/tmp/refiner-status.txt`
2. claude-hud 的 `preRefine` 字段读取此文件（已内置支持）
3. HUD 显示: `✎ <精炼后文本>`

## 文件结构

```
~/.claude/skills/input-refiner/
├── DESIGN.md          ← 本文件
├── config.yaml        ← 用户配置文件
├── refiner            ← CLI 入口（Python，单文件 ~300 行）
│                        - refiner serve    启动代理
│                        - refiner models   列出可用模型
│                        - refiner switch   切换模型
│                        - refiner status   查看状态
└── install.sh         ← 一键安装/卸载
```

## 安装方式

```bash
# 安装
~/.claude/skills/input-refiner/install.sh

# 启动（systemd user 或手动）
systemctl --user start input-refiner
# 或手动: refiner serve

# 卸载
~/.claude/skills/input-refiner/install.sh --uninstall
```

安装脚本做的事：
1. 检查 Python 3.10+ / `pyyaml` / `httpx`（缺则自动 pip install --user）
2. 生成默认 `config.yaml`（如果不存在）
3. 创建 systemd user unit（`refiner serve` 后台常驻）
4. 创建 `/usr/local/bin/refiner` 软链（`refiner models/switch/status`）
5. 提示用户修改 ccswitch 中 provider 的 endpoint 指向 `:18888`

## 非目标

- 不改 ccswitch 源码
- 不改 Claude Code / Codex CLI 配置
- 不缓存/存储用户对话内容（精炼即删）
- 不处理 tool_use / assistant / system 消息
