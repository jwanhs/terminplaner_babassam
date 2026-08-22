// Minimal Appwrite Tables-API client over fetch.
//
// Deliberately not the node-appwrite SDK: this function needs six REST calls,
// and a dependency-light function is a function that still deploys in two
// years. Node 22's global fetch does the rest.
//
// The API key here is a *server* key. It never leaves the function container —
// that asymmetry is the whole security model: the client may not touch the
// appointments table, this may.

let dispatcher; // lazily built, only when insecure TLS is explicitly opted into

/**
 * Self-hosted Appwrite behind a self-signed certificate needs verification
 * relaxed for function→Appwrite calls. Unlike the old code this is opt-in via
 * APPWRITE_INSECURE_TLS rather than always-on, so a Cloud or properly-certified
 * deployment keeps full validation.
 */
async function insecureDispatcher() {
  if (dispatcher !== undefined) return dispatcher;
  if (String(process.env.APPWRITE_INSECURE_TLS) !== 'true') {
    dispatcher = null;
    return dispatcher;
  }

  // FIX: Appwrite's sandbox doesn't expose Web Streams globally by default.
  // undici 6+ requires them during module initialization, so we inject them here.
  if (!globalThis.ReadableStream) {
    const webStreams = await import('node:stream/web');
    Object.assign(globalThis, webStreams);
  }

  const { Agent } = await import('undici');
  dispatcher = new Agent({ connect: { rejectUnauthorized: false } });
  return dispatcher;
}

export class AppwriteDb {
  constructor({ endpoint, projectId, apiKey, databaseId }) {
    // Appwrite injects APPWRITE_FUNCTION_API_ENDPOINT as plain http://, but
    // the self-hosted proxy 301-redirects http -> https. undici's request()
    // (unlike fetch) does not follow redirects, so that 301's HTML body was
    // silently swallowed as "no rows" on every call. Go straight to https.
    this.endpoint = String(endpoint || '').replace(/\/+$/, '').replace(/^http:\/\//, 'https://');
    this.projectId = projectId;
    this.apiKey = apiKey;
    this.databaseId = databaseId;
  }

  get headers() {
    return {
      'X-Appwrite-Project': this.projectId,
      'X-Appwrite-Key': this.apiKey,
      'Content-Type': 'application/json',
    };
  }

  async #send(method, path, { body, query } = {}) {
    const url = new URL(`${this.endpoint}/tablesdb/${this.databaseId}${path}`);
    for (const q of query ?? []) url.searchParams.append('queries[]', q);

    const init = { method, headers: this.headers };
    if (body !== undefined) init.body = JSON.stringify(body);

    const d = await insecureDispatcher();
    if (d) init.dispatcher = d;

    // Use undici's native request to bypass sandbox AbortSignal bugs
    const { request } = await import('undici');
    const res = await request(url, init);

    const text = await res.body.text();
    let json = null;
    try { json = text ? JSON.parse(text) : null; } catch { /* non-JSON error page */ }

    if (res.statusCode >= 400) {
      const err = new Error(json?.message || `Appwrite ${res.statusCode}: ${text.slice(0, 200)}`);
      err.status = res.statusCode;
      err.type = json?.type;
      throw err;
    }
    return json;
  }

  listRows(tableId, queries = []) {
    return this.#send('GET', `/tables/${tableId}/rows`, { query: queries.map(JSON.stringify) })
      .then((r) => r?.rows ?? []);
  }

  async getRow(tableId, rowId) {
    try {
      return await this.#send('GET', `/tables/${tableId}/rows/${encodeURIComponent(rowId)}`);
    } catch (e) {
      if (e.status === 404) return null;
      throw e;
    }
  }

  createRow(tableId, rowId, data) {
    return this.#send('POST', `/tables/${tableId}/rows`, {
      // Rows carry no client permissions of their own. Access is decided by
      // the table-level grant (staff) and by this function.
      body: { rowId, data, permissions: [] },
    });
  }

  updateRow(tableId, rowId, data) {
    return this.#send('PATCH', `/tables/${tableId}/rows/${encodeURIComponent(rowId)}`, {
      body: { data },
    });
  }

  deleteRow(tableId, rowId) {
    return this.#send('DELETE', `/tables/${tableId}/rows/${encodeURIComponent(rowId)}`);
  }
}

// --- query builders ----------------------------------------------------------
export const Q = {
  equal: (attribute, values) => ({ method: 'equal', attribute, values: [].concat(values) }),
  notEqual: (attribute, values) => ({ method: 'notEqual', attribute, values: [].concat(values) }),
  greaterThanEqual: (attribute, value) => ({ method: 'greaterThanEqual', attribute, values: [value] }),
  lessThan: (attribute, value) => ({ method: 'lessThan', attribute, values: [value] }),
  orderAsc: (attribute) => ({ method: 'orderAsc', attribute }),
  orderDesc: (attribute) => ({ method: 'orderDesc', attribute }),
  limit: (value) => ({ method: 'limit', values: [value] }),
};

/** True when an error is Appwrite refusing a duplicate on a unique index. */
export function isUniqueViolation(e) {
  return e?.status === 409 ||
    e?.type === 'document_already_exists' ||
    e?.type === 'row_already_exists';
}
