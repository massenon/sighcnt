'use strict';
/* Scénario P8 (PRD relais consultable) : L'ORDRE GLOBAL DES VERSIONS DE LA COPIE. Deux postes modifient la MÊME fiche chacun de son côté (hors réseau), se retrouvent, et
   chacun dépose sa copie. Les enveloppes portent leur `ordre` [nOps, hlc, appareil, id] : lues dans N'IMPORTE QUEL ordre avec la règle de la page (la version la plus
   informée l'emporte), elles donnent toutes l'état fusionné final. Une version obsolète déposée en retard ne remplace jamais une plus récente. */
const { dechiffrer } = require('./crypto');
const { comparerOrdre } = require('./copie-ordre');
module.exports = ({ monde, verifier, attendre, dormir, titre }) => ({
  async P8() {
    titre('PAIR-P8 · ordre global de la copie : deux postes modifient la même fiche, les versions lues dans tout ordre donnent l\'état fusionné');
    const m = await monde({ relais: true });
    await m.mere.tuer();
    const f1 = await m.pair('F1', { copie: 'patients' });
    const f2 = await m.pair('F2', { copie: 'patients' });
    const cle = Buffer.from(m.clePair, 'hex');
    const lire = async () => {
      const tout = (await m.relais.direct('GET', '/banc/tout')).json;
      const lignes = tout.lignes.filter((l) => l.dir === 'copie');
      return Promise.all(lignes.map((l) => dechiffrer(cle, l)));
    };
    const retenir = (charges) => {
      const t = {};
      for (const c of charges) {
        const k = c.collection + '/' + c.fiche; const d = t[k];
        if (!d) { t[k] = c; continue; }
        const o = comparerOrdre(d.ordre, c.ordre);
        t[k] = o < 0 || (o === 0 && JSON.stringify(c.data) + c.archive > JSON.stringify(d.data) + d.archive) ? c : d;
      }
      return t;
    };
    const pretes = async (p) => { const e = await p.etat(); return e.copie_en_attente === 0; };

    await f1.emettre({ collection: 'patients', fiche: 'p1', type: 'creer', champs: { nom: 'AKPO', tel: '1' }, role: 'reception' });
    verifier('F2 reçoit la fiche', await attendre(async () => !!(await f2.fiches()).fiches['patients/p1'], 15000));
    const vu = (await f1.fiches()).fiches['patients/p1'].hlc;
    f1.coupe(); f2.coupe();
    await dormir(300);
    await f1.emettre({ collection: 'patients', fiche: 'p1', type: 'modifier', champs: { tel: '2' }, vu: { tel: vu.tel }, role: 'reception' });
    await f2.emettre({ collection: 'patients', fiche: 'p1', type: 'modifier', champs: { nom: 'AKPO-DOSSOU' }, vu: { nom: vu.nom }, role: 'reception' });
    await dormir(400);
    f2.rouvre(); await dormir(800); f1.rouvre();
    verifier('les deux postes reconvergent sur la même fiche (tel 2 ET nom modifié)', await attendre(async () => {
      const a = (await f1.fiches()).fiches['patients/p1'], b = (await f2.fiches()).fiches['patients/p1'];
      return a && b && a.data.tel === '2' && a.data.nom === 'AKPO-DOSSOU' && JSON.stringify(a.data) === JSON.stringify(b.data);
    }, 25000));
    verifier('chacun a déposé sa copie finale', await attendre(async () => (await pretes(f1)) && (await pretes(f2)), 25000));
    await dormir(800);

    const charges = await lire();
    const final = (await f1.fiches()).fiches['patients/p1'].data;
    const versions = charges.filter((c) => c.fiche === 'p1');
    verifier('plusieurs versions de la fiche sont au relais (de plusieurs appareils), toutes portent un ordre', versions.length >= 2 && versions.every((c) => Array.isArray(c.ordre) && c.ordre.length === 4), versions.map((c) => c.ordre));
    let divergences = 0; let essais = 0;
    const alea = (s) => () => (s = (s * 1664525 + 1013904223) % 4294967296) / 4294967296;
    const r = alea(42);
    for (let i = 0; i < 300; i++) {
      const p = charges.slice().sort(() => r() - 0.5); essais++;
      const f = retenir(p)['patients/p1'];
      if (JSON.stringify(f.data) !== JSON.stringify(final)) divergences++;
    }
    verifier(`lues dans ${essais} ordres au hasard, les copies donnent TOUJOURS l'état fusionné final`, divergences === 0, { divergences, final });
    const max = versions.slice().sort((a, b) => comparerOrdre(a.ordre, b.ordre)).pop();
    verifier('la version retenue est celle qui connaît les trois opérations (nOps = 3)', max.ordre[0] === 3 && JSON.stringify(max.data) === JSON.stringify(final), max.ordre);
    // une version obsolète déposée EN RETARD (ordre plus ancien) ne remplace rien
    const tardive = { collection: 'patients', fiche: 'p1', data: { nom: 'VIEUX', tel: '0' }, archive: false, ordre: [1, 1, 'F0', 'vieux'] };
    verifier('une version obsolète qui arrive en dernier ne remplace pas la plus récente', JSON.stringify(retenir([...charges, tardive])['patients/p1'].data) === JSON.stringify(final));
    await m.fermer();
  },
});
