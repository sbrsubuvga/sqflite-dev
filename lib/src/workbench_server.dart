import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
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
    if (!kDebugMode) {
      print('sqflite_dev: Workbench is only available in debug mode');
      return;
    }

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
      print('sqflite_dev: Database "$dbId" registered. Workbench already running.');
    }
  }

  /// Get all registered databases
  Map<String, DatabaseInfo> get databases => Map.unmodifiable(_databases);

  /// Get a database by ID
  DatabaseInfo? getDatabase(String dbId) => _databases[dbId];

  /// Start the web server
  Future<void> _startServer() async {
    if (!kDebugMode) {
      print('sqflite_dev: Workbench is only available in debug mode');
      return;
    }

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
      if (e is SocketException && e.message.contains('Address already in use')) {
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
      if (requestPath == '' || requestPath == '/' || requestPath == '/index.html') {
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
      // If server is bound to any address, try to find a local network IP
      if (serverAddress.rawAddress.every((b) => b == 0)) {
        // Server is bound to 0.0.0.0, find actual network IP
        return await _findNetworkIp();
      } else if (!serverAddress.isLoopback) {
        return serverAddress.address;
      }
    } catch (e) {
      // Ignore errors
    }
    return null;
  }

  /// Get the embedded web UI HTML (similar to sqflite_orm approach)
  String _getWebUIHtml() {
    // Embed all HTML, CSS, and JS in one string to avoid file system issues
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
    <div class="app-container">
        <!-- Header -->
        <header class="header">
            <div class="header-left">
                <h1>SQLite Workbench</h1>
                <span class="connection-status" id="connectionStatus">●</span>
            </div>
            <div class="header-right">
                <select id="databaseSelector" class="database-selector">
                    <option value="">Select Database...</option>
                </select>
                <div class="database-info" id="databaseInfo"></div>
            </div>
        </header>

        <div class="main-content">
            <!-- Left Sidebar -->
            <aside class="sidebar">
                <div class="sidebar-header">
                    <h2>Tables</h2>
                    <button id="refreshTables" class="btn-icon" title="Refresh">↻</button>
                </div>
                <div id="tablesList" class="tables-list">
                    <p class="empty-state">Select a database to view tables</p>
                </div>
            </aside>

            <!-- Main Content Area -->
            <main class="content-area">
                <div id="noSelection" class="empty-state-large">
                    <p>Select a table to view details</p>
                </div>

                <div id="tableContent" class="table-content" style="display: none;">
                    <!-- Tab Bar -->
                    <div class="tab-bar">
                        <button class="tab-btn active" data-tab="info">Table Info</button>
                        <button class="tab-btn" data-tab="data">Table Data</button>
                        <button class="tab-btn" data-tab="query">Query Browser</button>
                    </div>

                    <!-- Tab Content -->
                    <div class="tab-content">
                        <!-- Table Info Tab -->
                        <div id="tab-info" class="tab-pane active">
                            <div class="info-section">
                                <h3>Schema</h3>
                                <div id="schemaContent"></div>
                            </div>
                            <div class="info-section">
                                <h3>Indexes</h3>
                                <div id="indexesContent"></div>
                            </div>
                            <div class="info-section">
                                <h3>CREATE TABLE Statement</h3>
                                <pre id="createTableStatement"></pre>
                            </div>
                        </div>

                        <!-- Table Data Tab -->
                        <div id="tab-data" class="tab-pane">
                            <div class="data-controls">
                                <div class="pagination-controls">
                                    <label>Page Size:
                                        <select id="pageSize">
                                            <option value="10">10</option>
                                            <option value="25" selected>25</option>
                                            <option value="50">50</option>
                                            <option value="100">100</option>
                                        </select>
                                    </label>
                                    <div class="page-info" id="pageInfo"></div>
                                    <div class="page-nav">
                                        <button id="firstPage" class="btn-small">First</button>
                                        <button id="prevPage" class="btn-small">Prev</button>
                                        <button id="nextPage" class="btn-small">Next</button>
                                        <button id="lastPage" class="btn-small">Last</button>
                                    </div>
                                </div>
                                <button id="exportData" class="btn-primary">Export CSV</button>
                            </div>
                            <div class="table-container">
                                <table id="dataTable" class="data-table">
                                    <thead id="dataTableHead"></thead>
                                    <tbody id="dataTableBody"></tbody>
                                </table>
                            </div>
                        </div>

                        <!-- Query Browser Tab -->
                        <div id="tab-query" class="tab-pane">
                            <div class="query-editor-container">
                                <textarea id="queryEditor" class="query-editor" placeholder="Enter SQL query..."></textarea>
                                <div class="query-controls">
                                    <button id="executeQuery" class="btn-primary">Execute (Ctrl+Enter)</button>
                                    <span id="queryTime" class="query-time"></span>
                                </div>
                            </div>
                            <div id="queryHistory" class="query-history">
                                <h4>Query History</h4>
                                <div id="historyList"></div>
                            </div>
                            <div id="queryResults" class="query-results">
                                <div class="table-container">
                                    <table id="queryTable" class="data-table">
                                        <thead id="queryTableHead"></thead>
                                        <tbody id="queryTableBody"></tbody>
                                    </table>
                                </div>
                            </div>
                            <div id="queryError" class="error-message"></div>
                        </div>
                    </div>
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

  // Embedded CSS (from web/css/styles.css)
  static const String _webUICSS = '''
* {
    margin: 0;
    padding: 0;
    box-sizing: border-box;
}

:root {
    --primary-color: #007bff;
    --secondary-color: #6c757d;
    --success-color: #28a745;
    --danger-color: #dc3545;
    --warning-color: #ffc107;
    --bg-color: #f8f9fa;
    --card-bg: #ffffff;
    --border-color: #dee2e6;
    --text-color: #212529;
    --text-muted: #6c757d;
    --sidebar-width: 250px;
}

body {
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
    background-color: var(--bg-color);
    color: var(--text-color);
    line-height: 1.6;
}

.app-container {
    display: flex;
    flex-direction: column;
    height: 100vh;
    overflow: hidden;
}

/* Header */
.header {
    background: var(--card-bg);
    border-bottom: 1px solid var(--border-color);
    padding: 1rem 1.5rem;
    display: flex;
    justify-content: space-between;
    align-items: center;
    box-shadow: 0 2px 4px rgba(0,0,0,0.1);
}

.header-left {
    display: flex;
    align-items: center;
    gap: 1rem;
}

.header-left h1 {
    font-size: 1.5rem;
    font-weight: 600;
}

.connection-status {
    font-size: 0.75rem;
    color: var(--success-color);
}

.connection-status.disconnected {
    color: var(--danger-color);
}

.header-right {
    display: flex;
    align-items: center;
    gap: 1rem;
}

.database-selector {
    padding: 0.5rem 1rem;
    border: 1px solid var(--border-color);
    border-radius: 4px;
    font-size: 0.9rem;
    min-width: 200px;
}

.database-info {
    font-size: 0.85rem;
    color: var(--text-muted);
}

/* Main Content */
.main-content {
    display: flex;
    flex: 1;
    overflow: hidden;
}

/* Sidebar */
.sidebar {
    width: var(--sidebar-width);
    background: var(--card-bg);
    border-right: 1px solid var(--border-color);
    display: flex;
    flex-direction: column;
    overflow-y: auto;
}

.sidebar-header {
    padding: 1rem;
    border-bottom: 1px solid var(--border-color);
    display: flex;
    justify-content: space-between;
    align-items: center;
}

.sidebar-header h2 {
    font-size: 1.1rem;
    font-weight: 600;
}

.btn-icon {
    background: none;
    border: none;
    cursor: pointer;
    font-size: 1.2rem;
    padding: 0.25rem 0.5rem;
    color: var(--text-color);
}

.btn-icon:hover {
    color: var(--primary-color);
}

.tables-list {
    flex: 1;
    overflow-y: auto;
    padding: 0.5rem;
}

.database-section {
    margin-bottom: 1rem;
}

.database-section-header {
    padding: 0.75rem;
    background: var(--bg-color);
    font-weight: 600;
    cursor: pointer;
    display: flex;
    justify-content: space-between;
    align-items: center;
    border-radius: 4px;
}

.database-section-header:hover {
    background: #e9ecef;
}

.database-section-header.active {
    background: var(--primary-color);
    color: white;
}

.table-item {
    padding: 0.5rem 0.75rem 0.5rem 2rem;
    cursor: pointer;
    border-radius: 4px;
    margin: 0.25rem 0;
}

.table-item:hover {
    background: var(--bg-color);
}

.table-item.active {
    background: var(--primary-color);
    color: white;
}

.empty-state {
    padding: 1rem;
    text-align: center;
    color: var(--text-muted);
    font-style: italic;
}

/* Content Area */
.content-area {
    flex: 1;
    display: flex;
    flex-direction: column;
    overflow: hidden;
}

.empty-state-large {
    display: flex;
    align-items: center;
    justify-content: center;
    height: 100%;
    font-size: 1.2rem;
    color: var(--text-muted);
}

.table-content {
    display: flex;
    flex-direction: column;
    height: 100%;
    overflow: hidden;
}

/* Tab Bar */
.tab-bar {
    display: flex;
    border-bottom: 2px solid var(--border-color);
    background: var(--card-bg);
}

.tab-btn {
    padding: 0.75rem 1.5rem;
    background: none;
    border: none;
    border-bottom: 2px solid transparent;
    cursor: pointer;
    font-size: 0.9rem;
    font-weight: 500;
    color: var(--text-muted);
    margin-bottom: -2px;
}

.tab-btn:hover {
    color: var(--text-color);
    background: var(--bg-color);
}

.tab-btn.active {
    color: var(--primary-color);
    border-bottom-color: var(--primary-color);
}

/* Tab Content */
.tab-content {
    flex: 1;
    overflow-y: auto;
    padding: 1.5rem;
}

.tab-pane {
    display: none;
}

.tab-pane.active {
    display: block;
}

/* Info Tab */
.info-section {
    margin-bottom: 2rem;
}

.info-section h3 {
    margin-bottom: 1rem;
    color: var(--text-color);
    font-size: 1.1rem;
}

.schema-table, .indexes-table {
    width: 100%;
    border-collapse: collapse;
    background: var(--card-bg);
    border: 1px solid var(--border-color);
}

.schema-table th, .indexes-table th {
    background: var(--bg-color);
    padding: 0.75rem;
    text-align: left;
    font-weight: 600;
    border-bottom: 2px solid var(--border-color);
}

.schema-table td, .indexes-table td {
    padding: 0.75rem;
    border-bottom: 1px solid var(--border-color);
}

.schema-table tr:hover, .indexes-table tr:hover {
    background: var(--bg-color);
}

pre {
    background: var(--bg-color);
    padding: 1rem;
    border-radius: 4px;
    overflow-x: auto;
    font-size: 0.9rem;
    border: 1px solid var(--border-color);
}

/* Data Tab */
.data-controls {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 1rem;
    padding: 1rem;
    background: var(--card-bg);
    border-radius: 4px;
    border: 1px solid var(--border-color);
}

.pagination-controls {
    display: flex;
    align-items: center;
    gap: 1rem;
}

.page-info {
    color: var(--text-muted);
    font-size: 0.9rem;
}

.page-nav {
    display: flex;
    gap: 0.5rem;
}

.btn-small, .btn-primary {
    padding: 0.5rem 1rem;
    border: 1px solid var(--border-color);
    border-radius: 4px;
    cursor: pointer;
    font-size: 0.9rem;
    background: var(--card-bg);
    color: var(--text-color);
}

.btn-small:hover, .btn-primary:hover {
    background: var(--bg-color);
}

.btn-primary {
    background: var(--primary-color);
    color: white;
    border-color: var(--primary-color);
}

.btn-primary:hover {
    background: #0056b3;
}

.table-container {
    overflow-x: auto;
    border: 1px solid var(--border-color);
    border-radius: 4px;
    background: var(--card-bg);
}

.data-table {
    width: 100%;
    border-collapse: collapse;
}

.data-table th {
    background: var(--bg-color);
    padding: 0.75rem;
    text-align: left;
    font-weight: 600;
    border-bottom: 2px solid var(--border-color);
    cursor: pointer;
    user-select: none;
}

.data-table th:hover {
    background: #e9ecef;
}

.data-table td {
    padding: 0.75rem;
    border-bottom: 1px solid var(--border-color);
}

.data-table tr:hover {
    background: var(--bg-color);
}

/* Query Tab */
.query-editor-container {
    margin-bottom: 1.5rem;
}

.query-editor {
    width: 100%;
    min-height: 200px;
    padding: 1rem;
    border: 1px solid var(--border-color);
    border-radius: 4px;
    font-family: 'Courier New', monospace;
    font-size: 0.9rem;
    resize: vertical;
}

.query-controls {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-top: 0.5rem;
}

.query-time {
    color: var(--text-muted);
    font-size: 0.85rem;
}

.query-history {
    margin-bottom: 1.5rem;
    padding: 1rem;
    background: var(--card-bg);
    border: 1px solid var(--border-color);
    border-radius: 4px;
}

.query-history h4 {
    margin-bottom: 0.5rem;
    font-size: 1rem;
}

.history-item {
    padding: 0.5rem;
    margin: 0.25rem 0;
    background: var(--bg-color);
    border-radius: 4px;
    cursor: pointer;
    font-size: 0.85rem;
    font-family: 'Courier New', monospace;
}

.history-item:hover {
    background: #e9ecef;
}

.query-results {
    margin-top: 1rem;
}

.error-message {
    padding: 1rem;
    background: #f8d7da;
    color: #721c24;
    border-radius: 4px;
    margin-top: 1rem;
    display: none;
}

.error-message.show {
    display: block;
}

/* Responsive */
@media (max-width: 768px) {
    .main-content {
        flex-direction: column;
    }
    
    .sidebar {
        width: 100%;
        max-height: 200px;
    }
    
    .header {
        flex-direction: column;
        gap: 1rem;
    }
}
''';

  // Embedded JavaScript (from web/js/app.js)
  static const String _webUIJS = '''
// Application state
let state = {
    databases: [],
    currentDbId: null,
    currentTable: null,
    currentTab: 'info',
    currentPage: 1,
    pageSize: 25,
    queryHistory: []
};

// API base URL
const API_BASE = '/api';

// Initialize app
document.addEventListener('DOMContentLoaded', () => {
    initializeApp();
});

async function initializeApp() {
    await loadDatabases();
    setupEventListeners();
    checkConnection();
    setInterval(checkConnection, 5000); // Check every 5 seconds
}

// Event Listeners
function setupEventListeners() {
    // Database selector
    document.getElementById('databaseSelector').addEventListener('change', (e) => {
        const dbId = e.target.value;
        if (dbId) {
            selectDatabase(dbId);
        }
    });

    // Refresh tables
    document.getElementById('refreshTables').addEventListener('click', () => {
        if (state.currentDbId) {
            loadTables(state.currentDbId);
        }
    });

    // Tab buttons
    document.querySelectorAll('.tab-btn').forEach(btn => {
        btn.addEventListener('click', (e) => {
            const tab = e.target.dataset.tab;
            switchTab(tab);
        });
    });

    // Pagination
    document.getElementById('pageSize').addEventListener('change', (e) => {
        state.pageSize = parseInt(e.target.value);
        state.currentPage = 1;
        if (state.currentDbId && state.currentTable) {
            loadTableData(state.currentDbId, state.currentTable);
        }
    });

    document.getElementById('firstPage').addEventListener('click', () => {
        state.currentPage = 1;
        loadTableData(state.currentDbId, state.currentTable);
    });

    document.getElementById('prevPage').addEventListener('click', () => {
        if (state.currentPage > 1) {
            state.currentPage--;
            loadTableData(state.currentDbId, state.currentTable);
        }
    });

    document.getElementById('nextPage').addEventListener('click', () => {
        state.currentPage++;
        loadTableData(state.currentDbId, state.currentTable);
    });

    document.getElementById('lastPage').addEventListener('click', () => {
        // Will be set after loading data
        loadTableData(state.currentDbId, state.currentTable);
    });

    // Query execution
    document.getElementById('executeQuery').addEventListener('click', executeQuery);
    
    // Keyboard shortcut for query execution
    document.getElementById('queryEditor').addEventListener('keydown', (e) => {
        if (e.ctrlKey && e.key === 'Enter') {
            executeQuery();
        }
    });

    // Export data
    document.getElementById('exportData').addEventListener('click', exportTableData);
}

// Load databases
async function loadDatabases() {
    try {
        const response = await fetch(\`\${API_BASE}/databases\`);
        const data = await response.json();
        state.databases = data.databases || [];
        
        const selector = document.getElementById('databaseSelector');
        selector.innerHTML = '<option value="">Select Database...</option>';
        
        state.databases.forEach(db => {
            const option = document.createElement('option');
            option.value = db.id;
            option.textContent = \`\${db.name} (\${db.id})\`;
            selector.appendChild(option);
        });

        if (state.databases.length > 0 && !state.currentDbId) {
            selectDatabase(state.databases[0].id);
        }
    } catch (error) {
        console.error('Failed to load databases:', error);
        updateConnectionStatus(false);
    }
}

// Select database
async function selectDatabase(dbId) {
    state.currentDbId = dbId;
    state.currentTable = null;
    state.currentPage = 1;
    
    const db = state.databases.find(d => d.id === dbId);
    if (db) {
        document.getElementById('databaseSelector').value = dbId;
        document.getElementById('databaseInfo').textContent = db.path;
    }

    await loadDatabaseInfo(dbId);
    await loadTables(dbId);
    hideTableContent();
}

// Load database info
async function loadDatabaseInfo(dbId) {
    try {
        const response = await fetch(\`\${API_BASE}/databases/\${dbId}/info\`);
        const data = await response.json();
        // Could display more info here
    } catch (error) {
        console.error('Failed to load database info:', error);
    }
}

// Load tables
async function loadTables(dbId) {
    try {
        const response = await fetch(\`\${API_BASE}/databases/\${dbId}/tables\`);
        const data = await response.json();
        const tables = data.tables || [];
        
        const tablesList = document.getElementById('tablesList');
        tablesList.innerHTML = '';
        
        if (tables.length === 0) {
            tablesList.innerHTML = '<p class="empty-state">No tables found</p>';
            return;
        }

        const db = state.databases.find(d => d.id === dbId);
        const section = document.createElement('div');
        section.className = 'database-section';
        
        const header = document.createElement('div');
        header.className = 'database-section-header active';
        header.textContent = db ? db.name : dbId;
        section.appendChild(header);

        tables.forEach(tableName => {
            const item = document.createElement('div');
            item.className = 'table-item';
            item.textContent = tableName;
            item.addEventListener('click', () => {
                selectTable(tableName);
                // Update active state
                document.querySelectorAll('.table-item').forEach(i => i.classList.remove('active'));
                item.classList.add('active');
            });
            section.appendChild(item);
        });

        tablesList.appendChild(section);
    } catch (error) {
        console.error('Failed to load tables:', error);
        document.getElementById('tablesList').innerHTML = 
            '<p class="empty-state">Failed to load tables</p>';
    }
}

// Select table
function selectTable(tableName) {
    state.currentTable = tableName;
    state.currentPage = 1;
    showTableContent();
    
    // Load data based on current tab
    if (state.currentTab === 'info') {
        loadTableInfo(state.currentDbId, tableName);
    } else if (state.currentTab === 'data') {
        loadTableData(state.currentDbId, tableName);
    }
}

// Switch tab
function switchTab(tab) {
    state.currentTab = tab;
    
    // Update tab buttons
    document.querySelectorAll('.tab-btn').forEach(btn => {
        btn.classList.remove('active');
        if (btn.dataset.tab === tab) {
            btn.classList.add('active');
        }
    });

    // Update tab panes
    document.querySelectorAll('.tab-pane').forEach(pane => {
        pane.classList.remove('active');
    });
    document.getElementById(\`tab-\${tab}\`).classList.add('active');

    // Load data if table is selected
    if (state.currentDbId && state.currentTable) {
        if (tab === 'info') {
            loadTableInfo(state.currentDbId, state.currentTable);
        } else if (tab === 'data') {
            loadTableData(state.currentDbId, state.currentTable);
        }
    }
}

// Load table info
async function loadTableInfo(dbId, tableName) {
    try {
        const response = await fetch(\`\${API_BASE}/databases/\${dbId}/schema/\${tableName}\`);
        const data = await response.json();
        
        // Display schema
        const schemaContent = document.getElementById('schemaContent');
        if (data.columns && data.columns.length > 0) {
            let html = '<table class="schema-table"><thead><tr>';
            html += '<th>Name</th><th>Type</th><th>Not Null</th><th>Default</th><th>Primary Key</th>';
            html += '</tr></thead><tbody>';
            
            data.columns.forEach(col => {
                html += '<tr>';
                html += \`<td>\${escapeHtml(col.name || '')}</td>\`;
                html += \`<td>\${escapeHtml(col.type || '')}</td>\`;
                html += \`<td>\${col.notnull === 1 ? 'Yes' : 'No'}</td>\`;
                html += \`<td>\${escapeHtml(String(col.dflt_value || ''))}</td>\`;
                html += \`<td>\${col.pk === 1 ? 'Yes' : 'No'}</td>\`;
                html += '</tr>';
            });
            
            html += '</tbody></table>';
            schemaContent.innerHTML = html;
        } else {
            schemaContent.innerHTML = '<p>No schema information available</p>';
        }

        // Display indexes
        const indexesContent = document.getElementById('indexesContent');
        if (data.indexes && data.indexes.length > 0) {
            let html = '<table class="indexes-table"><thead><tr><th>Name</th><th>SQL</th></tr></thead><tbody>';
            data.indexes.forEach(idx => {
                html += '<tr>';
                html += \`<td>\${escapeHtml(idx.name || '')}</td>\`;
                html += \`<td><code>\${escapeHtml(idx.sql || '')}</code></td>\`;
                html += '</tr>';
            });
            html += '</tbody></table>';
            indexesContent.innerHTML = html;
        } else {
            indexesContent.innerHTML = '<p>No indexes</p>';
        }

        // Display CREATE TABLE statement
        const createTable = document.getElementById('createTableStatement');
        createTable.textContent = data.createTable || 'Not available';
    } catch (error) {
        console.error('Failed to load table info:', error);
    }
}

// Load table data
async function loadTableData(dbId, tableName) {
    try {
        const response = await fetch(
            \`\${API_BASE}/databases/\${dbId}/table/\${tableName}?page=\${state.currentPage}&limit=\${state.pageSize}\`
        );
        const data = await response.json();
        
        if (data.data && data.data.length > 0) {
            // Get column names from first row
            const columns = Object.keys(data.data[0]);
            
            // Build table header
            const thead = document.getElementById('dataTableHead');
            thead.innerHTML = '<tr>' + columns.map(col => 
                \`<th>\${escapeHtml(col)}</th>\`
            ).join('') + '</tr>';
            
            // Build table body
            const tbody = document.getElementById('dataTableBody');
            tbody.innerHTML = data.data.map(row => {
                return '<tr>' + columns.map(col => {
                    const value = row[col];
                    return \`<td>\${escapeHtml(value != null ? String(value) : 'NULL')}</td>\`;
                }).join('') + '</tr>';
            }).join('');
            
            // Update pagination info
            const pagination = data.pagination;
            const totalPages = pagination.totalPages || 1;
            state.currentPage = pagination.page;
            
            document.getElementById('pageInfo').textContent = 
                \`Page \${pagination.page} of \${totalPages} (\${pagination.total} rows)\`;
            
            // Update last page button
            document.getElementById('lastPage').onclick = () => {
                state.currentPage = totalPages;
                loadTableData(dbId, tableName);
            };
            
            // Enable/disable navigation buttons
            document.getElementById('firstPage').disabled = state.currentPage === 1;
            document.getElementById('prevPage').disabled = state.currentPage === 1;
            document.getElementById('nextPage').disabled = state.currentPage >= totalPages;
            document.getElementById('lastPage').disabled = state.currentPage >= totalPages;
        } else {
            document.getElementById('dataTableHead').innerHTML = '';
            document.getElementById('dataTableBody').innerHTML = 
                '<tr><td colspan="100%" style="text-align: center; padding: 2rem;">No data</td></tr>';
        }
    } catch (error) {
        console.error('Failed to load table data:', error);
    }
}

// Execute query
async function executeQuery() {
    if (!state.currentDbId) {
        alert('Please select a database first');
        return;
    }

    const query = document.getElementById('queryEditor').value.trim();
    if (!query) {
        alert('Please enter a query');
        return;
    }

    // Add to history
    if (!state.queryHistory.includes(query)) {
        state.queryHistory.unshift(query);
        if (state.queryHistory.length > 10) {
            state.queryHistory.pop();
        }
        updateQueryHistory();
    }

    try {
        const startTime = Date.now();
        const response = await fetch(\`\${API_BASE}/databases/\${state.currentDbId}/query\`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify({ query }),
        });

        const data = await response.json();
        const elapsed = Date.now() - startTime;

        if (data.error) {
            document.getElementById('queryError').textContent = data.error;
            document.getElementById('queryError').classList.add('show');
            document.getElementById('queryResults').style.display = 'none';
        } else {
            document.getElementById('queryError').classList.remove('show');
            document.getElementById('queryTime').textContent = 
                \`Executed in \${data.executionTime || elapsed}ms (\${data.rowCount || 0} rows)\`;
            
            // Display results
            if (data.data && data.data.length > 0) {
                const columns = Object.keys(data.data[0]);
                const thead = document.getElementById('queryTableHead');
                thead.innerHTML = '<tr>' + columns.map(col => 
                    \`<th>\${escapeHtml(col)}</th>\`
                ).join('') + '</tr>';
                
                const tbody = document.getElementById('queryTableBody');
                tbody.innerHTML = data.data.map(row => {
                    return '<tr>' + columns.map(col => {
                        const value = row[col];
                        return \`<td>\${escapeHtml(value != null ? String(value) : 'NULL')}</td>\`;
                    }).join('') + '</tr>';
                }).join('');
                
                document.getElementById('queryResults').style.display = 'block';
            } else {
                document.getElementById('queryResults').style.display = 'none';
            }
        }
    } catch (error) {
        document.getElementById('queryError').textContent = error.toString();
        document.getElementById('queryError').classList.add('show');
        document.getElementById('queryResults').style.display = 'none';
    }
}

// Update query history
function updateQueryHistory() {
    const historyList = document.getElementById('historyList');
    historyList.innerHTML = '';
    
    state.queryHistory.forEach(query => {
        const item = document.createElement('div');
        item.className = 'history-item';
        item.textContent = query.substring(0, 100) + (query.length > 100 ? '...' : '');
        item.title = query;
        item.addEventListener('click', () => {
            document.getElementById('queryEditor').value = query;
        });
        historyList.appendChild(item);
    });
}

// Export table data to CSV
function exportTableData() {
    if (!state.currentDbId || !state.currentTable) {
        alert('Please select a table first');
        return;
    }

    // Simple CSV export - in production, you might want to fetch all data
    const table = document.getElementById('dataTable');
    const rows = table.querySelectorAll('tr');
    
    let csv = '';
    rows.forEach(row => {
        const cells = row.querySelectorAll('th, td');
        csv += Array.from(cells).map(cell => 
            '"' + cell.textContent.replace(/"/g, '""') + '"'
        ).join(',') + '\\n';
    });

    const blob = new Blob([csv], { type: 'text/csv' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = \`\${state.currentTable}_\${Date.now()}.csv\`;
    a.click();
    URL.revokeObjectURL(url);
}

// Show/hide table content
function showTableContent() {
    document.getElementById('noSelection').style.display = 'none';
    document.getElementById('tableContent').style.display = 'flex';
}

function hideTableContent() {
    document.getElementById('noSelection').style.display = 'flex';
    document.getElementById('tableContent').style.display = 'none';
}

// Check connection
async function checkConnection() {
    try {
        const response = await fetch(\`\${API_BASE}/databases\`);
        updateConnectionStatus(response.ok);
    } catch (error) {
        updateConnectionStatus(false);
    }
}

function updateConnectionStatus(connected) {
    const status = document.getElementById('connectionStatus');
    if (connected) {
        status.textContent = '●';
        status.classList.remove('disconnected');
        status.title = 'Connected';
    } else {
        status.textContent = '●';
        status.classList.add('disconnected');
        status.title = 'Disconnected';
    }
}

// Utility function
function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
}
''';

  /// Find network IP address from network interfaces
  Future<String?> _findNetworkIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );

      // Priority order: 192.168.x.x, 10.x.x.x, 172.16-31.x.x, then any non-loopback
      String? preferredIp;
      String? fallbackIp;

      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (addr.isLoopback) continue;

          final address = addr.address;

          // Prefer private network ranges
          if (address.startsWith('192.168.')) {
            preferredIp = address;
            break; // Found preferred IP, use it
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
            // Any other non-loopback IPv4 address
            fallbackIp = address;
          }
        }
        if (preferredIp != null && preferredIp.startsWith('192.168.')) {
          break; // Found best match, stop searching
        }
      }

      return preferredIp ?? fallbackIp;
    } catch (e) {
      // Ignore errors - IP detection is not critical
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

