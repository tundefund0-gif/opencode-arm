import fs from "fs"
import process from "process"

class BunFile {
  constructor(p) { this._path = p }
  text() { return fs.readFileSync(this._path, "utf-8") }
  json() { return JSON.parse(fs.readFileSync(this._path, "utf-8")) }
  bytes() { return fs.readFileSync(this._path) }
  exists() { try { fs.accessSync(this._path); return true } catch { return false } }
}

globalThis.Bun = {
  file: (p) => new BunFile(p),
  write: (p, d) => {
    fs.writeFileSync(p, d)
    return Buffer.isBuffer(d) ? d.length : Buffer.byteLength(d)
  },
  stringWidth: (s) => {
    if (!s) return 0
    let w = 0
    for (const ch of s) {
      const cp = ch.codePointAt(0)
      if (!cp) continue
      if (cp >= 0x3000 || (cp >= 0x1100 && cp <= 0x115f)) w += 2
      else if (
        (cp >= 0x2e80 && cp <= 0x303e) || (cp >= 0x3040 && cp <= 0x309f) ||
        (cp >= 0x30a0 && cp <= 0x30ff) || (cp >= 0x3100 && cp <= 0x312f) ||
        (cp >= 0x3130 && cp <= 0x318f) || (cp >= 0x3190 && cp <= 0x31ff) ||
        (cp >= 0x3200 && cp <= 0x4dbf) || (cp >= 0x4e00 && cp <= 0x9fff) ||
        (cp >= 0xac00 && cp <= 0xd7af) || (cp >= 0xf900 && cp <= 0xfaff) ||
        (cp >= 0x1f300 && cp <= 0x1f9ff)
      ) w += 2
      else if (cp >= 0x200b && cp <= 0x200f || cp === 0x200d || cp >= 0xfe00 && cp <= 0xfe0f) w += 0
      else w += 1
    }
    return w
  },
  get stdin() {
    return {
      text: () => new Promise(r => {
        const c = []; process.stdin.on("data", d => c.push(Buffer.from(d)))
        process.stdin.on("end", () => r(Buffer.concat(c).toString("utf-8")))
      })
    }
  },
  escapeHTML: (s) => s.replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;").replace(/"/g,"&quot;").replace(/'/g,"&#39;"),
  sleep: (ms) => new Promise(r => setTimeout(r, ms)),
  deepEquals: (a,b) => JSON.stringify(a) === JSON.stringify(b),
  get version() { return "1.3.14" },
  unsafe: () => ({
    html: (s,...v) => String.raw(s,...v)
  }),
  get $() { return undefined },
}
