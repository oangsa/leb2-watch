/// Renders the user-facing semester label.
///
/// The backend name is authoritative when present. The numeric identifier is
/// only a fallback so a semester never renders as an empty string.
String formatSemesterLabel({String? name, int? id}) {
  final trimmed = name?.trim();
  if (trimmed != null && trimmed.isNotEmpty) {
    return trimmed.toLowerCase().startsWith('semester ')
        ? trimmed
        : 'Semester $trimmed';
  }
  return id == null ? 'Semester' : 'Semester $id';
}
