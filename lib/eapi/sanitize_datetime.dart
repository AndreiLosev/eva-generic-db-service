void sanitizeDateTime(List<Map<String, dynamic>> rows) {
  for (final (i, row) in rows.indexed) {
    for (final key in row.keys) {
      if (row[key] is DateTime) {
        rows[i][key] = (row[key] as DateTime).toIso8601String();
      }
    }
  }
}
