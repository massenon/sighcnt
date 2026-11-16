/* =============================================================================
 * VECTEURS DU LOT FISC-2 (Direction, 16/11/2026, section AQ) : confirmation d'une obligation fiscale (CNSS), imputation de l'AIB opération par opération
 * -----------------------------------------------------------------------------
 * Le MOTEUR RÉEL de la maquette est piloté dans Chrome sur la base jetable (jamais recopié) :
 *   SIGH.configurationFiscale.confirmerObligation : refus nommés (fileul, droit, obligation inconnue, déjà confirmée, référence absente, exercice clos, date antérieure)
 *                                                    et confirmation (la fiche APRÈS, la copie à l'historique) ;
 *   SIGH.imputationAib.imputer / proposer          : la proposition du barème à la date, les refus nommés, les trois imputations (appliquée, non appliquée, hors proposition).
 * Chaque cas porte son entrée (rôle, poste fileul, droit du geste réservé lu à la fiche RBAC), la sortie, et l'état d'entrée. Un cas qui écrit est RESTITUÉ avant le suivant :
 * tous les cas confirment la MÊME obligation d'origine. Horloge d'extraction : 30/10/2026 midi.
 *   SIGH_PORT_PHP=<port libre> SIGH_BASE_TEST=<base à soi> node build/vecteurs-fisc2.js   →   packages/domaine/test/vecteurs/fisc2.json
 * Rejoués par packages/domaine/test/fisc2_test.dart (cfbConfirmerObligation, aibProposerImputation, aibImputer).
 * ========================================================================== */
'use strict';
const { ouvrirMaquette, ecrire } = require('./extraire');

(async () => {
  console.log('▶ Vecteurs du lot FISC-2 (confirmation, imputation de l’AIB)');
  const m = await ouvrirMaquette();
  try {
    const sortie = await m.page.evaluate(() => {
      const S = SIGH.store, C = SIGH.core, CF = SIGH.configurationFiscale, IA = SIGH.imputationAib, N = SIGH.nav, B = SIGH.baremeAib;
      const propre = (x) => JSON.parse(JSON.stringify(x === undefined ? null : x));
      const SESSION = { role: 'admin', fonction: 'admin', nom: 'Admin Vecteur', nomComplet: 'Admin Vecteur', identifiant: 'admin.vecteur', secteur: 'DIR' };
      S.setSession(SESSION);
      const sous = (role, fileul, f) => {
        const avant = S.session(), reg = S.reglage('posteFileul', false);
        S.setSession(Object.assign({}, SESSION, { role, nom: 'Acteur ' + role, nomComplet: 'Acteur ' + role }));
        S.setReglage('posteFileul', !!fileul);
        try { return f(); } finally { S.setSession(avant); S.setReglage('posteFileul', reg); }
      };
      const out = { _doc: 'ENGENDRÉ par prototype_html/build/vecteurs-fisc2.js : SIGH.configurationFiscale.confirmerObligation et SIGH.imputationAib pilotés dans Chrome, ne pas éditer. Horloge : 30/10/2026 midi.' };
      out.aujourdhui = C.iso(C.aujourdhui());
      out.gestes = { confirmer: 'confirmer_obligation_fiscale', imputer: 'imputer_aib' };
      out.detenteurs = { confirmer: N.rolesAvecGeste('confirmer_obligation_fiscale').slice().sort(), imputer: N.rolesAvecGeste('imputer_aib').slice().sort() };

      /* ---------- 1. la confirmation d'une obligation « à confirmer » ---------- */
      const colO = S.collection('obligationsFiscales'), colH = S.collection('historiqueObligations');
      out.obligations = propre(colO.all().filter((o) => o.code === 'CNSS-VERSEMENT' || o.code === 'CNSS'));
      out.exercices = propre(S.collection('exercices').all());
      const origine = propre(colO.all().filter((o) => o.code === 'CNSS-VERSEMENT')[0]);
      const net = (x) => { if (!x) return null; const c = propre(x); ['id', '_creePar', '_creeLe', '_modifiePar', '_modifieLe', 'confirmeeLe', 'modifieLe', 'remplaceeLe', 'obligationId'].forEach((k) => { delete c[k]; }); return c; };
      const confirmations = [];
      const cas = (nom, role, fileul, entree) => {
        const avantIds = new Set(colH.all().map((x) => x.id)), h0 = colH.all().length;
        const nouvelles = () => colH.all().filter((x) => !avantIds.has(x.id));
        const droit = !!N.droitGeste(role, 'confirmer_obligation_fiscale');
        const r = sous(role, fileul, () => CF.confirmerObligation(entree));
        const ligne = { nom, role, fileul: !!fileul, droit, entree: propre(entree), sortie: r.ok ? { ok: true, fiche: net(r.fiche), dateEffet: r.dateEffet, reference: r.reference, historique: net(nouvelles()[0]), nbHistorique: nouvelles().length }
          : { ok: false, code: r.code, motif: r.motif, geste: r.geste || null } };
        confirmations.push(ligne);
        if (r.ok) {
          nouvelles().forEach((h) => colH.archive(h.id, 'Vecteur : restauration'));
          const cur = colO.get(origine.id); const patch = {};
          Object.keys(cur).forEach((k) => { if (k === 'id' || k.charAt(0) === '_') return; if (!(k in origine)) patch[k] = null; });
          Object.keys(origine).forEach((k) => { if (k === 'id' || k.charAt(0) === '_') return; if (JSON.stringify(origine[k]) !== JSON.stringify(cur[k])) patch[k] = origine[k]; });
          colO.update(origine.id, patch);
        }
      };
      cas('fileul', 'admin', true, { code: 'CNSS-VERSEMENT', reference: 'R1' });
      cas('sans droit (comptable)', 'comptable', false, { code: 'CNSS-VERSEMENT', reference: 'R1' });
      cas('obligation inconnue', 'admin', false, { code: 'NEXISTE-PAS', reference: 'R1' });
      cas('obligation déjà arrêtée', 'admin', false, { code: 'CNSS', reference: 'R1' });
      cas('référence absente', 'admin', false, { code: 'CNSS-VERSEMENT', reference: '   ' });
      cas('référence manquante', 'admin', false, { code: 'CNSS-VERSEMENT' });
      cas('confirmée ce jour', 'admin', false, { code: 'CNSS-VERSEMENT', reference: 'Courrier CNSS n° 2026/118 du 12/11/2026' });
      cas('confirmée à une date à venir', 'da', false, { code: 'CNSS-VERSEMENT', reference: 'E-mail CNSS du 15/11/2026', dateEffet: '2026-12-01' });
      cas('confirmée par la Direction', 'direction', false, { code: 'CNSS-VERSEMENT', reference: 'Page CNSS « Déclaration et paiement », relevée le 16/11/2026', dateEffet: '2026-11-16' });
      out.confirmations = confirmations;

      /* ---------- 2. l'imputation de l'AIB ---------- */
      const colI = S.collection('imputationsAib');
      out.situations = propre(S.collection('situationsAib').all()); out.bareme = propre(S.collection('baremeAib').all());
      const compte = String(S.collection('comptes').active()[0].num);
      out.comptes = propre(S.collection('comptes').active().slice(0, 3).map((c) => ({ id: c.id, num: c.num, libelle: c.libelle, statut: c.statut })));
      out.compte = compte;
      out.propositions = [];
      [['personne_physique', '2026-11-16'], ['personne_morale', '2026-11-16'], ['personne_morale', '2025-12-31'], ['ifu_actif', '2026-11-16'], ['ifu_inactif_ou_absent', '2026-09-06'], ['ifu_inactif_ou_absent', '2026-09-07'], ['nexiste_pas', '2026-11-16']].forEach((a) => {
        const r = IA.proposer({ situation: a[0], date: a[1] }); const c = propre(r); delete c.undo; out.propositions.push({ situation: a[0], date: a[1], sortie: c });
      });
      const existantes = [];
      const imputations = [];
      const imp = (nom, role, saisie) => {
        const droit = !!N.droitGeste(role, 'imputer_aib');
        const n0 = colI.all().length;
        const r = sous(role, false, () => IA.imputer(saisie));
        let sortieC;
        if (r.ok) {
          const f = propre(colI.get(r.id)); ['id', '_creePar', '_creeLe', '_modifiePar', '_modifieLe', 'signeeLe', 'statut'].forEach((k) => { delete f[k]; });
          sortieC = { ok: true, fiche: f };
        } else sortieC = { ok: false, code: r.code, motif: r.motif, geste: r.geste || null };
        imputations.push({ nom, role, droit, entree: propre(saisie), existantes: propre(existantes.map((x) => Object.assign({}, x))), sortie: sortieC, nb: colI.all().length - n0 });
        if (r.ok) existantes.push(propre(colI.get(r.id)));
      };
      const base = { operation: 'achat_fournisseur', reference: 'FF-V-1', tiers: 'Fournisseur Vecteur', dateOperation: '2026-10-10', base: 100000 };
      imp('sans droit (caissier)', 'caissier', Object.assign({}, base, { appliquer: false, motif: 'm' }));
      imp('opération inconnue', 'comptable', Object.assign({}, base, { operation: 'vente', appliquer: false, motif: 'm' }));
      imp('référence absente', 'comptable', Object.assign({}, base, { reference: ' ', appliquer: false, motif: 'm' }));
      imp('date illisible', 'comptable', Object.assign({}, base, { dateOperation: 'demain', appliquer: false, motif: 'm' }));
      imp('base nulle', 'comptable', Object.assign({}, base, { base: 0, appliquer: false, motif: 'm' }));
      imp('base décimale', 'comptable', Object.assign({}, base, { base: 100.5, appliquer: false, motif: 'm' }));
      imp('décision absente', 'comptable', Object.assign({}, base, { situation: 'personne_morale', taux: 5, compte }));
      imp('non appliqué sans motif', 'comptable', Object.assign({}, base, { appliquer: false }));
      imp('ligne absente', 'comptable', Object.assign({}, base, { appliquer: true, taux: 5, compte }));
      imp('ligne inconnue', 'comptable', Object.assign({}, base, { appliquer: true, situation: 'nexiste_pas', taux: 5, compte }));
      imp('taux absent', 'comptable', Object.assign({}, base, { appliquer: true, situation: 'personne_morale', compte }));
      imp('taux invalide', 'comptable', Object.assign({}, base, { appliquer: true, situation: 'personne_morale', taux: 101, compte }));
      imp('taux décimal', 'comptable', Object.assign({}, base, { appliquer: true, situation: 'personne_morale', taux: 2.5, compte }));
      imp('compte absent', 'comptable', Object.assign({}, base, { appliquer: true, situation: 'personne_morale', taux: 5 }));
      imp('compte inconnu', 'comptable', Object.assign({}, base, { appliquer: true, situation: 'personne_morale', taux: 5, compte: '999999999' }));
      imp('taux hors barème sans motif', 'comptable', Object.assign({}, base, { appliquer: true, situation: 'personne_morale', taux: 3, compte }));
      imp('appliquée au taux du barème (5 % de 100 000)', 'comptable', Object.assign({}, base, { appliquer: true, situation: 'personne_morale', taux: 5, compte }));
      imp('déjà imputée (même écrite autrement)', 'comptable', Object.assign({}, base, { reference: 'ff-v-1', appliquer: false, motif: 'm' }));
      imp('non appliquée (assureur)', 'comptable', { operation: 'reglement_assureur', reference: 'REG-V-2', tiers: 'Assureur Vecteur', dateOperation: '2026-10-11', base: 250000, appliquer: false, motif: 'Cet assureur n’applique pas l’AIB à ce règlement' });
      imp('hors proposition motivée (4 % de 40 000)', 'da', { operation: 'reglement_prescripteur', reference: 'HON-V-3', tiers: 'Dr Vecteur', dateOperation: '2026-10-12', base: 40000, appliquer: true, situation: 'personne_physique', taux: 4, compte, motif: 'Le prescripteur a négocié 4 %' });
      imp('ligne de l’acheteur (prestation de service, 3 % de 33 333)', 'admin', { operation: 'achat_fournisseur', reference: 'FF-V-4', dateOperation: '2026-10-13', base: 33333, appliquer: true, situation: 'prestation_service', taux: 3, compte });
      out.imputations = imputations;
      /* ---------- 3. le motif du validateur (PRD M13 Q4, section AQ point 6) : TOUTE modification par le validateur se motive ---------- */
      const V = SIGH.validations;
      const motifs = [];
      const mot = (nom, famille, role, avant, valeurs, extra) => {
        extra = extra || {};
        const chiffres = V.chiffresModifies(famille, avant, valeurs);
        const r = sous(role, !!extra.fileul, () => V.controlerEnregistrement(famille, { role, chiffres, motif: extra.motif || null, avant, valeurs, modifie: extra.modifie }));
        motifs.push({ nom, famille, role, avant: propre(avant), valeurs: propre(valeurs), motif: extra.motif || null, modifie: extra.modifie === undefined ? null : extra.modifie, fileul: !!extra.fileul, chiffres, sortie: r ? { code: r.code, motif: r.motif, geste: r.geste || null } : null });
      };
      const fiche = { libelle: 'Modèle A', description: 'texte', aValider: false, valideLe: '2026-11-01T10:00:00.000Z' };
      mot('libellé modifié sans motif', 'modeles_badge', 'direction', fiche, { libelle: 'Modèle B' });
      mot('libellé modifié avec motif', 'modeles_badge', 'direction', fiche, { libelle: 'Modèle B' }, { motif: 'Coquille corrigée' });
      mot('plusieurs champs sans motif', 'modeles_badge', 'da', fiche, { libelle: 'B', description: 'autre' });
      mot('motif d’espaces', 'modeles_badge', 'admin', fiche, { libelle: 'Modèle B' }, { motif: '   ' });
      mot('valeur chiffrée sans motif', 'labo_variables', 'laborantin', { min: 1, max: 5, aValider: false }, { min: 2 });
      mot('valeur chiffrée avec motif', 'labo_variables', 'laborantin', { min: 1, max: 5, aValider: false }, { min: 2 }, { motif: 'Notice du réactif' });
      mot('aucun changement', 'modeles_badge', 'direction', fiche, { libelle: 'Modèle A' });
      mot('création par le validateur', 'modeles_badge', 'direction', null, { libelle: 'Neuf' });
      mot('profil hors famille (caissier)', 'modeles_badge', 'caissier', fiche, { libelle: 'Modèle B' });
      mot('seuls les marquages de validation', 'modeles_badge', 'direction', fiche, { aValider: true, valideLe: null });
      mot('artefact tenu ailleurs, modifié', 'valorisation_sage', 'admin', { prixRevient: 10 }, {}, { modifie: true });
      mot('artefact tenu ailleurs, inchangé', 'valorisation_sage', 'admin', { prixRevient: 10 }, {}, { modifie: false });
      mot('fileul', 'modeles_badge', 'direction', fiche, { libelle: 'Modèle B' }, { fileul: true, motif: 'x' });
      out.motifs = motifs;
      /* ---------- 4. les paramètres du calendrier fiscal, datés (délais d'alerte, montant de la CCIB) : D.delaisFiscauxALaDate, D.montantCcibALaDate ---------- */
      const D = SIGH.data;
      const colP = S.collection('parametresFiscaux');
      const avantP = colP.all().map((x) => x.id);
      out.parametresFiscaux = { depart: propre(colP.all()) };
      const m1 = CF.modifierParametreFiscal({ code: 'DELAIS-ALERTE', valeurs: { delaiAPayer: 15, delaiDeclaration: 45 }, dateEffet: '2026-12-01', motif: 'Vecteur : délais allongés' });
      const m2 = CF.modifierParametreFiscal({ code: 'CCIB-MONTANT', valeurs: { montantTotal: 400000 }, dateEffet: '2027-01-01', motif: 'Vecteur : CCIB révisée' });
      out.parametresFiscaux.fiches = propre(colP.all());
      out.parametresFiscaux.creees = [m1.ok, m2.ok];
      out.parametresFiscaux.delais = ['2026-10-30', '2026-11-30', '2026-12-01', '2027-03-01'].map((d) => { const r = D.delaisFiscauxALaDate(d); return { date: d, delaiAPayer: r.delaiAPayer, delaiDeclaration: r.delaiDeclaration }; });
      out.parametresFiscaux.ccib = ['2026-10-30', '2026-12-31', '2027-01-01', '2027-06-01'].map((d) => { const r = D.montantCcibALaDate(d); return { date: d, total: r.total, tranches: r.tranches, tranche: r.tranche }; });
      colP.all().filter((x) => avantP.indexOf(x.id) < 0).forEach((x) => colP.archive(x.id, 'Vecteur : restauration'));
      out.situationsParFamille = { acheteur: B.situations().map((x) => x.code), retenue: B.situations('retenue_tiers').map((x) => x.code), tous: B.situations('tous').map((x) => x.code) };
      /* restitution : les imputations posées sont archivées */
      colI.all().forEach((x) => { if (x.statut !== 'archive') colI.archive(x.id, 'Vecteur : restauration'); });
      return out;
    });
    console.log('  ' + sortie.confirmations.length + ' confirmations · ' + sortie.imputations.length + ' imputations · ' + sortie.propositions.length + ' propositions');
    ecrire('packages/domaine/test/vecteurs/fisc2.json', sortie);
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
