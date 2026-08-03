import 'package:drift/drift.dart';

/// Stores application-owned timestamps as UTC Unix epoch milliseconds.
class UtcDateTimeConverter extends TypeConverter<DateTime, int> {
  const UtcDateTimeConverter();

  @override
  DateTime fromSql(int fromDb) {
    return DateTime.fromMillisecondsSinceEpoch(fromDb, isUtc: true);
  }

  @override
  int toSql(DateTime value) {
    return value.toUtc().millisecondsSinceEpoch;
  }
}
