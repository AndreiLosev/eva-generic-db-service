import 'dart:io';

import 'package:eva_generic_db_service/config/config.dart';
import 'package:eva_generic_db_service/db/data_base_client.dart';
import 'package:eva_generic_db_service/eapi/delete.dart';
import 'package:eva_generic_db_service/eapi/insert.dart';
import 'package:eva_generic_db_service/eapi/select.dart';
import 'package:eva_generic_db_service/eapi/update.dart';
import 'package:eva_sdk/eva_sdk.dart';
import 'package:eva_sdk/src/debug_log.dart';

const author = 'Losev Andrei';
const version = '1.0.0';
const description = 'Generic PostgreSQL CRUD service';

int exitCode = 1;

void main(List<String> arguments) async {
  DataBaseClient? dbc;
  try {
    final info = ServiceInfo(author, version, description)
      ..addMethod(Select.createMethod())
      ..addMethod(Insert.createMethod())
      ..addMethod(Update.createMethod())
      ..addMethod(Delete.createMethod());

    if (arguments.contains('--local')) {
      await svc().debugLoad(
        '/home/andrei/documents/my/eva-generic-db-service/example-config.yaml',
        'softkip.generic.db',
      );
      dbgInit('console');
    } else {
      await svc().load();
    }
    await svc().init(info);

    final config = Config.fromMap(svc().config.config, svc().config.id);
    dbc = DataBaseClient.getInstance(config);
    await dbc.connect();
    await dbc.makeTable();
    await svc().block();

    exitCode = 0;
  } catch (e) {
    svc().logger.error(e);
  } finally {
    await dbc?.disconnect();
    exit(exitCode);
  }
}
