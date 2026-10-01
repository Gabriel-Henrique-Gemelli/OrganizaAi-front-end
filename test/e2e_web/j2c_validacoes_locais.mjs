// J2 (complemento): repete as validações locais (UF, latitude, longitude) com a localização de campos corrigida. Sem chamadas /api de escrita.
import * as L from './lib.mjs';
import fs from 'node:fs';
const b = await L.launch();
const s = await L.newSession(b, 'J2c');
const P = s.page;
try {
  await L.login(s, 'gestor');
  await L.waitText(P, 'Hoje', 60000); await L.sleep(3000);
  await L.selectProject(P, '[TESTE] E2E Obra simples');
  await L.assertTestProject(P);
  await L.clickBtn(P, 'DADOS DA OBRA'); await L.waitText(P, 'Dados da obra', 10000);
  await L.clickBtn(P, 'Mais detalhes'); await L.sleep(1000);
  const mark = s.net.length;
  await L.fillField(P, 'UF', 'S1');
  await L.clickBtn(P, 'SALVAR OBRA'); await L.sleep(800);
  L.check(s, 'UF "S1": "Use a sigla da UF" (local)', await L.has(P, 'Use a sigla da UF'));
  await L.fillField(P, 'UF', 'SP');
  await L.fillField(P, 'Latitude', '999');
  await L.fillField(P, 'Longitude', '-46.6');
  await L.clickBtn(P, 'SALVAR OBRA'); await L.sleep(800);
  L.check(s, 'latitude 999: "Coordenada inválida" (local)', await L.has(P, 'Coordenada inválida'));
  await L.fillField(P, 'Latitude', '-23.5');
  await L.fillField(P, 'Longitude', '500');
  await L.clickBtn(P, 'SALVAR OBRA'); await L.sleep(800);
  L.check(s, 'longitude 500: "Coordenada inválida" (local)', await L.has(P, 'Coordenada inválida'));
  await L.shot(s, 'validacoes-locais-corrigido');
  L.check(s, 'nenhuma chamada /api durante as validações', L.apiCalls(s, mark).length === 0, `${L.apiCalls(s, mark).length}`);
  await L.clickBtn(P, 'Cancelar');
} catch (e) { L.check(s, 'execução sem exceção', false, String(e.message).slice(0, 300)); await L.shot(s, 'erro'); }
const f = L.RES_DIR + '/J2.json';
const prev = JSON.parse(fs.readFileSync(f, 'utf8'));
const ids = new Set(s.checks.map((c) => c.id));
prev.checks = prev.checks.filter((c) => !ids.has(c.id) && c.id !== 'execução sem exceção').concat(s.checks);
fs.writeFileSync(f, JSON.stringify(prev, null, 1));
await b.close();
