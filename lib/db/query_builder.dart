import 'package:eva_generic_db_service/config/column.dart';
import 'package:eva_sdk/eva_sdk.dart';

class BuiltQuery {
  final String sql;
  final Map<String, dynamic> parameters;

  BuiltQuery(this.sql, this.parameters);
}

class QueryBuilder {
  static const operators = {'=', '!=', '>', '>=', '<', '<='};

  final TableSchema schema;

  QueryBuilder(this.schema);

  BuiltQuery buildSelect(Map<String, dynamic> params) {
    final parameters = <String, dynamic>{};
    var paramIndex = 0;

    final whereClause = _buildWhereClause(params, parameters, () => 'p${paramIndex++}');
    final orderClause = _buildOrderClause(params);
    final offset = _readInt(params, 'offset') ?? _readInt(params, 'OFFSET');
    final limit = _readInt(params, 'limit') ?? _readInt(params, 'LIMIT');

    final parts = <String>['SELECT * FROM ${schema.tableName}'];
    if (whereClause != null) {
      parts.add('WHERE $whereClause');
    }
    if (orderClause != null) {
      parts.add('ORDER BY $orderClause');
    }
    if (offset != null) {
      parameters['offset'] = offset;
      parts.add('OFFSET @offset');
    }
    if (limit != null) {
      parameters['limit'] = limit;
      parts.add('LIMIT @limit');
    }

    return BuiltQuery(parts.join(' '), parameters);
  }

  BuiltQuery buildCount(Map<String, dynamic> params) {
    final parameters = <String, dynamic>{};
    var paramIndex = 0;
    final whereClause = _buildWhereClause(params, parameters, () => 'p${paramIndex++}');

    final parts = <String>['SELECT COUNT(*) FROM ${schema.tableName}'];
    if (whereClause != null) {
      parts.add('WHERE $whereClause');
    }

    return BuiltQuery(parts.join(' '), parameters);
  }

  BuiltQuery buildInsert(Map<String, dynamic> params) {
    final values = params['values'];
    if (values is! Map) {
      throw EvaError(EvaErrorKind.invalidParams, 'param values: dict is required');
    }

    final entries = <MapEntry<String, dynamic>>[];
    for (final entry in values.entries) {
      final key = entry.key.toString();
      _validateColumn(key);
      entries.add(MapEntry(key, entry.value));
    }

    if (entries.isEmpty) {
      throw EvaError(EvaErrorKind.invalidParams, 'param values must not be empty');
    }

    final parameters = <String, dynamic>{};
    final columns = <String>[];
    final placeholders = <String>[];

    for (var i = 0; i < entries.length; i++) {
      final name = 'v$i';
      columns.add(entries[i].key);
      placeholders.add('@$name');
      parameters[name] = entries[i].value;
    }

    final sql =
        'INSERT INTO ${schema.tableName} (${columns.join(', ')}) '
        'VALUES (${placeholders.join(', ')}) RETURNING *';

    return BuiltQuery(sql, parameters);
  }

  BuiltQuery buildUpdate(Map<String, dynamic> params) {
    final setMap = params['set'];
    if (setMap is! Map || setMap.isEmpty) {
      throw EvaError(EvaErrorKind.invalidParams, 'param set: dict is required');
    }

    final parameters = <String, dynamic>{};
    var paramIndex = 0;
    final setParts = <String>[];

    for (final entry in setMap.entries) {
      final key = entry.key.toString();
      _validateColumn(key);
      final name = 's$paramIndex';
      paramIndex++;
      setParts.add('$key = @$name');
      parameters[name] = entry.value;
    }

    final whereClause = _buildWhereClause(
      params,
      parameters,
      () => 'w${paramIndex++}',
      required: true,
    );

    final sql =
        'UPDATE ${schema.tableName} SET ${setParts.join(', ')} WHERE $whereClause';

    return BuiltQuery(sql, parameters);
  }

  BuiltQuery buildDelete(Map<String, dynamic> params) {
    final parameters = <String, dynamic>{};
    var paramIndex = 0;
    final whereClause = _buildWhereClause(
      params,
      parameters,
      () => 'd${paramIndex++}',
      required: true,
    );

    final sql = 'DELETE FROM ${schema.tableName} WHERE $whereClause';
    return BuiltQuery(sql, parameters);
  }

  String? _buildWhereClause(
    Map<String, dynamic> params,
    Map<String, dynamic> parameters,
    String Function() nextParamName, {
    bool required = false,
  }) {
    final whereConditions = _parseConditions(params['where'], parameters, nextParamName);
    final orWhereConditions = _parseConditions(params['orWhere'], parameters, nextParamName);

    if (whereConditions.isEmpty && orWhereConditions.isEmpty) {
      if (required) {
        throw EvaError(EvaErrorKind.invalidParams, 'param where is required');
      }
      return null;
    }

    final parts = <String>[];
    if (whereConditions.isNotEmpty) {
      parts.add(whereConditions.length == 1
          ? whereConditions.first
          : '(${whereConditions.join(' AND ')})');
    }
    if (orWhereConditions.isNotEmpty) {
      final orPart = orWhereConditions.length == 1
          ? orWhereConditions.first
          : '(${orWhereConditions.join(' OR ')})';
      parts.add(orPart);
    }

    return parts.join(' OR ');
  }

  List<String> _parseConditions(
    dynamic raw,
    Map<String, dynamic> parameters,
    String Function() nextParamName,
  ) {
    if (raw == null) return [];

    final conditions = <List<dynamic>>[];
    if (raw is List) {
      if (raw.isEmpty) return [];
      if (raw.first is List) {
        for (final item in raw) {
          conditions.add(List<dynamic>.from(item as List));
        }
      } else {
        conditions.add(List<dynamic>.from(raw));
      }
    } else {
      throw EvaError(EvaErrorKind.invalidParams, 'where/orWhere must be a list');
    }

    return conditions.map((c) => _conditionToSql(c, parameters, nextParamName)).toList();
  }

  String _conditionToSql(
    List<dynamic> condition,
    Map<String, dynamic> parameters,
    String Function() nextParamName,
  ) {
    if (condition.length != 3) {
      throw EvaError(
        EvaErrorKind.invalidParams,
        'condition must be [column, operator, value]',
      );
    }

    final column = condition[0].toString();
    final operator = condition[1].toString();
    final value = condition[2];

    _validateColumn(column);
    if (!operators.contains(operator)) {
      throw EvaError(EvaErrorKind.invalidParams, 'unsupported operator: $operator');
    }

    if (value == null) {
      return switch (operator) {
        '=' => '$column IS NULL',
        '!=' => '$column IS NOT NULL',
        _ => throw EvaError(
          EvaErrorKind.invalidParams,
          'operator $operator with null requires = or !=',
        ),
      };
    }

    final paramName = nextParamName();
    parameters[paramName] = value;
    return '$column $operator @$paramName';
  }

  String? _buildOrderClause(Map<String, dynamic> params) {
    final raw = params['order'];
    if (raw == null) return null;

    final orders = <List<String>>[];
    if (raw is List) {
      if (raw.isEmpty) return null;
      if (raw.first is List) {
        for (final item in raw) {
          orders.add(_parseOrderItem(List.from(item as List)));
        }
      } else {
        orders.add(_parseOrderItem(List.from(raw)));
      }
    } else {
      throw EvaError(EvaErrorKind.invalidParams, 'order must be a list');
    }

    return orders.map((o) => '${o[0]} ${o[1]}').join(', ');
  }

  List<String> _parseOrderItem(List<dynamic> item) {
    if (item.length != 2) {
      throw EvaError(
        EvaErrorKind.invalidParams,
        'order item must be [column, asc|desc]',
      );
    }
    final column = item[0].toString();
    final direction = item[1].toString().toUpperCase();
    _validateColumn(column);
    if (direction != 'ASC' && direction != 'DESC') {
      throw EvaError(EvaErrorKind.invalidParams, 'order direction must be asc or desc');
    }
    return [column, direction];
  }

  void _validateColumn(String column) {
    if (!schema.columnNames.contains(column)) {
      throw EvaError(EvaErrorKind.invalidParams, 'unknown column: $column');
    }
  }

  int? _readInt(Map<String, dynamic> params, String key) {
    final value = params[key];
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    throw EvaError(EvaErrorKind.invalidParams, 'param $key must be an integer');
  }
}
