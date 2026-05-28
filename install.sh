#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="${OPENCODE_ARM_DIR:-$HOME/.opencode-arm}"

echo "=== opencode-ai 32-bit ARM installer ==="
echo "Target: $INSTALL_DIR"

for cmd in node npm curl; do
  if ! command -v "$cmd" &>/dev/null; then echo "Missing: $cmd — install it first"; exit 1; fi
done

NODE_VER=$(node -v | sed 's/v//' | cut -d. -f1)
if [ "$NODE_VER" -lt 18 ]; then echo "Node.js 18+ required (found: $(node -v))"; exit 1; fi
echo "Node.js: $(node -v) | npm: $(npm -v)"

# Step 1: Download bundled opencode source (2 MB)
mkdir -p "$INSTALL_DIR/src"
echo "Downloading opencode source (2 MB)..."
TARBALL_URL="https://github.com/tundefund0-gif/opencode-arm/releases/download/v1.0.0/mini-opencode.tar.gz"
TARBALL="$INSTALL_DIR/source.tar.gz"

OK=false
for i in 1 2 3; do
  echo "  Attempt $i/3..."
  if curl -fL --retry 3 --retry-delay 5 --http1.1 -o "$TARBALL" "$TARBALL_URL" 2>/dev/null; then
    OK=true; break
  fi
  [ "$i" -lt 3 ] && sleep 3
done

if $OK && tar tzf "$TARBALL" &>/dev/null; then
  tar xzf "$TARBALL" -C "$INSTALL_DIR/src"
  rm -f "$TARBALL"
  echo "  Extracted successfully."
else
  rm -f "$TARBALL"
  echo ""
  echo "Download failed on all attempts."
  echo "Try downloading manually on a better connection:"
  echo "  curl -L $TARBALL_URL -o ~/opencode-source.tar.gz"
  echo "  mkdir -p $INSTALL_DIR/src"
  echo "  tar xzf ~/opencode-source.tar.gz -C $INSTALL_DIR/src"
  echo "Then re-run this installer."
  exit 1
fi

cd "$INSTALL_DIR/src"

# Step 2: Patch workspace:* and catalog: references for npm
echo "Patching workspace/catalog references..."
node -e "
const fs = require('fs'), path = require('path');
const root = process.cwd();
const ws = JSON.parse(fs.readFileSync(path.join(root, 'package.json'), 'utf-8'));
const pkgs = {};

const scan = (dir) => {
  try { for (const e of fs.readdirSync(dir, {withFileTypes: true})) {
    if (!e.isDirectory()) continue;
    const pj = path.join(dir, e.name, 'package.json');
    if (fs.existsSync(pj)) { const p = JSON.parse(fs.readFileSync(pj, 'utf-8')); if (p.name) pkgs[p.name] = path.join(dir, e.name); }
  }} catch {}
};
scan(path.join(root, 'packages'));
for (const d of ['console', 'stats']) scan(path.join(root, 'packages', d));
const sdkjs = path.join(root, 'packages', 'sdk', 'js', 'package.json');
if (fs.existsSync(sdkjs)) { const p = JSON.parse(fs.readFileSync(sdkjs, 'utf-8')); if (p.name) pkgs[p.name] = path.join(root, 'packages', 'sdk', 'js'); }

const catalog = ws.workspaces?.catalog || {};
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

# Step 4: Install tsx + extras in the opencode package
echo "Setting up ARM launcher..."
cd "$INSTALL_DIR/src/packages/opencode"
npm install tsx better-sqlite3 drizzle-orm --no-save 2>&1 | tail -3

# Step 5: Copy shims
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ARM_DIR="$INSTALL_DIR/arm"
mkdir -p "$ARM_DIR/shims" "$ARM_DIR/storage"

cp "$SCRIPT_DIR/loader.mjs" "$ARM_DIR/"
cp "$SCRIPT_DIR/bun-shim.mjs" "$ARM_DIR/"
cp "$SCRIPT_DIR/bun-sqlite-shim.ts" "$ARM_DIR/"
cp "$SCRIPT_DIR/storage/db.node.ts" "$ARM_DIR/storage/"
cp "$SCRIPT_DIR/shims/"*.ts "$ARM_DIR/shims/"

# Step 6: Create wrapper script
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

# Step 7: Try symlink
ln -sf "$INSTALL_DIR/opencode" /data/data/com.termux/files/usr/bin/opencode 2>/dev/null || \
  ln -sf "$INSTALL_DIR/opencode" /usr/local/bin/opencode 2>/dev/null || true

echo ""
echo "=== Installation complete! ==="
echo "Run: $INSTALL_DIR/opencode"
