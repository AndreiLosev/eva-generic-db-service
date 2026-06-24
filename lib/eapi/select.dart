import 'package:eva_generic_db_service/db/data_base_client.dart';
import 'package:eva_sdk/eva_sdk.dart';

class Select {
  static const name = 'select';
  static const description = 'select rows from table';

  Future<Map<String, dynamic>?> call(Map<String, dynamic> params) async {
    final db = DataBaseClient.getInstance();
    final withCount = params['with_count'] == true;
    final queryParams = Map<String, dynamic>.from(params)..remove('with_count');

    final rows = await db.select(queryParams);
    final result = <String, dynamic>{'rows': rows};
    if (withCount) {
      result['count'] = await db.count(queryParams);
    }
    return result;
  }

  static ServiceMethod createMethod() {
    return ServiceMethod(name, Select().call, description)
      ..optional('where', 'list', '[column, operator, value] or list of conditions')
      ..optional('orWhere', 'list', '[column, operator, value] or list of conditions')
      ..optional('offset', 'u64', 'default: 0')
      ..optional('limit', 'u64')
      ..optional('order', 'list', '[column, asc|desc] or list of pairs')
      ..optional('with_count', 'bool', 'include total count');
  }
}
