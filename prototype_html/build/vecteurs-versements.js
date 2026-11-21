/* =============================================================================
 * VECTEURS DU LOT PAIE-V (Direction, 20/11/2026, section BI) : le paiement par versements successifs et modes multiples
 * -----------------------------------------------------------------------------
 * Le MOTEUR RÉEL de la maquette est piloté dans Chrome sur la base jetable, jamais recopié :
 *   lettres     : C.nombreEnLettres et C.montantEnLettres (la mention « Arrêtée la présente facture à la somme de ») ;
 *   modalités   : D.semenceModalitesVersement, SIGH.versements.definir (versions datées) puis D.modaliteVersementALaDate et D.modalitesVersementActives ;
 *   contrôle    : SIGH.versements.controler (pièce, lot de versements, date) : refus nommés (code, motif, geste) ;
 *   séquences   : PR.encaisser(id, { versements }) sur des pièces jetables : lignes réglées, reste dû, statut, mode de la pièce, base MECeF, écriture par versement ;
 *   rejeu       : SIGH.versements.controlerUn (le contrôle que la garde de la collection et la mère rejouent).
 * Horloge d'extraction : 30/10/2026 midi. Chaque fiche écrite est RESTITUÉE (archive RG-14) avant la suivante.
 *   SIGH_PORT_PHP=<port libre> SIGH_BASE_TEST=<base à soi> node build/vecteurs-versements.js   →   packages/domaine/test/vecteurs/versements.json
 * Rejoués par packages/domaine/test/versements_test.dart.
 * ========================================================================== */
'use strict';
const { ouvrirMaquette, ecrire } = require('./extraire');

(async () => {
  console.log('▶ Vecteurs du lot PAIE-V (versements successifs et modes multiples)');
  const m = await ouvrirMaquette();
  try {
    const sortie = await m.page.evaluate(() => {
      const S = SIGH.store, C = SIGH.core, D = SIGH.data, PR = SIGH.parcours, VS = SIGH.versements, N = SIGH.nav;
      const propre = (x) => JSON.parse(JSON.stringify(x === undefined ? null : x));
      const SESSION = { role: 'admin', fonction: 'admin', nom: 'Admin Vecteur', nomComplet: 'Admin Vecteur', identifiant: 'admin.vecteur', secteur: 'DIR' };
      S.setSession(SESSION);
      const sous = (role, f) => { const avant = S.session(); S.setSession(Object.assign({}, SESSION, { role, nom: 'Acteur ' + role, nomComplet: 'Acteur ' + role })); try { return f(); } finally { S.setSession(avant); } };
      const out = { _doc: 'ENGENDRÉ par prototype_html/build/vecteurs-versements.js : le moteur des versements piloté dans Chrome, ne pas éditer. Horloge : 30/10/2026 midi.' };
      out.aujourdhui = C.iso(C.aujourdhui());
      out.geste = VS.GESTE;
      out.detenteurs = N.rolesAvecGeste(VS.GESTE).slice().sort();
      /* 1. les montants en lettres : la règle unique */
      const montants = [0, 1, 2, 16, 17, 21, 71, 72, 77, 80, 81, 91, 99, 100, 101, 200, 280, 300, 999, 1000, 1001, 2000, 8500, 15000, 21000, 23500, 80000, 81000, 100000, 180000, 200000, 280000, 999999,
        1000000, 1000001, 1200000, 2000000, 2500000, 80000000, 200000000, 1000000000, 2000000000, 1200000000];
      out.lettres = montants.map((v) => ({ valeur: v, nombre: C.nombreEnLettres(v), montant: C.montantEnLettres(v) }));
      out.formuleArrete = C.BRAND.formuleArrete;
      /* 2. les modalités : la semence, puis des versions datées (un opérateur archivé puis réactivé, une modalité neuve) */
      out.semence = propre(D.semenceModalitesVersement());
      const posees = [];
      const poser = (nom, o) => { const r = VS.definir(o); posees.push({ nom, entree: propre(o), sortie: r.ok ? { ok: true, actif: r.actif, dateEffet: r.dateEffet } : { ok: false, code: r.code } }); };
      poser('archiver Moov à partir du 25/11/2026', { famille: 'operateur', code: 'moov', libelle: 'Moov Money', actif: false, dateEffet: '2026-11-25', motif: 'Vecteur : contrat résilié' });
      poser('réactiver Moov à partir du 10/12/2026', { famille: 'operateur', code: 'moov', libelle: 'Moov Money', actif: true, dateEffet: '2026-12-10', motif: 'Vecteur : contrat renouvelé' });
      poser('ajouter la modalité chèque', { famille: 'modalite', code: 'cheque', libelle: 'Chèque', compte: '521000', exigeReference: true, exigeOperateur: false, dateEffet: '2026-11-05', motif: 'Vecteur : nouvelle modalité' });
      poser('archiver la modalité TPE à partir du 25/11/2026', { famille: 'modalite', code: 'tpe', libelle: 'TPE (carte bancaire)', compte: '521000', actif: false, dateEffet: '2026-11-25', motif: 'Vecteur : terminal rendu' });
      poser('famille inconnue', { famille: 'banque', code: 'abc', libelle: 'Banque', motif: 'Vecteur' });
      poser('code invalide', { famille: 'operateur', code: 'Moov 2', libelle: 'Moov', motif: 'Vecteur' });
      poser('libellé absent', { famille: 'operateur', code: 'orange', libelle: ' ', motif: 'Vecteur' });
      poser('compte absent', { famille: 'modalite', code: 'virement', libelle: 'Virement', motif: 'Vecteur' });
      poser('motif absent', { famille: 'operateur', code: 'orange', libelle: 'Orange', motif: '' });
      poser('date antérieure à la dernière version', { famille: 'operateur', code: 'moov', libelle: 'Moov Money', actif: true, dateEffet: '2026-11-01', motif: 'Vecteur' });
      poser('archiver le mobile money à partir du 20/12/2026', { famille: 'modalite', code: 'mobile_money', libelle: 'Mobile money', compte: '521000', exigeReference: true, exigeOperateur: true, actif: false, dateEffet: '2026-12-20', motif: 'Vecteur' });
      poser('archiver le chèque à partir du 20/12/2026', { famille: 'modalite', code: 'cheque', libelle: 'Chèque', compte: '521000', exigeReference: true, actif: false, dateEffet: '2026-12-20', motif: 'Vecteur' });
      poser('archiver la dernière modalité proposée (espèces le 20/12/2026)', { famille: 'modalite', code: 'especes', libelle: 'Espèces', compte: '571000', actif: false, dateEffet: '2026-12-20', motif: 'Vecteur' });
      out.posees = posees;
      out.fiches = propre(S.collection('modalitesVersement').all().filter((x) => x.statut !== 'archive').map((x) => { const c = Object.assign({}, x); Object.keys(c).filter((k) => k.charAt(0) === '_').forEach((k) => { delete c[k]; }); return c; }));
      const dates = ['2026-10-30', '2026-11-04', '2026-11-05', '2026-11-24', '2026-11-25', '2026-12-09', '2026-12-10', '2026-12-20'];
      out.resolutions = [];
      [['operateur', 'moov'], ['operateur', 'mtn'], ['modalite', 'cheque'], ['modalite', 'tpe'], ['modalite', 'especes'], ['type', 'solde'], ['modalite', 'inconnue']].forEach((fc) => dates.forEach((d) => {
        const v = D.modaliteVersementALaDate(fc[0], fc[1], d);
        out.resolutions.push({ famille: fc[0], code: fc[1], date: d, existe: !!v, actif: v ? v.actif !== false : null, libelle: v ? v.libelle : null, libelleLu: D.libelleModaliteVersement(fc[0], fc[1], d) });
      }));
      out.actives = dates.map((d) => ({ date: d, type: D.modalitesVersementActives('type', d).map((x) => x.code), modalite: D.modalitesVersementActives('modalite', d).map((x) => x.code), operateur: D.modalitesVersementActives('operateur', d).map((x) => x.code) }));
      /* 3. le contrôle pur d'un lot de versements (pièces littérales) */
      const piece = (o) => Object.assign({ id: 'FV-X', numero: 'FV-X', statutPaiement: 'impayee', montantPaye: 0, partPatient: 23500, partAssurance: 0, montantTTC: 23500,
        lignes: [{ id: 'L001', partPatient: 15000 }, { id: 'L002', partPatient: 8500 }] }, o || {});
      const lot = (...v) => v;
      const mtn = (montant, ref) => Object.assign({ type: 'acompte', modalite: 'mobile_money', operateur: 'mtn', montant }, ref === undefined ? { referenceTransaction: 'M123' } : (ref ? { referenceTransaction: ref } : {}));
      const esp = (montant, type) => ({ type: type || 'solde', modalite: 'especes', montant });
      const cas = [
        ['deux versements qui soldent (15 000 mobile money + 8 500 espèces)', piece(), lot(mtn(15000), esp(8500)), '2026-10-30'],
        ['un seul versement en espèces', piece(), lot(esp(23500)), '2026-10-30'],
        ['trois versements', piece(), lot(esp(10000, 'acompte'), mtn(10000, 'R9'), { type: 'solde', modalite: 'tpe', montant: 3500 }), '2026-10-30'],
        ['mobile money sans référence', piece(), lot(mtn(15000, '')), '2026-10-30'],
        ['mobile money référence d’espaces', piece(), lot(mtn(15000, '   ')), '2026-10-30'],
        ['mobile money sans opérateur', piece(), lot({ type: 'acompte', modalite: 'mobile_money', referenceTransaction: 'M1', montant: 1000 }), '2026-10-30'],
        ['mobile money opérateur inconnu', piece(), lot({ type: 'acompte', modalite: 'mobile_money', operateur: 'orange', referenceTransaction: 'M1', montant: 1000 }), '2026-10-30'],
        ['espèces avec un opérateur superflu (ignoré)', piece(), lot({ type: 'acompte', modalite: 'especes', operateur: 'mtn', montant: 1000 }), '2026-10-30'],
        ['dépasse le dû', piece(), lot(esp(23501)), '2026-10-30'],
        ['le deuxième versement dépasse le dû', piece(), lot(esp(20000, 'acompte'), esp(3501)), '2026-10-30'],
        ['dépasse le reste après un acompte déjà reçu', piece({ montantPaye: 20000, statutPaiement: 'partielle' }), lot(esp(3501)), '2026-10-30'],
        ['solde exact du reste', piece({ montantPaye: 20000, statutPaiement: 'partielle' }), lot(esp(3500)), '2026-10-30'],
        ['pièce soldée', piece({ montantPaye: 23500, statutPaiement: 'soldee' }), lot(esp(1)), '2026-10-30'],
        ['versement sur la part de l’assureur', piece(), lot(Object.assign(esp(1000), { partie: 'assureur' })), '2026-10-30'],
        ['pièce à la charge de l’assureur seul', piece({ partPatient: 0, lignes: [{ id: 'L001', partPatient: 0 }] }), lot(esp(1000)), '2026-10-30'],
        ['montant nul', piece(), lot(esp(0)), '2026-10-30'],
        ['montant négatif', piece(), lot(esp(-500)), '2026-10-30'],
        ['montant décimal', piece(), lot(esp(100.5)), '2026-10-30'],
        ['montant absent', piece(), lot({ type: 'solde', modalite: 'especes' }), '2026-10-30'],
        ['aucun versement', piece(), lot(), '2026-10-30'],
        ['type inconnu', piece(), lot({ type: 'avance', modalite: 'especes', montant: 1000 }), '2026-10-30'],
        ['modalité inconnue', piece(), lot({ type: 'solde', modalite: 'troc', montant: 1000 }), '2026-10-30'],
        ['modalité archivée à la date (TPE le 26/11/2026)', piece(), lot({ type: 'solde', modalite: 'tpe', montant: 1000 }), '2026-11-26'],
        ['modalité encore proposée la veille de l’archivage (TPE le 24/11/2026)', piece(), lot({ type: 'solde', modalite: 'tpe', montant: 1000 }), '2026-11-24'],
        ['opérateur archivé à la date (Moov le 26/11/2026)', piece(), lot({ type: 'acompte', modalite: 'mobile_money', operateur: 'moov', referenceTransaction: 'M5', montant: 1000 }), '2026-11-26'],
        ['opérateur réactivé (Moov le 10/12/2026)', piece(), lot({ type: 'acompte', modalite: 'mobile_money', operateur: 'moov', referenceTransaction: 'M5', montant: 1000 }), '2026-12-10'],
        ['modalité ajoutée : chèque avec référence', piece(), lot({ type: 'solde', modalite: 'cheque', referenceTransaction: 'CHQ1', montant: 1000 }), '2026-11-05'],
        ['modalité ajoutée : chèque sans référence', piece(), lot({ type: 'solde', modalite: 'cheque', montant: 1000 }), '2026-11-05'],
        ['modalité pas encore en vigueur : chèque le 04/11/2026', piece(), lot({ type: 'solde', modalite: 'cheque', referenceTransaction: 'CHQ1', montant: 1000 }), '2026-11-04'],
        ['pièce sans lignes', piece({ lignes: [] }), lot(esp(23500)), '2026-10-30'],
        ['pièce sans lignes : dépasse', piece({ lignes: [] }), lot(esp(23501)), '2026-10-30'],
        ['pièce assurée : seule la part du patient compte', piece({ partPatient: 7000, partAssurance: 16500, lignes: [{ id: 'L001', partPatient: 4000, partAssureur: 11000 }, { id: 'L002', partPatient: 3000, partAssureur: 5500 }] }), lot(esp(7001)), '2026-10-30'],
      ];
      out.controle = cas.map((c) => {
        const r = VS.controler(propre(c[1]), propre(c[2]), c[3]);
        return { nom: c[0], piece: propre(c[1]), versements: propre(c[2]), date: c[3], sortie: r.ok ? { ok: true, total: r.total, lignes: propre(r.lignes) }
          : { ok: false, code: r.code, motif: r.motif, geste: r.geste, rang: r.rang || null, famille: r.famille || null, reste: r.reste == null ? null : r.reste } };
      });
      /* 4. les séquences de versements par le moteur d'encaissement, sur des pièces jetables restituées ensuite */
      const p = S.collection('patients').active()[0];
      const poseesPieces = [];
      const mkFac = (id, spec) => {
        const lignes = spec.lignes.map((a, i) => ({ id: 'L00' + (i + 1), categorie: 'acte', designation: 'Acte ' + (i + 1), quantite: 1, prixUnitaire: a[0] + (a[1] || 0), montant: a[0] + (a[1] || 0), partAssureur: a[1] || 0, partPatient: a[0], statutPaiement: 'du' }));
        const part = lignes.reduce((n, l) => n + l.partPatient, 0), ass = lignes.reduce((n, l) => n + l.partAssureur, 0);
        return S.collection('factures').insert({ id, numero: id, date: spec.date || '2026-10-30', patientId: p.id, patient: 'Patient Vecteur', patientCode: p.code, type: 'Facture', montantTTC: part + ass, montantHT: part + ass,
          partAssurance: ass, partPatient: part, assureur: ass ? 'Assureur Vecteur' : null, montantPaye: 0, reliquat: part, statutPaiement: 'impayee', statutMecef: 'en_attente', lignes }).record;
      };
      const sequences = [
        { nom: 'PRD : 23 500 en deux versements (15 000 mobile money MTN, 8 500 espèces)', id: 'FV-S1', lignes: [[15000], [8500]], lots: [[mtn(15000), esp(8500)]] },
        { nom: 'un versement partiel qui solde une ligne entière mais pas la suivante', id: 'FV-S2', lignes: [[10000], [12000], [5000]], lots: [[esp(10000, 'acompte')], [esp(17000)]] },
        { nom: 'un acompte qui ne couvre aucune ligne entière reste non affecté', id: 'FV-S3', lignes: [[10000], [12000]], lots: [[esp(5000, 'acompte')], [esp(5000, 'acompte')], [esp(12000)]] },
        { nom: 'trois versements de trois modes', id: 'FV-S4', lignes: [[9000], [9000], [5500]], lots: [[esp(9000, 'acompte'), mtn(9000, 'R2')], [{ type: 'solde', modalite: 'tpe', montant: 5500 }]] },
        { nom: 'pièce assurée : la part de l’assureur ne se constate qu’une fois et n’est jamais un versement', id: 'FV-S5', lignes: [[4000, 11000], [3000, 5500]], lots: [[esp(4000, 'acompte')], [mtn(3000)]] },
        { nom: 'refus : dépasse le dû, rien n’est écrit', id: 'FV-S6', lignes: [[15000], [8500]], lots: [[esp(23501)], [esp(15000, 'acompte')]] },
        { nom: 'refus : mobile money sans référence, puis lot accepté', id: 'FV-S7', lignes: [[15000], [8500]], lots: [[mtn(1000, '')], [mtn(1000, 'R7'), esp(22500)]] },
        { nom: 'refus : pièce soldée', id: 'FV-S8', lignes: [[5000]], lots: [[esp(5000)], [esp(1)]] },
        { nom: 'un jour de décalage : versement un autre jour que la pièce (marqué horsJour)', id: 'FV-S9', date: '2026-10-29', lignes: [[5000]], lots: [[esp(2000, 'acompte')]] },
      ];
      out.sequences = sequences.map((sq) => {
        const f0 = mkFac(sq.id, sq);
        poseesPieces.push(f0.id);
        const depart = propre(S.collection('factures').get(f0.id));
        const etapes = []; let ecrituresAvant = [];
        sq.lots.forEach((versements) => {
          const factAvant = propre(S.collection('factures').get(f0.id));
          const ecrAvant = propre(S.collection('ecritures').active().filter((e) => e.pieceId === f0.id));
          const nbVers = S.collection('versementsCaisse').active().filter((v) => v.factureId === f0.id).length;
          const r = PR.encaisser(f0.id, { versements: propre(versements) });
          const g = S.collection('factures').get(f0.id);
          const ecr = S.collection('ecritures').active().filter((e) => e.pieceId === f0.id);
          const nouvelles = ecr.filter((e) => !ecrAvant.some((a) => a.id === e.id));
          const vs = S.collection('versementsCaisse').active().filter((v) => v.factureId === f0.id).slice().reverse();
          etapes.push({
            versements: propre(versements), factureAvant: factAvant, ecrituresAvant: ecrAvant.map((e) => ({ id: e.id, pieceId: e.pieceId, compte: e.compte, debit: e.debit, credit: e.credit, numero: e.numero, journal: e.journal, statut: e.statut })), rangDepart: nbVers,
            sortie: r.refus ? { ok: false, code: r.refusNomme.code, motif: r.refusNomme.motif, rang: r.refusNomme.rang || null, restantDu: r.restantDu }
              : { ok: true, montantRegle: r.montantRegle, restantDu: r.restantDu, lignesReglees: propre(r.lignesReglees.map((l) => l.id)),
                facture: { statutPaiement: g.statutPaiement, montantPaye: g.montantPaye, reliquat: g.reliquat, modePaiement: g.modePaiement, baseMecef: g.baseMecef, lignes: g.lignes.map((l) => [l.id, l.statutPaiement]) },
                ecritures: nouvelles.map((e) => [e.compte, e.debit, e.credit]), numeroUnique: Array.from(new Set(ecr.map((e) => e.numero))).length === 1,
                versements: vs.slice(nbVers).map((v) => ({ rang: v.rang, type: v.type, modalite: v.modalite, operateur: v.operateur || null, referenceTransaction: v.referenceTransaction || null, montant: v.montant, resteApres: v.resteApres, compte: v.compte, horsJour: !!v.horsJour })) },
            rien: r.refus ? { versements: S.collection('versementsCaisse').active().filter((v) => v.factureId === f0.id).length === nbVers, ecritures: S.collection('ecritures').active().filter((e) => e.pieceId === f0.id).length === ecrAvant.length } : null,
          });
        });
        return { nom: sq.nom, depart, etapes };
      });
      /* 5. le rejeu : le contrôle que la garde de la collection et la mère appliquent à UN versement arrivant */
      out.rejeu = [
        ['rejeu qui tient dans le dû', piece(), 10000, esp(13500), '2026-10-30'],
        ['rejeu qui dépasse le dû (deux fileuls ont encaissé la même pièce)', piece(), 20000, esp(3501), '2026-10-30'],
        ['rejeu sans référence mobile money', piece(), 0, mtn(1000, ''), '2026-10-30'],
        ['rejeu sur modalité archivée à sa date', piece(), 0, { type: 'solde', modalite: 'tpe', montant: 1000 }, '2026-11-26'],
        ['rejeu sur la part de l’assureur', piece(), 0, Object.assign(esp(1000), { partie: 'assureur' }), '2026-10-30'],
      ].map((c) => { const r = VS.controlerUn(propre(c[1]), propre(c[3]), c[4], c[2]); return { nom: c[0], piece: propre(c[1]), dejaVerse: c[2], entrant: propre(c[3]), date: c[4], sortie: r ? { code: r.code, motif: r.motif } : null }; });
      /* 6. le mode de la pièce */
      out.modes = [[[mtn(1, 'a')]], [[esp(1)]], [[esp(1), esp(1)]], [[esp(1), mtn(1, 'a')]], [[{ type: 'solde', modalite: 'mobile_money', operateur: 'celtiis', montant: 1, referenceTransaction: 'x' }]],
        [[{ type: 'solde', modalite: 'mobile_money', operateur: 'moov', montant: 1, referenceTransaction: 'x' }]], [[{ type: 'solde', modalite: 'tpe', montant: 1 }]]]
        .map((c) => ({ versements: propre(c[0]), mode: VS.modePiece(c[0]) }));
      /* restitution : tout ce que les cas ont posé est archivé (RG-14) */
      ['versementsCaisse', 'ecritures', 'factures'].forEach((c) => S.collection(c).all().forEach((x) => { if (x.statut !== 'archive' && (c !== 'factures' || poseesPieces.indexOf(x.id) >= 0)) S.collection(c).archive(x.id, 'Vecteur : restauration'); }));
      S.collection('modalitesVersement').all().forEach((x) => { if (x.statut !== 'archive' && x.dateEffet) S.collection('modalitesVersement').archive(x.id, 'Vecteur : restauration'); });
      return out;
    });
    console.log('  ' + sortie.lettres.length + ' montants · ' + sortie.posees.length + ' réglages · ' + sortie.resolutions.length + ' résolutions · ' + sortie.controle.length + ' contrôles · ' + sortie.sequences.length + ' séquences · ' + sortie.rejeu.length + ' rejeux');
    ecrire('packages/domaine/test/vecteurs/versements.json', sortie);
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
