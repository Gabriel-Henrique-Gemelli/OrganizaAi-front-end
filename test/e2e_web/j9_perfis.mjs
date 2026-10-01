// J9: perfis colaborador, revisor, auditor. O REVISOR envia o 2º áudio (diario.ogg) na obra '[TESTE] E2E Obra simples' e fecha o diário.
import * as L from './lib.mjs';
import path from 'node:path';
const CLIMA = '[TESTE] E2E Obra clima', SIMPLES = '[TESTE] E2E Obra simples';
const b = await L.launch();
const results = [];
async function perfil(profile, fn) {
  const s = await L.newSession(b, `J9-${profile}`);
  try {
    await L.login(s, profile);
    L.check(s, 'login ' + profile, await L.waitText(s.page, 'Hoje', 60000));
    await L.sleep(3000);
    await fn(s, s.page);
  } catch (e) { L.check(s, 'execução sem exceção', false, String(e.message).slice(0, 300)); await L.shot(s, 'erro'); console.log((await L.bodyText(s.page)).slice(0, 1200)); }
  const bad = s.net.filter((n) => n.kind === 'api' && [400, 401, 403, 404, 429].includes(n.status));
  L.check(s, 'sem respostas 400/401/403/404/429 da API na rede', bad.length === 0, bad.map((n) => `${n.method} ${n.path} ${n.status}`).join(';'));
  L.saveResult(s);
  console.log(L.fmtNet(s.net).join('\n'));
  console.log('console errors:', s.consoleErrors);
  await s.context.close();
}
const nav = async (P, label) => { await L.clickBtn(P, label, { exact: true }); await L.sleep(1500); };

await perfil('colaborador', async (s, P) => {
  const t = await L.bodyText(P);
  L.check(s, 'não vê "+ nova" (criar obra)', !/\+ nova/.test(t));
  L.check(s, 'não vê "DADOS DA OBRA" (editar obra)', !/DADOS DA OBRA/.test(t));
  await L.selectProject(P, CLIMA);
  await nav(P, 'Enviar');
  L.check(s, 'vê Enviar (SELECIONAR ARQUIVOS)', await L.has(P, 'SELECIONAR ARQUIVOS'));
  await nav(P, 'Diário');
  const d = await L.bodyText(P);
  L.check(s, 'vê o Diário (gravar/importar áudio)', /IMPORTAR ÁUDIO/.test(d) && /INICIAR GRAVAÇÃO/.test(d));
  L.check(s, 'fechar diário: sem entrada no cache não há botão; não verificável por UI sem gastar um 3º áudio', false, 'BLOQUEADO pelo limite de 2 áudios; no código o botão APROVAR DIÁRIO fica visível porém desabilitado (canApprove=false)');
  await nav(P, 'Perguntar');
  L.check(s, 'vê o assistente', await L.has(P, 'Pergunte. Volte à fonte'));
  await nav(P, 'Conta');
  L.check(s, 'Conta mostra o perfil COLABORADOR', /COLABORADOR/i.test(await L.bodyText(P)));
});

await perfil('revisor', async (s, P) => {
  let t = await L.bodyText(P);
  L.check(s, 'não vê "+ nova"', !/\+ nova/.test(t));
  if (/ENVIAR DOCUMENTO/.test(t)) L.finding(s, 'Revisor/Hoje mostra botão "ENVIAR DOCUMENTO" (ou "CONFERIR LEITURAS") sem permissão de envio: leva à tela "Acesso restrito".');
  await L.selectProject(P, SIMPLES);
  await L.assertTestProject(P);
  await nav(P, 'Enviar');
  L.check(s, 'Enviar: "Acesso restrito ao seu perfil."', await L.has(P, 'Acesso restrito ao seu perfil'));
  L.check(s, 'Enviar: sem botão SELECIONAR ARQUIVOS', !(await L.has(P, 'SELECIONAR ARQUIVOS')));
  await nav(P, 'Diário');
  L.check(s, 'vê o Diário', await L.waitText(P, 'IMPORTAR ÁUDIO', 10000));
  await L.fillField(P, 'Função', '[TESTE] E2E Engenheiro');
  const mark = s.net.length;
  await L.chooseFiles(P, 'IMPORTAR ÁUDIO', [path.join(L.FX, 'diario.ogg')]);
  const t0 = Date.now();
  let st = '';
  while (Date.now() - t0 < 6 * 60 * 1000) {
    await L.sleep(4000);
    const tx = await L.bodyText(P);
    st = (tx.match(/(AGUARDANDO REVIS[AÃ]O|FALHA TRANSCRI[CÇ][AÃ]O|FECHADO)/) || [])[1] || '';
    L.assertNo400(s);
    if (st) break;
    const b2 = L.btn(P, 'CONSULTAR TRANSCRIÇÃO');
    if ((Date.now() - t0) > 90000 && (Date.now() - t0) % 40000 < 5000 && await b2.count()) await b2.dispatchEvent('click');
  }
  const secs = Math.round((Date.now() - t0) / 1000);
  await L.shot(s, 'diario-transcrito');
  const api = L.apiCalls(s, mark);
  L.check(s, 'revisor grava diário: upload-url 201, confirmar 200', api.some((n) => /diario\/upload-url$/.test(n.path) && n.status === 201) && api.some((n) => /confirmar-upload$/.test(n.path) && n.status === 200), api.map((n) => `${n.method} ${n.path.split('/').slice(-1)[0]} ${n.status}`).join(';'));
  L.check(s, 'transcrição ogg pronta em até 6 min', /AGUARDANDO/.test(st), `${st} ${secs}s`);
  if (/AGUARDANDO/.test(st)) {
    // edição real do texto revisado (o campo é localizado pelo rótulo)
    const ta = P.locator('flt-semantics > textarea[aria-label="Texto revisado"], flt-semantics > textarea[placeholder="Texto revisado"]').first();
    await ta.click({ force: true }); await L.sleep(500);
    const val = await ta.inputValue();
    L.check(s, 'campo "Texto revisado" traz a transcrição (ogg)', val.length > 20, val.slice(0, 120).replace(/\s+/g, ' '));
    L.check(s, 'transcrição ogg cita TESTE-ZETA (ou variante)', /teste[\s\-–_.,]{0,3}(zeta|z)\b/i.test(val), val.slice(0, 160).replace(/\s+/g, ' '));
    await P.keyboard.press('Control+End');
    await P.keyboard.type(' [TESTE] E2E revisado pelo revisor.', { delay: 10 });
    await L.sleep(400);
    const mE = s.net.length;
    await L.clickBtn(P, 'SALVAR REVISÃO', { exact: true });
    await L.sleep(3500);
    const aE = L.apiCalls(s, mE);
    L.check(s, 'J4 edição: PATCH /texto 200 com texto alterado', aE.some((n) => n.method === 'PATCH' && /\/texto$/.test(n.path) && n.status === 200), aE.map((n) => `${n.method} ${n.path.split('/').slice(-1)[0]} ${n.status}`).join(';'));
    const m2 = s.net.length;
    await L.clickBtn(P, 'APROVAR DIÁRIO');
    await L.waitText(P, 'Aprovar e fechar o diário', 10000);
    await L.clickBtn(P, 'Aprovar', { exact: true });
    await L.sleep(5000);
    const a2 = L.apiCalls(s, m2);
    L.check(s, 'revisor fecha diário: PATCH /texto 200 e POST /aprovar 200', a2.some((n) => /\/texto$/.test(n.path) && n.status === 200) && a2.some((n) => /\/aprovar$/.test(n.path) && n.status === 200), a2.map((n) => `${n.method} ${n.path.split('/').slice(-1)[0]} ${n.status}`).join(';'));
    L.check(s, 'status FECHADO', /FECHADO/.test(await L.bodyText(P)));
    await L.shot(s, 'diario-fechado');
  }
  await nav(P, 'Perguntar');
  L.check(s, 'vê o assistente', await L.has(P, 'Pergunte. Volte à fonte'));
});

await perfil('auditor', async (s, P) => {
  let t = await L.bodyText(P);
  L.check(s, 'não vê "+ nova"', !/\+ nova/.test(t));
  L.check(s, 'não vê "DADOS DA OBRA"', !/DADOS DA OBRA/.test(t));
  if (/ENVIAR DOCUMENTO|REGISTRAR O DIA/.test(t)) L.finding(s, 'Auditor/Hoje mostra "ENVIAR DOCUMENTO"/"REGISTRAR O DIA" sem permissão: levam a "Acesso restrito ao seu perfil" (UI enganosa).');
  L.check(s, 'lê obras (lista no dropdown)', await L.selectProject(P, CLIMA));
  await nav(P, 'Enviar');
  L.check(s, 'Enviar: "Acesso restrito ao seu perfil."', await L.has(P, 'Acesso restrito ao seu perfil'));
  await nav(P, 'Diário');
  L.check(s, 'Diário: "Acesso restrito ao seu perfil."', await L.has(P, 'Acesso restrito ao seu perfil'));
  await nav(P, 'Acervo');
  L.check(s, 'Acervo abre', await L.waitText(P, 'ACERVO DA OBRA', 10000));
  await nav(P, 'Perguntar');
  const inp = P.locator('flt-semantics > textarea[aria-label="O que você precisa saber?"], flt-semantics > textarea[placeholder="O que você precisa saber?"]').first();
  await inp.click({ force: true }); await L.sleep(300);
  await P.keyboard.type('[TESTE] Auditor: o que o diário registra com TESTE-ZETA?', { delay: 8 });
  const mark = s.net.length;
  await L.clickBtn(P, 'Enviar pergunta');
  let got = null; const t0 = Date.now();
  while (Date.now() - t0 < 120000) { await L.sleep(2500); got = L.apiCalls(s, mark).find((n) => /perguntas$/.test(n.path) && n.status != null); if (got) break; }
  L.check(s, 'auditor usa o assistente: POST /perguntas 200', got && got.status === 200, got && String(got.status));
  await L.shot(s, 'pergunta');
});
await b.close();
