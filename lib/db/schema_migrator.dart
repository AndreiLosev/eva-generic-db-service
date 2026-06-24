import 'package:eva_generic_db_service/config/column.dart';
import 'package:postgres/postgres.dart';

class SchemaMigrator {
  final TableSchema schema;
  final Connection connection;

  SchemaMigrator(this.schema, this.connection);

  Future<void> migrate() async {
    final current = await _fetchCurrentColumns();
    final statements = buildAlterStatements(schema, current);
    if (statements.isEmpty) return;

    await connection.runTx((tx) async {
      for (final sql in statements) {
        await tx.execute(sql, queryMode: QueryMode.simple);
      }
    });
  }

  Future<List<ExistingColumn>> _fetchCurrentColumns() async {
    final columnsResult = await connection.execute(
      Sql.named('''
SELECT column_name, data_type, udt_name, character_maximum_length,
       is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = @table
ORDER BY ordinal_position
'''),
      parameters: {'table': schema.tableName},
    );

    if (columnsResult.isEmpty) {
      return [];
    }

    final uniqueByColumn = <String, String>{};
    final uniqueResult = await connection.execute(
      Sql.named('''
SELECT tc.constraint_name, kcu.column_name
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
  ON tc.constraint_schema = kcu.constraint_schema
 AND tc.constraint_name = kcu.constraint_name
WHERE tc.table_schema = 'public'
  AND tc.table_name = @table
  AND tc.constraint_type = 'UNIQUE'
'''),
      parameters: {'table': schema.tableName},
    );
    for (final row in uniqueResult) {
      final map = row.toColumnMap();
      uniqueByColumn[map['column_name'] as String] =
          map['constraint_name'] as String;
    }

    final primaryKeys = <String>{};
    final pkResult = await connection.execute(
      Sql.named('''
SELECT kcu.column_name
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
  ON tc.constraint_schema = kcu.constraint_schema
 AND tc.constraint_name = kcu.constraint_name
WHERE tc.table_schema = 'public'
  AND tc.table_name = @table
  AND tc.constraint_type = 'PRIMARY KEY'
'''),
      parameters: {'table': schema.tableName},
    );
    for (final row in pkResult) {
      primaryKeys.add(row.toColumnMap()['column_name'] as String);
    }

    return columnsResult.map((row) {
      final map = row.toColumnMap();
      final name = map['column_name'] as String;
      return ExistingColumn(
        name: name,
        type: normalizePostgresColumnType(
          dataType: map['data_type'] as String,
          udtName: map['udt_name'] as String,
          characterMaximumLength: map['character_maximum_length'] as int?,
          columnDefault: map['column_default'] as String?,
        ),
        notNull: map['is_nullable'] == 'NO',
        defaultValue: map['column_default'] as String?,
        unique: uniqueByColumn.containsKey(name),
        primaryKey: primaryKeys.contains(name),
        uniqueConstraintName: uniqueByColumn[name],
      );
    }).toList();
  }

  static List<String> buildAlterStatements(
    TableSchema desired,
    List<ExistingColumn> current,
  ) {
    _validatePrimaryKey(desired, current);

    final currentByName = {for (final c in current) c.name: c};
    final addColumn = <String>[];
    final alterColumn = <String>[];
    final constraints = <String>[];

    for (final column in desired.columns) {
      final existing = currentByName[column.name];
      if (existing == null) {
        addColumn.add(
          'ALTER TABLE ${desired.tableName} ADD COLUMN ${column.toAddColumnSql()}',
        );
        if (column.unique) {
          constraints.add(
            'ALTER TABLE ${desired.tableName} '
            'ADD CONSTRAINT ${column.uniqueConstraintName(desired.tableName)} '
            'UNIQUE (${column.name})',
          );
        }
        continue;
      }

      if (column.primaryKey != existing.primaryKey) {
        throw Exception(
          'changing primary key for column ${column.name} is not supported',
        );
      }

      final desiredType = _desiredTypeForComparison(column);
      if (desiredType != existing.normalizedType()) {
        alterColumn.add(
          'ALTER TABLE ${desired.tableName} '
          'ALTER COLUMN ${column.name} TYPE ${column.addColumnType()} '
          'USING ${column.name}::${column.addColumnType()}',
        );
      }

      if (column.primaryKey) continue;

      if (column.notNull != existing.notNull) {
        alterColumn.add(
          column.notNull
              ? 'ALTER TABLE ${desired.tableName} ALTER COLUMN ${column.name} SET NOT NULL'
              : 'ALTER TABLE ${desired.tableName} ALTER COLUMN ${column.name} DROP NOT NULL',
        );
      }

      final desiredDefault = normalizeDefaultValue(column.defaultValue);
      final existingDefault = existing.normalizedDefault();
      if (_defaultsDiffer(desiredDefault, existingDefault, column, existing)) {
        if (desiredDefault == null) {
          alterColumn.add(
            'ALTER TABLE ${desired.tableName} ALTER COLUMN ${column.name} DROP DEFAULT',
          );
        } else {
          alterColumn.add(
            'ALTER TABLE ${desired.tableName} '
            'ALTER COLUMN ${column.name} SET DEFAULT ${column.defaultValue}',
          );
        }
      }

      if (column.unique != existing.unique) {
        if (column.unique) {
          constraints.add(
            'ALTER TABLE ${desired.tableName} '
            'ADD CONSTRAINT ${column.uniqueConstraintName(desired.tableName)} '
            'UNIQUE (${column.name})',
          );
        } else {
          final constraintName =
              existing.uniqueConstraintName ??
              column.uniqueConstraintName(desired.tableName);
          constraints.add(
            'ALTER TABLE ${desired.tableName} DROP CONSTRAINT $constraintName',
          );
        }
      }
    }

    return [...addColumn, ...alterColumn, ...constraints];
  }

  static void _validatePrimaryKey(
    TableSchema desired,
    List<ExistingColumn> current,
  ) {
    final desiredPk = desired.primaryKeyColumn?.name;
    String? currentPk;
    for (final column in current) {
      if (column.primaryKey) {
        currentPk = column.name;
        break;
      }
    }

    if (desiredPk == currentPk) return;
    if (current.isEmpty) return;

    throw Exception(
      'changing primary key is not supported (config: $desiredPk, database: $currentPk)',
    );
  }

  static String _desiredTypeForComparison(ColumnDefinition column) {
    if (column.primaryKey && column.isAutoIncrementType) {
      return column.normalizedType();
    }
    return column.normalizedType();
  }

  static bool _defaultsDiffer(
    String? desiredDefault,
    String? existingDefault,
    ColumnDefinition column,
    ExistingColumn existing,
  ) {
    if (column.isAutoIncrementType || _isAutoIncrementType(existing.normalizedType())) {
      return false;
    }
    return desiredDefault != existingDefault;
  }

  static bool _isAutoIncrementType(String type) {
    final base = type.split('(').first;
    return base == 'SERIAL' || base == 'BIGSERIAL';
  }
}
