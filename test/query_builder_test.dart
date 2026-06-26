import 'package:eva_generic_db_service/config/column.dart';
import 'package:eva_generic_db_service/db/query_builder.dart';
import 'package:eva_sdk/eva_sdk.dart';
import 'package:test/test.dart';

TableSchema _testSchema() {
  return TableSchema.fromServiceId('softkip.generic.db', [
    ColumnDefinition(name: 'id', type: 'SERIAL', primaryKey: true),
    ColumnDefinition(name: 'time', type: 'TIMESTAMP', notNull: true),
    ColumnDefinition(name: 'value', type: 'VARCHAR(255)'),
  ]);
}

void main() {
  group('TableSchema', () {
    test('table name from service id', () {
      final schema = _testSchema();
      expect(schema.tableName, 'softkip_generic_db');
    });

    test('createTableSql', () {
      final schema = _testSchema();
      expect(
        schema.createTableSql(),
        'CREATE TABLE IF NOT EXISTS softkip_generic_db (\n'
        '  id SERIAL PRIMARY KEY,\n'
        '  time TIMESTAMP NOT NULL,\n'
        '  value VARCHAR(255)\n'
        ');',
      );
    });

    test('rejects invalid column name', () {
      expect(
        () => ColumnDefinition.fromMap({'name': '1bad', 'type': 'INTEGER'}),
        throwsException,
      );
    });

    test('accepts BIGSERIAL type', () {
      final column = ColumnDefinition.fromMap({'name': 'id', 'type': 'BIGSERIAL'});
      expect(column.type, 'BIGSERIAL');
    });

    test('rejects unsupported type', () {
      expect(
        () => ColumnDefinition.fromMap({'name': 'col', 'type': 'FOOBAR'}),
        throwsException,
      );
    });
  });

  group('QueryBuilder select', () {
    late QueryBuilder qb;

    setUp(() {
      qb = QueryBuilder(_testSchema());
    });

    test('simple where with limit and order', () {
      final query = qb.buildSelect({
        'where': ['id', '>=', 32],
        'offset': 12,
        'limit': 33,
        'order': ['id', 'asc'],
      });

      expect(
        query.sql,
        'SELECT * FROM softkip_generic_db '
        'WHERE id >= @p0 '
        'ORDER BY id ASC '
        'OFFSET @offset LIMIT @limit',
      );
      expect(query.parameters, {'p0': 32, 'offset': 12, 'limit': 33});
    });

    test('where and orWhere with null', () {
      final query = qb.buildSelect({
        'where': ['id', '>=', 32],
        'orWhere': ['time', '!=', null],
      });

      expect(
        query.sql,
        'SELECT * FROM softkip_generic_db WHERE id >= @p0 OR time IS NOT NULL',
      );
      expect(query.parameters, {'p0': 32});
    });

    test('multiple where conditions are ANDed', () {
      final query = qb.buildSelect({
        'where': [
          ['id', '>=', 10],
          ['id', '<=', 20],
        ],
      });

      expect(
        query.sql,
        'SELECT * FROM softkip_generic_db WHERE (id >= @p0 AND id <= @p1)',
      );
      expect(query.parameters, {'p0': 10, 'p1': 20});
    });

    test('null equality', () {
      final query = qb.buildSelect({
        'where': ['value', '=', null],
      });

      expect(query.sql, 'SELECT * FROM softkip_generic_db WHERE value IS NULL');
      expect(query.parameters, isEmpty);
    });

    test('unknown column throws', () {
      expect(
        () => qb.buildSelect({'where': ['unknown', '=', 1]}),
        throwsA(isA<EvaError>()),
      );
    });

    test('like generates parameterized LIKE clause', () {
      final query = qb.buildSelect({
        'where': ['value', 'like', '%abc%'],
      });

      expect(
        query.sql,
        'SELECT * FROM softkip_generic_db WHERE value LIKE @p0',
      );
      expect(query.parameters, {'p0': '%abc%'});
    });

    test('not like generates parameterized NOT LIKE clause', () {
      final query = qb.buildSelect({
        'where': ['value', 'NOT LIKE', 'test%'],
      });

      expect(
        query.sql,
        'SELECT * FROM softkip_generic_db WHERE value NOT LIKE @p0',
      );
      expect(query.parameters, {'p0': 'test%'});
    });

    test('like with null throws', () {
      expect(
        () => qb.buildSelect({'where': ['value', 'like', null]}),
        throwsA(isA<EvaError>()),
      );
    });

    test('like with non-string value throws', () {
      expect(
        () => qb.buildSelect({'where': ['value', 'like', 42]}),
        throwsA(isA<EvaError>()),
      );
    });

    test('unsupported pattern operator throws', () {
      expect(
        () => qb.buildSelect({'where': ['value', 'ilike', '%x%']}),
        throwsA(isA<EvaError>()),
      );
    });
  });

  group('QueryBuilder insert', () {
    test('builds insert with returning', () {
      final qb = QueryBuilder(_testSchema());
      final query = qb.buildInsert({
        'values': {'time': 1719234567.0, 'value': 'abc'},
      });

      expect(
        query.sql,
        'INSERT INTO softkip_generic_db (time, value) '
        'VALUES (@v0, @v1) RETURNING *',
      );
      expect(query.parameters, {'v0': 1719234567.0, 'v1': 'abc'});
    });

    test('empty values throws', () {
      final qb = QueryBuilder(_testSchema());
      expect(
        () => qb.buildInsert({'values': {}}),
        throwsA(isA<EvaError>()),
      );
    });
  });

  group('QueryBuilder update', () {
    test('builds update with required where', () {
      final qb = QueryBuilder(_testSchema());
      final query = qb.buildUpdate({
        'set': {'value': 'new'},
        'where': ['id', '=', 1],
      });

      expect(
        query.sql,
        'UPDATE softkip_generic_db SET value = @s0 WHERE id = @w1',
      );
      expect(query.parameters, {'s0': 'new', 'w1': 1});
    });

    test('missing where throws', () {
      final qb = QueryBuilder(_testSchema());
      expect(
        () => qb.buildUpdate({'set': {'value': 'new'}}),
        throwsA(isA<EvaError>()),
      );
    });
  });

  group('QueryBuilder delete', () {
    test('builds delete with required where', () {
      final qb = QueryBuilder(_testSchema());
      final query = qb.buildDelete({
        'where': ['id', '=', 1],
      });

      expect(query.sql, 'DELETE FROM softkip_generic_db WHERE id = @d0');
      expect(query.parameters, {'d0': 1});
    });

    test('missing where throws', () {
      final qb = QueryBuilder(_testSchema());
      expect(
        () => qb.buildDelete({}),
        throwsA(isA<EvaError>()),
      );
    });
  });
}
