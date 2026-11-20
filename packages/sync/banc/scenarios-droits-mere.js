'use strict';
/* Scénario P6 : la mère Dart décide avec la MATRICE RBAC (production), pas avec la table du banc. Un poste du banc émet une opération sous le rôle `x` (permis par la table
   du banc, inconnu de la matrice) : la mère à la matrice la REFUSE en le nommant (`droit_refuse`) ; sous la table du banc elle l'aurait acceptée. Ne s'exécute qu'avec
   SIGH_MERE=dart (la mère Node n'a pas de matrice). */
module.exports = ({ monde, verifier, attendre, dormir, titre }) => ({
  async P6() {
    titre = typeof titre === 'function' ? titre : () => {};
    titre('PAIR-P6 · la mère Dart décide avec la matrice RBAC : un rôle sans droit est refusé, nommé ; la table du banc l\'aurait accepté');
    if (process.env.SIGH_MERE !== 'dart') { verifier('P6 ignoré : la mère Node n\'a pas de matrice (SIGH_MERE=dart requis)', true); return; }
    for (const mode of ['banc', 'matrice']) {
      const m = await monde({ relais: true });
      await m.mere.tuer();
      m.mere.opts.cle = Buffer.from(m.clePair, 'hex').toString('base64');
      m.mere.opts.droits = mode;
      const f1 = await m.pair('F1');
      await f1.emettre({ collection: 'patients', fiche: 'p1', type: 'creer', champs: { nom: 'AKPO' }, role: 'reception' });
      await f1.emettre({ collection: 'patients', fiche: 'p2', type: 'creer', champs: { nom: 'INTRUS' }, role: 'x' });
      await m.mere.demarrer();
      const etat = () => m.mere.admin('GET', '/admin/pair/etat').then((r) => r.json);
      await attendre(async () => (await etat()).ops === 2, 15000);
      const e = await etat();
      if (mode === 'banc') {
        verifier('table du banc : la mère accepte le rôle de banc `x` (deux fiches, aucun refus)', !!e.fiches['patients/p2'] && e.refusees.length === 0, e.refusees);
      } else {
        verifier('matrice RBAC : la réception écrit un patient, la mère l\'accepte', !!e.fiches['patients/p1']);
        verifier('matrice RBAC : le rôle inconnu `x` est refusé, nommé droit_refuse, et sa fiche n\'existe pas', !e.fiches['patients/p2'] && e.refusees.some((r) => r.code === 'droit_refuse'), e.refusees);
        const refus = await m.mere.admin('POST', '/admin/pair/trancher', { fiche: 'patients/p1', champ: 'nom', valeur: 'X' });
        verifier('la mère ne tranche toujours pas ce qui n\'a pas de conflit (409 nommé)', refus.status === 409 && refus.json.code === 'aucun_conflit', refus.json);
      }
      await m.fermer();
    }
  },
});
