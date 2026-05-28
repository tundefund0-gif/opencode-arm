/* bun:ffi stub for non-Windows platforms */

export function dlopen(_lib: string, _symbols: Record<string, any>) {
  return {
    symbols: {},
  }
}

export function ptr(_buf: Uint8Array): number {
  return 0
}
