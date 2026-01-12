/// SQLite Dev Workbench - A development tool for inspecting SQLite databases
///
/// This package provides a web-based workbench accessible during development.
/// Add this package to your `dev_dependencies` in pubspec.yaml.
///
/// Usage:
/// ```dart
/// import 'package:sqflite_dev/sqflite_dev.dart';
///
/// // Method 1: Manual enable
/// final db = await openDatabase('my_db.db');
/// db.enableWorkbench();
///
/// // Method 2: Using WorkbenchHelper (similar to sqflite_orm)
/// final db = await openDatabase('my_db.db', version: 1);
/// WorkbenchHelper.autoEnable(db, webDebug: true, webDebugPort: 8080);
/// ```
library sqflite_dev;

export 'src/database_wrapper.dart';
export 'src/workbench_server.dart';
export 'src/workbench_helper.dart';
