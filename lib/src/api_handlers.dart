import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'workbench_server.dart';

/// Create API handler for workbench endpoints
Handler createApiHandler(WorkbenchServer server) {
  return (Request request) async {
    final path = request.url.path;
    final method = request.method;

    // List all databases
    if (method == 'GET' && path == 'api/databases') {
      final databases = server.databases.values
          .map((db) => {
                'id': db.id,
                'name': db.name,
                'path': db.path,
              })
          .toList();

      return Response.ok(
        jsonEncode({'databases': databases}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    // Get database info
    final dbInfoMatch =
        RegExp(r'^api/databases/([^/]+)/info$').firstMatch(path);
    if (method == 'GET' && dbInfoMatch != null) {
      final dbId = dbInfoMatch.group(1)!;
      final dbInfo = server.getDatabase(dbId);
      if (dbInfo == null) {
        return Response.notFound(jsonEncode({'error': 'Database not found'}));
      }

      int fileSize = 0;
      try {
        fileSize = await File(dbInfo.path).length();
      } catch (_) {}

      Future<Object?> pragma(String name) async {
        try {
          final r = await dbInfo.database.rawQuery('PRAGMA $name');
          if (r.isEmpty) return null;
          return r.first.values.first;
        } catch (_) {
          return null;
        }
      }

      String? sqliteVersion;
      try {
        final r =
            await dbInfo.database.rawQuery('SELECT sqlite_version() as v');
        sqliteVersion = r.first['v'] as String?;
      } catch (_) {}

      int tableCount = 0;
      try {
        final r = await dbInfo.database.rawQuery(
          "SELECT COUNT(*) as c FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
        );
        tableCount = (r.first['c'] as int?) ?? 0;
      } catch (_) {}

      return Response.ok(
        jsonEncode({
          'id': dbInfo.id,
          'name': dbInfo.name,
          'path': dbInfo.path,
          'size': fileSize,
          'tableCount': tableCount,
          'sqliteVersion': sqliteVersion,
          'userVersion': await pragma('user_version'),
          'schemaVersion': await pragma('schema_version'),
          'pageSize': await pragma('page_size'),
          'pageCount': await pragma('page_count'),
          'encoding': await pragma('encoding'),
          'journalMode': await pragma('journal_mode'),
          'foreignKeys': await pragma('foreign_keys'),
          'autoVacuum': await pragma('auto_vacuum'),
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }

    // List tables for a database
    final tablesMatch =
        RegExp(r'^api/databases/([^/]+)/tables$').firstMatch(path);
    if (method == 'GET' && tablesMatch != null) {
      final dbId = tablesMatch.group(1)!;
      final dbInfo = server.getDatabase(dbId);
      if (dbInfo == null) {
        return Response.notFound(jsonEncode({'error': 'Database not found'}));
      }

      try {
        final tables = await dbInfo.database.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
        );

        return Response.ok(
          jsonEncode({
            'tables': tables.map((t) => t['name'] as String).toList(),
          }),
          headers: {'Content-Type': 'application/json'},
        );
      } catch (e) {
        return Response.internalServerError(
          body: jsonEncode({'error': e.toString()}),
          headers: {'Content-Type': 'application/json'},
        );
      }
    }

    // Get table count
    final countMatch =
        RegExp(r'^api/databases/([^/]+)/table/([^/]+)/count$').firstMatch(path);
    if (method == 'GET' && countMatch != null) {
      final dbId = countMatch.group(1)!;
      final tableName = countMatch.group(2)!;
      final dbInfo = server.getDatabase(dbId);
      if (dbInfo == null) {
        return Response.notFound(jsonEncode({'error': 'Database not found'}));
      }

      try {
        final result = await dbInfo.database.rawQuery(
          'SELECT COUNT(*) as count FROM "$tableName"',
        );
        final count = result.first['count'] as int;

        return Response.ok(
          jsonEncode({'count': count}),
          headers: {'Content-Type': 'application/json'},
        );
      } catch (e) {
        return Response.internalServerError(
          body: jsonEncode({'error': e.toString()}),
          headers: {'Content-Type': 'application/json'},
        );
      }
    }

    // Get table data with pagination
    final tableDataMatch =
        RegExp(r'^api/databases/([^/]+)/table/([^/]+)$').firstMatch(path);
    if (method == 'GET' && tableDataMatch != null) {
      final dbId = tableDataMatch.group(1)!;
      final tableName = tableDataMatch.group(2)!;
      final dbInfo = server.getDatabase(dbId);
      if (dbInfo == null) {
        return Response.notFound(jsonEncode({'error': 'Database not found'}));
      }

      try {
        final page =
            int.tryParse(request.url.queryParameters['page'] ?? '1') ?? 1;
        final limit =
            int.tryParse(request.url.queryParameters['limit'] ?? '50') ?? 50;
        final offset = (page - 1) * limit;

        // Get total count
        final countResult = await dbInfo.database.rawQuery(
          'SELECT COUNT(*) as count FROM "$tableName"',
        );
        final totalCount = countResult.first['count'] as int;

        // Get paginated data
        final data = await dbInfo.database.rawQuery(
          'SELECT * FROM "$tableName" LIMIT $limit OFFSET $offset',
        );

        return Response.ok(
          jsonEncode({
            'data': data,
            'pagination': {
              'page': page,
              'limit': limit,
              'total': totalCount,
              'totalPages': (totalCount / limit).ceil(),
            },
          }),
          headers: {'Content-Type': 'application/json'},
        );
      } catch (e) {
        return Response.internalServerError(
          body: jsonEncode({'error': e.toString()}),
          headers: {'Content-Type': 'application/json'},
        );
      }
    }

    // Get table schema
    final schemaMatch =
        RegExp(r'^api/databases/([^/]+)/schema/([^/]+)$').firstMatch(path);
    if (method == 'GET' && schemaMatch != null) {
      final dbId = schemaMatch.group(1)!;
      final tableName = schemaMatch.group(2)!;
      final dbInfo = server.getDatabase(dbId);
      if (dbInfo == null) {
        return Response.notFound(jsonEncode({'error': 'Database not found'}));
      }

      try {
        // Get table info
        final tableInfo =
            await dbInfo.database.rawQuery('PRAGMA table_info("$tableName")');

        // Foreign keys for this table
        final fkList = await dbInfo.database
            .rawQuery('PRAGMA foreign_key_list("$tableName")');

        // Get CREATE TABLE statement
        final createTable = await dbInfo.database.rawQuery(
          "SELECT sql FROM sqlite_master WHERE type='table' AND name='$tableName'",
        );

        // Get indexes (raw SQL from sqlite_master)
        final indexes = await dbInfo.database.rawQuery(
          "SELECT name, sql FROM sqlite_master WHERE type='index' AND tbl_name='$tableName'",
        );

        // Enriched index metadata via PRAGMA index_list + index_info
        final indexList = await dbInfo.database
            .rawQuery('PRAGMA index_list("$tableName")');
        final enrichedIndexes = <Map<String, Object?>>[];
        for (final idx in indexList) {
          final idxName = idx['name'] as String? ?? '';
          final info =
              await dbInfo.database.rawQuery('PRAGMA index_info("$idxName")');
          String? sql;
          for (final r in indexes) {
            if (r['name'] == idxName) {
              sql = r['sql'] as String?;
              break;
            }
          }
          enrichedIndexes.add({
            'name': idxName,
            'unique': idx['unique'],
            'origin': idx['origin'],
            'partial': idx['partial'],
            'columns': info.map((c) => c['name']).toList(),
            'sql': sql,
          });
        }

        // Triggers (needed for Alter Table recreation path)
        final triggers = await dbInfo.database.rawQuery(
          "SELECT name, sql FROM sqlite_master WHERE type='trigger' AND tbl_name='$tableName'",
        );

        return Response.ok(
          jsonEncode({
            'columns': tableInfo,
            'foreignKeys': fkList,
            'createTable':
                createTable.isNotEmpty ? createTable.first['sql'] : null,
            'indexes': indexes,
            'indexList': enrichedIndexes,
            'triggers': triggers,
          }),
          headers: {'Content-Type': 'application/json'},
        );
      } catch (e) {
        return Response.internalServerError(
          body: jsonEncode({'error': e.toString()}),
          headers: {'Content-Type': 'application/json'},
        );
      }
    }

    // Get indexes for a table
    final indexesMatch =
        RegExp(r'^api/databases/([^/]+)/indexes/([^/]+)$').firstMatch(path);
    if (method == 'GET' && indexesMatch != null) {
      final dbId = indexesMatch.group(1)!;
      final tableName = indexesMatch.group(2)!;
      final dbInfo = server.getDatabase(dbId);
      if (dbInfo == null) {
        return Response.notFound(jsonEncode({'error': 'Database not found'}));
      }

      try {
        final indexes = await dbInfo.database.rawQuery(
          "SELECT name, sql FROM sqlite_master WHERE type='index' AND tbl_name='$tableName'",
        );

        return Response.ok(
          jsonEncode({'indexes': indexes}),
          headers: {'Content-Type': 'application/json'},
        );
      } catch (e) {
        return Response.internalServerError(
          body: jsonEncode({'error': e.toString()}),
          headers: {'Content-Type': 'application/json'},
        );
      }
    }

    // Execute a batch of SQL statements inside a transaction
    final batchMatch =
        RegExp(r'^api/databases/([^/]+)/batch$').firstMatch(path);
    if (method == 'POST' && batchMatch != null) {
      final dbId = batchMatch.group(1)!;
      final dbInfo = server.getDatabase(dbId);
      if (dbInfo == null) {
        return Response.notFound(jsonEncode({'error': 'Database not found'}));
      }
      try {
        final body = await request.readAsString();
        final json = jsonDecode(body) as Map<String, dynamic>;
        final statements = (json['statements'] as List?)?.cast<String>();
        if (statements == null || statements.isEmpty) {
          return Response.badRequest(
            body: jsonEncode({'error': 'statements array is required'}),
            headers: {'Content-Type': 'application/json'},
          );
        }

        final stopwatch = Stopwatch()..start();
        try {
          await dbInfo.database.transaction((txn) async {
            for (final stmt in statements) {
              final s = stmt.trim();
              if (s.isEmpty) continue;
              await txn.execute(s);
            }
          });
          stopwatch.stop();
          return Response.ok(
            jsonEncode({
              'ok': true,
              'executed': statements.length,
              'executionTime': stopwatch.elapsedMilliseconds,
            }),
            headers: {'Content-Type': 'application/json'},
          );
        } catch (e) {
          stopwatch.stop();
          return Response.ok(
            jsonEncode({
              'error': e.toString(),
              'executionTime': stopwatch.elapsedMilliseconds,
            }),
            headers: {'Content-Type': 'application/json'},
          );
        }
      } catch (e) {
        return Response.internalServerError(
          body: jsonEncode({'error': e.toString()}),
          headers: {'Content-Type': 'application/json'},
        );
      }
    }

    // Execute SQL query
    final queryMatch =
        RegExp(r'^api/databases/([^/]+)/query$').firstMatch(path);
    if (method == 'POST' && queryMatch != null) {
      final dbId = queryMatch.group(1)!;
      final dbInfo = server.getDatabase(dbId);
      if (dbInfo == null) {
        return Response.notFound(jsonEncode({'error': 'Database not found'}));
      }

      try {
        final body = await request.readAsString();
        final json = jsonDecode(body) as Map<String, dynamic>;
        final query = json['query'] as String?;

        if (query == null || query.trim().isEmpty) {
          return Response.badRequest(
            body: jsonEncode({'error': 'Query is required'}),
            headers: {'Content-Type': 'application/json'},
          );
        }

        final stopwatch = Stopwatch()..start();

        // Detect query type to use correct method
        final upperQuery = query.trimLeft().toUpperCase();
        final isSelect = upperQuery.startsWith('SELECT') ||
            upperQuery.startsWith('PRAGMA') ||
            upperQuery.startsWith('EXPLAIN');

        if (isSelect) {
          final result = await dbInfo.database.rawQuery(query);
          stopwatch.stop();
          return Response.ok(
            jsonEncode({
              'data': result,
              'executionTime': stopwatch.elapsedMilliseconds,
              'rowCount': result.length,
            }),
            headers: {'Content-Type': 'application/json'},
          );
        } else {
          // Use execute for all non-SELECT statements (UPDATE, INSERT, DELETE, CREATE, DROP, ALTER)
          await dbInfo.database.execute(query);
          stopwatch.stop();

          // Get affected rows count via changes()
          int affected = 0;
          try {
            final changesResult =
                await dbInfo.database.rawQuery('SELECT changes() as cnt');
            affected = (changesResult.first['cnt'] as int?) ?? 0;
          } catch (_) {}

          return Response.ok(
            jsonEncode({
              'data': [],
              'executionTime': stopwatch.elapsedMilliseconds,
              'rowCount': affected,
              'affectedRows': affected,
            }),
            headers: {'Content-Type': 'application/json'},
          );
        }
      } catch (e) {
        return Response.internalServerError(
          body: jsonEncode({'error': e.toString()}),
          headers: {'Content-Type': 'application/json'},
        );
      }
    }

    // Legacy endpoints for backward compatibility
    if (method == 'GET' && path == 'api/tables') {
      final dbId = request.url.queryParameters['db'];
      final dbInfo = dbId != null
          ? server.getDatabase(dbId)
          : server.databases.values.isNotEmpty
              ? server.databases.values.first
              : null;

      if (dbInfo == null) {
        return Response.notFound(jsonEncode({'error': 'Database not found'}));
      }

      try {
        final tables = await dbInfo.database.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
        );

        return Response.ok(
          jsonEncode({
            'tables': tables.map((t) => t['name'] as String).toList(),
          }),
          headers: {'Content-Type': 'application/json'},
        );
      } catch (e) {
        return Response.internalServerError(
          body: jsonEncode({'error': e.toString()}),
          headers: {'Content-Type': 'application/json'},
        );
      }
    }

    return Response.notFound('Not found');
  };
}
