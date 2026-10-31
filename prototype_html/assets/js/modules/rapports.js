/* =============================================================================
 * RAPPORTS, IMPRESSION & ÉTATS OFFICIELS
 * -----------------------------------------------------------------------------
 * CDCT §21 — catalogue complet des états et rapports que le système doit
 * éditer, tous revêtus de l'entête officielle de la clinique.
 * draf1 §10.14 — bibliothèque des états, prévisualisation, impression, export,
 * archivage et journal des éditions.
 * ========================================================================== */
(function (global) {
  'use strict';
  var C = global.SIGH.core, U = global.SIGH.ui, S = global.SIGH.store, D = global.SIGH.data,
      P = global.SIGH.print, G = global.SIGH.charts, K = global.SIGH.kit;
  var el = C.el;
  var AUJ = C.aujourdhui();   /* l’horloge réelle — vague 68 */

  /* Rattachement de chaque état à l'écran qui sait le produire. */
  var ECRANS = {
    'Fiche patient': 'm1-patients', 'Carte patient': 'm1-patients',
    'Historique médical': 'm1-patient-profil', 'Parcours de soins': 'm1-patient-profil',
    'Compte rendu de consultation': 'm2-consultations', 'Ordonnance': 'm2-ordonnances',
    'Certificat médical': 'm2-consultation-fiche', 'Bon d’examen': 'm2-consultation-fiche',
    'Bon d’admission': 'm3-admissions', 'Feuille de température': 'm3-feuille-temperature',
    'Feuille de soins': 'm3-soins', 'Bon de sortie': 'm3-sorties',
    'Sortie contre avis médical': 'm3-sortie-avis-medical', 'Rapport d’hospitalisation': 'm3-admissions',
    'Fiche d’accouchement': 'm4-accouchements', 'Acte de naissance': 'm4-naissances',
    'Registre des naissances': 'm4-naissances', 'Déclaration de décès': 'm4-deces',
    'Registre des décès': 'm4-deces',
    'Résultat d’analyse': 'm5-resultats', 'Rapport biologique': 'm5-resultats',
    'Bon de prélèvement': 'm5-demandes', 'Registre des analyses': 'm5-catalogue',
    'Bon de demande de sang': 'm5-banque-sang',
    'Bon d’expression de besoins': 'm7-besoins', 'Bon de commande': 'm7-commandes',
    'Bon de livraison': 'm7-livraisons', 'Bon de sortie de stock': 'm6-dispensation',
    'État d’inventaire': 'm6-inventaire', 'État des produits périmés': 'm6-lots',
    'État des alertes de stock': 'm6-alertes', 'Étiquettes produits': 'm6-etiquetage',
    'Facture normalisée MECeF': 'mecef-factures', 'Facture pro-forma': 'm8-proforma',
    'Reçu de paiement': 'm8-paiements', 'Avoir': 'mecef-avoirs',
    'État de caisse journalier': 'm8-caisse', 'Historique des paiements': 'm8-paiements',
    'Facture mensuelle par assureur': 'm9-factures-assureur', 'État des créances': 'm9-creances',
    'Lettre de relance': 'm9-relances', 'État des prises en charge': 'm9-prises-en-charge',
    'Contrat de travail': 'm10-contrats', 'Fiche employé': 'm10-personnel',
    'Fiche d’évaluation (NS 131)': 'm10-evaluations', 'Planning de garde/permanence': 'm10-planning',
    'État des présences': 'm10-presences', 'État des congés': 'm10-conges',
    'Notification de sanction': 'm10-sanctions',
    'Bulletin de paie': 'm11-bulletins', 'Fiche de solde mensuelle': 'm10-evaluations',
    'Journal de paie': 'm11-calcul', 'État des cotisations CNSS': 'm11-cotisations',
    'État ITS': 'm11-cotisations', 'État VPS': 'm11-cotisations', 'État des primes': 'm10-primes',
    'Journaux comptables': 'm12-journaux', 'Grand livre': 'm12-grand-livre',
    'Balance générale': 'm12-balance', 'Balance âgée': 'm12-balance',
    'Tableau d’amortissement': 'm12-immobilisations', 'État de rapprochement bancaire': 'm12-banques',
    'Bilan': 'm12-etats-financiers', 'Compte de résultat': 'm12-compte-resultat',
    'Tableau des flux de trésorerie': 'm12-flux-tresorerie',
    'Registre des courriers': 'm13-courriers', 'Compte rendu de réunion': 'm13-reunions',
    'Plan annuel de travail': 'm13-plan-annuel', 'Note de service': 'm13-notes-service',
    'Tableau de bord financier': 'dash-direction', 'Tableau de bord stock': 'm6-dashboard',
    'Tableau de bord RH': 'm10-dashboard', 'Tableau de bord d’activité': 'dash-direction',
    'Rapport d’activité': 'dash-direction',
    'Journal d’audit': 'm14-audit', 'Liste des comptes utilisateurs et rôles': 'm14-utilisateurs',
  };

  function catalogue() {
    var out = [];
    D.CATALOGUE_ETATS.forEach(function (dom) {
      dom.etats.forEach(function (e) {
        out.push({
          id: C.slug(dom.domaine + '-' + e),
          domaine: dom.domaine, etat: e,
          ecran: ECRANS[e] || null,
          disponible: !!ECRANS[e],
        });
      });
    });
    return out;
  }

  /* ==========================================================================
   * BIBLIOTHÈQUE DES ÉTATS
   * ======================================================================== */
  global.SIGH.screen('rapports-bibliotheque', {
    title: 'Bibliothèque des états',
    description: 'Catalogue de tous les états et rapports éditables par le système, avec accès direct à l’écran producteur.',
    regle: 'Tous les états reprennent automatiquement le <strong>papier à en-tête officiel</strong> de la clinique : logo, dénomination, adresse, téléphones, autorisation d’ouverture, IFU et RCCM, ainsi qu’un pied de page normalisé (pagination, date et heure d’impression, utilisateur générateur, identifiant unique).',
    render: function (root) {
      var rows = catalogue();
      var host = el('div.space-y-4');

      host.appendChild(U.kpiGrid([
        { label: 'États au catalogue', value: C.num(rows.length), icon: 'library', tone: 'navy' },
        { label: 'Domaines couverts', value: C.num(D.CATALOGUE_ETATS.length), icon: 'layers', tone: 'info' },
        { label: 'Éditables dans le prototype', value: C.num(rows.filter(function (r) { return r.disponible; }).length), icon: 'printer', tone: 'success' },
        { label: 'Modèle d’entête', value: 'Unique', icon: 'file-badge', tone: 'neutral', hint: 'Brand Configuration Center' },
      ]));

      /* Aperçu de l'entête officielle */
      var apercu = el('div.grid.gap-4.lg\\:grid-cols-3');
      var mentions = el('div.lg\\:col-span-2');
      mentions.appendChild(U.card('Mentions portées sur tous les états', U.descList([
        ['Dénomination', C.BRAND.nom],
        ['Adresse postale', C.BRAND.bp],
        ['Téléphones', C.BRAND.telephones.join('  /  ')],
        ['Adresse électronique', C.BRAND.email],
        ['Autorisation d’ouverture', C.BRAND.autorisation],
        ['IFU', el('span.font-mono.font-semibold', { text: C.BRAND.ifu })],
        ['RCCM', el('span.font-mono.font-semibold', { text: C.BRAND.rccm })],
        ['Devise', C.BRAND.devise],
      ], 'grid-cols-1 sm:grid-cols-2'), [K.lien('cfg-branding', 'Modifier l’identité', { size: 'sm', icon: 'settings' })]));
      apercu.appendChild(mentions);

      var pied = el('div');
      pied.appendChild(U.card('Pied de page normalisé', el('div.space-y-2', null, [
        pucePied('Dénomination, RCCM et IFU de l’établissement'),
        pucePied('Nom de l’utilisateur ayant généré le document'),
        pucePied('Date et heure d’impression'),
        pucePied('Identifiant unique du document (traçabilité)'),
        pucePied('Mention « Édité depuis le SIGH-CNT »'),
      ])));
      apercu.appendChild(pied);
      host.appendChild(apercu);

      /* Catalogue par domaine */
      D.CATALOGUE_ETATS.forEach(function (dom) {
        var grille = el('div.grid.gap-2.sm\\:grid-cols-2.lg\\:grid-cols-3');
        dom.etats.forEach(function (e) {
          var ecran = ECRANS[e];
          var carte = el('div.flex.items-center.gap-3.rounded-lg.border.border-slate-200.bg-white.px-3.py-2\\.5');
          carte.appendChild(el('span.grid.h-8.w-8.shrink-0.place-items-center.rounded-lg', {
            class: ecran ? 'bg-success-50 text-success-600' : 'bg-slate-100 text-slate-400',
          }, C.icon(ecran ? 'printer' : 'file', 'h-4 w-4')));
          carte.appendChild(el('span.min-w-0.flex-1.text-sm.text-slate-700', { text: e }));
          if (ecran) {
            carte.appendChild(el('a.btn.btn-secondary.btn-sm', { href: global.SIGH.app.href(ecran) }, 'Éditer'));
          } else {
            carte.appendChild(U.badge('À venir', 'neutral'));
          }
          grille.appendChild(carte);
        });
        host.appendChild(U.card(dom.domaine + ' — ' + dom.etats.length + ' état(s)', grille));
      });

      root.appendChild(host);
      return null;

      function pucePied(t) {
        return el('div.flex.items-start.gap-2', null, [
          el('span.mt-0\\.5.text-success-600', null, C.icon('check', 'h-3.5 w-3.5')),
          el('span.text-xs.text-slate-600', { text: t }),
        ]);
      }
    },
  });

  /* ==========================================================================
   * GÉNÉRATEUR DE RAPPORTS
   * ======================================================================== */
  global.SIGH.screen('rapports-generateur', {
    title: 'Générateur de rapports',
    description: 'Composition d’un rapport personnalisé : périmètre, période, indicateurs et mise en forme.',
    render: function (root) {
      var host = el('div.grid.gap-4.lg\\:grid-cols-3');

      var SECTIONS = [
        { id: 'activite', label: 'Activité — patients, consultations, hospitalisations' },
        { id: 'financier', label: 'Financier — chiffre d’affaires, encaissements, créances' },
        { id: 'stock', label: 'Stock — valeur, alertes, péremptions' },
        { id: 'laboratoire', label: 'Laboratoire — analyses réalisées, réactifs' },
        { id: 'rh', label: 'Ressources humaines — effectif, masse salariale, présences' },
        { id: 'comptable', label: 'Comptabilité — journaux, balance, résultat' },
        { id: 'assurances', label: 'Assurances — prises en charge et créances' },
      ];

      var f = U.form([
        { name: 'titre', label: 'Titre du rapport', required: true, col: 'full', value: 'Rapport d’activité' },
        { name: 'sousTitre', label: 'Sous-titre', col: 'full', value: 'Période : ' + C.moisAnnee(AUJ) },
        { name: 'destinataire', label: 'Destinataire', type: 'select', options: ['Direction', 'Conseil de gestion', 'Partenaire technique', 'Usage interne'] },
        { name: 'periode', label: 'Période', type: 'select', required: true, options: ['Journalière', 'Hebdomadaire', 'Mensuelle', 'Trimestrielle', 'Annuelle'], value: 'Mensuelle' },
        { name: 'dateDebut', label: 'Du', type: 'date', value: C.iso(new Date(2026, 7, 1)) },
        { name: 'dateFin', label: 'Au', type: 'date', value: C.iso(AUJ) },
        { name: 'filigrane', label: 'Filigrane', type: 'select', options: ['', 'Document officiel', 'Confidentiel', 'Brouillon'] },
      ], {});

      var choix = {};
      var listeSections = el('div.space-y-2');
      SECTIONS.forEach(function (s) {
        var row = el('label.flex.cursor-pointer.items-start.gap-2\\.5.rounded-lg.border.border-slate-200.p-3.transition-colors.hover\\:bg-slate-50');
        var cb = el('input.checkbox.mt-0\\.5', { type: 'checkbox' });
        cb.checked = ['activite', 'financier'].indexOf(s.id) !== -1;
        choix[s.id] = cb;
        row.appendChild(cb);
        row.appendChild(el('span.text-sm.text-slate-700', { text: s.label }));
        listeSections.appendChild(row);
      });

      var principal = el('div.space-y-4.lg\\:col-span-2');
      principal.appendChild(U.card('Paramètres du rapport', f));
      principal.appendChild(U.card('Sections à inclure', listeSections));
      host.appendChild(principal);

      var lateral = el('div.space-y-4');
      lateral.appendChild(U.card('Génération', el('div.space-y-2', null, [
        K.btn('Prévisualiser et imprimer', { variant: 'primary', icon: 'printer', onclick: generer }),
        K.note('Le rapport reprend automatiquement l’entête et le pied de page officiels de la clinique.', { tone: 'info' }),
      ])));
      lateral.appendChild(U.card('Modèles enregistrés', el('div.space-y-2', null, [
        modele('Rapport d’activité mensuel', 'Direction', ['activite', 'financier']),
        modele('Situation des stocks', 'Gestion des stocks', ['stock']),
        modele('Rapport financier trimestriel', 'Direction', ['financier', 'comptable']),
        modele('Bilan social', 'Ressources humaines', ['rh']),
      ])));
      host.appendChild(lateral);
      root.appendChild(host);
      return null;

      function modele(nom, dest, sections) {
        return el('button.flex.w-full.items-center.gap-3.rounded-lg.border.border-slate-200.px-3.py-2\\.5.text-left.transition-colors.hover\\:border-navy-300.hover\\:bg-navy-50', {
          type: 'button',
          onclick: function () {
            f.controls.titre.value = nom;
            f.controls.destinataire.value = dest;
            Object.keys(choix).forEach(function (k) { choix[k].checked = sections.indexOf(k) !== -1; });
            U.toast('Modèle « ' + nom + ' » chargé.', { type: 'info' });
          },
        }, [
          el('span.grid.h-8.w-8.shrink-0.place-items-center.rounded-lg.bg-navy-50.text-navy-700', null, C.icon('file-text', 'h-4 w-4')),
          el('span.min-w-0', null, [
            el('span.block.truncate.text-sm.font-medium.text-slate-800', { text: nom }),
            el('span.block.text-xs.text-slate-400', { text: dest }),
          ]),
        ]);
      }

      function generer() {
        var v = f.collect();
        if (!v) { U.toast('Le formulaire comporte des erreurs.', { type: 'error' }); return; }
        var actives = Object.keys(choix).filter(function (k) { return choix[k].checked; });
        if (!actives.length) { U.toast('Sélectionner au moins une section.', { type: 'error' }); return; }

        var contenu = el('div.space-y-4');
        actives.forEach(function (id) {
          var s = SECTIONS.filter(function (x) { return x.id === id; })[0];
          contenu.appendChild(el('p.mt-3.text-\\[11px\\].font-bold.uppercase.text-navy-900', { text: s.label.split(' — ')[0] }));
          contenu.appendChild(P.tableau([
            { label: 'Indicateur', key: 'k' },
            { label: 'Valeur', key: 'v', align: 'right' },
          ], donnees(id)));
        });

        P.etat({
          titre: v.titre,
          sousTitre: v.sousTitre || null,
          filigrane: v.filigrane || null,
          cartouche: [
            ['Période', v.periode],
            ['Du', C.dateFR(v.dateDebut)],
            ['Au', C.dateFR(v.dateFin)],
            ['Destinataire', v.destinataire || 'Usage interne'],
            ['Sections', C.num(actives.length)],
            ['Généré par', S.currentUser()],
          ],
          contenu: contenu,
          signatures: [{ role: 'Le Rédacteur', nom: S.currentUser() },
            { role: 'La Directrice Administrative', nom: 'TAKI Alimatou' },
            { role: 'Le Directeur Médical', nom: 'BASSONGUI Chabi Séko' }],
        });
      }

      function donnees(id) {
        var factures = S.collection('factures').active();
        var produits = S.collection('produits').active();
        var lots = S.collection('lots').active();
        var personnel = S.collection('personnel').active();
        var ecritures = S.collection('ecritures').active();
        var consultations = S.collection('consultations').active();
        var admissions = S.collection('admissions').active();

        var jeux = {
          activite: [
            { k: 'Patients au répertoire', v: C.num(S.collection('patients').active().length) },
            { k: 'Consultations réalisées', v: C.num(consultations.length) },
            { k: 'Hospitalisations', v: C.num(admissions.length) },
            { k: 'Hospitalisations en cours', v: C.num(admissions.filter(function (a) { return a.statut === 'en_cours'; }).length) },
            { k: 'Interventions à domicile', v: C.num(consultations.filter(function (c) { return c.type === 'Domicile'; }).length) },
          ],
          financier: [
            { k: 'Chiffre d’affaires', v: C.money(C.sum(factures, 'montantTTC')) },
            { k: 'Montant encaissé', v: C.money(C.sum(factures, 'montantPaye')) },
            { k: 'Reste à recouvrer', v: C.money(C.sum(factures, 'reliquat')) },
            { k: 'Nombre de factures', v: C.num(factures.length) },
            { k: 'Factures impayées', v: C.num(factures.filter(function (f) { return f.statutPaiement === 'impayee'; }).length) },
          ],
          stock: [
            { k: 'Références gérées', v: C.num(produits.length) },
            { k: 'Valeur du stock (CUMP)', v: C.money(C.sum(produits, function (p) { return p.stock * p.cump; })) },
            { k: 'Produits sous le seuil d’alerte', v: C.num(produits.filter(function (p) { return p.stock <= p.seuilAlerte; }).length) },
            { k: 'Lots périmés', v: C.num(lots.filter(function (l) { return l.statut === 'perime'; }).length) },
            { k: 'Lots à péremption proche', v: C.num(lots.filter(function (l) { return l.statut === 'alerte'; }).length) },
          ],
          laboratoire: [
            { k: 'Analyses au catalogue', v: C.num(D.ANALYSES.length) },
            { k: 'Demandes enregistrées', v: C.num(S.collection('demandesAnalyses').active().length) },
            { k: 'Résultats validés', v: C.num(S.collection('demandesAnalyses').active().filter(function (d) { return d.etatAnalyse === 'valide'; }).length) },
            { k: 'Réactifs sous seuil', v: C.num(produits.filter(function (p) { return (p.categorie === 'reactif' || p.categorie === 'conso_labo') && p.stock <= p.seuilAlerte; }).length) },
          ],
          rh: [
            { k: 'Effectif total', v: C.num(personnel.length) },
            { k: 'Masse salariale de base', v: C.money(C.sum(personnel, 'salaireBase')) },
            { k: 'Salaire moyen', v: C.money(personnel.length ? C.sum(personnel, 'salaireBase') / personnel.length : 0) },
            { k: 'Services représentés', v: C.num(Object.keys(C.groupBy(personnel, 'service')).length) },
          ],
          comptable: [
            { k: 'Écritures enregistrées', v: C.num(ecritures.length) },
            { k: 'Total débit', v: C.money(C.sum(ecritures, 'debit')) },
            { k: 'Total crédit', v: C.money(C.sum(ecritures, 'credit')) },
            { k: 'Équilibre', v: C.sum(ecritures, 'debit') === C.sum(ecritures, 'credit') ? 'Équilibré' : 'Écart de ' + C.money(Math.abs(C.sum(ecritures, 'debit') - C.sum(ecritures, 'credit'))) },
          ],
          assurances: [
            { k: 'Compagnies partenaires', v: C.num(D.ASSUREURS.length) },
            { k: 'Patients assurés', v: C.num(S.collection('patients').active().filter(function (p) { return !!p.assureur; }).length) },
            { k: 'Créances assureurs', v: C.money(C.sum(factures.filter(function (f) { return f.assureur; }), 'partAssurance')) },
          ],
        };
        return jeux[id] || [];
      }
    },
  });

  /* ==========================================================================
   * HISTORIQUE DES ÉDITIONS
   * ======================================================================== */
  global.SIGH.screen('rapports-historique', {
    title: 'Historique des éditions',
    description: 'Journal des documents générés, imprimés et exportés, avec l’utilisateur à l’origine de l’édition.',
    regle: 'Écran en lecture seule. L’historique des éditions retrace <strong>ce qui a été imprimé</strong> : il constitue une preuve et ne peut être retouché.',
    render: function (root) {
      var audit = (S.raw().audit || []).filter(function (a) { return a.action === 'Impression'; });
      var rnd = C.seeded(3221);
      var ETATS = Object.keys(ECRANS);
      var pers = S.collection('personnel').active();
      var rows = audit.map(function (a, i) {
        return {
          id: a.id, reference: a.reference || ('CNT-' + C.pad(i + 1, 5)),
          dateHeure: a.dateHeure, utilisateur: a.utilisateur,
          etat: C.pick(rnd, ETATS), module: a.module, format: 'PDF',
          poste: a.poste,
        };
      });
      /* Complément de démonstration pour disposer d'un historique représentatif */
      for (var i = rows.length; i < 60; i++) {
        var d = C.addDays(AUJ, -C.between(rnd, 0, 60));
        d.setHours(C.between(rnd, 7, 19), C.between(rnd, 0, 59));
        rows.push({
          id: 'ED' + i, reference: 'CNT-' + C.iso(d).replace(/-/g, '') + '-' + C.pad(i, 4),
          dateHeure: d.toISOString(),
          utilisateur: C.pick(rnd, pers).nomComplet,
          etat: C.pick(rnd, ETATS),
          module: C.pick(rnd, ['M1', 'M6', 'M8', 'M10', 'M11', 'M12', 'RAP']),
          format: C.pick(rnd, ['PDF', 'PDF', 'PDF', 'Impression directe', 'CSV']),
          poste: 'POSTE-' + C.pick(rnd, ['ACCUEIL', 'CAISSE', 'PHARMA', 'COMPTA', 'DIR']),
        });
      }
      rows = C.sortBy(rows, 'dateHeure', 'desc');

      var host = el('div.space-y-4');
      var mois = rows.filter(function (r) {
        var d = C.toDate(r.dateHeure);
        return d.getMonth() === AUJ.getMonth() && d.getFullYear() === AUJ.getFullYear();
      });

      host.appendChild(U.kpiGrid([
        { label: 'Éditions enregistrées', value: C.num(rows.length), icon: 'printer', tone: 'navy' },
        { label: 'Ce mois-ci', value: C.num(mois.length), icon: 'calendar', tone: 'info' },
        { label: 'Exports PDF', value: C.num(rows.filter(function (r) { return r.format === 'PDF'; }).length), icon: 'file-text', tone: 'success' },
        { label: 'Utilisateurs distincts', value: C.num(Object.keys(C.groupBy(rows, 'utilisateur')).length), icon: 'users', tone: 'neutral' },
      ]));

      host.appendChild(K.note('Chaque édition est journalisée avec son <strong>identifiant unique de document</strong>, l’utilisateur générateur et l’horodatage, conformément à l’exigence de traçabilité (RG-12).', { tone: 'info' }));

      host.appendChild(U.dataTable({
        title: 'Journal des éditions', rows: rows, exportName: 'historique-editions', pageSize: 20,
        filters: [
          { name: 'format', label: 'Format', options: ['PDF', 'Impression directe', 'CSV'] },
          { name: 'module', label: 'Module', options: Object.keys(C.groupBy(rows, 'module')).sort() },
        ],
        columns: [
          { key: 'reference', label: 'Réf. document', nowrap: true, render: function (r) { return el('span.font-mono.text-xs', { text: r.reference }); } },
          {
            key: 'dateHeure', label: 'Horodatage', nowrap: true,
            text: function (r) { return C.dateHeure(r.dateHeure); },
            render: function (r) { return C.dateHeure(r.dateHeure); },
            sortValue: function (r) { return C.toDate(r.dateHeure).getTime(); },
          },
          { key: 'etat', label: 'État édité' },
          { key: 'module', label: 'Module', render: function (r) { return U.badge(r.module, 'navy'); } },
          { key: 'format', label: 'Format', render: function (r) { return U.badge(r.format, 'neutral'); } },
          { key: 'utilisateur', label: 'Généré par' },
          { key: 'poste', label: 'Poste', nowrap: true, render: function (r) { return el('span.font-mono.text-xs.text-slate-500', { text: r.poste }); } },
        ],
      }));

      host.appendChild(K.charts([
        {
          title: 'Éditions par module',
          render: function () {
            var g = C.groupBy(rows, 'module');
            var keys = Object.keys(g);
            return G.barres(keys, [{ label: 'Éditions', data: keys.map(function (k) { return g[k].length; }) }]);
          },
        },
        {
          title: 'États les plus édités',
          render: function () {
            var g = C.groupBy(rows, 'etat');
            return K.ranking(Object.keys(g).map(function (k) { return { label: k, value: g[k].length }; })
              .sort(function (a, b) { return b.value - a.value; }).slice(0, 8));
          },
        },
      ]));
      root.appendChild(host);
      return null;
    },
  });
  /* ==========================================================================
   * ÉTATS DE LA DIRECTION
   * --------------------------------------------------------------------------
   * Le cahier de charge du 30/12/2024 énumère ce que la Directrice
   * Administrative attend : « points de vente et de caisse, journalier,
   * hebdomadaire, mensuel, trimestriel, semestriel, annuel ; par client, lot de
   * clients, article, lot d'articles, groupe et famille ; cumuls global et
   * détaillé ; totalisation du nombre d'un article vendu ; impression de chaque
   * état ».
   *
   * Une seule mécanique répond à tout cela : une PÉRIODE et un AXE d'analyse.
   * Multiplier les écrans pour chaque combinaison aurait donné trente-six
   * tableaux à maintenir.
   * ======================================================================== */
  var PERIODES_DA = [
    { id: 'jour', label: 'Journalier', jours: 1 },
    { id: 'semaine', label: 'Hebdomadaire', jours: 7 },
    { id: 'mois', label: 'Mensuel', jours: 30 },
    { id: 'trimestre', label: 'Trimestriel', jours: 91 },
    { id: 'semestre', label: 'Semestriel', jours: 182 },
    { id: 'annee', label: 'Annuel', jours: 365 },
  ];

  var AXES_DA = [
    { id: 'client', label: 'Par client', cle: 'patient', detail: 'Un patient, une ligne' },
    { id: 'nature', label: 'Par nature de facture', cle: 'type', detail: 'Consultation, maternité, pharmacie…' },
    { id: 'assureur', label: 'Par assureur', cle: 'assureur', detail: 'Compagnies conventionnées' },
    { id: 'article', label: 'Par article', cle: null, detail: 'Chaque produit ou prestation vendu' },
    { id: 'famille', label: 'Par famille d’articles', cle: null, detail: 'Sept familles de l’inventaire SAGE' },
    { id: 'groupe', label: 'Par groupe d’articles', cle: null, detail: 'Regroupement proposé — à valider' },
  ];

  global.SIGH.screen('rapports-direction', {
    title: 'États de la Direction',
    description: 'Points de vente et de caisse par période et par axe d’analyse, avec cumuls et impression.',
    regle: 'Les états sont <strong>calculés</strong> depuis les factures émises : ils ne se saisissent pas. '
      + 'Choisir une <strong>période</strong> et un <strong>axe</strong> suffit à produire les points demandés '
      + 'par le cahier de charge — par client, par article, par famille ou par groupe.',
    render: function (root) {
      var selPeriode = el('select.select');
      PERIODES_DA.forEach(function (p) { selPeriode.appendChild(el('option', { value: p.id }, p.label)); });
      selPeriode.value = 'mois';
      var selAxe = el('select.select');
      AXES_DA.forEach(function (a) { selAxe.appendChild(el('option', { value: a.id }, a.label)); });
      var selFin = el('input.input', { type: 'date', value: C.iso(AUJ) });
      var detaille = el('input.checkbox', { type: 'checkbox', id: 'f_detaille' });
      var vue = el('div.space-y-4');

      var barre = el('div.card');
      barre.appendChild(el('div.card-body.flex.flex-wrap.items-end.gap-3', null, [
        el('div', null, [el('label.label', { text: 'Périodicité' }), selPeriode]),
        el('div', null, [el('label.label', { text: 'Arrêté au' }), selFin]),
        el('div.min-w-\\[14rem\\]', null, [el('label.label', { text: 'Axe d’analyse' }), selAxe]),
        el('label.flex.cursor-pointer.items-center.gap-2.pb-2', { for: 'f_detaille' }, [
          detaille, el('span.text-xs.text-slate-600', { text: 'Cumul détaillé' }),
        ]),
        K.btn('Éditer l’état', { variant: 'primary', icon: 'printer', onclick: imprimer }),
      ]));

      [selPeriode, selAxe, selFin, detaille].forEach(function (c) { c.addEventListener('change', afficher); });
      root.appendChild(el('div.space-y-4', null, [barre, vue]));
      afficher();
      return null;

      function bornes() {
        var p = PERIODES_DA.filter(function (x) { return x.id === selPeriode.value; })[0];
        var f = C.toDate(selFin.value);
        return { debut: C.addDays(f, -(p.jours - 1)), fin: f, label: p.label };
      }

      function facturesPeriode() {
        var b = bornes();
        var d1 = C.toDate(b.debut).getTime(), d2 = C.toDate(b.fin).getTime();
        return S.collection('factures').active().filter(function (f) {
          var t = C.toDate(f.date).getTime();
          return t >= d1 && t <= d2 && f.montantTTC >= 0;
        });
      }

      /* Regroupement selon l'axe. Les axes « article », « famille » et
         « groupe » descendent au niveau des LIGNES : c'est là que se trouvent
         les quantités vendues, que le cahier de charge demande de totaliser. */
      function agreger() {
        var fac = facturesPeriode();
        var axe = selAxe.value;
        var groupes = {};

        function ajouter(cle, libelle, montant, quantite, extra) {
          if (!cle) cle = '—';
          if (!groupes[cle]) {
            groupes[cle] = Object.assign({
              cle: cle, libelle: libelle || cle,
              montant: 0, quantite: 0, pieces: 0, assureur: 0, patient: 0,
            }, extra || {});
          }
          groupes[cle].montant += montant || 0;
          groupes[cle].quantite += quantite || 0;
        }

        if (axe === 'client' || axe === 'nature' || axe === 'assureur') {
          var cleF = AXES_DA.filter(function (a) { return a.id === axe; })[0].cle;
          fac.forEach(function (f) {
            var v = f[cleF] || (axe === 'assureur' ? 'Sans assurance' : '—');
            ajouter(v, v, f.montantTTC, (f.lignes || []).length, {});
            groupes[v].pieces++;
            groupes[v].assureur += f.partAssurance || 0;
            groupes[v].patient += f.partPatient != null ? f.partPatient : f.montantTTC;
          });
        } else {
          var produits = S.collection('produits').active();
          fac.forEach(function (f) {
            (f.lignes || []).forEach(function (l) {
              var montant = l.montant != null ? l.montant : (l.quantite || 1) * (l.prixUnitaire || 0);
              var q = l.quantite || 1;
              if (axe === 'article') {
                ajouter(l.designation || l.produit || '—', l.designation || l.produit || '—', montant, q);
                groupes[l.designation || l.produit || '—'].pieces++;
                return;
              }
              /* Familles et groupes : on remonte par le produit quand la ligne
                 en désigne un ; les prestations sans article vont en « Actes ». */
              var prod = l.produitId ? produits.filter(function (p) { return p.id === l.produitId; })[0] : null;
              var cat = prod ? prod.categorie : null;
              var fam = cat ? D.familleDe(cat) : null;
              var grp = cat ? D.groupeDe(cat) : null;
              if (axe === 'famille') {
                var lf = fam ? fam.label : 'Actes et prestations';
                ajouter(lf, lf, montant, q);
                groupes[lf].pieces++;
              } else {
                var lg = grp ? grp.label : 'Actes et prestations';
                ajouter(lg, lg, montant, q);
                groupes[lg].pieces++;
              }
            });
          });
        }
        return Object.keys(groupes).map(function (k) { return groupes[k]; })
          .sort(function (a, b) { return b.montant - a.montant; });
      }

      function afficher() {
        var b = bornes();
        var axe = AXES_DA.filter(function (a) { return a.id === selAxe.value; })[0];
        var rows = agreger();
        var fac = facturesPeriode();

        C.clear(vue);
        vue.appendChild(U.kpiGrid([
          {
            label: 'Point ' + b.label.toLowerCase(), value: C.money(C.sum(fac, 'montantTTC')),
            icon: 'chart-no-axes-combined', tone: 'navy',
            hint: C.dateFR(b.debut) + ' → ' + C.dateFR(b.fin),
          },
          { label: 'Encaissé', value: C.money(C.sum(fac, 'montantPaye')), icon: 'banknote', tone: 'success' },
          { label: 'Pièces émises', value: C.num(fac.length), icon: 'receipt', tone: 'info' },
          {
            label: axe.label.replace('Par ', 'Postes — '), value: C.num(rows.length),
            icon: 'layers', tone: 'neutral', hint: axe.detail,
          },
        ]));

        if (selAxe.value === 'groupe') {
          vue.appendChild(K.note('Le regroupement en quatre groupes est une <strong>proposition</strong> : '
            + 'les documents de la clinique ne définissent que les sept familles de l’inventaire SAGE. '
            + 'À valider avant usage officiel.', { tone: 'warning', icon: 'help-circle' }));
        }

        var colonnes = [
          { key: 'libelle', label: axe.label.replace('Par ', '').replace(/^./, function (c) { return c.toUpperCase(); }) },
          { key: 'pieces', label: 'Pièces', align: 'right', render: function (r) { return C.num(r.pieces); } },
          {
            key: 'quantite', label: 'Quantité vendue', align: 'right',
            render: function (r) { return el('span.font-semibold', { text: C.num(r.quantite) }); },
          },
          {
            key: 'montant', label: 'Montant', align: 'right',
            text: function (r) { return String(r.montant); },
            render: function (r) { return el('span.font-semibold', { text: C.money(r.montant, false) }); },
          },
        ];
        if (detaille.checked && ['client', 'nature', 'assureur'].indexOf(selAxe.value) >= 0) {
          colonnes.push({ key: 'assureur', label: 'Part assureur', align: 'right', render: function (r) { return C.money(r.assureur, false); } });
          colonnes.push({ key: 'patient', label: 'Part patient', align: 'right', render: function (r) { return C.money(r.patient, false); } });
        }

        vue.appendChild(U.dataTable({
          title: 'Point ' + b.label.toLowerCase() + ' — ' + axe.label.toLowerCase(),
          rows: rows, exportName: 'etat-direction-' + selAxe.value,
          pageSize: 25, searchable: true, defaultSort: 'montant', defaultDir: 'desc',
          emptyMessage: 'Aucune vente sur la période.',
          columns: colonnes,
        }));

        vue.appendChild(K.note('<strong>Cumul global :</strong> ' + C.money(C.sum(rows, 'montant'))
          + ' sur ' + C.num(C.sum(rows, 'quantite')) + ' unité(s) vendue(s), '
          + C.num(rows.length) + ' poste(s) d’analyse.', { tone: 'info', icon: 'sigma' }));
        U.icons(vue);
      }

      function imprimer() {
        var b = bornes();
        var axe = AXES_DA.filter(function (a) { return a.id === selAxe.value; })[0];
        var rows = agreger();
        var fac = facturesPeriode();
        P.etat({
          titre: 'Point ' + b.label.toLowerCase() + ' — ' + axe.label.toLowerCase(),
          sousTitre: C.dateFR(b.debut) + ' au ' + C.dateFR(b.fin),
          cartouche: [['Périodicité', b.label], ['Du', C.dateFR(b.debut)], ['Au', C.dateFR(b.fin)],
            ['Axe d’analyse', axe.label], ['Pièces émises', C.num(fac.length)],
            ['Cumul global', C.money(C.sum(rows, 'montant'))]],
          contenu: P.tableau([
            { label: axe.label.replace('Par ', ''), key: 'libelle' },
            { label: 'Pièces', align: 'right', value: function (r) { return C.num(r.pieces); }, somme: function (r) { return r.pieces; }, formatTotal: function (v) { return C.num(v); } },
            { label: 'Quantité vendue', align: 'right', value: function (r) { return C.num(r.quantite); }, somme: function (r) { return r.quantite; }, formatTotal: function (v) { return C.num(v); } },
            { label: 'Montant', align: 'right', value: function (r) { return C.money(r.montant, false); }, somme: function (r) { return r.montant; } },
          ], rows, { total: true, totalLabel: 'CUMUL GLOBAL' }),
          signatures: [{ role: 'La Directrice Administrative', nom: 'TAKI Alimatou' },
            { role: 'Le Comptable', nom: 'KASSA Augustin' }],
        });
      }
    },
  });

})(window);
