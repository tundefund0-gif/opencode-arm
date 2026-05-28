import fs from "fs"
import path from "path"
import { fileURLToPath } from "url"

const __dirname = path.dirname(fileURLToPath(import.meta.url))

function findFile(candidates) {
  for (const c of candidates) {
    try { if (fs.statSync(c).isFile()) return c } catch {}
  }
  return null
}

function findDir(candidates) {
  for (const c of candidates) {
    try { if (fs.statSync(c).isDirectory()) return c } catch {}
  }
  return null
}

// Locate opencode source files
const srcBase = findDir([
  path.join(__dirname, "..", "packages", "opencode", "src"),
  path.join(process.cwd(), "packages", "opencode", "src"),
  path.join(__dirname, "..", "..", "packages", "opencode", "src"),
])

const ptyPath = srcBase
  ? path.join(srcBase, "pty", "pty.node.ts")
  : findFile([path.join(__dirname, "..", "pty", "pty.node.ts")])

const dbNodePath = srcBase
  ? path.join(__dirname, "storage", "db.node.ts")
  : null

const aliasMap = {
  "bun:sqlite": path.join(__dirname, "bun-sqlite-shim.ts"),
  "bun:ffi": path.join(__dirname, "shims", "bun-ffi.ts"),
  "bun": path.join(__dirname, "shims", "bun-module.ts"),
  "bun-pty": ptyPath,
  "#db": dbNodePath || path.join(__dirname, "storage", "db.node.ts"),
  "#pty": ptyPath,
}

export async function resolve(specifier, context, nextResolve) {
  if (aliasMap[specifier]) {
    return { shortCircuit: true, url: new URL(`file://${aliasMap[specifier]}`).href }
  }
  return nextResolve(specifier, context)
}
