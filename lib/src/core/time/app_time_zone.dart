/// The time zone every user-facing wall clock in the app is expressed in.
///
/// LEB2 publishes deadlines without an offset, so the app has to supply one to
/// turn a published wall clock into an instant and back. Routing that through
/// [appTimeZone] keeps the choice in a single place.
///
/// Correct only for zones without daylight saving. A zone that observes DST
/// needs an implementation backed by a zone database rather than a wider
/// [offset], and every call site here goes through the same two methods.
final class FixedOffsetTimeZone {
  const FixedOffsetTimeZone({
    required this.offset,
    required this.label,
    required this.displayName,
  });

  final Duration offset;

  /// Short offset label shown beside a rendered wall clock, e.g. `GMT+7`.
  final String label;

  /// Human name for the zone, e.g. `Bangkok`.
  final String displayName;

  /// The wall clock this zone shows for [instantUtc].
  ///
  /// Read the result for its calendar fields only. Dart has no naive date
  /// type, so the returned value keeps a UTC flag it no longer deserves:
  /// converting it again with `toLocal` or `toUtc` shifts it a second time.
  DateTime wallTime(DateTime instantUtc) => instantUtc.toUtc().add(offset);

  /// The UTC instant at which this zone shows [wallTime]'s fields.
  ///
  /// [wallTime] is read for its calendar fields only; its own UTC flag is
  /// ignored.
  DateTime instantAt(DateTime wallTime) => DateTime.utc(
    wallTime.year,
    wallTime.month,
    wallTime.day,
    wallTime.hour,
    wallTime.minute,
    wallTime.second,
    wallTime.millisecond,
    wallTime.microsecond,
  ).subtract(offset);
}

/// The zone the app currently ships with.
///
/// LEB2 serves one university in Thailand, which has not observed daylight
/// saving since 1952, so a fixed offset is exact here.
const appTimeZone = FixedOffsetTimeZone(
  offset: Duration(hours: 7),
  label: 'GMT+7',
  displayName: 'Bangkok',
);
