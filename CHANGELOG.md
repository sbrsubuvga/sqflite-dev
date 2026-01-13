# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

