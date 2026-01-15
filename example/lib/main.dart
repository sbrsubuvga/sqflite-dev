import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_dev/sqflite_dev.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize database
  final dbHelper = DatabaseHelper();
  await dbHelper.initDatabase();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SQLite Dev Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  List<Map<String, dynamic>> _todos = [];
  final TextEditingController _titleController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadTodos();
  }

  Future<void> _loadTodos() async {
    setState(() => _isLoading = true);
    final todos = await _dbHelper.getAllTodos();
    setState(() {
      _todos = todos;
      _isLoading = false;
    });
  }

  Future<void> _addTodo() async {
    if (_titleController.text.trim().isEmpty) return;

    await _dbHelper.insertTodo({
      'title': _titleController.text.trim(),
      'completed': 0,
      'created_at': DateTime.now().toIso8601String(),
    });

    _titleController.clear();
    _loadTodos();
  }

  Future<void> _toggleTodo(int id, bool completed) async {
    await _dbHelper.updateTodo(id, {'completed': completed ? 1 : 0});
    _loadTodos();
  }

  Future<void> _deleteTodo(int id) async {
    await _dbHelper.deleteTodo(id);
    _loadTodos();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('SQLite Dev Example'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadTodos,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          // Add Todo Section
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _titleController,
                    decoration: const InputDecoration(
                      labelText: 'New Todo',
                      hintText: 'Enter todo title',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _addTodo(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _addTodo,
                  child: const Text('Add'),
                ),
              ],
            ),
          ),

          // Info Banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline,
                        color: Colors.blue.shade700, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Workbench Active',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Open http://localhost:8080 in your browser to access the SQLite workbench.',
                  style: TextStyle(fontSize: 12, color: Colors.blue.shade900),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Todos List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _todos.isEmpty
                    ? const Center(
                        child: Text(
                          'No todos yet. Add one above!',
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _todos.length,
                        itemBuilder: (context, index) {
                          final todo = _todos[index];
                          final isCompleted = todo['completed'] == 1;

                          return Card(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 4,
                            ),
                            child: ListTile(
                              leading: Checkbox(
                                value: isCompleted,
                                onChanged: (value) => _toggleTodo(
                                  todo['id'] as int,
                                  value ?? false,
                                ),
                              ),
                              title: Text(
                                todo['title'] as String,
                                style: TextStyle(
                                  decoration: isCompleted
                                      ? TextDecoration.lineThrough
                                      : null,
                                  color: isCompleted ? Colors.grey : null,
                                ),
                              ),
                              subtitle: Text(
                                'Created: ${todo['created_at']}',
                                style: const TextStyle(fontSize: 12),
                              ),
                              trailing: IconButton(
                                icon:
                                    const Icon(Icons.delete, color: Colors.red),
                                onPressed: () => _deleteTodo(todo['id'] as int),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }
}

/// Database helper that works on both mobile and desktop platforms
class DatabaseHelper {
  static Database? _database;
  static const String _databaseName = 'todos.db';
  static const int _databaseVersion = 2;

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

    // Enable workbench
    _database?.enableWorkbench(
      webDebug: !kReleaseMode,
      webDebugPort: 8080,
      webDebugName: 'TodosDB',
    );
  }

  /// Create database tables
  Future<void> _onCreate(Database db, int version) async {
    // Create categories table
    await db.execute('''
      CREATE TABLE categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        color TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    // Create todos table with category reference
    await db.execute('''
      CREATE TABLE todos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        completed INTEGER NOT NULL DEFAULT 0,
        category_id INTEGER,
        priority INTEGER DEFAULT 0,
        created_at TEXT NOT NULL,
        FOREIGN KEY (category_id) REFERENCES categories(id)
      )
    ''');

    // Create users table
    await db.execute('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT NOT NULL UNIQUE,
        email TEXT NOT NULL,
        role TEXT DEFAULT 'user',
        created_at TEXT NOT NULL
      )
    ''');

    // Create notes table
    await db.execute('''
      CREATE TABLE notes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        content TEXT,
        user_id INTEGER,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (user_id) REFERENCES users(id)
      )
    ''');

    // Insert sample categories
    final now = DateTime.now().toIso8601String();
    final category1 = await db.insert('categories', {
      'name': 'Work',
      'color': '#FF5722',
      'created_at': now,
    });
    final category2 = await db.insert('categories', {
      'name': 'Personal',
      'color': '#2196F3',
      'created_at': now,
    });
    final category3 = await db.insert('categories', {
      'name': 'Shopping',
      'color': '#4CAF50',
      'created_at': now,
    });

    // Insert sample users
    final user1 = await db.insert('users', {
      'username': 'admin',
      'email': 'admin@example.com',
      'role': 'admin',
      'created_at': now,
    });
    final user2 = await db.insert('users', {
      'username': 'john_doe',
      'email': 'john@example.com',
      'role': 'user',
      'created_at': now,
    });

    // Insert sample todos
    await db.insert('todos', {
      'title': 'Welcome to SQLite Dev Workbench!',
      'completed': 0,
      'category_id': category1,
      'priority': 1,
      'created_at': now,
    });

    await db.insert('todos', {
      'title': 'Check out the workbench at http://localhost:8080',
      'completed': 0,
      'category_id': category2,
      'priority': 2,
      'created_at': now,
    });

    await db.insert('todos', {
      'title': 'Try running queries in the Query Browser tab',
      'completed': 1,
      'category_id': category3,
      'priority': 0,
      'created_at': now,
    });

    // Insert sample notes
    await db.insert('notes', {
      'title': 'Project Ideas',
      'content': 'List of project ideas for the next quarter',
      'user_id': user1,
      'created_at': now,
      'updated_at': now,
    });

    await db.insert('notes', {
      'title': 'Meeting Notes',
      'content': 'Important points from today\'s meeting',
      'user_id': user2,
      'created_at': now,
      'updated_at': now,
    });
  }

  /// Handle database upgrades
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Migration from version 1 to 2: Add new tables
      // Create categories table
      await db.execute('''
        CREATE TABLE IF NOT EXISTS categories (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL UNIQUE,
          color TEXT,
          created_at TEXT NOT NULL
        )
      ''');

      // Add category_id and priority columns to todos
      try {
        await db.execute('ALTER TABLE todos ADD COLUMN category_id INTEGER');
        await db.execute('ALTER TABLE todos ADD COLUMN priority INTEGER DEFAULT 0');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS todos_new (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            completed INTEGER NOT NULL DEFAULT 0,
            category_id INTEGER,
            priority INTEGER DEFAULT 0,
            created_at TEXT NOT NULL,
            FOREIGN KEY (category_id) REFERENCES categories(id)
          )
        ''');
        await db.execute('''
          INSERT INTO todos_new (id, title, completed, created_at)
          SELECT id, title, completed, created_at FROM todos
        ''');
        await db.execute('DROP TABLE todos');
        await db.execute('ALTER TABLE todos_new RENAME TO todos');
      } catch (e) {
        // Columns might already exist, ignore
      }

      // Create users table
      await db.execute('''
        CREATE TABLE IF NOT EXISTS users (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          username TEXT NOT NULL UNIQUE,
          email TEXT NOT NULL,
          role TEXT DEFAULT 'user',
          created_at TEXT NOT NULL
        )
      ''');

      // Create notes table
      await db.execute('''
        CREATE TABLE IF NOT EXISTS notes (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT NOT NULL,
          content TEXT,
          user_id INTEGER,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          FOREIGN KEY (user_id) REFERENCES users(id)
        )
      ''');

      // Insert sample data only if tables are empty
      final now = DateTime.now().toIso8601String();
      
      // Check if categories table is empty before inserting
      final categoryCount = await db.rawQuery('SELECT COUNT(*) as count FROM categories');
      if ((categoryCount.first['count'] as int) == 0) {
        await db.insert('categories', {
          'name': 'Work',
          'color': '#FF5722',
          'created_at': now,
        });
        await db.insert('categories', {
          'name': 'Personal',
          'color': '#2196F3',
          'created_at': now,
        });
        await db.insert('categories', {
          'name': 'Shopping',
          'color': '#4CAF50',
          'created_at': now,
        });
      }

      // Check if users table is empty before inserting
      final userCount = await db.rawQuery('SELECT COUNT(*) as count FROM users');
      if ((userCount.first['count'] as int) == 0) {
        final user1 = await db.insert('users', {
          'username': 'admin',
          'email': 'admin@example.com',
          'role': 'admin',
          'created_at': now,
        });
        final user2 = await db.insert('users', {
          'username': 'john_doe',
          'email': 'john@example.com',
          'role': 'user',
          'created_at': now,
        });

        // Insert notes only if users were inserted
        await db.insert('notes', {
          'title': 'Project Ideas',
          'content': 'List of project ideas for the next quarter',
          'user_id': user1,
          'created_at': now,
          'updated_at': now,
        });

        await db.insert('notes', {
          'title': 'Meeting Notes',
          'content': 'Important points from today\'s meeting',
          'user_id': user2,
          'created_at': now,
          'updated_at': now,
        });
      }
    }
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
