import 'package:eva_generic_db_service/config/config.dart';
import 'package:eva_generic_db_service/db/query_builder.dart';
import 'package:eva_generic_db_service/db/schema_migrator.dart';
import 'package:postgres/postgres.dart';

class DataBaseClient {
  static DataBaseClient? _instance;

  final Config _config;
  late final QueryBuilder _queryBuilder;
  late final String _createTableSql;
  Connection? _dbConn;

  DataBaseClient._(this._config) {
    _queryBuilder = QueryBuilder(_config.schema);
    _createTableSql = _config.schema.createTableSql();
  }

  factory DataBaseClient.getInstance([Config? config]) {
    if (_instance == null && config == null) {
      throw Exception('need initialize connection');
    }
    _instance ??= DataBaseClient._(config!);
    return _instance!;
  }

  QueryBuilder get queryBuilder => _queryBuilder;

  Future<void> connect() async {
    _dbConn = await Connection.open(
      Endpoint(
        host: _config.db.host,
        port: _config.db.port,
        username: _config.db.user,
        password: _config.db.password,
        database: _config.db.db,
      ),
      settings: ConnectionSettings(
        sslMode: _config.db.ssl ? SslMode.require : SslMode.disable,
      ),
    );
  }

  Future<void> disconnect() async {
    await _dbConn?.close();
    _dbConn = null;
  }

  bool isConnected() => _dbConn?.isOpen ?? false;

  Future<void> makeTable() async {
    await _dbConn!.execute(_createTableSql, queryMode: QueryMode.simple);
    await SchemaMigrator(_config.schema, _dbConn!).migrate();
  }

  Future<List<Map<String, dynamic>>> select(Map<String, dynamic> params) async {
    final query = _queryBuilder.buildSelect(params);
    final res = await _dbConn!.execute(Sql.named(query.sql), parameters: query.parameters);
    return res.map((row) => row.toColumnMap()).toList();
  }

  Future<int?> count(Map<String, dynamic> params) async {
    final query = _queryBuilder.buildCount(params);
    final res = await _dbConn!.execute(Sql.named(query.sql), parameters: query.parameters);
    if (res.isEmpty) return null;
    return res.first.first as int?;
  }

  Future<Map<String, dynamic>> insert(Map<String, dynamic> params) async {
    final query = _queryBuilder.buildInsert(params);
    final res = await _dbConn!.execute(Sql.named(query.sql), parameters: query.parameters);
    if (res.isEmpty) {
      return {'affected': 0};
    }
    return {'row': res.first.toColumnMap(), 'affected': res.affectedRows};
  }

  Future<int> update(Map<String, dynamic> params) async {
    final query = _queryBuilder.buildUpdate(params);
    final res = await _dbConn!.execute(Sql.named(query.sql), parameters: query.parameters);
    return res.affectedRows;
  }

  Future<int> delete(Map<String, dynamic> params) async {
    final query = _queryBuilder.buildDelete(params);
    final res = await _dbConn!.execute(Sql.named(query.sql), parameters: query.parameters);
    return res.affectedRows;
  }
}
