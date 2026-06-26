import 'package:eva_generic_db_service/db/data_base_client.dart';
import 'package:eva_sdk/eva_sdk.dart';

class Update {
  static const name = 'update';
  static const description = 'update rows in table';

  Future<Map<String, dynamic>?> call(Map<String, dynamic> params) async {
    final affected = await DataBaseClient.getInstance().update(params);
    return {'affected': affected};
  }

  static ServiceMethod createMethod() {
    return ServiceMethod(name, Update().call, description)
      ..required('set', 'dict', 'column name to value map')
      ..required('where', 'list', '[column, operator, value] — operators: =, !=, >, >=, <, <=, like, not like');
  }
}
