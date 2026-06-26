import 'package:eva_generic_db_service/db/data_base_client.dart';
import 'package:eva_sdk/eva_sdk.dart';

class Delete {
  static const name = 'delete';
  static const description = 'delete rows from table';

  Future<Map<String, dynamic>?> call(Map<String, dynamic> params) async {
    final affected = await DataBaseClient.getInstance().delete(params);
    return {'affected': affected};
  }

  static ServiceMethod createMethod() {
    return ServiceMethod(name, Delete().call, description)
      ..required('where', 'list', '[column, operator, value] — operators: =, !=, >, >=, <, <=, like, not like');
  }
}
