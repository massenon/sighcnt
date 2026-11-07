/* PUITS SMTP DE TEST — serveur SMTP minimal, sans dépendance. Il sert à PROUVER qu'un message part vraiment par le protocole :
 * EHLO, STARTTLS (certificat auto-signé engendré par openssl) ou SSL, AUTH PLAIN et LOGIN, MAIL FROM, RCPT TO, DATA avec dot-unstuffing.
 * Il garde les messages reçus (décodés : entêtes RFC 2047 et corps base64) et les commandes vues, pour que le test lise ce qui a VRAIMENT circulé.
 *
 *   const { demarrerPuits } = require('./_smtp_sink');
 *   const puits = await demarrerPuits({ user: 'clinique', pass: 'secret', mode: 'starttls' | 'ssl' | 'aucun', refuser: ['mauvais@x.bj'], echo: true });
 *   (echo : un serveur MALADROIT dont le refus recopie le mot de passe reçu, pour prouver que le client le masque)
 *   puits.port, puits.messages, puits.commandes, await puits.fermer()
 * Ligne de commande : node build/_smtp_sink.js --port=2525 --user=u --pass=p --mode=starttls   (affiche « PRET <port> »).
 */
const net = require('net');
const tls = require('tls');
const os = require('os');
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

function certificat() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'sigh-smtp-cert-'));
  execFileSync('openssl', ['req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-keyout', path.join(dir, 'k.pem'), '-out', path.join(dir, 'c.pem'),
    '-days', '2', '-subj', '/CN=localhost'], { stdio: 'ignore' });
  return { key: fs.readFileSync(path.join(dir, 'k.pem')), cert: fs.readFileSync(path.join(dir, 'c.pem')), dir };
}

function decoderEntete(v) {
  return v.replace(/=\?UTF-8\?B\?([^?]*)\?=/gi, (_, b) => Buffer.from(b, 'base64').toString('utf8'));
}

function analyser(brut) {
  const [tete, ...reste] = brut.split('\r\n\r\n');
  const corpsBrut = reste.join('\r\n\r\n');
  const entetes = {};
  tete.replace(/\r\n[ \t]+/g, ' ').split('\r\n').forEach((l) => { const i = l.indexOf(':'); if (i > 0) entetes[l.slice(0, i).toLowerCase()] = decoderEntete(l.slice(i + 1).trim()); });
  const corps = /base64/i.test(entetes['content-transfer-encoding'] || '') ? Buffer.from(corpsBrut.replace(/\s+/g, ''), 'base64').toString('utf8') : corpsBrut;
  return { entetes, corps, brut };
}

async function demarrerPuits(opts = {}) {
  const user = opts.user, pass = opts.pass, mode = opts.mode || 'aucun';
  const refuser = (opts.refuser || []).map((x) => x.toLowerCase());
  const cert = mode === 'aucun' ? null : certificat();
  const puits = { messages: [], commandes: [], connexions: 0 };

  function session(brute) {
    let socket = brute, tampon = '', enData = false, donnees = '', auth = null, chiffre = mode === 'ssl', authentifie = !user, de = null, a = [];
    const dire = (t) => { socket.write(t + '\r\n'); };
    const lignes = () => {
      for (;;) {
        if (enData) {
          const fin = tampon.indexOf('\r\n.\r\n');
          if (fin < 0) return;
          donnees = tampon.slice(0, fin);
          tampon = tampon.slice(fin + 5);
          enData = false;
          const m = analyser(donnees.replace(/^\.\./gm, '.'));
          m.de = de; m.a = a.slice();
          puits.messages.push(m);
          dire('250 2.0.0 message accepté, file ' + puits.messages.length);
          continue;
        }
        const i = tampon.indexOf('\r\n');
        if (i < 0) return;
        const l = tampon.slice(0, i);
        tampon = tampon.slice(i + 2);
        traiter(l);
      }
    };
    function traiter(l) {
      if (auth === 'login-user') { auth = { user: Buffer.from(l, 'base64').toString() }; dire('334 ' + Buffer.from('Password:').toString('base64')); return; }
      if (auth && auth.user !== undefined) {
        const recu = Buffer.from(l, 'base64').toString(); const ok = auth.user === user && recu === pass;
        puits.commandes.push('AUTH LOGIN ' + (ok ? 'ok' : 'refusé'));
        auth = null; authentifie = ok; dire(ok ? '235 2.7.0 authentifié' : '535 5.7.8 identifiants invalides' + (opts.echo ? ' (reçu : ' + recu + ')' : '')); return;
      }
      const cmd = l.split(' ')[0].toUpperCase();
      puits.commandes.push(cmd === 'AUTH' ? 'AUTH ' + l.split(' ')[1] : l.replace(/^(AUTH \S+).*/i, '$1'));
      if (cmd === 'EHLO' || cmd === 'HELO') {
        const ext = ['250-puits.test', '250-8BITMIME'];
        if (mode === 'starttls' && !chiffre) ext.push('250-STARTTLS');
        if (user && (mode === 'aucun' || chiffre)) ext.push('250-AUTH PLAIN LOGIN');
        ext.push('250 SIZE 10485760');
        socket.write(ext.join('\r\n') + '\r\n'); return;
      }
      if (cmd === 'STARTTLS') {
        if (mode !== 'starttls' || chiffre) { dire('454 4.7.0 TLS indisponible'); return; }
        dire('220 2.0.0 prêt à négocier');
        const brut = socket; brut.removeAllListeners('data');
        const s = new tls.TLSSocket(brut, { isServer: true, key: cert.key, cert: cert.cert });
        s.on('error', () => {}); socket = s; chiffre = true; tampon = ''; s.on('data', (d) => { tampon += d.toString('utf8'); lignes(); });
        return;
      }
      if (cmd === 'AUTH') {
        const [, meca, init] = l.split(' ');
        if (!user) { dire('503 5.5.1 authentification non attendue'); return; }
        if (String(meca).toUpperCase() === 'PLAIN') {
          const [, u, p] = Buffer.from(init || '', 'base64').toString().split('\0');
          const ok = u === user && p === pass; authentifie = ok;
          puits.commandes.push('AUTH PLAIN ' + (ok ? 'ok' : 'refusé'));
          dire(ok ? '235 2.7.0 authentifié' : '535 5.7.8 identifiants invalides' + (opts.echo ? ' (reçu : ' + p + ')' : '')); return;
        }
        if (String(meca).toUpperCase() === 'LOGIN') { auth = 'login-user'; dire('334 ' + Buffer.from('Username:').toString('base64')); return; }
        dire('504 5.5.4 mécanisme inconnu'); return;
      }
      if (cmd === 'MAIL') { if (!authentifie) { dire('530 5.7.0 authentification requise'); return; } de = (l.match(/<([^>]*)>/) || [])[1]; a = []; dire('250 2.1.0 ok'); return; }
      if (cmd === 'RCPT') {
        const d = (l.match(/<([^>]*)>/) || [])[1] || '';
        if (refuser.includes(d.toLowerCase())) { dire('550 5.1.1 destinataire inconnu'); return; }
        a.push(d); dire('250 2.1.5 ok'); return;
      }
      if (cmd === 'DATA') { enData = true; dire('354 fin par <CRLF>.<CRLF>'); return; }
      if (cmd === 'QUIT') { dire('221 2.0.0 au revoir'); socket.end(); return; }
      if (cmd === 'RSET' || cmd === 'NOOP') { dire('250 ok'); return; }
      dire('502 5.5.2 commande inconnue');
    }
    socket.on('error', () => {});
    socket.on('data', (d) => { tampon += d.toString('utf8'); lignes(); });
    dire('220 puits.test ESMTP');
  }

  puits.serveur = mode === 'ssl'
    ? tls.createServer({ key: cert.key, cert: cert.cert }, (s) => { puits.connexions++; session(s); })
    : net.createServer((s) => { puits.connexions++; session(s); });
  await new Promise((ok) => puits.serveur.listen(opts.port || 0, '127.0.0.1', ok));
  puits.port = puits.serveur.address().port;
  puits.fermer = () => new Promise((ok) => { puits.serveur.close(() => ok()); puits.serveur.closeAllConnections && puits.serveur.closeAllConnections(); setTimeout(ok, 300); });
  puits.dernier = () => puits.messages[puits.messages.length - 1] || null;
  return puits;
}

module.exports = { demarrerPuits };

if (require.main === module) {
  const a = (n, d) => { const x = process.argv.find((y) => y.startsWith('--' + n + '=')); return x ? x.split('=').slice(1).join('=') : d; };
  demarrerPuits({ port: Number(a('port', 0)), user: a('user', ''), pass: a('pass', ''), mode: a('mode', 'aucun'), refuser: a('refuser', '').split(',').filter(Boolean), echo: a('echo', '') === '1' }).then((p) => {
    console.log('PRET ' + p.port);
    /* à chaque message reçu, une ligne JSON sur la sortie standard : le processus qui pilote le puits les lit (tests Dart) */
    let vus = 0;
    setInterval(() => { while (vus < p.messages.length) { const m = p.messages[vus++]; console.log('MSG ' + JSON.stringify({ de: m.de, a: m.a, entetes: m.entetes, corps: m.corps, commandes: p.commandes })); } }, 50);
    process.on('SIGTERM', () => process.exit(0));
  });
}
