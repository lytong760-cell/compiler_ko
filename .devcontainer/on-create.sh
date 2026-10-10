#!/usr/bin/env bash
# Cài toàn bộ toolchain của compiler_ko. Idempotent: chạy lại không sao.
set -euo pipefail

ZIG_VERSION="0.16.0"
BUN_VERSION="1.4.2"
NODE_MAJOR="24"
DOTNET_VERSION="10.0"

log() { printf '[devcontainer] %s\n' "$*"; }

export DEBIAN_FRONTEND=noninteractive

log "apt: build-essential, cmake, curl, unzip, python3"
sudo apt-get update -qq
sudo apt-get install -y -qq --no-install-recommends \
  build-essential cmake pkg-config make curl wget unzip xz-utils git ca-certificates python3 python3-venv

# ---------------------------------------------------------------- Zig
# Không có gói zig trên apt; phải tải tarball chính thức.
# Lưu ý: tên file đổi theo phiên bản — 0.13 dùng zig-linux-x86_64-*, từ 0.16 dùng zig-x86_64-linux-*
if ! command -v zig >/dev/null 2>&1 || [ "$(zig version 2>/dev/null || true)" != "$ZIG_VERSION" ]; then
  log "zig $ZIG_VERSION"
  arch="$(uname -m)"
  case "$arch" in
    x86_64)  zig_arch="x86_64-linux" ;;
    aarch64) zig_arch="aarch64-linux" ;;
    *) echo "Khong ho tro kien truc: $arch" >&2; exit 1 ;;
  esac
  url="https://ziglang.org/download/${ZIG_VERSION}/zig-${zig_arch}-${ZIG_VERSION}.tar.xz"
  tmp="$(mktemp -d)"
  curl -fsSL "$url" -o "$tmp/zig.tar.xz"
  tar -xf "$tmp/zig.tar.xz" -C "$tmp"
  sudo rm -rf /opt/zig
  sudo mv "$tmp/zig-${zig_arch}-${ZIG_VERSION}" /opt/zig
  rm -rf "$tmp"
  sudo ln -sf /opt/zig/zig /usr/local/bin/zig
fi
log "zig -> $(zig version)"

# ---------------------------------------------------------------- JDK
# Agter cần JDK cho src/Import.java. CI chỉ chạy javac, không cần JRE riêng.
if ! command -v javac >/dev/null 2>&1; then
  log "openjdk-21-jdk (long-term, khả dụng qua apt)"
  sudo apt-get install -y -qq openjdk-21-jdk-headless
fi
log "javac -> $(javac -version 2>&1 | head -1)"

# ---------------------------------------------------------------- .NET
# Cho job `csharp` trong CI. Dùng script chính thức để tránh phụ thuộc repo.
if ! command -v dotnet >/dev/null 2>&1; then
  log "dotnet-sdk-${DOTNET_VERSION}"
  curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh
  bash /tmp/dotnet-install.sh --channel "${DOTNET_VERSION}" --install-dir /usr/local/share/dotnet
  sudo ln -sf /usr/local/share/dotnet/dotnet /usr/local/bin/dotnet
fi
log "dotnet -> $(dotnet --version 2>/dev/null || echo 'n/a')"

# ---------------------------------------------------------------- Node / npm
if ! command -v node >/dev/null 2>&1; then
  log "node ${NODE_MAJOR}.x (NodeSource)"
  curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | sudo -E bash -
  sudo apt-get install -y -qq nodejs
fi
log "node  -> $(node --version 2>/dev/null || echo 'n/a')"
log "npm   -> $(npm --version 2>/dev/null || echo 'n/a')"

# ---------------------------------------------------------------- pnpm / yarn
# Dùng corepack nên không phải cài binary riêng.
if command -v corepack >/dev/null 2>&1; then
  corepack enable
  corepack prepare pnpm@latest --activate >/dev/null 2>&1 || true
  corepack prepare yarn@latest --activate >/dev/null 2>&1 || true
fi
log "pnpm  -> $(pnpm --version 2>/dev/null || echo 'n/a')"
log "yarn  -> $(yarn --version 2>/dev/null || echo 'n/a')"

# ---------------------------------------------------------------- Bun
if ! command -v bun >/dev/null 2>&1 || [ "$(bun --version 2>/dev/null || true)" != "$BUN_VERSION" ]; then
  log "bun ${BUN_VERSION}"
  arch="$(uname -m)"
  case "$arch" in
    x86_64)  bun_arch="linux-x64" ;;
    aarch64) bun_arch="linux-aarch64" ;;
    *) echo "Khong ho tro kien truc: $arch" >&2; exit 1 ;;
  esac
  tmp="$(mktemp -d)"
  curl -fsSL "https://github.com/oven-sh/bun/releases/download/bun-v${BUN_VERSION}/bun-${bun_arch}.zip" -o "$tmp/bun.zip"
  unzip -q "$tmp/bun.zip" -d "$tmp"
  sudo install -m 0755 "$tmp/bun-${bun_arch}/bun" /usr/local/bin/bun
  rm -rf "$tmp"
fi
log "bun   -> $(bun --version 2>/dev/null || echo 'n/a')"

# ---------------------------------------------------------------- Gói npm toàn cục
# compiler_ko KHÔNG có JavaScript (0 file .js/.ts, không package.json), nên đây là
# công cụ dùng chung cho môi trường dev, không phải phụ thuộc của repo.
# Sửa danh sách dưới đây nếu cần thêm/bớt.
NPM_GLOBAL_PACKAGES=(
  "typescript"      # tsc — trình biên dịch TypeScript
  "prettier"        # formatter
  "eslint"          # linter
  "tsx"             # chạy TypeScript trực tiếp không cần build
)

log "cài gói npm toàn cục: ${NPM_GLOBAL_PACKAGES[*]}"
for pkg in "${NPM_GLOBAL_PACKAGES[@]}"; do
  if npm ls -g --depth=0 "$pkg" >/dev/null 2>&1; then
    log "  $pkg — đã có, giữ nguyên"
  else
    if npm install -g "$pkg"; then
      log "  $pkg — OK"
    else
      log "  $pkg — CÀI LỖI, bỏ qua"
    fi
  fi
done

<<<<<<< ours
# ---------------------------------------------------------------- Kilo CLI
# Bản thân agent đang chạy bằng @kilocode/cli — devcontainer phải có để dùng lại
# cùng CLI, cùng agent và skill.
KILO_CLI_VERSION="7.8.3"

log "kilo cli ${KILO_CLI_VERSION}"
if ! npm ls -g --depth=0 @kilocode/cli >/dev/null 2>&1; then
  npm install -g "@kilocode/cli@${KILO_CLI_VERSION}" || log "cài kilo cli lỗi, bỏ qua"
else
  log "  @kilocode/cli — đã có"
fi
log "kilo -> $(kilo --version 2>/dev/null || echo 'n/a')"

# Config của Kilo (kilo.jsonc, agents/, skills/) được mount từ host theo
# `mounts` trong devcontainer.json — không copy vào image, để máy này và máy khác
# dùng chung một bộ config.
if [ -d /root/.config/kilo ]; then
  log "kilo config: $(find /root/.config/kilo/agents -name '*.md' 2>/dev/null | wc -l) agent, $(ls /root/.config/kilo/skills 2>/dev/null | wc -l) skill"
fi

# Nếu môi trường cần token cho MCP server github:
if [ -z "${GITHUB_MCP_TOKEN:-}" ]; then
  log "GITHUB_MCP_TOKEN chưa được set — MCP 'github' sẽ không hoạt động"
fi

# ---------------------------------------------------------------- MCP server
# Cấu hình MCP nằm trong /root/.config/kilo/kilo.jsonc (được mount từ host).
# Ở đây chỉ cài dependency cho các MCP server chạy local.
#   - chrome-devtools  : local, npx chrome-devtools-mcp  -> cần Chrome ở
#                        /opt/chrome-for-testing/chrome (KHÔNG có sẵn, xem bên dưới)
#   - camofox-browser  : local, npx @askjo/camofox-browser-mcp
#   - github           : remote, https://api.githubcopilot.com/mcp/
#                        cần GITHUB_MCP_TOKEN trong môi trường
MCP_PACKAGES=(
  "chrome-devtools-mcp@latest"
  "@askjo/camofox-browser-mcp"
)

log "cài dependency cho MCP server"
for pkg in "${MCP_PACKAGES[@]}"; do
  if npm ls -g --depth=0 "${pkg%@*}" >/dev/null 2>&1; then
    log "  $pkg — đã có"
  else
    # Pre-cache để MCP khởi động nhanh, không cần tải lúc chạy.
    if npm install -g "$pkg" >/dev/null 2>&1; then
      log "  $pkg — OK"
    else
      log "  $pkg — cài lỗi, MCP sẽ tải lúc chạy"
    fi
  fi
done

# Chrome cho chrome-devtools-mcp. Đặt đúng đường dẫn kilo.jsonc trỏ tới.
CHROME_PATH="/opt/chrome-for-testing/chrome"
if [ -x "$CHROME_PATH" ]; then
  log "chrome: $("$CHROME_PATH" --version 2>/dev/null || echo 'có')"
elif command -v google-chrome >/dev/null 2>&1; then
  log "chrome: dùng $(google-chrome --version 2>/dev/null) — cần sửa --executablePath trong kilo.jsonc"
else
  log "chrome: CHƯA CÀI — MCP 'chrome-devtools' sẽ không chạy được"
  log "  cài bằng: npx @puppeteer/browsers install chrome@stable --path /opt/chrome-for-testing"
fi

=======
>>>>>>> theirs
# ---------------------------------------------------------------- Kiểm tra
cd "$(dirname "$0")/.." || exit 1
log "zig build"
if zig build; then
  log "zig build OK"
else
  log "zig build THAT BAI — xem loi tren"
fi

cat <<'EOF'

=== Đã cài ===
  zig      0.16.0   /usr/local/bin/zig
  gcc/g++  13.x     (Ubuntu 24.04)
  cmake, make, pkg-config
  javac    21.x
  python3  3.x
  dotnet   10.x
  node     24.x + npm
  pnpm, yarn (qua corepack)
  bun      1.4.2
<<<<<<< ours
  docker, gh
  kilo CLI @kilocode/cli 7.8.3
=======
  docker, gh (qua devcontainer features)
>>>>>>> theirs

=== Gói npm toàn cục ===
  npm ls -g --depth=0

<<<<<<< ours
=== MCP server (cấu hình trong /root/.config/kilo/kilo.jsonc) ===
  chrome-devtools   local    -> cần Chrome tại /opt/chrome-for-testing/chrome
  camofox-browser   local    -> npx @askjo/camofox-browser-mcp
  github            remote   -> cần GITHUB_MCP_TOKEN

=== Config Kilo (mount từ host) ===
  /root/.config/kilo/kilo.jsonc   -- quyền + MCP server
  /root/.config/kilo/agents/      -- 69 agent
  /root/.config/kilo/skills/      -- 338 skill

=======
>>>>>>> theirs
=== Kiểm tra nhanh ===
  cd /workspaces/compiler_ko
  zig build
  zig build test --summary all < /dev/null
  docker build -t ko-test .
<<<<<<< ours
  kilo --version
=======
>>>>>>> theirs

Lưu ý: `zig build test` cần stdin đóng, nếu không có thể treo.
EOF
