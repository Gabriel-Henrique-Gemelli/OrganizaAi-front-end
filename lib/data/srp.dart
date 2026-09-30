import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'api_client.dart';

/// SRP-6a do Amazon Cognito (USER_SRP_AUTH): a senha nunca sai do aparelho, só a prova derivada dela.
class CognitoSrp {
  /// Primo seguro de 3072 bits (RFC 3526) que o Cognito usa, com gerador 2.
  static final BigInt _n = BigInt.parse(
    'FFFFFFFFFFFFFFFFC90FDAA22168C234C4C6628B80DC1CD129024E088A67CC74020BBEA63B139B22514A08798E3404DD'
    'EF9519B3CD3A431B302B0A6DF25F14374FE1356D6D51C245E485B576625E7EC6F44C42E9A637ED6B0BFF5CB6F406B7ED'
    'EE386BFB5A899FA5AE9F24117C4B1FE649286651ECE45B3DC2007CB8A163BF0598DA48361C55D39A69163FA8FD24CF5F'
    '83655D23DCA3AD961C62F356208552BB9ED529077096966D670C354E4ABC9804F1746C08CA18217C32905E462E36CE3B'
    'E39E772C180E86039B2783A2EC07A28FB5C55DF06F4C52C9DE2BCBF6955817183995497CEA956AE515D2261898FA0510'
    '15728E5A8AAAC42DAD33170D04507A33A85521ABDF1CBA64ECFB850458DBEF0A8AEA71575D060C7DB3970F85A6E1E4C7'
    'ABF5AE8CDB0933D71E8C94E04A25619DCEE3D2261AD2EE6BF12FFA06D98A0864D87602733EC86A64521F2B18177B200C'
    'BBE117577A615D6C770988C0BAD946E208E24FA074E5AB3143DB5BFCE0FD108E4B82D120A93AD2CAFFFFFFFFFFFFFFFF',
    radix: 16,
  );
  static final BigInt _g = BigInt.two;
  static final BigInt _k = _bigInt(_hashHex(_padHex(_n) + _padHex(_g)));

  final String poolName;
  final BigInt _a;
  final DateTime Function() _clock;

  /// [poolName] é o trecho do id do pool depois do "_" (ex.: `rGx2f3AxE`). [a] e [clock] só existem
  /// para tornar o cálculo reproduzível em teste.
  CognitoSrp(this.poolName, {BigInt? a, DateTime Function()? clock})
    : _a = a ?? _randomA(),
      _clock = clock ?? DateTime.now;

  BigInt get publicA => _g.modPow(_a, _n);
  String get publicAHex => publicA.toRadixString(16);

  /// Respostas do desafio PASSWORD_VERIFIER a partir dos parâmetros devolvidos pelo Cognito.
  Map<String, String> respond({
    required String userId,
    required String password,
    required String saltHex,
    required String srpBHex,
    required String secretBlock,
  }) {
    final b = _bigInt(srpBHex);
    if (b % _n == BigInt.zero) {
      throw ApiFailure('Resposta de autenticação inválida.');
    }
    final u = _bigInt(_hashHex(_padHex(publicA) + _padHex(b)));
    if (u == BigInt.zero) {
      throw ApiFailure('Resposta de autenticação inválida.');
    }
    final passwordHash = sha256
        .convert(utf8.encode('$poolName$userId:$password'))
        .toString();
    final x = _bigInt(_hashHex(_padHex(_bigInt(saltHex)) + passwordHash));
    final base = (b - _k * _g.modPow(x, _n)) % _n;
    final s = base.modPow(_a + u * x, _n);
    final key = _hkdf(_hexBytes(_padHex(s)), _hexBytes(_padHex(u)));
    final timestamp = _timestamp(_clock().toUtc());
    final message = BytesBuilder()
      ..add(utf8.encode(poolName))
      ..add(utf8.encode(userId))
      ..add(base64.decode(secretBlock))
      ..add(utf8.encode(timestamp));
    final signature = Hmac(sha256, key).convert(message.toBytes()).bytes;
    return {
      'USERNAME': userId,
      'PASSWORD_CLAIM_SECRET_BLOCK': secretBlock,
      'TIMESTAMP': timestamp,
      'PASSWORD_CLAIM_SIGNATURE': base64.encode(signature),
    };
  }

  static BigInt _randomA() {
    final random = Random.secure();
    final bytes = List<int>.generate(128, (_) => random.nextInt(256));
    return _bigInt(
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
    );
  }

  static BigInt _bigInt(String hex) => BigInt.parse(hex, radix: 16);

  /// Hexadecimal com número par de dígitos e sem bit de sinal, como o Cognito espera.
  static String _padHex(BigInt value) {
    var hex = value.toRadixString(16);
    if (hex.length.isOdd) {
      hex = '0$hex';
    } else if ('89abcdef'.contains(hex[0])) {
      hex = '00$hex';
    }
    return hex;
  }

  static Uint8List _hexBytes(String hex) => Uint8List.fromList([
    for (var i = 0; i < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ]);

  static String _hashHex(String hex) =>
      sha256.convert(_hexBytes(hex)).toString().padLeft(64, '0');

  static List<int> _hkdf(List<int> ikm, List<int> salt) {
    final prk = Hmac(sha256, salt).convert(ikm).bytes;
    final info = [...utf8.encode('Caldera Derived Key'), 1];
    return Hmac(sha256, prk).convert(info).bytes.sublist(0, 16);
  }

  static String _timestamp(DateTime t) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    String two(int v) => v.toString().padLeft(2, '0');
    return '${days[t.weekday - 1]} ${months[t.month - 1]} ${t.day} '
        '${two(t.hour)}:${two(t.minute)}:${two(t.second)} UTC ${t.year}';
  }
}
