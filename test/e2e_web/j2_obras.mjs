// J2: criar obra só com nome, validações locais, editar com detalhes, criar obra com coordenadas (clima). Perfil GESTOR.
import * as L from './lib.mjs';
import fs from 'node:fs';
const SIMPLES = '[TESTE] E2E Obra simples';
const CLIMA = '[TESTE] E2E Obra clima';
const b = await L.launch();
const s = await L.newSession(b, 'J2');
const P = s.page;
let c;
const last = () => L.apiCalls(s).slice(-1)[0];
try {
  await L.login(s, 'gestor');
  L.check(s, 'login gestor', await L.waitText(P, 'Hoje', 60000));
  await L.sleep(3000);
  const t0 = await L.bodyText(P);
  L.check(s, 'gestor vê "+ nova"', /\+ nova/.test(t0));

  const RESUME = !!process.env.RESUME;
  let mark = s.net.length;
  if (RESUME) {
    const prev = JSON.parse(fs.readFileSync(L.RES_DIR + '/J2.json', 'utf8'));
    s.checks.push(...prev.checks.filter((c) => c.ok));
    s.net.unshift(...prev.net.filter((n) => n.kind === 'api' && n.method !== 'GET'));
    L.check(s, 'obra simples selecionada via dropdown', await L.selectProject(P, SIMPLES));
  }
  // --- 1) validação local: nome vazio
  if (!RESUME) {
  await L.clickBtn(P, '+ nova');
  L.check(s, 'diálogo "Adicionar obra" abriu', await L.waitText(P, 'Adicionar obra', 10000));
  await L.clickBtn(P, 'SALVAR OBRA');
  await L.sleep(800);
  L.check(s, 'nome vazio: "Campo obrigatório" local', await L.has(P, 'Campo obrigatório'));
  L.check(s, 'nome vazio: nenhuma chamada /api', L.apiCalls(s, mark).length === 0);
  await L.shot(s, 'nome-vazio');

  // --- 2) só o nome (POST 201)
  await L.fillField(P, 'Nome da obra *', SIMPLES);
  mark = s.net.length;
  await L.clickBtn(P, 'SALVAR OBRA');
  await L.sleep(4000);
  c = L.apiCalls(s, mark);
  const post = c.find((n) => n.method === 'POST' && n.path === '/api/obras');
  L.check(s, 'POST /api/obras (só nome) 201', post && post.status === 201, post && String(post.status));
  L.assertNo400(s);
  await L.shot(s, 'obra-simples-criada');
  const hdr = await L.bodyText(P);
  L.check(s, 'obra nova fica selecionada no cabeçalho', hdr.toUpperCase().includes(SIMPLES.toUpperCase()));

  }
  await L.assertTestProject(P);
  // --- 3) editar com detalhes e validações locais (UF e coordenadas)
  await L.clickBtn(P, 'DADOS DA OBRA');
  L.check(s, 'diálogo "Dados da obra" abriu', await L.waitText(P, 'Dados da obra', 10000));
  await L.clickBtn(P, 'Mais detalhes');
  await L.sleep(800);
  mark = s.net.length;
  await L.fillField(P, 'UF', 'S1');
  await L.clickBtn(P, 'SALVAR OBRA');
  await L.sleep(800);
  L.check(s, 'UF inválida: "Use a sigla da UF" local', await L.has(P, 'Use a sigla da UF'));
  await L.fillField(P, 'UF', 'SP');
  await L.fillField(P, 'Latitude', '999');
  await L.clickBtn(P, 'SALVAR OBRA');
  await L.sleep(800);
  L.check(s, 'latitude 999: "Coordenada inválida" local', await L.has(P, 'Coordenada inválida'));
  await L.fillField(P, 'Latitude', '-23,5505');
  await L.fillField(P, 'Longitude', '500');
  await L.clickBtn(P, 'SALVAR OBRA');
  await L.sleep(800);
  L.check(s, 'longitude 500: "Coordenada inválida" local', await L.has(P, 'Coordenada inválida'));
  L.check(s, 'validações locais não chamaram /api', L.apiCalls(s, mark).length === 0, `${L.apiCalls(s, mark).length}`);
  await L.shot(s, 'validacoes-locais');
  await L.fillField(P, 'Longitude', '-46,6333');
  await L.fillField(P, 'Cidade', 'São Paulo');
  await L.fillField(P, 'Endereço', '[TESTE] E2E Rua Teste 1');
  mark = s.net.length;
  await L.clickBtn(P, 'SALVAR OBRA');
  await L.sleep(4000);
  c = L.apiCalls(s, mark);
  const pt = c.find((n) => n.method === 'PATCH');
  L.check(s, 'PATCH /api/obras/{id} 200', pt && pt.status === 200, pt && `${pt.path} ${pt.status}`);
  L.assertNo400(s);
  await L.shot(s, 'obra-simples-editada');

  // --- 4) obra com coordenadas (clima)
  await L.clickBtn(P, '+ nova');
  await L.waitText(P, 'Adicionar obra', 10000);
  await L.fillField(P, 'Nome da obra *', CLIMA);
  await L.clickBtn(P, 'Mais detalhes');
  await L.sleep(800);
  await L.fillField(P, 'Cidade', 'São Paulo');
  await L.fillField(P, 'UF', 'SP');
  await L.fillField(P, 'Latitude', '-23.5505');
  await L.fillField(P, 'Longitude', '-46.6333');
  mark = s.net.length;
  await L.clickBtn(P, 'SALVAR OBRA');
  await L.sleep(4000);
  c = L.apiCalls(s, mark);
  const post2 = c.find((n) => n.method === 'POST' && n.path === '/api/obras');
  L.check(s, 'POST /api/obras (com coordenadas) 201', post2 && post2.status === 201, post2 && String(post2.status));
  L.assertNo400(s);
  await L.shot(s, 'obra-clima-criada');
  // reabre "Dados da obra" para conferir que a coordenada voltou do servidor
  await L.clickBtn(P, 'DADOS DA OBRA');
  await L.waitText(P, 'Dados da obra', 10000);
  await L.clickBtn(P, 'Mais detalhes');
  await L.sleep(800);
  // o input da árvore de semântica só recebe o valor depois do foco
  const fl = await L.fieldHandle(P, 'Latitude'); await fl.click({ force: true }); await L.sleep(400); const lat = await fl.inputValue();
  const fo = await L.fieldHandle(P, 'Longitude'); await fo.click({ force: true }); await L.sleep(400); const lon = await fo.inputValue();
  L.check(s, 'coordenadas persistidas (-23.5505 / -46.6333)', lat.startsWith('-23.55') && lon.startsWith('-46.63'), `${lat} / ${lon}`);
  await L.clickBtn(P, 'Cancelar');
  L.saveState({ simples: SIMPLES, clima: CLIMA });
} catch (e) { L.check(s, 'execução sem exceção', false, String(e.message).slice(0, 300)); await L.shot(s, 'erro'); console.log((await L.bodyText(P)).slice(0, 1200)); }
{ const m = new Map(); for (const k of s.checks) m.set(k.id, k); s.checks = [...m.values()]; }
L.saveResult(s);
console.log(L.fmtNet(s.net).filter((x) => /api/.test(x) || true).join('\n'));
console.log('console errors:', s.consoleErrors);
await b.close();
