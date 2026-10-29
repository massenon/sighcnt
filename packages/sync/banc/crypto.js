'use strict';
/* Enveloppes chiffrées de bout en bout (spec §12) : AES-256-GCM, clé de clinique que SEULS la mère et les
 * appareils détiennent. Le RELAIS n'importe PAS ce fichier. Les métadonnées (id, appareil, sens, rang) sont
 * authentifiées (AAD) : une enveloppe déplacée, rejouée sous un autre rang ou altérée est rejetée. */
const crypto = require('node:crypto');
const nouvelleCle = () => crypto.randomBytes(32);
function chiffrer(cle, obj, m) {
  const nonce = crypto.randomBytes(12);
  const c = crypto.createCipheriv('aes-256-gcm', cle, nonce);
  c.setAAD(Buffer.from(`${m.id}|${m.appareil}|${m.dir}|${m.n}`));
  const ct = Buffer.concat([c.update(JSON.stringify(obj), 'utf8'), c.final()]);
  return { id: m.id, appareil: m.appareil, dir: m.dir, n: m.n, nonce: nonce.toString('base64'), ct: Buffer.concat([ct, c.getAuthTag()]).toString('base64') };
}
function dechiffrer(cle, env) {
  const raw = Buffer.from(env.ct, 'base64');
  const d = crypto.createDecipheriv('aes-256-gcm', cle, Buffer.from(env.nonce, 'base64'));
  d.setAAD(Buffer.from(`${env.id}|${env.appareil}|${env.dir}|${env.n}`));
  d.setAuthTag(raw.subarray(raw.length - 16));
  return JSON.parse(Buffer.concat([d.update(raw.subarray(0, raw.length - 16)), d.final()]).toString('utf8'));
}
module.exports = { nouvelleCle, chiffrer, dechiffrer };
