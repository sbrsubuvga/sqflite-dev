import 'dart:async';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_cors_headers/shelf_cors_headers.dart' as cors;
import 'package:sqflite_common/sqlite_api.dart';
import 'package:path/path.dart' as path;
import 'api_handlers.dart';

/// Singleton workbench server that manages multiple databases
class WorkbenchServer {
  static WorkbenchServer? _instance;
  static WorkbenchServer get instance {
    _instance ??= WorkbenchServer._();
    return _instance!;
  }

  WorkbenchServer._();

  HttpServer? _server;
  final Map<String, DatabaseInfo> _databases = {};
  int _port = 8080;
  String? _localIp;

  /// Register a database with the workbench server
  void registerDatabase({
    required String dbId,
    required Database database,
    required String dbPath,
    String? name,
  }) {
    _databases[dbId] = DatabaseInfo(
      id: dbId,
      database: database,
      path: dbPath,
      name: name ?? path.basename(dbPath),
    );

    // Start server if not already running
    if (_server == null) {
      _startServer();
    } else {
      print(
          'sqflite_dev: Database "$dbId" registered. Workbench already running.');
    }
  }

  /// Get all registered databases
  Map<String, DatabaseInfo> get databases => Map.unmodifiable(_databases);

  /// Get a database by ID
  DatabaseInfo? getDatabase(String dbId) => _databases[dbId];

  /// Start the web server
  Future<void> _startServer() async {
    if (_server != null) {
      return; // Already running
    }

    try {
      // Try to start on the configured port
      _server = await shelf_io.serve(
        _createHandler(),
        InternetAddress.anyIPv4,
        _port,
      );

      // Get network IP - wait a short moment for detection
      _localIp = await _getLocalIpAddress(_server!.address);

      print('');
      print('═══════════════════════════════════════════════════════════');
      print('sqflite_dev: Workbench server started!');
      print('  Local:   http://localhost:$_port');
      if (_localIp != null) {
        print('  Network: http://$_localIp:$_port');
      } else {
        print('  Network: IP not detected - check device network settings');
        print('           Access from PC using device IP address');
      }
      print('═══════════════════════════════════════════════════════════');
      print('');
    } catch (e) {
      // Port might be in use, try next port
      if (e is SocketException &&
          e.message.contains('Address already in use')) {
        print('sqflite_dev: Port $_port is in use, trying next port...');
        _port++;
        return _startServer();
      }
      print('sqflite_dev: Failed to start server: $e');
    }
  }

  /// Create the shelf handler with CORS and static file serving
  Handler _createHandler() {
    final apiHandler = createApiHandler(this);

    // CORS middleware
    final corsMiddleware = cors.corsHeaders(
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type',
      },
    );

    return Pipeline()
        .addMiddleware(corsMiddleware)
        .addHandler((Request request) async {
      // Route API requests
      if (request.url.path.startsWith('api/')) {
        return apiHandler(request);
      }

      // Serve embedded web UI for root and index.html
      final requestPath = request.url.path;
      if (requestPath == '' ||
          requestPath == '/' ||
          requestPath == '/index.html') {
        return Response.ok(
          _getWebUIHtml(),
          headers: {'Content-Type': 'text/html; charset=utf-8'},
        );
      }

      // For any other path, return 404 or the embedded HTML
      return Response.ok(
        _getWebUIHtml(),
        headers: {'Content-Type': 'text/html; charset=utf-8'},
      );
    });
  }

  /// Get local IP address for network access (async)
  Future<String?> _getLocalIpAddress(InternetAddress serverAddress) async {
    try {
      if (serverAddress.rawAddress.every((b) => b == 0)) {
        return await _findNetworkIp();
      } else if (!serverAddress.isLoopback) {
        return serverAddress.address;
      }
    } catch (e) {
      // Ignore errors
    }
    return null;
  }

  /// Get the embedded web UI HTML
  String _getWebUIHtml() {
    return '''
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>SQLite Workbench</title>
    <style>
${_getWebUICSS()}
    </style>
</head>
<body>
    <!-- Toast Container -->
    <div id="toastContainer" class="toast-container"></div>

    <!-- Loading Overlay -->
    <div id="loadingOverlay" class="loading-overlay">
        <div class="spinner"></div>
    </div>

    <!-- Shortcuts Modal -->
    <div id="shortcutsModal" class="modal-overlay">
        <div class="modal">
            <div class="modal-header">
                <h3>Keyboard Shortcuts</h3>
                <button class="btn-icon modal-close-btn" onclick="document.getElementById('shortcutsModal').style.display='none'">&#x2715;</button>
            </div>
            <div class="modal-body">
                <table class="shortcuts-table">
                    <tr><td><kbd>Ctrl</kbd> + <kbd>Enter</kbd></td><td>Execute query</td></tr>
                    <tr><td><kbd>Ctrl</kbd> + <kbd>T</kbd></td><td>New query tab</td></tr>
                    <tr><td><kbd>Ctrl</kbd> + <kbd>W</kbd></td><td>Close current tab</td></tr>
                    <tr><td><kbd>Ctrl</kbd> + <kbd>K</kbd></td><td>Focus table search</td></tr>
                    <tr><td><kbd>Ctrl</kbd> + <kbd>D</kbd></td><td>Toggle dark mode</td></tr>
                    <tr><td><kbd>Escape</kbd></td><td>Close modal / panel</td></tr>
                    <tr><td><kbd>?</kbd></td><td>Show this help</td></tr>
                    <tr><td>Type in query editor</td><td>Autocomplete tables, columns, SQL</td></tr>
                    <tr><td><kbd>Tab</kbd> / <kbd>Enter</kbd></td><td>Accept autocomplete suggestion</td></tr>
                    <tr><td><kbd>&#8593;</kbd> <kbd>&#8595;</kbd></td><td>Navigate autocomplete list</td></tr>
                    <tr><td>Double-click cell</td><td>Copy value to clipboard</td></tr>
                    <tr><td>Click row #</td><td>View row details</td></tr>
                </table>
            </div>
        </div>
    </div>

    <!-- Row Detail Slide-Over -->
    <div id="rowDetailPanel" class="row-detail-panel">
        <div class="row-detail-header">
            <h3 id="rowDetailTitle">Row Details</h3>
            <button class="btn-icon" onclick="closeRowDetail()">&#x2715;</button>
        </div>
        <div id="rowDetailContent" class="row-detail-content"></div>
    </div>
    <div id="rowDetailBackdrop" class="row-detail-backdrop" onclick="closeRowDetail()"></div>

    <div class="app-container">
        <!-- Header -->
        <header class="header">
            <div class="header-left">
                <div class="logo-icon">
                    <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                        <ellipse cx="12" cy="6" rx="8" ry="3"/>
                        <path d="M4 6v6c0 1.657 3.582 3 8 3s8-1.343 8-3V6"/>
                        <path d="M4 12v6c0 1.657 3.582 3 8 3s8-1.343 8-3v-6"/>
                    </svg>
                </div>
                <h1>SQLite Workbench</h1>
                <div class="connection-badge" id="connectionStatus">
                    <span class="status-dot"></span>
                    <span class="status-text">Connected</span>
                </div>
            </div>
            <div class="header-right">
                <select id="databaseSelector" class="database-selector">
                    <option value="">Select Database...</option>
                </select>
                <span class="database-info" id="databaseInfo"></span>
                <div class="header-actions">
                    <button id="darkModeToggle" class="btn-icon" title="Toggle Dark Mode (Ctrl+D)">
                        <svg id="sunIcon" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" style="display:none">
                            <circle cx="12" cy="12" r="5"/><line x1="12" y1="1" x2="12" y2="3"/><line x1="12" y1="21" x2="12" y2="23"/><line x1="4.22" y1="4.22" x2="5.64" y2="5.64"/><line x1="18.36" y1="18.36" x2="19.78" y2="19.78"/><line x1="1" y1="12" x2="3" y2="12"/><line x1="21" y1="12" x2="23" y2="12"/><line x1="4.22" y1="19.78" x2="5.64" y2="18.36"/><line x1="18.36" y1="5.64" x2="19.78" y2="4.22"/>
                        </svg>
                        <svg id="moonIcon" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                            <path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/>
                        </svg>
                    </button>
                    <button id="shortcutsBtn" class="btn-icon" title="Keyboard Shortcuts (?)">
                        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                            <rect x="2" y="6" width="20" height="12" rx="2"/>
                            <path d="M6 10h.01M10 10h.01M14 10h.01M18 10h.01M8 14h8"/>
                        </svg>
                    </button>
                </div>
            </div>
        </header>

        <div class="main-content">
            <!-- Left Sidebar -->
            <aside class="sidebar" id="sidebar">
                <div class="sidebar-header">
                    <h2>Tables</h2>
                    <button id="refreshTables" class="btn-icon" title="Refresh tables">&#8635;</button>
                </div>
                <div class="sidebar-search">
                    <input type="text" id="tableSearch" placeholder="Filter tables... (Ctrl+K)" class="search-input" />
                </div>
                <div id="tablesList" class="tables-list">
                    <p class="empty-state">Select a database to view tables</p>
                </div>
            </aside>

            <!-- Resize Handle -->
            <div class="resize-handle" id="resizeHandle"></div>

            <!-- Main Content Area -->
            <main class="content-area">
                <!-- Welcome screen (shown when no tabs open) -->
                <div id="welcomeScreen" class="empty-state-large">
                    <div class="welcome-content">
                        <svg class="welcome-icon" width="64" height="64" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
                            <ellipse cx="12" cy="6" rx="8" ry="3"/>
                            <path d="M4 6v6c0 1.657 3.582 3 8 3s8-1.343 8-3V6"/>
                            <path d="M4 12v6c0 1.657 3.582 3 8 3s8-1.343 8-3v-6"/>
                        </svg>
                        <h2>Welcome to SQLite Workbench</h2>
                        <p class="welcome-subtitle">Click a table in the sidebar to open it, or start a new query</p>
                        <div class="welcome-features">
                            <div class="feature-card">
                                <strong>Open Tables as Tabs</strong>
                                <span>Click any table to open it in a new tab</span>
                            </div>
                            <div class="feature-card">
                                <strong>Multiple Queries</strong>
                                <span>Open many query tabs side by side</span>
                            </div>
                            <div class="feature-card">
                                <strong>Inspect Schema</strong>
                                <span>Toggle Data / Structure per table tab</span>
                            </div>
                            <div class="feature-card">
                                <strong>Export Data</strong>
                                <span>Download as CSV or JSON per table</span>
                            </div>
                        </div>
                        <p class="welcome-hint">
                            <kbd>Ctrl+T</kbd> New query &nbsp;
                            <kbd>Ctrl+K</kbd> Search tables &nbsp;
                            <kbd>?</kbd> All shortcuts
                        </p>
                    </div>
                </div>

                <!-- Workspace (shown when tabs exist) -->
                <div id="workspaceArea" class="workspace-area" style="display:none">
                    <!-- Unified Tab Bar -->
                    <div class="workspace-tabs-bar">
                        <div class="workspace-tabs-scroll" id="workspaceTabsList"></div>
                        <button class="workspace-tab-add" id="addTabBtn" title="New Query (Ctrl+T)">+</button>
                    </div>
                    <!-- Tab Content Panes -->
                    <div class="workspace-content" id="workspaceContent"></div>
                </div>
            </main>
        </div>
    </div>

    <script>
${_getWebUIJS()}
    </script>
</body>
</html>
''';
  }

  /// Get embedded CSS
  String _getWebUICSS() {
    return _webUICSS;
  }

  /// Get embedded JavaScript
  String _getWebUIJS() {
    return _webUIJS;
  }

  // ======================== EMBEDDED CSS ========================
  static const String _webUICSS = '''
/* ==================== RESET & VARIABLES ==================== */
* { margin: 0; padding: 0; box-sizing: border-box; }

:root {
    --primary: #4f6bed;
    --primary-hover: #3d5bd9;
    --primary-light: rgba(79,107,237,0.1);
    --bg: #f5f7fa;
    --card: #ffffff;
    --text: #1e293b;
    --text-secondary: #64748b;
    --border: #e2e8f0;
    --hover: #f1f5f9;
    --success: #10b981;
    --danger: #ef4444;
    --warning: #f59e0b;
    --info: #3b82f6;
    --sidebar-width: 260px;
    --header-height: 56px;
    --tab-bar-height: 38px;
    --radius: 6px;
    --radius-lg: 10px;
    --shadow: 0 1px 3px rgba(0,0,0,0.06);
    --shadow-md: 0 4px 12px rgba(0,0,0,0.08);
    --shadow-lg: 0 8px 24px rgba(0,0,0,0.12);
    --font-mono: "SF Mono","Fira Code","Cascadia Code",Menlo,Consolas,monospace;
}

/* ==================== DARK MODE ==================== */
body.dark-mode {
    --primary: #6b8aff;
    --primary-hover: #8da4ff;
    --primary-light: rgba(107,138,255,0.15);
    --bg: #0f1117;
    --card: #1a1d2e;
    --text: #e2e8f0;
    --text-secondary: #94a3b8;
    --border: #2d3348;
    --hover: #242840;
    --shadow: 0 1px 3px rgba(0,0,0,0.3);
    --shadow-md: 0 4px 12px rgba(0,0,0,0.3);
    --shadow-lg: 0 8px 24px rgba(0,0,0,0.4);
}

/* ==================== BASE ==================== */
body {
    font-family: -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,"Helvetica Neue",Arial,sans-serif;
    background: var(--bg);
    color: var(--text);
    line-height: 1.5;
    overflow: hidden;
    font-size: 14px;
}

.app-container {
    display: flex;
    flex-direction: column;
    height: 100vh;
    overflow: hidden;
}

/* ==================== HEADER ==================== */
.header {
    background: var(--card);
    border-bottom: 1px solid var(--border);
    padding: 0 1.25rem;
    height: var(--header-height);
    display: flex;
    justify-content: space-between;
    align-items: center;
    box-shadow: var(--shadow);
    flex-shrink: 0;
    z-index: 10;
}
.header-left { display: flex; align-items: center; gap: 0.75rem; }
.logo-icon { display: flex; align-items: center; color: var(--primary); }
.header-left h1 { font-size: 1.1rem; font-weight: 700; letter-spacing: -0.02em; }
.connection-badge {
    display: inline-flex; align-items: center; gap: 6px;
    padding: 3px 10px; border-radius: 20px; font-size: 0.75rem; font-weight: 500;
    background: rgba(16,185,129,0.1); color: var(--success);
}
.connection-badge.disconnected { background: rgba(239,68,68,0.1); color: var(--danger); }
.status-dot {
    width: 7px; height: 7px; border-radius: 50%;
    background: var(--success); display: inline-block;
}
.connection-badge.disconnected .status-dot { background: var(--danger); }
.header-right { display: flex; align-items: center; gap: 0.75rem; }
.header-actions { display: flex; gap: 4px; }
.database-selector {
    padding: 6px 12px; border: 1px solid var(--border); border-radius: var(--radius);
    font-size: 0.85rem; min-width: 200px; background: var(--card); color: var(--text); cursor: pointer;
}
.database-info {
    font-size: 0.8rem; color: var(--text-secondary);
    max-width: 200px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
}
.btn-icon {
    background: none; border: 1px solid transparent; cursor: pointer;
    padding: 6px; color: var(--text-secondary); border-radius: var(--radius);
    display: flex; align-items: center; justify-content: center; transition: all 0.15s;
}
.btn-icon:hover { color: var(--primary); background: var(--primary-light); }

/* ==================== MAIN LAYOUT ==================== */
.main-content { display: flex; flex: 1; overflow: hidden; }

/* ==================== SIDEBAR ==================== */
.sidebar {
    width: var(--sidebar-width); min-width: 180px; max-width: 500px;
    background: var(--card); border-right: 1px solid var(--border);
    display: flex; flex-direction: column; flex-shrink: 0;
}
.sidebar-header {
    padding: 0.75rem 1rem; border-bottom: 1px solid var(--border);
    display: flex; justify-content: space-between; align-items: center; flex-shrink: 0;
}
.sidebar-header h2 {
    font-size: 0.85rem; font-weight: 600; text-transform: uppercase;
    letter-spacing: 0.05em; color: var(--text-secondary);
}
.sidebar-search { padding: 0.5rem 0.75rem; border-bottom: 1px solid var(--border); flex-shrink: 0; }
.search-input {
    width: 100%; padding: 6px 10px; border: 1px solid var(--border);
    border-radius: var(--radius); font-size: 0.85rem;
    background: var(--bg); color: var(--text); outline: none; transition: border-color 0.15s;
}
.search-input:focus { border-color: var(--primary); box-shadow: 0 0 0 3px var(--primary-light); }
.tables-list { flex: 1; overflow-y: auto; padding: 0.5rem; }
.database-section { margin-bottom: 0.5rem; }
.database-section-header {
    padding: 0.5rem 0.75rem; background: var(--bg); font-weight: 600; font-size: 0.85rem;
    cursor: pointer; display: flex; justify-content: space-between; align-items: center;
    border-radius: var(--radius); transition: background 0.15s;
}
.database-section-header:hover { background: var(--hover); }
.database-section-header.active { background: var(--primary); color: white; }
.table-item {
    padding: 5px 8px 5px 1.5rem; cursor: pointer; border-radius: var(--radius);
    margin: 2px 0; display: flex; justify-content: space-between; align-items: center;
    font-size: 0.85rem; transition: background 0.1s;
}
.table-item:hover { background: var(--hover); }
.table-item.active { background: var(--primary); color: white; }
.table-item .table-name { flex: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.table-item .table-count {
    font-size: 0.7rem; color: var(--text-secondary); background: var(--bg);
    padding: 1px 6px; border-radius: 10px; margin-left: 6px; font-weight: 500; flex-shrink: 0;
}
.table-item.active .table-count { background: rgba(255,255,255,0.2); color: rgba(255,255,255,0.9); }
.table-item.hidden { display: none; }
.empty-state { padding: 1.5rem 1rem; text-align: center; color: var(--text-secondary); font-size: 0.85rem; }

/* ==================== RESIZE HANDLE ==================== */
.resize-handle {
    width: 4px; cursor: col-resize; background: transparent;
    transition: background 0.15s; flex-shrink: 0; z-index: 5;
}
.resize-handle:hover, .resize-handle.active { background: var(--primary); }

/* ==================== CONTENT AREA ==================== */
.content-area { flex: 1; display: flex; flex-direction: column; overflow: hidden; min-width: 0; }

/* ==================== WELCOME SCREEN ==================== */
.empty-state-large { display: flex; align-items: center; justify-content: center; height: 100%; padding: 2rem; }
.welcome-content { text-align: center; max-width: 560px; }
.welcome-icon { color: var(--text-secondary); margin-bottom: 1.25rem; opacity: 0.4; }
.welcome-content h2 { font-size: 1.5rem; font-weight: 700; margin-bottom: 0.5rem; }
.welcome-subtitle { color: var(--text-secondary); margin-bottom: 2rem; font-size: 1rem; }
.welcome-features { display: grid; grid-template-columns: repeat(2,1fr); gap: 1rem; margin-bottom: 2rem; text-align: left; }
.feature-card {
    padding: 1rem; background: var(--card); border: 1px solid var(--border);
    border-radius: var(--radius-lg); display: flex; flex-direction: column; gap: 4px;
}
.feature-card strong { font-size: 0.9rem; }
.feature-card span { font-size: 0.8rem; color: var(--text-secondary); }
.welcome-hint { font-size: 0.8rem; color: var(--text-secondary); }
kbd {
    display: inline-block; padding: 2px 6px; font-size: 0.75rem; font-family: var(--font-mono);
    background: var(--bg); border: 1px solid var(--border); border-radius: 4px; box-shadow: 0 1px 0 var(--border);
}

/* ==================== WORKSPACE AREA ==================== */
.workspace-area { display: flex; flex-direction: column; height: 100%; overflow: hidden; }

/* ==================== WORKSPACE TAB BAR ==================== */
.workspace-tabs-bar {
    display: flex; align-items: stretch; background: var(--bg);
    border-bottom: 1px solid var(--border); flex-shrink: 0; height: var(--tab-bar-height);
}
.workspace-tabs-scroll {
    display: flex; overflow-x: auto; flex: 1; min-width: 0;
    scrollbar-width: none;
}
.workspace-tabs-scroll::-webkit-scrollbar { display: none; }

.workspace-tab {
    display: flex; align-items: center; gap: 6px;
    padding: 0 14px; cursor: pointer;
    border-right: 1px solid var(--border); background: var(--bg);
    font-size: 0.82rem; white-space: nowrap; flex-shrink: 0;
    transition: background 0.1s; position: relative; user-select: none;
    height: 100%;
}
.workspace-tab:hover { background: var(--hover); }
.workspace-tab.active {
    background: var(--card);
    box-shadow: inset 0 -2px 0 var(--primary);
}

/* Tab type indicators */
.workspace-tab .tab-indicator {
    width: 8px; height: 8px; border-radius: 2px; flex-shrink: 0;
}
.workspace-tab.table-tab .tab-indicator { background: var(--info); border-radius: 2px; }
.workspace-tab.query-tab .tab-indicator { background: var(--success); border-radius: 50%; }

.workspace-tab .tab-label {
    max-width: 140px; overflow: hidden; text-overflow: ellipsis;
}

.workspace-tab .tab-close {
    font-size: 1rem; line-height: 1; color: var(--text-secondary);
    border-radius: 50%; width: 18px; height: 18px;
    display: flex; align-items: center; justify-content: center;
    opacity: 0; transition: all 0.1s; flex-shrink: 0;
}
.workspace-tab:hover .tab-close,
.workspace-tab.active .tab-close { opacity: 1; }
.workspace-tab .tab-close:hover { background: rgba(239,68,68,0.15); color: var(--danger); }

.workspace-tab-add {
    padding: 0 12px; border: none; background: var(--bg); color: var(--text-secondary);
    cursor: pointer; font-size: 1.15rem; line-height: 1;
    display: flex; align-items: center; justify-content: center;
    min-width: 36px; flex-shrink: 0; transition: all 0.1s;
}
.workspace-tab-add:hover { background: var(--hover); color: var(--primary); }

/* ==================== WORKSPACE CONTENT ==================== */
.workspace-content { flex: 1; overflow: hidden; position: relative; }

.workspace-pane {
    display: none; position: absolute; top: 0; left: 0; right: 0; bottom: 0;
    flex-direction: column; overflow: hidden;
}
.workspace-pane.active { display: flex; }

/* ==================== TABLE TAB CONTENT ==================== */
.table-tab-toolbar {
    display: flex; align-items: center; justify-content: space-between;
    padding: 6px 1rem; background: var(--card);
    border-bottom: 1px solid var(--border); flex-shrink: 0;
    gap: 0.75rem; flex-wrap: wrap;
}
.toolbar-section { display: flex; align-items: center; gap: 0.75rem; flex-wrap: wrap; }

/* Sub-view toggle (Data / Structure) */
.sub-view-toggle {
    display: flex; background: var(--bg); border-radius: var(--radius);
    padding: 2px; border: 1px solid var(--border);
}
.sub-view-btn {
    padding: 3px 14px; border: none; background: transparent; cursor: pointer;
    font-size: 0.8rem; font-weight: 500; border-radius: calc(var(--radius) - 2px);
    color: var(--text-secondary); transition: all 0.15s;
}
.sub-view-btn.active { background: var(--card); color: var(--text); box-shadow: var(--shadow); }
.sub-view-btn:hover:not(.active) { color: var(--text); }

.data-controls { display: flex; align-items: center; gap: 0.75rem; flex-wrap: wrap; }
.data-controls label {
    font-size: 0.8rem; color: var(--text-secondary);
    display: flex; align-items: center; gap: 4px;
}
.data-controls select {
    padding: 3px 6px; border: 1px solid var(--border); border-radius: var(--radius);
    background: var(--card); color: var(--text); font-size: 0.8rem; cursor: pointer;
}
.data-filter-input {
    padding: 4px 8px; border: 1px solid var(--border); border-radius: var(--radius);
    font-size: 0.8rem; background: var(--bg); color: var(--text); width: 150px;
    outline: none; transition: border-color 0.15s;
}
.data-filter-input:focus { border-color: var(--primary); box-shadow: 0 0 0 3px var(--primary-light); }
.page-info { color: var(--text-secondary); font-size: 0.78rem; white-space: nowrap; }
.page-nav { display: flex; gap: 2px; align-items: center; }
.page-btn {
    min-width: 28px; height: 28px; padding: 0 5px;
    border: 1px solid var(--border); border-radius: var(--radius);
    background: var(--card); color: var(--text); cursor: pointer;
    display: flex; align-items: center; justify-content: center;
    font-size: 0.78rem; transition: all 0.15s;
}
.page-btn:hover:not(:disabled) { background: var(--hover); border-color: var(--text-secondary); }
.page-btn.active { background: var(--primary); color: white; border-color: var(--primary); }
.page-btn:disabled { cursor: default; opacity: 0.4; }

.btn-group { display: flex; }
.btn-group .btn-small:first-child { border-radius: var(--radius) 0 0 var(--radius); }
.btn-group .btn-small:last-child { border-radius: 0 var(--radius) var(--radius) 0; border-left: none; }
.btn-small {
    padding: 4px 10px; border: 1px solid var(--border); border-radius: var(--radius);
    cursor: pointer; font-size: 0.78rem; background: var(--card); color: var(--text);
    font-weight: 500; transition: all 0.15s;
}
.btn-small:hover { background: var(--hover); border-color: var(--text-secondary); }

/* Sub-views */
.table-tab-body { flex: 1; overflow: hidden; position: relative; }
.sub-view { display: none; position: absolute; top: 0; left: 0; right: 0; bottom: 0; overflow: auto; }
.sub-view.active { display: block; }

/* Data Table */
.table-container { height: 100%; overflow: auto; background: var(--card); }
.data-table { width: 100%; border-collapse: collapse; font-size: 0.83rem; }
.data-table th {
    background: var(--bg); padding: 7px 10px; text-align: left; font-weight: 600; font-size: 0.78rem;
    border-bottom: 2px solid var(--border); position: sticky; top: 0; z-index: 2;
    cursor: pointer; user-select: none; white-space: nowrap; transition: background 0.1s;
}
.data-table th:hover { background: var(--hover); }
.data-table th .sort-arrow { margin-left: 4px; font-size: 0.65rem; color: var(--text-secondary); opacity: 0.3; }
.data-table th .sort-arrow.asc, .data-table th .sort-arrow.desc { opacity: 1; color: var(--primary); }
.data-table th.row-num-col {
    cursor: default; text-align: center; width: 44px; min-width: 44px;
    color: var(--text-secondary); font-weight: 500;
}
.data-table td {
    padding: 5px 10px; border-bottom: 1px solid var(--border);
    max-width: 280px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
}
.data-table td.row-num-cell {
    text-align: center; color: var(--text-secondary); font-size: 0.72rem;
    cursor: pointer; font-weight: 500;
}
.data-table td.row-num-cell:hover { color: var(--primary); background: var(--primary-light); }
.data-table tbody tr:nth-child(even) { background: var(--bg); }
.data-table tbody tr:hover { background: var(--primary-light); }
.data-table .null-value { color: var(--text-secondary); font-style: italic; opacity: 0.6; }
.data-table .cell-copied { animation: flashCopy 0.5s ease; }
@keyframes flashCopy { 0% { background: var(--primary-light); } 100% { background: transparent; } }

/* Structure view */
.structure-view-inner { padding: 1.25rem; }
.info-section { margin-bottom: 2rem; }
.info-section h3 { margin-bottom: 0.75rem; font-size: 0.95rem; font-weight: 600; }
.schema-table, .indexes-table {
    width: 100%; border-collapse: collapse; background: var(--card);
    border: 1px solid var(--border); border-radius: var(--radius); overflow: hidden; font-size: 0.83rem;
}
.schema-table th, .indexes-table th {
    background: var(--bg); padding: 7px 10px; text-align: left;
    font-weight: 600; font-size: 0.78rem; border-bottom: 2px solid var(--border);
}
.schema-table td, .indexes-table td { padding: 7px 10px; border-bottom: 1px solid var(--border); }
.schema-table tr:hover, .indexes-table tr:hover { background: var(--hover); }
.type-badge {
    display: inline-block; padding: 1px 8px; background: var(--bg);
    color: var(--text-secondary); border-radius: 4px; font-size: 0.78rem; font-family: var(--font-mono);
}
.pk-badge {
    display: inline-block; padding: 1px 6px; background: var(--primary-light);
    color: var(--primary); border-radius: 4px; font-size: 0.72rem; font-weight: 600;
}
.notnull-badge {
    display: inline-block; padding: 1px 6px; background: rgba(245,158,11,0.1);
    color: var(--warning); border-radius: 4px; font-size: 0.72rem; font-weight: 600;
}
.code-block {
    background: var(--bg); padding: 1rem; border-radius: var(--radius); overflow-x: auto;
    font-size: 0.83rem; font-family: var(--font-mono); border: 1px solid var(--border); line-height: 1.6;
}
body.dark-mode .code-block { background: #0f1117; }

/* ==================== QUERY TAB CONTENT ==================== */
.query-tab-inner { display: flex; flex-direction: column; height: 100%; overflow-y: auto; padding: 1rem 1.25rem; }
.query-editor-container { margin-bottom: 0.75rem; flex-shrink: 0; }
.query-editor {
    width: 100%; min-height: 140px; padding: 10px; border: 1px solid var(--border);
    border-radius: var(--radius); font-family: var(--font-mono); font-size: 0.83rem;
    resize: vertical; background: var(--card); color: var(--text); line-height: 1.5;
    outline: none; transition: border-color 0.15s;
}
.query-editor:focus { border-color: var(--primary); box-shadow: 0 0 0 3px var(--primary-light); }

/* Autocomplete dropdown */
.ac-dropdown {
    position: absolute; z-index: 100; background: var(--card);
    border: 1px solid var(--border); border-radius: var(--radius);
    box-shadow: var(--shadow-md); max-height: 220px; overflow-y: auto;
    min-width: 200px; max-width: 340px; font-size: 0.82rem;
    font-family: var(--font-mono);
}
.ac-item {
    padding: 5px 10px; cursor: pointer; display: flex;
    align-items: center; gap: 8px; white-space: nowrap;
}
.ac-item:hover, .ac-item.selected { background: var(--primary-light); }
.ac-item.selected { color: var(--primary); }
.ac-badge {
    font-size: 0.65rem; font-weight: 600; padding: 1px 5px;
    border-radius: 3px; text-transform: uppercase; flex-shrink: 0;
}
.ac-badge.kw { background: rgba(139,92,246,0.12); color: #8b5cf6; }
.ac-badge.tbl { background: rgba(59,130,246,0.12); color: var(--info); }
.ac-badge.col { background: rgba(16,185,129,0.12); color: var(--success); }
.ac-badge.fn { background: rgba(245,158,11,0.12); color: var(--warning); }
.ac-name { overflow: hidden; text-overflow: ellipsis; }
.ac-hint { margin-left: auto; font-size: 0.7rem; color: var(--text-secondary); padding-left: 12px; }

/* Context menu */
.ctx-menu {
    position: fixed; z-index: 10003; background: var(--card);
    border: 1px solid var(--border); border-radius: var(--radius);
    box-shadow: var(--shadow-lg); min-width: 200px; padding: 4px 0;
    font-size: 0.83rem;
}
.ctx-item {
    padding: 6px 14px; cursor: pointer; display: flex;
    align-items: center; gap: 10px; white-space: nowrap;
    color: var(--text); transition: background 0.08s;
}
.ctx-item:hover { background: var(--primary-light); color: var(--primary); }
.ctx-icon { width: 16px; text-align: center; color: var(--text-secondary); font-size: 0.78rem; flex-shrink: 0; }
.ctx-item:hover .ctx-icon { color: var(--primary); }
.ctx-sep { height: 1px; background: var(--border); margin: 4px 0; }
.query-controls {
    display: flex; justify-content: space-between; align-items: center;
    margin-top: 0.4rem; gap: 0.5rem;
}
.query-controls-left { display: flex; gap: 0.5rem; align-items: center; }
.btn-primary {
    padding: 5px 14px; border: none; border-radius: var(--radius); cursor: pointer;
    font-size: 0.83rem; background: var(--primary); color: white; font-weight: 500;
    transition: background 0.15s;
}
.btn-primary:hover { background: var(--primary-hover); }
.query-time { color: var(--text-secondary); font-size: 0.78rem; }
.query-row-count {
    color: var(--text-secondary); font-size: 0.78rem;
    padding: 2px 8px; background: var(--bg); border-radius: 4px;
}
.query-history { margin-bottom: 0.75rem; flex-shrink: 0; }
.query-history h4 {
    margin-bottom: 0.4rem; font-size: 0.78rem; font-weight: 600;
    color: var(--text-secondary); text-transform: uppercase; letter-spacing: 0.05em;
}
.history-list { max-height: 80px; overflow-y: auto; }
.history-item {
    padding: 3px 8px; margin: 2px 0; background: var(--bg); border-radius: 4px;
    cursor: pointer; font-size: 0.78rem; font-family: var(--font-mono);
    color: var(--text-secondary); transition: all 0.1s;
    overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
}
.history-item:hover { background: var(--primary-light); color: var(--text); }
.query-results { flex: 1; min-height: 0; }
.query-results .table-container {
    max-height: 400px; overflow: auto; border: 1px solid var(--border); border-radius: var(--radius);
}
.error-message {
    padding: 0.75rem 1rem; background: rgba(239,68,68,0.1); color: var(--danger);
    border: 1px solid rgba(239,68,68,0.2); border-radius: var(--radius);
    margin-top: 0.5rem; font-size: 0.83rem; font-family: var(--font-mono); display: none;
}
.error-message.show { display: block; }

/* ==================== TOAST NOTIFICATIONS ==================== */
.toast-container {
    position: fixed; top: 16px; right: 16px; z-index: 10000;
    display: flex; flex-direction: column; gap: 8px; pointer-events: none;
}
.toast {
    padding: 10px 16px; border-radius: var(--radius); color: white;
    font-size: 0.83rem; font-weight: 500; box-shadow: var(--shadow-lg);
    pointer-events: auto; max-width: 340px;
    animation: toastIn 0.25s ease, toastOut 0.25s ease 2.75s forwards;
}
.toast.success { background: var(--success); }
.toast.error { background: var(--danger); }
.toast.info { background: var(--info); }
.toast.warning { background: var(--warning); color: #1e293b; }
@keyframes toastIn { from { opacity: 0; transform: translateX(40px); } to { opacity: 1; transform: translateX(0); } }
@keyframes toastOut { from { opacity: 1; } to { opacity: 0; transform: translateY(-10px); } }

/* ==================== LOADING ==================== */
.loading-overlay {
    display: none; position: fixed; top: 0; left: 0; right: 0; bottom: 0;
    background: rgba(0,0,0,0.05); z-index: 9999;
    justify-content: center; align-items: center;
}
.loading-overlay.show { display: flex; }
.spinner {
    width: 36px; height: 36px; border: 3px solid var(--border);
    border-top-color: var(--primary); border-radius: 50%; animation: spin 0.7s linear infinite;
}
@keyframes spin { to { transform: rotate(360deg); } }

/* ==================== MODAL ==================== */
.modal-overlay {
    display: none; position: fixed; top: 0; left: 0; right: 0; bottom: 0;
    background: rgba(0,0,0,0.4); z-index: 10001; justify-content: center; align-items: center;
}
.modal-overlay.show { display: flex; }
.modal { background: var(--card); border-radius: var(--radius-lg); box-shadow: var(--shadow-lg); max-width: 480px; width: 90%; overflow: hidden; }
.modal-header {
    display: flex; justify-content: space-between; align-items: center;
    padding: 1rem 1.25rem; border-bottom: 1px solid var(--border);
}
.modal-header h3 { font-size: 1rem; font-weight: 600; }
.modal-close-btn { font-size: 1.25rem; color: var(--text-secondary); }
.modal-body { padding: 1.25rem; }
.shortcuts-table { width: 100%; font-size: 0.83rem; }
.shortcuts-table td { padding: 5px 4px; }
.shortcuts-table td:first-child { white-space: nowrap; padding-right: 1.5rem; color: var(--text-secondary); }

/* ==================== ROW DETAIL PANEL ==================== */
.row-detail-backdrop { display: none; position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(0,0,0,0.3); z-index: 999; }
.row-detail-backdrop.show { display: block; }
.row-detail-panel {
    position: fixed; top: 0; right: -420px; width: 400px; height: 100vh;
    background: var(--card); box-shadow: var(--shadow-lg); z-index: 1000;
    display: flex; flex-direction: column; transition: right 0.25s ease;
}
.row-detail-panel.show { right: 0; }
.row-detail-header {
    display: flex; justify-content: space-between; align-items: center;
    padding: 1rem 1.25rem; border-bottom: 1px solid var(--border); flex-shrink: 0;
}
.row-detail-header h3 { font-size: 1rem; font-weight: 600; }
.row-detail-content { flex: 1; overflow-y: auto; padding: 1rem 1.25rem; }
.row-detail-field { margin-bottom: 1rem; padding-bottom: 1rem; border-bottom: 1px solid var(--border); }
.row-detail-field:last-child { border-bottom: none; }
.row-detail-label {
    font-size: 0.72rem; font-weight: 600; color: var(--text-secondary);
    text-transform: uppercase; letter-spacing: 0.05em; margin-bottom: 4px;
}
.row-detail-value { font-size: 0.88rem; word-break: break-all; white-space: pre-wrap; }
.row-detail-value.null-val { color: var(--text-secondary); font-style: italic; opacity: 0.6; }

/* ==================== CONFIRM DIALOG ==================== */
.confirm-overlay {
    display: flex; position: fixed; top: 0; left: 0; right: 0; bottom: 0;
    background: rgba(0,0,0,0.4); z-index: 10002;
    justify-content: center; align-items: center;
}
.confirm-dialog { background: var(--card); border-radius: var(--radius-lg); box-shadow: var(--shadow-lg); max-width: 400px; width: 90%; padding: 1.5rem; }
.confirm-dialog h3 { font-size: 1rem; margin-bottom: 0.75rem; color: var(--danger); }
.confirm-dialog p { font-size: 0.88rem; color: var(--text-secondary); margin-bottom: 1.25rem; line-height: 1.5; }
.confirm-dialog code {
    display: block; margin-top: 0.5rem; padding: 8px; background: var(--bg);
    border-radius: 4px; font-family: var(--font-mono); font-size: 0.78rem; overflow-x: auto;
}
.confirm-actions { display: flex; gap: 0.75rem; justify-content: flex-end; }
.btn-cancel {
    padding: 6px 16px; border: 1px solid var(--border); border-radius: var(--radius);
    background: var(--card); color: var(--text); cursor: pointer; font-size: 0.83rem;
}
.btn-cancel:hover { background: var(--hover); }
.btn-danger {
    padding: 6px 16px; border: none; border-radius: var(--radius);
    background: var(--danger); color: white; cursor: pointer; font-size: 0.83rem; font-weight: 500;
}
.btn-danger:hover { background: #dc2626; }

/* ==================== SCROLLBAR ==================== */
::-webkit-scrollbar { width: 8px; height: 8px; }
::-webkit-scrollbar-track { background: transparent; }
::-webkit-scrollbar-thumb { background: var(--border); border-radius: 4px; }
::-webkit-scrollbar-thumb:hover { background: var(--text-secondary); }

/* ==================== RESPONSIVE ==================== */
@media (max-width: 768px) {
    .main-content { flex-direction: column; }
    .sidebar { width: 100% !important; max-height: 200px; min-width: unset; max-width: unset; }
    .resize-handle { display: none; }
    .header { flex-direction: column; height: auto; padding: 0.75rem 1rem; gap: 0.5rem; }
    .welcome-features { grid-template-columns: 1fr; }
    .row-detail-panel { width: 100%; right: -100%; }
}
''';

  // ======================== EMBEDDED JAVASCRIPT ========================
  static const String _webUIJS = '''
// ==================== STATE ====================
let state = {
    databases: [],
    currentDbId: null,
    tabs: [],
    activeTabId: null,
    nextTabId: 1,
    queryHistory: [],
    darkMode: false,
    tableCounts: {},
    schemaCache: {}
};

const API_BASE = '/api';

// ==================== INIT ====================
document.addEventListener('DOMContentLoaded', () => {
    initDarkMode();
    initApp();
});

async function initApp() {
    await loadDatabases();
    setupListeners();
    setupKeyboard();
    setupResize();
    checkConnection();
    setInterval(checkConnection, 5000);
}

// ==================== DARK MODE ====================
function initDarkMode() {
    if (localStorage.getItem('sqflite_dark') === 'true') {
        state.darkMode = true;
        document.body.classList.add('dark-mode');
    }
    updateDarkIcon();
}
function toggleDark() {
    state.darkMode = !state.darkMode;
    document.body.classList.toggle('dark-mode', state.darkMode);
    localStorage.setItem('sqflite_dark', state.darkMode);
    updateDarkIcon();
}
function updateDarkIcon() {
    document.getElementById('sunIcon').style.display = state.darkMode ? 'block' : 'none';
    document.getElementById('moonIcon').style.display = state.darkMode ? 'none' : 'block';
}

// ==================== EVENT LISTENERS ====================
function setupListeners() {
    document.getElementById('databaseSelector').addEventListener('change', e => {
        if (e.target.value) selectDatabase(e.target.value);
    });
    document.getElementById('refreshTables').addEventListener('click', () => {
        if (state.currentDbId) { loadTables(state.currentDbId); showToast('Refreshed', 'info'); }
    });
    document.getElementById('addTabBtn').addEventListener('click', () => openQueryTab());
    document.getElementById('darkModeToggle').addEventListener('click', toggleDark);
    document.getElementById('shortcutsBtn').addEventListener('click', () => {
        document.getElementById('shortcutsModal').style.display = 'flex';
    });
    document.getElementById('tableSearch').addEventListener('input', filterTables);
}

// ==================== KEYBOARD ====================
function setupKeyboard() {
    document.addEventListener('keydown', e => {
        if (e.key === 'Escape') {
            document.getElementById('shortcutsModal').style.display = 'none';
            closeRowDetail();
            return;
        }
        const isInput = e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA' || e.target.tagName === 'SELECT';

        if ((e.ctrlKey || e.metaKey) && e.key === 'k') { e.preventDefault(); document.getElementById('tableSearch').focus(); return; }
        if ((e.ctrlKey || e.metaKey) && e.key === 'd') { e.preventDefault(); toggleDark(); return; }
        if ((e.ctrlKey || e.metaKey) && e.key === 't') { e.preventDefault(); openQueryTab(); return; }
        if ((e.ctrlKey || e.metaKey) && e.key === 'w') {
            e.preventDefault();
            if (state.activeTabId) closeTab(state.activeTabId);
            return;
        }
        if (e.key === '?' && !isInput) {
            document.getElementById('shortcutsModal').style.display = 'flex';
        }
    });
}

// ==================== RESIZE ====================
function setupResize() {
    const handle = document.getElementById('resizeHandle');
    const sidebar = document.getElementById('sidebar');
    handle.addEventListener('mousedown', e => {
        const startX = e.clientX, startW = sidebar.offsetWidth;
        handle.classList.add('active');
        document.body.style.cursor = 'col-resize';
        document.body.style.userSelect = 'none';
        const onMove = ev => { sidebar.style.width = Math.max(180, Math.min(500, startW + ev.clientX - startX)) + 'px'; };
        const onUp = () => {
            handle.classList.remove('active');
            document.body.style.cursor = '';
            document.body.style.userSelect = '';
            document.removeEventListener('mousemove', onMove);
            document.removeEventListener('mouseup', onUp);
        };
        document.addEventListener('mousemove', onMove);
        document.addEventListener('mouseup', onUp);
    });
}

// ==================== TOAST ====================
function showToast(msg, type) {
    const c = document.getElementById('toastContainer');
    const t = document.createElement('div');
    t.className = 'toast ' + (type || 'info');
    t.textContent = msg;
    c.appendChild(t);
    setTimeout(() => { if (t.parentNode) t.remove(); }, 3000);
}

// ==================== LOADING ====================
function showLoading() { document.getElementById('loadingOverlay').classList.add('show'); }
function hideLoading() { document.getElementById('loadingOverlay').classList.remove('show'); }

// ==================== DATABASE ====================
async function loadDatabases() {
    try {
        const res = await fetch(API_BASE + '/databases');
        const data = await res.json();
        state.databases = data.databases || [];
        const sel = document.getElementById('databaseSelector');
        sel.innerHTML = '<option value="">Select Database...</option>';
        state.databases.forEach(db => {
            const o = document.createElement('option');
            o.value = db.id;
            o.textContent = db.name + ' (' + db.id + ')';
            sel.appendChild(o);
        });
        if (state.databases.length > 0 && !state.currentDbId) selectDatabase(state.databases[0].id);
    } catch (err) {
        console.error('Failed to load databases:', err);
        updateConnectionStatus(false);
    }
}

async function selectDatabase(dbId) {
    state.currentDbId = dbId;
    const db = state.databases.find(d => d.id === dbId);
    if (db) {
        document.getElementById('databaseSelector').value = dbId;
        document.getElementById('databaseInfo').textContent = db.path;
    }
    await loadTables(dbId);
    loadSchemaCache(dbId);
}

// ==================== TABLES LIST ====================
async function loadTables(dbId) {
    try {
        const res = await fetch(API_BASE + '/databases/' + dbId + '/tables');
        const data = await res.json();
        const tables = data.tables || [];
        const list = document.getElementById('tablesList');
        list.innerHTML = '';
        if (tables.length === 0) { list.innerHTML = '<p class="empty-state">No tables found</p>'; return; }

        const db = state.databases.find(d => d.id === dbId);
        const sec = document.createElement('div');
        sec.className = 'database-section';

        const hdr = document.createElement('div');
        hdr.className = 'database-section-header active';
        hdr.textContent = db ? db.name : dbId;
        sec.appendChild(hdr);

        tables.forEach(name => {
            const item = document.createElement('div');
            item.className = 'table-item';
            item.dataset.tableName = name.toLowerCase();
            item.dataset.rawName = name;

            const nameEl = document.createElement('span');
            nameEl.className = 'table-name';
            nameEl.textContent = name;
            item.appendChild(nameEl);

            const countEl = document.createElement('span');
            countEl.className = 'table-count';
            countEl.textContent = '...';
            countEl.id = 'cnt_' + name;
            item.appendChild(countEl);

            item.addEventListener('click', () => openTableTab(dbId, name));
            item.addEventListener('auxclick', e => { if (e.button === 1) openTableTab(dbId, name); });
            sec.appendChild(item);
        });
        list.appendChild(sec);
        loadTableCounts(dbId, tables);
    } catch (err) {
        console.error('Failed to load tables:', err);
        document.getElementById('tablesList').innerHTML = '<p class="empty-state">Failed to load tables</p>';
    }
}

async function loadTableCounts(dbId, tables) {
    for (const name of tables) {
        try {
            const res = await fetch(API_BASE + '/databases/' + dbId + '/table/' + name + '/count');
            const data = await res.json();
            state.tableCounts[name] = data.count;
            const el = document.getElementById('cnt_' + name);
            if (el) { el.textContent = fmtNum(data.count); el.title = data.count + ' rows'; }
        } catch (e) {}
    }
}

function filterTables() {
    const q = document.getElementById('tableSearch').value.toLowerCase().trim();
    document.querySelectorAll('.table-item').forEach(item => {
        item.classList.toggle('hidden', q !== '' && !(item.dataset.tableName || '').includes(q));
    });
}

function updateSidebarHighlight() {
    document.querySelectorAll('.table-item').forEach(i => i.classList.remove('active'));
    const tab = state.tabs.find(t => t.id === state.activeTabId);
    if (tab && tab.type === 'table') {
        document.querySelectorAll('.table-item').forEach(i => {
            if (i.dataset.rawName === tab.tableName) i.classList.add('active');
        });
    }
}

// ==================== TAB MANAGEMENT ====================
function openTableTab(dbId, tableName) {
    // Reuse existing tab for same table
    const existing = state.tabs.find(t => t.type === 'table' && t.dbId === dbId && t.tableName === tableName);
    if (existing) { switchToTab(existing.id); return; }

    const tab = {
        id: 'tab_' + state.nextTabId++,
        type: 'table',
        dbId: dbId,
        tableName: tableName,
        subView: 'data',
        page: 1,
        pageSize: 25,
        sortColumn: null,
        sortDir: 'asc',
        pageData: [],
        columns: [],
        structureLoaded: false
    };
    state.tabs.push(tab);
    createTabHeader(tab);
    createTablePane(tab);
    switchToTab(tab.id);
    loadTabData(tab.id);
}

function openQueryTab() {
    const num = state.tabs.filter(t => t.type === 'query').length + 1;
    const tab = {
        id: 'tab_' + state.nextTabId++,
        type: 'query',
        name: 'Query ' + num
    };
    state.tabs.push(tab);
    createTabHeader(tab);
    createQueryPane(tab);
    switchToTab(tab.id);
    showWorkspace();
}

function switchToTab(tabId) {
    state.activeTabId = tabId;
    document.querySelectorAll('.workspace-tab').forEach(el => el.classList.toggle('active', el.dataset.id === tabId));
    document.querySelectorAll('.workspace-pane').forEach(el => el.classList.toggle('active', el.id === 'pane_' + tabId));
    updateSidebarHighlight();
    showWorkspace();
    // Focus query editor if query tab
    const tab = state.tabs.find(t => t.id === tabId);
    if (tab && tab.type === 'query') {
        setTimeout(() => {
            const ed = document.querySelector('#pane_' + tabId + ' .query-editor');
            if (ed) ed.focus();
        }, 0);
    }
}

function closeTab(tabId) {
    const idx = state.tabs.findIndex(t => t.id === tabId);
    if (idx === -1) return;
    state.tabs.splice(idx, 1);

    const hdr = document.querySelector('.workspace-tab[data-id="' + tabId + '"]');
    if (hdr) hdr.remove();
    const pane = document.getElementById('pane_' + tabId);
    if (pane) pane.remove();

    if (state.activeTabId === tabId) {
        if (state.tabs.length > 0) {
            switchToTab(state.tabs[Math.min(idx, state.tabs.length - 1)].id);
        } else {
            state.activeTabId = null;
            hideWorkspace();
        }
    }
    updateSidebarHighlight();
}

function showWorkspace() {
    document.getElementById('welcomeScreen').style.display = 'none';
    document.getElementById('workspaceArea').style.display = 'flex';
}

function hideWorkspace() {
    document.getElementById('welcomeScreen').style.display = 'flex';
    document.getElementById('workspaceArea').style.display = 'none';
}

// ==================== TAB HEADER ====================
function createTabHeader(tab) {
    const el = document.createElement('div');
    el.className = 'workspace-tab ' + tab.type + '-tab';
    el.dataset.id = tab.id;

    const indicator = document.createElement('span');
    indicator.className = 'tab-indicator';
    el.appendChild(indicator);

    const label = document.createElement('span');
    label.className = 'tab-label';
    label.textContent = tab.type === 'table' ? tab.tableName : tab.name;
    el.appendChild(label);

    const close = document.createElement('span');
    close.className = 'tab-close';
    close.innerHTML = '\\u00D7';
    close.title = 'Close (Ctrl+W)';
    close.addEventListener('click', e => { e.stopPropagation(); closeTab(tab.id); });
    el.appendChild(close);

    el.addEventListener('click', () => switchToTab(tab.id));
    el.addEventListener('auxclick', e => { if (e.button === 1) { e.preventDefault(); closeTab(tab.id); } });

    document.getElementById('workspaceTabsList').appendChild(el);
}

// ==================== TABLE TAB PANE ====================
function createTablePane(tab) {
    const pane = document.createElement('div');
    pane.className = 'workspace-pane';
    pane.id = 'pane_' + tab.id;

    pane.innerHTML =
        '<div class="table-tab-toolbar">' +
        '  <div class="toolbar-section">' +
        '    <div class="sub-view-toggle">' +
        '      <button class="sub-view-btn active" data-view="data">Data</button>' +
        '      <button class="sub-view-btn" data-view="structure">Structure</button>' +
        '    </div>' +
        '  </div>' +
        '  <div class="toolbar-section data-controls-section">' +
        '    <div class="data-controls">' +
        '      <label>Rows: <select class="ps-select">' +
        '        <option value="10">10</option><option value="25" selected>25</option>' +
        '        <option value="50">50</option><option value="100">100</option><option value="500">500</option>' +
        '      </select></label>' +
        '      <input type="text" class="data-filter-input" placeholder="Quick filter..." />' +
        '      <span class="page-info"></span>' +
        '      <div class="page-nav"></div>' +
        '      <div class="btn-group">' +
        '        <button class="btn-small csv-btn">CSV</button>' +
        '        <button class="btn-small json-btn">JSON</button>' +
        '      </div>' +
        '    </div>' +
        '  </div>' +
        '</div>' +
        '<div class="table-tab-body">' +
        '  <div class="sub-view data-view active">' +
        '    <div class="table-container"><table class="data-table"><thead></thead><tbody></tbody></table></div>' +
        '  </div>' +
        '  <div class="sub-view structure-view">' +
        '    <div class="structure-view-inner">' +
        '      <div class="info-section"><h3>Columns</h3><div class="schema-area"></div></div>' +
        '      <div class="info-section"><h3>Indexes</h3><div class="indexes-area"></div></div>' +
        '      <div class="info-section"><h3>CREATE TABLE Statement</h3><pre class="code-block create-stmt"></pre></div>' +
        '    </div>' +
        '  </div>' +
        '</div>';

    // Sub-view toggle
    pane.querySelectorAll('.sub-view-btn').forEach(btn => {
        btn.addEventListener('click', () => {
            const view = btn.dataset.view;
            tab.subView = view;
            pane.querySelectorAll('.sub-view-btn').forEach(b => b.classList.toggle('active', b.dataset.view === view));
            pane.querySelectorAll('.sub-view').forEach(v => v.classList.toggle('active', v.classList.contains(view + '-view')));
            pane.querySelector('.data-controls-section').style.display = view === 'data' ? '' : 'none';
            if (view === 'structure' && !tab.structureLoaded) {
                loadTabStructure(tab.id);
            }
        });
    });

    // Page size
    pane.querySelector('.ps-select').addEventListener('change', e => {
        tab.pageSize = parseInt(e.target.value);
        tab.page = 1;
        loadTabData(tab.id);
    });

    // Filter
    pane.querySelector('.data-filter-input').addEventListener('input', e => {
        const q = e.target.value.toLowerCase().trim();
        pane.querySelectorAll('.data-view tbody tr').forEach(row => {
            row.style.display = (!q || row.textContent.toLowerCase().includes(q)) ? '' : 'none';
        });
    });

    // Export
    pane.querySelector('.csv-btn').addEventListener('click', () => exportCSV(tab.id));
    pane.querySelector('.json-btn').addEventListener('click', () => exportJSON(tab.id));

    // Table event delegation (sort, row detail, copy)
    const tableEl = pane.querySelector('.data-table');
    tableEl.addEventListener('click', e => {
        const th = e.target.closest('th[data-col]');
        if (th) { sortTabColumn(tab.id, th.dataset.col); return; }
        const rn = e.target.closest('.row-num-cell');
        if (rn) { showRowDetail(tab.id, parseInt(rn.dataset.idx)); }
    });
    tableEl.addEventListener('dblclick', e => {
        const td = e.target.closest('td:not(.row-num-cell)');
        if (td) copyCell(td);
    });

    // Right-click context menu for copy operations
    attachTableContextMenu(tableEl, () => {
        const t = state.tabs.find(x => x.id === tab.id);
        return t ? { columns: t.columns, data: t.pageData } : null;
    });

    document.getElementById('workspaceContent').appendChild(pane);
}

// ==================== QUERY TAB PANE ====================
function createQueryPane(tab) {
    const pane = document.createElement('div');
    pane.className = 'workspace-pane';
    pane.id = 'pane_' + tab.id;

    pane.innerHTML =
        '<div class="query-tab-inner">' +
        '  <div class="query-editor-container">' +
        '    <textarea class="query-editor" placeholder="Enter SQL query... (Ctrl+Enter to execute)"></textarea>' +
        '    <div class="query-controls">' +
        '      <div class="query-controls-left">' +
        '        <button class="btn-primary exec-btn">Execute</button>' +
        '        <span class="query-time"></span>' +
        '      </div>' +
        '      <span class="query-row-count"></span>' +
        '    </div>' +
        '  </div>' +
        '  <div class="query-history"><h4>History</h4><div class="history-list"></div></div>' +
        '  <div class="query-results">' +
        '    <div class="table-container"><table class="data-table"><thead></thead><tbody></tbody></table></div>' +
        '  </div>' +
        '  <div class="error-message"></div>' +
        '</div>';

    const editor = pane.querySelector('.query-editor');
    pane.querySelector('.exec-btn').addEventListener('click', () => execQuery(tab.id));
    editor.addEventListener('keydown', e => {
        if ((e.ctrlKey || e.metaKey) && e.key === 'Enter') { e.preventDefault(); execQuery(tab.id); }
    });

    // Attach autocomplete (handles Tab key for accept or indent)
    attachAutocomplete(editor);

    // Right-click context menu on query results table
    const qResultTable = pane.querySelector('.query-results .data-table');
    attachTableContextMenu(qResultTable, () => {
        const t = state.tabs.find(x => x.id === tab.id);
        return t ? { columns: t._resultCols || [], data: t._resultData || [] } : null;
    });

    updatePaneHistory(pane);
    document.getElementById('workspaceContent').appendChild(pane);
}

// ==================== LOAD TABLE DATA ====================
async function loadTabData(tabId) {
    const tab = state.tabs.find(t => t.id === tabId);
    if (!tab || tab.type !== 'table') return;
    const pane = document.getElementById('pane_' + tabId);
    if (!pane) return;

    showLoading();
    try {
        const res = await fetch(
            API_BASE + '/databases/' + tab.dbId + '/table/' + tab.tableName +
            '?page=' + tab.page + '&limit=' + tab.pageSize
        );
        const data = await res.json();

        if (data.data && data.data.length > 0) {
            tab.columns = Object.keys(data.data[0]);
            tab.pageData = data.data;
            renderTabTable(tab, pane);
            const pg = data.pagination;
            tab.page = pg.page;
            pane.querySelector('.page-info').textContent = 'Page ' + pg.page + ' of ' + (pg.totalPages || 1) + ' (' + fmtNum(pg.total) + ')';
            renderTabPagination(tab, pane, pg.totalPages || 1, pg.page);
        } else {
            tab.pageData = [];
            tab.columns = [];
            pane.querySelector('.data-view thead').innerHTML = '';
            pane.querySelector('.data-view tbody').innerHTML = '<tr><td colspan="100" style="text-align:center;padding:2rem;color:var(--text-secondary)">No data</td></tr>';
            pane.querySelector('.page-info').textContent = '0 rows';
            pane.querySelector('.page-nav').innerHTML = '';
        }
    } catch (err) {
        console.error('Load error:', err);
        showToast('Failed to load data', 'error');
    }
    hideLoading();
}

function renderTabTable(tab, pane) {
    const thead = pane.querySelector('.data-view thead');
    const tbody = pane.querySelector('.data-view tbody');

    // Header
    let hHtml = '<tr><th class="row-num-col">#</th>';
    tab.columns.forEach(col => {
        let arrow = '';
        if (tab.sortColumn === col) arrow = tab.sortDir === 'asc' ? ' \\u25B2' : ' \\u25BC';
        else arrow = ' \\u25B4';
        const cls = tab.sortColumn === col ? tab.sortDir : '';
        hHtml += '<th data-col="' + escAttr(col) + '">' + escHtml(col) + '<span class="sort-arrow ' + cls + '">' + arrow + '</span></th>';
    });
    hHtml += '</tr>';
    thead.innerHTML = hHtml;

    // Body
    const start = (tab.page - 1) * tab.pageSize;
    tbody.innerHTML = tab.pageData.map((row, i) => {
        let r = '<tr><td class="row-num-cell" data-idx="' + i + '" title="View details">' + (start + i + 1) + '</td>';
        tab.columns.forEach(col => {
            const v = row[col];
            if (v === null || v === undefined) {
                r += '<td class="null-value">NULL</td>';
            } else {
                r += '<td title="' + escAttr(String(v)) + '">' + escHtml(String(v)) + '</td>';
            }
        });
        return r + '</tr>';
    }).join('');
}

function sortTabColumn(tabId, col) {
    const tab = state.tabs.find(t => t.id === tabId);
    if (!tab) return;
    if (tab.sortColumn === col) tab.sortDir = tab.sortDir === 'asc' ? 'desc' : 'asc';
    else { tab.sortColumn = col; tab.sortDir = 'asc'; }

    const sorted = [...tab.pageData].sort((a, b) => {
        let va = a[col], vb = b[col];
        if (va == null) va = '';
        if (vb == null) vb = '';
        const na = Number(va), nb = Number(vb);
        if (!isNaN(na) && !isNaN(nb)) return tab.sortDir === 'asc' ? na - nb : nb - na;
        const sa = String(va).toLowerCase(), sb = String(vb).toLowerCase();
        if (sa < sb) return tab.sortDir === 'asc' ? -1 : 1;
        if (sa > sb) return tab.sortDir === 'asc' ? 1 : -1;
        return 0;
    });

    tab.pageData = sorted;
    renderTabTable(tab, document.getElementById('pane_' + tabId));
}

function renderTabPagination(tab, pane, total, current) {
    const nav = pane.querySelector('.page-nav');
    nav.innerHTML = '';
    if (total <= 1) return;

    const mkBtn = (text, page, active, disabled) => {
        const b = document.createElement('button');
        b.className = 'page-btn' + (active ? ' active' : '');
        b.textContent = text;
        if (disabled) b.disabled = true;
        else b.onclick = () => { tab.page = page; tab.sortColumn = null; tab.sortDir = 'asc'; loadTabData(tab.id); };
        return b;
    };

    nav.appendChild(mkBtn('\\u2039', current - 1, false, current === 1));
    const delta = 2, range = [];
    for (let i = 1; i <= total; i++) {
        if (i === 1 || i === total || (i >= current - delta && i <= current + delta)) range.push(i);
    }
    let last;
    for (const i of range) {
        if (last) {
            if (i - last === 2) nav.appendChild(mkBtn(last + 1, last + 1, false, false));
            else if (i - last !== 1) nav.appendChild(mkBtn('...', 0, false, true));
        }
        nav.appendChild(mkBtn(i, i, i === current, false));
        last = i;
    }
    nav.appendChild(mkBtn('\\u203A', current + 1, false, current === total));
}

// ==================== LOAD TABLE STRUCTURE ====================
async function loadTabStructure(tabId) {
    const tab = state.tabs.find(t => t.id === tabId);
    if (!tab || tab.type !== 'table') return;
    const pane = document.getElementById('pane_' + tabId);
    if (!pane) return;

    try {
        const res = await fetch(API_BASE + '/databases/' + tab.dbId + '/schema/' + tab.tableName);
        const data = await res.json();

        // Schema
        const schemaArea = pane.querySelector('.schema-area');
        if (data.columns && data.columns.length > 0) {
            let h = '<table class="schema-table"><thead><tr><th>#</th><th>Name</th><th>Type</th><th>Not Null</th><th>Default</th><th>PK</th></tr></thead><tbody>';
            data.columns.forEach((c, i) => {
                h += '<tr><td>' + (i+1) + '</td>';
                h += '<td><strong>' + escHtml(c.name || '') + '</strong></td>';
                h += '<td><span class="type-badge">' + escHtml(c.type || '') + '</span></td>';
                h += '<td>' + (c.notnull === 1 ? '<span class="notnull-badge">NOT NULL</span>' : '-') + '</td>';
                h += '<td>' + (c.dflt_value != null ? escHtml(String(c.dflt_value)) : '-') + '</td>';
                h += '<td>' + (c.pk === 1 ? '<span class="pk-badge">PK</span>' : '-') + '</td></tr>';
            });
            h += '</tbody></table>';
            schemaArea.innerHTML = h;
        } else {
            schemaArea.innerHTML = '<p class="empty-state">No schema info</p>';
        }

        // Indexes
        const idxArea = pane.querySelector('.indexes-area');
        if (data.indexes && data.indexes.length > 0) {
            let h = '<table class="indexes-table"><thead><tr><th>Name</th><th>SQL</th></tr></thead><tbody>';
            data.indexes.forEach(idx => {
                h += '<tr><td><strong>' + escHtml(idx.name || '') + '</strong></td>';
                h += '<td><code>' + escHtml(idx.sql || 'N/A') + '</code></td></tr>';
            });
            h += '</tbody></table>';
            idxArea.innerHTML = h;
        } else {
            idxArea.innerHTML = '<p class="empty-state">No indexes</p>';
        }

        pane.querySelector('.create-stmt').textContent = data.createTable || 'Not available';
        tab.structureLoaded = true;
    } catch (err) {
        console.error('Structure load error:', err);
        showToast('Failed to load structure', 'error');
    }
}

// ==================== QUERY EXECUTION ====================
async function execQuery(tabId) {
    const tab = state.tabs.find(t => t.id === tabId);
    if (!tab || tab.type !== 'query') return;
    if (!state.currentDbId) { showToast('Select a database first', 'warning'); return; }

    const pane = document.getElementById('pane_' + tabId);
    const editor = pane.querySelector('.query-editor');

    let query;
    if (editor.selectionStart !== editor.selectionEnd) {
        query = editor.value.substring(editor.selectionStart, editor.selectionEnd).trim();
    } else {
        query = editor.value.trim();
    }
    if (!query) { showToast('Enter a query', 'warning'); return; }

    // Destructive check
    if (isDestructive(query)) {
        const ok = await confirmDialog('Destructive Query', 'This may modify or delete data. Proceed?', query);
        if (!ok) return;
    }

    // History
    if (!state.queryHistory.includes(query)) {
        state.queryHistory.unshift(query);
        if (state.queryHistory.length > 20) state.queryHistory.pop();
        updateAllHistories();
    }

    const errEl = pane.querySelector('.error-message');
    const resEl = pane.querySelector('.query-results');
    const timeEl = pane.querySelector('.query-time');
    const cntEl = pane.querySelector('.query-row-count');
    const thead = pane.querySelector('.query-results thead');
    const tbody = pane.querySelector('.query-results tbody');

    showLoading();
    try {
        const t0 = Date.now();
        const res = await fetch(API_BASE + '/databases/' + state.currentDbId + '/query', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ query: query }),
        });
        const data = await res.json();
        const elapsed = Date.now() - t0;

        if (data.error) {
            errEl.textContent = data.error;
            errEl.classList.add('show');
            resEl.style.display = 'none';
            cntEl.textContent = '';
            showToast('Query error', 'error');
        } else {
            errEl.classList.remove('show');
            timeEl.textContent = (data.executionTime || elapsed) + 'ms';
            cntEl.textContent = (data.rowCount || 0) + ' rows';

            if (data.data && data.data.length > 0) {
                const cols = Object.keys(data.data[0]);
                tab._resultCols = cols;
                tab._resultData = data.data;
                thead.innerHTML = '<tr>' + cols.map(c => '<th>' + escHtml(c) + '</th>').join('') + '</tr>';
                tbody.innerHTML = data.data.map(row =>
                    '<tr>' + cols.map(c => {
                        const v = row[c];
                        return v == null ? '<td class="null-value">NULL</td>' : '<td>' + escHtml(String(v)) + '</td>';
                    }).join('') + '</tr>'
                ).join('');
                resEl.style.display = 'block';
                showToast(data.rowCount + ' rows returned', 'success');
            } else {
                tab._resultCols = [];
                tab._resultData = [];
                thead.innerHTML = '';
                tbody.innerHTML = '';
                resEl.style.display = 'none';
                showToast('Query executed', 'success');
            }

            // Auto-refresh open table tabs on DML
            const up = query.toUpperCase().trim();
            if (/^(INSERT|UPDATE|DELETE|DROP|ALTER|CREATE)/.test(up)) {
                state.tabs.filter(t => t.type === 'table' && t.dbId === state.currentDbId).forEach(t => {
                    setTimeout(() => loadTabData(t.id), 300);
                });
                if (state.currentDbId) loadTables(state.currentDbId);
            }
        }
    } catch (err) {
        errEl.textContent = err.toString();
        errEl.classList.add('show');
        resEl.style.display = 'none';
        showToast('Query failed', 'error');
    }
    hideLoading();
}

function isDestructive(q) {
    const u = q.toUpperCase().trim();
    if (u.startsWith('DROP')) return true;
    if (u.startsWith('TRUNCATE')) return true;
    if (u.startsWith('DELETE') && !u.includes('WHERE')) return true;
    return false;
}

function confirmDialog(title, msg, code) {
    return new Promise(resolve => {
        const ov = document.createElement('div');
        ov.className = 'confirm-overlay';
        ov.innerHTML =
            '<div class="confirm-dialog">' +
            '<h3>' + escHtml(title) + '</h3>' +
            '<p>' + escHtml(msg) + '<code>' + escHtml(code.substring(0, 200)) + '</code></p>' +
            '<div class="confirm-actions">' +
            '<button class="btn-cancel">Cancel</button>' +
            '<button class="btn-danger">Execute</button>' +
            '</div></div>';
        ov.querySelector('.btn-cancel').onclick = () => { ov.remove(); resolve(false); };
        ov.querySelector('.btn-danger').onclick = () => { ov.remove(); resolve(true); };
        ov.addEventListener('click', e => { if (e.target === ov) { ov.remove(); resolve(false); } });
        document.body.appendChild(ov);
    });
}

function updateAllHistories() {
    document.querySelectorAll('.workspace-pane').forEach(pane => {
        if (pane.querySelector('.history-list')) updatePaneHistory(pane);
    });
}

function updatePaneHistory(pane) {
    const list = pane.querySelector('.history-list');
    if (!list) return;
    list.innerHTML = '';
    state.queryHistory.forEach(q => {
        const item = document.createElement('div');
        item.className = 'history-item';
        item.textContent = q.length > 80 ? q.substring(0, 80) + '...' : q;
        item.title = q;
        item.addEventListener('click', () => {
            const ed = pane.querySelector('.query-editor');
            if (ed) { ed.value = q; ed.focus(); }
        });
        list.appendChild(item);
    });
}

// ==================== EXPORT ====================
function exportCSV(tabId) {
    const tab = state.tabs.find(t => t.id === tabId);
    if (!tab || !tab.pageData.length) { showToast('No data to export', 'warning'); return; }
    let csv = tab.columns.map(c => '"' + c.replace(/"/g, '""') + '"').join(',') + '\\n';
    tab.pageData.forEach(row => {
        csv += tab.columns.map(c => {
            const v = row[c];
            return v == null ? '""' : '"' + String(v).replace(/"/g, '""') + '"';
        }).join(',') + '\\n';
    });
    dlFile(csv, tab.tableName + '.csv', 'text/csv');
    showToast('CSV exported', 'success');
}

function exportJSON(tabId) {
    const tab = state.tabs.find(t => t.id === tabId);
    if (!tab || !tab.pageData.length) { showToast('No data to export', 'warning'); return; }
    dlFile(JSON.stringify(tab.pageData, null, 2), tab.tableName + '.json', 'application/json');
    showToast('JSON exported', 'success');
}

function dlFile(content, name, mime) {
    const blob = new Blob([content], { type: mime });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url; a.download = name; a.click();
    URL.revokeObjectURL(url);
}

// ==================== ROW DETAIL ====================
function showRowDetail(tabId, idx) {
    const tab = state.tabs.find(t => t.id === tabId);
    if (!tab || !tab.pageData[idx]) return;
    const row = tab.pageData[idx];
    const content = document.getElementById('rowDetailContent');
    document.getElementById('rowDetailTitle').textContent = tab.tableName + ' - Row ' + ((tab.page - 1) * tab.pageSize + idx + 1);

    let html = '';
    tab.columns.forEach(col => {
        const v = row[col];
        const isNull = v === null || v === undefined;
        html += '<div class="row-detail-field">';
        html += '<div class="row-detail-label">' + escHtml(col) + '</div>';
        html += '<div class="row-detail-value' + (isNull ? ' null-val' : '') + '">' + (isNull ? 'NULL' : escHtml(String(v))) + '</div>';
        html += '</div>';
    });
    content.innerHTML = html;

    document.getElementById('rowDetailPanel').classList.add('show');
    document.getElementById('rowDetailBackdrop').classList.add('show');
}

function closeRowDetail() {
    document.getElementById('rowDetailPanel').classList.remove('show');
    document.getElementById('rowDetailBackdrop').classList.remove('show');
}

// ==================== COPY & CONTEXT MENU ====================
function copyToClip(text, label) {
    if (navigator.clipboard) {
        navigator.clipboard.writeText(text).then(() => showToast(label || 'Copied', 'success'));
    }
}

function copyCell(td) {
    const text = td.textContent;
    if (navigator.clipboard) {
        navigator.clipboard.writeText(text).then(() => {
            td.classList.add('cell-copied');
            setTimeout(() => td.classList.remove('cell-copied'), 500);
            showToast('Copied', 'success');
        });
    }
}

// Close any open context menu on click/scroll/resize
document.addEventListener('click', closeCtxMenu);
document.addEventListener('scroll', closeCtxMenu, true);
window.addEventListener('resize', closeCtxMenu);

function closeCtxMenu() {
    const old = document.querySelector('.ctx-menu');
    if (old) old.remove();
}

function showCtxMenu(x, y, items) {
    closeCtxMenu();
    const menu = document.createElement('div');
    menu.className = 'ctx-menu';
    items.forEach(item => {
        if (item === 'sep') {
            const sep = document.createElement('div');
            sep.className = 'ctx-sep';
            menu.appendChild(sep);
            return;
        }
        const el = document.createElement('div');
        el.className = 'ctx-item';
        el.innerHTML = '<span class="ctx-icon">' + (item.icon || '') + '</span>' + escHtml(item.label);
        el.addEventListener('click', e => { e.stopPropagation(); closeCtxMenu(); item.action(); });
        menu.appendChild(el);
    });
    // Position ensuring it stays in viewport
    menu.style.left = x + 'px';
    menu.style.top = y + 'px';
    document.body.appendChild(menu);
    const rect = menu.getBoundingClientRect();
    if (rect.right > window.innerWidth) menu.style.left = (x - rect.width) + 'px';
    if (rect.bottom > window.innerHeight) menu.style.top = (y - rect.height) + 'px';
}

// dataFn returns { columns: string[], data: object[] }
function attachTableContextMenu(tableEl, dataFn) {
    tableEl.addEventListener('contextmenu', e => {
        const info = dataFn();
        if (!info || !info.columns || info.columns.length === 0) return;
        const cols = info.columns;
        const rowsData = info.data || [];

        const th = e.target.closest('th[data-col]');
        const thAny = e.target.closest('th');
        const td = e.target.closest('td:not(.row-num-cell)');
        const tr = e.target.closest('tbody tr');
        const rowNumCell = e.target.closest('.row-num-cell');

        // For query result tables without data-col, get column from cell index
        let clickedCol = null;
        if (th && th.dataset.col) {
            clickedCol = th.dataset.col;
        } else if (thAny && !thAny.classList.contains('row-num-col')) {
            clickedCol = thAny.textContent.trim();
        }

        if (!clickedCol && !td && !rowNumCell && !thAny) return;
        e.preventDefault();

        const items = [];

        // ---- Right-clicked a column header ----
        if (clickedCol || (thAny && !thAny.classList.contains('row-num-col'))) {
            const colName = clickedCol || thAny.textContent.trim();
            items.push({
                icon: '\\u2398', label: 'Copy column name: ' + colName,
                action: () => copyToClip(colName, 'Column name copied')
            });
            items.push({
                icon: '\\u2630', label: 'Copy all column names',
                action: () => copyToClip(cols.join(', '), 'All column names copied')
            });
            items.push({
                icon: '\\u2637', label: 'Copy all column names (newline)',
                action: () => copyToClip(cols.join('\\n'), 'All column names copied')
            });
            if (rowsData.length > 0) {
                items.push('sep');
                items.push({
                    icon: '\\u25A5', label: 'Copy column data (' + rowsData.length + ' rows)',
                    action: () => {
                        const vals = rowsData.map(row => {
                            const v = row[colName];
                            return v == null ? 'NULL' : String(v);
                        });
                        copyToClip(vals.join('\\n'), 'Column data copied');
                    }
                });
            }
        }

        // ---- Right-clicked a data cell ----
        if (td) {
            items.push({
                icon: '\\u2398', label: 'Copy cell value',
                action: () => { copyCell(td); }
            });
        }

        // ---- Right-clicked a row ----
        if (tr && (td || rowNumCell)) {
            const rowIdx = Array.from(tr.parentNode.children).indexOf(tr);
            if (rowIdx >= 0 && rowsData[rowIdx]) {
                const rowData = rowsData[rowIdx];
                if (td) items.push('sep');
                items.push({
                    icon: '\\u007B', label: 'Copy row as JSON',
                    action: () => copyToClip(JSON.stringify(rowData, null, 2), 'Row copied as JSON')
                });
                items.push({
                    icon: '\\u2630', label: 'Copy row as CSV',
                    action: () => {
                        const vals = cols.map(c => {
                            const v = rowData[c];
                            return v == null ? '' : '"' + String(v).replace(/"/g, '""') + '"';
                        });
                        copyToClip(vals.join(','), 'Row copied as CSV');
                    }
                });
                items.push({
                    icon: '\\u2261', label: 'Copy row values (tab-separated)',
                    action: () => {
                        const vals = cols.map(c => {
                            const v = rowData[c];
                            return v == null ? 'NULL' : String(v);
                        });
                        copyToClip(vals.join('\\t'), 'Row copied');
                    }
                });
            }
        }

        if (items.length > 0) showCtxMenu(e.clientX, e.clientY, items);
    });

    // Also support dblclick to copy cell on query result tables
    if (!tableEl._dblClickAttached) {
        tableEl.addEventListener('dblclick', e => {
            const td = e.target.closest('td:not(.row-num-cell)');
            if (td) copyCell(td);
        });
        tableEl._dblClickAttached = true;
    }
}

// ==================== CONNECTION ====================
async function checkConnection() {
    try {
        const res = await fetch(API_BASE + '/databases');
        updateConnectionStatus(res.ok);
    } catch (e) { updateConnectionStatus(false); }
}

function updateConnectionStatus(ok) {
    const badge = document.getElementById('connectionStatus');
    const text = badge.querySelector('.status-text');
    if (ok) { badge.classList.remove('disconnected'); text.textContent = 'Connected'; }
    else { badge.classList.add('disconnected'); text.textContent = 'Disconnected'; }
}

// ==================== AUTOCOMPLETE ====================
const SQL_KEYWORDS = [
    'SELECT','FROM','WHERE','AND','OR','NOT','IN','LIKE','BETWEEN','IS','NULL',
    'INSERT','INTO','VALUES','UPDATE','SET','DELETE','CREATE','TABLE','ALTER',
    'DROP','INDEX','VIEW','TRIGGER','JOIN','LEFT','RIGHT','INNER','OUTER',
    'CROSS','ON','AS','ORDER','BY','ASC','DESC','GROUP','HAVING','LIMIT',
    'OFFSET','UNION','ALL','DISTINCT','EXISTS','CASE','WHEN','THEN','ELSE',
    'END','CAST','PRIMARY','KEY','FOREIGN','REFERENCES','UNIQUE','CHECK',
    'DEFAULT','AUTOINCREMENT','INTEGER','TEXT','REAL','BLOB','NUMERIC',
    'VARCHAR','BOOLEAN','DATE','DATETIME','TIMESTAMP','IF','REPLACE',
    'PRAGMA','BEGIN','COMMIT','ROLLBACK','TRANSACTION','EXPLAIN','VACUUM',
    'REINDEX','ATTACH','DETACH','RENAME','ADD','COLUMN','CONSTRAINT',
    'ABORT','CONFLICT','FAIL','IGNORE','COUNT','SUM','AVG','MIN','MAX',
    'TOTAL','LENGTH','UPPER','LOWER','TRIM','SUBSTR','TYPEOF','COALESCE',
    'NULLIF','IFNULL','INSTR','REPLACE','ROUND','ABS','RANDOM',
    'GROUP_CONCAT','HEX','QUOTE','ZEROBLOB','GLOB','PRINTF'
];

const SQL_FUNCTIONS = [
    'COUNT','SUM','AVG','MIN','MAX','TOTAL','LENGTH','UPPER','LOWER',
    'TRIM','LTRIM','RTRIM','SUBSTR','TYPEOF','COALESCE','NULLIF','IFNULL',
    'INSTR','REPLACE','ROUND','ABS','RANDOM','GROUP_CONCAT','HEX','QUOTE',
    'ZEROBLOB','GLOB','PRINTF','DATE','TIME','DATETIME','JULIANDAY',
    'STRFTIME','UNICODE','CHAR','LIKE','JSON','JSON_EXTRACT','JSON_ARRAY',
    'JSON_OBJECT','JSON_TYPE','JSON_VALID','JSON_GROUP_ARRAY','JSON_GROUP_OBJECT'
];

async function loadSchemaCache(dbId) {
    state.schemaCache = {};
    try {
        const res = await fetch(API_BASE + '/databases/' + dbId + '/tables');
        const data = await res.json();
        const tables = data.tables || [];
        for (const tbl of tables) {
            try {
                const sr = await fetch(API_BASE + '/databases/' + dbId + '/schema/' + tbl);
                const sd = await sr.json();
                state.schemaCache[tbl] = (sd.columns || []).map(c => c.name);
            } catch (e) {
                state.schemaCache[tbl] = [];
            }
        }
    } catch (e) { console.error('Schema cache error:', e); }
}

function getAcSuggestions(word) {
    if (!word || word.length < 1) return [];
    const w = word.toUpperCase();
    const results = [];

    // SQL keywords
    SQL_KEYWORDS.forEach(kw => {
        if (kw.startsWith(w) && kw !== w) results.push({ name: kw, type: 'kw', hint: 'keyword' });
    });

    // SQL functions (subset)
    SQL_FUNCTIONS.forEach(fn => {
        if (fn.startsWith(w) && fn !== w && !results.find(r => r.name === fn))
            results.push({ name: fn + '()', type: 'fn', hint: 'function' });
    });

    // Table names
    const wLower = word.toLowerCase();
    Object.keys(state.schemaCache).forEach(tbl => {
        if (tbl.toLowerCase().startsWith(wLower) && tbl.toLowerCase() !== wLower)
            results.push({ name: tbl, type: 'tbl', hint: 'table' });
    });

    // Column names (from all tables)
    const addedCols = new Set();
    Object.entries(state.schemaCache).forEach(([tbl, cols]) => {
        cols.forEach(col => {
            const cl = col.toLowerCase();
            if (cl.startsWith(wLower) && cl !== wLower && !addedCols.has(cl)) {
                addedCols.add(cl);
                results.push({ name: col, type: 'col', hint: tbl });
            }
        });
    });

    // Sort: exact prefix match first, then by type priority (table > column > keyword)
    const typePrio = { tbl: 0, col: 1, fn: 2, kw: 3 };
    results.sort((a, b) => (typePrio[a.type] || 9) - (typePrio[b.type] || 9));
    return results.slice(0, 15);
}

function attachAutocomplete(editor) {
    let dropdown = null;
    let items = [];
    let selIdx = -1;

    function close() {
        if (dropdown) { dropdown.remove(); dropdown = null; }
        items = []; selIdx = -1;
    }

    function insert(text) {
        const pos = editor.selectionStart;
        const val = editor.value;
        const wordStart = findWordStart(val, pos);
        // If suggestion ends with (), place cursor between parens
        const hasParen = text.endsWith('()');
        editor.value = val.substring(0, wordStart) + text + val.substring(pos);
        const newPos = wordStart + text.length - (hasParen ? 1 : 0);
        editor.selectionStart = editor.selectionEnd = newPos;
        editor.focus();
        close();
    }

    function findWordStart(text, pos) {
        let i = pos - 1;
        while (i >= 0 && /[a-zA-Z0-9_]/.test(text[i])) i--;
        return i + 1;
    }

    function getCurrentWord() {
        const pos = editor.selectionStart;
        const start = findWordStart(editor.value, pos);
        return editor.value.substring(start, pos);
    }

    function render(suggestions) {
        close();
        if (suggestions.length === 0) return;

        dropdown = document.createElement('div');
        dropdown.className = 'ac-dropdown';
        items = suggestions;
        selIdx = 0;

        suggestions.forEach((s, i) => {
            const el = document.createElement('div');
            el.className = 'ac-item' + (i === 0 ? ' selected' : '');
            el.innerHTML = '<span class="ac-badge ' + s.type + '">' + s.type + '</span>' +
                '<span class="ac-name">' + escHtml(s.name) + '</span>' +
                '<span class="ac-hint">' + escHtml(s.hint) + '</span>';
            el.addEventListener('mousedown', e => { e.preventDefault(); insert(s.name); });
            dropdown.appendChild(el);
        });

        // Position dropdown below cursor
        const rect = editor.getBoundingClientRect();
        const coords = getCaretCoords(editor);
        dropdown.style.left = Math.min(rect.left + coords.left, window.innerWidth - 260) + 'px';
        dropdown.style.top = (rect.top + coords.top + coords.height + 4) + 'px';
        document.body.appendChild(dropdown);
    }

    function updateSelection() {
        if (!dropdown) return;
        dropdown.querySelectorAll('.ac-item').forEach((el, i) => {
            el.classList.toggle('selected', i === selIdx);
        });
        // Scroll selected into view
        const sel = dropdown.querySelector('.selected');
        if (sel) sel.scrollIntoView({ block: 'nearest' });
    }

    editor.addEventListener('input', () => {
        const word = getCurrentWord();
        if (word.length >= 1) {
            const suggestions = getAcSuggestions(word);
            render(suggestions);
        } else {
            close();
        }
    });

    editor.addEventListener('keydown', e => {
        if (!dropdown) return;

        if (e.key === 'ArrowDown') {
            e.preventDefault();
            selIdx = Math.min(selIdx + 1, items.length - 1);
            updateSelection();
            return;
        }
        if (e.key === 'ArrowUp') {
            e.preventDefault();
            selIdx = Math.max(selIdx - 1, 0);
            updateSelection();
            return;
        }
        if (e.key === 'Enter' && !e.ctrlKey && !e.metaKey) {
            if (selIdx >= 0 && items[selIdx]) {
                e.preventDefault();
                insert(items[selIdx].name);
                return;
            }
        }
        if (e.key === 'Tab') {
            if (selIdx >= 0 && items[selIdx]) {
                e.preventDefault();
                insert(items[selIdx].name);
                return;
            }
        }
        if (e.key === 'Escape') {
            close();
            return;
        }
    });

    // Tab indent when autocomplete is NOT open
    editor.addEventListener('keydown', e => {
        if (e.key === 'Tab' && !dropdown) {
            e.preventDefault();
            const s = editor.selectionStart, end = editor.selectionEnd;
            editor.value = editor.value.substring(0, s) + '    ' + editor.value.substring(end);
            editor.selectionStart = editor.selectionEnd = s + 4;
        }
    });

    editor.addEventListener('blur', () => { setTimeout(close, 150); });
    editor.addEventListener('scroll', close);
}

// Approximate caret pixel coordinates in a textarea
function getCaretCoords(textarea) {
    const div = document.createElement('div');
    const style = getComputedStyle(textarea);
    const props = [
        'fontFamily','fontSize','fontWeight','letterSpacing','lineHeight',
        'padding','paddingTop','paddingRight','paddingBottom','paddingLeft',
        'border','borderWidth','boxSizing','whiteSpace','wordWrap','overflowWrap','tabSize'
    ];
    props.forEach(p => { div.style[p] = style[p]; });
    div.style.position = 'absolute';
    div.style.visibility = 'hidden';
    div.style.whiteSpace = 'pre-wrap';
    div.style.wordWrap = 'break-word';
    div.style.width = textarea.offsetWidth + 'px';
    div.style.height = 'auto';
    div.style.overflow = 'hidden';

    const text = textarea.value.substring(0, textarea.selectionStart);
    div.textContent = text;

    const span = document.createElement('span');
    span.textContent = textarea.value.substring(textarea.selectionStart) || '.';
    div.appendChild(span);

    document.body.appendChild(div);

    const spanRect = span.offsetTop;
    const spanLeft = span.offsetLeft;
    const lineH = parseInt(style.lineHeight) || parseInt(style.fontSize) * 1.5;

    document.body.removeChild(div);

    return {
        top: spanRect - textarea.scrollTop,
        left: spanLeft - textarea.scrollLeft,
        height: lineH
    };
}

// ==================== UTILITIES ====================
function escHtml(t) { const d = document.createElement('div'); d.textContent = t; return d.innerHTML; }
function escAttr(t) { return t.replace(/&/g,'&amp;').replace(/"/g,'&quot;').replace(/</g,'&lt;').replace(/>/g,'&gt;'); }
function fmtNum(n) { if (n >= 1000000) return (n/1000000).toFixed(1)+'M'; if (n >= 1000) return (n/1000).toFixed(1)+'K'; return String(n); }
''';

  /// Find network IP address from network interfaces
  Future<String?> _findNetworkIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );

      String? preferredIp;
      String? fallbackIp;

      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (addr.isLoopback) continue;

          final address = addr.address;

          if (address.startsWith('192.168.')) {
            preferredIp = address;
            break;
          } else if (address.startsWith('10.')) {
            if (preferredIp == null || !preferredIp.startsWith('192.168.')) {
              preferredIp = address;
            }
          } else if (address.startsWith('172.')) {
            final secondOctet = int.tryParse(address.split('.')[1]);
            if (secondOctet != null && secondOctet >= 16 && secondOctet <= 31) {
              if (preferredIp == null ||
                  (!preferredIp.startsWith('192.168.') &&
                      !preferredIp.startsWith('10.'))) {
                preferredIp = address;
              }
            }
          } else if (fallbackIp == null) {
            fallbackIp = address;
          }
        }
        if (preferredIp != null && preferredIp.startsWith('192.168.')) {
          break;
        }
      }

      return preferredIp ?? fallbackIp;
    } catch (e) {
      return null;
    }
  }

  /// Update server port (restart server)
  Future<void> updatePort(int newPort) async {
    if (_port == newPort) return;

    _port = newPort;
    if (_server != null) {
      await _server!.close(force: true);
      _server = null;
      await _startServer();
    }
  }

  /// Get current port
  int get port => _port;

  /// Get local IP address
  String? get localIp => _localIp;

  /// Stop the server
  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _databases.clear();
  }
}

/// Information about a registered database
class DatabaseInfo {
  final String id;
  final Database database;
  final String path;
  final String name;

  DatabaseInfo({
    required this.id,
    required this.database,
    required this.path,
    required this.name,
  });
}
