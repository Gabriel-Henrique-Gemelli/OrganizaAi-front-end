"""Login SRP (USER_SRP_AUTH) no Cognito, em Python, para os testes de integração contra a API."""
import base64, hashlib, hmac, json, os, datetime, requests

N_HEX = ("FFFFFFFFFFFFFFFFC90FDAA22168C234C4C6628B80DC1CD129024E088A67CC74020BBEA63B139B22514A08798E3404DD"
 "EF9519B3CD3A431B302B0A6DF25F14374FE1356D6D51C245E485B576625E7EC6F44C42E9A637ED6B0BFF5CB6F406B7ED"
 "EE386BFB5A899FA5AE9F24117C4B1FE649286651ECE45B3DC2007CB8A163BF0598DA48361C55D39A69163FA8FD24CF5F"
 "83655D23DCA3AD961C62F356208552BB9ED529077096966D670C354E4ABC9804F1746C08CA18217C32905E462E36CE3B"
 "E39E772C180E86039B2783A2EC07A28FB5C55DF06F4C52C9DE2BCBF6955817183995497CEA956AE515D2261898FA0510"
 "15728E5A8AAAC42DAD33170D04507A33A85521ABDF1CBA64ECFB850458DBEF0A8AEA71575D060C7DB3970F85A6E1E4C7"
 "ABF5AE8CDB0933D71E8C94E04A25619DCEE3D2261AD2EE6BF12FFA06D98A0864D87602733EC86A64521F2B18177B200C"
 "BBE117577A615D6C770988C0BAD946E208E24FA074E5AB3143DB5BFCE0FD108E4B82D120A93AD2CAFFFFFFFFFFFFFFFF")
N = int(N_HEX, 16)
G = 2
POOL = "us-east-1_rGx2f3AxE"
CLIENT = "2r86sk9kud3k8444dnalptct8k"
POOLNAME = POOL.split("_")[1]
URL = "https://cognito-idp.us-east-1.amazonaws.com/"


def pad(x):
    h = format(x, "x")
    if len(h) % 2:
        h = "0" + h
    elif h[0] in "89abcdef":
        h = "00" + h
    return h


def hhex(h):
    return hashlib.sha256(bytes.fromhex(h)).hexdigest().rjust(64, "0")


K = int(hhex(pad(N) + pad(G)), 16)


def call(action, body):
    r = requests.post(URL, data=json.dumps(body), headers={
        "Content-Type": "application/x-amz-json-1.1",
        "X-Amz-Target": "AWSCognitoIdentityProviderService." + action}, timeout=20)
    return r.status_code, r.json()


def login(username, password):
    """Devolve AuthenticationResult (AccessToken, IdToken, RefreshToken). A senha nunca é enviada."""
    a = int.from_bytes(os.urandom(128), "big")
    A = pow(G, a, N)
    st, j = call("InitiateAuth", {"ClientId": CLIENT, "AuthFlow": "USER_SRP_AUTH",
                                  "AuthParameters": {"USERNAME": username, "SRP_A": format(A, "x")}})
    if st != 200:
        raise RuntimeError(f"InitiateAuth {st} {j.get('__type')}")
    p = j["ChallengeParameters"]
    uid = p["USER_ID_FOR_SRP"]
    B = int(p["SRP_B"], 16)
    salt = int(p["SALT"], 16)
    u = int(hhex(pad(A) + pad(B)), 16)
    x = int(hhex(pad(salt) + hashlib.sha256(f"{POOLNAME}{uid}:{password}".encode()).hexdigest()), 16)
    s = pow((B - K * pow(G, x, N)) % N, a + u * x, N)
    prk = hmac.new(bytes.fromhex(pad(u)), bytes.fromhex(pad(s)), hashlib.sha256).digest()
    key = hmac.new(prk, b"Caldera Derived Key\x01", hashlib.sha256).digest()[:16]
    ts = datetime.datetime.now(datetime.timezone.utc).strftime("%a %b %-d %H:%M:%S UTC %Y")
    msg = POOLNAME.encode() + uid.encode() + base64.b64decode(p["SECRET_BLOCK"]) + ts.encode()
    sig = base64.b64encode(hmac.new(key, msg, hashlib.sha256).digest()).decode()
    st, j = call("RespondToAuthChallenge", {
        "ClientId": CLIENT, "ChallengeName": "PASSWORD_VERIFIER",
        "ChallengeResponses": {"USERNAME": uid, "PASSWORD_CLAIM_SECRET_BLOCK": p["SECRET_BLOCK"],
                               "TIMESTAMP": ts, "PASSWORD_CLAIM_SIGNATURE": sig}})
    if st != 200:
        raise RuntimeError(f"Respond {st} {j.get('__type')}")
    return j["AuthenticationResult"]
