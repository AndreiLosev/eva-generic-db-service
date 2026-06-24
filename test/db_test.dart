import 'package:eva_generic_db_service/config/db.dart';
import 'package:test/test.dart';

void main() {
  group('Db.fromString', () {
    test('parses connection string with database in path', () {
      final db = Db.fromString('postgres://user1:pass1@127.0.0.1:5432/eva-db');

      expect(db.host, '127.0.0.1');
      expect(db.port, 5432);
      expect(db.user, 'user1');
      expect(db.password, 'pass1');
      expect(db.db, 'eva-db');
      expect(db.unixSocket, isFalse);
      expect(db.ssl, isFalse);
    });

    test('unix and ssl from separate config params', () {
      final db = Db.fromString(
        'postgres://user1:pass1@127.0.0.1:5432/eva-db',
        unix: true,
        ssl: true,
      );

      expect(db.unixSocket, isTrue);
      expect(db.ssl, isTrue);
    });

    test('requires database name in connection string', () {
      expect(
        () => Db.fromString('postgres://user1:pass1@127.0.0.1:5432/'),
        throwsException,
      );
    });
  });
}
