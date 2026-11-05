/// Formateo local corto de fechas de la biblioteca.
///
/// Sin `intl`: la app corre en la LAN de la sala y las etiquetas de
/// fecha son solo presentacion, en espanol, con las abreviaturas del
/// manual de la institucion.
library;

const _months = [
  'ene.',
  'feb.',
  'mar.',
  'abr.',
  'may.',
  'jun.',
  'jul.',
  'ago.',
  'sept.',
  'oct.',
  'nov.',
  'dic.',
];

/// Fecha corta local: `19 oct. 2026`.
String shortLocalDate(DateTime date) {
  final local = date.toLocal();
  return '${local.day} ${_months[local.month - 1]} ${local.year}';
}

/// Fecha + hora local: `19 oct. 2026, 14:05`.
String localDateTime(DateTime date) {
  final local = date.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${shortLocalDate(date)}, ${two(local.hour)}:${two(local.minute)}';
}
