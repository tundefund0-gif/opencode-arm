#!/usr/bin/env bash
set -euo pipefail

REPO="https://github.com/anomalyco/opencode.git"
INSTALL_DIR="${OPENCODE_ARM_DIR:-$HOME/.opencode-arm}"
OPENCODE_VERSION="${OPENCODE_VERSION:-main}"

echo "=== opencode-ai 32-bit ARM installer ==="
echo "Target: $INSTALL_DIR"

# Prerequisites
for cmd in node npm git; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Missing: $cmd — please install it first"
    exit 1
  fi
done

NODE_VER=$(node -v | sed 's/v//' | cut -d. -f1)
if [ "$NODE_VER" -lt 18 ]; then
  echo "Node.js 18+ required (found: $(node -v))"
  exit 1
fi
echo "Node.js: $(node -v)"
echo "npm: $(npm -v)"

# Step 1: Clone or update the repo
if [ -d "$INSTALL_DIR/src" ]; then
  echo "Updating existing installation..."
  cd "$INSTALL_DIR/src"
  git pull --depth 1 origin "$OPENCODE_VERSION" 2>/dev/null || true
else
  echo "Cloning opencode repository..."
  git clone --depth 1 --branch "$OPENCODE_VERSION" "$REPO" "$INSTALL_DIR/src" 2>/dev/null || \
    git clone --depth 1 "$REPO" "$INSTALL_DIR/src"
fi

cd "$INSTALL_DIR/src"

# Step 2: Install tsx globally
echo "Installing tsx..."
npm install -g tsx 2>/dev/null || npm install -g tsx --force 2>/dev/null || {
  echo "Trying local tsx install..."
  npm install tsx --no-save
}

# Step 3: Install workspace dependencies
echo "Installing dependencies (this may take a while)..."
npm install 2>/dev/null || npm install --legacy-peer-deps 2>/dev/null || {
  echo "npm install failed. Trying bun install..."
  if command -v bun &>/dev/null; then
    bun install
  else
    echo "npm install failed and bun not found."
    echo "Try: cd $INSTALL_DIR/src && npm install --legacy-peer-deps"
    exit 1
  fi
}

# Step 4: Copy launcher and shims
echo "Setting up ARM launcher..."
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ARM_DIR="$INSTALL_DIR/arm"
mkdir -p "$ARM_DIR/shims" "$ARM_DIR/storage"

# Copy shim files from the script directory to the arm dir
for f in loader.mjs bun-shim.mjs bun-sqlite-shim.ts; do
  if [ -f "$SCRIPT_DIR/$f" ]; then
    cp "$SCRIPT_DIR/$f" "$ARM_DIR/$f"
  fi
done

for f in bun-module.ts bun-ffi.ts drizzle-bun-sqlite.ts drizzle-bun-sqlite-migrator.ts; do
  if [ -f "$SCRIPT_DIR/shims/$f" ]; then
    cp "$SCRIPT_DIR/shims/$f" "$ARM_DIR/shims/$f"
  fi
done

if [ -f "$SCRIPT_DIR/storage/db.node.ts" ]; then
  cp "$SCRIPT_DIR/storage/db.node.ts" "$ARM_DIR/storage/db.node.ts"
fi

# Step 5: Create the opencode wrapper command
WRAPPER="$INSTALL_DIR/opencode"
cat > "$WRAPPER" << 'WRAPPER'
#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="$(cd "$(dirname "$0")" && pwd)"
ARM_DIR="$INSTALL_DIR/arm"
OPENCODE_SRC="$INSTALL_DIR/src/packages/opencode/src/index.ts"

if [ ! -f "$OPENCODE_SRC" ]; then
  for candidate in "$INSTALL_DIR/src/src/index.ts" "$INSTALL_DIR/packages/opencode/src/index.ts"; do
    if [ -f "$candidate" ]; then OPENCODE_SRC="$candidate"; break; fi
  done
fi

if [ ! -f "$OPENCODE_SRC" ]; then
  echo "Cannot find opencode source. Re-run the installer."
  exit 1
fi

export OPENCODE_MIGRATIONS="$(dirname "$OPENCODE_SRC")/../migration"
cd "$(dirname "$OPENCODE_SRC")/.."

exec node \
  --loader "$ARM_DIR/loader.mjs" \
  --import tsx/esm \
  --import "$ARM_DIR/bun-shim.mjs" \
  "$OPENCODE_SRC" \
  "$@"
WRAPPER

chmod +x "$WRAPPER"

# Step 6: Create a symlink or suggest PATH addition
if [ -d "/usr/local/bin" ]; then
  ln -sf "$WRAPPER" "/usr/local/bin/opencode" 2>/dev/null && \
    echo "Created /usr/local/bin/opencode symlink"
fi

echo ""
echo "=== Installation complete! ==="
echo ""
echo "Run opencode with:"
echo "  $INSTALL_DIR/opencode"
echo ""
if [ ! -f "/usr/local/bin/opencode" ]; then
  echo "Or add to PATH:"
  echo "  export PATH=\"\$PATH:$INSTALL_DIR\""
  echo "  source ~/.bashrc"
fi
echo ""
echo "First run: $INSTALL_DIR/opencode --help"
