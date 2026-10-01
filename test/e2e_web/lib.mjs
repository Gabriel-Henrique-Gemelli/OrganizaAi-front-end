// Utilitários comuns das jornadas E2E (Flutter web CanvasKit). Sem segredos: senhas vêm de ~/.config/organizai-e2e/pw.json.
import { chromium } from '/home/gabriel-henrique-gemelli/Documentos/TCC/dtms-frontend/node_modules/playwright/index.mjs';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

export const HOME = os.homedir();
export const BASE = 'http://localhost:8081';
export const FX = path.join(HOME, '.cache/organizai-e2e/fx');
export const SHOTS = path.join(HOME, '.cache/organizai-e2e/shots');
export const RES_DIR = path.join(HOME, '.cache/organizai-e2e/results');
fs.mkdirSync(SHOTS, { recursive: true });
fs.mkdirSync(RES_DIR, { recursive: true });
const creds = JSON.parse(fs.readFileSync(path.join(HOME, '.config/organizai-e2e/pw.json'), 'utf8'));
export const LOGIN = { admin: 'teste@organizai.dev', gestor: 'teste-gestor', colaborador: 'teste-colaborador', revisor: 'teste-revisor', auditor: 'teste-auditor' };
export const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

export async function launch() {
  return chromium.launch({ headless: true, args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
}

/** Contexto novo + página com captura de rede (sem valores de cabeçalhos/corpo) e erros do console. */
export async function newSession(browser, name, opts = {}) {
  const context = await browser.newContext({ viewport: { width: 1280, height: 900 }, acceptDownloads: true, ...opts });
  const page = await context.newPage();
  const net = [];
  const consoleErrors = [];
  const t0 = Date.now();
  const pending = new Map();
  page.on('request', (r) => {
    const u = new URL(r.url());
    let kind = null;
    if (u.host === 'api.organizaii.com.br') kind = 'api';
    else if (u.host.startsWith('cognito-idp')) kind = 'cognito';
    else if (u.host.includes('amazonaws.com') && /s3/.test(u.host)) kind = 's3';
    if (!kind) return;
    if (r.method() === 'OPTIONS') return;
    const h = r.headers();
    let op = '';
    if (kind === 'cognito') op = (h['x-amz-target'] || '').split('.').pop();
    const rec = { t: Date.now() - t0, kind, method: r.method(), path: kind === 's3' ? u.host.split('.')[0] + u.pathname.replace(/[0-9a-f-]{36}/g, ':id') : u.pathname, op, hasAuth: 'authorization' in h, status: null };
    if (kind === 'api' && /\/clima$|\/perguntas$/.test(u.pathname) && ['PATCH', 'POST'].includes(r.method())) {
      try { const j = JSON.parse(r.postData() || '{}'); rec.body = { corrigidoPeloUsuario: j.corrigidoPeloUsuario, tokenConsulta: 'tokenConsulta' in j, sessionId: 'sessionId' in j && !!j.sessionId, campos: Object.keys(j).filter((k) => !['question', 'pergunta', 'tokenConsulta', 'sessionId'].includes(k)) }; } catch {}
    }
    pending.set(r, rec);
    net.push(rec);
  });
  page.on('response', (resp) => { const rec = pending.get(resp.request()); if (rec) rec.status = resp.status(); });
  page.on('requestfailed', (r) => { const rec = pending.get(r); if (rec && rec.status == null) rec.status = 'FAILED:' + (r.failure()?.errorText || ''); });
  page.on('console', (m) => { if (m.type() === 'error') consoleErrors.push(m.text().slice(0, 300)); });
  page.on('pageerror', (e) => consoleErrors.push('pageerror: ' + String(e.message).slice(0, 300)));
  return { name, context, page, net, consoleErrors, findings: [], checks: [] };
}

export function check(s, id, ok, detail = '') {
  s.checks.push({ id, ok: !!ok, detail });
  console.log(`${ok ? 'PASS' : 'FAIL'}  [${s.name}] ${id} ${detail}`);
  return !!ok;
}
export function finding(s, text) { s.findings.push(text); console.log(`ACHADO [${s.name}] ${text}`); }
export const apiCalls = (s, from = 0) => s.net.slice(from).filter((n) => n.kind === 'api');
export const fmtNet = (list) => list.map((n) => `${n.method} ${n.path}${n.op ? ' (' + n.op + ')' : ''}${n.body ? ' body=' + JSON.stringify(n.body) : ''} -> ${n.status}${n.kind === 's3' ? (n.hasAuth ? ' [COM Authorization]' : ' [sem Authorization]') : ''}`);
export function count400(s) { return s.net.filter((n) => n.kind === 'api' && n.status === 400).length; }
export function assertNo400(s) {
  if (count400(s) > 0) { console.log('!!! 400 INESPERADO DA API, abortando'); throw new Error('HTTP 400 inesperado da API'); }
}

export async function shot(s, label) {
  const f = path.join(SHOTS, `${s.name}-${label}.png`.replace(/[^\w.\-]/g, '_'));
  await s.page.screenshot({ path: f }).catch(() => {});
  return f;
}

/** Ativa a árvore de semântica do Flutter após uma navegação completa. */
export async function activate(page) {
  await page.waitForSelector('flt-glass-pane', { state: 'attached', timeout: 90000 });
  await page.waitForSelector('flt-semantics-placeholder', { state: 'attached', timeout: 60000 }).catch(() => {});
  for (let i = 0; i < 5; i++) {
    if (await page.$('flt-semantics-host flt-semantics')) return;
    const ph = await page.$('flt-semantics-placeholder');
    if (ph) await ph.dispatchEvent('click');
    await sleep(1200);
  }
  await page.waitForSelector('flt-semantics-host flt-semantics', { state: 'attached', timeout: 30000 });
}
export async function openApp(s) {
  await s.page.goto(BASE, { waitUntil: 'load' });
  await activate(s.page);
  await sleep(1500);
}

/** Dump textual da árvore de semântica visível. */
export async function dump(page) {
  return page.evaluate(() => [...document.querySelectorAll('flt-semantics')].map((e) => {
    const inp = e.querySelector(':scope > input, :scope > textarea');
    return { role: e.getAttribute('role') || '', label: (e.getAttribute('aria-label') || '').trim(), text: (e.textContent || '').trim().slice(0, 200), input: !!inp, disabled: e.getAttribute('aria-disabled') === 'true' };
  }));
}
export async function bodyText(page) {
  return page.evaluate(() => {
    const out = [];
    for (const e of document.querySelectorAll('flt-semantics')) {
      const al = e.getAttribute('aria-label'); if (al) out.push(al);
      for (const n of e.childNodes) {
        if (n.nodeType === 3 && n.textContent.trim()) out.push(n.textContent);
        else if (n.nodeType === 1 && n.tagName === 'SPAN') out.push(n.textContent);
      }
    }
    return out.join(' \n ').replace(/\s+/g, ' ');
  });
}
const esc = (t) => t.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
/** Botão (role=button) cujo texto contém/igual ao informado (sem diferenciar maiúsculas). */
export function btn(page, text, { exact = false } = {}) {
  return page.locator('flt-semantics[role="button"]').filter({ hasText: new RegExp(exact ? '^\\s*' + esc(text) + '\\s*$' : esc(text), 'i') }).first();
}
/** Qualquer nó semântico com o texto (o mais interno). */
export function txt(page, text) {
  return page.locator('flt-semantics').filter({ hasText: new RegExp(esc(text), 'i') }).last();
}
/** Campo de texto (input/textarea) logo abaixo do rótulo informado; rola a página/diálogo até ele ficar na faixa clicável. */
export async function fieldHandle(page, label, { nth = 0, scroll = true } = {}) {
  for (let attempt = 0; attempt < 30; attempt++) {
    const r = await page.evaluate(({ label, nth }) => {
      const norm = (x) => (x || '').replace(/\s+/g, ' ').trim().toLowerCase();
      const nodes = [...document.querySelectorAll('flt-semantics')].filter((e) => { const sp = e.querySelector(':scope > span'); return sp && norm(sp.textContent) === norm(label); });
      const inputs = [...document.querySelectorAll('flt-semantics > input, flt-semantics > textarea')];
      const cands = [];
      for (const n of nodes) {
        const lr = n.getBoundingClientRect();
        let best = null, bd = 1e9;
        for (const i of inputs) {
          const ir = i.getBoundingClientRect();
          const dy = ir.top - (lr.bottom - 6);
          if (dy >= -2 && dy < 90 && dy < bd && ir.left < lr.right + 400 && ir.right > lr.left - 400) { bd = dy; best = i; }
        }
        if (best) cands.push(best);
      }
      const el = cands[nth];
      if (!el) return { found: false };
      const b = el.getBoundingClientRect();
      window.__e2eField = el;
      return { found: true, top: b.top, bottom: b.bottom, vh: window.innerHeight };
    }, { label, nth });
    if (r.found && r.top >= 100 && r.bottom <= r.vh - 110) {
      const h = await page.evaluateHandle(() => window.__e2eField);
      return h.asElement();
    }
    if (!scroll) break;
    await page.mouse.move(640, 450);
    const dir = r.found && r.top < 100 ? -1 : 1;
    await page.mouse.wheel(0, dir * 180);
    await sleep(350);
  }
  throw new Error('campo não encontrado: ' + label);
}
export async function fillField(page, label, value, opts = {}) {
  const el = await fieldHandle(page, label, opts);
  await el.click({ force: true });
  await sleep(150);
  await page.keyboard.press('Control+A');
  await page.keyboard.press('Delete');
  if (value !== '') await page.keyboard.type(value, { delay: 15 });
  await sleep(150);
}
export async function readField(page, label, opts = {}) {
  const el = await fieldHandle(page, label, opts);
  await el.click({ force: true });
  await sleep(400);
  return el.inputValue();
}
export async function clickBtn(page, text, opts = {}) {
  const l = btn(page, text, opts);
  await l.waitFor({ state: 'attached', timeout: 20000 });
  await l.dispatchEvent('click');
  await sleep(600);
}
export async function has(page, text) {
  return (await bodyText(page)).toLowerCase().includes(text.toLowerCase());
}
export async function waitText(page, text, timeout = 30000) {
  const end = Date.now() + timeout;
  while (Date.now() < end) { if (await has(page, text)) return true; await sleep(700); }
  return false;
}

export function password(profile) { return creds[profile]; }
export const pwdFor = password;

export async function login(s, profile) {
  await openApp(s);
  await fillField(s.page, 'Usuário ou e-mail', LOGIN[profile]);
  await fillField(s.page, 'Senha', password(profile));
  await clickBtn(s.page, 'ENTRAR', { exact: true });
}
export async function waitLoggedIn(s, timeout = 60000) {
  return waitText(s.page, 'SELECIONE UMA OBRA', timeout) || false;
}

export function saveResult(s, extra = {}) {
  const out = { name: s.name, checks: s.checks, findings: s.findings, net: s.net, consoleErrors: s.consoleErrors, ...extra };
  fs.writeFileSync(path.join(RES_DIR, `${s.name}.json`), JSON.stringify(out, null, 1));
}
export function loadState() { try { return JSON.parse(fs.readFileSync(path.join(RES_DIR, 'state.json'), 'utf8')); } catch { return {}; } }
export function saveState(st) { fs.writeFileSync(path.join(RES_DIR, 'state.json'), JSON.stringify({ ...loadState(), ...st }, null, 1)); }

/** Seleciona a obra ativa no dropdown da sidebar (pelo nome). Retorna true se o cabeçalho passou a mostrá-la. */
export async function selectProject(page, name) {
  const dd = page.locator('flt-semantics[role="button"]').filter({ hasText: /OBRA DE DESENVOLVIMENTO|\[TESTE\]|SELECIONE|OBRA TESTE/i }).first();
  await dd.dispatchEvent('click');
  await sleep(1000);
  const item = page.locator(`flt-semantics[role="menuitem"][aria-label="${name.toUpperCase()}"]`).first();
  await item.waitFor({ state: 'attached', timeout: 10000 });
  await item.dispatchEvent('click');
  await sleep(2000);
  return (await bodyText(page)).toUpperCase().includes(name.toUpperCase() + ' ·');
}
/** Falha se a obra ativa (cabeçalho) não for uma obra '[TESTE] E2E'. */
export async function assertTestProject(page) {
  const t = (await bodyText(page)).toUpperCase();
  if (!t.includes('[TESTE] E2E')) throw new Error('obra ativa não é [TESTE] E2E; abortando ação de escrita');
}

/** Trecho do texto da tela logo após o nome de um arquivo (tamanho · status · mensagem). */
export function rowAfter(text, name, len = 260) {
  const i = text.indexOf(name);
  return i < 0 ? null : text.slice(i, i + len);
}
export const STATUS_RE = /(Pronto para conferir|Conferido|Lendo documento|Enviando|Na fila|Leitura parcial|Consulta pausada|Cancelado|Falha)/;
/** Clica num botão com clique real (gesto confiável) e devolve o file chooser. */
export async function chooseFiles(page, buttonText, files) {
  const l = btn(page, buttonText);
  await l.waitFor({ state: 'attached', timeout: 20000 });
  let fc;
  try {
    [fc] = await Promise.all([page.waitForEvent('filechooser', { timeout: 8000 }), l.click({ force: true })]);
  } catch {
    [fc] = await Promise.all([page.waitForEvent('filechooser', { timeout: 8000 }), l.dispatchEvent('click')]);
  }
  await fc.setFiles(files);
}
