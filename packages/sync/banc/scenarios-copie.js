'use strict';
/* Scénario P5 (PRD relais consultable) : les postes ET la mère DÉPOSENT la copie chiffrée de leurs fiches dans le sens `copie` du relais. Rangs contigus, dépôt
   idempotent, aucun clair au relais, reprise après SIGKILL sans doublon, une fiche changée ou archivée repart comme nouvelle version (jamais de suppression, RG-14).
   La lecture de la copie appartient au superadmin du panneau (dans le navigateur) : ici on déchiffre avec la clé de clinique, comme le fait la page. */
const { dechiffrer } = require('./crypto');
module.exports = ({ monde, verifier, attendre, dormir, titre }) => ({
  async P5() {
    titre('PAIR-P5 · la copie consolidée : le poste et la mère la déposent chiffrée, rangs contigus, sans clair, reprise après SIGKILL sans doublon');
    const m = await monde({ relais: true });
    await m.mere.tuer();
    m.mere.opts.cle = Buffer.from(m.clePair, 'hex').toString('base64');
    const f1 = await m.pair('F1', { copie: 'patients,rendezvous' });
    const cle = Buffer.from(m.clePair, 'hex');
    const lire = async (appareil) => {
      const tout = (await m.relais.direct('GET', '/banc/tout')).json;
      const lignes = tout.lignes.filter((l) => l.dir === 'copie' && (!appareil || l.appareil === appareil)).sort((a, b) => a.n - b.n);
      return { lignes, charges: await Promise.all(lignes.map((l) => dechiffrer(cle, l))), tout };
    };
    const fichesDe = (charges) => { const o = {}; for (const c of charges) for (const x of (c.lot || [c])) o[x.collection + '/' + x.fiche] = x; return o; };

    await f1.emettre({ collection: 'patients', fiche: 'p1', type: 'creer', champs: { nom: 'AKPO', tel: '1' }, role: 'reception' });
    await f1.emettre({ collection: 'patients', fiche: 'p2', type: 'creer', champs: { nom: 'KOUA' }, role: 'reception' });
    await f1.emettre({ collection: 'rendezvous', fiche: 'r1', type: 'creer', champs: { motif: 'CPN' }, role: 'reception' });
    await f1.emettre({ collection: 'constantes', fiche: 'c1', type: 'creer', champs: { pouls: 70 }, role: 'infirmier' });
    verifier('le poste dépose la copie de ses fiches (patients et rendez-vous, pas les constantes hors choix)', await attendre(async () => (await f1.etat()).copie_deposee >= 3, 15000));
    let a = await lire(f1.uuid);
    const f = fichesDe(a.charges);
    verifier('la copie déchiffrée porte les trois fiches et rien d\'autre', Object.keys(f).sort().join() === 'patients/p1,patients/p2,rendezvous/r1' && f['patients/p1'].data.nom === 'AKPO' && f['patients/p1'].archive === false, Object.keys(f));
    verifier('rangs contigus dans la copie du poste', a.lignes.length >= 3 && a.lignes.every((l, i) => l.n === i + 1), a.lignes.map((l) => l.n));

    await f1.emettre({ collection: 'patients', fiche: 'p1', type: 'modifier', champs: { tel: '2' }, vu: { tel: (await f1.fiches()).fiches['patients/p1'].hlc.tel }, role: 'reception' });
    await f1.emettre({ collection: 'patients', fiche: 'p2', type: 'archiver', champs: {}, role: 'da' });
    verifier('une fiche changée ou archivée repart comme nouvelle version (l\'archivage est un champ)', await attendre(async () => { const g = fichesDe((await lire(f1.uuid)).charges); return g['patients/p1'].data.tel === '2' && g['patients/p2'].archive === true; }, 15000));

    const avant = (await lire(f1.uuid)).lignes.length;
    await f1.tuer(); await f1.demarrer();
    await dormir(1500);
    const apres = await lire(f1.uuid);
    verifier('après SIGKILL : rien republié, rangs toujours contigus', apres.lignes.length === avant && apres.lignes.every((l, i) => l.n === i + 1), [avant, apres.lignes.length]);

    await m.mere.demarrer();
    verifier('la mère dépose la copie CONSOLIDÉE (lot) sous l\'appareil `mere`', await attendre(async () => { const g = fichesDe((await lire('mere')).charges); return !!g['patients/p1'] && g['patients/p1'].data.tel === '2' && g['patients/p2'].archive === true; }, 20000));
    const mere = await lire('mere');
    verifier('rangs contigus dans la copie de la mère, charges en lots', mere.lignes.every((l, i) => l.n === i + 1) && mere.charges.every((c) => Array.isArray(c.lot)), mere.lignes.map((l) => l.n));
    const nMere = mere.lignes.length;
    await m.mere.tuer(); await m.mere.demarrer(); await dormir(2000);
    verifier('après SIGKILL de la mère : aucune copie dupliquée', (await lire('mere')).lignes.length === nMere);

    const brut = JSON.stringify((await lire()).tout.lignes.filter((l) => l.dir === 'copie'));
    verifier('le relais ne voit AUCUN clair dans la copie (noms, collections, champs)', brut.length > 50 && !/AKPO|KOUA|patients|rendezvous|"nom"|"tel"|"lot"/.test(brut.replace(/"ct":"[^"]*"/g, '"ct"').replace(/"nonce":"[^"]*"/g, '"nonce"')));
    const tard = (await lire(f1.uuid)).lignes.length;
    verifier('le poste ne dépose pas la copie du poste voisin : chaque appareil a SA copie', (await lire()).lignes.every((l) => l.appareil === f1.uuid || l.appareil === 'mere') && tard === avant);
    await m.fermer();
  },
});
