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
        const response = await fetch(`${API_BASE}/databases`);
        const data = await response.json();
        state.databases = data.databases || [];
        
        const selector = document.getElementById('databaseSelector');
        selector.innerHTML = '<option value="">Select Database...</option>';
        
        state.databases.forEach(db => {
            const option = document.createElement('option');
            option.value = db.id;
            option.textContent = `${db.name} (${db.id})`;
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
        const response = await fetch(`${API_BASE}/databases/${dbId}/info`);
        const data = await response.json();
        // Could display more info here
    } catch (error) {
        console.error('Failed to load database info:', error);
    }
}

// Load tables
async function loadTables(dbId) {
    try {
        const response = await fetch(`${API_BASE}/databases/${dbId}/tables`);
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
    document.getElementById(`tab-${tab}`).classList.add('active');

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
        const response = await fetch(`${API_BASE}/databases/${dbId}/schema/${tableName}`);
        const data = await response.json();
        
        // Display schema
        const schemaContent = document.getElementById('schemaContent');
        if (data.columns && data.columns.length > 0) {
            let html = '<table class="schema-table"><thead><tr>';
            html += '<th>Name</th><th>Type</th><th>Not Null</th><th>Default</th><th>Primary Key</th>';
            html += '</tr></thead><tbody>';
            
            data.columns.forEach(col => {
                html += '<tr>';
                html += `<td>${escapeHtml(col.name || '')}</td>`;
                html += `<td>${escapeHtml(col.type || '')}</td>`;
                html += `<td>${col.notnull === 1 ? 'Yes' : 'No'}</td>`;
                html += `<td>${escapeHtml(String(col.dflt_value || ''))}</td>`;
                html += `<td>${col.pk === 1 ? 'Yes' : 'No'}</td>`;
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
                html += `<td>${escapeHtml(idx.name || '')}</td>`;
                html += `<td><code>${escapeHtml(idx.sql || '')}</code></td>`;
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
            `${API_BASE}/databases/${dbId}/table/${tableName}?page=${state.currentPage}&limit=${state.pageSize}`
        );
        const data = await response.json();
        
        if (data.data && data.data.length > 0) {
            // Get column names from first row
            const columns = Object.keys(data.data[0]);
            
            // Build table header
            const thead = document.getElementById('dataTableHead');
            thead.innerHTML = '<tr>' + columns.map(col => 
                `<th>${escapeHtml(col)}</th>`
            ).join('') + '</tr>';
            
            // Build table body
            const tbody = document.getElementById('dataTableBody');
            tbody.innerHTML = data.data.map(row => {
                return '<tr>' + columns.map(col => {
                    const value = row[col];
                    return `<td>${escapeHtml(value != null ? String(value) : 'NULL')}</td>`;
                }).join('') + '</tr>';
            }).join('');
            
            // Update pagination info
            const pagination = data.pagination;
            const totalPages = pagination.totalPages || 1;
            state.currentPage = pagination.page;
            
            document.getElementById('pageInfo').textContent = 
                `Page ${pagination.page} of ${totalPages} (${pagination.total} rows)`;
            
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
        const response = await fetch(`${API_BASE}/databases/${state.currentDbId}/query`, {
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
                `Executed in ${data.executionTime || elapsed}ms (${data.rowCount || 0} rows)`;
            
            // Display results
            if (data.data && data.data.length > 0) {
                const columns = Object.keys(data.data[0]);
                const thead = document.getElementById('queryTableHead');
                thead.innerHTML = '<tr>' + columns.map(col => 
                    `<th>${escapeHtml(col)}</th>`
                ).join('') + '</tr>';
                
                const tbody = document.getElementById('queryTableBody');
                tbody.innerHTML = data.data.map(row => {
                    return '<tr>' + columns.map(col => {
                        const value = row[col];
                        return `<td>${escapeHtml(value != null ? String(value) : 'NULL')}</td>`;
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
        ).join(',') + '\n';
    });

    const blob = new Blob([csv], { type: 'text/csv' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `${state.currentTable}_${Date.now()}.csv`;
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
        const response = await fetch(`${API_BASE}/databases`);
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

