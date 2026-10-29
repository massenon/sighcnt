'use strict';
/* =============================================================================
 * SIGH-CNT — BANC DE SYNCHRONISATION : le commutateur de réseau
 * -----------------------------------------------------------------------------
 * Un relais TCP entre les postes et la mère. Trois états, changés EN COURS DE ROUTE :
 *   ouvert        — le réseau fonctionne
 *   ferme         — plus rien ne passe (câble arraché) ; les connexions ouvertes sont coupées
 *   perd_reponse  — la requête d'ENVOI arrive et la mère la TRAITE, mais la réponse n'est jamais
 *                   rendue : le cas qui fabrique les doublons si le rejeu n'est pas idempotent
 * ========================================================================== */
const net = require('node:net');

class Commutateur {
  constructor(portMere) { this.portMere = portMere; this.mode = 'ouvert'; this.socks = new Set(); this.transmises = 0; this.reponsesPerdues = 0; this.retardPull = 0; }
  demarrer() {
    return new Promise((ok) => {
      this.serveur = net.createServer((client) => {
        if (this.mode === 'ferme') { client.destroy(); return; }
        const amont = net.connect(this.portMere, '127.0.0.1');
        this.socks.add(client); this.socks.add(amont);
        const fin = () => { client.destroy(); amont.destroy(); this.socks.delete(client); this.socks.delete(amont); };
        client.on('error', fin); amont.on('error', fin); client.on('close', fin); amont.on('close', fin);
        let perdre = false; let lent = false;
        client.on('data', (d) => {
          this.transmises++;
          /* Au début de CHAQUE requête on décide du sort de sa réponse : seul l'ENVOI
             d'un lot (POST /sync/push) a sa réponse perdue — c'est le cas qui fabrique des
             doublons ; le tirage qui précède, lui, passe (sinon l'envoi n'aurait jamais lieu). */
          const debut = d.toString('latin1', 0, 24);
          if (/^(GET|POST|PUT|DELETE) /.test(debut)) perdre = this.mode === 'perd_reponse' && /^POST \/sync\/push/.test(debut);
          if (/^(GET|POST|PUT|DELETE) /.test(debut)) lent = this.retardPull > 0 && /^GET \/sync\/pull/.test(debut);
          amont.write(d);
        });
        amont.on('data', (d) => {
          if (perdre) { this.reponsesPerdues++; setTimeout(fin, 10); return; }
          if (lent) setTimeout(() => { if (!client.destroyed) client.write(d); }, this.retardPull); else client.write(d);
        });
      });
      this.serveur.listen(0, '127.0.0.1', () => ok(this.serveur.address().port));
    });
  }
  regler(mode) {
    this.mode = mode;
    if (mode !== 'ouvert') for (const s of this.socks) s.destroy();
  }
  arreter() { for (const s of this.socks) s.destroy(); this.serveur.close(); }
}
module.exports = { Commutateur };
