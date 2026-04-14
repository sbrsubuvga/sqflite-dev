import 'package:sqflite_common/sqlite_api.dart';
import 'package:path/path.dart' as path;
import 'workbench_server.dart';

import '_overlay_inserter_stub.dart'
    if (dart.library.ui) '_overlay_inserter.dart' as overlay;

/// Extension on Database to enable workbench
extension DatabaseWorkbench on Database {
  /// Enable the SQLite workbench for this database
  ///
  /// [webDebug] - Enable workbench (default: true)
  /// [webDebugName] - Optional custom name for the database in the workbench UI
  /// [webDebugPort] - Port number for the web server (default: 8080)
  /// [webDebugInfoOverlay] - Show an in-app notch with the server URLs (Flutter only)
  ///
  /// Example:
  /// ```dart
  /// final db = await openDatabase('my_db.db');
  /// db.enableWorkbench(
  ///   webDebug: true,
  ///   webDebugName: 'MainDB',
  ///   webDebugPort: 8080,
  ///   webDebugInfoOverlay: true,
  /// );
  /// ```
  void enableWorkbench({
    bool webDebug = true,
    String? webDebugName,
    int? webDebugPort,
    bool webDebugInfoOverlay = false,
  }) {
    if (!webDebug) {
      return;
    }

    // Get database path
    final dbPath = this.path;
    if (dbPath.isEmpty) {
      print('sqflite_dev: Cannot enable workbench - database path is unknown');
      return;
    }

    // Generate unique ID from path or use custom name
    final dbId = webDebugName != null
        ? _sanitizeId(webDebugName)
        : _generateIdFromPath(dbPath);

    // Update port if specified
    if (webDebugPort != null) {
      WorkbenchServer.instance.updatePort(webDebugPort);
    }

    // Register database with workbench server
    WorkbenchServer.instance.registerDatabase(
      dbId: dbId,
      database: this,
      dbPath: dbPath,
      name: webDebugName ?? path.basename(dbPath),
    );

    // Show in-app overlay notch (Flutter only, no-op in pure Dart)
    if (webDebugInfoOverlay) {
      overlay.insertWorkbenchOverlay();
    }
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
