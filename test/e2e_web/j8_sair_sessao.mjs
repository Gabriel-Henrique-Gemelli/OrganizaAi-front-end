// J8: sair (logout limpa estado em memória; nenhuma chamada /api depois) e comportamento com 401 no meio da sessão (mock local, NÃO atinge o servidor). Perfil GESTOR.
import * as L from './lib.mjs';
const OBRA = '[TESTE] E2E Obra clima';
const b = await L.launch();
const s = await L.newSession(b, 'J8');
const P = s.page;
const idb = () => P.evaluate(async () => {
  const dbs = (await indexedDB.databases?.()) || [];
  const out = [];
  for (const d of dbs) {
    const n = await new Promise((res) => { const r = indexedDB.open(d.name); r.onsuccess = () => { const db = r.result; let c = 0; const names = [...db.objectStoreNames]; if (!names.length) { db.close(); return res(0); } const tx = db.transaction(names, 'readonly'); let pend = names.length; names.forEach((nm) => { const q = tx.objectStore(nm).count(); q.onsuccess = () => { c += q.result; if (--pend === 0) { db.close(); res(c); } }; }); }; r.onerror = () => res(-1); });
    out.push(`${d.name}:${n}`);
  }
  return out;
});
try {
  await L.login(s, 'gestor');
  L.check(s, 'login gestor', await L.waitText(P, 'Hoje', 60000));
  await L.sleep(3000);
  await L.selectProject(P, OBRA);
  await L.sleep(1500);
  const before = await idb();
  console.log('IDB antes do logout:', before);
  await L.clickBtn(P, 'Conta', { exact: true });
  L.check(s, 'página Conta mostra "SAIR DA CONTA"', await L.waitText(P, 'SAIR DA CONTA', 10000));
  const mark = s.net.length;
  await L.clickBtn(P, 'SAIR DA CONTA');
  await L.sleep(2500);
  let t = await L.bodyText(P);
  L.check(s, 'após sair: tela de login ("Acesse sua conta")', /Acesse sua conta/.test(t));
  L.check(s, 'após sair: nenhum dado de obra na tela', !/\[TESTE\]|SEED|documentos ·/i.test(t));
  await L.shot(s, 'pos-logout');
  console.log('aguardando 40 s (o timer de sincronização é de 30 s)...');
  await L.sleep(40000);
  L.check(s, 'após sair: nenhuma chamada /api (40 s)', L.apiCalls(s, mark).length === 0, `${L.apiCalls(s, mark).length}`);
  const after = await idb();
  console.log('IDB depois do logout:', after);
  const same = JSON.stringify(before) === JSON.stringify(after);
  L.check(s, 'logout: cache local (IndexedDB) apagado', false, `antes=${before.join(',')} depois=${after.join(',')}`);
  if (same || after.some((x) => !x.endsWith(':0'))) L.finding(s, 'Logout limpa só a sessão em memória: o cache local (IndexedDB do Hive: obras, documentos, diários, conversas, bytes dos arquivos) permanece no navegador e reaparece no próximo login do mesmo usuário (escopo por organização+usuário). Em computador compartilhado os dados ficam gravados.');
  // novo login
  await L.fillField(P, 'Usuário ou e-mail', L.LOGIN.gestor);
  await L.fillField(P, 'Senha', L.password('gestor'));
  await L.clickBtn(P, 'ENTRAR', { exact: true });
  await L.waitText(P, 'Hoje', 60000);
  await L.sleep(3000);
  t = await L.bodyText(P);
  L.check(s, 'novo login: obra ativa anterior restaurada do cache local', t.toUpperCase().includes(OBRA.toUpperCase() + ' ·'), 'cabeçalho ' + (t.toUpperCase().includes(OBRA.toUpperCase() + ' ·') ? 'mostra a obra' : 'não mostra'));
  // sessão inválida no meio da sessão: 401 simulado localmente (route.fulfill), sem tocar o servidor
  let mocked = 0;
  await P.route('https://api.organizaii.com.br/api/obras**', (r) => {
    if (r.request().method() === 'OPTIONS') return r.fallback();
    mocked++;
    return r.fulfill({ status: 401, headers: { 'content-type': 'application/problem+json', 'access-control-allow-origin': 'http://localhost:8081', 'www-authenticate': 'Bearer' }, body: JSON.stringify({ title: 'Unauthorized', status: 401 }) });
  });
  await L.clickBtn(P, 'Atualizar dados');
  await L.sleep(3500);
  t = await L.bodyText(P);
  const stillIn = !/Acesse sua conta/.test(t) && /Hoje/.test(t);
  const toast = t.match(/(Entre novamente[^.]*\.|Não foi possível[^.]*\.|Confira sua conexão[^.]*\.|Acesso não autorizado[^.]*\.|Sessão[^.]*\.)/);
  console.log('mock 401 atendidos:', mocked, '| permaneceu logado:', stillIn, '| mensagem:', toast && toast[0]);
  L.check(s, 'sessão inválida (401 simulado em GET /api/obras): comportamento registrado', mocked > 0, `permaneceu logado=${stillIn}; mensagem="${toast ? toast[0] : 'nenhuma mensagem semântica detectada'}"`);
  if (stillIn) L.finding(s, `401 no meio da sessão (simulado por mock local): o app NÃO desloga; permanece no workspace. Mensagem exibida: "${toast ? toast[0] : 'nenhuma visível'}". Usuário continua vendo dados antigos como se estivessem atualizados.`);
  await L.shot(s, 'sessao-401');
  await P.unroute('https://api.organizaii.com.br/api/obras**');
} catch (e) { L.check(s, 'execução sem exceção', false, String(e.message).slice(0, 300)); await L.shot(s, 'erro'); console.log((await L.bodyText(P)).slice(0, 1500)); }
L.saveResult(s);
console.log(L.fmtNet(s.net).join('\n'));
console.log('console errors:', s.consoleErrors);
await b.close();
