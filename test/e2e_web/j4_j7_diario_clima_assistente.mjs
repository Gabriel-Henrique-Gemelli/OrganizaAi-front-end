// J4 diário por áudio, J5 clima manual, J6 clima automático, J7 assistente. Perfil GESTOR, obra '[TESTE] E2E Obra clima'.
// Tudo em UM contexto porque o diário fica no cache local (IndexedDB) do navegador.
import * as L from './lib.mjs';
import path from 'node:path';
const OBRA = '[TESTE] E2E Obra clima';
const AUDIO = process.env.AUDIO || 'diario.webm';
const b = await L.launch();
const s = await L.newSession(b, 'J4-J7');
const P = s.page;
const SLA_TRANSC = 6 * 60 * 1000;
let id = '';
const C = (name, ok, d) => L.check(s, `${id}/ ${name}`, ok, d);
// SelectableText também vira <textarea> na árvore de semântica: localizar pelo rótulo, nunca por .first().
const textarea = () => P.locator('flt-semantics > textarea[aria-label="Texto revisado"], flt-semantics > textarea[placeholder="Texto revisado"]').first();
async function statusPill() { const t = await L.bodyText(P); return (t.match(/(AGUARDANDO REVISAO|AGUARDANDO REVISÃO|EM TRANSCRICAO|EM TRANSCRIÇÃO|GRAVADO|FALHA TRANSCRICAO|FALHA TRANSCRIÇÃO|FECHADO|RETIFICADO|CANCELADO)/) || [])[1] || ''; }
try {
  await L.login(s, 'gestor');
  id = 'J4';
  C('login gestor', await L.waitText(P, 'Hoje', 60000));
  await L.sleep(3000);
  C('obra clima selecionada', await L.selectProject(P, OBRA));
  await L.assertTestProject(P);
  await L.clickBtn(P, 'Diário', { exact: true });
  C('página Diário abriu', await L.waitText(P, 'O dia acontece', 10000));
  await L.fillField(P, 'Função', '[TESTE] E2E Engenheiro');
  let mark = s.net.length;
  await L.chooseFiles(P, 'IMPORTAR ÁUDIO', [path.join(L.FX, AUDIO)]);
  const t0 = Date.now();
  // aguarda a transcrição
  let st = '', clicked = 0;
  while (Date.now() - t0 < SLA_TRANSC) {
    await L.sleep(4000);
    st = await statusPill();
    L.assertNo400(s);
    if (/AGUARDANDO|FECHADO|FALHA/.test(st)) break;
    if (((Date.now() - t0) / 1000 | 0) > 60 && (Date.now() - t0) % 30000 < 5000 && clicked < 12) {
      const b2 = L.btn(P, 'CONSULTAR TRANSCRIÇÃO');
      if (await b2.count()) { await b2.dispatchEvent('click'); clicked++; }
    }
  }
  const secs = Math.round((Date.now() - t0) / 1000);
  await L.shot(s, 'J4-transcricao');
  let api = L.apiCalls(s, mark);
  const s3 = s.net.slice(mark).filter((n) => n.kind === 's3');
  C('POST /api/diario/upload-url 201', api.some((n) => n.method === 'POST' && /diario\/upload-url$/.test(n.path) && n.status === 201), api.filter((n) => /upload-url/.test(n.path)).map((n) => n.status).join(','));
  C('PUT S3 200 sem Authorization', s3.some((n) => n.method === 'PUT' && n.status === 200) && s3.every((n) => !n.hasAuth), s3.map((n) => `${n.method} ${n.status} auth=${n.hasAuth}`).join(';'));
  C('POST confirmar-upload 200', api.some((n) => /confirmar-upload$/.test(n.path) && n.status === 200), api.filter((n) => /confirmar-upload/.test(n.path)).map((n) => n.status).join(','));
  const tr = api.filter((n) => n.method === 'GET' && /transcricao$/.test(n.path)).map((n) => n.status);
  C('GET /transcricao (202... depois 200)', tr.includes(200), tr.join(','));
  C(`transcrição pronta em até 6 min (status=${st || 'sem status'})`, /AGUARDANDO/.test(st), `${secs}s`);
  if (/AGUARDANDO/.test(st)) {
    // edição de texto
    await L.sleep(1500);
    const ta = textarea();
    await ta.click({ force: true }); await L.sleep(500);
    const val = await ta.inputValue();
    C('transcrição contém TESTE-ZETA', /teste[\s\-–_.,]{0,3}zeta/i.test(val), val.slice(0, 160).replace(/\s+/g, ' '));
    await P.keyboard.press('Control+End');
    await P.keyboard.type(' [TESTE] E2E revisado.', { delay: 10 });
    await L.sleep(400);
    mark = s.net.length;
    await L.clickBtn(P, 'SALVAR REVISÃO', { exact: true });
    await L.sleep(3500);
    api = L.apiCalls(s, mark);
    const pt = api.find((n) => n.method === 'PATCH' && /\/texto$/.test(n.path));
    C('PATCH /texto 200 ao salvar revisão', pt && pt.status === 200, pt && String(pt.status));
    C('toast "Revisão salva."', await L.has(P, 'Revisão salva'));
    await L.shot(s, 'J4-revisao-salva');

    // ---- J5 clima manual
    id = 'J5';
    await L.clickBtn(P, 'INFORMAR CLIMA');
    C('diálogo "Clima observado" abriu', await L.waitText(P, 'Clima observado', 10000));
    mark = s.net.length;
    await L.fillField(P, 'Umidade (%)', '55,5');
    await L.clickBtn(P, 'Salvar clima');
    await L.sleep(800);
    C('umidade não inteira: erro local', await L.has(P, 'informe um valor entre 0 e 100, inteiro'));
    await L.fillField(P, 'Umidade (%)', '150');
    await L.clickBtn(P, 'Salvar clima');
    await L.sleep(800);
    C('umidade 150: erro local', await L.has(P, 'informe um valor entre 0 e 100'));
    C('validações locais sem chamada /api', L.apiCalls(s, mark).length === 0, `${L.apiCalls(s, mark).length}`);
    await L.shot(s, 'J5-validacao-local');
    await L.fillField(P, 'Condição', '[TESTE] E2E Ensolarado');
    await L.fillField(P, 'Temperatura (°C)', '25');
    await L.fillField(P, 'Umidade (%)', '60');
    await L.fillField(P, 'Vento (km/h)', '10');
    await L.fillField(P, 'Chuva (mm)', '0');
    mark = s.net.length;
    await L.clickBtn(P, 'Salvar clima');
    await L.sleep(3500);
    api = L.apiCalls(s, mark);
    const pc = api.find((n) => n.method === 'PATCH' && /\/clima$/.test(n.path));
    C('PATCH /clima 200 com corrigidoPeloUsuario=true e sem token', pc && pc.status === 200 && pc.body?.corrigidoPeloUsuario === true && pc.body?.tokenConsulta === false, pc && `${pc.status} ${JSON.stringify(pc.body)}`);
    C('clima manual aparece no painel (fonte MANUAL)', await L.has(P, '[TESTE] E2E Ensolarado'), (await L.bodyText(P)).match(/MANUAL|Open-Meteo/i)?.[0] || 'sem pill de fonte');
    await L.shot(s, 'J5-clima-manual');

    // ---- J6 clima automático
    id = 'J6';
    mark = s.net.length;
    await L.clickBtn(P, 'CONSULTAR CLIMA AUTOMÁTICO');
    const gotDlg = await L.waitText(P, 'Salvar clima', 20000);
    api = L.apiCalls(s, mark);
    const gc = api.find((n) => n.method === 'GET' && /diario\/clima$/.test(n.path));
    C('GET /api/diario/clima 200', gc && gc.status === 200, gc && String(gc.status));
    C('diálogo abre com a sugestão', gotDlg);
    await L.shot(s, 'J6-sugestao');
    if (gotDlg) {
      mark = s.net.length;
      await L.clickBtn(P, 'Salvar clima');   // sem alterar
      await L.sleep(3500);
      api = L.apiCalls(s, mark);
      const p1 = api.find((n) => n.method === 'PATCH' && /\/clima$/.test(n.path));
      C('confirmar sem alterar: PATCH 200 com corrigidoPeloUsuario=false + tokenConsulta', p1 && p1.status === 200 && p1.body?.corrigidoPeloUsuario === false && p1.body?.tokenConsulta === true, p1 && `${p1.status} ${JSON.stringify(p1.body)}`);
      C('fonte passa a Open-Meteo', /Open-?Meteo/i.test(await L.bodyText(P)), (await L.bodyText(P)).match(/Open-?Meteo|MANUAL/i)?.[0] || '');
      await L.shot(s, 'J6-confirmado');
      // consulta de novo e altera a temperatura
      mark = s.net.length;
      await L.clickBtn(P, 'CONSULTAR CLIMA AUTOMÁTICO');
      await L.waitText(P, 'Salvar clima', 20000);
      await L.fillField(P, 'Temperatura (°C)', '31');
      await L.clickBtn(P, 'Salvar clima');
      await L.sleep(3500);
      api = L.apiCalls(s, mark);
      const p2 = api.find((n) => n.method === 'PATCH' && /\/clima$/.test(n.path));
      C('alterando: PATCH 200 com corrigidoPeloUsuario=true e sem tokenConsulta', p2 && p2.status === 200 && p2.body?.corrigidoPeloUsuario === true && p2.body?.tokenConsulta === false, p2 && `${p2.status} ${JSON.stringify(p2.body)}`);
      const gets = api.filter((n) => /diario\/clima$/.test(n.path)).map((n) => n.status);
      C('segunda consulta GET /clima 200', gets.every((x) => x === 200) && gets.length >= 1, gets.join(','));
      await L.shot(s, 'J6-alterado');
    }

    // ---- J4 (continuação): fechar diário e bloqueio de edição
    id = 'J4';
    mark = s.net.length;
    await L.clickBtn(P, 'APROVAR DIÁRIO');
    await L.waitText(P, 'Aprovar e fechar o diário', 10000);
    await L.clickBtn(P, 'Aprovar', { exact: true });
    await L.sleep(5000);
    api = L.apiCalls(s, mark);
    const ap = api.find((n) => n.method === 'POST' && /\/aprovar$/.test(n.path));
    C('POST /aprovar 200', ap && ap.status === 200, ap && String(ap.status));
    C('status FECHADO na tela', /FECHADO/.test(await statusPill()), await statusPill());
    const tt = await L.bodyText(P);
    C('fechado: botões SALVAR REVISÃO/APROVAR somem', !/SALVAR REVISÃO|APROVAR DIÁRIO/.test(tt));
    const infBtn = L.btn(P, 'INFORMAR CLIMA');
    const dis = await infBtn.evaluate((e) => e.getAttribute('aria-disabled')).catch(() => 'n/a');
    C('fechado: INFORMAR CLIMA desabilitado', dis === 'true', `aria-disabled=${dis}`);
    await L.shot(s, 'J4-fechado');
    L.saveState({ diarioFechado: true });

    // ---- J7 assistente
    id = 'J7';
    await L.clickBtn(P, 'Perguntar', { exact: true });
    C('página Perguntar abriu', await L.waitText(P, 'Pergunte. Volte à fonte', 10000));
    const ask = async (q) => {
      const inp = P.locator('flt-semantics > textarea[aria-label="O que você precisa saber?"], flt-semantics > textarea[placeholder="O que você precisa saber?"]').first();
      await inp.click({ force: true }); await L.sleep(300);
      await P.keyboard.type(q, { delay: 8 });
      const m = s.net.length;
      await L.clickBtn(P, 'Enviar pergunta');
      const start = Date.now();
      let got = null;
      while (Date.now() - start < 120000) {
        await L.sleep(2500);
        const a = L.apiCalls(s, m).find((n) => /assistente\/perguntas$/.test(n.path) && n.status != null);
        if (a) { got = a; break; }
      }
      await L.sleep(2500);
      return { got, m, secs: Math.round((Date.now() - start) / 1000) };
    };
    // conta de perguntas feitas
    let asked = 0;
    const q1 = await ask('[TESTE] O que o diário desta obra registra com o termo TESTE-ZETA?'); asked++;
    C('Q1 POST /perguntas 200', q1.got?.status === 200, `${q1.got?.status} em ${q1.secs}s`);
    await L.shot(s, 'J7-q1');
    let t1 = await L.bodyText(P);
    let hasSrc = /FONTES DA RESPOSTA/.test(t1);
    C('Q1 resposta traz fontes (citações) do diário com TESTE-ZETA', hasSrc && /zeta/i.test(t1), hasSrc ? 'com fontes' : (/SEM FONTE/.test(t1) ? 'SEM FONTE ENCONTRADA' : 'sem fontes'));
    if (!hasSrc) L.finding(s, 'Q1 sobre TESTE-ZETA sem fonte logo após fechar o diário: indexação do diário para o assistente pode ser assíncrona/atrasada.');
    if (!hasSrc) {
      await L.sleep(120000);
      const q1b = await ask('[TESTE] Repetindo: o que consta sobre TESTE-ZETA no diário?'); asked++;
      t1 = await L.bodyText(P);
      hasSrc = /FONTES DA RESPOSTA/.test(t1);
      C('Q1b (após 2 min) traz fontes', hasSrc, `${q1b.got?.status}`);
      await L.shot(s, 'J7-q1b');
    }
    const q2 = await ask('[TESTE] Resuma em uma frase o que foi encontrado.'); asked++;
    const bodies = L.apiCalls(s).filter((n) => /assistente\/perguntas$/.test(n.path));
    C('pergunta seguinte reaproveita sessionId', bodies.length >= 2 && bodies[0].body?.sessionId === false && bodies[bodies.length - 1].body?.sessionId === true, bodies.map((n) => JSON.stringify(n.body?.sessionId)).join(','));
    await L.shot(s, 'J7-q2');
    const q3 = await ask('[TESTE] Qual é a capital da França e quem ganhou a Copa de 1970?'); asked++;
    const t3 = await L.bodyText(P);
    C('pergunta fora do tema: 200', q3.got?.status === 200, `${q3.got?.status}`);
    C('pergunta fora do tema: "SEM FONTE ENCONTRADA"', /SEM FONTE ENCONTRADA/.test(t3), '');
    await L.shot(s, 'J7-q3-fora-do-tema');
    C(`máximo de perguntas respeitado (${asked} <= 4 reservando 1 ao auditor)`, asked <= 4, String(asked));
    L.saveState({ perguntasJ7: asked });
  } else {
    C('etapas seguintes (edição, clima, fechamento, assistente) não executadas por falha de transcrição', false, `status=${st}`);
    console.log((await L.bodyText(P)).slice(0, 1500));
  }
} catch (e) { L.check(s, `${id}/ execução sem exceção`, false, String(e.message).slice(0, 300)); await L.shot(s, 'erro'); console.log((await L.bodyText(P)).slice(0, 1500)); }
L.saveResult(s);
console.log(L.fmtNet(s.net).join('\n'));
console.log('console errors:', s.consoleErrors);
await b.close();
