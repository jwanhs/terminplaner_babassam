// In-memory stand-in for AppwriteDb, faithful about the two behaviours the
// booking logic actually leans on: unique-index violations (the double-booking
// guard) and the subset of query methods the function issues.

import { isUniqueViolation } from '../src/appwrite.js';

export class FakeDb {
  constructor(seed = {}) {
    /** @type {Record<string, Map<string, object>>} */
    this.tables = {};
    for (const [table, rows] of Object.entries(seed)) {
      this.tables[table] = new Map(rows.map((r) => [r.$id, { ...r }]));
    }
    // table -> column that carries a unique index
    this.unique = { appointments: 'slot_key', rate_limits: 'bucket' };
    this.clock = Date.parse('2026-08-21T03:00:00Z');
  }

  #table(id) {
    if (!this.tables[id]) this.tables[id] = new Map();
    return this.tables[id];
  }

  async getRow(tableId, rowId) {
    return this.#table(tableId).get(rowId) ?? null;
  }

  async createRow(tableId, rowId, data) {
    const t = this.#table(tableId);
    if (t.has(rowId)) throw uniqueError();
    const col = this.unique[tableId];
    if (col && data[col] != null) {
      for (const r of t.values()) if (r[col] === data[col]) throw uniqueError();
    }
    const row = {
      ...data,
      $id: rowId,
      $createdAt: new Date(this.clock++).toISOString(),
      $updatedAt: new Date(this.clock).toISOString(),
    };
    t.set(rowId, row);
    return { ...row };
  }

  async updateRow(tableId, rowId, data) {
    const t = this.#table(tableId);
    const existing = t.get(rowId);
    if (!existing) { const e = new Error('not found'); e.status = 404; throw e; }
    const col = this.unique[tableId];
    if (col && data[col] != null) {
      for (const [id, r] of t) if (id !== rowId && r[col] === data[col]) throw uniqueError();
    }
    const row = { ...existing, ...data, $updatedAt: new Date(this.clock++).toISOString() };
    t.set(rowId, row);
    return { ...row };
  }

  async deleteRow(tableId, rowId) {
    this.#table(tableId).delete(rowId);
    return {};
  }

  async listRows(tableId, queries = []) {
    let rows = [...this.#table(tableId).values()];
    let limit = 25;

    for (const q of queries) {
      const { method, attribute, values } = q;
      switch (method) {
        case 'equal':
          rows = rows.filter((r) => values.includes(r[attribute]));
          break;
        case 'notEqual':
          rows = rows.filter((r) => !values.includes(r[attribute]));
          break;
        case 'greaterThanEqual':
          rows = rows.filter((r) => cmp(r[attribute], values[0]) >= 0);
          break;
        case 'lessThan':
          rows = rows.filter((r) => cmp(r[attribute], values[0]) < 0);
          break;
        case 'orderAsc':
          rows.sort((a, b) => cmp(a[attribute], b[attribute]));
          break;
        case 'orderDesc':
          rows.sort((a, b) => cmp(b[attribute], a[attribute]));
          break;
        case 'limit':
          limit = values[0];
          break;
        default:
          throw new Error(`FakeDb: unsupported query method "${method}"`);
      }
    }
    return rows.slice(0, limit).map((r) => ({ ...r }));
  }
}

function uniqueError() {
  const e = new Error('Document with the requested ID already exists');
  e.status = 409;
  e.type = 'document_already_exists';
  if (!isUniqueViolation(e)) throw new Error('FakeDb built an error the code will not recognise');
  return e;
}

function cmp(a, b) {
  const da = Date.parse(a);
  const db = Date.parse(b);
  if (Number.isFinite(da) && Number.isFinite(db)) return da - db;
  if (a === b) return 0;
  return a < b ? -1 : 1;
}

/** Captures what the handler passed to `res.json`. */
export function fakeRes() {
  const out = { status: 200, body: null };
  return {
    res: {
      json(body, status = 200) {
        out.body = body;
        out.status = status;
        return out;
      },
    },
    out,
  };
}
