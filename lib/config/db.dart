class Db {
  static const supportedDD = ['postgres'];

  final String host;
  final int port;
  final String db;
  final String user;
  final String password;
  final bool unixSocket;
  final bool ssl;

  Db(
    this.host,
    this.port,
    this.db,
    this.user,
    this.password,
    this.unixSocket,
    this.ssl,
  );

  factory Db.fromString(
    String conString, {
    bool unix = false,
    bool ssl = false,
  }) {
    final pars = Uri.parse(conString);
    if (!supportedDD.contains(pars.scheme)) {
      throw Exception('database: ${pars.scheme} not supported');
    }
    final parts = pars.userInfo.split(':');
    final user = parts.first;
    final password = parts.length > 1 ? parts.sublist(1).join(':') : '';
    if (pars.pathSegments.isEmpty) {
      throw Exception('database name is required in connection string');
    }
    final dbName = pars.pathSegments.last;
    return Db(
      pars.host,
      pars.hasPort ? pars.port : 5432,
      dbName,
      user,
      password,
      unix,
      ssl,
    );
  }
}
