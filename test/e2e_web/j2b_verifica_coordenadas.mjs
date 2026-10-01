// J2 (complemento): uma versão anterior do script digitou lat/long no campo errado (rolagem do diálogo). Este passo
// refaz a edição da obra clima com as coordenadas corretas (PATCH), reabre e confere. Anexa o resultado em results/J2.json.
import * as L from './lib.mjs';
import fs from 'node:fs';
const b = await L.launch();
const s = await L.newSession(b, 'J2b');
const P = s.page;
try {
  await L.login(s, 'gestor');
  await L.waitText(P, 'Hoje', 60000); await L.sleep(3000);
  await L.selectProject(P, '[TESTE] E2E Obra clima');
  await L.assertTestProject(P);
  await L.clickBtn(P, 'DADOS DA OBRA'); await L.waitText(P, 'Dados da obra', 10000);
  await L.clickBtn(P, 'Mais detalhes'); await L.sleep(1000);
  await L.fillField(P, 'Latitude', '-23.5505');
  await L.fillField(P, 'Longitude', '-46.6333');
  const mark = s.net.length;
  await L.clickBtn(P, 'SALVAR OBRA');
  await L.sleep(4000);
  const pt = L.apiCalls(s, mark).find((n) => n.method === 'PATCH');
  L.check(s, 'PATCH /api/obras/{id} 200 (corrigindo coordenadas da obra clima)', pt && pt.status === 200, pt && String(pt.status));
  L.assertNo400(s);
  await L.clickBtn(P, 'DADOS DA OBRA'); await L.waitText(P, 'Dados da obra', 10000);
  await L.clickBtn(P, 'Mais detalhes'); await L.sleep(1000);
  const lat = await L.readField(P, 'Latitude'), lon = await L.readField(P, 'Longitude');
  L.check(s, 'coordenadas persistidas (-23.5505 / -46.6333)', lat === '-23.5505' && lon === '-46.6333', `${lat} / ${lon}`);
  await L.clickBtn(P, 'Cancelar');
} catch (e) { L.check(s, 'execução sem exceção', false, String(e.message).slice(0, 300)); await L.shot(s, 'erro'); }
const f = L.RES_DIR + '/J2.json';
const prev = JSON.parse(fs.readFileSync(f, 'utf8'));
prev.checks = prev.checks.filter((c) => !c.id.startsWith('coordenadas persistidas') && c.id !== 'execução sem exceção').concat(s.checks);
prev.net.push(...s.net.filter((n) => n.kind === 'api'));
fs.writeFileSync(f, JSON.stringify(prev, null, 1));
L.saveState({ simples: '[TESTE] E2E Obra simples', clima: '[TESTE] E2E Obra clima' });
console.log(L.fmtNet(s.net).join('\n'));
await b.close();
