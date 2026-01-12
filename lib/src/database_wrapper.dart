
import 'package:flutter/foundation.dart';
import 'package:sqflite_common/sqlite_api.dart';
import 'package:path/path.dart' as path;
import 'workbench_server.dart';

/// Extension on Database to enable workbench
extension DatabaseWorkbench on Database {
  /// Enable the SQLite workbench for this database
  /// 
  /// [name] - Optional custom name for the database in the workbench UI
  /// [port] - Port number for the web server (default: 8080)
  /// 
  /// Example:
  /// ```dart
  /// final db = await openDatabase('my_db.db');
  /// db.enableWorkbench(name: 'MainDB', port: 8080);
  /// ```
  void enableWorkbench({String? name, int? port}) {
    if (!kDebugMode) {
      print('sqflite_dev: Workbench is only available in debug mode');
      return;
    }

    // Get database path
    final dbPath = this.path;
    if (dbPath.isEmpty) {
      print('sqflite_dev: Cannot enable workbench - database path is unknown');
      return;
    }

    // Generate unique ID from path or use custom name
    final dbId = name != null 
        ? _sanitizeId(name)
        : _generateIdFromPath(dbPath);

    // Update port if specified
    if (port != null) {
      WorkbenchServer.instance.updatePort(port);
    }

    // Register database with workbench server
    WorkbenchServer.instance.registerDatabase(
      dbId: dbId,
      database: this,
      dbPath: dbPath,
      name: name ?? path.basename(dbPath),
    );
  }

  /// Generate a unique ID from database path
  String _generateIdFromPath(String dbPath) {
    // Use basename and hash of full path
    final basename = path.basenameWithoutExtension(dbPath);
    final hash = dbPath.hashCode.abs();
    return '${_sanitizeId(basename)}_$hash';
  }

  /// Sanitize string to be used as ID
  String _sanitizeId(String input) {
    return input
        .replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .toLowerCase();
  }
}

