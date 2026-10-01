"""Testes de integração da API do EC2, na perspectiva das rotas que o front usa.

Uso: python3 run_api_tests.py <fase> [<fase> ...]
Fases: p0 (fumaça/auth/CORS), p1 (obras), p2 (documentos), p3 (diário+clima síncronos),
       p4 (assíncronos [W]), p5 (assistente), p7 (rate limit)
Senhas: ~/.config/organizai-e2e/pw.json (fora do repo). Fixtures: ~/.cache/organizai-e2e/fx.
Estado (IDs criados) em state.json e resultados em results.json, nesta pasta (ignorados pelo git).
ATENÇÃO fail2ban: o EC2 bane o IP após 5 respostas 400 em 10 min (jail nginx-bad-request);
os casos que devolvem 400 passam por badguard() e respeitam no máximo 3 por janela.
"""
import base64, hashlib, json, os, sys, time, uuid
import requests
import cog

API = "https://api.organizaii.com.br"
HERE = os.path.dirname(os.path.abspath(__file__))
FX = os.path.expanduser("~/.cache/organizai-e2e/fx")
PW = json.load(open(os.path.expanduser("~/.config/organizai-e2e/pw.json")))
ORIGIN = "http://localhost:8081"
ADMIN = ("teste@organizai.dev", PW["admin"])
STATE_F = os.path.join(HERE, "state.json")
RES_F = os.path.join(HERE, "results.json")
state = json.load(open(STATE_F)) if os.path.exists(STATE_F) else {}
results = json.load(open(RES_F)) if os.path.exists(RES_F) else []
_tok = {}
_bucket = {}  # role -> [timestamps] do balde UPLOAD_URL (30/min)
_bad = []  # timestamps de chamadas que devem devolver 400


def badguard():
    while len([t for t in _bad if t > time.time() - 600]) >= 2:
        oldest = min(t for t in _bad if t > time.time() - 600)
        wait = oldest + 690 - time.time()
        print(f"   (pausa {wait:.0f}s para respeitar o jail nginx-bad-request)", flush=True)
        time.sleep(max(1, wait))
    _bad.append(time.time())


def save():
    json.dump(state, open(STATE_F, "w"), indent=1)
    json.dump(results, open(RES_F, "w"), indent=1, ensure_ascii=False)


def creds(role):
    return ADMIN if role == "admin" else (f"teste-{role}", PW[role])


def token(role, kind="AccessToken"):
    t = _tok.get(role)
    if not t or t["exp"] < time.time() + 90:
        r = cog.login(*creds(role))
        p = r["AccessToken"].split(".")[1]
        p += "=" * (-len(p) % 4)
        _tok[role] = {"r": r, "exp": json.loads(base64.urlsafe_b64decode(p))["exp"]}
    return _tok[role]["r"][kind]


def guard(role, path):
    """Espera o balde UPLOAD_URL (30/min por usuário) para não estourar sem querer."""
    if "upload-url" in path or "confirmar-upload" in path:
        ts = [t for t in _bucket.get(role, []) if t > time.time() - 60]
        if len(ts) >= 27:
            time.sleep(max(1, 61 - (time.time() - ts[0])))
            ts = [t for t in ts if t > time.time() - 60]
        ts.append(time.time())
        _bucket[role] = ts


def call(role, method, path, body=None, headers=None, raw=None, auth=True, origin=True, params=None, bad=False):
    if bad:
        badguard()
    h = {}
    if origin:
        h["Origin"] = ORIGIN
    if auth:
        h["Authorization"] = "Bearer " + (role if role and role.count(".") == 2 else token(role))
    if headers:
        h.update(headers)
    if role and role.count(".") != 2:
        guard(role, path)
    kw = {"headers": h, "timeout": 40, "params": params}
    if raw is not None:
        kw["data"] = raw
    elif body is not None:
        kw["json"] = body
    return requests.request(method, API + path, **kw)


def brief(r):
    try:
        j = r.json()
        if isinstance(j, dict):
            if "detail" in j or "title" in j:
                return f"{j.get('title')}: {str(j.get('detail'))[:110]}"
            return json.dumps({k: (str(v)[:40]) for k, v in list(j.items())[:6]}, ensure_ascii=False)[:150]
        return str(j)[:100]
    except Exception:
        return (r.text or "")[:100].replace("\n", " ")


def rec(tid, desc, r, exp, note="", register=False):
    exp = exp if isinstance(exp, (list, tuple, set)) else [exp]
    got = r.status_code if hasattr(r, "status_code") else r
    ok = got in exp
    entry = {"id": tid, "desc": desc, "exp": list(exp), "got": got, "ok": ok, "register": register,
             "note": (note + " | " + brief(r)) if hasattr(r, "status_code") else note}
    results[:] = [e for e in results if e["id"] != tid] + [entry]
    flag = "PASS" if ok else ("REGISTRAR" if register else "FAIL")
    print(f"{flag:9} {tid:6} {desc[:60]:60} exp={list(exp)} got={got} {entry['note'][:90]}", flush=True)
    save()
    return ok


def sha(b):
    return hashlib.sha256(b).hexdigest()


def upload_doc(role, project, name, ctype, path, confirm=True, size=None, put=True, content=None):
    data = content if content is not None else open(os.path.join(FX, path), "rb").read()
    r = call(role, "POST", "/api/documentos/upload-url",
             {"projectId": project, "nomeArquivo": name, "contentType": ctype,
              "tamanhoBytes": size if size is not None else len(data)})
    if r.status_code != 201:
        return r, None, None
    j = r.json()
    pr = requests.put(j["urlUpload"], data=data, headers=j["headers"], timeout=60) if put else None
    cr = None
    if confirm:
        cr = call(role, "POST", f"/api/documentos/{j['documentoId']}/versoes/{j['versionId']}/confirmar-upload",
                  {"sha256": sha(data)})
    return r, pr, cr


def upload_audio(role, project, path, ctype="audio/webm", confirm=True, put=True, size=None, content=None, ar="[TESTE] Engenheiro"):
    data = content if content is not None else open(os.path.join(FX, path), "rb").read()
    r = call(role, "POST", "/api/diario/upload-url",
             {"projectId": project, "entryDate": time.strftime("%Y-%m-%d"), "authorRole": ar,
              "contentType": ctype, "tamanhoBytes": size if size is not None else len(data)})
    if r.status_code != 201:
        return r, None, None
    j = r.json()
    pr = requests.put(j["urlUpload"], data=data, headers=j["headers"], timeout=60) if put else None
    cr = call(role, "POST", f"/api/diario/{j['diarioId']}/confirmar-upload") if confirm else None
    return r, pr, cr


def b64(o):
    return base64.urlsafe_b64encode(json.dumps(o).encode()).decode().rstrip("=")


def obra(role, body, bad=False):
    return call(role, "POST", "/api/obras", body, bad=bad)


def skip(tid, desc, why):
    results[:] = [e for e in results if e["id"] != tid] + [{"id": tid, "desc": desc, "exp": [], "got": None, "ok": True, "register": False, "note": "NAO EXECUTADO: " + why, "skipped": True}]


# ---------------------------------------------------------------- p0
def p0():
    print("== p0 fumaça / auth / CORS")
    r = requests.get(API + "/actuator/health", timeout=20)
    rec("H01", "health sem token", r, 200)
    r = call("admin", "GET", "/api/conta")
    rec("A01", "GET /api/conta admin", r, 200)
    if r.status_code == 200:
        j = r.json()
        rec("A01b", "conta: org/roles/company", 200 if j.get("organizationId") == "00000000-0000-0000-0000-000000000001" and j.get("roles") == ["ADMIN"] and j.get("company") else 0, 200, str({k: j.get(k) for k in ("company", "roles")}))
    r = call(None, "GET", "/api/conta", auth=False)
    rec("A02", "sem Authorization", r, 401)
    rec("A02b", "WWW-Authenticate: Bearer", 200 if "Bearer" in r.headers.get("WWW-Authenticate", "") else 0, 200)
    t = token("admin")
    h, p, s = t.split(".")
    bad = h + "." + p + "." + ("A" if s[0] != "A" else "B") + s[1:]
    rec("A03", "assinatura adulterada", call(bad, "GET", "/api/conta"), 401)
    rec("A03b", "alg=none", call(b64({"alg": "none", "typ": "JWT"}) + "." + p + ".", "GET", "/api/conta"), 401)
    rec("A04", "ID token no lugar do access", call(token("admin", "IdToken"), "GET", "/api/conta"), 401)
    payload = json.loads(base64.urlsafe_b64decode(p + "=" * (-len(p) % 4)))
    payload["exp"] = int(time.time()) - 7200
    rec("A05", "token expirado forjado", call(h + "." + b64(payload) + "." + s, "GET", "/api/conta"), 401)
    rec("A05b", "Bearer lixo", call("abc.def.ghi", "GET", "/api/conta"), 401)
    rec("A05c", "Basic no lugar de Bearer", call(None, "GET", "/api/conta", auth=False, headers={"Authorization": "Basic YTpi"}), 401)
    for tid, org, desc in [("A07", ORIGIN, "preflight origem permitida"), ("A08", "https://evil.example", "preflight origem estranha")]:
        r = requests.options(API + "/api/obras", headers={"Origin": org, "Access-Control-Request-Method": "PATCH",
                             "Access-Control-Request-Headers": "authorization,content-type"}, timeout=20)
        acao = r.headers.get("Access-Control-Allow-Origin")
        if tid == "A07":
            rec(tid, desc, r, 200, f"ACAO={acao} creds={r.headers.get('Access-Control-Allow-Credentials')}")
            rec("A07b", "ACAO igual à origem, sem credenciais", 200 if acao == ORIGIN and not r.headers.get("Access-Control-Allow-Credentials") else 0, 200)
        else:
            rec(tid, desc, r, 403, f"ACAO={acao}")
            rec("A08b", "sem ACAO para origem estranha", 200 if not acao else 0, 200)
    r = requests.options(API + "/api/obras", headers={"Origin": ORIGIN, "Access-Control-Request-Method": "DELETE"}, timeout=20)
    rec("A09", "preflight com DELETE", r, [403, 405])
    r = call("admin", "GET", "/api/obras", params={"page": 0})
    rec("A10", "HSTS presente", 200 if "max-age" in r.headers.get("Strict-Transport-Security", "") else 0, 200, r.headers.get("Strict-Transport-Security", "")[:40])
    rec("A12a", "rota inexistente", call("admin", "GET", "/api/xyz"), [404], register=True)
    rec("A12b", "PATCH /api/conta", call("admin", "PATCH", "/api/conta", {}), [405], register=True)
    rec("A12c", "Content-Type text/plain em POST /api/obras", call("admin", "POST", "/api/obras", raw="x", headers={"Content-Type": "text/plain"}), [415], register=True)
    rec("A12d", "/actuator/env sem token", requests.get(API + "/actuator/env", timeout=20), [401, 403, 404])


# ---------------------------------------------------------------- p1
def p1():
    print("== p1 obras")
    r = call("admin", "GET", "/api/obras", params={"page": 0})
    rec("O01", "GET /api/obras", r, 200)
    ok = r.status_code == 200 and any(o["id"] == "00000000-0000-0000-0000-000000000002" for o in r.json()["items"])
    rec("O01b", "lista contém a obra seed", 200 if ok else 0, 200)
    rec("O02a", "page=-1", call("admin", "GET", "/api/obras", params={"page": -1}, bad=True), 400)
    for role in ("gestor", "colaborador", "revisor", "auditor"):
        rec(f"O03-{role}", f"{role} lista obras", call(role, "GET", "/api/obras", params={"page": 0}), 200)
    r = obra("admin", {"name": "[TESTE] Obra A"})
    rec("O04", "POST só com nome", r, 201)
    if r.status_code == 201:
        j = r.json()
        state["obraA"] = j["id"]
        rec("O04b", "executora=org, responsável=usuário, sem datas", 200 if j["executor"] and j["responsible"] == "Usuário Teste" and j["plannedStartDate"] == "" else 0, 200, f"exec={j['executor']} resp={j['responsible']}")
    r = obra("admin", {"name": "[TESTE] Obra B clima", "state": "SP", "city": "Sao Paulo", "latitude": -23.5505, "longitude": -46.6333, "plannedStartDate": "2026-10-01"})
    rec("O05", "POST com coordenadas", r, 201)
    if r.status_code == 201:
        state["obraB"] = r.json()["id"]
        rec("O05b", "coordenadas devolvidas", 200 if r.json().get("latitude") is not None else 0, 200)
    save()
    rec("O06", "name vazio", obra("admin", {"name": ""}, bad=True), 400)
    rec("O07b", "data 01/10/2026", obra("admin", {"name": "[TESTE] x", "plannedStartDate": "01/10/2026"}, bad=True), 400)
    rec("O07d", "type inválido", obra("admin", {"name": "[TESTE] x", "type": "CASA"}, bad=True), 400)
    r = obra("admin", {"name": "[TESTE] lat1234", "latitude": 1234.5}, bad=True)
    rec("O10b", "latitude=1234.5 (estoura numeric(9,6)?)", r, 400, register=True)
    if r.status_code == 201:
        state.setdefault("extra_obras", []).append(r.json()["id"])
    r = obra("admin", {"name": "[TESTE] mass", "organizationId": str(uuid.uuid4()), "id": str(uuid.uuid4())})
    rec("M01", "mass assignment: organizationId/id ignorados", r, 201)
    if r.status_code == 201:
        state.setdefault("extra_obras", []).append(r.json()["id"])
    for role in ("colaborador", "revisor", "auditor"):
        rec(f"O11-{role}", f"{role} não cria obra", obra(role, {"name": "[TESTE] nao"}), 403)
        rec(f"O15-{role}", f"{role} não edita obra", call(role, "PATCH", f"/api/obras/{state['obraA']}", {"name": "[TESTE] nao"}), 403)
    r = call("gestor", "POST", "/api/obras", {"name": "[TESTE] Obra do gestor"})
    rec("O11g", "gestor cria obra", r, 201)
    if r.status_code == 201:
        state.setdefault("extra_obras", []).append(r.json()["id"])
    r = call("gestor", "PATCH", f"/api/obras/{state['obraA']}", {"name": "[TESTE] Obra A editada", "city": "Curitiba", "state": "PR"})
    rec("O12", "gestor edita obra", r, 200)
    if r.status_code == 200:
        rec("O12b", "nome e cidade atualizados", 200 if r.json()["name"].endswith("editada") and r.json()["city"] == "Curitiba" else 0, 200)
    rec("O13", "PATCH UUID inexistente", call("admin", "PATCH", f"/api/obras/{uuid.uuid4()}", {"name": "x"}), 404)
    rec("O14", "PATCH id=abc", call("admin", "PATCH", "/api/obras/abc", {"name": "x"}, bad=True), 400)
    r = call("admin", "PATCH", f"/api/obras/{state['obraB']}", {"name": "[TESTE] Obra B clima"})
    lat_ok = r.status_code == 200 and r.json().get("latitude") is not None
    rec("O16", "PATCH sem coordenadas preserva lat/long? (F10)", 200 if lat_ok else 0, 200, "se falhar: F10 confirmado (PATCH apaga lat/long)", register=True)
    if r.status_code == 200 and not lat_ok:  # restaura para os testes de clima
        call("admin", "PATCH", f"/api/obras/{state['obraB']}", {"name": "[TESTE] Obra B clima", "latitude": -23.5505, "longitude": -46.6333, "state": "SP"})
    rec("O18", "auditor lista diários", call("auditor", "GET", f"/api/obras/{state['obraA']}/diarios", params={"page": 0}), 403)
    rec("O18b", "obra inexistente nas listas", call("admin", "GET", f"/api/obras/{uuid.uuid4()}/documentos", params={"page": 0}), 404)
    for tid, d in [("O06b", "JSON malformado"), ("O07a", "UF SPX"), ("O07c", "data 2026-13-45"), ("O07e", "status inválido"), ("O07f", "name com 201 caracteres"), ("O02b", "page=abc")]:
        skip(tid, d, "400 adicional evitado por causa do fail2ban; coberto por teste unitário do back")


# ---------------------------------------------------------------- p2
def p2():
    print("== p2 documentos")
    A = state["obraA"]
    docs = state.setdefault("docs", {})
    r, pr, cr = upload_doc("admin", A, "teste.txt", "text/plain", "teste.txt")
    rec("D01", "upload-url txt", r, 201)
    if pr is not None:
        rec("D02", "PUT S3 (sem Authorization)", pr, 200)
    rec("D03", "confirmar upload txt", cr, 200, "status " + (cr.json().get("status", "") if cr is not None and cr.status_code == 200 else ""))
    if r.status_code == 201:
        docs["txt"] = r.json()["documentoId"]
        docs["txt_v"] = r.json()["versionId"]
        rec("D01b", "resposta: bucket/chave/https/PUT", 200 if r.json()["urlUpload"].startswith("https://") and r.json()["metodo"] == "PUT" and "/doc/" in r.json()["chave"] else 0, 200, r.json()["chave"][-40:])
    if "txt" in docs:
        g = call("admin", "GET", f"/api/documentos/{docs['txt']}/ocr")
        rec("D06a", "txt processado de forma síncrona", g, 200, "status " + str(g.json().get("status")) if g.status_code == 200 else "")
        if g.status_code == 200:
            rec("D06a2", "texto contém TESTE-ZETA", 200 if "TESTE-ZETA" in (g.json().get("texto") or "") else 0, 200)
    for key, name, ct, fx in [("xlsx", "teste.xlsx", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", "teste.xlsx"),
                              ("docx", "teste.docx", "application/vnd.openxmlformats-officedocument.wordprocessingml.document", "teste.docx")]:
        r, pr, cr = upload_doc("colaborador", A, name, ct, fx)
        rec(f"D06-{key}-up", f"{key}: upload+confirmar (colaborador)", cr if cr is not None else r, 200)
        if cr is not None and cr.status_code == 200:
            docs[key] = r.json()["documentoId"]
            g = call("admin", "GET", f"/api/documentos/{docs[key]}/ocr")
            rec(f"D06-{key}", f"{key}: leitura síncrona", g, 200, "status " + str(g.json().get("status")) if g.status_code == 200 else "")
    r, pr, cr = upload_doc("admin", A, "teste2.txt", "text/plain", "teste.txt")
    rec("D07", "mesmo conteúdo na mesma obra", cr if cr is not None else r, 409)
    if cr is not None:
        rec("D07b", "type documento-duplicado", 200 if "documento-duplicado" in cr.text else 0, 200)
    badguard()
    r, pr, cr = upload_doc("admin", A, "semput.txt", "text/plain", "teste.txt", put=False, content=b"conteudo unico " + os.urandom(8).hex().encode())
    rec("D08", "confirmar sem ter feito o PUT", cr, 400)
    r, pr, cr = upload_doc("admin", A, "falso.pdf", "application/pdf", "falso.pdf")
    rec("D10", "PDF com conteúdo PNG", cr if cr is not None else r, 415)
    r, pr, cr = upload_doc("admin", A, "binario.txt", "text/plain", "binario.txt")
    rec("D11", "txt com byte 0", cr if cr is not None else r, 415)
    if "txt_v" in docs:
        rr = call("admin", "POST", f"/api/documentos/{docs['txt']}/versoes/{docs['txt_v']}/confirmar-upload", {"sha256": sha(open(os.path.join(FX, 'teste.txt'), 'rb').read())})
        rec("D12", "confirmar duas vezes", rr, 409)
        rec("D13a", "sha256 maiúsculo", call("admin", "POST", f"/api/documentos/{docs['txt']}/versoes/{docs['txt_v']}/confirmar-upload", {"sha256": "A" * 64}, bad=True), 400)
    up = lambda role, body, bad=False: call(role, "POST", "/api/documentos/upload-url", body, bad=bad)
    base = {"projectId": A, "nomeArquivo": "x.pdf", "contentType": "application/pdf", "tamanhoBytes": 1000}
    rec("D15", ".exe", up("admin", {**base, "nomeArquivo": "x.exe", "contentType": "application/octet-stream"}), 415)
    rec("D16", "contentType não confere", up("admin", {**base, "contentType": "image/png"}, bad=True), 400)
    r = up("admin", {**base, "nomeArquivo": "grande.png", "contentType": "image/png", "tamanhoBytes": 11 * 1024 * 1024})
    rec("D17", "png 11 MB (limite back 10 MB)", r, 413, "front aceita até 50 MB: divergência")
    rec("D18", "projectId inexistente", up("admin", {**base, "projectId": str(uuid.uuid4())}), 404)
    rec("D19b", "tamanhoBytes=0", up("admin", {**base, "tamanhoBytes": 0}, bad=True), 400)
    rec("D19c", "Long.MAX tamanhoBytes", up("admin", {**base, "tamanhoBytes": 2 ** 63 - 1}), 413)
    rec("D19d", "nomeArquivo com traversal", up("admin", {**base, "nomeArquivo": "../../etc/passwd.pdf"}), [201, 400], "verificar chave sem '..'", register=True)
    rec("D20a", "revisor não envia documento", up("revisor", base), 403)
    rec("D20b", "auditor não envia documento", up("auditor", base), 403)
    if "txt" in docs:
        for role in ("auditor", "revisor"):
            rec(f"D21-{role}", f"{role} consulta OCR", call(role, "GET", f"/api/documentos/{docs['txt']}/ocr"), 200)
    rec("D22", "OCR de UUID inexistente", call("admin", "GET", f"/api/documentos/{uuid.uuid4()}/ocr"), 404)
    r = up("admin", {**base, "nomeArquivo": "ct.txt", "contentType": "text/plain", "tamanhoBytes": 5})
    if r.status_code == 201:
        j = r.json()
        pr = requests.put(j["urlUpload"], data=b"12345", headers={"Content-Type": "application/x-outro"}, timeout=30)
        rec("D25", "PUT com Content-Type diferente do assinado", pr, 403)
    r = call("admin", "GET", f"/api/obras/{A}/documentos", params={"page": 0})
    rec("O17", "lista de documentos da obra", r, 200, f"itens={len(r.json()['items']) if r.status_code == 200 else '-'}")
    for tid, d in [("D13b", "sha256 curto"), ("D14", "versionId de outro documento"), ("D19a", "tamanhoBytes ausente"), ("D22b", "OCR com id=abc")]:
        skip(tid, d, "400 adicional evitado por causa do fail2ban; coberto por teste unitário do back")


# ---------------------------------------------------------------- p3
def p3():
    print("== p3 diário + clima (parte síncrona)")
    A, B = state["obraA"], state["obraB"]
    di = state.setdefault("diarios", {})
    r, pr, cr = upload_audio("admin", A, "diario.webm")
    rec("DI01", "upload-url áudio webm", r, 201)
    if pr is not None:
        rec("DI02", "PUT áudio S3", pr, 200)
    rec("DI03", "confirmar áudio", cr, 200, "status " + str(cr.json().get("status")) if cr is not None and cr.status_code == 200 else "")
    if r.status_code == 201:
        di["A_webm"] = r.json()["diarioId"]
    r, pr, cr = upload_audio("admin", A, "diario.ogg", ctype="audio/ogg")
    rec("DI05a", "áudio ogg: upload+confirmar", cr if cr is not None else r, 200)
    if r.status_code == 201:
        di["A_ogg"] = r.json()["diarioId"]
    r, pr, cr = upload_audio("gestor", B, "diario.webm", ctype="audio/webm;codecs=opus")
    rec("DI02b", "contentType com codecs (obra B)", cr if cr is not None else r, [200, 201])
    if r.status_code == 201:
        di["B_webm"] = r.json()["diarioId"]
    body = {"projectId": A, "entryDate": time.strftime("%Y-%m-%d"), "authorRole": "[TESTE] Eng", "contentType": "audio/webm", "tamanhoBytes": 1000}
    dup = lambda role, b, bad=False: call(role, "POST", "/api/diario/upload-url", b, bad=bad)
    rec("DI06a", "audio/mpeg", dup("admin", {**body, "contentType": "audio/mpeg"}), 415)
    rec("DI06b", "audio/wav", dup("admin", {**body, "contentType": "audio/wav"}), 415)
    r, pr, cr = upload_audio("admin", A, None, content=open(os.path.join(FX, "audio.mp3"), "rb").read())
    rec("DI07", "conteúdo mp3 declarado como webm", cr if cr is not None else r, 415)
    rec("DI09", "60 MB (limite back 50 MB)", dup("admin", {**body, "tamanhoBytes": 60 * 1024 * 1024}), 413, "front aceita até 120 MB: divergência")
    rec("DI10c", "entryDate inválida", dup("admin", {**body, "entryDate": "2025-02-30"}, bad=True), 400)
    rec("DI11", "auditor cria diário", dup("auditor", body), 403)
    rec("DI11b", "revisor cria diário", dup("revisor", body), 201)
    rec("DI19a", "transcrição de UUID inexistente", call("admin", "GET", f"/api/diario/{uuid.uuid4()}/transcricao"), 404)
    rec("DI20", "auditor não lê transcrição", call("auditor", "GET", f"/api/diario/{di.get('A_webm', uuid.uuid4())}/transcricao"), 403)
    rec("DI13", "PATCH texto em diário ainda sem texto (GRAVADO/EM_TRANSCRICAO)", call("admin", "PATCH", f"/api/diario/{di['A_ogg']}/texto", {"texto": "x"}), 409, "409 hoje aparece no front como 'já existe ou foi alterado'")
    rec("DI14a", "texto vazio", call("admin", "PATCH", f"/api/diario/{di['A_ogg']}/texto", {"texto": ""}, bad=True), 400)
    rec("DI17", "colaborador não aprova", call("colaborador", "POST", f"/api/diario/{di['A_ogg']}/aprovar"), 403)
    rec("DI16a", "aprovar diário fora de AGUARDANDO_REVISAO", call("admin", "POST", f"/api/diario/{di['A_ogg']}/aprovar"), 409)
    rec("C02", "clima em obra sem coordenadas", call("admin", "GET", "/api/diario/clima", params={"projectId": A}), 409, "front mostra a mensagem genérica de 409")
    rec("C03", "clima sem projectId", call("admin", "GET", "/api/diario/clima", bad=True), 400)
    rec("C04", "clima obra inexistente", call("admin", "GET", "/api/diario/clima", params={"projectId": str(uuid.uuid4())}), 404)
    rec("C11", "auditor não consulta clima", call("auditor", "GET", "/api/diario/clima", params={"projectId": B}), 403)
    r = call("admin", "GET", "/api/diario/clima", params={"projectId": B})
    rec("C01", "clima da obra B (Open-Meteo)", r, 200)
    if r.status_code == 200:
        state["clima"] = r.json()
        j = r.json()
        rec("C01b", "campos e tokenConsulta", 200 if j.get("tokenConsulta") and j.get("fonte") == "Open-Meteo" and j.get("temperaturaC") is not None else 0, 200, f"{j.get('temperaturaC')}C {j.get('condicao')}")
    cA = di["A_ogg"]
    rec("C07", "clima manual (obra A)", call("admin", "PATCH", f"/api/diario/{cA}/clima", {"condicao": "[TESTE] nublado", "temperaturaC": 18, "corrigidoPeloUsuario": True}), 200)
    rec("C09", "corrigidoPeloUsuario ausente + sem token", call("admin", "PATCH", f"/api/diario/{cA}/clima", {"condicao": "sol", "temperaturaC": 20}), 200)
    rec("C08a", "false sem token", call("admin", "PATCH", f"/api/diario/{cA}/clima", {"condicao": "sol", "temperaturaC": 20, "corrigidoPeloUsuario": False}, bad=True), 400)
    rec("C10a", "temperatura 61 (fora da faixa)", call("admin", "PATCH", f"/api/diario/{cA}/clima", {"temperaturaC": 61, "corrigidoPeloUsuario": True}, bad=True), 400)
    rec("C11b", "auditor não grava clima", call("auditor", "PATCH", f"/api/diario/{cA}/clima", {"temperaturaC": 20, "corrigidoPeloUsuario": True}), 403)
    if "clima" in state and "B_webm" in di:
        c = state["clima"]
        vals = {k: c[k] for k in ("temperaturaC", "condicao", "umidadePercent", "ventoKmh", "precipitacaoMm")}
        rec("C05", "confirmar clima sem alterar (Open-Meteo)", call("admin", "PATCH", f"/api/diario/{di['B_webm']}/clima", {**vals, "corrigidoPeloUsuario": False, "tokenConsulta": c["tokenConsulta"]}), 200)
        alt = {**vals, "temperaturaC": (vals["temperaturaC"] or 0) + 0.1}
        rec("C08c", "valor alterado com corrigidoPeloUsuario=false", call("admin", "PATCH", f"/api/diario/{di['B_webm']}/clima", {**alt, "corrigidoPeloUsuario": False, "tokenConsulta": c["tokenConsulta"]}, bad=True), 400)
        rec("C06", "corrigido pelo usuário (MANUAL)", call("admin", "PATCH", f"/api/diario/{di['B_webm']}/clima", {**alt, "corrigidoPeloUsuario": True}), 200)
        rec("C08d", "token da obra B reaproveitado em diário da obra A (F8)", call("admin", "PATCH", f"/api/diario/{cA}/clima", {**vals, "corrigidoPeloUsuario": False, "tokenConsulta": c["tokenConsulta"]}, bad=True), [400], "200 = F8 confirmado (token reutilizável entre diários/obras)", register=True)
    for tid, d in [("DI08", "confirmar sem PUT"), ("DI10a", "sem entryDate"), ("DI10b", "authorRole 101"), ("DI19b", "transcrição id=abc"), ("DI14b", "texto 50001"), ("C03b", "clima projectId=xyz"), ("C08b", "token lixo"), ("C10b-f", "demais faixas de clima")]:
        skip(tid, d, "400 adicional evitado por causa do fail2ban; coberto por teste unitário do back")


def p3b():
    print("== p3b diário + clima (continuação depois de DI10c)")
    A, B = state["obraA"], state["obraB"]
    di = state["diarios"]
    body = {"projectId": A, "entryDate": time.strftime("%Y-%m-%d"), "authorRole": "[TESTE] Eng", "contentType": "audio/webm", "tamanhoBytes": 1000}
    dup = lambda role, b, bad=False: call(role, "POST", "/api/diario/upload-url", b, bad=bad)
    rec("DI11", "auditor cria diário", dup("auditor", body), 403)
    rec("DI11b", "revisor cria diário", dup("revisor", body), 201)
    rec("DI19a", "transcrição de UUID inexistente", call("admin", "GET", f"/api/diario/{uuid.uuid4()}/transcricao"), 404)
    rec("DI20", "auditor não lê transcrição", call("auditor", "GET", f"/api/diario/{di.get('A_webm', uuid.uuid4())}/transcricao"), 403)
    rec("DI13", "PATCH texto em diário ainda sem texto (GRAVADO/EM_TRANSCRICAO)", call("admin", "PATCH", f"/api/diario/{di['A_ogg']}/texto", {"texto": "x"}), 409, "409 hoje aparece no front como 'já existe ou foi alterado'")
    rec("DI14a", "texto vazio", call("admin", "PATCH", f"/api/diario/{di['A_ogg']}/texto", {"texto": ""}, bad=True), 400)
    rec("DI17", "colaborador não aprova", call("colaborador", "POST", f"/api/diario/{di['A_ogg']}/aprovar"), 403)
    rec("DI16a", "aprovar diário fora de AGUARDANDO_REVISAO", call("admin", "POST", f"/api/diario/{di['A_ogg']}/aprovar"), 409)
    rec("C02", "clima em obra sem coordenadas", call("admin", "GET", "/api/diario/clima", params={"projectId": A}), 409, "front mostra a mensagem genérica de 409")
    rec("C03", "clima sem projectId", call("admin", "GET", "/api/diario/clima", bad=True), 400)
    rec("C04", "clima obra inexistente", call("admin", "GET", "/api/diario/clima", params={"projectId": str(uuid.uuid4())}), 404)
    rec("C11", "auditor não consulta clima", call("auditor", "GET", "/api/diario/clima", params={"projectId": B}), 403)
    r = call("admin", "GET", "/api/diario/clima", params={"projectId": B})
    rec("C01", "clima da obra B (Open-Meteo)", r, 200)
    if r.status_code == 200:
        state["clima"] = r.json()
        j = r.json()
        rec("C01b", "campos e tokenConsulta", 200 if j.get("tokenConsulta") and j.get("fonte") == "Open-Meteo" and j.get("temperaturaC") is not None else 0, 200, f"{j.get('temperaturaC')}C {j.get('condicao')}")
    cA = di["A_ogg"]
    rec("C07", "clima manual (obra A)", call("admin", "PATCH", f"/api/diario/{cA}/clima", {"condicao": "[TESTE] nublado", "temperaturaC": 18, "corrigidoPeloUsuario": True}), 200)
    rec("C09", "corrigidoPeloUsuario ausente + sem token", call("admin", "PATCH", f"/api/diario/{cA}/clima", {"condicao": "sol", "temperaturaC": 20}), 200)
    rec("C08a", "false sem token", call("admin", "PATCH", f"/api/diario/{cA}/clima", {"condicao": "sol", "temperaturaC": 20, "corrigidoPeloUsuario": False}, bad=True), 400)
    rec("C10a", "temperatura 61 (fora da faixa)", call("admin", "PATCH", f"/api/diario/{cA}/clima", {"temperaturaC": 61, "corrigidoPeloUsuario": True}, bad=True), 400)
    rec("C11b", "auditor não grava clima", call("auditor", "PATCH", f"/api/diario/{cA}/clima", {"temperaturaC": 20, "corrigidoPeloUsuario": True}), 403)
    if "clima" in state and "B_webm" in di:
        c = state["clima"]
        vals = {k: c[k] for k in ("temperaturaC", "condicao", "umidadePercent", "ventoKmh", "precipitacaoMm")}
        rec("C05", "confirmar clima sem alterar (Open-Meteo)", call("admin", "PATCH", f"/api/diario/{di['B_webm']}/clima", {**vals, "corrigidoPeloUsuario": False, "tokenConsulta": c["tokenConsulta"]}), 200)
        alt = {**vals, "temperaturaC": (vals["temperaturaC"] or 0) + 0.1}
        rec("C08c", "valor alterado com corrigidoPeloUsuario=false", call("admin", "PATCH", f"/api/diario/{di['B_webm']}/clima", {**alt, "corrigidoPeloUsuario": False, "tokenConsulta": c["tokenConsulta"]}, bad=True), 400)
        rec("C06", "corrigido pelo usuário (MANUAL)", call("admin", "PATCH", f"/api/diario/{di['B_webm']}/clima", {**alt, "corrigidoPeloUsuario": True}), 200)
        rec("C08d", "token da obra B reaproveitado em diário da obra A (F8)", call("admin", "PATCH", f"/api/diario/{cA}/clima", {**vals, "corrigidoPeloUsuario": False, "tokenConsulta": c["tokenConsulta"]}, bad=True), [400], "200 = F8 confirmado (token reutilizável entre diários/obras)", register=True)
    for tid, d in [("DI08", "confirmar sem PUT"), ("DI10a", "sem entryDate"), ("DI10b", "authorRole 101"), ("DI19b", "transcrição id=abc"), ("DI14b", "texto 50001"), ("C03b", "clima projectId=xyz"), ("C08b", "token lixo"), ("C10b-f", "demais faixas de clima")]:
        skip(tid, d, "400 adicional evitado por causa do fail2ban; coberto por teste unitário do back")


# ---------------------------------------------------------------- p4
def poll(role, path, done, tries=60, every=5):
    t0 = time.time()
    last = None
    for _ in range(tries):
        r = call(role, "GET", path)
        last = r
        if done(r):
            return r, time.time() - t0
        time.sleep(every)
    return last, time.time() - t0


def p4():
    print("== p4 assíncronos [W] (OCR e transcrição)")
    A = state["obraA"]
    docs = state["docs"]
    di = state["diarios"]
    r, pr, cr = upload_doc("admin", A, "teste.pdf", "application/pdf", "teste.pdf")
    rec("D04-up", "pdf: upload+confirmar", cr if cr is not None else r, 200)
    if cr is not None and cr.status_code == 200:
        docs["pdf"] = r.json()["documentoId"]
    r, pr, cr = upload_doc("admin", A, "teste.png", "image/png", "teste.png")
    rec("D05-up", "png: upload+confirmar", cr if cr is not None else r, 200)
    if cr is not None and cr.status_code == 200:
        docs["png"] = r.json()["documentoId"]
    if "png" in docs:
        rec("D23", "OCR logo após confirmar (assíncrono)", call("admin", "GET", f"/api/documentos/{docs['png']}/ocr"), [200, 202])
    for key in ("pdf", "png"):
        if key in docs:
            g, dt = poll("admin", f"/api/documentos/{docs[key]}/ocr", lambda r: r.status_code != 202)
            txt = (g.json().get("texto") or "").upper() if g.status_code == 200 else ""
            rec(f"D04-{key}", f"OCR {key} concluído em {dt:.0f}s (alvo <180s)", g, 200, f"paginas={g.json().get('paginas') if g.status_code == 200 else '-'} conf={g.json().get('confiancaMedia') if g.status_code == 200 else '-'}")
            rec(f"D04-{key}b", f"texto do OCR {key} contém o termo de teste", 200 if "ZETA" in txt else 0, 200, txt[:60])
            rec(f"D04-{key}t", f"{key}: dentro do SLA de 3 min", 200 if dt < 180 else 0, 200, f"{dt:.0f}s")
    for key in ("A_webm", "A_ogg", "B_webm"):
        if key in di:
            g, dt = poll("admin", f"/api/diario/{di[key]}/transcricao", lambda r: r.status_code != 202, tries=70)
            j = g.json() if g.status_code == 200 else {}
            rec(f"DI04-{key}", f"transcrição {key} em {dt:.0f}s (alvo <300s)", g, 200, f"status={j.get('status')} raw={str(j.get('transcriptRaw'))[:50]}")
            if g.status_code == 200:
                rec(f"DI04-{key}b", f"{key}: status AGUARDANDO_REVISAO ou FALHA", 200 if j.get("status") in ("AGUARDANDO_REVISAO", "FALHA_TRANSCRICAO") else 0, 200, str(j.get("mensagem")))
    k = "A_webm"
    if k in di:
        r = call("admin", "PATCH", f"/api/diario/{di[k]}/texto", {"texto": "[TESTE] texto revisado, concretagem da laje L7."})
        rec("DI12", "editar texto em AGUARDANDO_REVISAO", r, [200, 409], "409 se a transcrição falhou")
        if r.status_code == 200:
            rec("DI15", "aprovar (revisor)", call("revisor", "POST", f"/api/diario/{di[k]}/aprovar"), 200)
            rec("DI16", "aprovar de novo", call("admin", "POST", f"/api/diario/{di[k]}/aprovar"), 409)
            rec("DI18", "colaborador edita diário FECHADO (F7: 200 = retifica sem aprovação)", call("colaborador", "PATCH", f"/api/diario/{di[k]}/texto", {"texto": "[TESTE] retificado por colaborador"}), [403, 409], register=True)
            rec("D22c", "clima em diário FECHADO/RETIFICADO (F6: 200 = sem trilha)", call("admin", "PATCH", f"/api/diario/{di[k]}/clima", {"temperaturaC": 19, "corrigidoPeloUsuario": True}), [409], register=True)


# ---------------------------------------------------------------- p5
def p5():
    print("== p5 assistente")
    A = state["obraA"]
    ask = lambda role, b, bad=False: call(role, "POST", "/api/assistente/perguntas", b, bad=bad)
    r = ask("admin", {"projectId": A, "pergunta": "[TESTE] O que foi dito sobre TESTE-ZETA?"})
    rec("S01", "pergunta com termo indexado", r, 200)
    if r.status_code == 200:
        j = r.json()
        state["sessionId"] = j["sessionId"]
        rec("S01b", "resposta com citação (semFonte=false)", 200 if j.get("citacoes") and not j.get("semFonte") else 0, 200, f"semFonte={j.get('semFonte')} citacoes={len(j.get('citacoes') or [])}", register=True)
        r2 = ask("admin", {"projectId": A, "sessionId": j["sessionId"], "pergunta": "[TESTE] Quem é o responsável técnico?"})
        rec("S02", "mesma sessão", r2, 200)
        if r2.status_code == 200:
            rec("S02b", "sessionId mantido", 200 if r2.json()["sessionId"] == j["sessionId"] else 0, 200)
    r = ask("admin", {"projectId": A, "pergunta": "[TESTE] qual a cor do céu em Marte?"})
    rec("S03", "pergunta sem relação", r, 200, f"semFonte={r.json().get('semFonte') if r.status_code == 200 else '-'}")
    rec("S04a", "pergunta vazia", ask("admin", {"projectId": A, "pergunta": ""}, bad=True), 400)
    rec("S05", "sessionId de outra obra", ask("admin", {"projectId": state["obraB"], "sessionId": state.get("sessionId", str(uuid.uuid4())), "pergunta": "[TESTE] oi"}), 404)
    rec("S06", "projectId inexistente", ask("admin", {"projectId": str(uuid.uuid4()), "pergunta": "[TESTE] oi"}), 404)
    rec("S06b", "sessionId=abc", ask("admin", {"projectId": A, "sessionId": "abc", "pergunta": "[TESTE] oi"}, bad=True), 400)
    rec("S07", "auditor pergunta", ask("auditor", {"projectId": A, "pergunta": "[TESTE] resumo?"}), 200)
    for tid, d in [("S04b", "pergunta 2001 caracteres"), ("S04c", "sem projectId")]:
        skip(tid, d, "400 adicional evitado por causa do fail2ban; coberto por teste unitário do back")


# ---------------------------------------------------------------- p7
def p7():
    print("== p7 rate limit (por último)")
    A = state["obraA"]
    codes = []
    for i in range(12):
        r = call("gestor", "POST", "/api/assistente/perguntas", {"projectId": A, "pergunta": f"[TESTE] rate {i}"})
        codes.append(r.status_code)
        if r.status_code == 429:
            rec("S08", "429 no assistente (limite 10/min)", r, 429, f"na chamada {i + 1}; Retry-After={r.headers.get('Retry-After')} sem sub no corpo={'sub' not in r.text}")
            break
    if 429 not in codes:
        rec("S08", "429 no assistente (limite 10/min)", 200, 429, f"codes={codes}")
    for i in range(22):
        r = call("colaborador", "GET", "/api/diario/clima", params={"projectId": state["obraB"]})
        if r.status_code == 429:
            rec("R03", "429 no clima (limite 20/min)", r, 429, f"na chamada {i + 1}")
            break
    else:
        rec("R03", "429 no clima (limite 20/min)", r, 429, "nunca limitou")
    _bucket.clear()
    hit = None
    for i in range(33):
        r = requests.post(API + "/api/documentos/upload-url", headers={"Authorization": "Bearer " + token("revisor"), "Origin": ORIGIN},
                          json={"projectId": A, "nomeArquivo": "x.pdf", "contentType": "application/pdf", "tamanhoBytes": 1}, timeout=30)
        if r.status_code == 429:
            hit = i + 1
            break
    rec("R01", "429 em upload-url (30/min; revisor gasta cota mesmo com 403 - F5)", 429 if hit else 0, 429, f"na chamada {hit}", register=True)


PHASES = {"p3b": p3b, "p0": p0, "p1": p1, "p2": p2, "p3": p3, "p4": p4, "p5": p5, "p7": p7}

if __name__ == "__main__":
    for w in (sys.argv[1:] or ["p0"]):
        PHASES[w]()
        save()
    fail = [e for e in results if not e["ok"] and not e["register"]]
    reg = [e for e in results if not e["ok"] and e["register"]]
    print(f"\nTOTAL {len(results)}  PASS {sum(e['ok'] and not e.get('skipped') for e in results)}  FAIL {len(fail)}  REGISTRAR {len(reg)}  NAO-EXECUTADOS {sum(1 for e in results if e.get('skipped'))}")
