const fs = require('fs'), path = require('path');
const root = process.cwd();

const ws = JSON.parse(fs.readFileSync(path.join(root, 'package.json'), 'utf-8'));
const catalog = ws.workspaces?.catalog || {};

// Find all workspace packages by scanning package.json files
const pkgs = {};
const scan = (dir) => {
  let entries;
  try { entries = fs.readdirSync(dir, {withFileTypes: true}); } catch { return; }
  for (const e of entries) {
    if (!e.isDirectory()) continue;
    const pj = path.join(dir, e.name, 'package.json');
    if (fs.existsSync(pj)) {
      const p = JSON.parse(fs.readFileSync(pj, 'utf-8'));
      if (p.name) pkgs[p.name] = path.join(dir, e.name);
    }
  }
};
scan(path.join(root, 'packages'));
for (const d of ['console', 'stats']) scan(path.join(root, 'packages', d));

// Handle nested packages (sdk/js)
const sdkjs = path.join(root, 'packages', 'sdk', 'js', 'package.json');
if (fs.existsSync(sdkjs)) {
  const p = JSON.parse(fs.readFileSync(sdkjs, 'utf-8'));
  if (p.name) pkgs[p.name] = path.join(root, 'packages', 'sdk', 'js');
}

console.log("Found packages:", Object.keys(pkgs).join(", "));

let patched = 0;
const patch = (dir, label) => {
  const pj = path.join(dir, 'package.json');
  if (!fs.existsSync(pj)) { console.log("SKIP", label); return; }
  const pkg = JSON.parse(fs.readFileSync(pj, 'utf-8'));
  let dirty = false;
  for (const key of ['dependencies', 'devDependencies', 'peerDependencies', 'optionalDependencies', 'overrides']) {
    if (!pkg[key]) continue;
    for (const [name, ver] of Object.entries(pkg[key])) {
      if (typeof ver !== 'string') continue;
      if (ver.startsWith('workspace:')) {
        const target = pkgs[name];
        if (target) { pkg[key][name] = 'file:' + path.relative(dir, target); dirty = true; patched++; }
      } else if (ver === 'catalog:' && catalog[name]) {
        pkg[key][name] = catalog[name]; dirty = true; patched++;
        if (patched <= 5) console.log("  catalog:", label, "->", name, "=", catalog[name]);
      }
    }
  }
  if (dirty) fs.writeFileSync(pj, JSON.stringify(pkg, null, 2) + '\n');
};
patch(root, "root");
for (const [n, p] of Object.entries(pkgs)) patch(p, n);
console.log("Patched", patched, "dependencies");

// Verify no catalog: or workspace: remain
let remaining = 0;
const check = (dir, label) => {
  const pj = path.join(dir, 'package.json');
  if (!fs.existsSync(pj)) return;
  const pkg = JSON.parse(fs.readFileSync(pj, 'utf-8'));
  for (const key of ['dependencies', 'devDependencies', 'peerDependencies', 'optionalDependencies', 'overrides']) {
    if (!pkg[key]) continue;
    for (const [n, v] of Object.entries(pkg[key])) {
      if (typeof v === 'string' && (v === 'catalog:' || v.startsWith('workspace:'))) {
        console.log("  UNPATCHED:", label, key, n, "=", v);
        remaining++;
      }
    }
  }
};
check(root, "root");
for (const [n, p] of Object.entries(pkgs)) check(p, n);
if (remaining > 0) {
  console.error("ERROR:", remaining, "unpatched references remain!");
  process.exit(1);
}
