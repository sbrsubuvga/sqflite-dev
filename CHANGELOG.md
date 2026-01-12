# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

