/// LEB2 deadlines are published in Bangkok time, so every user-facing
/// timestamp renders in GMT+7 regardless of the device time zone.
const bangkokUtcOffset = Duration(hours: 7);

/// Converts a UTC instant to the Bangkok wall-clock time that represents it.
///
/// The result is a naive [DateTime] whose fields are the GMT+7 wall clock. It
/// is meant for display only and must not be converted again.
DateTime bangkokWallTime(DateTime instant) =>
    instant.toUtc().add(bangkokUtcOffset);
