'use strict';
/* Scénario P7 : la mère Dart en MODE PAIR sur PostgreSQL. Le même script d'opérations (émises une à une, chacune attendue chez la mère : l'ordre d'arrivée est donc le même) est
   joué dans deux mondes, l'un avec la mère sur SQLite, l'autre sur PostgreSQL (base jetable). Les deux états doivent être IDENTIQUES une fois retirés les identifiants et les horloges
   propres à chaque exécution : mêmes fiches, mêmes conflits marqués, mêmes décisions, mêmes refus, mêmes numéros d'ordre (seq) sans trou. Puis SIGKILL de la mère sur PG : rien relu
   deux fois, mêmes seq. Exige SIGH_MERE=dart, SIGH_MERE_DB=pg et SIGH_PG_URL (la mère Node reste sur SQLite). */
module.exports = ({ monde, verifier, attendre, dormir, titre }) => {
  /* l'état d'une mère, sans ce qui varie d'une exécution à l'autre (uuid d'appareil, horloge hybride) */
  const normaliser = (e) => JSON.stringify({
    ops: e.ops, seq_max: e.seq_max,
    fiches: Object.fromEntries(Object.entries(e.fiches).sort().map(([k, f]) => [k, { data: f.data, archive: f.archive, emise: f.emise }])),
    stock: e.stock, besoins: e.besoins,
    conflits: e.conflits.map((c) => [c.fiche, c.champ, c.a, c.b]),
    tranches: e.tranches.map((t) => [t.fiche, t.champ, t.valeur, t.par]),
    refusees: e.refusees.map((r) => r.code).sort(),
  });

  async function jouer(sur) {
    const m = await monde({ relais: true });
    await m.mere.tuer();
    if (sur === 'sqlite') m.mere.db = require('node:path').join(m.dir, 'mere-pair-sqlite.sqlite'); // sinon : la base PostgreSQL jetable que le banc a choisie
    m.mere.opts.cle = Buffer.from(m.clePair, 'hex').toString('base64');
    await m.mere.demarrer();
    const etat = () => m.mere.admin('GET', '/admin/pair/etat').then((r) => r.json);
    const f1 = await m.pair('F1'); const f2 = await m.pair('F2');
    let n = 0;
    const emettre = async (poste, cmd) => { await poste.emettre(cmd); n += 1; await attendre(async () => (await etat()).ops === n, 15000); };
    await emettre(f1, { collection: 'patients', fiche: 'p1', type: 'creer', champs: { nom: 'AKPO', tel: '1' }, role: 'reception' });
    await attendre(async () => (await f2.fiches()).fiches['patients/p1'], 15000);
    const vu = (await f2.fiches()).fiches['patients/p1'].hlc.tel;
    await emettre(f1, { collection: 'patients', fiche: 'p1', type: 'modifier', champs: { tel: '91' }, vu: { tel: vu }, role: 'reception' });
    await emettre(f2, { collection: 'patients', fiche: 'p1', type: 'modifier', champs: { tel: '92' }, vu: { tel: vu }, role: 'reception' });
    await emettre(f1, { collection: 'patients', fiche: 'p2', type: 'creer', champs: { nom: 'KOUA' }, role: 'reception' });
    await emettre(f1, { collection: 'patients', fiche: 'p2', type: 'archiver', champs: {}, role: 'reception' });
    await emettre(f1, { collection: 'stock', fiche: 'gants', type: 'creer', champs: { qte: 50 }, role: 'stock' });
    await emettre(f2, { collection: 'constantes', fiche: 'c1', type: 'creer', champs: { pouls: 70 }, role: 'infirmier' });
    // une opération sans droit : refusée, nommée, et sa fiche n'existe pas (le poste la refuse déjà à l'émission : on l'écrit directement chez la mère par un second poste désactivé n'étant pas
    // nécessaire ; ici le refus est celui de la règle de fusion sur une fiche inconnue)
    await emettre(f2, { collection: 'patients', fiche: 'fantome', type: 'modifier', champs: { nom: 'X' }, vu: {}, role: 'reception' });
    const avant = await etat();
    const choix = await m.mere.admin('POST', '/admin/pair/trancher', { fiche: 'patients/p1', champ: 'tel', valeur: '91' });
    await attendre(async () => (await etat()).ops === n + 1, 15000);
    const decide = await etat();
    await m.mere.tuer(); await m.mere.demarrer();
    await dormir(1500);
    const apres = await etat();
    const r = { avant: normaliser(avant), decide: normaliser(decide), apres: normaliser(apres), choix: choix.status, nbOps: n, apresOps: apres.ops, apresSeq: apres.seq_max, decideSeq: decide.seq_max, conflitsAvant: avant.conflits.length };
    await m.fermer();
    return r;
  }

  return {
    async P7() {
      titre = typeof titre === 'function' ? titre : () => {};
      titre('PAIR-P7 · la mère Dart sur PostgreSQL : même état pair que sur SQLite (fiches, conflits, décisions, refus, seq sans trou), reprise après SIGKILL sans relecture');
      if (process.env.SIGH_MERE !== 'dart' || process.env.SIGH_MERE_DB !== 'pg' || !process.env.SIGH_PG_URL) {
        verifier('P7 ignoré : SIGH_MERE=dart, SIGH_MERE_DB=pg et SIGH_PG_URL sont requis', true); return;
      }
      const sqlite = await jouer('sqlite');
      const pg = await jouer('pg');
      verifier('SQLite : un conflit marqué avant la décision, la console tranche (200)', sqlite.conflitsAvant === 1 && sqlite.choix === 200, [sqlite.conflitsAvant, sqlite.choix]);
      verifier('PostgreSQL : un conflit marqué avant la décision, la console tranche (200)', pg.conflitsAvant === 1 && pg.choix === 200, [pg.conflitsAvant, pg.choix]);
      verifier('PARITÉ avant la décision : même état fusionné sur SQLite et sur PostgreSQL', sqlite.avant === pg.avant, [sqlite.avant, pg.avant]);
      verifier('PARITÉ après la décision : même état, conflit levé, décision tracée', sqlite.decide === pg.decide && JSON.parse(pg.decide).conflits.length === 0 && JSON.parse(pg.decide).tranches.length === 1, pg.decide);
      verifier('seq sans trou sur PostgreSQL (un par opération, décision comprise)', pg.decideSeq === pg.nbOps + 1 && sqlite.decideSeq === sqlite.nbOps + 1, [pg.decideSeq, pg.nbOps]);
      verifier('PostgreSQL, après SIGKILL de la mère : rien relu deux fois, mêmes seq, même état', pg.apresOps === pg.nbOps + 1 && pg.apresSeq === pg.decideSeq && pg.apres === pg.decide, [pg.apresOps, pg.apresSeq, pg.decideSeq]);
      verifier('SQLite, après SIGKILL : même résultat que PostgreSQL', sqlite.apres === pg.apres);
    },
  };
};
