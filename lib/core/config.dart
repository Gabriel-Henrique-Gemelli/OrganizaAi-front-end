class AppConfig {
  static const brand = 'OrganizAI';
  static const defaultUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );
  static const cognitoIssuer = String.fromEnvironment(
    'COGNITO_ISSUER_URI',
    defaultValue:
        'https://cognito-idp.us-east-1.amazonaws.com/us-east-1_gdkHR3WCT',
  );
  static const cognitoClientId = String.fromEnvironment(
    'COGNITO_CLIENT_ID',
    defaultValue: '1v7oqsn5g97smst2hsrlhlhvep',
  );
  static const documentTypes = <String, String>{
    'pdf': 'application/pdf',
    'png': 'image/png',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'tif': 'image/tiff',
    'tiff': 'image/tiff',
    'xls': 'application/vnd.ms-excel',
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'xlsm': 'application/vnd.ms-excel.sheet.macroEnabled.12',
    'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'doc': 'application/msword',
    'txt': 'text/plain',
  };
  static const audioTypes = {
    'ogg': 'audio/ogg',
    'opus': 'audio/ogg',
    'webm': 'audio/webm',
  };
  static String extension(String name) => name.split('.').last.toLowerCase();
  static int maxBytes(String name) =>
      {'xls', 'xlsx', 'xlsm', 'doc', 'docx', 'txt'}.contains(extension(name))
      ? 20 * 1024 * 1024
      : 50 * 1024 * 1024;
  static String? validateUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        uri.host.isEmpty ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment)
      return 'Informe a URL HTTP(S) do servidor, sem credenciais ou parâmetros.';
    final octets = uri.host.split('.').map(int.tryParse).toList();
    final ipv4 =
        octets.length == 4 &&
        octets.every((v) => v != null && v >= 0 && v <= 255);
    final local =
        uri.host == 'localhost' ||
        uri.host == '::1' ||
        uri.host == '[::1]' ||
        ipv4 &&
            (octets[0] == 127 ||
                octets[0] == 10 ||
                octets[0] == 192 && octets[1] == 168 ||
                octets[0] == 172 && octets[1]! >= 16 && octets[1]! <= 31);
    if (uri.scheme != 'https' && !local)
      return 'Use HTTPS para servidores fora da rede local.';
    return null;
  }
}
