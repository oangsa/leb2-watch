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
/// Timed from the moment the request leaves rather than from the call that
/// asked for it, so credential reads and other on-device preflight work stay
/// out of the window. What remains is the exchange itself, which on a cold
/// connection still includes DNS and the TLS handshake — a tighter bound
/// discards the launch measurement that matters most. Half of this stays under
/// [clockSkewMinimumCorrection], so the deadband still absorbs the uncertainty
/// a slow reading carries.
const clockSkewMaximumRoundTrip = Duration(seconds: 5);

/// Smallest *movement* in the offset worth acting on.
///
/// Comfortably above the measurement's own uncertainty, so ordinary jitter
/// never moves the clock and a device that is merely a second out is left
/// alone.
///
/// Applied to the change rather than to the reading, so a device sitting near
/// this bound cannot flip between "corrected" and "uncorrected" on consecutive
/// responses — each flip would re-place every alarm the OS holds.
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
  // Reported as measured. The deadband belongs to [TrustedClock.adopt], which
  // applies it to the movement: clamping a small reading to zero here would
  // make a device sitting near the bound alternate between zero and the
  // reading, and every alternation reads as a correction worth applying.
  return skew;
}

/// A clock that reports backend time, using the device clock plus the latest
/// accepted [offset].
///
/// Held in memory only: the first backend response of a launch re-measures the
/// same offset within seconds, and nothing schedules before the first sync.
/// What alarms the OS already holds were placed under is durable and lives
/// beside the schedule state — see [onOffsetChanged].
final class TrustedClock {
  TrustedClock({
    DateTime Function()? deviceNow,
    Duration offset = Duration.zero,
    void Function(Duration offset)? onOffsetChanged,
  }) : _deviceNow = deviceNow ?? DateTime.now {
    _offset = offset;
    _onOffsetChanged = onOffsetChanged;
  }

  final DateTime Function() _deviceNow;
  void Function(Duration offset)? _onOffsetChanged;
  Duration _offset = Duration.zero;
  bool _measured = false;

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
  /// A reading that moves the offset by less than
  /// [clockSkewMinimumCorrection] is dropped whole rather than adopted
  /// quietly, so jitter neither shifts the clock nor reports a change.
  ///
  /// Anything already handed to the OS was placed against whatever offset was
  /// current then, so an accepted offset reports itself through
  /// `onOffsetChanged`. The first reading of a launch always reports: the
  /// in-memory offset starts at zero and carries no evidence of what the OS is
  /// already holding, so only the durable record can answer that, and the
  /// listener owns the comparison.
  void adopt(Duration offset) {
    if (offset.abs() > clockSkewMaximumCorrection) {
      return;
    }
    if (_measured && (offset - _offset).abs() < clockSkewMinimumCorrection) {
      return;
    }
    _measured = true;
    _offset = offset;
    _onOffsetChanged?.call(offset);
  }

  @override
  String toString() => 'TrustedClock(offset: $_offset)';
}
