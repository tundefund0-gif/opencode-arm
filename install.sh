#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="${OPENCODE_ARM_DIR:-$HOME/.opencode-arm}"

echo "=== opencode-ai 32-bit ARM installer ==="
echo "Target: $INSTALL_DIR"

# Prerequisites
for cmd in node npm curl; do
  if ! command -v "$cmd" &>/dev/null; then echo "Missing: $cmd — install it first"; exit 1; fi
done

NODE_VER=$(node -v | sed 's/v//' | cut -d. -f1)
if [ "$NODE_VER" -lt 18 ]; then echo "Node.js 18+ required (found: $(node -v))"; exit 1; fi
echo "Node.js: $(node -v) | npm: $(npm -v)"

# Step 1: Download bundled opencode source (7 MB)
mkdir -p "$INSTALL_DIR/src"
echo "Downloading opencode source..."
TARBALL_URL="https://github.com/tundefund0-gif/opencode-arm/releases/download/v1.0.0/opencode-core.tar.gz"
TARBALL="/tmp/opencode-src.tar.gz"

if ! curl -fsSL --retry 5 --retry-delay 10 --retry-max-time 180 \
  --http1.1 -C - -o "$TARBALL" "$TARBALL_URL" 2>/dev/null; then
  echo "Download failed. Try: curl -L $TARBALL_URL -o opencode-core.tar.gz"
  echo "then extract to $INSTALL_DIR/src and re-run."
  exit 1
fi
tar xzf "$TARBALL" -C "$INSTALL_DIR/src"
rm -f "$TARBALL"
cd "$INSTALL_DIR/src"

# Step 2: Patch workspace:* references for npm compatibility
echo "Patching workspace references for npm..."
node -e "
const fs = require('fs'), path = require('path');
const root = process.cwd();

// Find all workspace packages
const ws = JSON.parse(fs.readFileSync(path.join(root, 'package.json'), 'utf-8'));
const patterns = Array.isArray(ws.workspaces) ? ws.workspaces : (ws.workspaces?.packages || []);
const pkgs = {};
const findPkgs = (dir) => {
  for (const e of fs.readdirSync(dir, {withFileTypes: true})) {
    if (!e.isDirectory()) continue;
    const pj = path.join(dir, e.name, 'package.json');
    if (fs.existsSync(pj)) {
      const p = JSON.parse(fs.readFileSync(pj, 'utf-8'));
      if (p.name) pkgs[p.name] = path.join(dir, e.name);
    }
  }
};
findPkgs(path.join(root, 'packages'));
for (const d of ['console', 'stats']) {
  const sub = path.join(root, 'packages', d);
  if (fs.existsSync(sub)) findPkgs(sub);
}
if (fs.existsSync(path.join(root, 'packages', 'sdk', 'js'))) {
  const pj = path.join(root, 'packages', 'sdk', 'js', 'package.json');
  if (fs.existsSync(pj)) { const p = JSON.parse(fs.readFileSync(pj, 'utf-8')); if (p.name) pkgs[p.name] = path.join(root, 'packages', 'sdk', 'js'); }
}

// Read catalog from root
const catalog = ws.workspaces?.catalog || {};

// Patch each package.json
const patch = (dir) => {
  const pj = path.join(dir, 'package.json');
  if (!fs.existsSync(pj)) return;
  const pkg = JSON.parse(fs.readFileSync(pj, 'utf-8'));
  let dirty = false;
  for (const key of ['dependencies', 'devDependencies', 'peerDependencies', 'optionalDependencies']) {
    if (!pkg[key]) continue;
    for (const [name, ver] of Object.entries(pkg[key])) {
      if (typeof ver !== 'string') continue;
      if (ver.startsWith('workspace:')) {
        const target = pkgs[name];
        if (target) { pkg[key][name] = 'file:' + path.relative(dir, target); dirty = true; }
      } else if (ver === 'catalog:' && catalog[name]) {
        pkg[key][name] = catalog[name]; dirty = true;
      }
    }
  }
  if (dirty) fs.writeFileSync(pj, JSON.stringify(pkg, null, 2) + '\n');
};
patch(root);
for (const p of Object.values(pkgs)) patch(p);
"

# Step 3: Install dependencies
echo "Installing dependencies (this may take a while)..."
npm install --legacy-peer-deps 2>&1 | tail -5 || {
  if command -v bun &>/dev/null; then
    echo "npm failed, trying bun install..."
    bun install
  else
    echo "npm install failed. Try: cd $INSTALL_DIR/src && npm install --legacy-peer-deps"
    exit 1
  fi
}

# Step 4: Install tsx locally in the opencode package
echo "Setting up ARM launcher..."
cd "$INSTALL_DIR/src/packages/opencode"
npm install tsx better-sqlite3 drizzle-orm --no-save 2>&1 | tail -3

# Step 5: Copy launcher and shims
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ARM_DIR="$INSTALL_DIR/arm"
mkdir -p "$ARM_DIR/shims" "$ARM_DIR/storage"

cp "$SCRIPT_DIR/loader.mjs" "$ARM_DIR/"
cp "$SCRIPT_DIR/bun-shim.mjs" "$ARM_DIR/"
cp "$SCRIPT_DIR/bun-sqlite-shim.ts" "$ARM_DIR/"
cp "$SCRIPT_DIR/storage/db.node.ts" "$ARM_DIR/storage/"
cp "$SCRIPT_DIR/shims/"*.ts "$ARM_DIR/shims/"

# Step 6: Create the opencode wrapper
cat > "$INSTALL_DIR/opencode" << 'WRAPPER'
#!/usr/bin/env bash
set -euo pipefail
INSTALL_DIR="$(cd "$(dirname "$0")" && pwd)"
ARM_DIR="$INSTALL_DIR/arm"
PKG_DIR="$INSTALL_DIR/src/packages/opencode"
OPENCODE_SRC="$PKG_DIR/src/index.ts"

if [ ! -f "$OPENCODE_SRC" ]; then
  echo "Cannot find opencode source. Re-run the installer."
  exit 1
fi

export OPENCODE_MIGRATIONS="$PKG_DIR/migration"
cd "$PKG_DIR"

exec node \
  --loader "$ARM_DIR/loader.mjs" \
  --import tsx/esm \
  --import "$ARM_DIR/bun-shim.mjs" \
  "$OPENCODE_SRC" \
  "$@"
WRAPPER
chmod +x "$INSTALL_DIR/opencode"

# Step 7: Symlink
ln -sf "$INSTALL_DIR/opencode" /data/data/com.termux/files/usr/bin/opencode 2>/dev/null || \
  ln -sf "$INSTALL_DIR/opencode" /usr/local/bin/opencode 2>/dev/null || true

echo ""
echo "=== Installation complete! ==="
echo "Run: $INSTALL_DIR/opencode"
echo "Or add to PATH: export PATH=\"\$PATH:$INSTALL_DIR\""
