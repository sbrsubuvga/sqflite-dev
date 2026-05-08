import * as vscode from 'vscode';
import { DatabaseInfo, SchemaResult, WorkbenchClient } from './api';

const PAGE_SIZE_OPTIONS = [25, 50, 100, 200, 500];
const DEFAULT_PAGE_SIZE = 50;

function nonce(): string {
  let s = '';
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  for (let i = 0; i < 32; i++) {
    s += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return s;
}

function isSafeIdent(s: string): boolean {
  return /^[A-Za-z_][A-Za-z0-9_]*$/.test(s);
}

export class WorkbenchPanel {
  private static current: WorkbenchPanel | undefined;

  static show(baseUrl: string) {
    if (WorkbenchPanel.current) {
      WorkbenchPanel.current.panel.reveal();
      WorkbenchPanel.current.update(baseUrl);
      return;
    }
    const panel = vscode.window.createWebviewPanel(
      'sqfliteDev.workbench',
      'sqflite_dev Workbench',
      vscode.ViewColumn.One,
      {
        enableScripts: true,
        retainContextWhenHidden: true,
      },
    );
    WorkbenchPanel.current = new WorkbenchPanel(panel, baseUrl);
  }

  private constructor(private readonly panel: vscode.WebviewPanel, baseUrl: string) {
    panel.onDidDispose(() => {
      WorkbenchPanel.current = undefined;
    });
    this.update(baseUrl);
  }

  private update(baseUrl: string) {
    const n = nonce();
    const csp = [
      `default-src 'none'`,
      `frame-src ${baseUrl}`,
      `style-src 'unsafe-inline'`,
      `script-src 'nonce-${n}'`,
    ].join('; ');

    this.panel.webview.html = /* html */ `
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8" />
  <meta http-equiv="Content-Security-Policy" content="${csp}" />
  <style>
    html, body { margin: 0; padding: 0; height: 100%; background: var(--vscode-editor-background); }
    iframe { width: 100%; height: 100vh; border: 0; display: block; }
    .err { padding: 24px; font-family: var(--vscode-font-family); color: var(--vscode-errorForeground); }
  </style>
</head>
<body>
  <iframe id="wb" src="${baseUrl}" sandbox="allow-scripts allow-forms allow-same-origin allow-popups allow-downloads"></iframe>
  <script nonce="${n}">
    const f = document.getElementById('wb');
    f.addEventListener('error', () => {
      document.body.innerHTML = '<div class="err">Could not load workbench at ${baseUrl}. Make sure your app is running.</div>';
    });
  </script>
</body>
</html>`;
  }
}

interface TablePanelState {
  dbId: string;
  table: string;
  page: number;
  pageSize: number;
  totalPages: number;
  total: number;
  rows: Record<string, unknown>[];
  schema: SchemaResult | null;
  view: 'data' | 'structure';
  sortCol: string | null;
  sortDir: 'asc' | 'desc';
  filter: string;
  detailIndex: number | null;
  detailMode: 'view' | 'edit' | 'insert';
  hasRowid: boolean;
  withoutRowidChecked: boolean;
}

export class TablePanel {
  private static panels = new Map<string, TablePanel>();

  static show(client: WorkbenchClient, dbId: string, table: string) {
    const key = `${dbId}::${table}`;
    const existing = TablePanel.panels.get(key);
    if (existing) {
      existing.panel.reveal();
      return;
    }
    const panel = vscode.window.createWebviewPanel(
      'sqfliteDev.table',
      `${table} (${dbId})`,
      vscode.ViewColumn.Active,
      {
        enableScripts: true,
        retainContextWhenHidden: true,
      },
    );
    TablePanel.panels.set(key, new TablePanel(panel, client, dbId, table, key));
  }

  private state: TablePanelState;

  private constructor(
    private readonly panel: vscode.WebviewPanel,
    private readonly client: WorkbenchClient,
    dbId: string,
    table: string,
    private readonly key: string,
  ) {
    this.state = {
      dbId,
      table,
      page: 1,
      pageSize: DEFAULT_PAGE_SIZE,
      totalPages: 1,
      total: 0,
      rows: [],
      schema: null,
      view: 'data',
      sortCol: null,
      sortDir: 'asc',
      filter: '',
      detailIndex: null,
      detailMode: 'view',
      hasRowid: true,
      withoutRowidChecked: false,
    };
    panel.onDidDispose(() => {
      TablePanel.panels.delete(this.key);
    });
    panel.webview.onDidReceiveMessage(msg => this.onMessage(msg));
    void this.init();
  }

  private async init() {
    await this.loadSchema();
    if (this.state.schema?.createTable && /WITHOUT\s+ROWID/i.test(this.state.schema.createTable)) {
      this.state.hasRowid = false;
    }
    this.state.withoutRowidChecked = true;
    await this.loadData();
  }

  private async onMessage(msg: { type: string; [k: string]: unknown }) {
    switch (msg.type) {
      case 'page':
        this.state.page = Math.max(1, Math.min(Number(msg.page) || 1, this.state.totalPages));
        await this.loadData();
        break;
      case 'pageSize': {
        const next = Number(msg.size) || DEFAULT_PAGE_SIZE;
        if (next === this.state.pageSize) break;
        this.state.pageSize = next;
        this.state.page = 1;
        await this.loadData();
        break;
      }
      case 'refresh':
        await this.loadData();
        break;
      case 'view':
        this.state.view = msg.view === 'structure' ? 'structure' : 'data';
        if (this.state.view === 'structure' && !this.state.schema) {
          await this.loadSchema();
        }
        this.render();
        break;
      case 'sort': {
        const col = String(msg.col ?? '');
        if (!col) break;
        if (this.state.sortCol === col) {
          this.state.sortDir = this.state.sortDir === 'asc' ? 'desc' : 'asc';
        } else {
          this.state.sortCol = col;
          this.state.sortDir = 'asc';
        }
        this.state.page = 1;
        await this.loadData();
        break;
      }
      case 'clearSort':
        this.state.sortCol = null;
        this.state.sortDir = 'asc';
        await this.loadData();
        break;
      case 'filter':
        this.state.filter = String(msg.q ?? '');
        this.render();
        break;
      case 'detail':
        this.state.detailIndex = msg.index === null || msg.index === undefined ? null : Number(msg.index);
        this.state.detailMode = 'view';
        this.render();
        break;
      case 'detailMode':
        this.state.detailMode = (msg.mode === 'edit' || msg.mode === 'insert') ? msg.mode : 'view';
        this.render();
        break;
      case 'rowInsert':
        this.state.detailIndex = -1;
        this.state.detailMode = 'insert';
        this.render();
        break;
      case 'rowSave':
        await this.saveRow(msg.values as Record<string, string | null>);
        break;
      case 'rowDelete':
        await this.deleteRow();
        break;
      case 'export':
        await this.exportData(String(msg.format ?? 'csv') as 'csv' | 'json');
        break;
    }
  }

  private async saveRow(values: Record<string, string | null>) {
    const t = quoteIdent(this.state.table);
    const cols = this.state.schema?.columns.map(c => c.name) ?? [];
    if (cols.length === 0) {
      vscode.window.showErrorMessage('sqflite_dev: schema not loaded.');
      return;
    }

    if (this.state.detailMode === 'insert') {
      const provided = cols.filter(c => values[c] !== undefined);
      if (provided.length === 0) {
        vscode.window.showWarningMessage('sqflite_dev: no values entered.');
        return;
      }
      const colList = provided.map(quoteIdent).join(', ');
      const valList = provided.map(c => sqlLiteral(values[c])).join(', ');
      const sql = `INSERT INTO ${t} (${colList}) VALUES (${valList})`;
      const ok = await confirmWrite(`Insert 1 row into "${this.state.table}"?`);
      if (!ok) return;
      await this.execAndRefresh(sql, 'Inserted row');
      return;
    }

    if (this.state.detailMode === 'edit') {
      if (!this.state.hasRowid) {
        vscode.window.showErrorMessage('sqflite_dev: cannot edit rows of a WITHOUT ROWID table (no PK-based editor yet).');
        return;
      }
      const idx = this.state.detailIndex;
      if (idx === null || idx < 0) return;
      const row = this.state.rows[idx];
      const rowid = row?.['__rowid'];
      if (rowid === undefined || rowid === null) {
        vscode.window.showErrorMessage('sqflite_dev: missing rowid for edit.');
        return;
      }
      const changed = cols.filter(c => values[c] !== undefined && !sameValue(row[c], values[c]));
      if (changed.length === 0) {
        this.state.detailMode = 'view';
        this.render();
        return;
      }
      const setClause = changed.map(c => `${quoteIdent(c)} = ${sqlLiteral(values[c])}`).join(', ');
      const sql = `UPDATE ${t} SET ${setClause} WHERE rowid = ${Number(rowid)}`;
      const ok = await confirmWrite(`Update ${changed.length} field${changed.length === 1 ? '' : 's'} on this row?`);
      if (!ok) return;
      await this.execAndRefresh(sql, 'Row updated');
    }
  }

  private async deleteRow() {
    if (!this.state.hasRowid) {
      vscode.window.showErrorMessage('sqflite_dev: cannot delete rows of a WITHOUT ROWID table (no PK-based editor yet).');
      return;
    }
    const idx = this.state.detailIndex;
    if (idx === null || idx < 0) return;
    const row = this.state.rows[idx];
    const rowid = row?.['__rowid'];
    if (rowid === undefined || rowid === null) return;
    const ok = await confirmWrite(`Delete this row from "${this.state.table}"? This cannot be undone.`, 'Delete');
    if (!ok) return;
    const t = quoteIdent(this.state.table);
    const sql = `DELETE FROM ${t} WHERE rowid = ${Number(rowid)}`;
    await this.execAndRefresh(sql, 'Row deleted');
  }

  private async execAndRefresh(sql: string, successMessage: string) {
    try {
      const result = await this.client.query(this.state.dbId, sql);
      if (result.error) {
        vscode.window.showErrorMessage(`sqflite_dev: ${result.error}`);
        return;
      }
      vscode.window.showInformationMessage(`sqflite_dev: ${successMessage}.`);
      this.state.detailIndex = null;
      this.state.detailMode = 'view';
      await this.loadData();
    } catch (e) {
      vscode.window.showErrorMessage(`sqflite_dev: ${(e as Error).message}`);
    }
  }

  private async loadData() {
    try {
      const t = quoteIdent(this.state.table);
      const offset = (this.state.page - 1) * this.state.pageSize;
      const orderBy = this.state.sortCol
        ? ` ORDER BY ${quoteIdent(this.state.sortCol)} ${this.state.sortDir === 'desc' ? 'DESC' : 'ASC'}`
        : '';
      const limit = ` LIMIT ${this.state.pageSize} OFFSET ${offset}`;

      let result;
      if (this.state.hasRowid) {
        try {
          result = await this.client.query(this.state.dbId, `SELECT rowid AS __rowid, * FROM ${t}${orderBy}${limit}`);
        } catch {
          this.state.hasRowid = false;
          result = await this.client.query(this.state.dbId, `SELECT * FROM ${t}${orderBy}${limit}`);
        }
      } else {
        result = await this.client.query(this.state.dbId, `SELECT * FROM ${t}${orderBy}${limit}`);
      }
      this.state.rows = result.data;

      const countResult = await this.client.query(this.state.dbId, `SELECT COUNT(*) AS c FROM ${t}`);
      this.state.total = Number(countResult.data[0]?.c ?? 0);
      this.state.totalPages = Math.max(1, Math.ceil(this.state.total / this.state.pageSize));
      if (this.state.page > this.state.totalPages) this.state.page = this.state.totalPages;
    } catch (e) {
      vscode.window.showErrorMessage(`sqflite_dev: ${(e as Error).message}`);
    }
    this.render();
  }

  private async loadSchema() {
    try {
      this.state.schema = await this.client.getSchema(this.state.dbId, this.state.table);
    } catch (e) {
      vscode.window.showErrorMessage(`sqflite_dev: ${(e as Error).message}`);
    }
  }

  private async exportData(format: 'csv' | 'json') {
    const ext = format === 'csv' ? 'csv' : 'json';
    const target = await vscode.window.showSaveDialog({
      defaultUri: vscode.Uri.file(`${this.state.table}.${ext}`),
      filters: format === 'csv' ? { CSV: ['csv'] } : { JSON: ['json'] },
    });
    if (!target) return;

    await vscode.window.withProgress(
      { location: vscode.ProgressLocation.Notification, title: `Exporting ${this.state.table}…` },
      async () => {
        try {
          const t = quoteIdent(this.state.table);
          let sql = `SELECT * FROM ${t}`;
          if (this.state.sortCol) {
            sql += ` ORDER BY ${quoteIdent(this.state.sortCol)} ${this.state.sortDir === 'desc' ? 'DESC' : 'ASC'}`;
          }
          const result = await this.client.query(this.state.dbId, sql);
          const rows = result.data;
          const text = format === 'csv' ? toCsv(rows) : JSON.stringify(rows, null, 2);
          await vscode.workspace.fs.writeFile(target, Buffer.from(text, 'utf8'));
          vscode.window.showInformationMessage(`Exported ${rows.length} rows to ${target.fsPath}`);
        } catch (e) {
          vscode.window.showErrorMessage(`sqflite_dev export: ${(e as Error).message}`);
        }
      },
    );
  }

  private filteredRows(): Record<string, unknown>[] {
    const q = this.state.filter.trim().toLowerCase();
    if (!q) return this.state.rows;
    return this.state.rows.filter(r =>
      Object.values(r).some(v => v !== null && v !== undefined && String(v).toLowerCase().includes(q)),
    );
  }

  private render() {
    const n = nonce();
    const csp = [
      `default-src 'none'`,
      `style-src ${this.panel.webview.cspSource} 'unsafe-inline'`,
      `script-src 'nonce-${n}'`,
    ].join('; ');

    const detailModal = this.state.detailIndex !== null
      ? this.renderDetail(this.state.detailIndex)
      : '';

    this.panel.webview.html = /* html */ `
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8" />
  <meta http-equiv="Content-Security-Policy" content="${csp}" />
  <style>
    body { font-family: var(--vscode-font-family); color: var(--vscode-foreground); background: var(--vscode-editor-background); margin: 0; padding: 0; }
    .toolbar { display: flex; align-items: center; gap: 8px; padding: 8px 12px; border-bottom: 1px solid var(--vscode-panel-border); position: sticky; top: 0; background: var(--vscode-editor-background); z-index: 10; flex-wrap: wrap; }
    .toolbar h2 { margin: 0; font-size: 13px; font-weight: 600; }
    .pill { display: inline-flex; border: 1px solid var(--vscode-panel-border); border-radius: 4px; overflow: hidden; }
    .pill button { background: transparent; color: var(--vscode-foreground); border: 0; padding: 4px 10px; cursor: pointer; }
    .pill button.active { background: var(--vscode-button-background); color: var(--vscode-button-foreground); }
    button { background: var(--vscode-button-background); color: var(--vscode-button-foreground); border: 0; padding: 4px 10px; border-radius: 2px; cursor: pointer; font: inherit; }
    button:hover { background: var(--vscode-button-hoverBackground); }
    button:disabled { opacity: 0.5; cursor: not-allowed; }
    button.secondary { background: var(--vscode-button-secondaryBackground); color: var(--vscode-button-secondaryForeground); }
    button.danger { background: var(--vscode-errorForeground, #c62828); color: white; }
    button.secondary.active { background: var(--vscode-button-background); color: var(--vscode-button-foreground); }
    .spacer { flex: 1; }
    .body { padding: 12px; }
    table { border-collapse: collapse; width: 100%; font-size: 12px; font-family: var(--vscode-editor-font-family); }
    th, td { padding: 4px 8px; text-align: left; border-bottom: 1px solid var(--vscode-panel-border); white-space: nowrap; max-width: 320px; overflow: hidden; text-overflow: ellipsis; }
    th { position: sticky; top: 49px; background: var(--vscode-editorWidget-background); font-weight: 600; user-select: none; }
    th.sortable { cursor: pointer; }
    th .arrow { color: var(--vscode-descriptionForeground); margin-left: 4px; font-size: 10px; }
    th .arrow.active { color: var(--vscode-charts-blue, var(--vscode-textLink-foreground)); }
    tr.row { cursor: pointer; }
    tr.row:hover td { background: var(--vscode-list-hoverBackground); }
    .null { color: var(--vscode-disabledForeground); font-style: italic; }
    .pager { display: flex; align-items: center; gap: 8px; font-size: 12px; }
    .pager input, select, input[type="search"] { padding: 2px 6px; background: var(--vscode-input-background); color: var(--vscode-input-foreground); border: 1px solid var(--vscode-input-border); border-radius: 2px; font: inherit; }
    .pager input { width: 64px; }
    input[type="search"] { padding: 4px 8px; min-width: 200px; }
    .meta { color: var(--vscode-descriptionForeground); font-size: 12px; }
    pre { background: var(--vscode-textBlockQuote-background); padding: 12px; border-radius: 4px; overflow: auto; }
    code { font-family: var(--vscode-editor-font-family); }
    .badge { display: inline-block; padding: 1px 6px; border-radius: 3px; font-size: 10px; font-weight: 600; margin-right: 4px; }
    .badge.pk { background: #d97706; color: white; }
    .badge.nn { background: #6b7280; color: white; }
    .modal-bg { position: fixed; inset: 0; background: rgba(0,0,0,0.5); display: flex; align-items: center; justify-content: center; z-index: 100; }
    .modal { background: var(--vscode-editor-background); border: 1px solid var(--vscode-panel-border); border-radius: 6px; min-width: 480px; max-width: 80vw; max-height: 80vh; display: flex; flex-direction: column; box-shadow: 0 8px 32px rgba(0,0,0,0.4); }
    .modal-head { padding: 10px 14px; border-bottom: 1px solid var(--vscode-panel-border); display: flex; align-items: center; justify-content: space-between; }
    .modal-head h3 { margin: 0; font-size: 13px; }
    .modal-body { padding: 10px 14px; overflow: auto; }
    .kv { display: grid; grid-template-columns: max-content 1fr; gap: 4px 14px; font-size: 12px; font-family: var(--vscode-editor-font-family); }
    .kv .k { color: var(--vscode-descriptionForeground); padding: 4px 0; }
    .kv .v { padding: 4px 0; word-break: break-all; white-space: pre-wrap; }
  </style>
</head>
<body>
  <div class="toolbar">
    <h2>${escapeHtml(this.state.table)}</h2>
    <span class="meta">${this.state.total} row${this.state.total === 1 ? '' : 's'}</span>
    <div class="pill">
      <button id="viewData" class="${this.state.view === 'data' ? 'active' : ''}">Data</button>
      <button id="viewStructure" class="${this.state.view === 'structure' ? 'active' : ''}">Structure</button>
    </div>
    ${this.state.view === 'data' ? `
      <input type="search" id="filter" placeholder="Filter rows on this page…" value="${escapeAttr(this.state.filter)}" />
      ${this.state.sortCol ? `<button class="secondary" id="clearSort" title="Clear sort">Sort: ${escapeHtml(this.state.sortCol)} ${this.state.sortDir} ✕</button>` : ''}
    ` : ''}
    <span class="spacer"></span>
    ${this.state.view === 'data' ? `
      ${this.state.hasRowid && this.state.schema ? `<button id="insertRow">+ Insert Row</button>` : ''}
      <button class="secondary" id="exportCsv">Export CSV</button>
      <button class="secondary" id="exportJson">Export JSON</button>
    ` : ''}
    <button class="secondary" id="refresh">Refresh</button>
  </div>
  ${this.state.view === 'data' ? this.renderData() : this.renderStructure()}
  ${detailModal}
  <script nonce="${n}">
    const vscode = acquireVsCodeApi();
    const $ = id => document.getElementById(id);
    $('viewData').onclick = () => vscode.postMessage({ type: 'view', view: 'data' });
    $('viewStructure').onclick = () => vscode.postMessage({ type: 'view', view: 'structure' });
    $('refresh').onclick = () => vscode.postMessage({ type: 'refresh' });
    if ($('clearSort')) $('clearSort').onclick = () => vscode.postMessage({ type: 'clearSort' });
    if ($('exportCsv')) $('exportCsv').onclick = () => vscode.postMessage({ type: 'export', format: 'csv' });
    if ($('exportJson')) $('exportJson').onclick = () => vscode.postMessage({ type: 'export', format: 'json' });
    if ($('filter')) {
      let t;
      $('filter').addEventListener('input', e => {
        clearTimeout(t);
        const q = e.target.value;
        t = setTimeout(() => vscode.postMessage({ type: 'filter', q }), 150);
      });
    }
    if ($('prev')) $('prev').onclick = () => vscode.postMessage({ type: 'page', page: ${this.state.page - 1} });
    if ($('next')) $('next').onclick = () => vscode.postMessage({ type: 'page', page: ${this.state.page + 1} });
    if ($('goto')) $('goto').addEventListener('change', e => vscode.postMessage({ type: 'page', page: Number(e.target.value) }));
    if ($('pageSize')) $('pageSize').addEventListener('change', e => vscode.postMessage({ type: 'pageSize', size: Number(e.target.value) }));
    document.querySelectorAll('th[data-sort]').forEach(th => {
      th.addEventListener('click', () => vscode.postMessage({ type: 'sort', col: th.dataset.sort }));
    });
    document.querySelectorAll('tr[data-idx]').forEach(tr => {
      tr.addEventListener('click', () => vscode.postMessage({ type: 'detail', index: Number(tr.dataset.idx) }));
    });
    if ($('closeDetail')) $('closeDetail').onclick = () => vscode.postMessage({ type: 'detail', index: null });
    if ($('detailBg')) $('detailBg').addEventListener('click', e => {
      if (e.target === $('detailBg')) vscode.postMessage({ type: 'detail', index: null });
    });
    if ($('insertRow')) $('insertRow').onclick = () => vscode.postMessage({ type: 'rowInsert' });
    if ($('detailEdit')) $('detailEdit').onclick = () => vscode.postMessage({ type: 'detailMode', mode: 'edit' });
    if ($('detailDelete')) $('detailDelete').onclick = () => vscode.postMessage({ type: 'rowDelete' });
    if ($('detailCancel')) $('detailCancel').onclick = () => vscode.postMessage({ type: 'detail', index: null });
    document.querySelectorAll('button[data-null-toggle]').forEach(btn => {
      btn.addEventListener('click', () => {
        const input = btn.previousElementSibling;
        const isNull = btn.classList.toggle('active');
        if (input) {
          input.disabled = isNull;
          if (isNull) { input.dataset.wasValue = input.value; input.value = ''; input.placeholder = 'NULL'; }
          else { input.value = input.dataset.wasValue || ''; input.placeholder = ''; }
        }
      });
    });
    if ($('detailSave')) $('detailSave').onclick = () => {
      const values = {};
      document.querySelectorAll('input[data-col], textarea[data-col]').forEach(el => {
        const col = el.dataset.col;
        if (el.disabled) values[col] = null;
        else values[col] = el.value;
      });
      vscode.postMessage({ type: 'rowSave', values });
    };
  </script>
</body>
</html>`;
  }

  private renderData(): string {
    if (this.state.rows.length === 0) {
      return `<div class="body"><p class="meta">No rows.</p></div>`;
    }
    const rows = this.filteredRows();
    const cols = Object.keys(this.state.rows[0]).filter(c => c !== '__rowid');
    const head = cols.map(c => {
      const isSorted = this.state.sortCol === c;
      const arrow = isSorted ? (this.state.sortDir === 'asc' ? '▲' : '▼') : '↕';
      const safeForSort = isSafeIdent(c);
      const cls = safeForSort ? 'sortable' : '';
      const attr = safeForSort ? ` data-sort="${escapeAttr(c)}"` : '';
      return `<th class="${cls}"${attr}>${escapeHtml(c)}<span class="arrow${isSorted ? ' active' : ''}">${arrow}</span></th>`;
    }).join('');

    const body = rows.map((r, i) => {
      const cells = cols.map(c => {
        const v = r[c];
        if (v === null || v === undefined) return `<td class="null">NULL</td>`;
        return `<td title="${escapeAttr(String(v))}">${escapeHtml(truncate(String(v), 200))}</td>`;
      }).join('');
      return `<tr class="row" data-idx="${i}">${cells}</tr>`;
    }).join('');

    const sizeOpts = PAGE_SIZE_OPTIONS.map(s =>
      `<option value="${s}" ${s === this.state.pageSize ? 'selected' : ''}>${s} / page</option>`,
    ).join('');

    const filteredNote = this.state.filter
      ? `<span class="meta">${rows.length} of ${this.state.rows.length} on page</span>`
      : '';

    const pager = `
      <div class="body" style="display:flex;align-items:center;gap:12px;border-bottom:1px solid var(--vscode-panel-border);flex-wrap:wrap">
        <div class="pager">
          <button id="prev" ${this.state.page <= 1 ? 'disabled' : ''}>‹ Prev</button>
          <span>Page <input id="goto" type="number" min="1" max="${this.state.totalPages}" value="${this.state.page}"/> of ${this.state.totalPages}</span>
          <button id="next" ${this.state.page >= this.state.totalPages ? 'disabled' : ''}>Next ›</button>
        </div>
        <select id="pageSize">${sizeOpts}</select>
        ${filteredNote}
      </div>`;

    return `${pager}<div class="body" style="overflow:auto"><table><thead><tr>${head}</tr></thead><tbody>${body}</tbody></table></div>`;
  }

  private renderDetail(index: number): string {
    const mode = this.state.detailMode;
    const isInsert = mode === 'insert';
    const isEdit = mode === 'edit';

    let row: Record<string, unknown> | undefined;
    if (!isInsert) {
      row = this.filteredRows()[index];
      if (!row) return '';
    }

    const cols = this.state.schema?.columns ?? [];
    const colNames = cols.length > 0
      ? cols.map(c => c.name)
      : (row ? Object.keys(row).filter(k => k !== '__rowid') : []);

    const title = isInsert
      ? `Insert into ${this.state.table}`
      : isEdit
        ? `Edit row ${index + 1}`
        : `Row ${index + 1} on page ${this.state.page}`;

    const items = colNames.map(name => {
      const v = row?.[name];
      if (isInsert || isEdit) {
        const isNull = v === null || v === undefined;
        const valAttr = isNull ? '' : escapeAttr(String(v));
        return `<div class="k">${escapeHtml(name)}</div>
          <div class="v" style="display:flex;gap:6px;align-items:center">
            <input data-col="${escapeAttr(name)}" type="text" value="${valAttr}" ${isNull && !isInsert ? 'disabled placeholder="NULL"' : ''} style="flex:1;padding:4px 6px;background:var(--vscode-input-background);color:var(--vscode-input-foreground);border:1px solid var(--vscode-input-border);border-radius:2px;font:inherit" />
            <button data-null-toggle type="button" class="secondary ${isNull && !isInsert ? 'active' : ''}" title="Toggle NULL">NULL</button>
          </div>`;
      }
      const display = v === null || v === undefined
        ? `<span class="null">NULL</span>`
        : escapeHtml(String(v));
      return `<div class="k">${escapeHtml(name)}</div><div class="v">${display}</div>`;
    }).join('');

    const buttons = isInsert
      ? `<button id="detailCancel" class="secondary">Cancel</button>
         <button id="detailSave">Insert</button>`
      : isEdit
        ? `<button id="detailCancel" class="secondary">Cancel</button>
           <button id="detailSave">Save</button>`
        : `${this.state.hasRowid ? `<button id="detailEdit">Edit</button>
           <button id="detailDelete" class="danger">Delete</button>` : ''}
           <button id="closeDetail" class="secondary">Close</button>`;

    return `<div id="detailBg" class="modal-bg">
      <div class="modal">
        <div class="modal-head">
          <h3>${escapeHtml(title)}</h3>
          <div style="display:flex;gap:6px">${buttons}</div>
        </div>
        <div class="modal-body"><div class="kv">${items}</div></div>
      </div>
    </div>`;
  }

  private renderStructure(): string {
    const s = this.state.schema;
    if (!s) return `<div class="body"><p class="meta">Loading schema…</p></div>`;
    const cols = s.columns.map(c => `<tr>
      <td>${escapeHtml(c.name)} ${c.pk > 0 ? '<span class="badge pk">PK</span>' : ''}${c.notnull > 0 ? '<span class="badge nn">NOT NULL</span>' : ''}</td>
      <td>${escapeHtml(c.type || '')}</td>
      <td>${c.dflt_value === null || c.dflt_value === undefined ? '<span class="null">—</span>' : escapeHtml(String(c.dflt_value))}</td>
    </tr>`).join('');

    const idx = s.indexList.map(i => `<tr>
      <td>${escapeHtml(i.name)}${i.unique ? ' <span class="badge nn">UNIQUE</span>' : ''}</td>
      <td>${i.columns.map(escapeHtml).join(', ')}</td>
      <td><code>${escapeHtml(i.sql ?? '')}</code></td>
    </tr>`).join('');

    const fks = s.foreignKeys.map(fk => `<tr>
      <td>${escapeHtml(fk.from)}</td>
      <td>${escapeHtml(fk.table)}.${escapeHtml(fk.to)}</td>
      <td>${escapeHtml(fk.on_update || '—')}</td>
      <td>${escapeHtml(fk.on_delete || '—')}</td>
    </tr>`).join('');

    const triggers = s.triggers.map(t => `<details style="margin-bottom:8px">
      <summary><b>${escapeHtml(t.name)}</b></summary>
      <pre>${escapeHtml(t.sql ?? '')}</pre>
    </details>`).join('');

    return `
    <div class="body">
      <h3>Columns</h3>
      <table>
        <thead><tr><th>Name</th><th>Type</th><th>Default</th></tr></thead>
        <tbody>${cols}</tbody>
      </table>
      ${s.foreignKeys.length ? `<h3 style="margin-top:24px">Foreign keys</h3>
        <table>
          <thead><tr><th>Column</th><th>References</th><th>On update</th><th>On delete</th></tr></thead>
          <tbody>${fks}</tbody>
        </table>` : ''}
      ${s.indexList.length ? `<h3 style="margin-top:24px">Indexes</h3>
        <table>
          <thead><tr><th>Name</th><th>Columns</th><th>SQL</th></tr></thead>
          <tbody>${idx}</tbody>
        </table>` : ''}
      ${s.triggers.length ? `<h3 style="margin-top:24px">Triggers</h3>${triggers}` : ''}
      ${s.createTable ? `<h3 style="margin-top:24px">CREATE TABLE</h3><pre>${escapeHtml(s.createTable)}</pre>` : ''}
    </div>`;
  }
}

export class DbInfoPanel {
  private static panels = new Map<string, DbInfoPanel>();

  static show(client: WorkbenchClient, dbId: string, dbName: string) {
    const existing = DbInfoPanel.panels.get(dbId);
    if (existing) {
      existing.panel.reveal();
      void existing.load();
      return;
    }
    const panel = vscode.window.createWebviewPanel(
      'sqfliteDev.dbInfo',
      `${dbName} — Info`,
      vscode.ViewColumn.Active,
      { enableScripts: true, retainContextWhenHidden: true },
    );
    DbInfoPanel.panels.set(dbId, new DbInfoPanel(panel, client, dbId, dbName));
  }

  private info: DatabaseInfo | null = null;

  private constructor(
    private readonly panel: vscode.WebviewPanel,
    private readonly client: WorkbenchClient,
    private readonly dbId: string,
    private readonly dbName: string,
  ) {
    panel.onDidDispose(() => DbInfoPanel.panels.delete(this.dbId));
    panel.webview.onDidReceiveMessage(m => {
      if (m?.type === 'refresh') void this.load();
    });
    void this.load();
  }

  private async load() {
    try {
      this.info = await this.client.getInfo(this.dbId);
    } catch (e) {
      vscode.window.showErrorMessage(`sqflite_dev: ${(e as Error).message}`);
    }
    this.render();
  }

  private render() {
    const n = nonce();
    const csp = [
      `default-src 'none'`,
      `style-src ${this.panel.webview.cspSource} 'unsafe-inline'`,
      `script-src 'nonce-${n}'`,
    ].join('; ');

    const i = this.info;
    const rows = i ? [
      ['Name', i.name],
      ['Path', i.path],
      ['File size', formatBytes(i.size)],
      ['SQLite version', i.sqliteVersion ?? '—'],
      ['Tables', String(i.tableCount)],
      ['User version', i.userVersion ?? '—'],
      ['Schema version', i.schemaVersion ?? '—'],
      ['Page size', i.pageSize ?? '—'],
      ['Page count', i.pageCount ?? '—'],
      ['Encoding', i.encoding ?? '—'],
      ['Journal mode', i.journalMode ?? '—'],
      ['Foreign keys', i.foreignKeys === null ? '—' : i.foreignKeys ? 'on' : 'off'],
      ['Auto vacuum', autoVacuumLabel(i.autoVacuum)],
    ] : [];

    const body = i
      ? `<div class="kv">${rows.map(([k, v]) => `<div class="k">${escapeHtml(String(k))}</div><div class="v">${escapeHtml(String(v))}</div>`).join('')}</div>`
      : `<p class="meta">Loading…</p>`;

    this.panel.webview.html = /* html */ `
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8" />
  <meta http-equiv="Content-Security-Policy" content="${csp}" />
  <style>
    body { font-family: var(--vscode-font-family); color: var(--vscode-foreground); background: var(--vscode-editor-background); margin: 0; }
    .toolbar { display: flex; align-items: center; gap: 8px; padding: 8px 12px; border-bottom: 1px solid var(--vscode-panel-border); }
    .toolbar h2 { margin: 0; font-size: 13px; font-weight: 600; }
    .spacer { flex: 1; }
    button { background: var(--vscode-button-background); color: var(--vscode-button-foreground); border: 0; padding: 4px 10px; border-radius: 2px; cursor: pointer; font: inherit; }
    button.secondary { background: var(--vscode-button-secondaryBackground); color: var(--vscode-button-secondaryForeground); }
    .body { padding: 16px; }
    .meta { color: var(--vscode-descriptionForeground); font-size: 12px; }
    .kv { display: grid; grid-template-columns: max-content 1fr; gap: 6px 18px; font-size: 12px; font-family: var(--vscode-editor-font-family); }
    .kv .k { color: var(--vscode-descriptionForeground); padding: 4px 0; }
    .kv .v { padding: 4px 0; word-break: break-all; }
  </style>
</head>
<body>
  <div class="toolbar">
    <h2>${escapeHtml(this.dbName)}</h2>
    <span class="spacer"></span>
    <button class="secondary" id="refresh">Refresh</button>
  </div>
  <div class="body">${body}</div>
  <script nonce="${n}">
    const vscode = acquireVsCodeApi();
    document.getElementById('refresh').onclick = () => vscode.postMessage({ type: 'refresh' });
  </script>
</body>
</html>`;
  }
}

function quoteIdent(name: string): string {
  return `"${name.replace(/"/g, '""')}"`;
}

function sqlLiteral(v: unknown): string {
  if (v === null || v === undefined) return 'NULL';
  if (typeof v === 'number') return Number.isFinite(v) ? String(v) : 'NULL';
  if (typeof v === 'boolean') return v ? '1' : '0';
  const s = String(v);
  if (s === '') return "''";
  // Numeric-looking strings: keep quoted to preserve type, SQLite will coerce.
  return `'${s.replace(/'/g, "''")}'`;
}

function sameValue(a: unknown, b: unknown): boolean {
  if (a === null || a === undefined) return b === null || b === undefined || b === '';
  return String(a) === String(b);
}

async function confirmWrite(message: string, action = 'Save'): Promise<boolean> {
  const choice = await vscode.window.showWarningMessage(message, { modal: true }, action);
  return choice === action;
}

const HISTORY_KEY_PREFIX = 'sqfliteDev.history.';
const HISTORY_LIMIT = 50;

export class HistoryStore {
  constructor(private readonly memento: vscode.Memento) {}
  get(dbId: string): string[] {
    return this.memento.get<string[]>(HISTORY_KEY_PREFIX + dbId, []);
  }
  push(dbId: string, sql: string): Thenable<void> {
    const trimmed = sql.trim();
    if (!trimmed) return Promise.resolve();
    const list = this.get(dbId).filter(s => s !== trimmed);
    list.unshift(trimmed);
    return this.memento.update(HISTORY_KEY_PREFIX + dbId, list.slice(0, HISTORY_LIMIT));
  }
  clear(dbId: string): Thenable<void> {
    return this.memento.update(HISTORY_KEY_PREFIX + dbId, []);
  }
}

interface SqlEditorState {
  dbs: { id: string; name: string }[];
  dbId: string | null;
  sql: string;
  result: { columns: string[]; rows: Record<string, unknown>[]; executionTime: number; affectedRows?: number } | null;
  error: string | null;
  status: string;
  history: string[];
  historyOpen: boolean;
}

export class SqlEditorPanel {
  private static current: SqlEditorPanel | undefined;

  static show(client: WorkbenchClient, history: HistoryStore, dbs: { id: string; name: string }[], preferredDbId?: string) {
    if (SqlEditorPanel.current) {
      SqlEditorPanel.current.panel.reveal();
      SqlEditorPanel.current.updateDatabases(dbs, preferredDbId);
      return;
    }
    const panel = vscode.window.createWebviewPanel(
      'sqfliteDev.sqlEditor',
      'SQL Editor — sqflite_dev',
      vscode.ViewColumn.Active,
      { enableScripts: true, retainContextWhenHidden: true },
    );
    SqlEditorPanel.current = new SqlEditorPanel(panel, client, history, dbs, preferredDbId);
  }

  private state: SqlEditorState;

  private constructor(
    private readonly panel: vscode.WebviewPanel,
    private readonly client: WorkbenchClient,
    private readonly history: HistoryStore,
    dbs: { id: string; name: string }[],
    preferredDbId?: string,
  ) {
    const dbId = preferredDbId && dbs.some(d => d.id === preferredDbId) ? preferredDbId : (dbs[0]?.id ?? null);
    this.state = {
      dbs,
      dbId,
      sql: '',
      result: null,
      error: null,
      status: '',
      history: dbId ? this.history.get(dbId) : [],
      historyOpen: false,
    };
    panel.onDidDispose(() => {
      SqlEditorPanel.current = undefined;
    });
    panel.webview.onDidReceiveMessage(msg => this.onMessage(msg));
    this.render();
  }

  updateDatabases(dbs: { id: string; name: string }[], preferredDbId?: string) {
    this.state.dbs = dbs;
    if (preferredDbId && dbs.some(d => d.id === preferredDbId)) {
      this.state.dbId = preferredDbId;
      this.state.history = this.history.get(preferredDbId);
    } else if (this.state.dbId && !dbs.some(d => d.id === this.state.dbId)) {
      this.state.dbId = dbs[0]?.id ?? null;
      this.state.history = this.state.dbId ? this.history.get(this.state.dbId) : [];
    }
    this.render();
  }

  private async onMessage(msg: { type: string; [k: string]: unknown }) {
    switch (msg.type) {
      case 'setDb':
        this.state.dbId = String(msg.dbId ?? '') || null;
        this.state.history = this.state.dbId ? this.history.get(this.state.dbId) : [];
        this.state.result = null;
        this.state.error = null;
        this.state.status = '';
        this.render();
        break;
      case 'sqlChanged':
        this.state.sql = String(msg.sql ?? '');
        break;
      case 'run':
        this.state.sql = String(msg.sql ?? this.state.sql);
        await this.runQuery(false);
        break;
      case 'runBatch':
        this.state.sql = String(msg.sql ?? this.state.sql);
        await this.runQuery(true);
        break;
      case 'loadHistory':
        this.state.sql = String(msg.sql ?? '');
        this.render();
        break;
      case 'clearHistory':
        if (this.state.dbId) {
          await this.history.clear(this.state.dbId);
          this.state.history = [];
          this.render();
        }
        break;
      case 'toggleHistory':
        this.state.historyOpen = !this.state.historyOpen;
        this.render();
        break;
    }
  }

  private async runQuery(asBatch: boolean) {
    if (!this.state.dbId) {
      this.state.error = 'No database selected.';
      this.render();
      return;
    }
    const sql = this.state.sql.trim();
    if (!sql) {
      this.state.error = 'Nothing to run.';
      this.render();
      return;
    }
    this.state.status = 'Running…';
    this.state.error = null;
    this.render();

    try {
      if (asBatch) {
        const statements = splitSql(sql);
        if (statements.length === 0) {
          this.state.error = 'No statements detected.';
          this.state.status = '';
          this.render();
          return;
        }
        const result = await this.client.batch(this.state.dbId, statements);
        if (result.error) {
          this.state.error = result.error;
          this.state.result = null;
          this.state.status = `Failed in ${result.executionTime}ms (rolled back)`;
        } else {
          this.state.result = { columns: [], rows: [], executionTime: result.executionTime, affectedRows: result.executed ?? 0 };
          this.state.status = `OK · ${result.executed} statement${result.executed === 1 ? '' : 's'} in ${result.executionTime}ms`;
        }
      } else {
        const result = await this.client.query(this.state.dbId, sql);
        if (result.error) {
          this.state.error = result.error;
          this.state.result = null;
          this.state.status = `Failed in ${result.executionTime}ms`;
        } else {
          const cols = result.data.length > 0 ? Object.keys(result.data[0]) : [];
          this.state.result = {
            columns: cols,
            rows: result.data,
            executionTime: result.executionTime,
            affectedRows: result.affectedRows,
          };
          this.state.status = result.data.length > 0
            ? `${result.rowCount} row${result.rowCount === 1 ? '' : 's'} in ${result.executionTime}ms`
            : `OK · ${result.affectedRows ?? 0} affected in ${result.executionTime}ms`;
        }
      }

      await this.history.push(this.state.dbId, sql);
      this.state.history = this.history.get(this.state.dbId);
    } catch (e) {
      this.state.error = (e as Error).message;
      this.state.result = null;
      this.state.status = '';
    }
    this.render();
  }

  private render() {
    const n = nonce();
    const csp = [
      `default-src 'none'`,
      `style-src ${this.panel.webview.cspSource} 'unsafe-inline'`,
      `script-src 'nonce-${n}'`,
    ].join('; ');

    const dbOptions = this.state.dbs.map(d =>
      `<option value="${escapeAttr(d.id)}" ${d.id === this.state.dbId ? 'selected' : ''}>${escapeHtml(d.name)}</option>`,
    ).join('');

    const resultPanel = this.state.error
      ? `<div class="error">${escapeHtml(this.state.error)}</div>`
      : this.state.result
        ? this.renderResult(this.state.result)
        : `<div class="meta">Run a query to see results.</div>`;

    const historyItems = this.state.history.length === 0
      ? `<div class="meta" style="padding:8px">No history yet.</div>`
      : this.state.history.map((h, i) => `<div class="hist-item" data-hist="${i}" title="${escapeAttr(h)}">${escapeHtml(truncate(h.replace(/\s+/g, ' '), 90))}</div>`).join('');

    this.panel.webview.html = /* html */ `
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8" />
  <meta http-equiv="Content-Security-Policy" content="${csp}" />
  <style>
    body { font-family: var(--vscode-font-family); color: var(--vscode-foreground); background: var(--vscode-editor-background); margin: 0; height: 100vh; display: flex; flex-direction: column; }
    .toolbar { display: flex; align-items: center; gap: 8px; padding: 8px 12px; border-bottom: 1px solid var(--vscode-panel-border); flex-wrap: wrap; }
    select, input { padding: 4px 8px; background: var(--vscode-input-background); color: var(--vscode-input-foreground); border: 1px solid var(--vscode-input-border); border-radius: 2px; font: inherit; }
    button { background: var(--vscode-button-background); color: var(--vscode-button-foreground); border: 0; padding: 4px 10px; border-radius: 2px; cursor: pointer; font: inherit; }
    button:hover { background: var(--vscode-button-hoverBackground); }
    button.secondary { background: var(--vscode-button-secondaryBackground); color: var(--vscode-button-secondaryForeground); }
    .spacer { flex: 1; }
    .meta { color: var(--vscode-descriptionForeground); font-size: 12px; }
    .main { flex: 1; display: flex; min-height: 0; }
    .editor-pane { flex: 1; display: flex; flex-direction: column; min-width: 0; }
    .editor-area { flex: 0 0 auto; height: 220px; padding: 8px 12px; }
    textarea { width: 100%; height: 100%; box-sizing: border-box; font-family: var(--vscode-editor-font-family); font-size: var(--vscode-editor-font-size, 13px); background: var(--vscode-input-background); color: var(--vscode-input-foreground); border: 1px solid var(--vscode-input-border); padding: 8px; border-radius: 2px; resize: none; }
    .results { flex: 1; overflow: auto; padding: 0 12px 12px; min-height: 0; }
    .error { color: var(--vscode-errorForeground); white-space: pre-wrap; font-family: var(--vscode-editor-font-family); padding: 12px; background: var(--vscode-inputValidation-errorBackground, transparent); border-left: 3px solid var(--vscode-errorForeground); border-radius: 2px; }
    table { border-collapse: collapse; width: 100%; font-size: 12px; font-family: var(--vscode-editor-font-family); }
    th, td { padding: 4px 8px; text-align: left; border-bottom: 1px solid var(--vscode-panel-border); white-space: nowrap; max-width: 320px; overflow: hidden; text-overflow: ellipsis; }
    th { position: sticky; top: 0; background: var(--vscode-editorWidget-background); font-weight: 600; }
    tr:hover td { background: var(--vscode-list-hoverBackground); }
    .null { color: var(--vscode-disabledForeground); font-style: italic; }
    .history-pane { width: 280px; border-left: 1px solid var(--vscode-panel-border); display: flex; flex-direction: column; flex-shrink: 0; }
    .history-pane.hidden { display: none; }
    .history-head { padding: 8px 12px; border-bottom: 1px solid var(--vscode-panel-border); display: flex; align-items: center; gap: 8px; }
    .history-head h3 { margin: 0; font-size: 12px; font-weight: 600; }
    .history-list { flex: 1; overflow: auto; }
    .hist-item { padding: 6px 12px; font-family: var(--vscode-editor-font-family); font-size: 11px; border-bottom: 1px solid var(--vscode-panel-border); cursor: pointer; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
    .hist-item:hover { background: var(--vscode-list-hoverBackground); }
    kbd { font-family: var(--vscode-editor-font-family); font-size: 11px; background: var(--vscode-keybindingLabel-background, var(--vscode-editorWidget-background)); border: 1px solid var(--vscode-panel-border); border-radius: 2px; padding: 0 4px; }
  </style>
</head>
<body>
  <div class="toolbar">
    <span class="meta">Database</span>
    <select id="db">${dbOptions || '<option>No databases</option>'}</select>
    <button id="run" ${this.state.dbId ? '' : 'disabled'}>Run <kbd>⌘↵</kbd></button>
    <button id="runBatch" class="secondary" ${this.state.dbId ? '' : 'disabled'} title="Run all statements in one transaction">Run as Transaction</button>
    <span class="spacer"></span>
    <span class="meta" id="status">${escapeHtml(this.state.status)}</span>
    <button id="toggleHistory" class="secondary">${this.state.historyOpen ? 'Hide history' : 'Show history'}</button>
  </div>
  <div class="main">
    <div class="editor-pane">
      <div class="editor-area"><textarea id="sql" placeholder="-- Type SQL here. ⌘/Ctrl+Enter to run.">${escapeHtml(this.state.sql)}</textarea></div>
      <div class="results">${resultPanel}</div>
    </div>
    <div class="history-pane ${this.state.historyOpen ? '' : 'hidden'}">
      <div class="history-head">
        <h3>History</h3>
        <span class="spacer"></span>
        <button id="clearHistory" class="secondary" ${this.state.history.length === 0 ? 'disabled' : ''}>Clear</button>
      </div>
      <div class="history-list">${historyItems}</div>
    </div>
  </div>
  <script nonce="${n}">
    const vscode = acquireVsCodeApi();
    const $ = id => document.getElementById(id);
    const sqlEl = $('sql');
    const getSql = () => sqlEl.value;
    sqlEl.addEventListener('input', () => vscode.postMessage({ type: 'sqlChanged', sql: getSql() }));
    sqlEl.addEventListener('keydown', e => {
      if ((e.metaKey || e.ctrlKey) && e.key === 'Enter') {
        e.preventDefault();
        vscode.postMessage({ type: 'run', sql: getSql() });
      }
    });
    $('run').onclick = () => vscode.postMessage({ type: 'run', sql: getSql() });
    $('runBatch').onclick = () => vscode.postMessage({ type: 'runBatch', sql: getSql() });
    $('db').addEventListener('change', e => vscode.postMessage({ type: 'setDb', dbId: e.target.value }));
    $('toggleHistory').onclick = () => vscode.postMessage({ type: 'toggleHistory' });
    if ($('clearHistory')) $('clearHistory').onclick = () => vscode.postMessage({ type: 'clearHistory' });
    document.querySelectorAll('.hist-item').forEach(el => {
      el.addEventListener('click', () => {
        const idx = Number(el.dataset.hist);
        const all = ${JSON.stringify(this.state.history)};
        vscode.postMessage({ type: 'loadHistory', sql: all[idx] });
      });
    });
    sqlEl.focus();
  </script>
</body>
</html>`;
  }

  private renderResult(r: { columns: string[]; rows: Record<string, unknown>[]; executionTime: number; affectedRows?: number }): string {
    if (r.rows.length === 0) {
      return `<div class="meta" style="padding:12px">No rows returned. ${r.affectedRows !== undefined ? `${r.affectedRows} affected.` : ''}</div>`;
    }
    const head = r.columns.map(c => `<th>${escapeHtml(c)}</th>`).join('');
    const body = r.rows.map(row => {
      const cells = r.columns.map(c => {
        const v = row[c];
        if (v === null || v === undefined) return `<td class="null">NULL</td>`;
        return `<td title="${escapeAttr(String(v))}">${escapeHtml(truncate(String(v), 200))}</td>`;
      }).join('');
      return `<tr>${cells}</tr>`;
    }).join('');
    return `<table><thead><tr>${head}</tr></thead><tbody>${body}</tbody></table>`;
  }
}

function splitSql(sql: string): string[] {
  const out: string[] = [];
  let buf = '';
  let i = 0;
  let inSingle = false;
  let inDouble = false;
  let inLineComment = false;
  let inBlockComment = false;
  while (i < sql.length) {
    const ch = sql[i];
    const next = sql[i + 1];
    if (inLineComment) {
      buf += ch;
      if (ch === '\n') inLineComment = false;
      i++;
      continue;
    }
    if (inBlockComment) {
      buf += ch;
      if (ch === '*' && next === '/') { buf += next; i += 2; inBlockComment = false; continue; }
      i++;
      continue;
    }
    if (inSingle) {
      buf += ch;
      if (ch === "'") {
        if (next === "'") { buf += next; i += 2; continue; }
        inSingle = false;
      }
      i++;
      continue;
    }
    if (inDouble) {
      buf += ch;
      if (ch === '"') {
        if (next === '"') { buf += next; i += 2; continue; }
        inDouble = false;
      }
      i++;
      continue;
    }
    if (ch === '-' && next === '-') { inLineComment = true; buf += ch; i++; continue; }
    if (ch === '/' && next === '*') { inBlockComment = true; buf += ch + next; i += 2; continue; }
    if (ch === "'") { inSingle = true; buf += ch; i++; continue; }
    if (ch === '"') { inDouble = true; buf += ch; i++; continue; }
    if (ch === ';') {
      const t = buf.trim();
      if (t) out.push(t);
      buf = '';
      i++;
      continue;
    }
    buf += ch;
    i++;
  }
  const tail = buf.trim();
  if (tail) out.push(tail);
  return out;
}

function toCsv(rows: Record<string, unknown>[]): string {
  if (rows.length === 0) return '';
  const cols = Object.keys(rows[0]);
  const escape = (v: unknown) => {
    if (v === null || v === undefined) return '';
    const s = String(v);
    if (/[",\n\r]/.test(s)) return `"${s.replace(/"/g, '""')}"`;
    return s;
  };
  const out = [cols.map(escape).join(',')];
  for (const r of rows) out.push(cols.map(c => escape(r[c])).join(','));
  return out.join('\n');
}

function truncate(s: string, n: number): string {
  return s.length > n ? s.slice(0, n) + '…' : s;
}

function formatBytes(bytes: number): string {
  if (!Number.isFinite(bytes) || bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  const i = Math.min(units.length - 1, Math.floor(Math.log(bytes) / Math.log(1024)));
  return `${(bytes / Math.pow(1024, i)).toFixed(i === 0 ? 0 : 2)} ${units[i]}`;
}

function autoVacuumLabel(v: number | null): string {
  if (v === null || v === undefined) return '—';
  return v === 0 ? 'none' : v === 1 ? 'full' : v === 2 ? 'incremental' : String(v);
}

function escapeHtml(s: string): string {
  return s.replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]!));
}
function escapeAttr(s: string): string {
  return escapeHtml(s).replace(/\n/g, ' ');
}
