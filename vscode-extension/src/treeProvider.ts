import * as vscode from 'vscode';
import { DatabaseSummary, SchemaResult, WorkbenchClient } from './api';

type Node = DatabaseNode | TableNode | ColumnNode | MessageNode;

export class DatabaseNode extends vscode.TreeItem {
  readonly kind = 'database' as const;
  constructor(public readonly db: DatabaseSummary) {
    super(db.name, vscode.TreeItemCollapsibleState.Expanded);
    this.id = `db:${db.id}`;
    this.iconPath = new vscode.ThemeIcon('database');
    this.tooltip = db.path;
    this.description = db.id === db.name ? undefined : db.path.split('/').pop();
    this.contextValue = 'database';
  }
}

export class TableNode extends vscode.TreeItem {
  readonly kind = 'table' as const;
  constructor(public readonly db: DatabaseSummary, public readonly tableName: string, public readonly rowCount?: number) {
    super(tableName, vscode.TreeItemCollapsibleState.Collapsed);
    this.id = `table:${db.id}:${tableName}`;
    this.iconPath = new vscode.ThemeIcon('table');
    this.contextValue = 'table';
    this.description = rowCount !== undefined ? `${rowCount} row${rowCount === 1 ? '' : 's'}` : undefined;
    this.command = {
      command: 'sqfliteDev.openTable',
      title: 'Open Table',
      arguments: [this],
    };
  }
}

export class ColumnNode extends vscode.TreeItem {
  readonly kind = 'column' as const;
  constructor(public readonly db: DatabaseSummary, public readonly tableName: string, public readonly columnName: string, type: string, pk: boolean, notNull: boolean) {
    super(columnName, vscode.TreeItemCollapsibleState.None);
    this.id = `col:${db.id}:${tableName}:${columnName}`;
    this.iconPath = new vscode.ThemeIcon(pk ? 'key' : 'symbol-field');
    const flags = [pk ? 'PK' : null, notNull ? 'NOT NULL' : null].filter(Boolean).join(' · ');
    this.description = flags ? `${type} · ${flags}` : type;
    this.contextValue = 'column';
  }
}

export class MessageNode extends vscode.TreeItem {
  readonly kind = 'message' as const;
  constructor(label: string, icon: string = 'info') {
    super(label, vscode.TreeItemCollapsibleState.None);
    this.iconPath = new vscode.ThemeIcon(icon);
    this.contextValue = 'message';
  }
}

export class WorkbenchTreeProvider implements vscode.TreeDataProvider<Node> {
  private readonly _onDidChangeTreeData = new vscode.EventEmitter<Node | undefined | void>();
  readonly onDidChangeTreeData = this._onDidChangeTreeData.event;

  private connected = false;
  private connecting = false;
  private lastError: string | null = null;
  private databases: DatabaseSummary[] = [];
  private readonly schemaCache = new Map<string, SchemaResult>();
  private readonly rowCountCache = new Map<string, number>();
  private tableFilter: string | null = null;

  constructor(private readonly client: WorkbenchClient) {}

  isConnected() {
    return this.connected;
  }

  isConnecting() {
    return this.connecting;
  }

  getLastError(): string | null {
    return this.lastError;
  }

  getDatabases(): readonly DatabaseSummary[] {
    return this.databases;
  }

  getTableFilter(): string | null {
    return this.tableFilter;
  }

  setTableFilter(q: string | null) {
    this.tableFilter = q && q.trim() ? q.trim() : null;
    this._onDidChangeTreeData.fire();
  }

  async refresh(): Promise<{ wasConnected: boolean; nowConnected: boolean }> {
    const wasConnected = this.connected;
    this.schemaCache.clear();
    this.rowCountCache.clear();
    this.connecting = true;
    this._onDidChangeTreeData.fire();
    try {
      this.databases = await this.client.listDatabases();
      this.connected = true;
      this.lastError = null;
    } catch (e) {
      this.connected = false;
      this.databases = [];
      this.lastError = (e as Error).message;
    } finally {
      this.connecting = false;
      this._onDidChangeTreeData.fire();
    }
    return { wasConnected, nowConnected: this.connected };
  }

  getTreeItem(element: Node): vscode.TreeItem {
    return element;
  }

  async getChildren(element?: Node): Promise<Node[]> {
    if (!element) {
      if (this.connecting && this.databases.length === 0) {
        return [new MessageNode('Connecting…', 'sync~spin')];
      }
      if (!this.connected) {
        return [];
      }
      if (this.databases.length === 0) {
        return [new MessageNode('No databases registered yet', 'circle-slash')];
      }
      return this.databases.map(db => new DatabaseNode(db));
    }

    if (element instanceof DatabaseNode) {
      try {
        const allTables = await this.client.listTables(element.db.id);
        const filter = this.tableFilter?.toLowerCase();
        const tables = filter
          ? allTables.filter(t => t.toLowerCase().includes(filter))
          : allTables;
        if (filter && tables.length === 0) {
          return [new MessageNode(`No tables match "${this.tableFilter}"`, 'circle-slash')];
        }
        const counts = await Promise.all(
          tables.map(async t => {
            const cacheKey = `${element.db.id}:${t}`;
            const cached = this.rowCountCache.get(cacheKey);
            if (cached !== undefined) return cached;
            try {
              const c = await this.client.getCount(element.db.id, t);
              this.rowCountCache.set(cacheKey, c);
              return c;
            } catch {
              return undefined;
            }
          }),
        );
        return tables.map((t, i) => new TableNode(element.db, t, counts[i]));
      } catch (err) {
        return [new MessageNode(`Failed to load tables: ${(err as Error).message}`, 'error')];
      }
    }

    if (element instanceof TableNode) {
      try {
        const cacheKey = `${element.db.id}:${element.tableName}`;
        let schema = this.schemaCache.get(cacheKey);
        if (!schema) {
          schema = await this.client.getSchema(element.db.id, element.tableName);
          this.schemaCache.set(cacheKey, schema);
        }
        return schema.columns.map(c => new ColumnNode(
          element.db,
          element.tableName,
          c.name,
          c.type || 'BLOB',
          c.pk > 0,
          c.notnull > 0,
        ));
      } catch (err) {
        return [new MessageNode(`Failed to load schema: ${(err as Error).message}`, 'error')];
      }
    }

    return [];
  }

  async getSchema(dbId: string, table: string): Promise<SchemaResult> {
    const cacheKey = `${dbId}:${table}`;
    let schema = this.schemaCache.get(cacheKey);
    if (!schema) {
      schema = await this.client.getSchema(dbId, table);
      this.schemaCache.set(cacheKey, schema);
    }
    return schema;
  }
}

export type { Node };
