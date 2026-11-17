/* =============================================================================
 * VECTEURS DU LOT TIERS (Direction, 16/11/2026, section AQ point 36) : la facture à un tiers payeur
 * -----------------------------------------------------------------------------
 * Le MOTEUR RÉEL de la maquette (SIGH.tiers) est piloté dans Chrome sur la base jetable, jamais recopié :
 *   acheteurs      : T.validerAcheteur (IFU de 13 chiffres et nom obligatoires) ;
 *   champs du tiers: T.creerTiers (refus nommés avant écriture) ;
 *   décisions      : T.deciderAib sur un brouillon (le logiciel propose, le comptable décide), avec le barème de la base ;
 *   émission       : T.emettre (droit, pièce déjà émise, décision absente, émission) ;
 *   numéros        : T.numeroSuivant (année de la DATE de la pièce) ;
 *   créances       : T.creance, T.lettrer, T.creances (balance âgée aux tranches lues en base).
 * Horloge d'extraction : 30/10/2026 midi. Chaque cas écrit est RESTITUÉ (archive RG-14) avant le suivant.
 *   SIGH_PORT_PHP=<port libre> SIGH_BASE_TEST=<base à soi> node build/vecteurs-tiers.js   →   packages/domaine/test/vecteurs/tiers.json
 * Rejoués par packages/domaine/test/tiers_payeurs_test.dart.
 * ========================================================================== */
'use strict';
const { ouvrirMaquette, ecrire } = require('./extraire');

(async () => {
  console.log('▶ Vecteurs du lot TIERS (facture à un tiers payeur)');
  const m = await ouvrirMaquette();
  try {
    const sortie = await m.page.evaluate(() => {
      const S = SIGH.store, C = SIGH.core, T = SIGH.tiers, N = SIGH.nav;
      const propre = (x) => JSON.parse(JSON.stringify(x === undefined ? null : x));
      const SESSION = { role: 'admin', fonction: 'admin', nom: 'Admin Vecteur', nomComplet: 'Admin Vecteur', identifiant: 'admin.vecteur', secteur: 'DIR' };
      S.setSession(SESSION);
      const sous = (role, f) => { const avant = S.session(); S.setSession(Object.assign({}, SESSION, { role, nom: 'Acteur ' + role, nomComplet: 'Acteur ' + role })); try { return f(); } finally { S.setSession(avant); } };
      const net = (r) => { const c = propre(r); delete c.undo; delete c.fiche; delete c.decision; return c; };
      const out = { _doc: 'ENGENDRÉ par prototype_html/build/vecteurs-tiers.js : SIGH.tiers piloté dans Chrome, ne pas éditer. Horloge : 30/10/2026 midi.' };
      out.aujourdhui = C.iso(C.aujourdhui());
      out.gestes = { emettre: 'emettre_facture_tiers', corriger: 'corriger_facture_tiers' };
      out.detenteurs = { emettre: N.rolesAvecGeste('emettre_facture_tiers').slice().sort(), corriger: N.rolesAvecGeste('corriger_facture_tiers').slice().sort(), imputer: N.rolesAvecGeste('imputer_aib').slice().sort() };
      out.situations = propre(S.collection('situationsAib').all()); out.bareme = propre(S.collection('baremeAib').all());
      /* 1. l'acheteur */
      out.acheteurs = [['IFU et nom valides', '3201642748214', 'Société Vecteur'], ['IFU absent', '', 'Société Vecteur'], ['IFU absent (espaces)', '   ', 'Société Vecteur'], ['IFU de 5 chiffres', '12345', 'Société Vecteur'],
        ['IFU avec des lettres', '32016427489AB', 'Société Vecteur'], ['IFU de 14 chiffres', '32016427482140', 'Société Vecteur'], ['IFU avec espaces à nettoyer', '3201 6427 48214', 'Société Vecteur'], ['nom absent', '3201642748214', ''], ['nom d’espaces', '3201642748214', '   ']]
        .map((a) => ({ nom: a[0], ifu: a[1], acheteur: a[2], sortie: net(T.validerAcheteur({ ifu: a[1], nom: a[2] })) }));
      /* 2. les champs d'un tiers */
      const ok0 = { nom: 'Société Vecteur', type: 'entreprise', ifu: '3201642748999', adresse: 'BP 1', delaiPaiementJours: 30, dateEffet: '2026-10-01' };
      const champs = [];
      const ch = (nom, e) => { const n0 = S.collection('tiersPayeurs').all().length; const r = T.creerTiers(e); champs.push({ nom, entree: propre(e), sortie: r.ok ? { ok: true, version: r.fiche.version, ifu: r.fiche.ifu === undefined ? null : r.fiche.ifu, delai: r.fiche.delaiPaiementJours === undefined ? null : r.fiche.delaiPaiementJours } : { ok: false, code: r.code }, ecrits: S.collection('tiersPayeurs').all().length - n0 }); if (r.ok) S.collection('tiersPayeurs').archive(r.id, 'Vecteur : restauration'); };
      ch('tiers complet', ok0); ch('sans IFU', Object.assign({}, ok0, { ifu: '' })); ch('sans délai', Object.assign({}, ok0, { delaiPaiementJours: '' }));
      ch('nom vide', Object.assign({}, ok0, { nom: ' ' })); ch('IFU court', Object.assign({}, ok0, { ifu: '12345' })); ch('IFU lettres', Object.assign({}, ok0, { ifu: '32016427489AB' }));
      ch('type inconnu', Object.assign({}, ok0, { type: 'banque' })); ch('délai négatif', Object.assign({}, ok0, { delaiPaiementJours: -3 })); ch('délai décimal', Object.assign({}, ok0, { delaiPaiementJours: 2.5 }));
      ch('délai trop long', Object.assign({}, ok0, { delaiPaiementJours: 400 })); ch('assureur', Object.assign({}, ok0, { type: 'assureur' }));
      out.champs = champs;
      /* préparation : un patient, sa facture, un tiers avec IFU, un sans */
      const p = S.collection('patients').active()[0];
      const fac = S.collection('factures').insert({ numero: 'FAC-VT-1', date: '2026-10-10', patientId: p.id, patient: 'Patient Vecteur', patientCode: p.code, montantTTC: 4000000, montantHT: 4000000, type: 'Facture', partAssurance: 0, partPersonnel: 0, partPatient: 4000000,
        lignes: Array.from({ length: 40 }, (x, i) => 'L' + String(i + 1).padStart(3, '0')).map((id, i) => ({ id, categorie: 'acte', designation: 'Acte ' + (i + 1), montant: 100000, partAssureur: 0, partPersonnel: 0, partPatient: 100000, statutPaiement: 'du' })) }).record;
      const tiers = T.creerTiers({ nom: 'Société Vecteur Tiers', type: 'entreprise', ifu: '3201642748555', adresse: 'BP 2', delaiPaiementJours: 30, dateEffet: '2026-01-05' });
      const tiersSans = T.creerTiers({ nom: 'Convention Vecteur', type: 'convention', ifu: '3201642748556', dateEffet: '2026-01-05' });
      let ligne = 0; const lignes = Array.from({ length: 40 }, (x, i) => 'L' + String(i + 1).padStart(3, '0'));
      const brouillon = (code, date) => { const r = T.proposer({ tiersCode: code || tiers.code, date: date || '2026-10-12', lignes: [{ factureId: fac.id, ligneId: lignes[ligne++], montant: 100000 }] }); if (!r.ok) throw new Error('brouillon : ' + r.code + ' ' + r.motif + ' tiers=' + JSON.stringify([tiers.ok, tiers.code, tiersSans.ok, tiersSans.code])); return r; };
      /* 3. la décision du comptable */
      const decisions = [];
      const dec = (nom, role, saisie, prepar) => {
        const b = brouillon(); const f = S.collection('facturesTiers').get(b.id);
        if (prepar) prepar(b.id);
        const droit = !!N.droitGeste(role, 'imputer_aib');
        const avant = propre(S.collection('facturesTiers').get(b.id));
        const r = sous(role, () => T.deciderAib(b.id, saisie));
        const apres = S.collection('facturesTiers').get(b.id);
        decisions.push({ nom, role, droit, facture: { statut: avant.statut, date: avant.date, numero: avant.numero || null }, saisie: propre(saisie),
          sortie: r.ok ? { ok: true, decision: (() => { const d = propre(apres.aibDecision); ['decideLe', 'decidePar', 'decideRole'].forEach((k) => { delete d[k]; }); return d; })() } : { ok: false, code: r.code } });
      };
      dec('sans droit (caissier)', 'caissier', { appliquer: false, motif: 'm' });
      dec('décision absente', 'comptable', {});
      dec('non appliqué sans motif', 'comptable', { appliquer: false });
      dec('non appliqué avec motif', 'comptable', { appliquer: false, motif: 'L’acheteur paie lui-même son AIB' });
      dec('ligne absente', 'comptable', { appliquer: true, taux: 1 });
      dec('ligne inconnue', 'comptable', { appliquer: true, situation: 'nexiste_pas', taux: 1 });
      dec('taux absent', 'comptable', { appliquer: true, situation: 'ifu_actif' });
      dec('taux invalide', 'comptable', { appliquer: true, situation: 'ifu_actif', taux: 150 });
      dec('taux décimal', 'comptable', { appliquer: true, situation: 'ifu_actif', taux: 1.5 });
      dec('taux hors barème sans motif', 'comptable', { appliquer: true, situation: 'ifu_actif', taux: 3 });
      dec('taux du barème (1 %)', 'comptable', { appliquer: true, situation: 'ifu_actif', taux: 1 });
      dec('taux hors barème motivé (3 %)', 'da', { appliquer: true, situation: 'ifu_actif', taux: 3, motif: 'Convention de la Direction' });
      dec('ligne de retenue (personne morale 5 %)', 'admin', { appliquer: true, situation: 'personne_morale', taux: 5 });
      out.decisions = decisions;
      /* 4. l'émission : un brouillon sans décision, un avec décision, un émis, un sans droit */
      const emissions = [];
      const emi = (nom, role, prepar) => {
        const b = brouillon(); if (prepar) prepar(b.id);
        const avant = propre(S.collection('facturesTiers').get(b.id));
        const droit = !!N.droitGeste(role, 'emettre_facture_tiers');
        const r = sous(role, () => T.emettre(b.id));
        emissions.push({ nom, role, droit, facture: { statut: avant.statut, numero: avant.numero || null, ifuAcheteur: avant.ifuAcheteur, nomAcheteur: avant.nomAcheteur, aibDecision: avant.aibDecision || null },
          sortie: r.ok ? { ok: true, numeroPrefixe: /^FT-\d{4}-\d{4}$/.test(r.numero), net: r.net, aib: r.aib } : { ok: false, code: r.code } });
        return b.id;
      };
      emi('sans droit d’émettre (comptable sans le geste)', 'laborantin', (id) => sous('comptable', () => T.deciderAib(id, { appliquer: false, motif: 'x' })));
      emi('sans décision de l’AIB', 'caissier');
      emi('décidée : non appliqué', 'caissier', (id) => sous('comptable', () => T.deciderAib(id, { appliquer: false, motif: 'Sonde' })));
      emi('décidée : 1 % (base 100 000, AIB 1 000)', 'caissier', (id) => sous('comptable', () => T.deciderAib(id, { appliquer: true, situation: 'ifu_actif', taux: 1 })));
      const dejaId = emi('déjà émise : seconde émission', 'caissier', (id) => sous('comptable', () => T.deciderAib(id, { appliquer: false, motif: 'Sonde' })));
      const deja = propre(S.collection('facturesTiers').get(dejaId));
      emissions.push({ nom: 'pièce déjà émise', role: 'caissier', droit: true, facture: { statut: deja.statut, numero: deja.numero, ifuAcheteur: deja.ifuAcheteur, nomAcheteur: deja.nomAcheteur, aibDecision: deja.aibDecision }, sortie: { ok: false, code: sous('caissier', () => T.emettre(dejaId)).code } });
      out.emissions = emissions;
      /* 5. le numéro : l'année de la date de la pièce */
      const pieces = S.collection('facturesTiers').all().map((f) => ({ numero: f.numero || null })).filter((f) => f.numero);
      out.numeros = { pieces: propre(pieces), cas: ['2026-10-30', '2026-01-01', '2026-12-31', '2027-03-05', '2025-06-01', ''].map((d) => ({ date: d, numero: T.numeroSuivant(d || undefined) })) };
      /* 6. la créance, le lettrage, la balance âgée : trois factures émises (récente, moyenne, ancienne), un avoir, un règlement, des lettrages */
      const creer = (code, date, montant, aibOui) => { const r = T.proposer({ tiersCode: code, date, lignes: [{ factureId: fac.id, ligneId: lignes[ligne++], montant }] }); const d = sous('comptable', () => aibOui ? T.deciderAib(r.id, { appliquer: true, situation: 'ifu_actif', taux: 1 }) : T.deciderAib(r.id, { appliquer: false, motif: 'Vecteur' })); return T.emettre(r.id).id; };
      /* le tableau de lignes est épuisé par les cas précédents : on libère en archivant les brouillons restants */
      S.collection('facturesTiers').all().filter((f) => f.statut === 'brouillon').forEach((f) => S.collection('facturesTiers').archive(f.id, 'Vecteur : restauration'));
      S.collection('facturesTiers').all().filter((f) => f.statut === 'emise').forEach((f) => { T.avoir(f.id, 'Vecteur : libère les lignes'); });
      const libres = T.lignesFacturables(fac.id).lignes.filter((l) => l.disponible > 0).map((l) => l.ligneId);
      let k = 0;
      const mk = (code, date, montant, aibOui) => { const r = T.proposer({ tiersCode: code, date, lignes: [{ factureId: fac.id, ligneId: libres[k++], montant }] }); if (!r.ok) throw new Error('proposer ' + r.code); sous('comptable', () => aibOui ? T.deciderAib(r.id, { appliquer: true, situation: 'ifu_actif', taux: 1 }) : T.deciderAib(r.id, { appliquer: false, motif: 'Vecteur' })); const e = T.emettre(r.id); if (!e.ok) throw new Error('emettre ' + e.code); return r.id; };
      const f1 = mk(tiers.code, '2026-10-20', 100000, true), f2 = mk(tiers.code, '2026-08-30', 100000, false), f3 = mk(tiersSans.code, '2026-05-01', 100000, true);
      const f4 = mk(tiers.code, '2026-10-25', 50000, false);
      const av = sous('comptable', () => T.avoir(f4, 'Vecteur : annulée'));
      const regl = T.reglement({ tiersCode: tiers.code, date: '2026-10-28', montant: 150000, mode: 'virement', referencePaiement: 'VIR-V-1' });
      const regl2 = T.reglement({ tiersCode: tiersSans.code, date: '2026-10-28', montant: 5000, mode: 'cheque', referencePaiement: 'CHQ-V-2' });
      const etat = () => ({ factures: propre(S.collection('facturesTiers').all().filter((f) => f.statut === 'emise').map((f) => ({ id: f.id, statut: f.statut, numero: f.numero, tiersCode: f.tiersCode, tiersNom: f.tiersNom, date: f.date, net: f.net, delaiPaiementJours: f.delaiPaiementJours === undefined ? null : f.delaiPaiementJours }))),
        avoirs: propre(S.collection('avoirsTiers').active().map((a) => ({ id: a.id, factureTiersId: a.factureTiersId, statut: a.statut }))),
        reglements: propre(S.collection('reglementsTiers').active().map((r) => ({ id: r.id, tiersCode: r.tiersCode, montant: r.montant, numero: r.numero, statut: r.statut }))),
        lettrages: propre(S.collection('lettragesTiers').active().map((l) => ({ id: l.id, reglementId: l.reglementId, factureTiersId: l.factureTiersId, montant: l.montant, statut: l.statut }))) });
      const creances = { depart: etat(), ids: { f1, f2, f3, f4, regl: regl.id, regl2: regl2.id }, jour: '2026-10-30', etapes: [] };
      const du = (id) => T.creance(S.collection('facturesTiers').get(id));
      const etape = (nom, entree, droitRole, f) => { const r = sous(droitRole, f); creances.etapes.push({ nom, role: droitRole, droit: !!N.droitGeste(droitRole, 'corriger_facture_tiers'), entree: propre(entree), etat: etat(), sortie: r.ok ? { ok: true, lettre: r.lettre, resteNonLettre: r.resteNonLettre } : { ok: false, code: r.code },
        creances: { f1: du(f1), f2: du(f2), f3: du(f3), f4: du(f4) }, balance: propre(T.creances('2026-10-30')) }); };
      /* chaque étape enregistre l'état d'ENTRÉE avant l'écriture : on le relève avant l'appel */
      const lettrer = (nom, role, reglId, aff) => { const entree = { reglementId: reglId, affectations: aff }; const avant = etat(); const r = sous(role, () => T.lettrer(entree)); creances.etapes.push({ nom, role, droit: !!N.droitGeste(role, 'corriger_facture_tiers'), entree: propre(entree), etatAvant: avant,
        sortie: r.ok ? { ok: true, lettre: r.lettre, resteNonLettre: r.resteNonLettre } : { ok: false, code: r.code }, creances: { f1: du(f1), f2: du(f2), f3: du(f3), f4: du(f4) }, balance: propre(T.creances('2026-10-30')), etatApres: etat() }); };
      creances.balanceDepart = propre(T.creances('2026-10-30'));
      lettrer('sans droit (caissier)', 'caissier', regl.id, [{ factureTiersId: f1, montant: 1000 }]);
      lettrer('aucune facture', 'comptable', regl.id, []);
      lettrer('facture d’un autre tiers', 'comptable', regl.id, [{ factureTiersId: f3, montant: 1000 }]);
      lettrer('facture annulée par un avoir', 'comptable', regl.id, [{ factureTiersId: f4, montant: 1000 }]);
      lettrer('facture inconnue', 'comptable', regl.id, [{ factureTiersId: 'FTPinconnue', montant: 1000 }]);
      lettrer('au-delà du dû de la facture', 'comptable', regl.id, [{ factureTiersId: f1, montant: 101001 }]);
      lettrer('au-delà du reste du règlement', 'comptable', regl.id, [{ factureTiersId: f1, montant: 101000 }, { factureTiersId: f2, montant: 60000 }]);
      lettrer('montant décimal', 'comptable', regl.id, [{ factureTiersId: f1, montant: 100.5 }]);
      lettrer('montant nul', 'comptable', regl.id, [{ factureTiersId: f1, montant: 0 }]);
      lettrer('facture répétée', 'comptable', regl.id, [{ factureTiersId: f1, montant: 1000 }, { factureTiersId: f1, montant: 1000 }]);
      lettrer('lettrage sur deux factures (101 000 + 49 000)', 'comptable', regl.id, [{ factureTiersId: f1, montant: 101000 }, { factureTiersId: f2, montant: 49000 }]);
      lettrer('règlement entièrement lettré', 'da', regl.id, [{ factureTiersId: f2, montant: 1 }]);
      lettrer('second règlement du second tiers (5 000 sur f3)', 'admin', regl2.id, [{ factureTiersId: f3, montant: 5000 }]);
      creances.avoir = { f4: av.ok };
      out.creances = creances;
      /* 7. les sets de synchronisation sont dans le domaine ; ici on note les collections que le moteur écrit */
      out.collections = ['tiersPayeurs', 'facturesTiers', 'avoirsTiers', 'reglementsTiers', 'lettragesTiers'];
      /* restitution : tout ce que les cas ont posé est archivé */
      ['lettragesTiers', 'reglementsTiers', 'avoirsTiers', 'facturesTiers', 'tiersPayeurs', 'factures'].forEach((c) => S.collection(c).all().forEach((x) => { if (x.statut !== 'archive') S.collection(c).archive(x.id, 'Vecteur : restauration'); }));
      return out;
    });
    console.log('  ' + sortie.acheteurs.length + ' acheteurs · ' + sortie.champs.length + ' champs · ' + sortie.decisions.length + ' décisions · ' + sortie.emissions.length + ' émissions · ' + sortie.creances.etapes.length + ' étapes de lettrage');
    ecrire('packages/domaine/test/vecteurs/tiers.json', sortie);
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
