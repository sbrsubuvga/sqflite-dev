# SQLite Dev Example

This is an example Flutter application demonstrating how to use the `sqflite_dev` package. The app works on all platforms: iOS, Android, Linux, Windows, and macOS.

## Features

- ✅ Cross-platform support (iOS, Android, Linux, Windows, macOS)
- ✅ Simple Todo app with SQLite database
- ✅ SQLite Dev Workbench integration
- ✅ Automatic platform detection (uses `sqflite` for mobile, `sqflite_common_ffi` for desktop)

## Setup

1. Navigate to the example directory:
   ```bash
   cd example
   ```

2. Install dependencies:
   ```bash
   flutter pub get
   ```

3. Run the app:
   ```bash
   # For mobile (iOS/Android)
   flutter run
   
   # For desktop (Linux/Windows/macOS)
   flutter run -d linux
   flutter run -d windows
   flutter run -d macos
   ```

## Using the Workbench

Once the app is running in **debug mode**, the SQLite workbench will automatically start:

1. Look for this message in your console:
   ```
   ═══════════════════════════════════════════════════════════
   sqflite_dev: Workbench server started!
     Local:   http://localhost:8080
     Network: http://192.168.x.x:8080
   ═══════════════════════════════════════════════════════════
   ```

2. Open your browser and navigate to `http://localhost:8080`

3. You'll see:
   - **Database Selector**: Select "TodosDB"
   - **Tables Sidebar**: Click on "todos" table
   - **Table Info Tab**: View schema, indexes, and CREATE statement
   - **Table Data Tab**: Browse todos with pagination
   - **Query Browser Tab**: Run SQL queries like:
     ```sql
     SELECT * FROM todos WHERE completed = 0;
     UPDATE todos SET completed = 1 WHERE id = 1;
     ```

## App Features

- Add new todos
- Mark todos as completed
- Delete todos
- View all todos in a list
- All data is stored in SQLite database

## Database Structure

The app creates a `todos` table with the following schema:

```sql
CREATE TABLE todos (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title TEXT NOT NULL,
  completed INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL
)
```

## Platform-Specific Notes

### Mobile (iOS/Android)
- Uses `sqflite` package
- Database stored in app's database directory
- Workbench accessible from development PC on same network

### Desktop (Linux/Windows/macOS)
- Uses `sqflite_common_ffi` package
- Database stored in application documents directory
- Workbench accessible from localhost or network

## Troubleshooting

- **Workbench not starting**: Make sure you're running in debug mode (not release)
- **Can't access workbench**: Check the console for the correct URL and port
- **Database errors**: Make sure all dependencies are installed (`flutter pub get`)

