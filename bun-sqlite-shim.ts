import DatabaseBetter from "better-sqlite3"

export class Database {
  private _db: DatabaseBetter.Database

  constructor(path: string, options?: { readonly?: boolean; create?: boolean }) {
    this._db = new DatabaseBetter(path, { readonly: options?.readonly ?? false })
    this._db.pragma("journal_mode = WAL")
    if (options?.create) this._db.pragma("journal_mode = WAL")
  }

  query(sql: string) {
    const stmt = this._db.prepare(sql)
    return {
      all: (params?: any) => stmt.all(params),
      get: (params?: any) => stmt.get(params),
      values: (params?: any) => stmt.raw().all(params),
      run: (params?: any) => stmt.run(params),
    }
  }

  run(sql: string, ...params: any[]) {
    return this._db.prepare(sql).run(...params)
  }

  prepare(sql: string) {
    return this._db.prepare(sql)
  }

  exec(sql: string) {
    return this._db.exec(sql)
  }

  close() {
    this._db.close()
  }

  transaction<T>(fn: (...args: any[]) => T): (...args: any[]) => T {
    return this._db.transaction(fn) as any
  }
}
