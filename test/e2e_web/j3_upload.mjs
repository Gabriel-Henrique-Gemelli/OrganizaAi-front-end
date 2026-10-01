// J3: upload de documentos (txt, xlsx síncronos; falso.pdf rejeitado; pdf e png com OCR assíncrono). Perfil GESTOR, obra '[TESTE] E2E Obra clima'.
import * as L from './lib.mjs';
import path from 'node:path';
const OBRA = '[TESTE] E2E Obra clima';
const fx = (n) => path.join(L.FX, n);
const b = await L.launch();
const s = await L.newSession(b, 'J3');
const P = s.page;
const OCR_SLA = 4 * 60 * 1000;
try {
  await L.login(s, 'gestor');
  L.check(s, 'login gestor', await L.waitText(P, 'Hoje', 60000));
  await L.sleep(3000);
  L.check(s, 'obra clima selecionada', await L.selectProject(P, OBRA));
  await L.assertTestProject(P);
  await L.clickBtn(P, 'Enviar', { exact: true });
  L.check(s, 'página Enviar abriu', await L.waitText(P, 'ARQUIVOS DA OBRA', 10000));
  let mark = s.net.length;
  // teste.png tem o MESMO conteúdo de falso.pdf: o front descarta em silêncio o que repete o hash de um item já listado (mesmo com Falha). Por isso o PNG vai na etapa J3b, em contexto novo.
  const files = ['teste.txt', 'teste.xlsx', 'falso.pdf', 'teste.pdf'];
  await L.chooseFiles(P, 'SELECIONAR ARQUIVOS', files.map(fx));
  const t0 = Date.now();
  const done = {};
  const sla = {};
  const end = Date.now() + 10 * 60 * 1000;
  let text = '';
  while (Date.now() < end) {
    await L.sleep(2500);
    text = await L.bodyText(P);
    for (const f of files) {
      const row = L.rowAfter(text, f);
      const st = row && row.match(L.STATUS_RE)?.[1];
      if (st && !['Lendo documento', 'Enviando', 'Na fila'].includes(st) && !done[f]) { done[f] = st; sla[f] = Math.round((Date.now() - t0) / 1000); }
    }
    L.assertNo400(s);
    if (files.every((f) => done[f])) break;
  }
  await L.shot(s, 'lote-final');
  for (const f of files) {
    const row = L.rowAfter(text, f, 400);
    console.log('ROW', f, '=>', row);
  }
  L.check(s, 'teste.txt pronto (síncrono)', done['teste.txt'] === 'Pronto para conferir', `${done['teste.txt']} em ${sla['teste.txt']}s`);
  L.check(s, 'teste.xlsx pronto (síncrono)', done['teste.xlsx'] === 'Pronto para conferir', `${done['teste.xlsx']} em ${sla['teste.xlsx']}s`);
  const fRow = L.rowAfter(text, 'falso.pdf', 500) || '';
  L.check(s, 'falso.pdf termina em Falha', done['falso.pdf'] === 'Falha', fRow.slice(0, 300));
  const msgOk = /formato|não aceito|conteúdo|tipo/i.test(fRow);
  L.check(s, 'falso.pdf mostra mensagem de formato/conteúdo não aceito', msgOk, fRow.slice(0, 300));
  L.check(s, `teste.pdf OCR dentro de 4 min`, done['teste.pdf'] === 'Pronto para conferir' && sla['teste.pdf'] * 1000 <= OCR_SLA + 60000, `${done['teste.pdf']} em ${sla['teste.pdf']}s`);
  // rede
  const api = L.apiCalls(s, mark);
  const s3 = s.net.slice(mark).filter((n) => n.kind === 's3');
  const cnt = (m, p, st) => api.filter((n) => n.method === m && p.test(n.path) && (st == null || n.status === st)).length;
  L.check(s, 'POST upload-url 201 x4', cnt('POST', /upload-url$/, 201) === 4, `${cnt('POST', /upload-url$/, 201)}`);
  L.check(s, 'PUT S3 x4 sem Authorization, 200', s3.filter((n) => n.method === 'PUT').length === 4 && s3.every((n) => !n.hasAuth && n.status === 200), s3.map((n) => `${n.method} ${n.status} auth=${n.hasAuth}`).join(';'));
  const conf = api.filter((n) => /confirmar-upload$/.test(n.path)).map((n) => n.status);
  L.check(s, 'confirmar-upload: 3x200 e falso.pdf rejeitado com 415', conf.filter((x) => x === 200).length === 3 && conf.filter((x) => x === 415).length === 1, conf.join(','));
  const ocr = api.filter((n) => n.method === 'GET' && /\/ocr$/.test(n.path)).map((n) => n.status);
  L.check(s, 'GET /ocr retornou 202 e 200 (pipeline assíncrono)', ocr.includes(200) && ocr.includes(202), ocr.join(','));
  // duplicado local: reenviar teste.txt no mesmo navegador
  mark = s.net.length;
  await L.chooseFiles(P, 'SELECIONAR ARQUIVOS', [fx('teste.txt')]);
  await L.sleep(4000);
  const again = (await L.bodyText(P)).split('teste.txt').length - 1;
  L.check(s, 'reenviar teste.txt no mesmo navegador: ignorado localmente, sem chamada /api', L.apiCalls(s, mark).length === 0, `ocorrências na tela=${again}, chamadas=${L.apiCalls(s, mark).length}`);
  if (L.apiCalls(s, mark).length === 0) L.finding(s, 'Duplicata enviada no mesmo navegador é descartada em silêncio (só grava no log interno): nenhum aviso ao usuário. O estado DUPLICADO só aparece com cache local vazio (409 do servidor).');
  L.saveState({ j3done: true });
} catch (e) { L.check(s, 'execução sem exceção', false, String(e.message).slice(0, 300)); await L.shot(s, 'erro'); console.log((await L.bodyText(P)).slice(0, 1500)); }
L.saveResult(s);
console.log(L.fmtNet(s.net).join('\n'));
console.log('console errors:', s.consoleErrors);
await b.close();
