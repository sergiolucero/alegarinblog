#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────
# Deploy FDG Blog (static Vite build) to a DigitalOcean droplet
# over SSH.
#
# Examples:
#   DEPLOY_HOST=203.0.113.10 ./deploy.sh
#   DEPLOY_HOST=my-droplet.example.com DEPLOY_USER=www-data \
#     DEPLOY_PATH=/var/www/fdg-blog SSH_KEY=~/.ssh/id_ed25519 ./deploy.sh
# ─────────────────────────────────────────────────────────────

# Change into the directory this script lives in (the project root).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ── Configuration (override via environment) ────────────────
DEPLOY_HOST="${DEPLOY_HOST:-}"
DEPLOY_USER="${DEPLOY_USER:-root}"
DEPLOY_PATH="${DEPLOY_PATH:-/var/www/fdg-blog}"
SSH_KEY="${SSH_KEY:-}"            # optional: ~/.ssh/id_ed25519
SSH_PORT="${SSH_PORT:-22}"
DELETE_STALE="${DELETE_STALE:-0}" # rsync only: 1 = remove files deleted locally
BUILD_DIR="dist"
# ─────────────────────────────────────────────────────────────

if [[ -z "$DEPLOY_HOST" ]]; then
  cat >&2 <<'EOF'
ERROR: DEPLOY_HOST is not set.

Usage:
  DEPLOY_HOST=<droplet-ip-or-hostname> [DEPLOY_USER=root] \
  [DEPLOY_PATH=/var/www/fdg-blog] [SSH_KEY=~/.ssh/id_ed25519] ./deploy.sh

Examples:
  DEPLOY_HOST=203.0.113.10 ./deploy.sh
  DEPLOY_HOST=example.com DEPLOY_USER=www-data DEPLOY_PATH=/var/www/html ./deploy.sh
EOF
  exit 1
fi

SSH_ARGS=( -p "$SSH_PORT" )
[[ -n "$SSH_KEY" ]] && SSH_ARGS+=( -i "$SSH_KEY" )

remote() { ssh "${SSH_ARGS[@]}" "$DEPLOY_USER@$DEPLOY_HOST" "$@"; }

echo "==> Building the production bundle..."
npm run build
[[ -d "$BUILD_DIR" ]] || { echo "ERROR: build output '$BUILD_DIR' missing." >&2; exit 1; }

echo "==> Ensuring '$DEPLOY_PATH' exists on $DEPLOY_HOST..."
remote "mkdir -p '$DEPLOY_PATH'"

if command -v rsync >/dev/null 2>&1; then
  echo "==> Uploading with rsync..."
  RSYNC_RSH="ssh -p $SSH_PORT${SSH_KEY:+ -i $SSH_KEY}"
  RSYNC_ARGS=( -az --info=progress2 )
  [[ "$DELETE_STALE" == "1" ]] && RSYNC_ARGS+=( --delete )
  rsync "${RSYNC_ARGS[@]}" -e "$RSYNC_RSH" \
    "$BUILD_DIR/" "$DEPLOY_USER@$DEPLOY_HOST:$DEPLOY_PATH/"
else
  echo "==> rsync not found; uploading with tar over ssh..."
  tar -C "$BUILD_DIR" -czf - . | remote "tar -C '$DEPLOY_PATH' -xzf -"
fi

echo "==> Done. Site deployed to $DEPLOY_USER@$DEPLOY_HOST:$DEPLOY_PATH"
