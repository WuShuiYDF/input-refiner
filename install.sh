#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_BIN="/usr/local/bin/refiner"
SYSTEMD_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[✓]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[✗]${NC} $*"; exit 1; }

# ── uninstall ──
if [[ "${1:-}" == "--uninstall" ]]; then
    echo "=== 卸载 input-refiner ==="

    # 停止服务
    systemctl --user stop input-refiner 2>/dev/null || true
    systemctl --user disable input-refiner 2>/dev/null || true
    rm -f "$SYSTEMD_DIR/input-refiner.service"
    systemctl --user daemon-reload 2>/dev/null || true

    # 删除软链
    sudo rm -f "$INSTALL_BIN"

    log "卸载完成"
    exit 0
fi

echo "=== 安装 input-refiner ==="
echo ""

# 1. 检查 Python
PYTHON=$(command -v python3 || command -v python || true)
PYTHON_VER=$("$PYTHON" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null || echo "0.0")
if [[ "$PYTHON_VER" < "3.10" ]]; then
    err "需要 Python 3.10+，当前: $PYTHON_VER"
fi
log "Python $PYTHON_VER"

# 2. 安装 Python 依赖
for pkg in httpx pyyaml; do
    if ! "$PYTHON" -c "import $pkg" 2>/dev/null; then
        warn "安装 $pkg..."
        "$PYTHON" -m pip install --user "$pkg" || err "安装 $pkg 失败"
    fi
done
log "Python 依赖检查通过"

# 3. 安装二进制
sudo cp "$SCRIPT_DIR/refiner" "$INSTALL_BIN"
sudo chmod +x "$INSTALL_BIN"
log "已安装: $INSTALL_BIN"

# 4. 复制配置文件（如果不存在）
if [[ ! -f "$SCRIPT_DIR/config.yaml" ]]; then
    err "config.yaml 不在项目目录中"
fi
log "配置文件: $SCRIPT_DIR/config.yaml"

# 5. 创建 systemd user unit
mkdir -p "$SYSTEMD_DIR"
cat > "$SYSTEMD_DIR/input-refiner.service" << UNIT
[Unit]
Description=input-refiner — 本地模型输入精炼代理
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$INSTALL_BIN serve
Restart=on-failure
RestartSec=5
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=default.target
UNIT

systemctl --user daemon-reload
log "systemd unit 已创建"

# 6. 提示
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  安装完成!"
echo ""
echo "  启动服务:"
echo "    systemctl --user enable --now input-refiner"
echo "    # 或手动: refiner serve"
echo ""
echo "  日常命令:"
echo "    refiner serve         启动代理 (:18888)"
echo "    refiner models        列出可用模型"
echo "    refiner switch xxx    切换模型"
echo "    refiner status        查看状态"
echo ""
echo "  健康检查: curl http://localhost:18888/health"
echo ""
echo "  ⚠ 下一步: 在 ccswitch 中将 provider 的 endpoint"
echo "    改为 http://localhost:18888/v1/messages"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
