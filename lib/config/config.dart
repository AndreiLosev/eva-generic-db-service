import 'package:eva_generic_db_service/config/column.dart';
import 'package:eva_generic_db_service/config/db.dart';

class Config {
  final Db db;
  final TableSchema schema;

  Config(this.db, this.schema);

  factory Config.fromMap(Map map, String serviceId) {
    final columns = <ColumnDefinition>[];
    for (final item in map['columns'] as List) {
      columns.add(ColumnDefinition.fromMap(item as Map));
    }
    return Config(
      Db.fromString(
        map['db'] as String,
        unix: map['unix'] == true,
        ssl: map['ssl'] == true,
      ),
      TableSchema.fromServiceId(serviceId, columns),
    );
  }
}
