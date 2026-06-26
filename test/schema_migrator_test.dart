import 'package:eva_generic_db_service/config/column.dart';
import 'package:eva_generic_db_service/db/schema_migrator.dart';
import 'package:test/test.dart';

TableSchema _schema([List<ColumnDefinition>? columns]) {
  return TableSchema.fromServiceId('softkip.generic.db', columns ?? [
    ColumnDefinition(name: 'id', type: 'SERIAL', primaryKey: true),
    ColumnDefinition(name: 'time', type: 'TIMESTAMP', notNull: true),
    ColumnDefinition(name: 'value', type: 'VARCHAR(255)'),
  ]);
}

ExistingColumn _existing({
  required String name,
  required String type,
  bool notNull = false,
  String? defaultValue,
  bool unique = false,
  bool primaryKey = false,
  String? uniqueConstraintName,
}) {
  return ExistingColumn(
    name: name,
    type: type,
    notNull: notNull,
    defaultValue: defaultValue,
    unique: unique,
    primaryKey: primaryKey,
    uniqueConstraintName: uniqueConstraintName,
  );
}

void main() {
  group('normalizePostgresColumnType', () {
    test('maps character varying with length', () {
      expect(
        normalizePostgresColumnType(
          dataType: 'character varying',
          udtName: 'varchar',
          characterMaximumLength: 255,
        ),
        'VARCHAR(255)',
      );
    });

    test('maps integer with nextval to SERIAL', () {
      expect(
        normalizePostgresColumnType(
          dataType: 'integer',
          udtName: 'int4',
          columnDefault: "nextval('softkip_generic_db_id_seq'::regclass)",
        ),
        'SERIAL',
      );
    });

    test('maps bigint with nextval to BIGSERIAL', () {
      expect(
        normalizePostgresColumnType(
          dataType: 'bigint',
          udtName: 'int8',
          columnDefault: "nextval('softkip_generic_db_id_seq'::regclass)",
        ),
        'BIGSERIAL',
      );
    });

    test('maps timestamp without time zone', () {
      expect(
        normalizePostgresColumnType(
          dataType: 'timestamp without time zone',
          udtName: 'timestamp',
        ),
        'TIMESTAMP',
      );
    });
  });

  group('ColumnDefinition helpers', () {
    test('toAddColumnSql uses INTEGER instead of SERIAL', () {
      final column = ColumnDefinition(name: 'id', type: 'SERIAL', notNull: true);
      expect(column.toAddColumnSql(), 'id INTEGER NOT NULL');
    });

    test('toAddColumnSql uses BIGINT instead of BIGSERIAL', () {
      final column = ColumnDefinition(name: 'id', type: 'BIGSERIAL', notNull: true);
      expect(column.toAddColumnSql(), 'id BIGINT NOT NULL');
    });

    test('normalizedType uppercases type', () {
      final column = ColumnDefinition(name: 'value', type: 'varchar(255)');
      expect(column.normalizedType(), 'VARCHAR(255)');
    });
  });

  group('SchemaMigrator.buildAlterStatements', () {
    test('adds new column', () {
      final desired = _schema([
        ColumnDefinition(name: 'id', type: 'SERIAL', primaryKey: true),
        ColumnDefinition(name: 'time', type: 'TIMESTAMP', notNull: true),
        ColumnDefinition(name: 'value', type: 'VARCHAR(255)'),
        ColumnDefinition(name: 'status', type: 'INTEGER', defaultValue: '0'),
      ]);
      final current = [
        _existing(name: 'id', type: 'SERIAL', primaryKey: true),
        _existing(name: 'time', type: 'TIMESTAMP', notNull: true),
        _existing(name: 'value', type: 'VARCHAR(255)'),
      ];

      final statements = SchemaMigrator.buildAlterStatements(desired, current);

      expect(statements, [
        'ALTER TABLE softkip_generic_db ADD COLUMN status INTEGER DEFAULT 0',
      ]);
    });

    test('alters type, not_null and default', () {
      final desired = _schema([
        ColumnDefinition(name: 'id', type: 'SERIAL', primaryKey: true),
        ColumnDefinition(
          name: 'value',
          type: 'TEXT',
          notNull: true,
          defaultValue: "'x'",
        ),
      ]);
      final current = [
        _existing(name: 'id', type: 'SERIAL', primaryKey: true),
        _existing(name: 'value', type: 'VARCHAR(255)'),
      ];

      final statements = SchemaMigrator.buildAlterStatements(desired, current);

      expect(statements, [
        'ALTER TABLE softkip_generic_db ALTER COLUMN value TYPE TEXT USING value::TEXT',
        'ALTER TABLE softkip_generic_db ALTER COLUMN value SET NOT NULL',
        "ALTER TABLE softkip_generic_db ALTER COLUMN value SET DEFAULT 'x'",
      ]);
    });

    test('adds and drops unique constraint', () {
      final desired = _schema([
        ColumnDefinition(name: 'id', type: 'SERIAL', primaryKey: true),
        ColumnDefinition(name: 'value', type: 'VARCHAR(255)', unique: true),
      ]);
      final current = [
        _existing(name: 'id', type: 'SERIAL', primaryKey: true),
        _existing(
          name: 'time',
          type: 'TIMESTAMP',
          unique: true,
          uniqueConstraintName: 'softkip_generic_db_time_unique',
        ),
        _existing(name: 'value', type: 'VARCHAR(255)'),
      ];

      final statements = SchemaMigrator.buildAlterStatements(desired, current);

      expect(statements, [
        'ALTER TABLE softkip_generic_db '
        'ADD CONSTRAINT softkip_generic_db_value_unique UNIQUE (value)',
      ]);
    });

    test('drops unique constraint when disabled in config', () {
      final desired = _schema([
        ColumnDefinition(name: 'id', type: 'SERIAL', primaryKey: true),
        ColumnDefinition(name: 'value', type: 'VARCHAR(255)'),
      ]);
      final current = [
        _existing(name: 'id', type: 'SERIAL', primaryKey: true),
        _existing(
          name: 'value',
          type: 'VARCHAR(255)',
          unique: true,
          uniqueConstraintName: 'softkip_generic_db_value_unique',
        ),
      ];

      final statements = SchemaMigrator.buildAlterStatements(desired, current);

      expect(statements, [
        'ALTER TABLE softkip_generic_db DROP CONSTRAINT softkip_generic_db_value_unique',
      ]);
    });

    test('does not drop removed columns', () {
      final desired = _schema([
        ColumnDefinition(name: 'id', type: 'SERIAL', primaryKey: true),
      ]);
      final current = [
        _existing(name: 'id', type: 'SERIAL', primaryKey: true),
        _existing(name: 'value', type: 'VARCHAR(255)'),
      ];

      final statements = SchemaMigrator.buildAlterStatements(desired, current);

      expect(statements, isEmpty);
    });

    test('throws when primary key changes', () {
      final desired = _schema([
        ColumnDefinition(name: 'id', type: 'INTEGER'),
        ColumnDefinition(name: 'value', type: 'VARCHAR(255)', primaryKey: true),
      ]);
      final current = [
        _existing(name: 'id', type: 'SERIAL', primaryKey: true),
        _existing(name: 'value', type: 'VARCHAR(255)'),
      ];

      expect(
        () => SchemaMigrator.buildAlterStatements(desired, current),
        throwsA(
          predicate(
            (e) => e.toString().contains('changing primary key'),
          ),
        ),
      );
    });

    test('returns empty list for matching schema', () {
      final desired = _schema();
      final current = [
        _existing(name: 'id', type: 'SERIAL', primaryKey: true),
        _existing(name: 'time', type: 'TIMESTAMP', notNull: true),
        _existing(name: 'value', type: 'VARCHAR(255)'),
      ];

      expect(SchemaMigrator.buildAlterStatements(desired, current), isEmpty);
    });
  });

  group('SchemaMigrator.buildIndexStatements', () {
    test('creates index when index is true', () {
      final desired = _schema([
        ColumnDefinition(name: 'id', type: 'SERIAL', primaryKey: true),
        ColumnDefinition(name: 'time', type: 'TIMESTAMP', notNull: true, index: true),
        ColumnDefinition(name: 'value', type: 'VARCHAR(255)'),
      ]);

      final statements = SchemaMigrator.buildIndexStatements(desired, {});

      expect(statements, [
        'CREATE INDEX IF NOT EXISTS softkip_generic_db_time_idx '
        'ON softkip_generic_db (time)',
      ]);
    });

    test('creates index when columns match but index is missing', () {
      final desired = _schema([
        ColumnDefinition(name: 'id', type: 'SERIAL', primaryKey: true),
        ColumnDefinition(name: 'time', type: 'TIMESTAMP', notNull: true, index: true),
      ]);

      final statements = SchemaMigrator.buildIndexStatements(desired, {});

      expect(statements, hasLength(1));
      expect(statements.first, contains('CREATE INDEX IF NOT EXISTS'));
    });

    test('drops index when flag is removed', () {
      final desired = _schema([
        ColumnDefinition(name: 'id', type: 'SERIAL', primaryKey: true),
        ColumnDefinition(name: 'time', type: 'TIMESTAMP', notNull: true),
      ]);

      final statements = SchemaMigrator.buildIndexStatements(desired, {
        'softkip_generic_db_time_idx',
      });

      expect(statements, ['DROP INDEX IF EXISTS softkip_generic_db_time_idx']);
    });

    test('skips index for primary key column', () {
      final desired = _schema([
        ColumnDefinition(name: 'id', type: 'SERIAL', primaryKey: true, index: true),
      ]);

      expect(SchemaMigrator.buildIndexStatements(desired, {}), isEmpty);
    });

    test('skips index for unique column', () {
      final desired = _schema([
        ColumnDefinition(name: 'id', type: 'SERIAL', primaryKey: true),
        ColumnDefinition(name: 'value', type: 'VARCHAR(255)', unique: true, index: true),
      ]);

      expect(SchemaMigrator.buildIndexStatements(desired, {}), isEmpty);
    });

    test('does nothing when index already exists', () {
      final desired = _schema([
        ColumnDefinition(name: 'time', type: 'TIMESTAMP', index: true),
      ]);

      expect(
        SchemaMigrator.buildIndexStatements(desired, {'softkip_generic_db_time_idx'}),
        isEmpty,
      );
    });
  });
}
