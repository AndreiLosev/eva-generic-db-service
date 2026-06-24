import 'package:eva_generic_db_service/eva_generic_db_service.dart';
import 'package:test/test.dart';

void main() {
  test('TableSchema exports', () {
    final schema = TableSchema.fromServiceId('test.service', [
      ColumnDefinition(name: 'id', type: 'SERIAL', primaryKey: true),
    ]);
    expect(schema.tableName, 'test_service');
  });
}
