# sqflite_dev for VS Code

VS Code companion for the [`sqflite_dev`](https://pub.dev/packages/sqflite_dev) Dart/Flutter dev dependency. Browse and query SQLite databases exposed by your running app — without leaving the editor.

## What it does

- **Activity bar tree** of every database registered with `db.enableWorkbench()`, expanded down to columns
- **Open table** in a native VS Code panel with paged data, structure view, indexes, and CREATE TABLE
- **Open the full workbench** in an editor tab (iframes the package's built-in SPA)
- **Run SQL** from any `.sql` file or selection (`⌘/Ctrl+Enter`) against the chosen database, results rendered in the Output panel
- **Status bar indicator** showing connection state and database count
- **Copy CREATE / SELECT statements** from the tree context menu

## Requirements

Your Flutter or Dart app must be running with `sqflite_dev` enabled:

```dart
import 'package:sqflite_dev/sqflite_dev.dart';

final db = await openDatabase('app.db');
db.enableWorkbench(webDebug: true, webDebugPort: 8080);
```

The extension talks to the same HTTP API the browser UI uses — nothing to set up beyond pointing it at the right host/port.

## Settings

| Setting | Default | Description |
|---|---|---|
| `sqfliteDev.host` | `localhost` | Host where the workbench is reachable |
| `sqfliteDev.port` | `8080` | Port the workbench listens on |
| `sqfliteDev.autoRefreshSeconds` | `0` | Poll the tree every N seconds (0 disables) |

## Development

```bash
npm install
npm run watch
```

Press `F5` in VS Code to launch an Extension Development Host. To package:

```bash
npm run package
```

## Architecture

The extension is a thin client over the `sqflite_dev` REST API ([api_handlers.dart](../lib/src/api_handlers.dart)). All data — tables, schema, rows, query results — comes from the running app over plain HTTP/JSON. No native bindings, no Dart code.
