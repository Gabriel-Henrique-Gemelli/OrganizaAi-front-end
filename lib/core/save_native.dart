import 'dart:io';
import 'dart:typed_data';

Future<void> ensureDesktopSave(String? path, Uint8List bytes) async {
  if (path != null &&
      (Platform.isWindows || Platform.isLinux || Platform.isMacOS))
    await File(path).writeAsBytes(bytes, flush: true);
}
