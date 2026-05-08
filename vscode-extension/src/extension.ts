import * as vscode from 'vscode';
import { WorkbenchClient } from './api';
import { DatabaseNode, TableNode, WorkbenchTreeProvider } from './treeProvider';
import { DbInfoPanel, HistoryStore, SqlEditorPanel, TablePanel, WorkbenchPanel } from './webview';

const CONFIG_SECTION = 'sqfliteDev';

export function activate(context: vscode.ExtensionContext) {
  const config = () => vscode.workspace.getConfiguration(CONFIG_SECTION);
  const host = () => config().get<string>('host', 'localhost');
  const port = () => config().get<number>('port', 8080);

  const client = new WorkbenchClient(host(), port());
  const tree = new WorkbenchTreeProvider(client);
  const history = new HistoryStore(context.workspaceState);

  const treeView = vscode.window.createTreeView('sqfliteDev.databases', {
    treeDataProvider: tree,
    showCollapseAll: true,
  });

  const status = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Right, 99);
  status.command = 'sqfliteDev.connect';
  context.subscriptions.push(status);

  let pollHandle: NodeJS.Timeout | undefined;

  const updateStatus = () => {
    if (tree.isConnected()) {
      const n = tree.getDatabases().length;
      status.text = `$(database) sqflite_dev · ${n} db${n === 1 ? '' : 's'}`;
      status.tooltip = `Connected to ${client.baseUrl}`;
      status.backgroundColor = undefined;
    } else {
      status.text = `$(debug-disconnect) sqflite_dev`;
      status.tooltip = `No workbench at ${client.baseUrl}. Click to retry.`;
      status.backgroundColor = new vscode.ThemeColor('statusBarItem.warningBackground');
    }
    status.show();
  };

  const refresh = async () => {
    client.update(host(), port());
    await tree.refresh();
    updateStatus();
  };

  const startPolling = () => {
    if (pollHandle) clearInterval(pollHandle);
    const seconds = config().get<number>('autoRefreshSeconds', 0);
    if (seconds > 0) {
      pollHandle = setInterval(() => {
        void refresh();
      }, seconds * 1000);
    }
  };

  context.subscriptions.push(
    treeView,
    vscode.workspace.onDidChangeConfiguration(e => {
      if (e.affectsConfiguration(CONFIG_SECTION)) {
        void refresh();
        startPolling();
      }
    }),
    vscode.commands.registerCommand('sqfliteDev.connect', () => refresh()),
    vscode.commands.registerCommand('sqfliteDev.openSettings', () =>
      vscode.commands.executeCommand('workbench.action.openSettings', '@ext:subairanchukandan.sqflite-dev-vscode'),
    ),
    vscode.commands.registerCommand('sqfliteDev.openWorkbench', () => {
      WorkbenchPanel.show(client.baseUrl);
    }),
    vscode.commands.registerCommand('sqfliteDev.openInBrowser', () => {
      void vscode.env.openExternal(vscode.Uri.parse(client.baseUrl));
    }),
    vscode.commands.registerCommand('sqfliteDev.openTable', (node?: TableNode) => {
      if (!node) return;
      TablePanel.show(client, node.db.id, node.tableName);
    }),
    vscode.commands.registerCommand('sqfliteDev.showDbInfo', async (node?: DatabaseNode) => {
      let target = node?.db;
      if (!target) {
        const dbs = tree.getDatabases();
        if (dbs.length === 0) {
          vscode.window.showErrorMessage('sqflite_dev: no databases connected.');
          return;
        }
        if (dbs.length === 1) {
          target = dbs[0];
        } else {
          const pick = await vscode.window.showQuickPick(
            dbs.map(d => ({ label: d.name, description: d.id, db: d })),
            { placeHolder: 'Select database' },
          );
          if (!pick) return;
          target = pick.db;
        }
      }
      DbInfoPanel.show(client, target.id, target.name);
    }),
    vscode.commands.registerCommand('sqfliteDev.copyCreate', async (node?: TableNode) => {
      if (!node) return;
      try {
        const schema = await tree.getSchema(node.db.id, node.tableName);
        if (schema.createTable) {
          await vscode.env.clipboard.writeText(schema.createTable);
          vscode.window.showInformationMessage('CREATE statement copied');
        }
      } catch (e) {
        vscode.window.showErrorMessage(`sqflite_dev: ${(e as Error).message}`);
      }
    }),
    vscode.commands.registerCommand('sqfliteDev.copySelect', async (node?: TableNode) => {
      if (!node) return;
      try {
        const schema = await tree.getSchema(node.db.id, node.tableName);
        const cols = schema.columns.map(c => `"${c.name}"`).join(', ') || '*';
        await vscode.env.clipboard.writeText(`SELECT ${cols} FROM "${node.tableName}" LIMIT 100;`);
        vscode.window.showInformationMessage('SELECT statement copied');
      } catch (e) {
        vscode.window.showErrorMessage(`sqflite_dev: ${(e as Error).message}`);
      }
    }),
    vscode.commands.registerCommand('sqfliteDev.runSqlFile', () => runSqlFromEditor(client, tree, false)),
    vscode.commands.registerCommand('sqfliteDev.runSelection', () => runSqlFromEditor(client, tree, true)),
    vscode.commands.registerCommand('sqfliteDev.runSqlFileTransaction', () => runSqlAsTransaction(client, tree)),
    vscode.commands.registerCommand('sqfliteDev.copyDbPath', async (node?: DatabaseNode) => {
      if (!node) return;
      await vscode.env.clipboard.writeText(node.db.path);
      vscode.window.showInformationMessage(`Copied: ${node.db.path}`);
    }),
    vscode.commands.registerCommand('sqfliteDev.dropTable', async (node?: TableNode) => {
      if (!node) return;
      const ok = await confirm(`Drop table "${node.tableName}"? This permanently removes the table and all its data.`, 'Drop');
      if (!ok) return;
      await runDdl(client, tree, node.db.id, `DROP TABLE ${quote(node.tableName)}`, `Dropped "${node.tableName}"`);
    }),
    vscode.commands.registerCommand('sqfliteDev.truncateTable', async (node?: TableNode) => {
      if (!node) return;
      const ok = await confirm(`Delete all rows from "${node.tableName}"? Schema is kept; rows cannot be recovered.`, 'Truncate');
      if (!ok) return;
      await runDdl(client, tree, node.db.id, `DELETE FROM ${quote(node.tableName)}`, `Truncated "${node.tableName}"`);
    }),
    vscode.commands.registerCommand('sqfliteDev.renameTable', async (node?: TableNode) => {
      if (!node) return;
      const next = await vscode.window.showInputBox({
        prompt: `Rename table "${node.tableName}"`,
        value: node.tableName,
        validateInput: v => /^[A-Za-z_][A-Za-z0-9_]*$/.test(v.trim()) ? null : 'Use letters, digits, underscore (start with a letter or _)',
      });
      if (!next || next.trim() === node.tableName) return;
      const ok = await confirm(`Rename "${node.tableName}" to "${next.trim()}"?`, 'Rename');
      if (!ok) return;
      await runDdl(client, tree, node.db.id, `ALTER TABLE ${quote(node.tableName)} RENAME TO ${quote(next.trim())}`, `Renamed to "${next.trim()}"`);
    }),
    vscode.commands.registerCommand('sqfliteDev.vacuumDb', async (node?: DatabaseNode) => {
      const dbs = tree.getDatabases();
      let target = node?.db;
      if (!target) {
        if (dbs.length === 0) return;
        if (dbs.length === 1) target = dbs[0];
        else {
          const pick = await vscode.window.showQuickPick(
            dbs.map(d => ({ label: d.name, description: d.id, db: d })),
            { placeHolder: 'Select database to vacuum' },
          );
          if (!pick) return;
          target = pick.db;
        }
      }
      const ok = await confirm(`Run VACUUM on "${target.name}"? This rewrites the file and may take a while.`, 'Vacuum');
      if (!ok) return;
      await runDdl(client, tree, target.id, 'VACUUM', `VACUUM finished on "${target.name}"`);
    }),
    vscode.commands.registerCommand('sqfliteDev.filterTables', async () => {
      const current = tree.getTableFilter() ?? '';
      const next = await vscode.window.showInputBox({
        prompt: 'Filter tables (substring, case-insensitive). Empty to clear.',
        value: current,
      });
      if (next === undefined) return;
      tree.setTableFilter(next || null);
    }),
    vscode.commands.registerCommand('sqfliteDev.clearTableFilter', () => {
      tree.setTableFilter(null);
    }),
    vscode.commands.registerCommand('sqfliteDev.openSqlEditor', async (node?: DatabaseNode | TableNode) => {
      if (!tree.isConnected() || tree.getDatabases().length === 0) {
        await tree.refresh();
      }
      const dbs = tree.getDatabases().map(d => ({ id: d.id, name: d.name }));
      if (dbs.length === 0) {
        vscode.window.showErrorMessage('sqflite_dev: no databases connected.');
        return;
      }
      const preferred = node && 'db' in node ? node.db.id : undefined;
      SqlEditorPanel.show(client, history, dbs, preferred);
    }),
    vscode.commands.registerCommand('sqfliteDev.createTableTemplate', async (node?: DatabaseNode) => {
      const name = await vscode.window.showInputBox({
        prompt: 'New table name',
        validateInput: v => /^[A-Za-z_][A-Za-z0-9_]*$/.test(v.trim()) ? null : 'Use letters, digits, underscore (start with a letter or _)',
      });
      if (!name) return;
      const dbName = node?.db.name ?? '';
      await openSqlScratch(
        `-- Create table ${dbName ? `on "${dbName}" ` : ''}— ⌘/Ctrl+Enter to run\nCREATE TABLE ${quote(name.trim())} (\n  id INTEGER PRIMARY KEY AUTOINCREMENT,\n  -- column_name TEXT NOT NULL,\n  created_at INTEGER NOT NULL DEFAULT (strftime('%s','now'))\n);\n`,
      );
    }),
    vscode.commands.registerCommand('sqfliteDev.createIndexTemplate', async (node?: TableNode) => {
      const tableName = node?.tableName;
      if (!tableName) {
        vscode.window.showErrorMessage('sqflite_dev: open from a table to create an index.');
        return;
      }
      const idxName = await vscode.window.showInputBox({
        prompt: `Index name for "${tableName}"`,
        value: `idx_${tableName}_`,
        validateInput: v => /^[A-Za-z_][A-Za-z0-9_]*$/.test(v.trim()) ? null : 'Use letters, digits, underscore',
      });
      if (!idxName) return;
      await openSqlScratch(
        `-- Create index on "${tableName}" — ⌘/Ctrl+Enter to run\nCREATE INDEX ${quote(idxName.trim())} ON ${quote(tableName)} (\n  -- column_name\n);\n`,
      );
    }),
  );

  void refresh().then(startPolling);
}

async function runSqlFromEditor(
  client: WorkbenchClient,
  tree: WorkbenchTreeProvider,
  selectionOnly: boolean,
): Promise<void> {
  const editor = vscode.window.activeTextEditor;
  if (!editor) {
    vscode.window.showErrorMessage('sqflite_dev: open a SQL file first.');
    return;
  }
  const sql = (selectionOnly && !editor.selection.isEmpty
    ? editor.document.getText(editor.selection)
    : editor.document.getText()
  ).trim();
  if (!sql) {
    vscode.window.showWarningMessage('sqflite_dev: nothing to run.');
    return;
  }

  if (!tree.isConnected() || tree.getDatabases().length === 0) {
    await tree.refresh();
  }
  const dbs = tree.getDatabases();
  if (dbs.length === 0) {
    vscode.window.showErrorMessage('sqflite_dev: no databases connected.');
    return;
  }

  let target = dbs[0];
  if (dbs.length > 1) {
    const pick = await vscode.window.showQuickPick(
      dbs.map(d => ({ label: d.name, description: d.id, db: d })),
      { placeHolder: 'Select database to run query against' },
    );
    if (!pick) return;
    target = pick.db;
  }

  await vscode.window.withProgress(
    { location: vscode.ProgressLocation.Notification, title: `Running query on ${target.name}…` },
    async () => {
      try {
        const result = await client.query(target.id, sql);
        const channel = getOutputChannel();
        channel.show(true);
        channel.appendLine(`-- ${new Date().toISOString()} · ${target.name} · ${result.executionTime}ms`);
        channel.appendLine(sql);
        if (result.error) {
          channel.appendLine(`ERROR: ${result.error}`);
        } else if (result.data && result.data.length > 0) {
          channel.appendLine(`${result.rowCount} row${result.rowCount === 1 ? '' : 's'}`);
          channel.appendLine(formatTable(result.data));
        } else if (result.affectedRows !== undefined) {
          channel.appendLine(`OK · ${result.affectedRows} affected row${result.affectedRows === 1 ? '' : 's'}`);
        } else {
          channel.appendLine(`OK`);
        }
        channel.appendLine('');
        await tree.refresh();
      } catch (e) {
        vscode.window.showErrorMessage(`sqflite_dev: ${(e as Error).message}`);
      }
    },
  );
}

function quote(name: string): string {
  return `"${name.replace(/"/g, '""')}"`;
}

async function openSqlScratch(content: string): Promise<void> {
  const doc = await vscode.workspace.openTextDocument({ language: 'sql', content });
  await vscode.window.showTextDocument(doc);
}

async function confirm(message: string, action: string): Promise<boolean> {
  const choice = await vscode.window.showWarningMessage(message, { modal: true }, action);
  return choice === action;
}

async function runDdl(
  client: WorkbenchClient,
  tree: WorkbenchTreeProvider,
  dbId: string,
  sql: string,
  successMessage: string,
): Promise<void> {
  await vscode.window.withProgress(
    { location: vscode.ProgressLocation.Notification, title: successMessage + '…' },
    async () => {
      try {
        const result = await client.query(dbId, sql);
        if (result.error) {
          vscode.window.showErrorMessage(`sqflite_dev: ${result.error}`);
          return;
        }
        vscode.window.showInformationMessage(`sqflite_dev: ${successMessage}`);
        await tree.refresh();
      } catch (e) {
        vscode.window.showErrorMessage(`sqflite_dev: ${(e as Error).message}`);
      }
    },
  );
}

async function runSqlAsTransaction(
  client: WorkbenchClient,
  tree: WorkbenchTreeProvider,
): Promise<void> {
  const editor = vscode.window.activeTextEditor;
  if (!editor) {
    vscode.window.showErrorMessage('sqflite_dev: open a SQL file first.');
    return;
  }
  const text = editor.document.getText().trim();
  if (!text) {
    vscode.window.showWarningMessage('sqflite_dev: nothing to run.');
    return;
  }
  const statements = splitSqlStatements(text);
  if (statements.length === 0) {
    vscode.window.showWarningMessage('sqflite_dev: no statements detected.');
    return;
  }

  if (!tree.isConnected() || tree.getDatabases().length === 0) {
    await tree.refresh();
  }
  const dbs = tree.getDatabases();
  if (dbs.length === 0) {
    vscode.window.showErrorMessage('sqflite_dev: no databases connected.');
    return;
  }
  let target = dbs[0];
  if (dbs.length > 1) {
    const pick = await vscode.window.showQuickPick(
      dbs.map(d => ({ label: d.name, description: d.id, db: d })),
      { placeHolder: 'Select database for transaction' },
    );
    if (!pick) return;
    target = pick.db;
  }

  const confirm = await vscode.window.showWarningMessage(
    `Run ${statements.length} statement${statements.length === 1 ? '' : 's'} as a transaction on "${target.name}"? Any failure rolls back the whole batch.`,
    { modal: true },
    'Run',
  );
  if (confirm !== 'Run') return;

  await vscode.window.withProgress(
    { location: vscode.ProgressLocation.Notification, title: `Running batch on ${target.name}…` },
    async () => {
      try {
        const result = await client.batch(target.id, statements);
        const channel = getOutputChannel();
        channel.show(true);
        channel.appendLine(`-- ${new Date().toISOString()} · ${target.name} · batch · ${result.executionTime}ms`);
        if (result.error) {
          channel.appendLine(`ERROR (rolled back): ${result.error}`);
        } else {
          channel.appendLine(`OK · ${result.executed} statement${result.executed === 1 ? '' : 's'} committed`);
        }
        channel.appendLine('');
        await tree.refresh();
      } catch (e) {
        vscode.window.showErrorMessage(`sqflite_dev: ${(e as Error).message}`);
      }
    },
  );
}

function splitSqlStatements(sql: string): string[] {
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
      if (ch === '*' && next === '/') {
        buf += next;
        i += 2;
        inBlockComment = false;
        continue;
      }
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

let outputChannel: vscode.OutputChannel | undefined;
function getOutputChannel(): vscode.OutputChannel {
  if (!outputChannel) {
    outputChannel = vscode.window.createOutputChannel('sqflite_dev');
  }
  return outputChannel;
}

function formatTable(rows: Record<string, unknown>[]): string {
  if (rows.length === 0) return '';
  const cols = Object.keys(rows[0]);
  const widths = cols.map(c =>
    Math.min(40, Math.max(c.length, ...rows.map(r => String(r[c] ?? 'NULL').length))),
  );
  const fmt = (cells: string[]) =>
    cells.map((s, i) => s.padEnd(widths[i]).slice(0, widths[i])).join(' │ ');
  const sep = widths.map(w => '─'.repeat(w)).join('─┼─');
  const out: string[] = [];
  out.push(fmt(cols));
  out.push(sep);
  for (const r of rows) {
    out.push(fmt(cols.map(c => (r[c] === null || r[c] === undefined ? 'NULL' : String(r[c])))));
  }
  return out.join('\n');
}

export function deactivate() {
  // nothing to do
}
