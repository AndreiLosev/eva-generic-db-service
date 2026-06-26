class ColumnDefinition {
  static final _identifier = RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$');

  static const allowedTypes = {
    'SERIAL',
    'INTEGER',
    'INT',
    'BIGSERIAL',
    'BIGINT',
    'SMALLINT',
    'TEXT',
    'VARCHAR',
    'CHAR',
    'BOOLEAN',
    'BOOL',
    'TIMESTAMP',
    'TIMESTAMPTZ',
    'DATE',
    'TIME',
    'NUMERIC',
    'DECIMAL',
    'REAL',
    'DOUBLE PRECISION',
    'FLOAT',
    'JSON',
    'JSONB',
    'UUID',
  };

  final String name;
  final String type;
  final bool primaryKey;
  final bool notNull;
  final bool unique;
  final bool index;
  final String? defaultValue;

  ColumnDefinition({
    required this.name,
    required this.type,
    this.primaryKey = false,
    this.notNull = false,
    this.unique = false,
    this.index = false,
    this.defaultValue,
  });

  factory ColumnDefinition.fromMap(Map map) {
    final name = map['name'] as String;
    final type = map['type'] as String;
    _validateIdentifier(name);
    _validateType(type);
    return ColumnDefinition(
      name: name,
      type: type.toUpperCase(),
      primaryKey: map['primary_key'] == true,
      notNull: map['not_null'] == true,
      unique: map['unique'] == true,
      index: map['index'] == true,
      defaultValue: map['default']?.toString(),
    );
  }

  static void _validateIdentifier(String name) {
    if (!_identifier.hasMatch(name)) {
      throw Exception('invalid column name: $name');
    }
  }

  static void _validateType(String type) {
    final upper = type.toUpperCase();
    final base = upper.split('(').first.trim();
    if (!allowedTypes.contains(base)) {
      throw Exception('unsupported column type: $type');
    }
  }

  String normalizedType() => normalizeTypeName(type);

  String addColumnType() {
    final base = normalizedType().split('(').first;
    return switch (base) {
      'SERIAL' => 'INTEGER',
      'BIGSERIAL' => 'BIGINT',
      _ => type,
    };
  }

  bool get isAutoIncrementType {
    final base = normalizedType().split('(').first;
    return base == 'SERIAL' || base == 'BIGSERIAL';
  }

  String toSqlDefinition() {
    final parts = <String>[name, type];
    if (primaryKey) {
      parts.add('PRIMARY KEY');
    }
    if (notNull && !primaryKey) {
      parts.add('NOT NULL');
    }
    if (unique && !primaryKey) {
      parts.add('UNIQUE');
    }
    if (defaultValue != null) {
      parts.add('DEFAULT $defaultValue');
    }
    return parts.join(' ');
  }

  String toAddColumnSql() {
    final parts = <String>[name, addColumnType()];
    if (notNull) {
      parts.add('NOT NULL');
    }
    if (defaultValue != null) {
      parts.add('DEFAULT $defaultValue');
    }
    return parts.join(' ');
  }

  String uniqueConstraintName(String tableName) =>
      '${tableName}_${name}_unique';

  String indexName(String tableName) => '${tableName}_${name}_idx';

  bool get shouldCreateIndex => index && !primaryKey && !unique;
}

class ExistingColumn {
  final String name;
  final String type;
  final bool notNull;
  final String? defaultValue;
  final bool unique;
  final bool primaryKey;
  final String? uniqueConstraintName;

  ExistingColumn({
    required this.name,
    required this.type,
    required this.notNull,
    this.defaultValue,
    this.unique = false,
    this.primaryKey = false,
    this.uniqueConstraintName,
  });

  String normalizedType() => normalizeTypeName(type);

  String? normalizedDefault() => normalizeDefaultValue(defaultValue);
}

String normalizeTypeName(String type) {
  return type.toUpperCase().replaceAll(RegExp(r'\s+'), ' ').trim();
}

String? normalizeDefaultValue(String? value) {
  if (value == null) return null;
  var normalized = value.trim();
  final castIndex = normalized.indexOf('::');
  if (castIndex != -1) {
    normalized = normalized.substring(0, castIndex).trim();
  }
  return normalized;
}

String normalizePostgresColumnType({
  required String dataType,
  required String udtName,
  int? characterMaximumLength,
  String? columnDefault,
}) {
  final defaultValue = columnDefault ?? '';
  if (udtName == 'int4' && defaultValue.contains('nextval(')) {
    return 'SERIAL';
  }
  if (udtName == 'int8' && defaultValue.contains('nextval(')) {
    return 'BIGSERIAL';
  }

  switch (dataType) {
    case 'character varying':
      return characterMaximumLength == null
          ? 'VARCHAR'
          : 'VARCHAR($characterMaximumLength)';
    case 'character':
      return characterMaximumLength == null
          ? 'CHAR'
          : 'CHAR($characterMaximumLength)';
    case 'timestamp without time zone':
      return 'TIMESTAMP';
    case 'timestamp with time zone':
      return 'TIMESTAMPTZ';
    case 'double precision':
      return 'DOUBLE PRECISION';
    case 'boolean':
      return 'BOOLEAN';
    case 'text':
      return 'TEXT';
    case 'jsonb':
      return 'JSONB';
    case 'json':
      return 'JSON';
    case 'uuid':
      return 'UUID';
    case 'numeric':
      return 'NUMERIC';
    case 'real':
      return 'REAL';
    case 'smallint':
      return 'SMALLINT';
    case 'bigint':
      return 'BIGINT';
    case 'integer':
      return 'INTEGER';
    case 'date':
      return 'DATE';
    case 'time without time zone':
      return 'TIME';
    default:
      return normalizeTypeName(dataType);
  }
}

class TableSchema {
  static final _identifier = RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$');

  final String tableName;
  final List<ColumnDefinition> columns;

  TableSchema(this.tableName, this.columns) {
    _validateIdentifier(tableName);
    if (columns.isEmpty) {
      throw Exception('table must have at least one column');
    }
  }

  factory TableSchema.fromServiceId(
    String serviceId,
    List<ColumnDefinition> columns,
  ) {
    final tableName = serviceId.replaceAll('.', '_');
    return TableSchema(tableName, columns);
  }

  static void _validateIdentifier(String name) {
    if (!_identifier.hasMatch(name)) {
      throw Exception('invalid table name: $name');
    }
  }

  Set<String> get columnNames => columns.map((c) => c.name).toSet();

  ColumnDefinition? get primaryKeyColumn {
    for (final column in columns) {
      if (column.primaryKey) return column;
    }
    return null;
  }

  String createTableSql() {
    final defs = columns.map((c) => c.toSqlDefinition()).join(',\n  ');
    return 'CREATE TABLE IF NOT EXISTS $tableName (\n  $defs\n);';
  }
}
