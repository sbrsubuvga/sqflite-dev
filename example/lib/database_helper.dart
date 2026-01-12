import 'dart:io';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_dev/sqflite_dev.dart';

/// Database helper that works on both mobile and desktop platforms
class DatabaseHelper {
  static Database? _database;
  static const String _databaseName = 'todos.db';
  static const int _databaseVersion = 1;

  /// Initialize database - handles platform differences
  Future<void> initDatabase() async {
    // Initialize FFI for desktop platforms
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    // Get database path
    String path;
    if (Platform.isAndroid || Platform.isIOS) {
      // Mobile: use getDatabasesPath()
      final databasesPath = await getDatabasesPath();
      path = join(databasesPath, _databaseName);
    } else {
      // Desktop: use application documents directory
      final documentsDirectory = await getApplicationDocumentsDirectory();
      path = join(documentsDirectory.path, _databaseName);
    }

    // Open database
    _database = await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );

    // Enable workbench automatically (similar to sqflite_orm's webDebug option)
    WorkbenchHelper.autoEnable(
      _database!,
      webDebug: true,
      webDebugPort: 8080,
      webDebugName: 'TodosDB',
    );

    print('Database initialized at: $path');
  }

  /// Create database tables
  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE todos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        completed INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');

    // Insert some sample data
    await db.insert('todos', {
      'title': 'Welcome to SQLite Dev Workbench!',
      'completed': 0,
      'created_at': DateTime.now().toIso8601String(),
    });
    
    await db.insert('todos', {
      'title': 'Check out the workbench at http://localhost:8080',
      'completed': 0,
      'created_at': DateTime.now().toIso8601String(),
    });
    
    await db.insert('todos', {
      'title': 'Try running queries in the Query Browser tab',
      'completed': 1,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// Handle database upgrades
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Handle migrations here if needed
  }

  /// Get database instance
  Database get database {
    if (_database == null) {
      throw Exception('Database not initialized. Call initDatabase() first.');
    }
    return _database!;
  }

  /// Get all todos
  Future<List<Map<String, dynamic>>> getAllTodos() async {
    return await database.query(
      'todos',
      orderBy: 'created_at DESC',
    );
  }

  /// Get a single todo by ID
  Future<Map<String, dynamic>?> getTodo(int id) async {
    final results = await database.query(
      'todos',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }

  /// Insert a new todo
  Future<int> insertTodo(Map<String, dynamic> todo) async {
    return await database.insert('todos', todo);
  }

  /// Update a todo
  Future<int> updateTodo(int id, Map<String, dynamic> updates) async {
    return await database.update(
      'todos',
      updates,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Delete a todo
  Future<int> deleteTodo(int id) async {
    return await database.delete(
      'todos',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Close database
  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}

