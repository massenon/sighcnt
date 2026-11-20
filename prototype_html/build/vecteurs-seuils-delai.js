/* =============================================================================
 * VECTEURS DU DÉLAI MAXIMAL ENTRE DEUX MESURES (lot B, 13/11/2026) : l'écran RÉEL « Comparatif des résultats » est monté, un patient et un examen choisis, et ce que la
 * cellule « Variation » de la variable affiche est relu (texte de la variation, alerte, message « non évalué », âge de la mesure précédente), avec le verdict du moteur
 * (`SIGH.laboSeuils.alerteVariation`). Cas : sans délai, dans le délai, au bord, au-delà, valeur précédente nulle dans le délai et au-delà.
 * L'horloge est FIXÉE au 30/10/2026 (extraire.js) : les vecteurs ne dépendent pas du jour d'exécution.
 *   node build/vecteurs-seuils-delai.js   →   packages/domaine/test/vecteurs/seuils_delai.json
 * LIMITE DITE : le moteur des seuils n'existe PAS encore en Dart (lot de maquette seulement) : ce vecteur n'est consommé par aucun test Dart, il est tiré pour le jour du portage.
 * ========================================================================== */
'use strict';
const path = require('path');
const { ouvrirMaquette, ecrire, ROOT } = require('./extraire');

(async () => {
  console.log('▶ Vecteurs du délai entre deux mesures (seuils de variation)');
  const m = await ouvrirMaquette();
  try {
    await m.page.addScriptTag({ path: path.join(ROOT, 'assets/js/modules/m5-laboratoire.js') });
    const sortie = await m.page.evaluate(async () => {
      const S = SIGH.store, SE = SIGH.laboSeuils;
      const dormir = (ms) => new Promise((r) => setTimeout(r, ms));
      const so = S.session();
      S.setSession({ jeton: so.jeton, role: 'laborantin', nom: 'GARBA Yahouza', nomComplet: 'GARBA Yahouza', identifiant: 'y.garba', fonction: 'biologiste', secteur: 'LAB' });
      const NFS = 'NFS complète (hémogramme)', JUGE = '2026-10-30T12:00:00.000Z';
      const semer = (cle, mesures) => {
        const pat = S.collection('patients', { module: 'M1', entite: 'Patient' }).insert({ code: 'CNT/V' + cle + '/40', nom: 'VECT' + cle, prenom: 'Sonde', sexe: 'F', statut: 'actif', dateNaissance: '1985-03-12' }).record;
        const col = S.collection('demandesAnalyses', { module: 'M5', entite: 'demande', prefix: 'DEM' });
        mesures.forEach((x, i) => col.insert({
          patientId: pat.id, patient: pat.nom + ' ' + pat.prenom, patientCode: pat.code, analyse: NFS, analyseCode: 'NFS', examenCode: 'NFS',
          dateHeure: x.date + 'T09:00:00', reference: 'LAB-V' + cle + i, codeAnalyse: 'V' + cle + '-' + i, etatAnalyse: 'valide', valeurs: { GB: x.GB, HB: 12 },
          secteurDemandeur: 'Consultation', prescripteur: 'TAKI Orou', laborantin: 'GARBA Yahouza', origine: 'vecteur', statutPaiement: 'soldee',
          valideTechniqueLe: x.date + 'T10:00:00.000Z', valideTechniquePar: 'GARBA Yahouza', resultat: 'vecteur', conclusion: 'Normal',
          valideLe: x.derniere ? JUGE : x.date + 'T12:00:00.000Z', valideBiologiquePar: 'GARBA Yahouza' }));
        return pat.id;
      };
      const P78 = semer('A', [{ date: '2026-06-01', GB: 3 }, { date: '2026-08-18', GB: 9, derniere: true }]);
      const P8N = semer('B', [{ date: '2026-08-10', GB: 0 }, { date: '2026-08-18', GB: 5, derniere: true }]);
      const P78N = semer('C', [{ date: '2026-06-01', GB: 0 }, { date: '2026-08-18', GB: 5, derniere: true }]);
      const ecran = async (patientId) => {
        const root = document.createElement('div'); root.id = 'page-content'; document.body.appendChild(root);
        SIGH.screens['m5-resultats-comparatif'].render(root); await dormir(150);
        const wrap = [...root.querySelectorAll('*')].find((n) => Object.prototype.hasOwnProperty.call(n, 'value') && n.classList.contains('combo'));
        if (!wrap) throw new Error('combo absent'); wrap.value = patientId; wrap.dispatchEvent(new Event('change', { bubbles: true })); await dormir(400);
        const sel = root.querySelector('select.select:not([data-mesure-comparee])'); if (!sel || ![...sel.options].some((o) => o.value === 'NFS')) throw new Error('examen NFS absent : ' + (sel ? JSON.stringify([...sel.options].map((o) => o.value)) : 'pas de select') + ' | zone=' + root.innerText.replace(/\s+/g, ' ').slice(0, 200) + ' | n=' + SIGH.laboAnteriorites.mesuresRendues(patientId, 'NFS').visibles.length + ' | sels=' + root.querySelectorAll('select').length); sel.value = 'NFS'; sel.dispatchEvent(new Event('change', { bubbles: true })); await dormir(400);
        const td = root.querySelector('[data-comparatif] td[data-var="GB"][data-col="variation"]');
        if (!td) throw new Error('comparatif absent : ' + root.innerText.replace(/\s+/g, ' ').slice(0, 400) + ' | options=' + document.querySelectorAll('.combo-option').length);
        const t = (s) => { const n = td.querySelector(s); return n ? n.textContent.replace(/\s+/g, ' ').trim() : null; };
        const copie = td.cloneNode(true); copie.querySelectorAll('[data-age-precedente]').forEach((n) => n.remove());
        const r = { variation: copie.textContent.replace(/\s+/g, ' ').trim(), alerte: !!td.querySelector('[data-alerte-variation]'), nonEvalueeDelai: t('[data-variation-non-evaluee]'),
          ageAttribut: td.querySelector('[data-age-precedente]') ? td.querySelector('[data-age-precedente]').getAttribute('data-age-precedente') : null, ageTexte: t('[data-age-precedente]'),
          relatifNonEvaluable: !!td.querySelector('[data-alerte-nonevaluable]') };
        document.querySelectorAll('.modal-root, [role=dialog]').forEach((e) => { if (!e.closest('#page-content')) e.remove(); });
        root.remove();
        return r;
      };
      const verdict = (patientId) => {
        const v = S.collection('variablesLabo').get('VAR-NFS-GB');
        const d = S.collection('demandesAnalyses').all().filter((x) => x.patientId === patientId).sort((a, b) => String(a.dateHeure).localeCompare(String(b.dateHeure)));
        const L = SIGH.laboAnteriorites, prec = d[0], cmp = d[1];
        const a = SE.alerteVariation(v, L.variationEntre(v, prec.valeurs.GB, cmp.valeurs.GB), '2026-10-30', { ageJours: L.ageEntreMesures(prec, cmp) });
        return { alerte: a.alerte, nonEvalue: a.nonEvalue, nonEvaluable: a.nonEvaluable, ageJours: a.ageJours, delaiMaxJours: a.delaiMaxJours, ageInconnu: a.ageInconnu };
      };
      const cas = [];
      async function poser(nom, seuil, patientId, patients) {
        S.collection('seuilsDelta').all().splice(0); S.save();
        const e = SE.enregistrer('VAR-NFS-GB', seuil), v = SE.valider('VAR-NFS-GB', { motif: 'vecteur' });
        if (!e.ok || !v.ok) throw new Error('seuil refusé : ' + JSON.stringify([e.code, v.code]));
        cas.push({ nom, seuil, mesures: patients, moteur: verdict(patientId), ecran: await ecran(patientId) });
      }
      const m78 = [{ date: '2026-06-01', GB: 3 }, { date: '2026-08-18', GB: 9 }], m8n = [{ date: '2026-08-10', GB: 0 }, { date: '2026-08-18', GB: 5 }], m78n = [{ date: '2026-06-01', GB: 0 }, { date: '2026-08-18', GB: 5 }];
      await poser('sans délai : évalué, âge 78 jours affiché', { ecartAbsolu: 1 }, P78, m78);
      await poser('dans le délai (90) : évalué', { ecartAbsolu: 1, delaiMaxJours: 90 }, P78, m78);
      await poser('au bord (78 pour 78) : évalué', { ecartAbsolu: 1, delaiMaxJours: 78 }, P78, m78);
      await poser('au-delà (30) : non évalué, dit', { ecartAbsolu: 1, delaiMaxJours: 30 }, P78, m78);
      await poser('valeur précédente nulle, dans le délai : relatif non évaluable, âge 8 jours', { ecartRelatif: 20, delaiMaxJours: 30 }, P8N, m8n);
      await poser('valeur précédente nulle, au-delà du délai : non évalué (délai), pas de pourcentage', { ecartRelatif: 20, delaiMaxJours: 30 }, P78N, m78n);
      S.collection('seuilsDelta').all().splice(0); S.save();
      return { cas, jour: '2026-10-30' };
    });
    ecrire('packages/domaine/test/vecteurs/seuils_delai.json', { _doc: 'ENGENDRÉ par prototype_html/build/vecteurs-seuils-delai.js — ne pas éditer. Non consommé par un test Dart : le moteur des seuils n\'est pas porté (lot B, maquette seulement).', jour: sortie.jour, cas: sortie.cas });
    sortie.cas.forEach((c) => console.log('  ' + c.nom + ' : alerte=' + c.ecran.alerte + ' · ' + (c.ecran.nonEvalueeDelai || '—') + ' · âge ' + c.ecran.ageAttribut));
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
