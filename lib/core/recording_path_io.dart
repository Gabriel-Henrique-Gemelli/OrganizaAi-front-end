import 'dart:io';

import 'package:path_provider/path_provider.dart';

Future<String> recordingPath() async =>
    '${(await getTemporaryDirectory()).path}/organizai-${DateTime.now().microsecondsSinceEpoch}.ogg';
Future<void> removeRecording(String path) async {
  final f = File(path);
  if (await f.exists()) await f.delete();
}
