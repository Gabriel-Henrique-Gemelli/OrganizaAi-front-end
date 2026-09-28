$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
if (!(Test-Path 'config.json')) { throw 'Copie config.example.json para config.json e informe API_BASE_URL antes de iniciar.' }
$config = Get-Content 'config.json' -Raw | ConvertFrom-Json
if ([string]::IsNullOrWhiteSpace($config.API_BASE_URL)) { throw 'Informe API_BASE_URL no config.json. Use a URL da API Java.' }
flutter pub get
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
dart tool/bootstrap.dart
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
flutter run --dart-define-from-file=config.json @args
