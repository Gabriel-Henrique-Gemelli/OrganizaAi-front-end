// J3b: (1) teste.png com OCR assíncrono em contexto novo; (2) duplicado no servidor: teste.txt reenviado com cache local vazio (espera 409 -> DUPLICADO).
// Total de arquivos enviados em J3+J3b: 4 + 1 + 1 = 6. Perfil GESTOR, obra '[TESTE] E2E Obra clima'.
import * as L from './lib.mjs';
import fs from 'node:fs';
import path from 'node:path';
const OBRA = '[TESTE] E2E Obra clima';
const b = await L.launch();
const out = { checks: [], findings: [], net: [], consoleErrors: [] };
async function etapa(name, file, expect, fn) {
  const s = await L.newSession(b, name);
  const P = s.page;
  try {
    await L.login(s, 'gestor');
    L.check(s, 'login gestor', await L.waitText(P, 'Hoje', 60000));
    await L.sleep(3000);
    L.check(s, 'obra clima selecionada', await L.selectProject(P, OBRA));
    await L.assertTestProject(P);
    await L.clickBtn(P, 'Enviar', { exact: true });
    await L.waitText(P, 'ARQUIVOS DA OBRA', 10000);
    const mark = s.net.length;
    await L.chooseFiles(P, 'SELECIONAR ARQUIVOS', [path.join(L.FX, file)]);
    const t0 = Date.now();
    let st = '', row = '';
    while (Date.now() - t0 < expect.timeout) {
      await L.sleep(2500);
      const t = await L.bodyText(P);
      row = L.rowAfter(t, file, 300) || '';
      st = row.match(L.STATUS_RE)?.[1] || (/Duplicad/i.test(row) ? 'DUPLICADO' : '');
      L.assertNo400(s);
      if (st && !['Lendo documento', 'Enviando', 'Na fila'].includes(st)) break;
    }
    const secs = Math.round((Date.now() - t0) / 1000);
    await L.shot(s, 'final');
    await fn(s, st, row, secs, mark);
  } catch (e) { L.check(s, 'execução sem exceção', false, String(e.message).slice(0, 300)); await L.shot(s, 'erro'); }
  console.log(L.fmtNet(s.net).join('\n'));
  out.checks.push(...s.checks); out.findings.push(...s.findings); out.net.push(...s.net); out.consoleErrors.push(...s.consoleErrors);
  await s.context.close();
}
await etapa('J3b-png', 'teste.png', { timeout: 4 * 60 * 1000 + 30000 }, async (s, st, row, secs, mark) => {
  L.check(s, 'teste.png OCR dentro de 4 min', st === 'Pronto para conferir' && secs <= 250, `${st} em ${secs}s | ${row.slice(0, 120)}`);
  const api = L.apiCalls(s, mark);
  const s3 = s.net.slice(mark).filter((n) => n.kind === 's3');
  L.check(s, 'png: upload-url 201, PUT S3 200 sem Authorization, confirmar 200', api.some((n) => /upload-url$/.test(n.path) && n.status === 201) && s3.length === 1 && !s3[0].hasAuth && s3[0].status === 200 && api.some((n) => /confirmar-upload$/.test(n.path) && n.status === 200), `${s3.map((n) => n.status + ' auth=' + n.hasAuth)}`);
  const ocr = api.filter((n) => /\/ocr$/.test(n.path)).map((n) => n.status);
  L.check(s, 'png: GET /ocr 202... depois 200', ocr.includes(200), ocr.join(','));
});
await etapa('J3b-dup', 'teste.txt', { timeout: 60000 }, async (s, st, row, secs, mark) => {
  const api = L.apiCalls(s, mark);
  const conf = api.filter((n) => /confirmar-upload$/.test(n.path)).map((n) => n.status);
  const up = api.filter((n) => /upload-url$/.test(n.path)).map((n) => n.status);
  console.log('dup: upload-url', up, 'confirmar', conf, 'linha:', row);
  L.check(s, 'duplicado no servidor vira DUPLICADO na UI (409)', st === 'DUPLICADO' || /duplic|já (foi )?enviad/i.test(row), `status=${st} linha="${row.slice(0, 200)}" upload-url=${up} confirmar=${conf}`);
  L.check(s, 'duplicado: resposta da API é 409 (não 400)', [...up, ...conf].includes(409), `${up} / ${conf}`);
});
fs.writeFileSync(L.RES_DIR + '/J3b.json', JSON.stringify(out, null, 1));
await b.close();
