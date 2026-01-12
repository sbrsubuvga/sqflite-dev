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

      try {
        final file = File(dbInfo.path);
        final size = await file.length();

        return Response.ok(
          jsonEncode({
            'id': dbInfo.id,
            'name': dbInfo.name,
            'path': dbInfo.path,
            'size': size,
          }),
          headers: {'Content-Type': 'application/json'},
        );
      } catch (e) {
        return Response.ok(
          jsonEncode({
            'id': dbInfo.id,
            'name': dbInfo.name,
            'path': dbInfo.path,
            'size': 0,
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }
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

        // Get CREATE TABLE statement
        final createTable = await dbInfo.database.rawQuery(
          "SELECT sql FROM sqlite_master WHERE type='table' AND name='$tableName'",
        );

        // Get indexes
        final indexes = await dbInfo.database.rawQuery(
          "SELECT name, sql FROM sqlite_master WHERE type='index' AND tbl_name='$tableName'",
        );

        return Response.ok(
          jsonEncode({
            'columns': tableInfo,
            'createTable':
                createTable.isNotEmpty ? createTable.first['sql'] : null,
            'indexes': indexes,
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

        // Execute query
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
