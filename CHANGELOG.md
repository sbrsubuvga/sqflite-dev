# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.3.0-dev] - unreleased

### Added — In-App Workbench Overlay
- **`webDebugInfoOverlay` parameter** on `enableWorkbench()` / `WorkbenchHelper`: pass `webDebugInfoOverlay: true` and a draggable notch automatically appears at the edge of the running app, showing the Local and Network URLs (tap-to-copy) plus registered database count. No widget wrapping required — the overlay inserts itself programmatically into the app's `Overlay`. In pure Dart contexts the flag is silently ignored.
- **`SqfliteDevOverlay` widget** (via `package:sqflite_dev/sqflite_dev_flutter.dart`): an alternative manual widget-wrapper for users who need explicit control over placement. Most users should prefer `webDebugInfoOverlay: true` instead.
- `WorkbenchServer.isRunning` getter so consumers (and the overlay) can tell whether the HTTP server has been started.

## [2.2.0] - 2026-04-10

First release of the Schema Basics phase. Adds a Database Info panel, a visual Create Table wizard, and Truncate Table — all routed through a new SQL confirmation dialog so users can review (and copy) every generated statement before it runs.

### Added — Schema Management
- **Database Info panel**: Info icon in the header opens a slide-over showing name, path, SQLite version, `user_version`, `schema_version`, page size/count, file size, table count, encoding, and pragmas
- **Editable `user_version`**: Pencil icon next to user_version lets you bump the schema version through the SQL confirm dialog
- **Foreign Keys pragma toggle**: ON/OFF pill in the Database Info panel
- **Journal Mode selector**: Dropdown for DELETE/TRUNCATE/PERSIST/MEMORY/WAL/OFF in the Database Info panel
- **Truncate Table**: New option in the sidebar right-click context menu, showing the current row count in the warning and running `DELETE FROM table` + `DELETE FROM sqlite_sequence` through the SQL confirm dialog
- **Create Table wizard**: New `+` button in the sidebar header opens a visual form with live SQL preview. Supports column name, type, PRIMARY KEY, AUTOINCREMENT, NOT NULL, UNIQUE, DEFAULT, CHECK, and single-column foreign keys with ON DELETE/UPDATE actions

### Added — Editor & Query UX
- **SQL syntax highlighting for table & column names**: Table names highlighted in blue, column names in green — matching autocomplete badge colors
- **SQL confirm dialog for cell edits**: Editing a cell now shows the generated UPDATE SQL in a modal with Copy-to-Clipboard and Apply/Cancel actions, so users see exactly what will run before it executes
- **Refresh button in table toolbar**: "↻ Refresh" button next to Data/Structure tabs so Flutter app changes can be picked up without reopening the tab
- **Sidebar table right-click menu**: Refresh, Truncate, and Copy to Clipboard options (Table Name, CREATE, SELECT, INSERT, UPDATE, DELETE, DROP statements) with full column lists
- **DML query execution**: INSERT, UPDATE, DELETE, CREATE, DROP, and ALTER statements now execute correctly with affected row count feedback

### Fixed
- Query text is now visible in the editor — fixed the transparent-textarea overlay so the syntax-highlighted backdrop shows through
- Autocomplete insertion now immediately updates syntax highlighting
- `api_handlers.dart` `/query` endpoint correctly uses `execute()` for non-SELECT statements so INSERT/UPDATE/DELETE/CREATE/DROP/ALTER actually run

## [2.0.0] - 2026-04-03

### Added
- **MySQL Workbench-style tab system**: Tables and queries open as independent tabs in a unified tab bar
- **Multiple tables open simultaneously**: Each table gets its own tab with independent state
- **Dark mode**: Toggle with Ctrl+D, persisted to localStorage
- **Sidebar table search**: Filter tables by name with Ctrl+K
- **Table row count badges**: Row counts shown next to each table in the sidebar
- **Click-to-sort columns**: Click column headers to sort ascending/descending
- **NULL value styling**: NULL values displayed in italic gray, distinct from empty strings
- **Toast notifications**: Elegant toasts replace browser alerts
- **Loading spinner**: Visual feedback during data operations
- **Destructive query protection**: Confirmation dialog for DROP, DELETE without WHERE, TRUNCATE
- **Keyboard shortcuts**: Ctrl+Enter (run query), Ctrl+T (new query tab), Ctrl+W (close tab), ? (help)
- **SQL autocomplete**: Table names, column names, SQL keywords, and functions with dropdown
- **Right-click context menu**: Copy column names, row data (JSON/CSV/TSV), cell values, column data
- **Double-click cell to copy**: Quick-copy any cell value
- **Row detail panel**: Click row number to view all fields in a slide-over panel
- **Export JSON**: New JSON export alongside CSV
- **Run selected text**: Select part of a query to execute only that portion
- **Tab key indentation**: 4-space indent in query editor
- **Resizable sidebar**: Drag handle to resize
- **Breadcrumb navigation**: Shows current database and table context
- **Data/Structure toggle per tab**: Each table tab has its own Data/Structure sub-view
- **Welcome screen**: Feature cards and keyboard shortcut hints for new users
- **Zebra-striped rows**: Alternating row colors for readability
- **Auto-refresh on DML**: Table data and list refresh after INSERT/UPDATE/DELETE/CREATE/DROP

### Changed
- Complete UI redesign with modern color scheme and improved typography
- Tabs are now dynamic (open/close) instead of fixed Data/Structure/Query tabs
- Connection status badge shows text ("Connected"/"Disconnected") alongside indicator

## [1.0.8] - 2026-01-12

### Added
- Enhanced example with multiple tables (categories, todos, users, notes)
- Added foreign key relationships in example database
- Added database migration example (version 1 to 2)

### Changed
- Example now demonstrates workbench capabilities with complex multi-table schema
- Improved example database structure with relationships

## [1.0.7] - 2026-01-12

### Changed
- Updated example to use `kReleaseMode` for automatic workbench disabling in release builds
- Improved example code to follow best practices

## [1.0.6] - 2026-01-12

### Added
- Added `webDebug` parameter to `enableWorkbench()` extension method for enable/disable control
- Added `webDebugName` and `webDebugPort` parameters to `enableWorkbench()` for API consistency

### Changed
- `enableWorkbench()` now uses consistent parameter names (`webDebug`, `webDebugName`, `webDebugPort`)
- Updated example to use direct `enableWorkbench()` method instead of helper class
- Both `enableWorkbench()` and `WorkbenchHelper.autoEnable()` now have identical functionality

## [1.0.5] - 2026-01-12

### Added
- Added complete dartdoc documentation for `DatabaseInfo` class and all its properties
- Improved package description for better pub.dev scoring

### Changed
- Shortened package description to meet pub.dev requirements
- Cleaned up unnecessary files (removed unused web directory files)

### Fixed
- Fixed pub.dev scoring issues (documentation coverage, example detection)
- Improved package structure for publishing

## [1.0.4] - 2026-01-12

### Changed
- **BREAKING**: Removed Flutter dependency - package now works with both Flutter and pure Dart
- Removed automatic debug mode checking - users now control workbench via `webDebug` parameter
- Package no longer requires Flutter SDK, works in pure Dart environments

### Fixed
- Fixed `dart:ui` import error when used in pure Dart projects (e.g., with sqflite_orm)
- Workbench now respects user's `webDebug` setting instead of automatically disabling in release mode

## [1.0.3] - 2025-01-12

### Changed
- Consolidated example code into single file (main.dart) for better visibility on pub.dev
- Example now includes both UI and database helper code in one file

## [1.0.1] - 2025-01-12

### Changed
- Updated homepage URL in pubspec.yaml
- Removed unused `shelf_static` dependency
- Improved example code documentation

### Fixed
- Package structure optimized for pub.dev publishing

## [1.0.0] - 2024-01-XX

### Added
- Initial release of sqflite_dev
- Web-based SQLite workbench accessible during development
- Support for multiple databases
- Database selector in UI header
- Table list sidebar grouped by database
- Table Info tab with schema, indexes, and CREATE statement
- Table Data tab with pagination (10, 25, 50, 100 rows per page)
- Query Browser tab with SQL editor and query history
- Export to CSV functionality
- Real-time connection status indicator
- Cross-platform support (mobile with sqflite, desktop with sqflite_common_ffi)
- Configurable port (default: 8080)
- Network access from any device on the same network
- Debug mode only - automatically disabled in production builds
- Developer dependency - should be in dev_dependencies

### Features
- View all registered databases
- Switch between databases seamlessly
- Browse tables with full pagination support
- View complete table schema and metadata
- Run custom SQL queries with syntax highlighting
- View query execution results
- Export data to CSV
- Connection status monitoring
- Responsive design for mobile/tablet

### Platform Support
- iOS/Android/macOS via sqflite package
- Linux/Windows/macOS/Web via sqflite_common_ffi package

