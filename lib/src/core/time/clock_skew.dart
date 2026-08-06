/// Correction applied to this device's clock so scheduling uses backend time.
///
/// Reminders are scheduled against absolute instants, so a device time zone
/// set wrongly costs nothing — but a device *clock* set wrongly shifts every
/// reminder by the same error, silently. The backend `Date` header is the one
/// clock both sides agree on, so the difference against it is measured on each
/// response and applied to the scheduling clock.
library;

/// Longest round trip that still yields a usable measurement.
///
/// The `Date` header carries whole seconds and is stamped at response time,
/// not at the round-trip midpoint, so the measurement is already uncertain by
/// about a second. A slow response widens that by half the round trip, and
/// past this bound the reading says less than it costs to apply.
///
/// Measured across the whole exchange, which on a cold connection includes
/// DNS, the TLS handshake and any token refresh — a tighter bound discards
/// the launch measurement that matters most. Half of this stays under
/// [clockSkewMinimumCorrection], so the deadband still absorbs the
/// uncertainty a slow reading carries.
const clockSkewMaximumRoundTrip = Duration(seconds: 5);

/// Smallest skew worth correcting.
///
/// Comfortably above the measurement's own uncertainty, so ordinary jitter
/// never moves the clock and a device that is merely a second out is left
/// alone.
const clockSkewMinimumCorrection = Duration(seconds: 5);

/// Largest skew that is treated as a device-clock error at all.
///
/// A reading past this says something is wrong the app cannot silently repair
/// — a broken proxy, a spoofed header, a clock set to another year. Adopting
/// it would suppress every reminder, so it is discarded instead.
const clockSkewMaximumCorrection = Duration(hours: 12);

/// The device-clock error implied by one response, or null when the exchange
/// cannot support a reading.
///
/// [serverUtc] comes from the response `Date` header; [sentAtUtc] and
/// [receivedAtUtc] are read from the device clock either side of the request,
/// so the backend instant is compared against the round-trip midpoint rather
/// than against either edge.
Duration? resolveClockSkew({
  required DateTime sentAtUtc,
  required DateTime receivedAtUtc,
  required DateTime serverUtc,
}) {
  final sent = sentAtUtc.toUtc();
  final received = receivedAtUtc.toUtc();
  final roundTrip = received.difference(sent);
  if (roundTrip.isNegative || roundTrip > clockSkewMaximumRoundTrip) {
    return null;
  }
  final deviceMidpoint = sent.add(roundTrip ~/ 2);
  final skew = serverUtc.toUtc().difference(deviceMidpoint);
  if (skew.abs() > clockSkewMaximumCorrection) {
    return null;
  }
  return skew.abs() < clockSkewMinimumCorrection ? Duration.zero : skew;
}

/// A clock that reports backend time, using the device clock plus the latest
/// accepted [offset].
///
/// Held in memory only: the first backend response of a launch re-measures the
/// same offset within seconds, and nothing schedules before the first sync.
final class TrustedClock {
  TrustedClock({
    DateTime Function()? deviceNow,
    Duration offset = Duration.zero,
    void Function()? onOffsetChanged,
  }) : _deviceNow = deviceNow ?? DateTime.now {
    _onOffsetChanged = onOffsetChanged;
    _offset = offset;
  }

  final DateTime Function() _deviceNow;
  late final void Function()? _onOffsetChanged;
  late Duration _offset;

  /// True time minus device time, so `deviceNow + offset == trueNow`.
  Duration get offset => _offset;

  DateTime nowUtc() => _deviceNow().toUtc().add(_offset);

  /// The device-clock instant an OS alarm must carry to fire at
  /// [trueInstantUtc].
  ///
  /// The platform fires alarms by the device clock, which is the clock being
  /// corrected — so an instant expressed in backend time has to be moved back
  /// by [offset] before it is handed over, or the correction never reaches the
  /// only decision it exists to fix.
  DateTime deviceInstantFor(DateTime trueInstantUtc) =>
      trueInstantUtc.toUtc().subtract(_offset);

  /// Accepts a freshly measured [offset].
  ///
  /// A reading past [clockSkewMaximumCorrection] is discarded outright: the
  /// last accepted offset is a better answer than pretending the device agrees
  /// with the backend.
  ///
  /// Anything already handed to the OS was placed against the previous offset
  /// and now fires at the wrong instant, so a move worth correcting reports
  /// itself through `onOffsetChanged`.
  void adopt(Duration offset) {
    if (offset.abs() > clockSkewMaximumCorrection) {
      return;
    }
    final previous = _offset;
    _offset = offset;
    if ((offset - previous).abs() >= clockSkewMinimumCorrection) {
      _onOffsetChanged?.call();
    }
  }

  @override
  String toString() => 'TrustedClock(offset: $_offset)';
}
