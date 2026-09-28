import 'dart:convert';
import 'dart:typed_data';

String csvCell(Object? value) {
  var s = (value ?? '').toString();
  if (RegExp(r'^[\s]*[=+@\-\t\r]').hasMatch(s)) s = "'$s";
  return '"${s.replaceAll('"', '""')}"';
}

Uint8List csvBytes(List<List<Object?>> rows) => Uint8List.fromList(
  utf8.encode(
    '\uFEFF${rows.map((r) => r.map(csvCell).join(';')).join('\r\n')}',
  ),
);
