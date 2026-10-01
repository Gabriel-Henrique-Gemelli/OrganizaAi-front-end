// J1: login SRP (admin) + senha errada sem chamadas /api.
import * as L from './lib.mjs';
const b = await L.launch();
const s = await L.newSession(b, 'J1');
try {
  await L.openApp(s);
  // --- senha errada (Cognito recusa; nenhuma chamada /api)
  await L.fillField(s.page, 'Usuário ou e-mail', L.LOGIN.admin);
  await L.fillField(s.page, 'Senha', 'senha-errada-e2e-xyz');
  await L.clickBtn(s.page, 'ENTRAR', { exact: true });
  const shown = await L.waitText(s.page, 'Acesso não autorizado', 25000);
  await L.shot(s, 'senha-errada');
  L.check(s, 'senha errada mostra "Acesso não autorizado"', shown);
  L.check(s, 'senha errada: nenhuma chamada /api', L.apiCalls(s).length === 0, `${L.apiCalls(s).length} chamadas`);
  const cog = s.net.filter((n) => n.kind === 'cognito').map((n) => n.op + ':' + n.status);
  L.check(s, 'senha errada: Cognito InitiateAuth e RespondToAuthChallenge executados', cog.some((x) => x.startsWith('InitiateAuth')), cog.join(','));
  const mark = s.net.length;
  // --- login correto
  await L.fillField(s.page, 'Senha', L.password('admin'));
  await L.clickBtn(s.page, 'ENTRAR', { exact: true });
  const ok = await L.waitText(s.page, 'Hoje', 60000);
  await L.sleep(4000);
  await L.shot(s, 'logado');
  L.check(s, 'entrou no workspace', ok);
  const after = s.net.slice(mark);
  const ops = after.filter((n) => n.kind === 'cognito').map((n) => n.op + ':' + n.status);
  console.log('Cognito:', ops.join(' > '));
  const okSrp = ops.join('>').includes('InitiateAuth:200>RespondToAuthChallenge:200>GetUser:200');
  L.check(s, 'SRP InitiateAuth -> RespondToAuthChallenge -> GetUser (200)', okSrp, ops.join(' > '));
  const api = L.apiCalls(s, mark);
  const conta = api.find((n) => n.path === '/api/conta');
  const obras = api.find((n) => n.path === '/api/obras');
  L.check(s, 'GET /api/conta 200', conta && conta.method === 'GET' && conta.status === 200, conta && String(conta.status));
  L.check(s, 'GET /api/obras 200', obras && obras.method === 'GET' && obras.status === 200, obras && String(obras.status));
  const t = await L.bodyText(s.page);
  L.check(s, 'sidebar mostra seções Enviar/Diário/Perguntar (admin)', /Enviar/.test(t) && /Diário/.test(t) && /Perguntar/.test(t));
  L.check(s, '"+ nova" visível para admin', /\+ nova/.test(t));
  // achado: obra ativa pré-selecionada é a SEED
  if (/SEED/i.test(t)) L.finding(s, 'Após o login a obra ativa pré-selecionada é a seed (primeira da lista); ações de envio/diário sem trocar de obra iriam para a seed.');
  L.assertNo400(s);
} catch (e) { L.check(s, 'execução sem exceção', false, String(e.message).slice(0, 200)); await L.shot(s, 'erro'); }
L.saveResult(s);
console.log(L.fmtNet(s.net).join('\n'));
console.log('console errors:', s.consoleErrors.length, s.consoleErrors.slice(0, 5));
await b.close();
