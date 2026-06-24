import 'package:eva_generic_db_service/db/data_base_client.dart';
import 'package:eva_sdk/eva_sdk.dart';

class Insert {
  static const name = 'insert';
  static const description = 'insert row into table';

  Future<Map<String, dynamic>?> call(Map<String, dynamic> params) async {
    return DataBaseClient.getInstance().insert(params);
  }

  static ServiceMethod createMethod() {
    return ServiceMethod(name, Insert().call, description)
      ..required('values', 'dict', 'column name to value map');
  }
}
