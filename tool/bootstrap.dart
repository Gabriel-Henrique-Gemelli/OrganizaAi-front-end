// Execute: dart tool/bootstrap.dart
// Gera runners oficiais com a versão Flutter instalada e aplica permissões.
import 'dart:io';

Future<void> run(List<String> args) async {
  final p = await Process.start(
    Platform.isWindows ? 'flutter.bat' : 'flutter',
    args,
    runInShell: Platform.isWindows,
    mode: ProcessStartMode.inheritStdio,
  );
  final code = await p.exitCode;
  if (code != 0) exit(code);
}

void transform(String path, String Function(String) fn) {
  final f = File(path);
  if (f.existsSync()) f.writeAsStringSync(fn(f.readAsStringSync()));
}

void plist(String path, Map<String, String> entries) {
  transform(path, (s) {
    for (final e in entries.entries) {
      if (!s.contains('<key>${e.key}</key>')) {
        final end = s.lastIndexOf('</dict>');
        s = '${s.substring(0, end)}\t<key>${e.key}</key>\n\t${e.value}\n${s.substring(end)}';
      }
    }
    return s;
  });
}

Future<void> main() async {
  if (!File('pubspec.yaml').existsSync()) {
    stderr.writeln('Execute na pasta organizai_flutter.');
    exit(1);
  }
  await run([
    'create',
    '--no-pub',
    '--project-name',
    'organizai_flutter',
    '--org',
    'br.com.organizai',
    '--platforms',
    'android,ios,windows,macos,linux,web',
    '.',
  ]);
  transform('android/app/src/main/AndroidManifest.xml', (s) {
    for (final p in ['INTERNET', 'RECORD_AUDIO', 'CAMERA']) {
      if (!s.contains('android.permission.$p'))
        s = s.replaceFirst(
          '<application',
          '<uses-permission android:name="android.permission.$p"/>\n    <application',
        );
    }
    return s.replaceAll(
      'android:label="organizai_flutter"',
      'android:label="OrganizAI"',
    );
  });
  // HTTP liberado somente na variante debug para desenvolvimento em LAN.
  final debug = File('android/app/src/debug/AndroidManifest.xml');
  debug.parent.createSync(recursive: true);
  debug.writeAsStringSync(
    '<manifest xmlns:android="http://schemas.android.com/apk/res/android"><uses-permission android:name="android.permission.INTERNET"/><application android:usesCleartextTraffic="true"/></manifest>\n',
  );
  transform(
    'android/app/build.gradle.kts',
    (s) => s.replaceAll('minSdk = flutter.minSdkVersion', 'minSdk = 24'),
  );
  plist('ios/Runner/Info.plist', {
    'NSMicrophoneUsageDescription':
        '<string>Gravar o diário de obra por voz.</string>',
    'NSCameraUsageDescription':
        '<string>Fotografar documentos da obra.</string>',
    'NSPhotoLibraryUsageDescription':
        '<string>Selecionar fotos e documentos da obra.</string>',
    'NSLocalNetworkUsageDescription':
        '<string>Conectar ao servidor da obra na rede local.</string>',
  });
  plist('macos/Runner/Info.plist', {
    'NSMicrophoneUsageDescription':
        '<string>Gravar o diário de obra por voz.</string>',
  });
  for (final name in ['DebugProfile', 'Release']) {
    plist('macos/Runner/$name.entitlements', {
      'com.apple.security.network.client': '<true/>',
      'com.apple.security.device.audio-input': '<true/>',
      'com.apple.security.files.user-selected.read-write': '<true/>',
    });
  }
  transform(
    'web/index.html',
    (s) => s
        .replaceAll(
          '<title>organizai_flutter</title>',
          '<title>OrganizAI</title>',
        )
        .replaceAll('A new Flutter project.', 'Gestão documental de obras.')
        .replaceFirst('<html>', '<html lang="pt-BR">'),
  );
  await run(['pub', 'get']);
  stdout.writeln(
    '\nProjeto preparado. Execute: flutter run -d windows (ou macos, linux, chrome, ID do celular).',
  );
}
