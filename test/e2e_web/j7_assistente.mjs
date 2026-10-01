// J7 (reexecução): assistente com 3 perguntas em UM contexto (sessão reaproveitada) + fora do tema. A Q1 (TESTE-ZETA) já rodou em j4_j7.
// Orçamento total: 5 perguntas = 1 (Q1 em j4_j7) + 3 aqui + 1 do auditor (J9). Perfil GESTOR, obra '[TESTE] E2E Obra clima'.
import * as L from './lib.mjs';
const OBRA = '[TESTE] E2E Obra clima';
const b = await L.launch();
const s = await L.newSession(b, 'J7');
const P = s.page;
const SEL = 'flt-semantics > textarea[aria-label="O que você precisa saber?"], flt-semantics > textarea[placeholder="O que você precisa saber?"]';
try {
  await L.login(s, 'gestor');
  L.check(s, 'login gestor', await L.waitText(P, 'Hoje', 60000));
  await L.sleep(3000);
  L.check(s, 'obra clima selecionada', await L.selectProject(P, OBRA));
  await L.assertTestProject(P);
  await L.clickBtn(P, 'Perguntar', { exact: true });
  L.check(s, 'página Perguntar abriu', await L.waitText(P, 'Pergunte. Volte à fonte', 10000));
  const ask = async (q) => {
    const inp = P.locator(SEL).first();
    await inp.click({ force: true }); await L.sleep(300);
    await P.keyboard.type(q, { delay: 8 });
    await L.sleep(300);
    const typed = await inp.inputValue();
    if (typed !== q) throw new Error('texto digitado não confere; pergunta NÃO enviada');
    const m = s.net.length;
    await L.clickBtn(P, 'Enviar pergunta');
    const start = Date.now(); let got = null;
    while (Date.now() - start < 120000) { await L.sleep(2000); got = L.apiCalls(s, m).find((n) => /assistente\/perguntas$/.test(n.path) && n.status != null); if (got) break; }
    await L.sleep(3000);
    return { got, secs: Math.round((Date.now() - start) / 1000) };
  };
  const qa = await ask('[TESTE] Quais serviços foram registrados no diário de hoje desta obra?');
  const ta = await L.bodyText(P);
  L.check(s, 'Qa: POST /perguntas 200', qa.got?.status === 200, `${qa.got?.status} em ${qa.secs}s`);
  L.check(s, 'Qa: resposta com fontes (diário) e citação legível', /FONTES DA RESPOSTA/.test(ta) && /Diário de obra/.test(ta), '');
  if (/\*\*/.test(ta)) L.finding(s, 'A resposta do assistente chega com Markdown cru (asteriscos **negrito** e marcadores de fonte "[6]") exibido literalmente na tela.');
  await L.shot(s, 'qa');
  const qb = await ask('[TESTE] E quantas pessoas trabalharam nesse dia?');
  const bodies = L.apiCalls(s).filter((n) => /assistente\/perguntas$/.test(n.path));
  L.check(s, 'Qb: POST /perguntas 200', qb.got?.status === 200, `${qb.got?.status} em ${qb.secs}s`);
  L.check(s, 'sessão reaproveitada: 1ª sem sessionId, 2ª com sessionId', bodies.length >= 2 && bodies[0].body?.sessionId === false && bodies[1].body?.sessionId === true, bodies.map((n) => JSON.stringify(n.body?.sessionId)).join(','));
  await L.shot(s, 'qb');
  const qc = await ask('[TESTE] Qual é a capital da França e quem ganhou a Copa do Mundo de 1970?');
  const tc = await L.bodyText(P);
  L.check(s, 'Qc fora do tema: POST 200', qc.got?.status === 200, `${qc.got?.status} em ${qc.secs}s`);
  L.check(s, 'Qc fora do tema: "SEM FONTE ENCONTRADA"', /SEM FONTE ENCONTRADA/.test(tc), '');
  const last = tc.slice(tc.lastIndexOf('[TESTE] Qual é a capital'));
  console.log('Resposta fora do tema (trecho):', last.slice(0, 400));
  await L.shot(s, 'qc-fora-do-tema');
  L.check(s, 'máx. 5 perguntas no total (aqui 3)', L.apiCalls(s).filter((n) => /perguntas$/.test(n.path)).length === 3, '');
} catch (e) { L.check(s, 'execução sem exceção', false, String(e.message).slice(0, 300)); await L.shot(s, 'erro'); console.log((await L.bodyText(P)).slice(0, 1200)); }
L.saveResult(s);
console.log(L.fmtNet(s.net).join('\n'));
console.log('console errors:', s.consoleErrors);
await b.close();
