# input-refiner

<!-- prettier-ignore -->
> 本地模型输入精炼代理 —— 所有请求在到达主模型之前，先用你的本地小模型精炼一遍，节省 token 并提升指令质量。

[![license](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![python](https://img.shields.io/badge/python-3.10%2B-blue)](https://www.python.org/)

## 它做什么

你打字 → 本地小模型帮你精炼（去废话、补全指代、保留技术细节）→ 精炼后的指令再发给你用的主模型。

```
你输入:  "你好我是谁"
          │
          ▼
   ┌──────────────┐      ┌─────────────────┐      ┌──────────────┐
   │  Claude Code  │─────▶│  input-refiner  │─────▶│  DeepSeek API │
   │    / Codex    │      │    :18888       │      │   / Bailian   │
   │    / Gemini   │      │                 │      │   / 火山...   │
   └──────────────┘      │ ① 提取最后一条    │      └──────────────┘
                         │    user message   │
                         │ ② 调用本地模型     │
                         │ ③ 精炼后写回      │
                         │ ④ 透明转发       │
                         └────────┬────────┘
                                  │
                                  ▼
                         ┌──────────────────┐
                         │   llama.cpp       │
                         │   :8080 (Docker)  │
                         │   本地小模型       │
                         └──────────────────┘
```

## 前置条件

- **Python 3.10+**
- **llama.cpp Docker 容器** 监听 `:8080`（或其他 OpenAI-compatible 的本地模型）
- **ccswitch**（已安装并接管了你的 Claude Code / Codex 等终端工具）

## 快速开始

### 1. 安装

```bash
cd ~/input-refiner
./install.sh
```

安装脚本自动完成：
- pip 安装 httpx、pyyaml
- 复制 `refiner` 到 `~/.local/bin/`
- 创建 systemd user service（开机自启 + 常驻后台）

### 2. 修改配置（如需要）

编辑 `config.yaml`：

```yaml
refiner:
  endpoint: http://localhost:8080/v1/chat/completions   # 你的本地模型端点
  models_dir: ~/models                                    # .gguf 模型目录
  timeout: 5                                              # 精炼超时（秒）
  max_tokens: 256                                         # 精炼输出上限

prompt: |
  你是输入精炼器。接收用户原始输入，输出一条清晰完整的指令。
  规则：
  - 去除闲聊、客套、重复、口头禅
  - 补全模糊指代
  - 保留所有技术细节（文件名、命令、参数、版本号）
  - 不回答、不评价、不解释，只输出精炼后的指令
  - 输入已足够清晰 → 原样输出

skip_prefix: "!!!"    # 以这个前缀开头的输入不精炼，去掉前缀直接发主模型
```

### 3. 启动

```bash
systemctl --user enable --now input-refiner
```

### 4. 接入 ccswitch

```bash
refiner setup
```

这会把 ccswitch 中所有 provider 的 `ANTHROPIC_BASE_URL` 从原始地址（如 `https://api.deepseek.com/anthropic`）改为指向 refiner 代理 `http://localhost:18888/proxy/api.deepseek.com/anthropic`，并备份原始 URL。重启 ccswitch 后生效。

## 日常使用

| 命令 | 作用 |
|------|------|
| `refiner status` | 查看本地模型和 refiner 运行状态 |
| `refiner models` | 列出 models_dir 下所有 .gguf 文件 |
| `refiner switch <name>` | 切换到指定模型（模糊匹配，自动重启 Docker） |
| `refiner setup` | 一键接入 ccswitch（把 endpoint 指向 refiner） |
| `refiner teardown` | 一键还原（恢复原始 endpoint） |
| `refiner serve --port 18888` | 手动启动代理（通常用 systemd，不需要手动跑） |

## HUD 显示

refiner 在状态栏（claude-hud）显示精炼结果：

```
✎ 请问您是什么模型？   [DeepSeek-V4-Pro[1m] ◑ high] │ 下载 │ ...
```

精炼后的文本会自动写到 `/tmp/refiner-status.txt`，由 HUD 命令读取。

## 跳过精炼

以 `!!!` 开头（可在 config.yaml 中改为其他前缀）：

```
!!!restart              → 直接发给主模型 "restart"
!!!你怎么看这个bug      → 直接发给主模型 "你怎么看这个bug"
```

## 容错

| 情况 | 行为 |
|------|------|
| 本地模型无响应/超时 | 原样透传，不阻塞 |
| 精炼结果为空 | 原样透传 |
| 上游返回错误 | 原样透传状态码和错误体 |
| 配置文件缺失 | 使用内置默认值运行 |
| 并发请求 | 每个请求独立精炼 |

## 还原

```bash
# 还原 ccswitch endpoint
refiner teardown

# 停用服务
systemctl --user disable --now input-refiner

# 完整卸载
./install.sh --uninstall
```

## 项目结构

```
input-refiner/
├── README.md           # 本文件
├── DESIGN.md           # 详细设计文档
├── config.yaml         # 用户配置文件
├── refiner             # CLI 入口（Python 单文件）
├── install.sh          # 一键安装/卸载
├── LICENSE             # MIT
└── .gitignore
```

## 工作原理细节

1. refiner 作为 HTTP 代理，路径 `/proxy/api.deepseek.com/anthropic/v1/messages` 中的域名信息用于解析上游 URL
2. 收到请求后，找到 `messages[]` 中最后一条 `role: "user"` 的消息
3. 支持两种 content 格式：纯字符串 `"你好"` 和 content blocks 数组 `[{"type":"text","text":"你好"}]`
4. 跳过系统指令（长度 > 1000 字符）、agent prompt 等非用户输入
5. 调用本地模型 `/v1/completions`（非 chat），注入精炼 system prompt
6. 精炼结果写回消息体，透明转发到上游
7. 流式响应逐块透传给客户端

## License

MIT
