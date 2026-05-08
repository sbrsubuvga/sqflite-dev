import * as http from 'http';

export interface DatabaseSummary {
  id: string;
  name: string;
  path: string;
}

export interface DatabaseInfo extends DatabaseSummary {
  size: number;
  tableCount: number;
  sqliteVersion: string | null;
  userVersion: number | null;
  schemaVersion: number | null;
  pageSize: number | null;
  pageCount: number | null;
  encoding: string | null;
  journalMode: string | null;
  foreignKeys: number | null;
  autoVacuum: number | null;
}

export interface ColumnInfo {
  cid: number;
  name: string;
  type: string;
  notnull: number;
  dflt_value: unknown;
  pk: number;
}

export interface ForeignKeyInfo {
  id: number;
  seq: number;
  table: string;
  from: string;
  to: string;
  on_update: string;
  on_delete: string;
  match: string;
}

export interface SchemaResult {
  columns: ColumnInfo[];
  foreignKeys: ForeignKeyInfo[];
  createTable: string | null;
  indexes: { name: string; sql: string | null }[];
  indexList: {
    name: string;
    unique: number;
    origin: string;
    partial: number;
    columns: string[];
    sql: string | null;
  }[];
  triggers: { name: string; sql: string | null }[];
}

export interface QueryResult {
  data: Record<string, unknown>[];
  executionTime: number;
  rowCount: number;
  affectedRows?: number;
  error?: string;
}

export interface PaginatedRows {
  data: Record<string, unknown>[];
  pagination: {
    page: number;
    limit: number;
    total: number;
    totalPages: number;
  };
}

export class WorkbenchClient {
  constructor(private host: string, private port: number) {}

  update(host: string, port: number) {
    this.host = host;
    this.port = port;
  }

  get baseUrl(): string {
    return `http://${this.host}:${this.port}`;
  }

  listDatabases(): Promise<DatabaseSummary[]> {
    return this.get<{ databases: DatabaseSummary[] }>('/api/databases').then(r => r.databases);
  }

  getInfo(dbId: string): Promise<DatabaseInfo> {
    return this.get<DatabaseInfo>(`/api/databases/${encodeURIComponent(dbId)}/info`);
  }

  listTables(dbId: string): Promise<string[]> {
    return this.get<{ tables: string[] }>(`/api/databases/${encodeURIComponent(dbId)}/tables`).then(r => r.tables);
  }

  getCount(dbId: string, table: string): Promise<number> {
    return this.get<{ count: number }>(
      `/api/databases/${encodeURIComponent(dbId)}/table/${encodeURIComponent(table)}/count`,
    ).then(r => r.count);
  }

  getRows(dbId: string, table: string, page = 1, limit = 50): Promise<PaginatedRows> {
    return this.get<PaginatedRows>(
      `/api/databases/${encodeURIComponent(dbId)}/table/${encodeURIComponent(table)}?page=${page}&limit=${limit}`,
    );
  }

  getSchema(dbId: string, table: string): Promise<SchemaResult> {
    return this.get<SchemaResult>(
      `/api/databases/${encodeURIComponent(dbId)}/schema/${encodeURIComponent(table)}`,
    );
  }

  query(dbId: string, sql: string): Promise<QueryResult> {
    return this.post<QueryResult>(
      `/api/databases/${encodeURIComponent(dbId)}/query`,
      { query: sql },
    );
  }

  batch(dbId: string, statements: string[]): Promise<{ ok?: boolean; executed?: number; executionTime: number; error?: string }> {
    return this.post(`/api/databases/${encodeURIComponent(dbId)}/batch`, { statements });
  }

  async ping(timeoutMs = 1500): Promise<boolean> {
    try {
      await this.get('/api/databases', timeoutMs);
      return true;
    } catch {
      return false;
    }
  }

  private get<T>(path: string, timeoutMs = 5000): Promise<T> {
    return this.request<T>('GET', path, undefined, timeoutMs);
  }

  private post<T>(path: string, body: unknown, timeoutMs = 30_000): Promise<T> {
    return this.request<T>('POST', path, body, timeoutMs);
  }

  private request<T>(method: string, path: string, body: unknown, timeoutMs: number): Promise<T> {
    return new Promise<T>((resolve, reject) => {
      const payload = body === undefined ? undefined : Buffer.from(JSON.stringify(body), 'utf8');
      const req = http.request(
        {
          host: this.host,
          port: this.port,
          path,
          method,
          headers: {
            Accept: 'application/json',
            ...(payload ? { 'Content-Type': 'application/json', 'Content-Length': payload.length } : {}),
          },
          timeout: timeoutMs,
        },
        res => {
          const chunks: Buffer[] = [];
          res.on('data', c => chunks.push(c));
          res.on('end', () => {
            const text = Buffer.concat(chunks).toString('utf8');
            const status = res.statusCode ?? 0;
            if (status < 200 || status >= 300) {
              reject(new Error(`HTTP ${status}: ${text || res.statusMessage}`));
              return;
            }
            try {
              resolve(text ? (JSON.parse(text) as T) : (undefined as T));
            } catch (e) {
              reject(new Error(`Invalid JSON from ${path}: ${(e as Error).message}`));
            }
          });
        },
      );
      req.on('error', reject);
      req.on('timeout', () => {
        req.destroy(new Error(`Request to ${path} timed out after ${timeoutMs}ms`));
      });
      if (payload) {
        req.write(payload);
      }
      req.end();
    });
  }
}
