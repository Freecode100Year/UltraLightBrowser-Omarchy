#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${ULB_REPO_URL:-https://github.com/Freecode100Year/UltraLightBrowser-Omarchy.git}"
BRANCH="${ULB_BRANCH:-main}"

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m==>\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
  die "请不要直接用 root 运行此脚本；脚本会在需要安装依赖时自动调用 sudo。"
fi

if [[ "$(uname -s)" != "Linux" || "$(uname -m)" != "x86_64" ]]; then
  die "目前仅支持 x86_64 Arch Linux / Omarchy（当前：$(uname -s) $(uname -m)）。"
fi

if ! command -v pacman >/dev/null 2>&1 || ! command -v makepkg >/dev/null 2>&1; then
  die "未找到 pacman 或 makepkg，请确认当前系统为 Arch Linux / Omarchy。"
fi

# 支持 Omarchy 常见的 mise / rustup 用户态工具链
for extra_bin in "$HOME/.local/share/mise/shims" "$HOME/.cargo/bin" "$HOME/.local/bin"; do
  if [[ -d "$extra_bin" && ":$PATH:" != *":$extra_bin:"* ]]; then
    export PATH="$extra_bin:$PATH"
  fi
done

PACMAN_PKGS=(cef gtk4 libpipewire unzip git base-devel clang pkgconf)
if ! command -v cargo >/dev/null 2>&1; then
  PACMAN_PKGS+=(rust)
fi
if ! command -v go >/dev/null 2>&1; then
  PACMAN_PKGS+=(go)
fi

info "安装运行与构建依赖：${PACMAN_PKGS[*]}"
sudo pacman -S --needed --noconfirm "${PACMAN_PKGS[@]}"

command -v cargo >/dev/null 2>&1 || die "未检测到 cargo，请检查 Rust 工具链。"
command -v go >/dev/null 2>&1 || die "未检测到 go，请检查 Go 工具链。"

TMP_WORK=""
cleanup() {
  if [[ -n "$TMP_WORK" && -d "$TMP_WORK" ]]; then
    rm -rf "$TMP_WORK"
  fi
}
trap cleanup EXIT

TMP_WORK="$(mktemp -d -t ulb-install-XXXXXX)"

if [[ -f "$PWD/linux/packaging/PKGBUILD" && -f "$PWD/linux/Cargo.toml" && -f "$PWD/warp/go.mod" ]]; then
  info "检测到本地源码仓库：$PWD"
  REPO_ROOT="$PWD"
else
  info "克隆源码仓库 ($REPO_URL @ $BRANCH)..."
  git clone --depth=1 --branch "$BRANCH" "$REPO_URL" "$TMP_WORK/src"
  REPO_ROOT="$TMP_WORK/src"
fi

PKG_STAGE="$TMP_WORK/pkg"
mkdir -p "$PKG_STAGE"
cp "$REPO_ROOT/linux/packaging/PKGBUILD" \
   "$REPO_ROOT/linux/packaging/ultralightbrowser.desktop" \
   "$REPO_ROOT/linux/packaging/ultralightbrowser.svg" \
   "$PKG_STAGE/"

export SRCDEST_ROOT="$REPO_ROOT"
export PKGDEST="$TMP_WORK/out"
mkdir -p "$PKGDEST"

info "编译并打包 ultralightbrowser-git（链接系统 CEF / GTK4 / PipeWire）..."
pushd "$PKG_STAGE" >/dev/null
if pacman -Qq rust go >/dev/null 2>&1; then
  makepkg -si --noconfirm
else
  # 当 cargo/go 由 mise 或 rustup 提供而非 pacman 包时，跳过 makedepends 检查；
  # 产物包仍保留 depends=('cef' 'gtk4' 'libpipewire' 'unzip') 由 pacman 校验。
  makepkg -dfi --noconfirm
fi
popd >/dev/null

if command -v ulb-linux >/dev/null 2>&1; then
  info "安装完成！校验运行环境："
  ulb-linux --check
  echo
  info "现在可以直接运行：ulb-linux（或从应用启动器打开 UltraLightBrowser）"
  info "卸载命令：sudo pacman -R ultralightbrowser-git"
else
  die "安装似乎未生成 /usr/bin/ulb-linux，请检查上方输出。"
fi
