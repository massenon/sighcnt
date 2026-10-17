/* ==========================================================================
 * PEUPLEMENT DU JEU DE DÉMONSTRATION — NEUF MOIS D'ACTIVITÉ
 * --------------------------------------------------------------------------
 * Demande de la Direction du 26/08/2026 : peupler tous les modules, avec leurs
 * habilitations respectives, sur neuf mois.
 *
 * LE PRINCIPE QUI COMMANDE TOUT CE FICHIER : on ne fabrique pas vingt-huit
 * listes indépendantes, on REJOUE DE VRAIS PARCOURS. Une prescription passe par
 * PR.prescrire(), qui engendre elle-même l'ordonnance, les demandes d'analyses,
 * la facture et les files d'attente ; l'encaissement passe par PR.encaisser(),
 * qui débloque l'aval et pose l'écriture comptable.
 *
 * Deux raisons, et la seconde est la plus forte :
 *
 *   1. Les données sont COHÉRENTES entre modules — une facture correspond à une
 *      ordonnance qui correspond à des demandes de laboratoire. Vingt-huit
 *      listes tirées au sort donneraient des écrans pleins et un logiciel faux.
 *
 *   2. Les FORMES sont justes par construction. Recopier à la main les champs
 *      qu'attend chaque écran, c'est se tromper sur l'un d'eux et ne s'en
 *      apercevoir qu'à l'usage — ce qui est arrivé plusieurs fois sur ce
 *      projet, et toujours par supposition.
 *
 * CE PEUPLEMENT S'EXÉCUTE APRÈS LE CHARGEMENT DES MODULES, non pendant
 * store.seed() : le moteur de parcours n'existe pas encore à cet instant.
 * Il est déclenché une seule fois, sur un drapeau posé dans le magasin.
 * ======================================================================== */
(function (global) {
  'use strict';

  var C = global.SIGH.core;

  /* Neuf mois pleins, de décembre 2025 à la date de référence du prototype. */
  var FIN = new Date(2026, 7, 26);
  var DEBUT = new Date(2025, 11, 1);
  var JOURS = Math.round((FIN - DEBUT) / 86400000);

  function S() { return global.SIGH.store; }
  function PR() { return global.SIGH.parcours; }
  function D() { return global.SIGH.data; }

  function col(nom, meta) { return S().collection(nom, meta || {}); }
  function jour(rnd, recul) { return C.addDays(FIN, -recul); }
  function reculAleatoire(rnd) { return C.between(rnd, 0, JOURS); }

  /* Un jour ouvré : la clinique consulte du lundi au samedi, la garde
     assurant le dimanche. Semer des consultations le dimanche gonflerait
     artificiellement l'activité du week-end. */
  function jourOuvre(rnd) {
    for (var i = 0; i < 12; i++) {
      var d = jour(rnd, reculAleatoire(rnd));
      if (d.getDay() !== 0) return d;
    }
    return FIN;
  }

  /* ==========================================================================
   * OUTILLAGE
   * ======================================================================== */
  function patients() { return S().collection('patients').active(); }
  function personnel() { return S().collection('personnel').active(); }
  function soignants() { return S().collection('soignants').active(); }

  function parFonction(f) {
    return personnel().filter(function (a) { return a.fonction === f; });
  }
  function soignantsQui(pred) { return soignants().filter(pred); }

  function unDe(rnd, liste) { return liste.length ? C.pick(rnd, liste) : null; }

  /* ==========================================================================
   * 1. LES PARCOURS DE SOIN — le cœur
   * --------------------------------------------------------------------------
   * Chaque parcours traverse les modules dans l'ordre réel : consultation →
   * prescription → caisse → laboratoire ou pharmacie → résultat. On fait varier
   * l'avancement pour que chaque poste ait quelque chose à montrer : certains
   * parcours s'arrêtent à la caisse, d'autres vont jusqu'au résultat rendu.
   * ======================================================================== */
  function parcoursDeSoin(rnd, nb) {
    var pr = PR(), d = D();
    var meds = S().collection('produits').active().filter(function (p) { return p.stock > 20; });
    var analyses = (d.ANALYSES || []).filter(function (a) { return a.prix; });
    var medecins = parFonction('medecin').filter(function (a) { return !/Échographiste/i.test(a.poste || ''); });
    var bio = soignantsQui(function (x) { return x.qualite === 'medecin'; });
    var faits = { prescriptions: 0, encaisses: 0, resultats: 0, rendus: 0 };
    if (!medecins.length || !analyses.length) return faits;

    for (var i = 0; i < nb; i++) {
      var p = unDe(rnd, patients());
      var med = unDe(rnd, medecins);
      var date = C.iso(jourOuvre(rnd));
      var nAna = C.between(rnd, 1, 4);
      var codes = [];
      for (var k = 0; k < nAna; k++) {
        var a = unDe(rnd, analyses);
        if (a && codes.indexOf(a.code) === -1) codes.push(a.code);
      }
      var nMed = C.between(rnd, 0, 3);
      var lignesMed = [];
      for (var m = 0; m < nMed; m++) {
        var prod = unDe(rnd, meds);
        if (prod && !lignesMed.some(function (l) { return l.produitId === prod.id; })) {
          lignesMed.push({ produitId: prod.id, quantite: C.between(rnd, 1, 3),
            posologie: C.pick(rnd, ['1 cp x 3/j', '2 cp matin et soir', '1 sachet x 2/j', '1 amp/j']),
            duree: C.between(rnd, 3, 10) + ' jours' });
        }
      }
      if (!codes.length && !lignesMed.length) continue;

      var ord;
      try {
        ord = pr.prescrire({
          patientCode: p.code, medecin: med.nomComplet, date: date,
          diagnostic: C.pick(rnd, ['Paludisme simple', 'Fièvre typhoïde', 'Infection urinaire',
            'Anémie', 'Hypertension artérielle', 'Gastro-entérite', 'Bilan de santé',
            'Suivi de grossesse', 'Bronchite aiguë', 'Diabète — bilan']),
          analyses: codes, medicaments: lignesMed,
          urgent: rnd() > 0.88,
        });
      } catch (e) { continue; }
      faits.prescriptions++;

      /* --- L'encaissement : les trois quarts, dont un tiers partiellement.
         Un jeu où tout est payé ne montrerait jamais la file de la caisse ni
         les tâches bloquées. --------------------------------------------- */
      var fac = S().collection('factures').active().filter(function (f) {
        return f.ordonnanceId === ord.ordonnance.id;
      })[0];
      if (fac && rnd() > 0.25) {
        var dues = pr.lignesDues ? pr.lignesDues(fac) : [];
        var partiel = rnd() > 0.66 && dues.length > 1;
        var choisies = partiel ? dues.slice(0, Math.max(1, Math.floor(dues.length / 2))) : dues;
        try {
          pr.encaisser(fac.id, { lignes: choisies.map(function (l) { return l.id; }) });
          faits.encaisses++;
        } catch (e) { /* la facture n'a pas de lignes payables */ }
      }

      /* --- Le laboratoire : prélèvement, saisie, deux validations --------- */
      var demandes = S().collection('demandesAnalyses').active().filter(function (x) {
        return x.ordonnanceId === ord.ordonnance.id;
      });
      demandes.forEach(function (dem) {
        if (dem.etatAnalyse !== 'attente_prelevement') return;
        if (rnd() > 0.75) return;
        /* LA CONTINUITÉ : le même biologiste prélève et valide. */
        var biologiste = unDe(rnd, bio) || unDe(rnd, soignants());
        var quand = C.iso(C.addDays(C.toDate(dem.dateHeure), C.between(rnd, 0, 2)));
        /* L'ÉCRAN RANGE SES ONGLETS SUR LES HORODATAGES, pas sur l'état :
           à prélever (!preleveLe), à transmettre (preleveLe && !recuLaboLe),
           reçus (recuLaboLe). Le champ s'appelle `preleveLe` — écrire
           `prelevementLe` laissait les trois onglets se contredire. */
        S().collection('demandesAnalyses').update(dem.id, {
          etatAnalyse: 'preleve',
          prelevePar: biologiste ? biologiste.nomComplet : 'Laboratoire',
          preleveParId: biologiste ? biologiste.id : null,
          preleveLe: quand,
        });
        if (rnd() > 0.2) {
          /* UN RÉSULTAT SAISI SUPPOSE UN ÉCHANTILLON PARVENU. Poser le
             prélèvement sans la réception laisserait ces demandes en « à
             transmettre » pour l'éternité, alors que le laboratoire les a
             analysées. */
          S().collection('demandesAnalyses').update(dem.id, {
            etatAnalyse: 'en_cours',
            recuLaboLe: quand,
            recuPar: biologiste ? biologiste.nomComplet : 'Laboratoire',
          });

          /* UNE PART RESTE « AU LABORATOIRE » — reçue, non encore saisie.
             C'est l'état dans lequel se trouve, à tout instant, ce que le
             laboratoire a sur sa paillasse : le seul où il a quelque chose à
             faire immédiatement. Passer directement à la validation le rendait
             invisible, et le rappel du matin n'avait qu'une question sur deux
             à poser. */
          if (rnd() < 0.22) return;

          S().collection('demandesAnalyses').update(dem.id, {
            etatAnalyse: 'valide_technique',
            saisiPar: biologiste ? biologiste.nomComplet : 'Laboratoire',
            saisiLe: quand,
          });
          faits.resultats++;
          if (rnd() > 0.3) {
            S().collection('demandesAnalyses').update(dem.id, {
              /* Le code du référentiel, et lui seul. « valide_bio » n'y figure
                 pas : resultatRendu() le refusait, donc aucun résultat n'était
                 opposable au prescripteur. */
              etatAnalyse: 'valide',
              valideBioPar: biologiste ? biologiste.nomComplet : 'Laboratoire',
              valideBioLe: quand,
            });
            faits.rendus++;
          }
        }
      });
    }
    return faits;
  }

  /* ==========================================================================
   * 2. LES PRESCRIPTIONS DE SOINS ET LEURS ADMINISTRATIONS
   * --------------------------------------------------------------------------
   * On fait vivre la règle de relais : des traitements ambulatoires servis
   * entièrement en salle de soins, et des traitements hospitaliers dont la
   * première administration y passe avant que l'hospitalisation prenne la
   * suite. Sans cela, les deux postes afficheraient des files vides.
   * ======================================================================== */
  function prescriptionsDeSoins(rnd, nb) {
    var pr = PR(), d = D();
    var prescripteurs = soignantsQui(function (x) { return x.prescrit; });
    var executants = soignantsQui(function (x) { return x.execute; });
    var actesAmi = (d.tarifParFamille ? d.tarifParFamille('AMI') : [])
      .filter(function (a) { return a.prixNonAssure != null; });
    var faits = { prescriptions: 0, administrations: 0 };
    if (!prescripteurs.length || !actesAmi.length) return faits;

    for (var i = 0; i < nb; i++) {
      var p = unDe(rnd, patients());
      var presc = unDe(rnd, prescripteurs);
      var hospit = rnd() > 0.55;
      var nActes = C.between(rnd, 1, 3);
      var actes = [];
      for (var k = 0; k < nActes; k++) {
        var a = unDe(rnd, actesAmi);
        if (a && !actes.some(function (x) { return x.code === a.code; })) {
          actes.push({ code: a.code, nbAdministrations: hospit ? C.between(rnd, 2, 5) : C.between(rnd, 1, 3) });
        }
      }
      if (!actes.length) continue;

      var rec;
      try {
        rec = pr.prescrireSoins({
          patientCode: p.code, prescripteurId: presc.id,
          origine: C.pick(rnd, ['consultation', 'consultation', 'hospitalisation', 'maternite', 'bloc']),
          secteurDestinataire: hospit ? 'hospitalisation' : 'salle_soins',
          modalite: hospit ? 'hospitalisation' : 'ambulatoire',
          indication: C.pick(rnd, ['Pansement post-opératoire', 'Antibiothérapie parentérale',
            'Réhydratation', 'Surveillance de plaie', 'Traitement antipaludique']),
          date: C.iso(jourOuvre(rnd)),
          actes: actes,
        });
      } catch (e) { continue; }
      faits.prescriptions++;

      /* Les deux tiers sont réglés — sans quoi rien ne s'administrerait. */
      if (rnd() > 0.33) {
        col('prescriptions', { module: 'M2', entite: 'prescription', prefix: 'PRS' })
          .update(rec.id, { statutPaiement: 'payee' });

        /* On administre une partie des passages dus, en respectant le relais. */
        (rec.lignes || []).forEach(function (l, idx) {
          var total = l.nbAdministrations || 1;
          var faites = C.between(rnd, 0, total);
          for (var n = 0; n < faites; n++) {
            var rang = pr.rangSuivant(rec.id, idx);
            var att = d.secteurAdministrateur(rec.modalite, rang);
            var exec = unDe(rnd, executants.filter(function (x) {
              return (x.secteurs || []).indexOf(att.secteur) !== -1;
            })) || unDe(rnd, executants);
            if (!exec) break;
            var res = pr.administrer(rec.id, {
              ligneIndex: idx, secteur: att.secteur, executantId: exec.id,
              dateHeure: C.iso(C.addDays(C.toDate(rec.date), n)),
              observation: rnd() > 0.7 ? C.pick(rnd, ['Bien toléré', 'Douleur au point d’injection',
                'Patient calme', 'Sans incident']) : '',
            });
            if (!res.ok) break;
            faits.administrations++;
          }
        });
      }
    }
    return faits;
  }

  /* ==========================================================================
   * 3. LES PIÈCES CLINIQUES
   * ======================================================================== */
  function piecesCliniques(rnd) {
    var d = D();
    var faits = {};
    var medecins = soignantsQui(function (x) { return x.qualite === 'medecin'; });
    var sages = soignantsQui(function (x) { return x.qualite === 'sage_femme'; });
    var exec = soignantsQui(function (x) { return x.execute; });
    var femmes = patients().filter(function (p) { return p.sexe === 'F'; });

    /* --- Comptes rendus opératoires et check-listes --------------------- */
    var cro = col('crOperatoires', { module: 'M3', entite: 'compte rendu opératoire', prefix: 'CRO' });
    var ckl = col('checklistsBloc', { module: 'M3', entite: 'check-liste', prefix: 'CKL' });
    var INTERVENTIONS = [
      ['Appendicite aiguë', 'Appendicectomie par voie de McBurney', 'Rachianesthésie'],
      ['Hernie inguinale droite', 'Herniorraphie selon Lichtenstein', 'Rachianesthésie'],
      ['Grossesse à terme, souffrance fœtale', 'Césarienne segmentaire transversale', 'Rachianesthésie'],
      ['Kyste ovarien', 'Kystectomie par laparotomie', 'Anesthésie générale'],
      ['Fibrome utérin symptomatique', 'Myomectomie', 'Anesthésie générale'],
      ['Abcès de la fesse', 'Incision et drainage', 'Anesthésie locale'],
      ['Fracture fermée de l’avant-bras', 'Réduction et immobilisation plâtrée', 'Anesthésie locorégionale'],
    ];
    for (var i = 0; i < 26; i++) {
      var p = unDe(rnd, patients());
      var op = unDe(rnd, medecins);
      var an = unDe(rnd, exec) || op;
      var aide = rnd() > 0.4 ? unDe(rnd, exec) : null;
      var it = C.pick(rnd, INTERVENTIONS);
      var dt = C.iso(jourOuvre(rnd));
      if (!p || !op) break;
      var rec = cro.insert({
        reference: 'CRO-' + C.pad(i + 1, 4), dateOperation: dt,
        patientId: p.id, patient: p.nom + ' ' + p.prenom, patientCode: p.code, nip: p.code,
        diagnosticPeroperatoire: it[0],
        intervention: it[1],
        anesthesie: it[2],
        cro: 'Installation du patient. Asepsie et champage. ' + it[1] + '. '
          + C.pick(rnd, ['Exploration sans particularité.', 'Hémostase soigneuse.',
            'Pas d’incident per-opératoire.', 'Lavage abondant de la cavité.'])
          + ' Fermeture plan par plan. Pansement.',
        operateurId: op.id, operateur: op.nomComplet,
        aideOperateurId: aide ? aide.id : null, aideOperateur: aide ? aide.nomComplet : null,
        anesthesisteId: an.id, anesthesiste: an.nomComplet,
      }).record;

      /* Chaque intervention porte ses deux check-listes : les fondre ou en
         omettre une viderait l'exercice de son sens. */
      ['entree', 'sortie'].forEach(function (moment) {
        var items = moment === 'entree' ? d.CHECKLIST_BLOC.entree : d.CHECKLIST_BLOC.sortie;
        /* Quelques check-listes restent incomplètes : c'est la réalité d'un
           bloc chargé, et l'écran doit pouvoir le signaler. */
        var manque = rnd() > 0.82 ? C.between(rnd, 1, 2) : 0;
        var lignes = items.map(function (label, k) {
          return { label: label, coche: k >= items.length - manque ? false : true };
        });
        ckl.insert({
          reference: 'CKL-' + C.pad(i * 2 + (moment === 'entree' ? 1 : 2), 4),
          moment: moment, dateHeure: dt + 'T08:00:00.000Z',
          patientId: p.id, patient: rec.patient,
          responsableId: an.id, responsable: an.nomComplet,
          items: lignes,
          coches: lignes.filter(function (x) { return x.coche; }).length,
          total: lignes.length,
        });
      });
    }
    faits.cro = cro.active().length;

    /* --- Comptes rendus de maternité ------------------------------------ */
    var crm = col('crMaternite', { module: 'M4', entite: 'compte rendu de maternité', prefix: 'CRM' });
    (d.COMPTES_RENDUS_MATERNITE || []).forEach(function (mod, mi) {
      var n = mod.code === 'accouchement' ? 34 : (mod.code === 'planning_familial' ? 22 : 9);
      for (var j = 0; j < n; j++) {
        var pt = unDe(rnd, femmes);
        var sf = unDe(rnd, sages) || unDe(rnd, medecins);
        if (!pt || !sf) break;
        var o = {
          reference: 'CRM-' + C.pad(mi * 100 + j + 1, 4),
          typeCr: mod.code, typeLabel: mod.label,
          patientId: pt.id, patient: pt.nom + ' ' + pt.prenom, patientCode: pt.code,
          sageFemmeId: sf.id, sageFemme: sf.nomComplet,
          creeLe: C.iso(jourOuvre(rnd)) + 'T10:00:00.000Z',
        };
        /* Les rubriques sont remplies depuis leur DÉCLARATION : ajouter une
           rubrique au modèle la peuplera sans toucher à ce fichier. */
        mod.rubriques.forEach(function (r) {
          var nom = r[0], type = r[2], choix = r[4];
          if (type === 'liste' && choix) o[nom] = C.pick(rnd, choix);
          else if (type === 'binaire') o[nom] = rnd() > 0.5;
          else if (type === 'nombre') o[nom] = C.between(rnd, 1, 40);
          else if (type === 'date') o[nom] = C.iso(jourOuvre(rnd));
          else if (type === 'datetime') o[nom] = C.iso(jourOuvre(rnd)) + 'T'
            + C.pad(C.between(rnd, 0, 23), 2) + ':' + C.pad(C.between(rnd, 0, 59), 2);
          else if (type === 'soignant') o[nom] = sf.id;
          else if (type === 'zone') o[nom] = C.pick(rnd, ['Sans particularité.',
            'Évolution favorable.', 'Surveillance rapprochée.', 'Suites simples.']);
        });
        if (mod.code === 'accouchement') {
          o.poidsEnfant = C.between(rnd, 2200, 4100);
          o.apgar1 = C.between(rnd, 6, 10);
          o.apgar5 = C.between(rnd, 8, 10);
          o.termeSA = C.between(rnd, 36, 41);
        }
        crm.insert(o);
      }
    });
    faits.maternite = crm.active().length;

    /* --- Surveillance transfusionnelle ----------------------------------- */
    var trf = col('surveillancesTransfusion',
      { module: 'M3', entite: 'surveillance transfusionnelle', prefix: 'TRF' });
    var TEMPS = ['t0', 't15', 't30', 't60', 't90', 'fin', 'h1', 'h2'];
    for (var t = 0; t < 14; t++) {
      var pt2 = unDe(rnd, patients());
      var resp = unDe(rnd, exec);
      if (!pt2 || !resp) break;
      var incident = rnd() > 0.86;
      var releves = incident ? TEMPS.length : C.between(rnd, 5, TEMPS.length);
      var valeurs = {};
      TEMPS.forEach(function (tp, k) {
        if (k >= releves) { valeurs[tp] = {}; return; }
        valeurs[tp] = {
          temperature: (36.5 + rnd() * (incident && k > 2 ? 2.4 : 0.9)).toFixed(1),
          ta: C.between(rnd, 10, 14) + '/' + C.between(rnd, 6, 9),
          fr: String(C.between(rnd, 14, 22)),
          fc: String(C.between(rnd, 66, incident && k > 2 ? 128 : 96)),
          spo2: String(C.between(rnd, 94, 100)),
          urines: C.pick(rnd, ['claires', 'claires', 'foncées']),
          conscience: C.pick(rnd, ['normale', 'normale', 'obnubilation']),
          autre: '',
        };
      });
      trf.insert({
        reference: 'TRF-' + C.pad(t + 1, 4),
        patientId: pt2.id, patient: pt2.nom + ' ' + pt2.prenom, patientCode: pt2.code,
        service: C.pick(rnd, ['Hospitalisation', 'Maternité', 'Soins intensifs']),
        date: C.iso(jourOuvre(rnd)),
        pochePSL: 'PSL-' + C.between(rnd, 100000, 999999),
        debut: C.pad(C.between(rnd, 7, 18), 2) + 'h' + C.pad(C.between(rnd, 0, 59), 2),
        responsableId: resp.id, responsable: resp.nomComplet,
        valeurs: valeurs, releves: releves, attendus: TEMPS.length,
        incident: incident,
        natureIncident: incident ? C.pick(rnd, ['Frisson avec hyperthermie',
          'Urticaire généralisée', 'Douleur lombaire']) : null,
        conclusion: incident
          ? 'Transfusion interrompue, médecin appelé, traitement symptomatique institué.'
          : 'Transfusion menée à son terme sans incident. Surveillance poursuivie deux heures.',
      });
    }
    faits.transfusion = trf.active().length;

    /* --- Scores de Glasgow ----------------------------------------------- */
    var gcs = col('scoresGlasgow', { module: 'M3', entite: 'score de Glasgow', prefix: 'GCS' });
    var AXES = [
      { axe: 'Ouverture des yeux', max: 4 },
      { axe: 'Réponse verbale', max: 5 },
      { axe: 'Réponse motrice', max: 6 },
    ];
    var LIB = {
      'Ouverture des yeux': { 4: 'Spontanée', 3: 'Au bruit, à la parole', 2: 'À la douleur', 1: 'Aucune réponse' },
      'Réponse verbale': { 5: 'Normale', 4: 'Confuse', 3: 'Inappropriée', 2: 'Incompréhensible', 1: 'Aucune réponse' },
      'Réponse motrice': { 6: 'À la commande', 5: 'Localise la douleur', 4: 'Se retire à la douleur',
        3: 'Flexion à la douleur', 2: 'Extension à la douleur', 1: 'Aucune réponse' },
    };
    for (var g = 0; g < 18; g++) {
      var pt3 = unDe(rnd, patients());
      var ev = unDe(rnd, exec) || unDe(rnd, medecins);
      if (!pt3 || !ev) break;
      /* Un jeu où tous les scores valent 15 ne montrerait jamais l'alerte. */
      var grave = rnd() > 0.78;
      var axes = AXES.map(function (a) {
        var pts = grave ? C.between(rnd, 1, Math.max(1, a.max - 2)) : C.between(rnd, a.max - 1, a.max);
        return { axe: a.axe, libelle: LIB[a.axe][pts], points: pts };
      });
      gcs.insert({
        reference: 'GCS-' + C.pad(g + 1, 4),
        patientId: pt3.id, patient: pt3.nom + ' ' + pt3.prenom, nip: pt3.code,
        dateHeure: C.iso(jourOuvre(rnd)) + 'T' + C.pad(C.between(rnd, 6, 22), 2) + ':00',
        axes: axes,
        score: axes.reduce(function (n, a) { return n + a.points; }, 0),
        evaluePar: ev.id, evaluateur: ev.nomComplet,
        observation: grave ? C.pick(rnd, ['Réévaluation horaire prescrite',
          'Transfert en surveillance rapprochée', 'Médecin prévenu']) : '',
      });
    }
    faits.glasgow = gcs.active().length;

    /* --- Rapports médicaux ------------------------------------------------ */
    var rap = col('rapportsMedicaux', { module: 'M3', entite: 'rapport médical', prefix: 'RAP' });
    for (var r = 0; r < 22; r++) {
      var pt4 = unDe(rnd, patients());
      var md = unDe(rnd, medecins);
      if (!pt4 || !md) break;
      var entree = jourOuvre(rnd);
      var duree = C.between(rnd, 2, 12);
      var clos = rnd() > 0.2;
      var diag = C.pick(rnd, ['Paludisme grave', 'Fièvre typhoïde compliquée',
        'Pneumopathie aiguë communautaire', 'Anémie sévère', 'Crise drépanocytaire',
        'Accès palustre chez la femme enceinte', 'Gastro-entérite déshydratante']);
      rap.insert({
        reference: 'RAP-' + C.pad(r + 1, 4),
        patientId: pt4.id, patient: pt4.nom + ' ' + pt4.prenom, patientCode: pt4.code,
        age: C.age(pt4.dateNaissance), sexe: pt4.sexe,
        adresse: pt4.quartier, telephone: pt4.telephone,
        dateEntree: C.iso(entree),
        dateSortie: clos ? C.iso(C.addDays(entree, duree)) : null,
        motif: C.pick(rnd, ['Fièvre persistante depuis cinq jours',
          'Douleurs abdominales intenses', 'Asthénie et pâleur', 'Toux fébrile']),
        anamnese: 'Patient(e) admis(e) pour ' + diag.toLowerCase()
          + '. Début brutal, évolution sur plusieurs jours, automédication préalable sans amélioration.',
        examenPhysique: 'État général altéré. Conjonctives ' + C.pick(rnd, ['pâles', 'normocolorées'])
          + '. Abdomen souple. Auscultation cardio-pulmonaire ' + C.pick(rnd, ['normale', 'crépitants à la base droite']) + '.',
        hypotheses: diag + ' — à confirmer par les examens.',
        traitementEntree: C.pick(rnd, ['Artésunate injectable, réhydratation',
          'Ceftriaxone 1 g/j, antipyrétiques', 'Transfusion de deux culots, fer injectable']),
        examensParacliniques: 'GE-DP, NFS, ionogramme.',
        diagnosticRetenu: diag,
        traitementReajuste: rnd() > 0.5 ? 'Relais per os après apyrexie de 48 heures.' : '',
        evolution: clos ? 'Évolution favorable sous traitement. Apyrexie obtenue à J' + C.between(rnd, 2, 5) + '.'
          : 'Évolution en cours.',
        traitementSortie: clos ? 'Poursuite du traitement per os pendant sept jours.' : '',
        diagnosticSortie: clos ? diag + ' — guérison' : '',
        medecinId: md.id, medecin: md.nomComplet,
      });
    }
    faits.rapports = rap.active().length;

    return faits;
  }

  /* ==========================================================================
   * 4. L'IMAGERIE
   * ======================================================================== */
  function imagerie(rnd) {
    var d = D();
    var IM = d.IMAGERIE || {};
    var col2 = col('resultatsImagerie', { module: 'M2', entite: 'compte rendu d’imagerie', prefix: 'IMG' });
    var realisateur = soignantsQui(function (x) { return x.realiseImagerie; })[0]
      || soignantsQui(function (x) { return x.qualite === 'medecin'; })[0];
    var prescripteurs = soignantsQui(function (x) { return x.prescrit; });
    if (!realisateur || !prescripteurs.length) return 0;

    var INDICATIONS = {
      'IMG-ECHO-PEL': ['Kyste ovarien ?', 'Métrorragies', 'Douleurs pelviennes', 'Bilan d’infertilité'],
      'IMG-ECHO-ABD': ['Douleurs de l’hypochondre droit', 'Ictère', 'Hépatomégalie'],
      'IMG-ECHO-ABP': ['Ascite ?', 'Douleurs abdominales diffuses', 'Bilan d’extension'],
      'IMG-ECHO-PRO': ['RAU', 'Dysurie', 'PSA élevé'],
      'IMG-ECHO-OBS': ['Croissance', 'Terme', 'Vitalité fœtale'],
      'IMG-ECHO-OBS1': ['Terme', 'Métrorragies du premier trimestre', 'Datation'],
      'IMG-ECG': ['Palpitations', 'Douleur thoracique', 'Bilan préopératoire', 'HTA'],
    };

    var n = 0;
    (IM.EXAMENS || []).forEach(function (ex) {
      /* Les modalités ajoutées en vague 61 portent un jeu RÉDUIT : leur
         catalogue est une proposition, et le magasin du navigateur sature
         vite (leçon de la vague 60). Assez pour que chaque tableau montre
         des rendus, des brouillons et ses indicateurs propres. */
      var autreModalite = ex.modalite && ex.modalite !== 'echographie';
      /* Trois examens obstétricaux depuis le 14/09/2026 (dont le 1er trimestre
         évolué) : 12 chacun au lieu de 20, pour ne pas franchir le quota du
         navigateur (vague 62 — un magasin qui déborde ne montre RIEN). */
      var combien = autreModalite ? 3 : (/OBS/.test(ex.code) ? 12 : (ex.code === 'IMG-ECG' ? 14 : 12));
      for (var i = 0; i < combien; i++) {
        var pool = (/OBS/.test(ex.code) || ex.modalite === 'mammographie' || ex.code === 'IMG-IRM-PEL')
          ? patients().filter(function (p) { return p.sexe === 'F'; })
          : patients();
        var p = unDe(rnd, pool);
        var presc = unDe(rnd, prescripteurs);
        if (!p || !presc) break;

        var valeurs = valeursImagerie(rnd, IM, ex.code);

        var rendu = rnd() > 0.18;
        col2.insert({
          reference: 'IMG-' + C.pad(++n, 4),
          date: C.iso(jourOuvre(rnd)) + 'T' + C.pad(C.between(rnd, 8, 17), 2) + ':00:00.000Z',
          examenCode: ex.code, examen: ex.label,
          patientId: p.id, patient: p.nom + ' ' + p.prenom, patientCode: p.code,
          age: C.age(p.dateNaissance),
          indication: C.pick(rnd, INDICATIONS[ex.code] || ['Bilan']),
          ddr: /OBS/.test(ex.code) ? (rnd() > 0.5 ? 'inconnue' : C.dateFR(C.iso(C.addDays(FIN, -C.between(rnd, 60, 250))))) : '—',
          condition: C.pick(rnd, ['Bonne', 'Bonne', 'Bonne', 'Moyenne']),
          prescripteurId: presc.id, prescripteur: presc.nomComplet,
          realisateurId: realisateur.id, realisateur: realisateur.nomComplet,
          valeurs: valeurs,
          annexes: !autreModalite && rnd() > 0.6 ? 'Ovaires normaux. Cul-de-sac de Douglas libre.' : '',
          resultats: autreModalite ? 'Examen réalisé dans de bonnes conditions ; description conforme aux variables.' : undefined,
          recommandation: autreModalite && rnd() > 0.5 ? 'Confronter aux données cliniques ; contrôle selon l’évolution.' : undefined,
          conclusion: conclusionImagerie(rnd, ex.code),
          statut: rendu ? 'rendu' : 'brouillon',
          renduLe: rendu ? C.iso(FIN) : null,
        });
      }
    });
    return n;
  }

  /* Les valeurs d'un compte rendu suivent les variables DÉCLARÉES de l'examen :
     une variable ajoutée demain sera peuplée sans toucher à ce fichier. Hissée
     hors de imagerie() parce que les comptes rendus rattachés aux DEMANDES
     d'imagerie en ont besoin aussi — deux générateurs auraient divergé. */
  function valeursImagerie(rnd, IM, code) {
    var valeurs = {};
    (IM.variablesDe(code) || []).forEach(function (v) {
      if (v.type === 'liste' || v.type === 'binaire') {
        /* On penche vers la normale : un jeu où tout est pathologique
           rendrait la mise en évidence des écarts illisible. */
        valeurs[v.code] = (v.normal && rnd() > 0.22) ? v.normal
          : C.pick(rnd, v.options || [v.normal || '']);
      } else if (v.type === 'multiple') {
        valeurs[v.code] = (v.options || []).filter(function () { return rnd() > 0.5; });
        if (!valeurs[v.code].length && v.options && v.options.length) valeurs[v.code] = [v.options[0]];
      } else if (v.type === 'mesure' && v.unite === '') {
        /* Un index sans unité (cardio-thoracique) est un rapport, pas une longueur. */
        valeurs[v.code] = Number((C.between(rnd, 38, 58) / 100).toFixed(2));
      } else if (v.type === 'mesure') {
        valeurs[v.code] = Number((C.between(rnd, 20, 320) / (v.unite === 'g' ? 3 : 1)).toFixed(1));
      } else if (v.type === 'dimensions') {
        valeurs[v.code + '_a'] = C.between(rnd, 40, 120);
        valeurs[v.code + '_b'] = C.between(rnd, 30, 90);
        valeurs[v.code + '_c'] = C.between(rnd, 25, 70);
      } else if (v.type === 'gestationnel') {
        valeurs[v.code + '_sa'] = C.between(rnd, 6, 40);
        valeurs[v.code + '_j'] = C.between(rnd, 0, 6);
      } else if (v.type === 'texte') {
        valeurs[v.code] = v.normal || 'RAS';
      }
    });
    return valeurs;
  }

  function conclusionImagerie(rnd, code) {
    if (/^IMG-RX-/.test(code)) {
      return C.pick(rnd, ['Examen radiographique sans anomalie décelable.',
        'Pas de lésion osseuse traumatique visible.',
        'Opacité alvéolaire basale droite — foyer infectieux probable à confronter à la clinique.']);
    }
    if (/^IMG-MAM-/.test(code)) {
      return C.pick(rnd, ['Mammographie bilatérale sans anomalie — ACR 1 des deux côtés.',
        'Aspect bénin — ACR 2. Surveillance habituelle.',
        'Opacité du sein gauche d’allure suspecte — ACR 4 : prélèvement conseillé.']);
    }
    if (/^IMG-TDM-/.test(code)) {
      return C.pick(rnd, ['Examen tomodensitométrique sans anomalie significative.',
        'Pas de lésion hémorragique ni de processus expansif.',
        'Lithiase urétérale droite obstructive modérée.']);
    }
    if (/^IMG-IRM-/.test(code)) {
      return C.pick(rnd, ['IRM sans anomalie de signal significative.',
        'Hernie discale L4-L5 postéro-latérale gauche en conflit avec la racine L5.',
        'Fissure horizontale de la corne postérieure du ménisque interne.']);
    }
    if (/OBS1/.test(code)) {
      return 'Grossesse monoembryonnaire intra-utérine évolutive de biométrie correspondante au terme '
        + 'échographique de ' + C.pad(C.between(rnd, 6, 13), 2) + ' SA + '
        + C.pad(C.between(rnd, 0, 6), 2) + ' jours. À contrôler à 22 SA pour étudier la morphologie fœtale.';
    }
    if (/OBS/.test(code)) {
      return 'Grossesse monofœtale intra-utérine évolutive au terme échographique de '
        + C.between(rnd, 22, 39) + ' SA. Morphologie fœtale apparemment normale. '
        + 'Liquide amniotique d’abondance moyenne.';
    }
    if (/PRO/.test(code)) {
      return C.pick(rnd, ['Hypertrophie prostatique bénigne.', 'Prostate de volume normal.',
        'Hypertrophie prostatique hétérogène — avis urologique conseillé.'])
        + ' Reins normaux, sans dilatation des cavités pyélocalicielles.';
    }
    if (/ECG/.test(code)) {
      return C.pick(rnd, ['Tracé sinusal régulier sans anomalie.',
        'Rythme sinusal, trouble de repolarisation en territoire latéral.',
        'Tracé normal pour l’âge.']);
    }
    return C.pick(rnd, ['Examen échographique normal des viscères pleins intra-abdominaux.',
      'Absence d’épanchement liquidien intra-péritonéal.',
      'Utérus de statique antéversée, homogène et non gravide. Ovaires normaux.']);
  }

  /* ==========================================================================
   * 5. L'ACCUEIL — dossiers, références, file d'attente
   * ======================================================================== */
  function accueil(rnd) {
    var d = D();
    var faits = {};
    var recus = personnel().filter(function (a) { return a.fonction === 'accueil'; });
    var soignantsTous = soignants();

    /* --- Dossiers de consultation — FORME DE LA REFONTE ZONE 2 (14/09/2026) --
       Le dossier porte l'anamnèse, les antécédents en trois catégories, les
       données préalables, l'état général coté et l'examen IPPOA en UN objet
       JSON par appareil (`examensPhysiques`). Les constantes de l'accueil y
       sont COPIÉES (`constantesAccueil`) : le médecin a examiné sur elles.
       La décision (diagnostic, prescription) n'est plus au dossier : elle vit
       à la fiche de consultation, dont une partie des dossiers avancés porte
       le lien (`dossierConsultationId` sur la consultation).

       VOLUME MODESTE — 28 dossiers, champs compacts : la leçon de la vague 60 (le magasin du
       navigateur sature) vaut ici, chaque dossier portant un examen complet.
       Un patient n'a qu'UN dossier ouvert à la fois — la fiche ne saurait pas
       lequel récapituler. */
    var dos = col('dossiersConsultation', { module: 'M2', entite: 'dossier de consultation', prefix: 'DOS' });
    var consSeed = col('consultations', { module: 'M2', entite: 'Consultation' });
    var ETATS = ['attente', 'consultation', 'attente_labo', 'cloture'];
    var medecinsDossier = personnel().filter(function (a) { return a.fonction === 'medecin' || a.fonction === 'sage_femme'; });
    var pathoRef = S().collection('pathologies').active();
    var ouverts = {};

    /* Les CAS cliniques : un motif, son histoire, les appareils qu'il fait
       déplier et CE QUE l'examen y trouve. Le reste des appareils examinés est
       « RAS » — c'est ainsi qu'un examen réel se lit : l'anormal ressort. */
    var CAS = [
      { motif: 'Fièvre et céphalées', venue: 'premiere', pathologie: /paludisme/i,
        histoire: 'Fièvre évoluant depuis quatre jours, céphalées frontales, courbatures et frissons vespéraux. Automédication par paracétamol sans amélioration.',
        traitement: 'Paracétamol 500 mg en automédication',
        diagnostic: 'Paludisme simple', eg: 'passable', egPrecision: 'Asthénie fébrile, conjonctives légèrement pâles',
        anomalies: { cardio_vasculaire: { auscultation: 'Tachycardie régulière à 104/min, pas de souffle' },
          hepato_gastro_digestif: { palpation: 'Splénomégalie discrète, abdomen souple' } },
        appareils: ['cardio_vasculaire', 'pleuro_pulmonaire', 'hepato_gastro_digestif', 'neurologie'] },
      { motif: 'Toux productive', venue: 'premiere', pathologie: /bronch|pneumo|respir/i,
        histoire: 'Toux productive depuis une semaine, expectorations jaunâtres, fièvre vespérale, douleur basithoracique droite à la toux.',
        traitement: '', diagnostic: 'Bronchopneumopathie aiguë droite', eg: 'altere', egPrecision: 'Dyspnée d’effort, fébrile',
        anomalies: { pleuro_pulmonaire: { inspection: 'Polypnée à 26/min', percussion: 'Matité de la base droite',
          auscultation: 'Crépitants de la base droite, murmure vésiculaire diminué' } },
        appareils: ['pleuro_pulmonaire', 'cardio_vasculaire', 'orl'] },
      { motif: 'Douleurs épigastriques', venue: 'controle', pathologie: /gastr|ulc/i,
        histoire: 'Épigastralgies post-prandiales à type de brûlure depuis un mois, sans vomissement ni méléna.',
        traitement: 'Hydroxyde d’aluminium à la demande', diagnostic: 'Gastrite aiguë', eg: 'bon',
        anomalies: { hepato_gastro_digestif: { palpation: 'Sensibilité épigastrique à la palpation profonde, pas de défense' } },
        appareils: ['hepato_gastro_digestif', 'cardio_vasculaire'] },
      { motif: 'Consultation prénatale', venue: 'suivi', femme: true, pathologie: /grossesse|anémie/i,
        histoire: 'Grossesse suivie, sans complication à ce jour. Mouvements actifs fœtaux bien perçus. Pas de métrorragie.',
        traitement: 'Fer + acide folique, SP selon calendrier', diagnostic: 'Grossesse évolutive du deuxième trimestre', eg: 'bon',
        anomalies: { gyneco_obstetrique: { inspection: 'Abdomen augmenté de volume, vergetures', palpation: 'Utérus souple, gravide',
          auscultation: 'BDC perçus à 142 bpm', menstruation: 'Aménorrhée gravidique' } },
        appareils: ['gyneco_obstetrique', 'cardio_vasculaire', 'genito_urinaire'], obstetrical: true },
      { motif: 'Brûlures mictionnelles', venue: 'premiere', pathologie: /urin|cystite/i,
        histoire: 'Brûlures mictionnelles et pollakiurie depuis trois jours, sans fièvre.',
        traitement: '', diagnostic: 'Infection urinaire basse', eg: 'bon',
        anomalies: { genito_urinaire: { palpation: 'Sensibilité sus-pubienne, fosses lombaires libres' } },
        appareils: ['genito_urinaire', 'hepato_gastro_digestif'] },
      { motif: 'Plaie de la jambe', venue: 'urgence', pathologie: /plaie|trauma/i,
        histoire: 'Plaie de la jambe gauche par chute de moto il y a deux heures, saignement contrôlé par compression.',
        traitement: '', diagnostic: 'Plaie contuse de la jambe gauche', eg: 'bon',
        anomalies: { locomoteur: { inspection: 'Plaie contuse de 4 cm face antérieure de la jambe gauche', palpation: 'Pas de crépitation osseuse, mobilité conservée' },
          peau_phaneres: { inspection: 'Dermabrasions du genou gauche' } },
        appareils: ['locomoteur', 'peau_phaneres', 'neurologie'] },
      { motif: 'Hypertension — contrôle', venue: 'controle', pathologie: /hypertension/i,
        histoire: 'Hypertendu connu sous traitement, vient pour contrôle. Céphalées occipitales matinales intermittentes.',
        traitement: 'Amlodipine 5 mg/j', diagnostic: 'Hypertension artérielle mal équilibrée', eg: 'bon',
        anomalies: { cardio_vasculaire: { palpation: 'Pouls périphériques bien perçus', auscultation: 'B2 claqué au foyer aortique' } },
        appareils: ['cardio_vasculaire', 'neurologie', 'pleuro_pulmonaire'] },
    ];

    function normal(code) {
      return { inspection: 'RAS', palpation: 'RAS', percussion: 'RAS', auscultation: 'RAS' };
    }

    for (var i = 0; i < 28; i++) {
      var cas = CAS[i % CAS.length];
      var candidats = patients().filter(function (x) { return !ouverts[x.id] && (!cas.femme || x.sexe === 'F'); });
      var p = unDe(rnd, candidats);
      var recu = unDe(rnd, recus);
      if (!p) break;
      /* Les dossiers récents sont en cours, les anciens clôturés : un jeu où
         tout est clôturé ne montrerait jamais la file de consultation. Les
         premiers dossiers couvrent volontairement les quatre états. */
      var recul = i < 8 ? (i % 4 === 0 ? 0 : C.between(rnd, 0, 2)) : reculAleatoire(rnd);
      var etat = i < 8 ? ETATS[i % 4]
        : (recul < 2 ? C.pick(rnd, ['attente', 'consultation', 'attente_labo'])
          : (recul < 8 ? C.pick(rnd, ['consultation', 'attente_labo', 'cloture']) : 'cloture'));
      var dt = jour(rnd, recul);
      var poids = C.between(rnd, 42, 96);
      var taille = C.between(rnd, 148, 188);
      var heure = C.pad(C.between(rnd, 7, 17), 2) + 'h' + C.pad(C.between(rnd, 0, 59), 2);
      var med = unDe(rnd, medecinsDossier);
      var avance = etat !== 'attente';
      if (etat !== 'cloture') ouverts[p.id] = true;

      var fiche = {
        reference: 'DOS-' + C.pad(i + 1, 5),
        patientId: p.id, patient: p.nom + ' ' + p.prenom, patientCode: p.code,
        age: C.age(p.dateNaissance), sexe: p.sexe,
        assureur: p.assureurNom || p.assureur || null,
        dateArrivee: C.iso(dt), heureArrivee: heure,
        typeVenue: cas.venue, motifVenue: cas.motif,
        soignant: med ? med.nomComplet : 'Médecin',
        recuPar: recu ? recu.nomComplet : 'Accueil',
        etat: etat,
        ouvertLe: C.iso(dt) + 'T08:00:00.000Z',
      };
      if (avance) {
        var examens = {};
        cas.appareils.forEach(function (code) {
          if (code === 'gyneco_obstetrique' && p.sexe !== 'F') return;
          examens[code] = Object.assign(normal(code), (cas.anomalies || {})[code] || {});
        });
        Object.assign(fiche, {
          histoire: cas.histoire, traitementEnCours: cas.traitement,
          ant_medicaux: C.pick(rnd, ['Aucun antécédent notable', 'Hypertension artérielle traitée', 'Drépanocytose SC', 'Asthme dans l’enfance', 'Diabète de type 2']),
          ant_chirurgicaux: C.pick(rnd, ['Aucun', 'Appendicectomie en 2018', 'Herniorraphie en 2015', 'Aucun']),
          ant_gyneco_obstetricaux: p.sexe === 'F' ? C.pick(rnd, ['G3 P2 A1, 2 enfants vivants', 'G1 P0, première grossesse', 'Ménarche à 14 ans, cycles réguliers']) : 'Sans objet',
          allergies: rnd() > 0.8 ? 'Arachide' : '',
          allergiesMedicamenteuses: rnd() > 0.88 ? 'Pénicilline (urticaire)' : '',
          statutVaccinal: C.pick(rnd, ['À jour', 'À jour', 'Incomplet', 'Inconnu']),
          groupeSanguin: p.groupeSanguin || C.pick(rnd, ['O+', 'A+', 'B+', 'Inconnu']),
          electrophoreseHb: C.pick(rnd, ['AA', 'AA', 'AS', 'Non faite']),
          etatGeneral: cas.eg, etatGeneralPrecision: cas.egPrecision || '',
          examensPhysiques: examens,
          constantesAccueil: {
            /* Heure LOCALE, sans « Z » : l'heure d'arrivée est une heure de
               Natitingou, pas une heure UTC. */
            dateHeure: C.iso(dt) + 'T' + heure.replace('h', ':') + ':00',
            temperature: Number((36.2 + rnd() * 2.6).toFixed(1)), poids: poids, taille: taille,
            tension: C.between(rnd, 10, 16) + '/' + C.between(rnd, 6, 10), pouls: C.between(rnd, 58, 112),
            spo2: C.between(rnd, 93, 100), imc: Math.round((poids / Math.pow(taille / 100, 2)) * 10) / 10,
          },
          dossierSaisiLe: C.iso(dt) + 'T09:00:00.000Z',
        });
        if (p.sexe === 'F' && (cas.obstetrical || rnd() > 0.6)) {
          var g = C.between(rnd, 1, 5), par = C.between(rnd, 0, g - 1);
          fiche.antecedentsObstetricaux = {
            gestite: g, parite: par, enfantsVivants: par, faussesCouches: g - 1 - par > 0 ? g - 1 - par : 0,
            enfantsDecedes: 0, ageDerniereGrossesse: fiche.age != null ? Math.max(16, fiche.age - C.between(rnd, 0, 4)) : null,
            ddr: C.iso(C.addDays(dt, -C.between(rnd, 60, 200))),
            pathologies: rnd() > 0.75 ? [C.pick(rnd, ['Fausse couche spontanée', 'Œuf clair', 'Grossesse arrêtée'])] : [],
            procreateur: rnd() > 0.7 ? 'Drépanocytose AS connue chez le conjoint' : '',
          };
        }
        if (cas.obstetrical) {
          fiche.examenObstetrical = {
            terme: C.between(rnd, 18, 30) + ' SA', hu: C.between(rnd, 17, 29), bdc: C.between(rnd, 128, 156),
            dosFoetal: C.pick(rnd, ['Dos à gauche', 'Dos à droite']), presentation: 'Céphalique',
            perimetreOmbilical: C.between(rnd, 84, 102), consistanceUterus: 'Souple',
            speculum: 'Col sain, pas de leucorrhée pathologique', tv: 'Col postérieur, long, fermé',
          };
        }
      }
      var ins = dos.insert(fiche).record;

      /* LA FICHE DE CONSULTATION LIÉE — sur les dossiers arrivés au bout
         (attente labo, clôturé), une sur deux : le jeu doit montrer des
         dossiers AVEC leur fiche, sans prétendre que chaque venue ancienne en
         a une (la reprise des consultations antérieures n'en porte pas). */
      if ((etat === 'attente_labo' || etat === 'cloture') && i % 2 === 0) {
        var patho = pathoRef.filter(function (x) { return cas.pathologie.test(x.libelle || ''); })[0] || pathoRef[0];
        var consult = consSeed.insert({
          reference: 'C-DOS-' + C.pad(i + 1, 5),
          patientCode: p.code, patientId: p.id, patient: p.nom + ' ' + p.prenom,
          medecin: fiche.soignant, date: C.iso(dt) + 'T10:00', type: cas.venue === 'urgence' ? 'Urgence' : (cas.venue === 'premiere' ? 'Consultation' : 'Contrôle'),
          statut: 'terminee', motif: cas.motif, diagnostic: cas.diagnostic,
          resumeSyndromique: etat === 'attente_labo' ? 'Syndrome à préciser par les examens complémentaires.' : '',
          pathologies: patho ? [patho.code] : [], pathologiePrincipale: patho ? patho.code : null,
          pathologiesLibelles: patho ? [patho.libelle] : [],
          conduite: etat === 'attente_labo' ? 'Revoir avec les résultats des examens.' : 'Contrôle si persistance des symptômes.',
          orientation: etat === 'attente_labo' ? 'laboratoire' : 'domicile',
          orientationLabel: etat === 'attente_labo' ? 'Laboratoire (en attente des résultats)' : 'Domicile — traitement ambulatoire',
          temperature: fiche.constantesAccueil.temperature, tension: fiche.constantesAccueil.tension,
          poids: fiche.constantesAccueil.poids, fc: fiche.constantesAccueil.pouls,
          tarif: 3000, dossierConsultationId: ins.id, dossierReference: fiche.reference,
        }).record;
        dos.update(ins.id, { derniereFicheId: consult.id, fichesIds: [consult.id], diagnosticRetenu: cas.diagnostic,
          pathologiesRetenues: consult.pathologies, orientation: consult.orientation,
          cloturLe: etat === 'cloture' ? C.iso(dt) + 'T11:00:00.000Z' : null });
      }
    }
    faits.dossiers = dos.active().length;

    /* --- Fiches de référence et contre-références ------------------------ */
    var ref = col('fichesReference', { module: 'M1', entite: 'fiche de référence', prefix: 'REF' });
    var crf = col('contreReferences', { module: 'M1', entite: 'fiche de contre-référence', prefix: 'CRF' });
    var CENTRES = ['CHD Atacora — Natitingou', 'CHU-MEL Cotonou', 'Hôpital de zone de Tanguiéta',
      'CNHU-HKM Cotonou', 'Centre de santé de Perma', 'Hôpital Saint-Jean de Dieu, Tanguiéta'];
    var MOTIFS = ['Absence de médicaments', 'Absence de moyens de diagnostic',
      'Absence de personnel qualifié', 'Pas de réponse au traitement'];
    for (var r = 0; r < 30; r++) {
      var pt = unDe(rnd, patients());
      var ag = unDe(rnd, soignantsTous);
      if (!pt || !ag) break;
      var sortante = rnd() > 0.4;
      var dtr = jourOuvre(rnd);
      var numero = 'REF-' + C.pad(r + 1, 5);
      ref.insert({
        numero: numero,
        sens: sortante ? 'sortante' : 'entrante',
        urgent: rnd() > 0.7,
        patientId: pt.id, patient: pt.nom + ' ' + pt.prenom, patientCode: pt.code,
        age: C.age(pt.dateNaissance), sexe: pt.sexe, adresse: pt.quartier,
        formationSanitaire: sortante ? 'CLINIQUE NASSIERA TOO SARL' : C.pick(rnd, CENTRES),
        centreAlerte: rnd() > 0.4,
        dateAdmission: C.iso(dtr), heureAdmission: C.pad(C.between(rnd, 7, 20), 2) + 'h00',
        pouls: C.between(rnd, 60, 130), temperature: Number((36.5 + rnd() * 3).toFixed(1)),
        tension: C.between(rnd, 8, 16) + '/' + C.between(rnd, 5, 10),
        abordVeineux: rnd() > 0.35,
        contactNom: C.pick(rnd, ['ADAMOU Rachidatou', 'OROU Bio Sanni', 'TCHOBO Marcel', 'KORA Fatima']),
        contactAdresse: pt.quartier + ' — 0' + C.between(rnd, 1, 9) + C.between(rnd, 10000000, 99999999),
        symptomes: C.pick(rnd, ['Détresse respiratoire aiguë', 'Hémorragie du post-partum',
          'Coma fébrile', 'Traumatisme crânien', 'Anémie sévère mal tolérée',
          'Occlusion intestinale', 'Éclampsie']),
        traitements: C.pick(rnd, ['Oxygénothérapie, remplissage', 'Ocytocine, massage utérin',
          'Artésunate IV, antipyrétique', 'Immobilisation, antalgique', 'Transfusion d’un culot']),
        observations: rnd() > 0.6 ? 'Patient stabilisé avant transfert.' : '',
        motifs: [C.pick(rnd, MOTIFS)],
        centreDestination: sortante ? C.pick(rnd, CENTRES) : 'CLINIQUE NASSIERA TOO SARL',
        dateReference: C.iso(dtr), heureReference: C.pad(C.between(rnd, 7, 22), 2) + 'h' + C.pad(C.between(rnd, 0, 59), 2),
        moyen: C.pick(rnd, ['Ambulance', 'Ambulance', 'Taxi', 'Moyen personnel', 'Moto']),
        agentReferent: ag.nomComplet + ' — ' + ag.poste,
        departLe: C.dateFR(C.iso(dtr)) + ' ' + C.pad(C.between(rnd, 7, 22), 2) + 'h00',
        arriveeLe: C.dateFR(C.iso(dtr)) + ' ' + C.pad(C.between(rnd, 8, 23), 2) + 'h30',
        ambulancier: 'TCHANE Nourou',
      });

      /* La contre-référence ne revient pas toujours — et c'est justement
         l'indicateur que la clinique veut suivre. */
      if (sortante && rnd() > 0.45) {
        var concorde = rnd() > 0.25;
        crf.insert({
          reference: 'CRF-' + C.pad(r + 1, 5),
          numeroReference: numero,
          patientId: pt.id, patient: pt.nom + ' ' + pt.prenom, patientCode: pt.code,
          centreAccueil: C.pick(rnd, CENTRES),
          service: C.pick(rnd, ['Réanimation', 'Chirurgie', 'Médecine interne', 'Maternité', 'Pédiatrie']),
          dateArrivee: C.iso(C.addDays(dtr, C.between(rnd, 0, 1))),
          heureArrivee: C.pad(C.between(rnd, 8, 23), 2) + 'h15',
          agentReferent: ag.nomComplet,
          structureProvenance: 'CLINIQUE NASSIERA TOO SARL',
          hospitalise: rnd() > 0.25,
          numeroDossier: 'D' + C.between(rnd, 10000, 99999),
          diagnosticEntree: C.pick(rnd, ['Détresse respiratoire', 'Anémie sévère',
            'Hémorragie du post-partum', 'Traumatisme crânien']),
          diagnosticSortie: C.pick(rnd, ['Pneumopathie sévère', 'Anémie sur paludisme grave',
            'Atonie utérine', 'Contusion cérébrale']),
          concordance: concorde,
          justifiee: concorde || rnd() > 0.3,
          motifNonJustifiee: '',
          evolution: C.pick(rnd, ['Guéri(e)', 'Guéri(e)', 'Guéri(e)', 'Décédé(e)',
            'Référé vers un autre centre', 'Sortie contre avis médical']),
          observations: concorde ? 'Référence pertinente, prise en charge poursuivie.'
            : 'Le diagnostic initial n’a pas été confirmé ; le bilan a orienté autrement.',
          chefService: C.pick(rnd, ['Dr ADJOVI Pascal', 'Dr SOGLO Marie', 'Dr HOUNKPE Jean']),
        });
      }
    }
    faits.references = ref.active().length;
    faits.contreReferences = crf.active().length;

    /* --- La file d'attente du jour --------------------------------------- */
    var file = col('fileAttente', { module: 'M2', entite: 'ticket de file', prefix: 'FIL' });
    var POSTES = [['accueil', 'Accueil'], ['consultation', 'Consultation'], ['caisse', 'Caisse'],
      ['prelevement', 'Salle de prélèvement'], ['pharmacie', 'Pharmacie'], ['salle_soins', 'Salle de soins'],
      ['imagerie', 'Échographie']];
    var PRIORITES = ['ordre_arrivee', 'ordre_arrivee', 'ordre_arrivee', 'rdv', 'urgence', 'urgence_vitale'];
    /* Les praticiens qui reçoivent, dérivés du personnel soignant. */
    var recoivent = soignantsQui(function (x) { return x.prescrit; });

    POSTES.forEach(function (po) {
      var n = C.between(rnd, 0, 6);
      for (var f = 0; f < n; f++) {
        var pt = unDe(rnd, patients());
        if (!pt) break;
        var attente = C.between(rnd, 3, 75);
        var servi = rnd() > 0.55;
        /* Un patient sur trois est adressé NOMMÉMENT — rendez-vous nominatif
           ou suivi en cours. Les deux autres restent en file commune : le
           prochain praticien libre les prend. Tous les nommer donnerait une
           image fausse du couloir. */
        var attendu = (po[0] === 'consultation' && recoivent.length && rnd() > 0.66)
          ? unDe(rnd, recoivent) : null;
        file.insert({
          numero: po[1].slice(0, 1).toUpperCase() + C.pad(f + 1, 3),
          poste: po[0], posteLabel: po[1],
          patientId: pt.id, patient: pt.nom + ' ' + pt.prenom, patientCode: pt.code,
          praticien: attendu ? attendu.nomComplet : null,
          priorite: C.pick(rnd, PRIORITES),
          motif: C.pick(rnd, ['Consultation', 'Retrait de résultat', 'Règlement',
            'Prélèvement', 'Délivrance', 'Pansement', 'Échographie']),
          arriveeLe: C.iso(FIN) + 'T' + C.pad(7 + Math.floor(attente / 12), 2) + ':'
            + C.pad(attente % 60, 2) + ':00.000Z',
          etat: servi ? 'servi' : 'attente',
          serviLe: servi ? C.iso(FIN) + 'T' + C.pad(8 + Math.floor(attente / 12), 2) + ':00:00.000Z' : null,
          appelePar: servi ? 'Accueil' : null,
        });
      }
    });
    faits.file = file.active().length;
    return faits;
  }

  /* Le volet clinique d'un dossier avancé. */
  function dossierClinique(rnd, soignantsTous) {
    var med = soignantsTous.filter(function (x) { return x.prescrit; });
    var s = med.length ? C.pick(rnd, med) : null;
    var o = {
      typeVenue: C.pick(rnd, ['premiere', 'controle', 'suivi', 'urgence']),
      histoire: C.pick(rnd, [
        'Fièvre évoluant depuis quatre jours, associée à des céphalées et des courbatures.',
        'Douleurs épigastriques post-prandiales, sans vomissement.',
        'Grossesse suivie, sans complication jusqu’à ce jour.',
        'Toux productive depuis une semaine, fièvre vespérale.',
      ]),
      traitementEnCours: rnd() > 0.55 ? C.pick(rnd, ['Paracétamol en automédication',
        'Traitement antihypertenseur au long cours', 'Fer et acide folique']) : '',
      ant_medicaux: C.pick(rnd, ['Aucun', 'Hypertension artérielle traitée', 'Drépanocytose SC',
        'Asthme dans l’enfance', 'Diabète de type 2', 'Aucun antécédent notable']),
      ant_chirurgicaux: C.pick(rnd, ['Aucun', 'Appendicectomie en 2018', 'Césarienne en 2022',
        'Herniorraphie en 2015', 'Aucun']),
      ant_gyneco_obstetricaux: C.pick(rnd, ['Sans objet', 'G3 P2 A1, 2 enfants vivants',
        'G1 P0, première grossesse', 'Ménarche à 14 ans, cycles réguliers']),
      exam_inspection: C.pick(rnd, ['État général conservé, conjonctives normocolorées.',
        'Patient asthénique, muqueuses pâles.', 'Bon état général, pas de détresse.']),
      exam_palpation: C.pick(rnd, ['Abdomen souple, dépressible, indolore.',
        'Sensibilité de l’hypochondre droit, pas de défense.',
        'Adénopathies cervicales infracentimétriques.']),
      exam_percussion: C.pick(rnd, ['Sonorité pulmonaire normale.', 'Matité de la base droite.',
        'Tympanisme abdominal conservé.']),
      exam_auscultation: C.pick(rnd, ['Bruits du cœur réguliers, murmure vésiculaire présent.',
        'Quelques crépitants à la base droite.', 'Auscultation sans particularité.']),
      diagnostic: C.pick(rnd, ['Paludisme simple', 'Fièvre typhoïde', 'Gastrite',
        'Grossesse évolutive du deuxième trimestre', 'Bronchite aiguë', 'Anémie ferriprive']),
      analysesDemandees: C.pick(rnd, ['GE-DP, NFS', 'Sérodiagnostic de Widal, NFS',
        'ECBU, glycémie', 'NFS, GS-Rh', 'Aucune']),
      traitement: C.pick(rnd, ['Artéméther-luméfantrine 6 prises, paracétamol',
        'Ciprofloxacine 500 mg x 2/j pendant 7 jours',
        'Oméprazole 20 mg le matin, pansement gastrique',
        'Fer + acide folique, conseils diététiques']),
      conduite: C.pick(rnd, ['Revoir dans une semaine avec les résultats.',
        'Consulter en urgence si aggravation.', 'Contrôle dans un mois.']),
      soignant: s ? s.nomComplet : 'Médecin',
    };
    return o;
  }

  /* ==========================================================================
   * 6. LES PIÈCES CERTIFIANTES
   * ======================================================================== */
  function piecesCertifiantes(rnd) {
    var types = S().collection('typesPiece').active();
    var pieces = col('pieces', { module: 'M1', entite: 'pièce certifiante', prefix: 'PCE' });
    var medecins = parFonction('medecin');
    var d = D();
    if (!types.length || !medecins.length) return 0;

    var CORPS = {
      ATG: 'Je soussigné, Docteur en médecine, certifie avoir examiné ce jour la patiente '
        + 'susnommée et avoir constaté un état de grossesse évolutive.',
      CMNI: 'Je soussigné certifie que l’intéressé(e) ne présente aucune infirmité apparente '
        + 'de nature à le rendre inapte à l’emploi postulé.',
      CMD: 'Je soussigné certifie que le décès est survenu aux date et heure indiquées, '
        + 'de cause naturelle, en l’absence de signe de mort suspecte.',
      CMP: 'Je soussigné certifie avoir examiné l’intéressé(e) et pris connaissance des examens '
        + 'complémentaires. Aucune contre-indication médicale au mariage n’est relevée.',
      CMCBV: 'Je soussigné certifie avoir examiné l’intéressé(e) qui présente les lésions décrites '
        + 'ci-dessus, compatibles avec les faits allégués.',
      CMDPS: 'Je soussigné certifie que l’état de santé de l’intéressé(e) justifie une dispense '
        + 'temporaire des activités physiques et sportives.',
      CMNCI: 'Je soussigné certifie n’avoir constaté ce jour aucune contre-indication à la pratique '
        + 'des activités physiques et sportives.',
      CMVC: 'Je soussigné certifie avoir procédé à la visite médicale de l’intéressé(e).',
      'CMR-H': 'Je soussigné certifie que l’état de santé de l’intéressé(e) nécessite un arrêt '
        + 'de travail à compter de ce jour.',
      CMH: 'Je soussigné certifie que l’intéressé(e) est hospitalisé(e) dans notre établissement '
        + 'et que la présence d’un garde-malade est nécessaire.',
      CMA: 'Je soussigné certifie les faits rapportés ci-dessus, constatés dans notre établissement.',
      SCAM: 'Je soussigné reconnais avoir été informé(e) de mon état de santé et des risques '
        + 'encourus, et demander expressément à quitter l’établissement contre avis médical.',
    };

    var n = 0;
    types.forEach(function (t) {
      var combien = C.between(rnd, 2, 9);
      for (var i = 0; i < combien; i++) {
        var p = unDe(rnd, patients());
        var md = unDe(rnd, medecins);
        if (!p || !md) break;
        var an = FIN.getFullYear();
        n++;
        var tarif = t.tarifCode && d.tarif ? d.tarif(t.tarifCode) : null;
        pieces.insert({
          numero: i + 1, annee: an,
          reference: t.sigle + ' ' + C.pad(i + 1, 3) + '/' + C.pad(i + 1, 3)
            + '/CNT/' + t.direction + '/' + an,
          sigle: t.sigle, libelle: t.libelle, direction: t.direction,
          typeId: t.id,
          patientId: p.id, patient: p.nom + ' ' + p.prenom, patientCode: p.code,
          medecin: md.nomComplet,
          dateDelivrance: C.iso(jourOuvre(rnd)),
          contenu: CORPS[t.sigle] || 'En foi de quoi la présente pièce est établie pour servir et '
            + 'valoir ce que de droit.',
          remisA: rnd() > 0.7 ? C.pick(rnd, ['L’intéressé(e)', 'Le conjoint', 'L’employeur'])
            : 'L’intéressé(e)',
          montant: tarif ? tarif.prixNonAssure : null,
          couverture: tarif && tarif.assurable === 'sos'
            ? 'Couvert par SOS uniquement — toute autre compagnie : à la charge du patient'
            : 'Non couvert par les assurances',
        });
      }
    });
    return n;
  }

  /* ==========================================================================
   * 7. RH, PAIE ET ADMINISTRATION
   * ======================================================================== */
  function ressourcesHumaines(rnd) {
    var faits = {};
    var agents = personnel();

    /* --- Prêts-études et avances ----------------------------------------- */
    var prets = col('pretsEtudes', { module: 'M11', entite: 'prêt-études', prefix: 'PRT' });
    var OBJETS = {
      pret_etudes: ['Licence en soins infirmiers', 'Formation en gestion hospitalière',
        'Diplôme de sage-femme', 'Formation continue en biologie médicale'],
      avance: ['Avance sur salaire — rentrée scolaire', 'Avance sur salaire — dépense familiale',
        'Avance sur salaire — déménagement'],
      pret_social: ['Frais d’obsèques d’un parent', 'Hospitalisation d’un enfant',
        'Réparation du domicile'],
    };
    for (var i = 0; i < 12; i++) {
      var a = unDe(rnd, agents);
      if (!a) break;
      var nature = C.pick(rnd, ['pret_etudes', 'avance', 'pret_social']);
      var montant = C.between(rnd, 3, 30) * 25000;
      var n = C.between(rnd, 3, 12);
      var debut = C.addDays(FIN, -C.between(rnd, 30, 240));
      var mois = debut.getFullYear() + '-' + C.pad(debut.getMonth() + 1, 2);
      /* Les échéances passées sont réputées retenues : sinon aucun prêt ne
         serait jamais en cours de remboursement. */
      var retenues = [];
      var ecoule = Math.min(n, Math.max(0, Math.round((FIN - debut) / 2592000000)));
      for (var k = 0; k < ecoule; k++) {
        var dd = new Date(debut.getFullYear(), debut.getMonth() + k, 1);
        retenues.push(dd.getFullYear() + '-' + C.pad(dd.getMonth() + 1, 2));
      }
      prets.insert({
        reference: 'PRT-' + C.pad(i + 1, 4),
        employeId: a.id, agent: a.nomComplet, matricule: a.matricule,
        nature: nature, objet: C.pick(rnd, OBJETS[nature]),
        montant: montant,
        dateAccord: C.iso(debut),
        premiereEcheance: mois, nbEcheances: n,
        autorisePar: 'TAKI Alimatou',
        retenues: retenues,
      });
    }
    faits.prets = prets.active().length;

    /* --- Événements du personnel et participations ------------------------ */
    var evts = col('evenements', { module: 'M10', entite: 'événement', prefix: 'EVT' });
    var parts = col('participations', { module: 'M10', entite: 'participation', prefix: 'PAR' });
    var NATURES = [['mariage', 'Mariage'], ['naissance', 'Naissance'], ['deces', 'Décès']];
    for (var e = 0; e < 9; e++) {
      var ben = unDe(rnd, agents);
      if (!ben) break;
      var nat = C.pick(rnd, NATURES);
      var dte = C.addDays(FIN, -C.between(rnd, 5, 240));
      var mp = dte.getFullYear() + '-' + C.pad(dte.getMonth() + 1, 2);
      var evt = evts.insert({
        reference: 'EVT-' + C.pad(e + 1, 4),
        nature: nat[0],
        libelle: nat[1] + ' — ' + ben.nomComplet,
        beneficiaireId: ben.id, beneficiaire: ben.nomComplet,
        date: C.iso(dte),
        montantParAgent: 1000,
        periodePaiement: mp,
        modeParDefaut: C.pick(rnd, ['salaire', 'comptant']),
        portee: 'tous',
      }).record;

      /* UNE PARTICIPATION PAR AGENT, HORS BÉNÉFICIAIRE — c'est ce geste unique
         qui fait tenir le module. */
      agents.forEach(function (ag) {
        if (ag.id === ben.id) return;
        var comptant = evt.modeParDefaut === 'comptant' || rnd() > 0.75;
        parts.insert({
          reference: 'PAR-' + C.uid().slice(0, 6),
          evenementId: evt.id, evenementLibelle: evt.libelle,
          agentId: ag.id, agent: ag.nomComplet, matricule: ag.matricule,
          montant: 1000,
          mode: comptant ? 'comptant' : 'salaire',
          periodeRetenue: comptant ? null : mp,
          regle: comptant ? rnd() > 0.2 : rnd() > 0.35,
          dateReglement: comptant ? C.iso(C.addDays(dte, C.between(rnd, 0, 10))) : null,
        });
      });
    }
    faits.evenements = evts.active().length;
    faits.participations = parts.active().length;
    return faits;
  }

  /* ==========================================================================
   * 7 bis. MATERNITÉ — rapport officiel du 27/08/2026
   * --------------------------------------------------------------------------
   * SEMÉE AU SOCLE, et non plus par l'écran m4 : les statistiques (PIL) et le
   * tableau de bord de la sage-femme lisent ces collections — une collection
   * amorcée par son écran affiche un zéro FAUX partout ailleurs (le piège
   * documenté, vague 31). L'ancien amorçage d'écran (seed 509) est repris ici
   * à l'identique puis ENRICHI des variables du rapport : PC/PT, Apgar aux
   * trois temps, vitamine K1, vaccins J0, CPN structurée, CPoN, SONU, PF,
   * PTME, soins curatifs (Case 27), partogrammes.
   * ======================================================================== */
  /* Une valeur d'examen COMPLÉMENTAIRE plausible selon sa nature : un
     groupe sanguin n'a pas la forme d'une glycémie, et « Positif » partout
     ferait une cohorte entière de séropositives. */
  function valeurExamenDossier(rnd, code) {
    if (code === 'gs') return C.pick(rnd, ['O', 'A', 'B', 'AB']);
    if (code === 'rh') return rnd() > 0.08 ? 'Positif' : 'Négatif';
    if (code === 'coombs') return rnd() > 0.05 ? 'Négatif' : 'Positif';
    if (code === 'electrophorese') return C.pick(rnd, ['AA', 'AA', 'AA', 'AS', 'AC']);
    if (code === 'hb') return (9.5 + C.between(rnd, 0, 35) / 10).toFixed(1) + ' g/dl';
    if (code === 'hematocrite') return C.between(rnd, 29, 43) + ' %';
    if (code === 'plaquettes') return C.between(rnd, 150, 380) + ' G/l';
    if (code === 'glycemie') return (0.7 + C.between(rnd, 0, 45) / 100).toFixed(2) + ' g/l';
    if (code === 'gp75') return rnd() > 0.85 ? 'Anormale — avis médical' : 'Normale';
    if (code === 'ecbu') return rnd() > 0.82 ? 'Infection urinaire — E. coli' : 'Stérile';
    if (code === 'hiv1' || code === 'hiv2') return rnd() > 0.97 ? 'Positif' : 'Négatif';
    if (code === 'hepatiteB') return rnd() > 0.93 ? 'Positif' : 'Négatif';
    return rnd() > 0.15 ? 'Négatif' : 'Non fait';
  }

  /* La fiche de surveillance intégrée : les quinze temps des six premières
     heures, puis J1 et J2 — mère et bébé sur la même grille. */
  function surveillanceIntegree(rnd, d2) {
    var releves = [];
    (d2.TEMPS_SURVEILLANCE || []).concat(d2.TEMPS_JOURS || []).forEach(function (t) {
      releves.push({
        temps: t,
        mere: {
          pouls: 68 + C.between(rnd, 0, 28), ta: C.between(rnd, 10, 13) + '/' + C.between(rnd, 6, 8),
          temperature: (36.5 + C.between(rnd, 0, 9) / 10).toFixed(1),
          respiration: C.between(rnd, 16, 22),
          ecoulement: C.pick(rnd, ['Modéré', 'Modéré', 'Minime', 'Abondant']),
          globe: rnd() > 0.08 ? 'Bien formé' : 'Mou — massage utérin',
          psy: C.pick(rnd, ['Calme', 'Calme', 'Fatiguée', 'Anxieuse']),
        },
        bebe: {
          temperature: (36.4 + C.between(rnd, 0, 10) / 10).toFixed(1),
          coloration: rnd() > 0.06 ? 'Rose' : 'Anormale',
          respiration: rnd() > 0.05 ? 'Normale' : 'Difficile',
          cordon: rnd() > 0.96 ? 'Saignement minime' : 'Néant',
          allaitement: rnd() > 0.15 ? 'Régulier' : 'À stimuler',
        },
      });
    });
    return {
      releves: releves,
      actions: (d2.ACTIONS_SURVEILLANCE || []).reduce(function (o, a) {
        o[a] = rnd() > 0.15; return o;
      }, {}),
    };
  }

  /* Les éléments de surveillance du nouveau-né, H4 à H24. */
  function elements24h(rnd, d2, vivant) {
    if (!vivant) return [];
    return (d2.HEURES_NOUVEAU_NE || []).map(function (h) {
      return {
        heure: h,
        temperature: (36.4 + C.between(rnd, 0, 10) / 10).toFixed(1),
        respiration: C.between(rnd, 38, 58),
        coloration: rnd() > 0.07 ? 'Rose' : C.pick(rnd, ['Pâle', 'Cyanose des extrémités']),
        ictere: rnd() > 0.85 ? 'Modéré' : 'Absent',
        neuro: rnd() > 0.05 ? 'Éveillé, tonus normal, réflexes présents' : 'Hypotonique',
        meconium: h === 'H4' ? (rnd() > 0.4 ? 'Oui' : 'Non') : 'Oui',
        urines: h === 'H4' ? (rnd() > 0.5 ? 'Oui' : 'Non') : 'Oui',
        cordon: rnd() > 0.96 ? 'Saignement minime' : 'Néant',
        sein: rnd() > 0.12 ? 'Tète bien' : 'Tète mollement',
      };
    });
  }

  /* La cotation d'Apgar élément par élément, aux trois temps. */
  function apgarDetail(rnd, d2, a5) {
    var apg = (d2.APGAR || { temps: [], elements: [] });
    var detail = {};
    apg.temps.forEach(function (t, it) {
      detail[t] = (apg.elements || []).reduce(function (o, e) {
        /* Un score bas se lit sur les éléments, pas seulement sur le total. */
        var cote = a5 >= 8 ? 2 : (a5 >= 6 ? (rnd() > 0.4 ? 2 : 1) : (rnd() > 0.5 ? 1 : 0));
        if (it > 0) cote = Math.min(2, cote + (rnd() > 0.5 ? 1 : 0));
        o[e.code] = e.cotations[cote];
        return o;
      }, {});
    });
    return detail;
  }

  function maternite() {
    var faits = {};
    var rnd = C.seeded(509);
    var fs = patients().filter(function (p) { return p.sexe === 'F'; });
    var sf = personnel().filter(function (e) { return e.fonction === 'sage_femme' || e.fonction === 'medecin'; })
      .map(function (e) { return e.nomComplet; });
    if (!fs.length || !sf.length) return faits;
    var d2 = D();

    var acc = col('accouchements', { module: 'M4', entite: 'Accouchement' });
    var nais = col('naissances', { module: 'M4', entite: 'Naissance' });
    var suivi = col('suiviMaternite', { module: 'M4', entite: 'SuiviMaternite' });
    var dec = col('deces', { module: 'M4', entite: 'Deces' });

    if (!acc.all().length) {
      for (var i = 0; i < 48; i++) {
        var mere = C.pick(rnd, fs);
        var dt = C.addDays(FIN, -C.between(rnd, 0, 260));
        dt.setHours(C.between(rnd, 0, 23), C.between(rnd, 0, 59));
        var type = C.pick(rnd, ['Eutocique', 'Eutocique', 'Eutocique', 'Dystocique', 'Dirigé', 'Césarienne']);
        var hemo = rnd() > 0.9;
        var vivantAcc = rnd() > 0.02;
        /* LA FICHE DE SURVEILLANCE INTÉGRÉE EST LA FEUILLE DES 48 PREMIÈRES
           HEURES : elle vit dans le dossier des accouchements RÉCENTS. La
           porter sur les 48 accouchements de l’année ferait 900 relevés là où
           la maternité en tient une poignée — et le magasin du navigateur,
           qui est un localStorage, sature avant d’avoir rien montré. */
        var recentAcc = C.daysBetween(dt, FIN) <= 45;
        acc.all().push({
          id: 'ACC' + C.pad(i + 1, 4), statut: 'actif', reference: 'ACC-' + C.pad(i + 1, 4),
          patientId: mere.id, patient: mere.nom + ' ' + mere.prenom, patientCode: mere.code,
          dateHeure: dt.toISOString(),
          type: type,
          voie: type === 'Césarienne' ? 'Césarienne' : 'Voie basse',
          actes: rnd() > 0.7 ? [C.pick(rnd, d2.ACTES_ACCOUCHEMENT)] : [],
          sageFemme: C.pick(rnd, sf),
          duree: C.between(rnd, 2, 18) + ' h',
          complications: rnd() > 0.85 ? C.pick(rnd, ['Hémorragie de la délivrance', 'Souffrance fœtale', 'Dystocie']) : 'Aucune',
          issue: rnd() > 0.03 ? 'Favorable' : 'Défavorable',
          /* LE TROISIÈME FEUILLET : délivrance, placenta, issue. Ce sont
             EXACTEMENT les quatre questions que les indicateurs nationaux
             comptent — les laisser hors du registre obligeait à rouvrir le
             cahier papier pour produire le rapport mensuel. */
          modeDelivrance: C.pick(rnd, d2.MODES_DELIVRANCE),
          gestesDelivrance: d2.GESTES_DELIVRANCE.filter(function () { return rnd() > 0.2; }),
          hemorragie: hemo,
          quantiteSang: hemo ? C.between(rnd, 550, 1400) : C.between(rnd, 120, 420),
          placenta: {
            cotyledons: rnd() > 0.06, cupule: rnd() > 0.88,
            insertionCordon: C.pick(rnd, ['Centrale', 'Para-centrale', 'Marginale']),
            grandCote: C.between(rnd, 17, 23), petitCote: C.between(rnd, 14, 19),
            longueurCordon: C.between(rnd, 45, 65), poidsPlacenta: C.between(rnd, 450, 700),
            faceMaternelle: 'Cotylédons complets, pas de rétention',
            faceFoetale: 'Membranes complètes, insertion appréciée',
          },
          femmeReferee: rnd() > 0.94, femmeDecedee: false,
          nnReference: rnd() > 0.93, nnDecede: !vivantAcc,
          degreMortNe: !vivantAcc ? C.pick(rnd, d2.DEGRES_MORT_NE) : null,
          /* La fiche de surveillance intégrée : mère ET bébé sur la MÊME
             grille de temps — c'est la coïncidence des deux séries qui fait
             la valeur de la feuille unique. */
          surveillance: recentAcc ? surveillanceIntegree(rnd, d2) : null,
        });

        /* Le volet nouveau-né du registre : PC/PT OBLIGATOIRES (Module C),
           Apgar aux trois temps, soins essentiels, vaccins J0. */
        var vivant = vivantAcc;
        var a5 = C.between(rnd, 6, 10);
        nais.all().push({
          id: 'NAI' + C.pad(i + 1, 4), statut: 'actif',
          reference: 'NAI-' + C.pad(i + 1, 4), accouchementId: 'ACC' + C.pad(i + 1, 4),
          dateHeure: dt.toISOString(),
          mere: mere.nom + ' ' + mere.prenom, mereCode: mere.code, mereId: mere.id,
          sexe: rnd() > 0.5 ? 'M' : 'F',
          poids: (2.2 + rnd() * 2.1).toFixed(2),
          taille: C.between(rnd, 44, 54),
          pc: Math.round((32 + rnd() * 6) * 10) / 10,
          pt: Math.round((30 + rnd() * 6) * 10) / 10,
          apgar1: Math.max(3, a5 - C.between(rnd, 0, 2)),
          apgar5: a5,
          apgar10: Math.min(10, a5 + C.between(rnd, 0, 2)),
          reanimation: a5 < 7,
          vitK1: rnd() > 0.05,
          collyre: rnd() > 0.05,
          vpo0: rnd() > 0.12, bcg: rnd() > 0.12, hepB0: rnd() > 0.18,
          vivant: vivant,
          declare: vivant ? rnd() > 0.15 : false,
          /* La cotation d'Apgar élément par élément — le score seul ne dit
             pas CE QUI manquait, et c'est ce que la réanimation vise. */
          apgarDetail: apgarDetail(rnd, d2, a5),
          soinsFiche: (d2.SOINS_NOUVEAU_NE_FICHE || []).reduce(function (o, x) {
            o[x.code] = rnd() > 0.12; return o;
          }, {}),
          /* Les éléments de surveillance des vingt-quatre premières heures. */
          elements24h: recentAcc ? elements24h(rnd, d2, vivant) : [],
        });
      }
    }
    faits.accouchements = acc.active().length;
    faits.naissances = nais.active().length;

    /* --- CPN structurée : la carte maternelle (Module B, tableau 8) -------- */
    var gro = col('grossesses', { module: 'M4', entite: 'grossesse', prefix: 'GRO' });
    if (!gro.all().length) {
      for (var g = 0; g < 18; g++) {
        var f2 = C.pick(rnd, fs);
        var terme = C.between(rnd, 8, 38);
        var doses = d2.DOSES_SP.slice(0, Math.min(5, Math.floor(terme / 7)));
        var visites = [];
        for (var vn = 1; vn <= Math.min(4, Math.ceil(terme / 10)); vn++) {
          /* LA VISITE PORTE TOUTE LA GRILLE, pas quatre chiffres. Le
             formulaire national tient QUARANTE lignes par colonne, et c'est
             ce qui permet de lire une évolution : le poids seul ne dit pas
             si les conseils ont été donnés ni si le TPI a été pris. */
          var poidsV = 52 + C.between(rnd, 0, 30);
          var tailleV = 1.5 + C.between(rnd, 0, 25) / 100;
          var termeV = Math.max(6, terme - (visites.length ? 0 : 0) - (4 - vn) * 8);
          visites.push({
            n: vn, date: C.iso(C.addDays(FIN, -(terme - vn * 8) * 7)),
            /* Venue */
            arrivee: C.pad(C.between(rnd, 7, 11), 2) + 'h' + C.pad(C.between(rnd, 0, 55), 2),
            heureCpnr: C.pad(C.between(rnd, 8, 12), 2) + 'h' + C.pad(C.between(rnd, 0, 55), 2),
            prestataire: C.pick(rnd, sf) + ' — sage-femme d’État',
            terme: termeV + ' SA',
            echographie: vn === 1 ? 'Grossesse mono-fœtale évolutive'
              : C.pick(rnd, ['Non refaite', 'Présentation céphalique, LA normal', 'Croissance harmonieuse']),
            plaintes: C.pick(rnd, ['Aucune', 'Aucune', 'Lombalgies', 'Nausées matinales', 'Brûlures gastriques']),
            /* État général */
            ta: C.between(rnd, 9, 14) + '/' + C.between(rnd, 5, 9),
            pouls: 68 + C.between(rnd, 0, 24),
            temperature: (36.4 + C.between(rnd, 0, 9) / 10).toFixed(1),
            muqueuses: C.pick(rnd, ['Colorées', 'Colorées', 'Légèrement pâles']),
            omi: rnd() > 0.85 ? 'Présents (godet +)' : 'Absents',
            pb: (23 + C.between(rnd, 0, 6)) + ' cm',
            conscience: 'Bonne',
            poids: poidsV,
            imc: Math.round((poidsV / (tailleV * tailleV)) * 10) / 10,
            /* Examens */
            urines: rnd() > 0.88 ? 'A+ / N− / S− / L+' : 'A− / N− / S− / L−',
            albumine: rnd() > 0.9 ? '+' : '—', sucre: rnd() > 0.93 ? '+' : '—',
            seins: C.pick(rnd, ['Souples, mamelons ombiliqués perméables', 'Sans particularité']),
            inspection: C.pick(rnd, ['Abdomen distendu, vergetures', 'Cicatrice de césarienne', 'Sans particularité']),
            hu: 10 + vn * 6 + C.between(rnd, 0, 3),
            presentation: termeV >= 28 ? C.pick(rnd, ['Céphalique', 'Céphalique', 'Céphalique', 'Siège'])
              : 'Non fixée',
            pointsUreteraux: rnd() > 0.9 ? 'Sensibles à droite' : 'Libres',
            bdcf: 120 + C.between(rnd, 0, 40),
            vulve: 'Saine',
            speculum: vn === 1 ? 'Col sain, glaire limpide' : 'Non fait',
            toucherVaginal: vn === 1 ? 'Col long postérieur fermé' : 'Non fait',
            bassin: vn === 1 ? C.pick(rnd, ['Cliniquement normal', 'Cliniquement normal', 'À surveiller']) : 'Non refait',
            /* Prévention */
            sp: terme >= 14 && vn > 1 ? 'SP' + Math.min(5, vn) + ' — 3 cp supervisés' : 'Non due',
            deparasitage: terme >= 14 && vn >= 2 ? rnd() > 0.25 : false,
            fer: rnd() > 0.12, foldine: rnd() > 0.15,
            milda: rnd() > 0.22,
            /* Conseils */
            conseilsNutrition: rnd() > 0.15,
            signesDanger: rnd() > 0.1,
            counselingPF: vn >= 3 ? rnd() > 0.3 : false,
            methodePF: vn >= 3 && rnd() > 0.6 ? C.pick(rnd, ['Implant', 'DIU', 'Injectable']) : '',
            /* Conclusion & suite */
            diagnostic: 'Grossesse de ' + termeV + ' SA évolutive'
              + (rnd() > 0.8 ? ' — anémie modérée' : ''),
            conduite: C.pick(rnd, ['Poursuite du suivi', 'Poursuite du suivi',
              'Fer/Folates renforcés', 'Bilan à refaire à la prochaine venue']),
            rdvCpn: C.iso(C.addDays(FIN, -(terme - (vn + 1) * 8) * 7)),
            rdvClasse: C.pick(rnd, d2.CLASSES_MERES),
            rechercheActive: rnd() > 0.92 ? 'Perdue de vue — relancée par l’ASC' : '',
          });
        }
        gro.all().push({
          id: 'GRO' + C.pad(g + 1, 4), statut: 'actif', reference: 'CPN-' + C.pad(g + 1, 4),
          patientId: f2.id, patient: f2.nom + ' ' + f2.prenom, patientCode: f2.code,
          ddr: C.iso(C.addDays(FIN, -terme * 7)),
          dpa: C.iso(C.addDays(FIN, (40 - terme) * 7)),
          termeSA: terme,
          groupeSanguin: f2.groupeSanguin || C.pick(rnd, ['O+', 'A+', 'B+']),
          sageFemme: C.pick(rnd, sf),
          gar: rnd() > 0.78,
          milda: rnd() > 0.2,
          mebendazole: terme >= 14 ? rnd() > 0.25 : false,
          vat: 'VAT' + C.between(rnd, 1, 5),
          fer: rnd() > 0.15, folates: rnd() > 0.2,
          sp: doses,
          visites: visites,
        });
      }
    }
    faits.grossesses = gro.active().length;

    /* --- CPoN — avec l'hémorragie ANTE-partum, la variable NOUVELLE -------- */
    var cpo = col('cpon', { module: 'M4', entite: 'consultation post-natale', prefix: 'CPO' });
    if (!cpo.all().length) {
      for (var c2 = 0; c2 < 20; c2++) {
        var accRef = C.pick(rnd, acc.active());
        var hAnte = rnd() > 0.85;
        cpo.all().push({
          id: 'CPO' + C.pad(c2 + 1, 4), statut: 'actif', reference: 'CPO-' + C.pad(c2 + 1, 4),
          patientId: accRef.patientId, patient: accRef.patient, patientCode: accRef.patientCode,
          accouchementRef: accRef.reference,
          date: C.iso(C.addDays(C.toDate(accRef.dateHeure), C.between(rnd, 1, 42))),
          type: C.pick(rnd, ['cpon1', 'cpon2', 'cpon3']),
          hemorragieAntePartum: hAnte,
          etiologieAnte: hAnte ? C.pick(rnd, ['Placenta praevia', 'Hématome rétro-placentaire', 'Rupture utérine']) : null,
          hpp: rnd() > 0.9,
          examen: 'TA, T°, utérus, lochies, seins — ' + C.pick(rnd, ['sans particularité', 'involution normale', 'à surveiller']),
          supplementation: rnd() > 0.3 ? 'Vit A + Fer/Folates' : 'Fer/Folates',
          conseilPF: rnd() > 0.4,
          etatNouveauNe: C.pick(rnd, ['Bon état, allaitement établi', 'Ictère modéré à surveiller', 'Cordon propre, poids en hausse']),
          sageFemme: C.pick(rnd, sf),
        });
      }
    }
    faits.cpon = cpo.active().length;

    /* --- Planification familiale — 15 méthodes, codification A/N ----------- */
    var pf = col('planificationFamiliale', { module: 'M4', entite: 'consultation PF', prefix: 'PF' });
    if (!pf.all().length) {
      for (var p3 = 0; p3 < 24; p3++) {
        var cl = C.pick(rnd, fs);
        var meth = C.pick(rnd, d2.METHODES_PF);
        pf.all().push({
          id: 'PF' + C.pad(p3 + 1, 4), statut: 'actif', reference: 'PF-' + C.pad(p3 + 1, 4),
          date: C.iso(jourOuvre(rnd)),
          patientId: cl.id, patient: cl.nom + ' ' + cl.prenom, patientCode: cl.code,
          acceptante: rnd() > 0.45 ? 'A' : 'N',
          methode: meth.code, methodeLabel: meth.label,
          methodeAnterieure: rnd() > 0.6 ? C.pick(rnd, d2.METHODES_PF).label : null,
          ddr: C.iso(C.addDays(FIN, -C.between(rnd, 5, 40))),
          constantes: C.between(rnd, 50, 90) + ' kg · ' + C.between(rnd, 9, 14) + '/' + C.between(rnd, 5, 9),
          rdv: C.iso(C.addDays(FIN, C.between(rnd, 20, 120))),
          sageFemme: C.pick(rnd, sf),
        });
      }
    }
    faits.pf = pf.active().length;

    /* --- Registre SONUB / SONUC -------------------------------------------- */
    var sonu = col('registreSONU', { module: 'M4', entite: 'urgence obstétricale', prefix: 'SNU' });
    if (!sonu.all().length) {
      for (var s3 = 0; s3 < 10; s3++) {
        var pu = C.pick(rnd, fs);
        var du = jourOuvre(rnd); du.setHours(C.between(rnd, 0, 23), C.between(rnd, 0, 59));
        var nf = C.between(rnd, 1, 3);
        var fonctions = [];
        while (fonctions.length < nf) {
          var num = C.between(rnd, 1, 10);
          if (fonctions.indexOf(num) === -1) fonctions.push(num);
        }
        sonu.all().push({
          id: 'SNU' + C.pad(s3 + 1, 4), statut: 'actif', reference: 'SONU-' + C.pad(s3 + 1, 4),
          dateHeure: du.toISOString(),
          patientId: pu.id, patient: pu.nom + ' ' + pu.prenom, patientCode: pu.code,
          gestite: C.between(rnd, 1, 7), parite: C.between(rnd, 0, 6),
          evacuation: rnd() > 0.6,
          provenance: rnd() > 0.6 ? C.pick(rnd, ['CS de Perma', 'CS de Kouandé', 'CS de Boukoumbé']) : 'Venue d’elle-même',
          diagnosticEvacuation: rnd() > 0.5 ? C.pick(rnd, ['Travail prolongé', 'Pré-éclampsie', 'Hémorragie']) : null,
          heureAbordVeineux: C.pad(du.getHours()) + 'h' + C.pad((du.getMinutes() + 12) % 60),
          fonctions: fonctions.sort(function (a, b) { return a - b; }),
          autreGeste: rnd() > 0.8 ? 'Oxygénothérapie au masque' : null,
          heureFinGestes: C.pad((du.getHours() + 2) % 24) + 'h' + C.pad(du.getMinutes()),
          evolution: C.pick(rnd, ['Favorable', 'Favorable', 'Favorable', 'Référée', 'Décédée']),
          agent: C.pick(rnd, sf),
        });
      }
    }
    faits.sonu = sonu.active().length;

    /* --- PTME — quadripartite, données SENSIBLES --------------------------- */
    var ptme = col('ptme', { module: 'M4', entite: 'fiche PTME', prefix: 'PTM' });
    if (!ptme.all().length) {
      for (var t2 = 0; t2 < 6; t2++) {
        var fp = C.pick(rnd, fs);
        var dispensations = [];
        for (var mm = 0; mm < C.between(rnd, 2, 8); mm++) {
          dispensations.push({ mois: C.iso(C.addDays(FIN, -mm * 30)).slice(0, 7), servie: rnd() > 0.15 });
        }
        ptme.all().push({
          id: 'PTM' + C.pad(t2 + 1, 4), statut: 'actif', reference: 'PTME-' + C.pad(t2 + 1, 4),
          patientId: fp.id, patient: fp.nom + ' ' + fp.prenom, patientCode: fp.code,
          /* Volet 1 — dépistage triple. */
          vihTrimestre: C.between(rnd, 1, 3), vihType: C.pick(rnd, ['VIH-1', 'VIH-2', 'VIH-1+2']),
          agHbs: rnd() > 0.85 ? 'Positif' : 'Négatif',
          syphilis: rnd() > 0.9 ? 'Positif' : 'Négatif',
          chargeVirale: rnd() > 0.5 ? 'Indétectable' : C.between(rnd, 50, 5000) + ' copies/ml',
          /* Volet 2 — mère. */
          protocoleARV: 'TDF + 3TC + DTG',
          dureeARV: C.pick(rnd, d2.PTME.dureesARV),
          allaitement: C.pick(rnd, d2.PTME.allaitements),
          prophylaxieNN: C.pick(rnd, d2.PTME.prophylaxiesNN).code,
          /* Volet 3 — enfant exposé. */
          pcrNaissance: rnd() > 0.3 ? 'Négatif' : 'En attente',
          pcr1: rnd() > 0.5 ? 'Négatif' : null,
          pcr2: rnd() > 0.75 ? 'Négatif' : null,
          serologie18m: null,
          ctm: rnd() > 0.2, hepBJ0: rnd() > 0.2,
          /* Volet 4. */
          dispensations: dispensations,
        });
      }
    }
    faits.ptme = ptme.active().length;

    /* --- Soins curatifs & urgences maternité — Case 27 restructurée -------- */
    var cur = col('soinsCuratifsMaternite', { module: 'M4', entite: 'soin curatif maternité', prefix: 'SCM' });
    if (!cur.all().length) {
      for (var u2 = 0; u2 < 16; u2++) {
        var pc2 = C.pick(rnd, fs);
        var hospitalisee = rnd() > 0.7;
        cur.all().push({
          id: 'SCM' + C.pad(u2 + 1, 4), statut: 'actif', reference: 'SCM-' + C.pad(u2 + 1, 4),
          date: C.iso(jourOuvre(rnd)),
          patientId: pc2.id, patient: pc2.nom + ' ' + pc2.prenom, patientCode: pc2.code,
          trancheAge: C.pick(rnd, d2.TRANCHES_AGE_CURATIF.slice(5)),
          symptomes: C.pick(rnd, ['Fièvre et céphalées', 'Douleurs pelviennes', 'Toux depuis 5 jours', 'Métrorragies']),
          diagnostic: C.pick(rnd, ['Paludisme simple', 'Infection urinaire', 'Anémie', 'Menace d’accouchement prématuré']),
          traitement: C.pick(rnd, ['CTA 3 jours', 'Antibiothérapie', 'Fer + folates', 'Tocolyse et repos']),
          mildaDelivree: rnd() > 0.55,
          urgenceMaternite: rnd() > 0.75 ? C.pick(rnd, d2.URGENCES_MATERNITE).code : null,
          femmeObservee: rnd() > 0.55,
          femmeHospitalisee: hospitalisee,
          joursHospitalisation: hospitalisee ? C.between(rnd, 1, 9) : null,
          agent: C.pick(rnd, sf),
        });
      }
    }
    faits.soinsCuratifs = cur.active().length;

    /* --- Partogrammes — travail en cours ou récent ------------------------- */
    var par = col('partogrammes', { module: 'M4', entite: 'partogramme', prefix: 'PAR' });
    if (!par.all().length) {
      for (var w = 0; w < 6; w++) {
        var fw = C.pick(rnd, fs);
        var debut = C.addDays(FIN, -C.between(rnd, 0, 20));
        debut.setHours(C.between(rnd, 4, 20), 0, 0, 0);
        var mesures = [];
        var dil = 4;
        for (var h = 0; h <= C.between(rnd, 3, 8); h++) {
          dil = Math.min(10, dil + (rnd() > 0.35 ? 1 : 0));
          mesures.push({
            heure: h,
            dilatation: dil,
            descente: Math.max(0, 5 - Math.floor(h / 2)),
            bdf: 120 + C.between(rnd, 0, 40),
            contractions: Math.min(5, 2 + Math.floor(h / 2)),
            ta: C.between(rnd, 10, 14) + '/' + C.between(rnd, 6, 9),
            pouls: 70 + C.between(rnd, 0, 30),
            liquide: C.pick(rnd, ['I', 'C', 'C', 'C', 'M']),
            /* Les trois cotations de la légende : chevauchement des os du
               crâne, descente en travers de doigts, durée des contractions. */
            chevauchement: rnd() > 0.8 ? C.between(rnd, 1, 2) : 0,
            descenteCotee: Math.max(1, 5 - Math.floor(h / 2)) + '/5',
            dureeContractions: h < 2 ? 'courte' : (h < 4 ? 'moyenne' : 'longue'),
            ocytocine: h >= 3 && rnd() > 0.6 ? C.between(rnd, 5, 15) + ' gttes/mn' : '',
            temperature: (36.5 + C.between(rnd, 0, 8) / 10).toFixed(1),
            urines: rnd() > 0.7 ? 'A− S−' : '',
          });
          if (dil >= 10) break;
        }
        par.all().push({
          id: 'PAR' + C.pad(w + 1, 4), statut: 'actif', reference: 'PARTO-' + C.pad(w + 1, 4),
          patientId: fw.id, patient: fw.nom + ' ' + fw.prenom, patientCode: fw.code,
          gestite: C.between(rnd, 1, 6), parite: C.between(rnd, 0, 5),
          debut: debut.toISOString(),
          accoucheur: C.pick(rnd, sf),
          mesures: mesures,
          rupture: C.addDays(debut, 0).toISOString(),
          dilatationFinale: mesures[mesures.length - 1].dilatation,
          issue: mesures[mesures.length - 1].dilatation >= 10 ? 'Accouchement par voie basse'
            : 'Travail en cours',
          clos: mesures[mesures.length - 1].dilatation >= 10,
          resume: mesures[mesures.length - 1].dilatation >= 10 ? 'Dilatation complète — expulsion' : null,
        });
      }
    }
    faits.partogrammes = par.active().length;

    /* --- LE DOSSIER OBSTÉTRICAL — le cahier qui tient les autres ----------
     * Semé AU SOCLE, comme le reste de la maternité : le tableau de bord de
     * la maternité et les statistiques du Pilotage le lisent, et une
     * collection amorcée par son écran affiche un zéro FAUX partout ailleurs.
     * Un dossier est ouvert pour CHAQUE femme suivie en CPN et pour chaque
     * accouchée — c'est ainsi que le cahier existe dans la maternité.
     * ------------------------------------------------------------------- */
    var dob = col('dossiersObstetricaux', { module: 'M4', entite: 'dossier obstétrical', prefix: 'DOB' });
    if (!dob.all().length) {
      var vues = {};
      var candidates = gro.active().map(function (g) { return { p: g, acc: null }; })
        .concat(acc.active().slice(0, 14).map(function (a) { return { p: a, acc: a }; }));
      var nDob = 0;
      candidates.forEach(function (c) {
        if (vues[c.p.patientCode]) return;
        vues[c.p.patientCode] = true;
        nDob++;
        var mereD = fs.filter(function (x) { return x.code === c.p.patientCode; })[0];
        if (!mereD) return;
        var ddrD = c.p.ddr || C.iso(C.addDays(FIN, -C.between(rnd, 60, 270)));
        var ageD = C.age(mereD.dateNaissance) || C.between(rnd, 17, 41);
        var tailleD = Math.round((1.48 + C.between(rnd, 0, 24) / 100) * 100) / 100;
        var pariteD = C.between(rnd, 0, 7);
        /* Les facteurs de surveillance ne sont pas tirés au hasard : ils se
           DÉDUISENT de ce que le dossier porte déjà (âge, taille, parité).
           Les inventer à côté des données ferait deux vérités. */
        var fact = {};
        if (ageD < 16) fact.age_min = true;
        if (ageD > 35) fact.age_max = true;
        if (tailleD < 1.5) fact.taille = true;
        if (pariteD > 6) fact.parite = true;
        if (rnd() > 0.9) fact.cesarienne = true;
        if (rnd() > 0.94) fact.drepano = true;
        if (rnd() > 0.92) fact.hta = true;
        if (rnd() > 0.95) fact.fausses_couches = true;
        var accouchee = !!c.acc;
        dob.all().push({
          id: 'DOB' + C.pad(nDob, 4), statut: 'actif',
          numeroDossier: C.pad(nDob, 5) + '/' + String(FIN.getFullYear()).slice(-2),
          dateEntree: C.iso(C.addDays(C.toDate(ddrD), C.between(rnd, 56, 110))),
          patientId: mereD.id, patient: mereD.nom + ' ' + mereD.prenom, patientCode: mereD.code,
          age: ageD, taille: tailleD,
          profession: C.pick(rnd, ['Ménagère', 'Commerçante', 'Couturière', 'Cultivatrice',
            'Enseignante', 'Coiffeuse', 'Élève', 'Aide-soignante']),
          nationalite: 'Béninoise',
          quartier: mereD.quartier || C.pick(rnd, ['Peporiyakou', 'Kantaborifa', 'Tchoumi-Tchoumi', 'Yimporima']),
          telephone: mereD.telephone || '',
          personneContact: C.pick(rnd, ['Le conjoint', 'La mère', 'La sœur aînée', 'La belle-mère']),
          telephoneContact: '97' + C.between(rnd, 100000, 999999),
          referee: rnd() > 0.82,
          refereePar: rnd() > 0.82 ? C.pick(rnd, ['Centre de santé de Perma', 'Maternité de Kouandé',
            'Centre de santé de Tanguiéta']) : '',
          procreateurNom: C.pick(rnd, ['B. Idrissou', 'K. Salifou', 'T. Moussa', 'N. Bio', 'D. Yacoubou']),
          procreateurProfession: C.pick(rnd, ['Cultivateur', 'Conducteur de taxi-moto', 'Commerçant',
            'Enseignant', 'Maçon']),
          procreateurGs: C.pick(rnd, ['O+', 'A+', 'B+', 'AB+', 'O−']),
          procreateurSerologie: rnd() > 0.1 ? 'Négative' : 'Non faite',
          maladies: rnd() > 0.75 ? C.pick(rnd, ['Paludisme à répétition', 'Appendicectomie en 2019',
            'HTA sous traitement', 'Asthme']) : 'Néant',
          traitements: rnd() > 0.8 ? 'Fer + Acide folique' : 'Néant',
          allergies: rnd() > 0.9 ? 'Sulfamides' : 'Non connues',
          gestite: pariteD + C.between(rnd, 1, 2), parite: pariteD,
          avortements: rnd() > 0.75 ? C.between(rnd, 1, 2) : 0,
          enfantsVivants: Math.max(0, pariteD - (rnd() > 0.85 ? 1 : 0)),
          enfantsDecedes: rnd() > 0.85 ? 1 : 0,
          transfusions: rnd() > 0.92 ? 1 : 0,
          ddr: ddrD, dpa: C.iso(C.addDays(C.toDate(ddrD), 280)),
          facteurs: fact,
          examens: (d2.EXAMENS_DOSSIER || []).reduce(function (o, x) {
            o[x.code] = valeurExamenDossier(rnd, x.code);
            return o;
          }, {}),
          vat: ['VAT1', 'VAT2', 'VAT3', 'VAT4', 'VAT5'].reduce(function (o, v, iv) {
            if (iv < C.between(rnd, 2, 5)) o[v] = C.iso(C.addDays(C.toDate(ddrD), 60 + iv * 30));
            return o;
          }, {}),
          droits: (d2.DROITS_FONDAMENTAUX || []).reduce(function (o, x, ix) {
            o[ix] = rnd() > 0.15; return o;
          }, {}),
          plan: (d2.PLAN_ACCOUCHEMENT || []).reduce(function (o, x, ix) {
            o[ix] = rnd() > 0.25; return o;
          }, {}),
          classesMeres: [C.pick(rnd, d2.CLASSES_MERES)],
          infoPF: rnd() > 0.4 ? 'Counseling fait — méthode à confirmer après la CPoN' : '',
          referenceCPN: '', referenceAccouchement: rnd() > 0.9 ? 'CHD Atacora — si césarienne' : '',
          sageFemme: C.pick(rnd, sf),
          statutDossier: accouchee ? 'accouchee' : 'suivi',
        });
      });
    }
    faits.dossiersObstetricaux = dob.active().length;

    /* --- Décès (repris de l'ancien amorçage d'écran) ----------------------- */
    if (!dec.all().length) {
      for (var k = 0; k < 14; k++) {
        var pd = unDe(rnd, patients());
        var dd = C.addDays(FIN, -C.between(rnd, 0, 260));
        dd.setHours(C.between(rnd, 0, 23), C.between(rnd, 0, 59));
        dec.all().push({
          id: 'DEC' + C.pad(k + 1, 4), statut: 'actif',
          reference: 'DEC-' + C.pad(k + 1, 4),
          patientId: pd.id, patient: pd.nom + ' ' + pd.prenom, patientCode: pd.code,
          dateHeure: dd.toISOString(),
          cause: C.pick(rnd, ['Paludisme grave', 'Insuffisance rénale aiguë', 'Accident vasculaire cérébral',
            'Détresse respiratoire', 'Choc septique', 'Cause naturelle — grand âge']),
          lieu: C.pick(rnd, ['Hospitalisation', 'Urgences', 'Bloc opératoire', 'Maternité']),
          medecin: C.pick(rnd, sf),
          declare: rnd() > 0.2,
        });
      }
    }
    faits.deces = dec.active().length;

    /* --- Suivi maternité (l'écran historique) — conservé ------------------- */
    if (!suivi.all().length) {
      for (var j = 0; j < 26; j++) {
        var f3 = C.pick(rnd, fs);
        var t3 = C.between(rnd, 6, 40);
        suivi.all().push({
          id: 'MAT' + C.pad(j + 1, 4), statut: 'actif',
          patientId: f3.id, patient: f3.nom + ' ' + f3.prenom, patientCode: f3.code,
          dpa: C.iso(C.addDays(FIN, (40 - t3) * 7)),
          termeSA: t3,
          poids: 50 + C.between(rnd, 0, 35),
          cpn: C.between(rnd, 1, 4),
          groupeSanguin: f3.groupeSanguin,
          risque: rnd() > 0.78 ? 'Élevé' : 'Standard',
          sageFemme: C.pick(rnd, sf),
          observations: C.pick(rnd, ['Grossesse évolutive normale', 'Anémie modérée', 'HTA gravidique à surveiller', 'Diabète gestationnel']),
        });
      }
    }
    faits.suivis = suivi.active().length;

    return faits;
  }

  /* ==========================================================================
   * 8. ADMINISTRATION — courriers, ambulance, GED
   * ======================================================================== */
  function administration(rnd) {
    var faits = {};

    /* --- Interventions d'ambulance ----------------------------------------
       LA FORME EST CELLE QUE L'ÉCRAN LIT (m13-ambulance) : dateHeure,
       kilometrage, tarif, facture — plus l'etat que le tableau de bord
       consomme. Deux seeds aux formes divergentes ont coexisté ici : celui-ci
       écrivait date/distance/montant pendant que l'écran lisait dateHeure/
       kilometrage/tarif — toutes ses colonnes affichaient des tirets. */
    var amb = col('ambulance', { module: 'M13', entite: 'InterventionAmbulance' });
    if (!amb.all().length) {
      var DEST = ['CHD Atacora — Natitingou', 'Hôpital de zone de Tanguiéta',
        'Domicile — quartier Tchirimina', 'CNHU-HKM Cotonou', 'Centre de santé de Perma'];
      for (var i = 0; i < 38; i++) {
        var p = unDe(rnd, patients());
        if (!p) break;
        var dt = jourOuvre(rnd);
        dt.setHours(C.between(rnd, 0, 23), C.between(rnd, 0, 59), 0, 0);
        var recent = C.daysBetween(dt, FIN) < 2;
        var km = C.between(rnd, 3, 320);
        var etatAmb = recent ? C.pick(rnd, ['demandee', 'en_cours', 'terminee']) : 'terminee';
        amb.insert({
          reference: 'AM-2026-' + C.pad(i + 1, 4),
          dateHeure: dt.toISOString(),
          patientId: p.id, patient: p.nom + ' ' + p.prenom, patientCode: p.code,
          motif: C.pick(rnd, ['Transfert vers structure de référence', 'Ramassage à domicile',
            'Retour à domicile', 'Évacuation sanitaire', 'Transport post-opératoire']),
          destination: C.pick(rnd, DEST),
          kilometrage: km,
          chauffeur: 'TCHANE Nourou',
          accompagnant: C.pick(rnd, ['Infirmier de garde', 'Sage-femme', 'Aide-soignante', '—']),
          etat: etatAmb,
          tarif: 5000 + km * 500,
          facture: etatAmb === 'terminee' ? rnd() > 0.2 : false,
          statut: 'actif',
        });
      }
    }
    faits.ambulance = amb.active().length;

    /* --- Courriers ---------------------------------------------------------
       Même règle : la forme est celle de l'écran m13-courriers — traitement
       tri-état (en_attente / en_cours / traite), nature, service destinataire,
       numérisation. Le booléen « traite » d'autrefois n'était lu par personne
       et laissait la colonne Traitement muette. */
    var cour = col('courriers', { module: 'M13', entite: 'Courrier' });
    if (!cour.all().length) {
      var OBJETS = [
        ['arrivee', 'Convocation à la réunion de la zone sanitaire', 'Zone Sanitaire de Natitingou'],
        ['arrivee', 'Demande de statistiques mensuelles', 'DDS Atacora-Donga'],
        ['arrivee', 'Relance de règlement de créances', 'NSIA ASSURANCE'],
        ['arrivee', 'Notification de contrôle fiscal', 'DGI — Centre des impôts'],
        ['depart', 'Transmission des statistiques du mois', 'Zone Sanitaire de Natitingou'],
        ['depart', 'Demande de convention de partenariat', 'AFRICAINE DES ASSURANCES'],
        ['depart', 'Relevé et facture mensuelle', 'SUNU ASSURANCES'],
        ['depart', 'Réponse à la demande de renseignements', 'DDS Atacora-Donga'],
        ['arrivee', 'Offre commerciale — réactifs de laboratoire', 'SoBAPS SA'],
        ['depart', 'Bon de commande de médicaments', 'SoBAPS SA'],
      ];
      var NATURES_COURRIER = ['Lettre', 'Courriel', 'Note', 'Facture', 'Convocation'];
      var SERVICES_COURRIER = ['Direction Médicale', 'Direction Administrative', 'Comptabilité',
        'Ressources humaines', 'Gestion des stocks'];
      for (var c = 0; c < 34; c++) {
        var o = C.pick(rnd, OBJETS);
        var dtc = jourOuvre(rnd);
        cour.insert({
          reference: (o[0] === 'arrivee' ? 'ARR-' : 'DEP-') + '2026-' + C.pad(c + 1, 4),
          sens: o[0], objet: o[1], correspondant: o[2],
          date: C.iso(dtc),
          nature: C.pick(rnd, NATURES_COURRIER),
          affecteA: C.pick(rnd, SERVICES_COURRIER),
          traitement: C.daysBetween(dtc, FIN) > 6 ? 'traite' : C.pick(rnd, ['en_attente', 'en_cours', 'traite']),
          accuseReception: rnd() > 0.4,
          numerise: rnd() > 0.25,
          statut: 'actif',
        });
      }
    }
    faits.courriers = cour.active().length;

    /* --- Réunions -----------------------------------------------------------
       Amorcées ICI et non par l'écran m13-reunions : le tableau de bord de
       l'agent administratif et le tiroir des consultations les lisent aussi —
       une page ne charge que le module de son écran. */
    var reun = col('reunions', { module: 'M13', entite: 'Reunion' });
    if (!reun.all().length) {
      var rndR = C.seeded(2617);
      var TYPES_REUNION = ['Réunion de direction', 'Réunion de service', 'Comité d’hygiène',
        'Revue mensuelle d’activité', 'Réunion du personnel', 'Comité de gestion des stocks'];
      for (var r = 0; r < 18; r++) {
        var dr = C.addDays(FIN, C.between(rndR, -120, 30));
        reun.all().push({
          id: 'REU' + C.pad(r + 1, 4), statut: 'actif',
          reference: 'RU-2026-' + C.pad(r + 1, 3),
          date: C.iso(dr), heure: C.pad(C.between(rndR, 8, 16)) + ':00',
          type: C.pick(rndR, TYPES_REUNION),
          lieu: C.pick(rndR, ['Salle de réunion', 'Bureau de la Direction', 'Salle de garde']),
          president: C.pick(rndR, ['BASSONGUI Chabi Séko', 'TAKI Alimatou']),
          participants: C.between(rndR, 4, 22),
          ordreDuJour: C.pick(rndR, [
            'Point sur l’activité du mois ; situation des stocks ; questions diverses',
            'Suivi des créances assurances ; recouvrement ; plan d’action',
            'Hygiène et sécurité des patients ; protocole de désinfection',
            'Présentation du projet de digitalisation ; calendrier de déploiement',
          ]),
          compteRendu: dr < FIN,
        });
      }
    }
    faits.reunions = reun.active().length;

    /* --- Bibliothèque documentaire (GED) ------------------------------------
       Amorcée ICI et non par ged.js : le tableau de bord de l'agent
       administratif compte les documents à valider, et un compteur qui lit une
       collection vide affiche un zéro FAUX — pas un zéro vide. */
    var docs = col('documents', { module: 'GED', entite: 'Document' });
    if (!docs.all().length) {
      var rndG = C.seeded(3019);
      var patsG = patients();
      var empsG = personnel();
      for (var g = 0; g < 220; g++) {
        var cat = C.pick(rndG, D().GED_CATEGORIES);
        var rattache, codeR;
        if (cat.rattachement === 'Patient') {
          var pg = C.pick(rndG, patsG); rattache = pg.nom + ' ' + pg.prenom; codeR = pg.code;
        } else if (cat.rattachement === 'Employé') {
          var eg = C.pick(rndG, empsG); rattache = eg.nomComplet; codeR = 'MAT-' + eg.matricule;
        } else if (cat.rattachement === 'Fournisseur') {
          var fg = C.pick(rndG, D().FOURNISSEURS); rattache = fg.nom; codeR = fg.code;
        } else {
          rattache = 'Administration générale'; codeR = 'ADM';
        }
        docs.all().push({
          id: 'GED' + C.pad(g + 1, 5), statut: 'actif',
          reference: 'DOC-2026-' + C.pad(g + 1, 5),
          categorie: cat.id, rattachement: cat.rattachement,
          rattacheA: rattache, codeRattachement: codeR,
          libelle: cat.label.replace(/s$/, '') + ' — ' + rattache,
          date: C.iso(C.addDays(FIN, -C.between(rndG, 0, 500))),
          taille: C.between(rndG, 60, 4800),
          format: C.pick(rndG, ['PDF', 'PDF', 'PDF', 'JPEG', 'DOCX', 'XLSX']),
          version: C.between(rndG, 1, 3),
          etatValidation: C.pick(rndG, ['valide', 'valide', 'valide', 'en_attente', 'rejete']),
          signe: rndG() > 0.55,
          archive: rndG() > 0.7,
          deposePar: C.pick(rndG, empsG).nomComplet,
          consultations: C.between(rndG, 0, 45),
          conservation: cat.rattachement === 'Patient' ? 20 : (cat.rattachement === 'Employé' ? 10 : 5),
        });
      }
    }
    faits.documents = docs.active().length;

    /* Les événements de l'ÉTABLISSEMENT ne sont pas peuplés ici : l'écran de
       M13 les amorce lui-même, avec la forme qu'attend son formulaire
       (catégorie, heure, responsable, canaux). Les créer en double produisait
       des fiches incomplètes que la modification refusait d'enregistrer. */

    return faits;
  }

  /* ==========================================================================
   * 9. LES NOTIFICATIONS DE POSTE
   * --------------------------------------------------------------------------
   * Elles s'adressent à un POSTE et non à une personne : le prescripteur peut
   * être en congé, c'est le service qui doit voir passer l'information.
   * ======================================================================== */
  function notifications(rnd) {
    var pr = PR();
    var notif = S().collection('notifications');
    if (notif.active().length > 12) return notif.active().length;

    var demandes = S().collection('demandesAnalyses').active();
    var factures = S().collection('factures').active();
    var produits = S().collection('produits').active()
      .filter(function (p) { return p.seuilAlerte != null && p.stock <= p.seuilAlerte; });

    var MODELES = [
      { poste: 'consultation', type: 'resultat_rendu', priorite: 'normale',
        libelle: function (d) { return 'Résultat rendu — ' + d.patient; },
        detail: function (d) { return d.analyse + ' — validé biologiquement, consultable au dossier'; },
        /* On interroge le référentiel plutôt que de comparer une chaîne : un
           état ajouté demain sera pris en compte sans toucher à ce fichier. */
        source: demandes.filter(function (d) { return D().resultatRendu(d.etatAnalyse); }) },
      { poste: 'prelevement', type: 'prelevement_attendu', priorite: 'haute',
        libelle: function (d) { return 'Prélèvement à réaliser — ' + d.patient; },
        detail: function (d) { return d.analyse + ' — réglé, le patient peut être appelé'; },
        source: demandes.filter(function (d) { return d.etatAnalyse === 'attente_prelevement'; }) },
      { poste: 'caisse', type: 'encaissement', priorite: 'normale',
        libelle: function (f) { return 'Reliquat à encaisser — ' + f.patient; },
        detail: function (f) { return f.numero + ' — reste ' + C.money(f.reliquat); },
        source: factures.filter(function (f) { return f.reliquat > 0; }).slice(0, 14) },
      { poste: 'stock', type: 'reapprovisionnement', priorite: 'haute',
        libelle: function (p) { return 'Réapprovisionnement — ' + p.designation; },
        detail: function (p) { return 'Stock ' + p.stock + ' ' + p.unite + ' pour un seuil de ' + p.seuilAlerte; },
        source: produits.slice(0, 16) },
    ];

    var n = 0;
    MODELES.forEach(function (m) {
      m.source.slice(0, 14).forEach(function (x) {
        pr.notifier({
          type: m.type, poste: m.poste,
          libelle: m.libelle(x), detail: m.detail(x),
          priorite: m.priorite,
          patientId: x.patientId || null,
          reference: x.reference || x.numero || null,
        });
        n++;
        /* Les plus anciennes sont lues : une pile où tout est non lu ne
           distingue plus ce qui vient d'arriver. */
        if (rnd() > 0.55) {
          var derniere = S().collection('notifications').active()[0];
          if (derniere) S().collection('notifications').update(derniere.id, { lue: true });
        }
      });
    });
    return n;
  }

  /* ==========================================================================
   * 10. LA FACTURE MÈRE D'ASSURANCE
   * ======================================================================== */
  function facturesMere(rnd) {
    var d = D();
    var col2 = col('facturesMere', { module: 'M9', entite: 'facture mère', prefix: 'FM' });
    if (col2.all().length) return col2.active().length;
    var factures = S().collection('factures').active();
    var n = 0;

    (d.ASSUREURS || []).forEach(function (comp) {
      var siennes = factures.filter(function (f) {
        return (f.assureur === comp.code || f.assureur === comp.nom) && (f.partAssurance || 0) > 0;
      });
      if (siennes.length < 3) return;
      var parSous = {};
      siennes.forEach(function (f) {
        var s = f.souscripteur || 'Sans souscripteur désigné';
        if (!parSous[s]) parSous[s] = { souscripteur: s, nbFactures: 0, montant: 0, assureur: 0, patient: 0 };
        parSous[s].nbFactures++;
        parSous[s].montant += f.montantTTC || 0;
        parSous[s].assureur += f.partAssurance || 0;
        parSous[s].patient += f.partPatient || 0;
      });
      var sous = Object.keys(parSous).map(function (k) { return parSous[k]; });
      var total = sous.reduce(function (t, g) { return t + g.assureur; }, 0);
      var regle = rnd() > 0.45;
      n++;
      col2.insert({
        numero: 'FM-' + FIN.getFullYear() + '-' + C.pad(n, 4),
        compagnieCode: comp.code, compagnie: comp.nom,
        periode: 'trimestre', periodeLabel: 'Trimestrielle',
        debut: C.iso(C.addDays(FIN, -90)), fin: C.iso(FIN),
        dateEmission: C.iso(C.addDays(FIN, -C.between(rnd, 1, 30))),
        nbSouscripteurs: sous.length, nbFactures: siennes.length,
        montantReclame: total,
        souscripteurs: sous,
        piecesFilles: siennes.map(function (f) { return f.numero; }),
        controle: { totalFilles: total, totalFactures: total, totalLignes: total, concordant: true },
        etat: regle ? 'reglee' : 'transmise',
        dateReglement: regle ? C.iso(C.addDays(FIN, -C.between(rnd, 0, 15))) : null,
        montantRegle: regle ? total : null,
        referenceReglement: regle ? 'VIR-' + C.between(rnd, 100000, 999999) : null,
        reliquat: regle ? 0 : total,
        emisePar: 'TAKI Alimatou',
      });
    });
    return n;
  }

  /* ==========================================================================
   * 11. LES TRANSFERTS GROS → DÉTAIL — des bons MULTI-LIGNES, article par article
   * --------------------------------------------------------------------------
   * L'écran des transferts était vide dans le jeu de démonstration : on ne
   * pouvait ni lire le détail d'un bon, ni vérifier ce que la pharmacie avait
   * reçu. Un réapprovisionnement réel porte sur plusieurs références — le
   * bon est donc semé avec ses LIGNES, chacune tirée du référentiel des
   * produits (désignation, unité, CUMP, lot FEFO), et jamais avec un
   * « N articles » sans contenu.
   *
   * RG-03, POURQUOI AUCUN STOCK NE DEVIENT NÉGATIF : le stock actuel des
   * produits est l'état APRÈS ces transferts. Le magasin, au jour d'un bon,
   * détenait donc son stock actuel PLUS tout ce qui a été transféré depuis —
   * toujours au moins la quantité du bon. On ne retouche pas les stocks :
   * un transfert déplace, il ne crée rien, et la somme gros + détail reste
   * réconciliée avec l'inventaire SAGE. Le cumul transféré par article est
   * en outre plafonné à la moitié de son stock total, pour rester plausible.
   *
   * Chaque ligne écrit ses DEUX mouvements symétriques (sortie du magasin,
   * entrée à la pharmacie), justifiés par le numéro du bon — c'est ce que
   * lisent le registre des mouvements et le point des stocks.
   *
   * Générateur PROPRE (graine dédiée) : partager `rnd` décalerait les tirages
   * de toutes les fonctions appelées ensuite.
   * ======================================================================== */
  function transfertsGrosDetail() {
    var colT = col('transferts', { module: 'M6', entite: 'Transfert' });
    if (colT.all().length) return colT.active().length;
    var colM = col('mouvements', { module: 'M6', entite: 'MouvementStock' });
    var rnd2 = C.seeded(20260914);
    var tous = S().collection('produits').active();
    var lotsTous = S().collection('lots').active();
    var clinique = tous.filter(function (p) {
      return (p.categorie === 'medicament' || p.categorie === 'conso_medical') && (p.stock || 0) >= 4;
    });
    var labo = tous.filter(function (p) {
      return (p.categorie === 'reactif' || p.categorie === 'conso_labo') && (p.stock || 0) >= 4;
    });
    if (clinique.length < 3) return 0;

    /* Le destinataire nomme QUI réceptionne : le bon se signe à l'arrivée. */
    var pers = personnel();
    function agentDu(service, defaut) {
      var a = pers.filter(function (e) { return e.service === service; })[0];
      return a ? a.nomComplet : defaut;
    }
    var DESTINATIONS = [
      { nom: 'Pharmacie d’urgence', poids: 8, service: 'Pharmacie', recep: 'DIEYABIDI Aïssatou', labo: false },
      { nom: 'Pharmacie externe', poids: 3, service: 'Pharmacie', recep: 'DIEYABIDI Aïssatou', labo: false },
      { nom: 'Laboratoire', poids: 3, service: 'Laboratoire', labo: true },
      { nom: 'Maternité', poids: 2, service: 'Maternité', labo: false },
      { nom: 'Salle de soins', poids: 2, service: 'Soins infirmiers', labo: false },
      { nom: 'Bloc opératoire', poids: 1, service: 'Chirurgie', labo: false },
    ];
    var urne = [];
    DESTINATIONS.forEach(function (d) { for (var k = 0; k < d.poids; k++) urne.push(d); });

    var MOTIFS = ['Réapprovisionnement hebdomadaire', 'Rupture signalée au rayon',
      'Seuil d’alerte atteint', 'Préparation de la garde du week-end', 'Dotation mensuelle du service'];

    /* FEFO (RG-05) : le lot qui part est celui qui périme le premier, parmi
       ceux encore valides à la date du bon. */
    function lotFefo(produitId, dateBon) {
      var siens = lotsTous.filter(function (l) {
        return l.produitId === produitId && String(l.datePeremption) > dateBon;
      }).sort(function (a, b) { return String(a.datePeremption).localeCompare(String(b.datePeremption)); });
      return siens[0] || null;
    }

    var NB = 20, cumul = {}, n = 0;
    var dates = [];
    for (var i = 0; i < NB; i++) {
      var d = C.addDays(DEBUT, Math.round((JOURS - 2) * (i + rnd2() * 0.8) / NB));
      if (d.getDay() === 0) d = C.addDays(d, 1);
      dates.push(C.iso(d));
    }

    dates.forEach(function (dateBon) {
      var dest = C.pick(rnd2, urne);
      var vivier = (dest.labo && labo.length >= 3 ? labo : clinique).slice();
      var nbLignes = C.between(rnd2, 3, Math.min(12, vivier.length));
      var lignes = [];
      for (var k = 0; k < nbLignes && vivier.length; k++) {
        var idx = C.between(rnd2, 0, vivier.length - 1);
        var p = vivier.splice(idx, 1)[0];
        var plafond = Math.floor((p.stock || 0) / 2) - (cumul[p.id] || 0);
        if (plafond < 1) continue;
        var q = Math.min(plafond, C.between(rnd2, 1, Math.max(2, Math.min(120, Math.round(p.stock * 0.12)))));
        cumul[p.id] = (cumul[p.id] || 0) + q;
        var lot = lotFefo(p.id, dateBon);
        lignes.push({
          produitId: p.id, code: p.code, produit: p.designation, categorie: p.categorie,
          unite: p.unite, cump: p.cump, quantite: q,
          lot: lot ? lot.numeroLot : null, peremption: lot ? lot.datePeremption : null,
        });
      }
      if (lignes.length < 3) return;
      n++;
      var reference = 'TR-' + C.pad(n, 5);
      var quantite = lignes.reduce(function (t, l) { return t + l.quantite; }, 0);
      var valeur = lignes.reduce(function (t, l) { return t + l.quantite * (l.cump || 0); }, 0);

      lignes.forEach(function (l) {
        colM.insert({
          reference: reference, date: dateBon, produitId: l.produitId, produit: l.produit,
          type: 'transfert', typeLabel: 'Transfert — sortie magasin', quantite: l.quantite,
          stockType: 'gros', justificatif: 'Bon de transfert ' + reference,
          utilisateur: 'MAMAN Zoukanéri',
        });
        colM.insert({
          reference: reference, date: dateBon, produitId: l.produitId, produit: l.produit,
          type: 'transfert', typeLabel: 'Transfert — entrée pharmacie', quantite: l.quantite,
          stockType: 'detail', justificatif: 'Bon de transfert ' + reference,
          utilisateur: 'MAMAN Zoukanéri',
        });
      });

      colT.insert({
        reference: reference, date: dateBon,
        demandeur: dest.nom, motif: C.pick(rnd2, MOTIFS),
        lignes: lignes, nbLignes: lignes.length,
        quantiteTotale: quantite, valeur: valeur,
        operateur: 'MAMAN Zoukanéri',
        receptionnaire: dest.recep || agentDu(dest.service, 'Major du service'),
        etat: 'receptionne', dateReception: dateBon,
        /* Les champs à plat que lisaient les bons mono-ligne. */
        produit: lignes.length + ' articles', unite: '', quantite: quantite,
      });
    });
    return n;
  }

  /* ==========================================================================
   * VAGUE 61 — LES ÉCRANS QUI RESTAIENT VIDES
   * --------------------------------------------------------------------------
   * Demande de la Direction : demandes d’imagerie, constantes de l’accueil,
   * patients externes, certificats des externes et fiches patient complètes.
   * Même principe que tout ce fichier : on REJOUE les fabriques du parcours
   * (PR.ouvrirDemandeExterne, PR.ouvrirDemandeImagerie, PR.encaisser) plutôt
   * que de recopier leurs formes — une demande semée à la main aurait eu une
   * facture sans lignes, ou des lignes sans demande.
   *
   * Ces fonctions s’exécutent APRÈS la journée des postes : les états qu’elles
   * posent (examen exécuté, résultat en relecture) sont le flux COURANT que
   * chaque poste doit montrer, et la journée des postes les aurait soldés.
   *
   * VOLUME MESURÉ : le magasin frôle le quota du navigateur (leçon de la
   * vague 60). Chaque registre reçoit ce qu’il faut pour que ses onglets et
   * ses indicateurs aient quelque chose à dire, pas davantage.
   * ======================================================================== */

  /* L’heure d’un geste, au format des autres registres du jeu. */
  function horodatage(date, h, m) {
    return C.iso(date) + 'T' + C.pad(h, 2) + ':' + C.pad(m || 0, 2) + ':00.000Z';
  }

  /* Les examens du catalogue du laboratoire (D.ANALYSES, codes L01…) portent
     leur désignation ; les VARIABLES de résultat sont rangées sous le code du
     modèle structuré (data-labo). Le laboratoire les rapproche par désignation
     (codeExamenDe) ; le jeu nomme la correspondance pour les seuls examens
     qu’il sème — une table explicite plutôt qu’un rapprochement approché. */
  var EXAMEN_STRUCTURE = {
    'GE-DP / FROTTIS SANGUIN': 'GEDP', 'NFS COMPLETE (HEMOGRAMME)': 'NFS',
    'GROUPE SANGUIN-RHESUS': 'GSRH', 'SERODIAGNOSTIC WIDAL (SDW)': 'SDW', 'HIV': 'VIH',
    'HEPATITE B': 'AGHBS', 'TPHA': 'TPHA', 'GLYCEMIE': 'GLYAJ', 'CREATININE': 'CREA',
    'IONOGRAMME SANGUIN': 'IONO', 'ECBU': 'ECBU', 'PRELEVEMENT VAGINAL (PV)': 'PV',
    'PSA TOTAL': 'PSAT', 'CRP': 'CRP', 'TP + INR': 'TP', 'TBG SERIQUE (SANGUIN)': 'TBGS',
    'TRANSAMINASE TGO / ASAT': 'TGO', 'CHOLESTEROL TOTAL': 'CHOLT', 'TRIGLYCERIDE': 'TG',
  };

  function analyseParDesignation(designation) {
    return (D().ANALYSES || []).filter(function (a) { return a.designation === designation; })[0] || null;
  }

  /* Un résultat STRUCTURÉ, sous la forme qu’écrit la saisie du laboratoire :
     `valeurs` par code de variable, `resultat` en résumé, conclusion déduite
     des bornes par L.ecart — jamais tirée au sort à côté des valeurs, sans
     quoi un résultat « Normal » pourrait porter une glycémie à 2 g/l. */
  function resultatStructure(rnd, designation, anormal) {
    var L = global.SIGH.labo;
    var code = EXAMEN_STRUCTURE[designation];
    var vars = (L && code) ? L.variablesDe(code) : [];
    if (!vars.length) return null;
    var saisies = {};
    vars.forEach(function (v) {
      if (v.type === 'numerique') {
        var min = v.min != null ? v.min : (v.max != null ? v.max * 0.4 : 1);
        var max = v.max != null ? v.max : min * 2;
        var x = min + rnd() * (max - min);
        if (anormal && !v.parent && rnd() > 0.4) x = max * (1.2 + rnd() * 0.5);
        saisies[v.code] = Number(x.toFixed(v.decimales != null ? v.decimales : 2));
      } else if (['binaire', 'ternaire', 'titre'].indexOf(v.type) !== -1) {
        saisies[v.code] = (anormal && rnd() > 0.5) ? 'Positif' : (v.normal || 'Négatif');
      } else if (v.type === 'liste') {
        var autres = (v.valeurs || []).filter(function (x) { return x !== v.normal; });
        saisies[v.code] = (anormal && autres.length) ? autres[0] : (v.normal || (v.valeurs || [''])[0]);
      } else if (v.type === 'reactif') {
        saisies[v.code] = (v.valeurs || ['—'])[0];
      } else if (v.type === 'lot') {
        saisies[v.code] = 'LOT-' + C.between(rnd, 20000, 99999);
      } else if (v.type === 'expiration') {
        saisies[v.code] = '2027-0' + C.between(rnd, 1, 9);
      } else if (v.type === 'commentaire') {
        saisies[v.code] = (v.valeurs || [''])[anormal && v.valeurs && v.valeurs.length > 1 ? 1 : 0];
      } else if (v.type === 'texte') {
        saisies[v.code] = 'RAS';
      }
    });
    var anormales = vars.filter(function (v) { return L.ecart(v, saisies[v.code]); });
    return {
      valeurs: saisies,
      resultat: vars.filter(function (v) { return !v.accompagnement && saisies[v.code] != null && saisies[v.code] !== ''; })
        .slice(0, 4).map(function (v) {
          var u = L.unite(v.unite);
          return v.libelle + ' ' + saisies[v.code] + (u === '—' ? '' : ' ' + u);
        }).join(' · '),
      resultatStructure: true,
      conclusion: anormales.length ? 'Anormal' : 'Normal',
      anormales: anormales.length,
    };
  }

  /* Faire avancer une demande d’analyse sur le circuit du biologiste, en
     posant les HORODATAGES que l’écran lit (preleveLe, recuLaboLe) — l’état
     seul ne range rien dans les onglets du prélèvement. */
  function avancerAnalyse(dem, etape, date, rnd, anormal) {
    var bio = soignantsQui(function (x) { return x.qualite === 'medecin'; })[0];
    var qui = bio ? bio.nomComplet : 'Laboratoire';
    var col_ = S().collection('demandesAnalyses');
    var quand = horodatage(date, C.between(rnd, 8, 11), C.between(rnd, 0, 59));
    var ordre = ['preleve', 'recu', 'technique', 'rendu'];
    var rang = ordre.indexOf(etape);
    if (rang < 0) return;
    col_.update(dem.id, { etatAnalyse: 'preleve', prelevePar: qui, preleveParId: bio ? bio.id : null, preleveLe: quand });
    if (rang < 1) return;
    col_.update(dem.id, { etatAnalyse: 'en_cours', recuLaboLe: quand, recuPar: qui });
    if (rang < 2) return;
    var res = resultatStructure(rnd, dem.analyse, anormal) || { resultat: 'Résultat disponible', conclusion: 'Normal' };
    col_.update(dem.id, Object.assign({}, res, {
      etatAnalyse: 'valide_technique', laborantin: qui, saisiPar: qui, saisiLe: quand,
      valideTechniqueLe: quand, valideTechniquePar: qui,
    }));
    if (rang < 3) return;
    col_.update(dem.id, {
      etatAnalyse: 'valide', valideLe: quand, valideBiologiquePar: qui,
      qualiteValidateur: 'Biologiste médical', version: 1,
    });
  }

  /* Les identités des patients ADRESSÉS DE L’EXTÉRIEUR. Inventées pour le jeu,
     comme tous les patients de démonstration : aucune n’est reprise d’un
     document. */
  var EXTERNES = [
    { nom: 'GOUNOU', prenom: 'Rachidatou', sexe: 'F', dateNaissance: '1994-03-12', residence: 'Kouaba' },
    { nom: 'SAMBO', prenom: 'Issifou', sexe: 'M', dateNaissance: '1981-07-02', residence: 'Tchirimina' },
    { nom: 'N’TCHA', prenom: 'Bernadette', sexe: 'F', dateNaissance: '1989-11-23', residence: 'Boriyouré' },
    { nom: 'YOROU', prenom: 'Aboubakar', sexe: 'M', dateNaissance: '1976-01-15', residence: 'Péporiyakou' },
    { nom: 'KOUAGOU', prenom: 'Fidèle', sexe: 'M', dateNaissance: '1999-05-30', residence: 'Yimporima' },
    { nom: 'BIAOU', prenom: 'Célestine', sexe: 'F', dateNaissance: '2001-09-08', residence: 'Kantaborifa' },
    { nom: 'TAMOU', prenom: 'Salamatou', sexe: 'F', dateNaissance: '1992-12-19', residence: 'Winkè' },
    { nom: 'DJATO', prenom: 'Émile', sexe: 'M', dateNaissance: '1968-04-04', residence: 'Santa' },
    { nom: 'OUOROU', prenom: 'Mariam', sexe: 'F', dateNaissance: '1985-06-27', residence: 'Ourbouga' },
    { nom: 'KPATINDÉ', prenom: 'Honorine', sexe: 'F', dateNaissance: '1996-02-14', residence: 'Bérécingou' },
    { nom: 'MOUMOUNI', prenom: 'Karim', sexe: 'M', dateNaissance: '1990-10-10', residence: 'Kouaba' },
    { nom: 'SOUMANOU', prenom: 'Awaou', sexe: 'F', dateNaissance: '1979-08-21', residence: 'Tchirimina' },
  ];
  var PRESCRIPTEURS_EXTERIEURS = ['Dr AGBO Koffi — CS de Perma', 'Dr ZANNOU Parfait — HZ de Tanguiéta',
    'SF KOTO Mariette — CS de Kouandé', 'Dr HOUNSOU Rémi — cabinet médical, Natitingou'];

  /* --------------------------------------------------------------------------
   * 1. PATIENT EXTERNE — DEMANDES D’ANALYSES (m1-externe)
   * ----------------------------------------------------------------------- */
  function externesSeed(rnd) {
    var pr = PR();
    var caisse = parFonction('caissiere')[0];
    /* [désignations, étape, service, hospitalisé, anomalie, recul en jours]
       Les sept étapes du circuit sont toutes représentées : l’onglet
       « Résultats » doit montrer autant le verrou de la caisse que le compte
       rendu remis. */
    var PLAN = [
      [['GE-DP / FROTTIS SANGUIN', 'NFS COMPLETE (HEMOGRAMME)', 'GROUPE SANGUIN-RHESUS'], 'rendu', 'Maternité', false, false, 12],
      [['SERODIAGNOSTIC WIDAL (SDW)', 'NFS COMPLETE (HEMOGRAMME)'], 'impaye', 'Médecine', false, false, 0],
      [['HIV', 'HEPATITE B', 'TPHA'], 'paye', 'Maternité', false, false, 1],
      [['GLYCEMIE', 'CREATININE', 'IONOGRAMME SANGUIN'], 'rendu', null, true, true, 20],
      [['GE-DP / FROTTIS SANGUIN'], 'preleve', 'Médecine', false, false, 1],
      [['ECBU', 'PRELEVEMENT VAGINAL (PV)'], 'recu', 'Maternité', false, false, 2],
      [['NFS COMPLETE (HEMOGRAMME)', 'GE-DP / FROTTIS SANGUIN', 'GLYCEMIE'], 'partiel', 'Maternité', false, false, 1],
      [['PSA TOTAL', 'CREATININE'], 'technique', 'Médecine et spécialité', false, true, 3],
      [['NFS COMPLETE (HEMOGRAMME)', 'CRP', 'TP + INR'], 'rendu', null, true, false, 34],
      [['TBG SERIQUE (SANGUIN)'], 'impaye', 'Maternité', false, false, 0],
      [['TRANSAMINASE TGO / ASAT', 'CHOLESTEROL TOTAL', 'TRIGLYCERIDE'], 'rendu', 'Médecine', false, true, 45],
      [['SERODIAGNOSTIC WIDAL (SDW)', 'GE-DP / FROTTIS SANGUIN'], 'rendu', 'Médecine', false, true, 7],
    ];
    var fait = { patients: 0, demandes: 0 };
    PLAN.forEach(function (pl, i) {
      var id = EXTERNES[i];
      var codes = pl[0].map(analyseParDesignation).filter(Boolean).map(function (a) { return a.code; });
      if (!codes.length) return;
      var date = C.addDays(FIN, -pl[5]);
      var res;
      try {
        res = pr.ouvrirDemandeExterne(Object.assign({}, id, {
          telephone: '0' + C.between(rnd, 1, 9) + C.between(rnd, 10000000, 99999999),
          prescripteur: PRESCRIPTEURS_EXTERIEURS[i % PRESCRIPTEURS_EXTERIEURS.length],
          indication: C.pick(rnd, ['Fièvre persistante', 'Bilan prénatal', 'Bilan de contrôle',
            'Douleurs abdominales', 'Suivi d’un traitement']),
          /* Le secteur de l’hospitalisation prend le vocabulaire des SIX
             secteurs (vague 55) : c’est lui que l’onglet « hospitalisation »
             de l’accueil reconnaît. */
          serviceDemandeur: pl[2], hospitalise: pl[3],
          secteurDemandeur: pl[3] ? 'Hospitalisation et soins' : null,
          urgence: 'aucune', analyses: codes,
          date: horodatage(date, C.between(rnd, 7, 12), C.between(rnd, 0, 59)),
        }));
      } catch (e) { console.warn('[SEED] externe', id.nom, e.message); return; }
      fait.patients++; fait.demandes += res.demandes.length;
      /* dossierExterne ne date pas la création du dossier : la date est celle
         de la venue, sans quoi le répertoire afficherait un dossier sans âge. */
      S().collection('patients').update(res.patient.id, { dateCreation: C.iso(date) });

      var etape = pl[1];
      if (etape === 'impaye') return;
      var dues = pr.lignesDues(S().collection('factures').get(res.facture.id));
      var choisies = etape === 'partiel' ? dues.slice(0, 1) : dues;
      pr.encaisser(res.facture.id, {
        lignes: choisies.map(function (l) { return l.id; }), mode: 'especes',
        utilisateur: caisse ? caisse.nomComplet : 'Caisse',
      });
      if (etape === 'paye' || etape === 'partiel') return;
      res.demandes.forEach(function (dem) {
        var cur = S().collection('demandesAnalyses').get(dem.id);
        if (!cur || cur.bloqueParPaiement) return;
        avancerAnalyse(cur, etape, C.addDays(date, etape === 'rendu' ? 1 : 0), rnd, pl[4]);
      });
    });
    return fait;
  }

  /* --------------------------------------------------------------------------
   * 2. CERTIFICATS DES PATIENTS EXTERNES (m1-certificats-externes)
   * --------------------------------------------------------------------------
   * La NUMÉROTATION est celle de l’écran « Certificats & attestations » : série
   * propre au sigle ET à l’année, n = pièces déjà émises + 1. La règle vit dans
   * la fermeture de l’écran (numeroter) et n’est pas exposée ; on applique la
   * MÊME formule, sur la collection telle qu’elle est à cet instant, pour que
   * la série continue celle des pièces déjà semées au lieu de la doubler.
   * ----------------------------------------------------------------------- */
  function certificatsExternesSeed(rnd) {
    var pieces = col('pieces', { module: 'M1', entite: 'pièce certifiante', prefix: 'PCE' });
    var types = S().collection('typesPiece').active();
    var medecins = parFonction('medecin');
    var d = D();
    if (!types.length || !medecins.length) return 0;
    function type(sigle) { return types.filter(function (t) { return t.sigle === sigle; })[0]; }

    var externes = patients().filter(function (p) { return p.externe; });
    var CORPS = {
      CMNI: 'Je soussigné certifie que l’intéressé(e) ne présente aucune infirmité apparente '
        + 'de nature à le rendre inapte à l’emploi postulé.',
      CMVC: 'Je soussigné certifie avoir procédé à la visite médicale de l’intéressé(e).',
      CMNCI: 'Je soussigné certifie n’avoir constaté ce jour aucune contre-indication à la pratique '
        + 'des activités physiques et sportives.',
      CMDPS: 'Je soussigné certifie que l’état de santé de l’intéressé(e) justifie une dispense '
        + 'temporaire des activités physiques et sportives.',
      ATG: 'Je soussigné, Docteur en médecine, certifie avoir examiné ce jour la patiente '
        + 'susnommée et avoir constaté un état de grossesse évolutive.',
    };
    var n = 0;
    externes.forEach(function (p, i) {
      /* Un externe sur deux repart avec une pièce : l’aptitude à l’emploi et
         la visite sont ce que l’on vient chercher sans être suivi ici. */
      if (i % 2 === 1 && i !== 5) return;
      var sigle = p.sexe === 'F' && i % 4 === 0 ? 'ATG'
        : C.pick(rnd, ['CMNI', 'CMNI', 'CMVC', 'CMNCI', 'CMDPS']);
      var t = type(sigle) || type('CMVC') || types[0];
      var md = unDe(rnd, medecins);
      var delivrance = C.addDays(FIN, -C.between(rnd, 0, 30));
      var an = delivrance.getFullYear();
      var num = pieces.all().filter(function (x) { return x.sigle === t.sigle && x.annee === an; }).length + 1;
      var tarif = t.tarifCode && d.tarif ? d.tarif(t.tarifCode) : null;
      pieces.insert({
        numero: num, annee: an,
        reference: t.sigle + ' ' + C.pad(num, 3) + '/' + C.pad(num, 3) + '/CNT/' + t.direction + '/' + an,
        sigle: t.sigle, libelle: t.libelle, direction: t.direction, typeId: t.id,
        patientId: p.id, patient: p.nom + ' ' + p.prenom, patientCode: p.code,
        medecin: md.nomComplet,
        dateDelivrance: C.iso(delivrance),
        contenu: CORPS[t.sigle] || 'En foi de quoi la présente pièce est établie pour servir et valoir ce que de droit.',
        remisA: 'L’intéressé(e)',
        montant: tarif ? tarif.prixNonAssure : null,
        couverture: tarif && tarif.assurable === 'sos'
          ? 'Couvert par SOS uniquement — toute autre compagnie : à la charge du patient'
          : 'Non couvert par les assurances',
      });
      n++;
    });
    return n;
  }

  /* --------------------------------------------------------------------------
   * 3. DEMANDES D’IMAGERIE MÉDICALE (m2-imagerie-demandes)
   * --------------------------------------------------------------------------
   * Les cinq modalités, les quatre états. Une demande VALIDÉE d’un patient de
   * la maison reprend un compte rendu RENDU déjà au registre (même examen,
   * même patient, même prescripteur) et le lui RATTACHE : les comptes rendus
   * existaient sans demande, la demande naît sous eux — dupliquer aurait fait
   * deux comptes rendus pour un seul examen.
   * ----------------------------------------------------------------------- */
  function demandesImagerieSeed(rnd) {
    var pr = PR();
    var IM = D().IMAGERIE || {};
    var crs = col('resultatsImagerie', { module: 'M2', entite: 'compte rendu d’imagerie', prefix: 'IMG' });
    var realisateur = soignantsQui(function (x) { return x.realiseImagerie; })[0]
      || soignantsQui(function (x) { return x.qualite === 'medecin'; })[0];
    var prescripteurs = soignantsQui(function (x) { return x.prescrit; });
    var caisse = parFonction('caissiere')[0];
    if (!realisateur || !prescripteurs.length || !(IM.EXAMENS || []).length) return { demandes: 0 };

    var PLAN = [
      ['IMG-ECHO-PEL', 2], ['IMG-ECHO-ABD', 2], ['IMG-ECHO-ABP', 1], ['IMG-ECHO-PRO', 1],
      ['IMG-ECHO-OBS', 3], ['IMG-ECHO-OBS1', 2], ['IMG-ECG', 2],
      ['IMG-RX-THO', 2], ['IMG-RX-MEM', 2], ['IMG-RX-RAC', 1], ['IMG-RX-BAS', 1], ['IMG-RX-CRA', 1], ['IMG-RX-ASP', 1],
      ['IMG-MAM-DEP', 2], ['IMG-MAM-DIA', 2],
      ['IMG-TDM-CER', 2], ['IMG-TDM-THO', 1], ['IMG-TDM-ABP', 1], ['IMG-TDM-RAC', 1],
      ['IMG-IRM-CER', 1], ['IMG-IRM-RAC', 2], ['IMG-IRM-GEN', 1], ['IMG-IRM-PEL', 1],
    ];
    /* Deux validées pour une de chaque autre état : le registre est d’abord
       une archive, mais chaque KPI et chaque verrou doivent avoir un cas. */
    var CYCLE = ['validee', 'executee', 'payee', 'validee', 'demandee'];
    var externes = patients().filter(function (p) { return p.externe; });
    var fait = { demandes: 0, rattaches: 0, crCrees: 0, externes: 0 };
    var rang = 0;

    PLAN.forEach(function (pl) {
      var ex = IM.EXAMENS.filter(function (x) { return x.code === pl[0]; })[0];
      if (!ex) return;
      var feminin = /OBS|PEL/.test(ex.code) || ex.modalite === 'mammographie';
      for (var k = 0; k < pl[1]; k++) {
        var etat = CYCLE[rang % CYCLE.length];
        var externe = rang % 4 === 3;
        rang++;

        var recul = etat === 'demandee' ? C.between(rnd, 0, 2)
          : (etat === 'validee' ? C.between(rnd, 6, 90) : C.between(rnd, 1, 6));
        var date = C.addDays(FIN, -recul);
        var patient = null, crExistant = null;
        var presc = unDe(rnd, prescripteurs);

        if (externe) {
          patient = unDe(rnd, externes.filter(function (p) { return !feminin || p.sexe === 'F'; }));
        } else if (etat === 'validee') {
          /* Le compte rendu rendu, encore orphelin, de cet examen. */
          crExistant = crs.active().filter(function (r) {
            return r.examenCode === ex.code && r.statut === 'rendu' && !r.demandeImagerieId;
          })[0] || null;
          if (crExistant) {
            patient = S().collection('patients').get(crExistant.patientId);
            date = C.toDate(String(crExistant.date).slice(0, 10));
          }
        }
        if (!patient) {
          patient = unDe(rnd, patients().filter(function (p) {
            return !p.externe && (!feminin || p.sexe === 'F');
          }));
        }
        if (!patient) continue;

        var secteur = /OBS|PEL|MAM/.test(ex.code) ? 'Maternité'
          : (/TDM|RX-THO|RX-ASP/.test(ex.code) && rnd() > 0.5 ? 'Hospitalisation et soins' : 'Consultation');
        var res;
        try {
          res = pr.ouvrirDemandeImagerie({
            patientId: patient.id, examens: [ex.code],
            prescripteur: crExistant && crExistant.prescripteur ? crExistant.prescripteur
              : (externe ? PRESCRIPTEURS_EXTERIEURS[rang % PRESCRIPTEURS_EXTERIEURS.length] : presc.nomComplet),
            indication: crExistant ? crExistant.indication
              : C.pick(rnd, ['Douleurs à explorer', 'Bilan lésionnel', 'Contrôle évolutif', 'Bilan préopératoire', 'Suivi de grossesse']),
            urgent: etat !== 'validee' && rnd() > 0.85,
            secteurDemandeur: externe ? null : secteur,
            origine: externe ? 'externe' : (secteur === 'Hospitalisation et soins' ? 'hospitalisation' : 'consultation'),
            date: horodatage(date, C.between(rnd, 7, 11), C.between(rnd, 0, 59)),
          });
        } catch (e) { console.warn('[SEED] imagerie', ex.code, e.message); continue; }
        var dem = res.demandes[0];
        fait.demandes++;
        if (externe) fait.externes++;
        if (etat === 'demandee') continue;

        /* La caisse encaisse l’examen NOMMÉ : c’est ce qui le libère. */
        var fac = S().collection('factures').get(res.facture.id);
        pr.encaisser(fac.id, {
          lignes: pr.lignesDues(fac).map(function (l) { return l.id; }), mode: 'especes',
          utilisateur: caisse ? caisse.nomComplet : 'Caisse',
        });
        var colDem = S().collection('demandesImagerie');
        colDem.update(dem.id, { regleLe: horodatage(date, 11, 30) });
        if (etat === 'payee') continue;

        /* La tâche du poste est faite dès que l’examen est pratiqué. */
        pr.taches().filter(function (t) {
          return t.factureId === fac.id && t.type === 'imagerie' && t.statut !== 'fait';
        }).forEach(function (t) { pr.terminer(t.id, realisateur.nomComplet); });

        var rendu = etat === 'validee';
        if (crExistant) {
          crs.update(crExistant.id, { demandeImagerieId: dem.id, demandeReference: dem.reference });
          fait.rattaches++;
        } else {
          /* Un compte rendu EN RÉDACTION n’a pas encore de conclusion : c’est
             ce qui le distingue d’un compte rendu prêt à rendre, et l’écran
             refuse de rendre sans elle. */
          crs.insert({
            reference: 'IMG-' + C.pad(crs.all().length + 1, 4),
            date: horodatage(date, C.between(rnd, 12, 16), 0),
            examenCode: ex.code, examen: ex.label,
            patientId: patient.id, patient: patient.nom + ' ' + patient.prenom, patientCode: patient.code,
            age: C.age(patient.dateNaissance),
            indication: dem.indication || '—', ddr: /OBS/.test(ex.code) ? 'inconnue' : '—', condition: 'Bonne',
            prescripteur: dem.prescripteur,
            realisateurId: realisateur.id, realisateur: realisateur.nomComplet,
            valeurs: valeursImagerie(rnd, IM, ex.code),
            annexes: '',
            conclusion: rendu ? conclusionImagerie(rnd, ex.code) : '',
            statut: rendu ? 'rendu' : 'brouillon',
            renduLe: rendu ? horodatage(date, 17, 0) : null,
            demandeImagerieId: dem.id, demandeReference: dem.reference,
          });
          fait.crCrees++;
        }
        colDem.update(dem.id, Object.assign({
          statut: rendu ? 'validee' : 'executee', executeLe: horodatage(date, 12, 0),
        }, rendu ? { valideLe: horodatage(date, 17, 0) } : {}));
      }
    });
    return fait;
  }

  /* --------------------------------------------------------------------------
   * 4. CONSTANTES À L’ACCUEIL (m1-constantes) ET ZONE 1 DU DOSSIER
   * --------------------------------------------------------------------------
   * UNE MESURE, UNE FOIS. Le dossier de consultation porte en zone 1 les
   * constantes prises à l’arrivée ; la collection `constantes` est celle que
   * tient l’écran de l’accueil et que la consultation reprend (Bug 14). Semer
   * les deux indépendamment aurait donné, pour la même venue, une température
   * au dossier et une autre au relevé. Chaque dossier engendre donc SON
   * relevé ; un dossier arrivé sans constantes les reçoit du relevé.
   * ----------------------------------------------------------------------- */
  function constantesAccueilSeed(rnd, fichesDemo) {
    var cst = col('constantes', { module: 'M1', entite: 'relevé de constantes', prefix: 'CST' });
    var dos = S().collection('dossiersConsultation');
    var recus = parFonction('accueil');
    var n = 0, zone1 = 0;

    function mesure(p, base, anormal) {
      var enfant = C.age(p.dateNaissance) < 12;
      var poids = base && base.poids ? Math.round((base.poids + (rnd() - 0.5) * 3) * 10) / 10
        : (enfant ? C.between(rnd, 12, 35) : C.between(rnd, 48, 92));
      var taille = base && base.taille ? base.taille : (enfant ? C.between(rnd, 85, 145) : C.between(rnd, 150, 186));
      var m = {
        temperature: Number((36.3 + rnd() * 1.3).toFixed(1)),
        tensionSys: C.between(rnd, 10, 13), tensionDia: C.between(rnd, 6, 8),
        pouls: C.between(rnd, 64, 96), fr: C.between(rnd, 14, 20), spo2: C.between(rnd, 95, 99),
        poids: poids, taille: taille,
      };
      /* Une minorité hors bornes : fièvre, tachycardie, hypertension ou
         désaturation — c’est ce que l’écran signale, il doit avoir de quoi. */
      if (anormal) {
        var quoi = C.pick(rnd, ['fievre', 'fievre', 'tachy', 'hta', 'spo2']);
        if (quoi === 'fievre') { m.temperature = Number((38.4 + rnd() * 1.6).toFixed(1)); m.pouls = C.between(rnd, 98, 118); }
        if (quoi === 'tachy') m.pouls = C.between(rnd, 104, 128);
        if (quoi === 'hta') { m.tensionSys = C.between(rnd, 15, 18); m.tensionDia = C.between(rnd, 9, 11); }
        if (quoi === 'spo2') { m.spo2 = C.between(rnd, 88, 93); m.fr = C.between(rnd, 22, 28); }
      }
      m.tension = m.tensionSys + '/' + m.tensionDia;
      m.imc = Math.round((m.poids / Math.pow(m.taille / 100, 2)) * 10) / 10;
      return m;
    }

    function inserer(p, dateHeure, m, agent, extra) {
      var h = Number(String(dateHeure).slice(11, 13));
      cst.insert(Object.assign({
        reference: 'CST-' + C.pad(cst.all().length + 1, 5),
        patientCode: p.code, patientId: p.id, patient: p.nom + ' ' + p.prenom,
        dateHeure: dateHeure,
        moment: h < 12 ? 'matin' : (h < 15 ? 'midi' : 'soir'),
        temperature: m.temperature, tensionSys: m.tensionSys, tensionDia: m.tensionDia, tension: m.tension,
        pouls: m.pouls, fr: m.fr, spo2: m.spo2, poids: m.poids, taille: m.taille, imc: m.imc,
        releveePar: agent || 'Accueil',
        origine: 'accueil',
      }, extra || {}));
      n++;
    }

    /* --- Les dossiers de consultation : leur relevé, et leur zone 1 --- */
    dos.active().forEach(function (dr) {
      var p = S().collection('patients').get(dr.patientId);
      if (!p) return;
      var hm = /(\d{1,2})h(\d{2})/.exec(dr.heureArrivee || '') || [null, '08', '30'];
      var dateHeure = String(dr.dateArrivee).slice(0, 10) + 'T' + C.pad(hm[1], 2) + ':' + hm[2];
      var m;
      if (dr.temperature != null && dr.tension) {
        var ta = String(dr.tension).split('/');
        m = {
          temperature: dr.temperature, tensionSys: Number(ta[0]), tensionDia: Number(ta[1]), tension: dr.tension,
          pouls: dr.pouls, fr: C.between(rnd, 14, 20), spo2: dr.spo2, poids: dr.poids, taille: dr.taille,
          imc: dr.imc != null ? dr.imc : Math.round((dr.poids / Math.pow(dr.taille / 100, 2)) * 10) / 10,
        };
      } else {
        m = mesure(p, null, rnd() > 0.85);
        dos.update(dr.id, {
          temperature: m.temperature, tension: m.tension, pouls: m.pouls, spo2: m.spo2,
          poids: m.poids, taille: m.taille, imc: m.imc,
        });
        zone1++;
      }
      inserer(p, dateHeure, m, dr.recuPar, { dossierId: dr.id });
    });

    /* --- Des patients suivis : plusieurs relevés dans le temps --------- */
    var suivis = (fichesDemo || []).slice();
    patients().filter(function (p) { return !p.externe; }).forEach(function (p, i) {
      if (i % 9 === 4 && suivis.indexOf(p) === -1) suivis.push(p);
    });
    suivis.slice(0, 22).forEach(function (p) {
      var base = mesure(p, null, false);
      var combien = C.between(rnd, 2, 4);
      var recul = C.between(rnd, 60, 150);
      for (var k = 0; k < combien; k++) {
        var agent = unDe(rnd, recus);
        var jourR = C.addDays(FIN, -Math.max(0, recul - k * C.between(rnd, 15, 45)));
        inserer(p, C.iso(jourR) + 'T' + C.pad(C.between(rnd, 7, 16), 2) + ':' + C.pad(C.between(rnd, 0, 59), 2),
          mesure(p, base, rnd() > 0.82), agent ? agent.nomComplet : 'Accueil');
      }
    });
    return { releves: n, zone1Completees: zone1 };
  }

  /* --------------------------------------------------------------------------
   * 5. DES FICHES PATIENT COMPLÈTES (m1-patient-profil)
   * --------------------------------------------------------------------------
   * Dix dossiers choisis pour que chaque onglet de la fiche ait quelque chose
   * à montrer : hommes et femmes, assurés (carte valide et expirée) et non
   * assurés, un agent pris en charge par la clinique, une femme enceinte, une
   * accouchée et un patient externe. On COMPLÈTE ce que le parcours de soin
   * leur a donné ; on ne remplace rien. Les codes retenus sont notés au
   * magasin (`_fichesDemo`) pour qu’on puisse les ouvrir sans les chercher.
   * ----------------------------------------------------------------------- */
  function choisirFichesDemo() {
    var st = S();
    var tous = patients();
    var cols = ['consultations', 'admissions', 'demandesAnalyses', 'ordonnances', 'factures', 'soins',
      'suiviMaternite', 'accouchements'];
    var score = {};
    cols.forEach(function (c) {
      st.collection(c).active().forEach(function (x) {
        if (x.patientId) score[x.patientId] = (score[x.patientId] || 0) + 1;
      });
    });
    function riches(liste) {
      return liste.slice().sort(function (a, b) { return (score[b.id] || 0) - (score[a.id] || 0); });
    }
    var choisis = [];
    function prendre(p) { if (p && choisis.indexOf(p) === -1) choisis.push(p); }
    /* Une carte « valide » l’est encore pour plusieurs semaines : une carte
       qui expire dans la semaine ferait changer la démonstration de camp
       d’un jour à l’autre (RG-09 se lit à la date du jour). */
    var auj = new Date(2026, 10, 1).getTime();
    function valide(p) { return p.assureur && p.carteExpiration && C.toDate(p.carteExpiration).getTime() >= auj; }

    prendre(riches(tous.filter(function (p) { return p.personnelId; }))[0]);
    var enceintes = st.collection('grossesses').active().map(function (g) { return g.patientId; });
    prendre(riches(tous.filter(function (p) { return enceintes.indexOf(p.id) !== -1; }))[0]);
    var accouchees = st.collection('accouchements').active().map(function (a) { return a.patientId; });
    prendre(riches(tous.filter(function (p) { return accouchees.indexOf(p.id) !== -1 && choisis.indexOf(p) === -1; }))[0]);
    /* Deux hommes et deux femmes parmi les assurés à carte valide. */
    ['M', 'F'].forEach(function (sexe) {
      riches(tous.filter(function (p) {
        return valide(p) && !p.personnelId && p.sexe === sexe && choisis.indexOf(p) === -1;
      })).slice(0, 2).forEach(prendre);
    });
    /* Une carte franchement EXPIRÉE (avant la date de référence du jeu) : le
       bandeau rouge de RG-09 doit avoir un dossier où se montrer. */
    prendre(riches(tous.filter(function (p) {
      return p.assureur && p.carteExpiration && !p.personnelId && choisis.indexOf(p) === -1
        && C.toDate(p.carteExpiration).getTime() < FIN.getTime();
    }))[0]);
    riches(tous.filter(function (p) { return !p.assureur && !p.externe && !p.personnelId && p.sexe === 'M'; }))
      .slice(0, 2).forEach(prendre);
    prendre(tous.filter(function (p) { return p.externe; })[0]);
    return choisis.slice(0, 11);
  }

  function fichesPatientCompletes(rnd, choisis) {
    var st = S(), pr = PR(), d = D();
    var medecins = parFonction('medecin').filter(function (a) { return !/Échographiste/i.test(a.poste || ''); });
    var infirmiers = personnel().filter(function (e) { return e.fonction === 'infirmier'; });
    var sf = personnel().filter(function (e) { return e.fonction === 'sage_femme'; });
    var caisse = parFonction('caissiere')[0];
    var meds = st.collection('produits').active().filter(function (p) { return p.stock > 40 && p.categorie === 'medicament'; });
    var lits = [];
    (d.CHAMBRES || []).forEach(function (ch) { (ch.lits || []).forEach(function (l) { lits.push({ ch: ch, lit: l }); }); });
    var fait = { consultations: 0, domicile: 0, admissions: 0, soins: 0, prescriptions: 0, resultats: 0, suivis: 0 };

    function sien(nom, p) {
      return st.collection(nom).active().filter(function (x) { return x.patientId === p.id; });
    }

    choisis.forEach(function (p, i) {
      var nomP = p.nom + ' ' + p.prenom;
      var md = medecins[i % medecins.length];

      /* LE PATIENT EXTERNE N’EST PAS SUIVI ICI : il vient avec l’ordonnance
         d’un médecin extérieur. Lui inventer consultations, séjour ou
         ordonnance maison contredirait ce qui fait de lui un externe — sa
         fiche montre ses examens, ses pièces et ses factures, rien d’autre. */
      if (p.externe) {
        sien('demandesAnalyses', p).forEach(function (x) {
          if (x.etatAnalyse !== 'valide' || x.resultat) return;
          st.collection('demandesAnalyses').update(x.id, resultatStructure(rnd, x.analyse, false) || {});
        });
        return;
      }

      /* --- Médical : des consultations au registre ----------------------- */
      var consult = sien('consultations', p);
      if (!consult.some(function (c) { return c.type !== 'Domicile'; })) {
        [C.between(rnd, 50, 120), C.between(rnd, 5, 40)].forEach(function (recul, k) {
          st.collection('consultations', { module: 'M2', entite: 'consultation', prefix: 'CONS' }).insert({
            reference: 'C' + C.pad(st.collection('consultations').all().length + 1, 5),
            patientId: p.id, patient: nomP, patientCode: p.code,
            medecinId: md.id, medecin: md.nomComplet,
            date: horodatage(C.addDays(FIN, -recul), C.between(rnd, 8, 16), 30),
            motif: k ? 'Contrôle' : C.pick(rnd, ['Fièvre', 'Céphalées', 'Douleurs abdominales', 'Toux persistante']),
            diagnostic: k ? 'Évolution favorable' : C.pick(rnd, ['Paludisme simple', 'Gastrite', 'Bronchite aiguë', 'HTA essentielle']),
            type: k ? 'Contrôle' : 'Consultation', tarif: k ? 3000 : 5000, statut: 'terminee',
          });
          fait.consultations++;
        });
      }
      /* --- À domicile ---------------------------------------------------- */
      if (!consult.some(function (c) { return c.type === 'Domicile'; }) && !p.externe) {
        st.collection('consultations').insert({
          reference: 'C' + C.pad(st.collection('consultations').all().length + 1, 5),
          patientId: p.id, patient: nomP, patientCode: p.code,
          medecinId: md.id, medecin: md.nomComplet,
          date: horodatage(C.addDays(FIN, -C.between(rnd, 10, 70)), C.between(rnd, 15, 18), 0),
          motif: C.pick(rnd, ['Soins de plaie à domicile', 'Visite d’un patient alité', 'Perfusion à domicile']),
          diagnostic: C.pick(rnd, ['Plaie en voie de cicatrisation', 'Asthénie du sujet âgé', 'Déshydratation modérée']),
          type: 'Domicile', tarif: 10000, fraisDeplacement: 5000,
          adresseIntervention: (p.quartier || 'Natitingou') + ', Natitingou', statut: 'terminee',
        });
        fait.domicile++;
      }

      /* --- Hospitalisation et soins -------------------------------------- */
      var adm = sien('admissions', p);
      if (!adm.length && !p.externe && lits.length) {
        var slot = lits[(i * 3) % lits.length];
        var inf = unDe(rnd, infirmiers);
        var entree = C.addDays(FIN, -C.between(rnd, 20, 100));
        /* Un séjour CLOS : un lit ne porte qu’une admission active, et le jeu
           en occupe déjà. Le séjour terminé se relit au dossier sans rien
           prendre au plan des lits. */
        adm = [st.collection('admissions').insert({
          reference: 'H' + C.pad(st.collection('admissions').all().length + 1, 5),
          patientId: p.id, patient: nomP, patientCode: p.code,
          chambre: slot.ch.code, lit: slot.lit.label, typeChambre: slot.ch.type,
          dateEntree: C.iso(entree), dateSortie: C.iso(C.addDays(entree, C.between(rnd, 2, 6))),
          diagnosticEntree: C.pick(rnd, ['Paludisme grave', 'Gastro-entérite avec déshydratation', 'Pneumopathie aiguë']),
          symptomes: 'Altération de l’état général',
          priseEnCharge: 'plus_8h', infirmierId: inf ? inf.id : null, infirmier: inf ? inf.nomComplet : '—',
          statut: 'sortie',
        }).record];
        fait.admissions++;
      }
      if (adm.length && !sien('soins', p).length) {
        var a = adm[0];
        var jour0 = C.toDate(a.dateEntree);
        ['Prise des constantes', 'Pose de perfusion', 'Administration du traitement IV'].forEach(function (acte, k) {
          var prod = k === 2 ? unDe(rnd, meds) : null;
          st.collection('soins').insert({
            date: C.iso(C.addDays(jour0, k ? 1 : 0)), heure: C.pad(8 + k * 4, 2) + ':00',
            admissionId: a.id, patientId: p.id, patient: nomP, patientCode: p.code, lit: a.lit,
            acte: acte, produit: prod ? prod.designation : '', quantite: prod ? 1 : 0,
            soignant: a.infirmier, observations: '', etat: 'realise', statut: 'actif',
          });
          fait.soins++;
        });
      }

      /* --- Analyses : au moins un résultat RENDU ------------------------ */
      /* La fiche n’affiche que ce que le prescripteur peut lire (les deux
         verrous du laboratoire) : un patient dont toutes les analyses sont
         en cours montre un onglet vide. Une demande déjà RÉGLÉE avance sur
         son circuit plutôt que d’en ouvrir une nouvelle. */
      var analysesP = sien('demandesAnalyses', p);
      var aRendre = analysesP.some(function (x) { return x.etatAnalyse === 'valide'; }) ? null
        : analysesP.filter(function (x) { return !x.bloqueParPaiement; })[0];
      if (aRendre) {
        avancerAnalyse(aRendre, 'rendu', C.addDays(C.toDate(String(aRendre.dateHeure).slice(0, 10)), 1), rnd, i % 3 === 0);
      }

      /* --- Ordonnances, analyses et facture : par le parcours ----------- */
      if (!sien('ordonnances', p).length || !sien('demandesAnalyses', p).some(function (x) { return x.etatAnalyse === 'valide'; })) {
        var codes = ['GE-DP / FROTTIS SANGUIN', 'NFS COMPLETE (HEMOGRAMME)']
          .map(analyseParDesignation).filter(Boolean).map(function (x) { return x.code; });
        var prod2 = unDe(rnd, meds);
        var dateP = C.addDays(FIN, -C.between(rnd, 8, 30));
        try {
          var ord = pr.prescrire({
            patientCode: p.code, medecin: md.nomComplet, date: horodatage(dateP, 10, 15),
            diagnostic: 'Syndrome fébrile — bilan', analyses: codes,
            medicaments: prod2 ? [{ produitId: prod2.id, quantite: 2, posologie: '1 cp x 3/j', duree: '5 jours' }] : [],
          });
          fait.prescriptions++;
          var facP = st.collection('factures').active().filter(function (f) { return f.ordonnanceId === ord.ordonnance.id; })[0];
          if (facP) {
            pr.encaisser(facP.id, {
              lignes: pr.lignesDues(facP).map(function (l) { return l.id; }), mode: 'especes',
              utilisateur: caisse ? caisse.nomComplet : 'Caisse',
            });
          }
          st.collection('demandesAnalyses').active().filter(function (x) {
            return x.ordonnanceId === ord.ordonnance.id && !x.bloqueParPaiement;
          }).forEach(function (x, k) {
            avancerAnalyse(x, k === 0 ? 'rendu' : 'technique', C.addDays(dateP, 1), rnd, i % 3 === 0);
          });
        } catch (e) { console.warn('[SEED] fiche', p.code, e.message); }
      }
      /* Les résultats RENDUS du parcours de soin portaient un état sans
         valeur : la colonne « Résultat » de la fiche restait vide. Ils
         reçoivent le résultat structuré que la saisie aurait écrit. */
      sien('demandesAnalyses', p).forEach(function (x) {
        if ((x.etatAnalyse !== 'valide' && x.etatAnalyse !== 'valide_technique') || x.resultat) return;
        var res = resultatStructure(rnd, x.analyse, rnd() > 0.7)
          || { resultat: 'Résultat disponible — voir le compte rendu', conclusion: 'Normal' };
        st.collection('demandesAnalyses').update(x.id, res);
        fait.resultats++;
      });

      /* --- Maternité : la femme enceinte et l’accouchée ------------------ */
      if (p.sexe === 'F' && !sien('suiviMaternite', p).length) {
        var gro = sien('grossesses', p)[0];
        var acc = sien('accouchements', p)[0];
        if (gro || acc) {
          var terme = gro ? gro.termeSA : 36;
          var base = acc ? C.toDate(acc.dateHeure) : FIN;
          [3, 1].forEach(function (ecart, k) {
            var t = Math.max(8, terme - ecart * 4);
            st.collection('suiviMaternite').insert({
              patientId: p.id, patient: nomP, patientCode: p.code,
              date: C.iso(C.addDays(base, -(terme - t) * 7 - (acc ? 14 : 0))),
              dpa: gro ? gro.dpa : C.iso(base), termeSA: t,
              poids: 58 + k * 3, cpn: k + 2, groupeSanguin: p.groupeSanguin,
              risque: 'Standard', sageFemme: sf.length ? sf[k % sf.length].nomComplet : '—',
              observations: k ? 'Grossesse évolutive, bruits du cœur fœtal perçus' : 'Grossesse évolutive normale',
            });
            fait.suivis++;
          });
        }
      }

      /* --- Traçabilité : une mise à jour réelle du dossier, datée et signée
             par le magasin (RG-12) — la personne à prévenir confirmée à
             l’accueil lors de la dernière venue. -------------------------- */
      st.collection('patients').update(p.id, {
        personneAPrevenir: p.personneAPrevenir || 'Conjoint(e) — à confirmer',
      });
    });
    return fait;
  }

  /* ==========================================================================
   * ACHATS & FOURNISSEURS — REMONTÉS AU SOCLE (22/09/2026)
   * --------------------------------------------------------------------------
   * Ces quatre registres étaient amorcés PAR LEURS ÉCRANS, et c'était tenable
   * tant que M7 se lisait seul. Le BFR les lit désormais depuis la
   * comptabilité, depuis le pilotage et depuis le moteur d'alertes : sur un
   * poste qui n'a jamais ouvert « Factures fournisseurs », la dette
   * fournisseur valait ZÉRO, et le besoin en fonds de roulement s'en trouvait
   * SURESTIMÉ d'autant. Un tableau de bord qui se trompe dans ce sens est
   * plus dangereux qu'un tableau de bord absent — c'est la leçon des
   * échéances fiscales, payée une fois de plus.
   *
   * LA GRAINE EST CELLE DE L'ÉCRAN (911) : le jeu engendré ici est donc
   * EXACTEMENT celui que M7 produisait, au même ordre et aux mêmes montants.
   * Et parce qu'elle lui est propre, l'insertion ne décale aucun tirage des
   * sections voisines — les registres déjà semés restent ce qu'ils étaient.
   * ======================================================================== */
  var SERVICES_DEMANDEURS = ['Pharmacie d’urgence', 'Laboratoire', 'Hospitalisation', 'Maternité',
    'Bloc opératoire', 'Accueil', 'Administration', 'Entretien'];
  var ETAPES_BESOIN = ['brouillon', 'soumis', 'controle_stock', 'validation_da',
    'accorde', 'prepare', 'livre', 'cloture'];

  /**
   * @param {boolean} [complet] vrai depuis M7 : ajoute les BONS DE BESOINS.
   *   Le socle ne sème que ce que le BFR lit — commandes, livraisons et
   *   factures fournisseurs. Les bons ne pèsent sur aucun agrégat transverse,
   *   et le magasin du navigateur est à 275 Ko de son plafond : on ne sème au
   *   socle que ce qui doit y être.
   */
  function semerAchats(complet) {
    var st = S(), Dd = D();
    var AUJ = new Date(2026, 7, 16);
    var besoins = st.collection('besoins', { module: 'M7', entite: 'BonExpressionBesoin' });
    var cmds = st.collection('commandes', { module: 'M7', entite: 'BonCommande' });
    var livs = st.collection('livraisons', { module: 'M7', entite: 'BonLivraison' });
    var ff = st.collection('facturesFournisseurs', { module: 'M7', entite: 'FactureFournisseur' });
    var fait = { besoins: 0, commandes: 0, livraisons: 0, facturesFournisseurs: 0 };
    var prods = st.collection('produits').active();
    if (!prods.length) return fait;

    if (!cmds.all().length || (complet && !besoins.all().length)) {
      var rnd = C.seeded(911);
      for (var i = 0; complet && i < 20; i++) {
        var etape = C.pick(rnd, ETAPES_BESOIN);
        var nb = C.between(rnd, 1, 5);
        var lignes = [];
        for (var k = 0; k < nb; k++) {
          var p = C.pick(rnd, prods);
          var dem = C.between(rnd, 5, 120);
          var acc = ['brouillon', 'soumis', 'controle_stock', 'validation_da'].indexOf(etape) !== -1
            ? null : Math.round(dem * (0.6 + rnd() * 0.4));
          lignes.push({
            produitId: p.id, produit: p.designation, unite: p.unite,
            quantiteDemandee: dem, quantiteAccordee: acc,
            quantiteLivree: ['livre', 'cloture'].indexOf(etape) !== -1 ? acc : null,
            prixAchat: p.prixAchat,
          });
        }
        besoins.all().push({
          id: 'BEB' + C.pad(i + 1, 4), statut: 'actif',
          reference: 'BEB-2026-' + C.pad(i + 1, 4),
          date: C.iso(C.addDays(AUJ, -C.between(rnd, 0, 180))),
          service: C.pick(rnd, SERVICES_DEMANDEURS),
          demandeur: C.pick(rnd, ['MAMAN Zoukanéri', 'DIEYABIDI Aïssatou', 'KINNOU Addoul Ganiou', 'GARBA Yahouza']),
          etape: etape,
          motif: C.pick(rnd, ['Réapprovisionnement mensuel', 'Rupture constatée', 'Besoin exceptionnel', 'Dotation de service']),
          lignes: lignes,
          montantEstime: C.sum(lignes, function (l) { return l.quantiteDemandee * l.prixAchat; }),
          valideePar: ['validation_da', 'accorde', 'prepare', 'livre', 'cloture'].indexOf(etape) !== -1 ? 'TAKI Alimatou' : null,
        });
        fait.besoins++;
      }

      for (var j = 0; j < 15; j++) {
        var f = C.pick(rnd, Dd.FOURNISSEURS);
        /* DEUX À QUATRE LIGNES, et non deux à sept : les lignes sont le poste
           le plus lourd de ce que le socle sème — elles sont recopiées une
           seconde fois sur le bon de livraison. Le magasin du navigateur est à
           sa marge, et une commande de quatre références montre exactement la
           même chose qu'une commande de sept. */
        var nbL = C.between(rnd, 2, 4);
        var lignesC = [];
        for (var m = 0; m < nbL; m++) {
          var pc = C.pick(rnd, prods);
          var q = C.between(rnd, 10, 300);
          lignesC.push({ produitId: pc.id, produit: pc.designation, unite: pc.unite, quantite: q, prixUnitaire: pc.prixAchat, montant: q * pc.prixAchat });
        }
        /* LES HUIT PREMIÈRES COMMANDES SONT LIVRÉES, ET C'EST DÉLIBÉRÉ.
           Le statut tiré au sort ne donnait que deux bons de livraison sur
           quinze — donc deux factures fournisseurs, donc une dette de
           fournisseur que le BFR affichait comme anecdotique. Un jeu de
           démonstration doit montrer ce qu'il sert à montrer. Le tirage
           reste consommé pour les autres, l'ordre des suivantes ne bouge
           pas. */
        var tirage = C.pick(rnd, ['brouillon', 'attente_validation', 'validee', 'validee', 'transmise', 'livree', 'soldee']);
        var statutC = j < 8 ? (j % 2 ? 'soldee' : 'livree') : tirage;
        cmds.all().push({
          id: 'BC' + C.pad(j + 1, 4), statut: 'actif',
          reference: 'BC-2026-' + C.pad(j + 1, 4),
          date: C.iso(C.addDays(AUJ, -C.between(rnd, 0, 200))),
          fournisseur: f.code, fournisseurNom: f.nom,
          lignes: lignesC, montant: C.sum(lignesC, 'montant'),
          statutCommande: statutC,
          valideePar: ['validee', 'transmise', 'livree', 'soldee'].indexOf(statutC) !== -1 ? 'TAKI Alimatou' : null,
          dateValidation: ['validee', 'transmise', 'livree', 'soldee'].indexOf(statutC) !== -1 ? C.iso(C.addDays(AUJ, -C.between(rnd, 0, 190))) : null,
          delaiLivraison: f.delai,
        });
        fait.commandes++;

        if (['livree', 'soldee'].indexOf(statutC) !== -1) {
          var ecart = rnd() > 0.75;
          livs.all().push({
            id: 'BL' + C.pad(j + 1, 4), statut: 'actif',
            reference: '26LNA' + C.pad(C.between(rnd, 1, 99999), 5),
            commandeRef: 'BC-2026-' + C.pad(j + 1, 4),
            date: C.iso(C.addDays(AUJ, -C.between(rnd, 0, 180))),
            fournisseur: f.code, fournisseurNom: f.nom,
            lignes: lignesC.map(function (l) {
              var livree = ecart && rnd() > 0.6 ? Math.max(0, l.quantite - C.between(rnd, 1, 20)) : l.quantite;
              return Object.assign({}, l, { quantiteLivree: livree, ecart: livree - l.quantite });
            }),
            montant: C.sum(lignesC, 'montant'),
            controlePar: ['MAMAN Zoukanéri', 'DIEYABIDI Aïssatou'],
            statutReception: ecart ? 'ecart' : 'conforme',
          });
          fait.livraisons++;
        }
      }
    }

    /* LA FACTURE FOURNISSEUR NAÎT DU BON DE LIVRAISON — c'est ce
       rapprochement qui fait sa valeur, et c'est lui que le comptable
       contrôle avant de régler. */
    if (!ff.all().length) {
      var rndF = C.seeded(1013);
      st.collection('livraisons').active().forEach(function (l, i) {
        var anomalie = rndF() > 0.75;
        var montantFacture = anomalie ? Math.round(l.montant * (1 + (rndF() - 0.5) * 0.12)) : l.montant;
        ff.all().push({
          id: 'FF' + C.pad(i + 1, 4), statut: 'actif',
          reference: 'FF-2026-' + C.pad(i + 1, 4),
          numeroFournisseur: 'FN' + C.between(rndF, 100000, 999999),
          date: l.date, blRef: l.reference, commandeRef: l.commandeRef,
          fournisseur: l.fournisseur, fournisseurNom: l.fournisseurNom,
          montantLivraison: l.montant, montantFacture: montantFacture,
          ecart: montantFacture - l.montant,
          statutRappro: anomalie ? 'anomalie' : 'rapproche',
          statutPaiement: C.pick(rndF, ['impayee', 'payee', 'payee', 'partielle']),
          echeance: C.iso(C.addDays(l.date, 30)),
        });
        fait.facturesFournisseurs++;
      });
    }
    return fait;
  }

  /* ==========================================================================
   * ORCHESTRATION
   * ======================================================================== */
  function peupler(force) {
    var db = S().raw();
    if (db._parcoursAmorces && !force) return null;

    var rnd = C.seeded(20260826);
    var bilan = {};

    /* Tout le peuplement se fait EN LOT : sans cela, chaque insertion
       sérialiserait le magasin entier et l'opération dépasserait la minute. */
    return S().enLot(function () {

      try { bilan.soins = parcoursDeSoin(rnd, 130); } catch (e) { console.error('[SEED] parcours de soin', e); }
      try { bilan.soinsPrescrits = prescriptionsDeSoins(rnd, 65); } catch (e) { console.error('[SEED] soins', e); }
      try { bilan.cliniques = piecesCliniques(rnd); } catch (e) { console.error('[SEED] pièces cliniques', e); }
      try { bilan.imagerie = imagerie(rnd); } catch (e) { console.error('[SEED] imagerie', e); }
      try { bilan.accueil = accueil(rnd); } catch (e) { console.error('[SEED] accueil', e); }
      try { bilan.certificats = piecesCertifiantes(rnd); } catch (e) { console.error('[SEED] certificats', e); }
      try { bilan.rh = ressourcesHumaines(rnd); } catch (e) { console.error('[SEED] RH', e); }
      try { bilan.maternite = maternite(); } catch (e) { console.error('[SEED] maternité', e); }
      try { bilan.administration = administration(rnd); } catch (e) { console.error('[SEED] administration', e); }
      try { bilan.facturesMere = facturesMere(rnd); } catch (e) { console.error('[SEED] factures mères', e); }
      try { bilan.transferts = transfertsGrosDetail(); } catch (e) { console.error('[SEED] transferts gros → détail', e); }
      try { bilan.achats = semerAchats(); } catch (e) { console.error('[SEED] achats & fournisseurs', e); }
      try { bilan.notifications = notifications(rnd); } catch (e) { console.error('[SEED] notifications', e); }
      try { bilan.gestes = gestesDePoste(); } catch (e) { console.error('[SEED] gestes de poste', e); }

      /* Vague 61 — APRÈS la journée des postes, et sur leur propre suite
         pseudo-aléatoire : les tirages des registres antérieurs restent ceux
         qu’ils étaient, et les états posés ici ne sont pas soldés derrière. */
      var rnd61 = C.seeded(20260914);
      try { bilan.externes = externesSeed(rnd61); } catch (e) { console.error('[SEED] patients externes', e); }
      try { bilan.certificatsExternes = certificatsExternesSeed(rnd61); } catch (e) { console.error('[SEED] certificats externes', e); }
      try { bilan.demandesImagerie = demandesImagerieSeed(rnd61); } catch (e) { console.error('[SEED] demandes d’imagerie', e); }
      var fichesDemo = [];
      try {
        fichesDemo = choisirFichesDemo();
        bilan.fiches = fichesPatientCompletes(rnd61, fichesDemo);
        db._fichesDemo = fichesDemo.map(function (p) { return p.code; });
      } catch (e) { console.error('[SEED] fiches patient', e); }
      try { bilan.constantes = constantesAccueilSeed(rnd61, fichesDemo); } catch (e) { console.error('[SEED] constantes', e); }

      db._parcoursAmorces = true;
      db._parcoursAmorcesLe = new Date().toISOString();
      return bilan;
    });
  }

  /* ==========================================================================
   * VAGUE 51 \u2014 LA JOURN\u00c9E DES POSTES : les gestes de validation sont FAITS
   * --------------------------------------------------------------------------
   * Le jeu de d\u00e9monstration figurait un \u00e9tablissement o\u00f9 personne n'avait
   * valid\u00e9 depuis des mois \u2014 220 brouillons, 25 validations biologiques en
   * souffrance. La Direction a demand\u00e9 de passer aux donn\u00e9es r\u00e9elles : les
   * postes ont fait leurs gestes, il reste le FLUX COURANT \u2014 les files
   * r\u00e9siduelles montrent l'usage des \u00e9crans sans figurer l'abandon.
   * Chaque geste porte son auteur et sa date, comme s'il avait \u00e9t\u00e9 fait \u00e0
   * l'\u00e9cran \u2014 parce que c'est ce qu'il figure.
   * ======================================================================== */
  function gestesDePoste() {
    var fait = { ecritures: 0, bios: 0, cr: 0, besoins: 0, commandes: 0, mecef: 0, echeances: 0 };
    var st = S();

    /* Le comptable valide \u2014 les 15 plus r\u00e9centes restent en brouillon :
       c'est le flux du jour, pas un arri\u00e9r\u00e9. */
    /* ON VALIDE UNE PIÈCE, JAMAIS UNE LIGNE : la validation ligne à ligne
       coupait une écriture en deux au hasard de la découpe — une moitié
       validée, l'autre en brouillon — et la balance sortait boiteuse sans
       que rien ne le signale (RG-10). */
    var brouillons = st.collection('ecritures').active()
      .filter(function (e) { return e.statut === 'brouillon'; })
      .sort(function (a, b) { return String(a.date).localeCompare(String(b.date)); });
    var pieces = [], vues = {};
    brouillons.forEach(function (e) {
      var cle = e.numero || e.id;
      if (vues[cle]) { vues[cle].push(e); return; }
      vues[cle] = [e]; pieces.push(cle);
    });
    /* Une quinzaine de LIGNES restent en brouillon : c'est le flux du jour,
       pas un arriéré. On s'arrête sur une pièce entière. */
    var restant = 0, aValider = [];
    for (var p = pieces.length - 1; p >= 0; p--) {
      if (restant >= 15) { aValider.unshift(pieces[p]); continue; }
      restant += vues[pieces[p]].length;
    }
    aValider.forEach(function (cle) {
      vues[cle].forEach(function (e) {
        st.collection('ecritures').update(e.id, {
          statut: 'validee', valideLe: '2026-09-01', validePar: 'KASSA Augustin',
        });
        fait.ecritures++;
      });
    });

    /* Le biologiste rend \u2014 cinq r\u00e9sultats restent en relecture. */
    var bios = st.collection('demandesAnalyses').active()
      .filter(function (d) { return d.etatAnalyse === 'valide_technique'; })
      .sort(function (a, b) { return String(a.dateHeure).localeCompare(String(b.dateHeure)); });
    bios.slice(0, Math.max(0, bios.length - 5)).forEach(function (d) {
      st.collection('demandesAnalyses').update(d.id, {
        etatAnalyse: 'valide',
        valideLe: '2026-09-01T10:00:00.000Z',
        valideBiologiquePar: 'Biologiste m\u00e9dical',
      });
      fait.bios++;
    });

    /* L'\u00e9chographiste rend ses comptes rendus \u2014 quatre restent en
       r\u00e9daction. La demande li\u00e9e suit son CR. */
    var crs = st.collection('resultatsImagerie').active()
      .filter(function (r) { return r.statut !== 'rendu' && r.conclusion; })
      .sort(function (a, b) { return String(a.date).localeCompare(String(b.date)); });
    crs.slice(0, Math.max(0, crs.length - 4)).forEach(function (r) {
      st.collection('resultatsImagerie').update(r.id, {
        statut: 'rendu', renduLe: '2026-09-01T11:00:00.000Z',
      });
      if (r.demandeImagerieId) {
        var di = st.collection('demandesImagerie').get(r.demandeImagerieId);
        if (di) st.collection('demandesImagerie').update(di.id, { statut: 'validee', valideLe: '2026-09-01' });
      }
      fait.cr++;
    });

    /* La DA valide bons et commandes \u2014 cinq bons et trois commandes
       restent au circuit. */
    var besoins = st.collection('besoins').active()
      .filter(function (b) { return ['soumis', 'controle_stock', 'validation_da'].indexOf(b.etape) !== -1; })
      .sort(function (a, b) { return String(a.date).localeCompare(String(b.date)); });
    besoins.slice(0, Math.max(0, besoins.length - 5)).forEach(function (b) {
      st.collection('besoins').update(b.id, {
        etape: 'accorde', valideePar: 'TAKI Alimatou', valideeLe: '2026-09-01',
        lignes: (b.lignes || []).map(function (l) {
          return Object.assign({}, l, {
            quantiteAccordee: l.quantiteAccordee != null ? l.quantiteAccordee
              : Math.round(l.quantiteDemandee * 0.8),
          });
        }),
      });
      fait.besoins++;
    });
    var cmds = st.collection('commandes').active()
      .filter(function (x) { return x.statutCommande === 'attente_validation'; })
      .sort(function (a, b) { return String(a.date).localeCompare(String(b.date)); });
    cmds.slice(0, Math.max(0, cmds.length - 3)).forEach(function (x) {
      st.collection('commandes').update(x.id, {
        statutCommande: 'validee', valideePar: 'TAKI Alimatou', dateValidation: '2026-09-01',
      });
      fait.commandes++;
    });

    /* La normalisation MECeF \u2014 quatre pi\u00e8ces restent en attente. */
    var mecef = st.collection('factures').active()
      .filter(function (fa) { return fa.statutMecef === 'en_attente' && fa.numeroMecef; })
      .sort(function (a, b) { return String(a.date).localeCompare(String(b.date)); });
    mecef.slice(0, Math.max(0, mecef.length - 4)).forEach(function (fa) {
      st.collection('factures').update(fa.id, { statutMecef: 'valide' });
      fait.mecef++;
    });

    /* Les \u00e9ch\u00e9ances d\u00e9pass\u00e9es sont r\u00e9gl\u00e9es \u2014 SAUF UNE : l'alarme du
       tableau de bord doit avoir quelque chose \u00e0 montrer, et un z\u00e9ro
       permanent endormirait la vigilance. */
    var depassees = st.collection('echeancesFiscales').active()
      .filter(function (e) { return !e.paye && e.echeance < '2026-08-16'; })
      .sort(function (a, b) { return String(a.echeance).localeCompare(String(b.echeance)); });
    depassees.slice(0, Math.max(0, depassees.length - 1)).forEach(function (e) {
      st.collection('echeancesFiscales').update(e.id, {
        paye: true, payeLe: '2026-09-01', payePar: 'KASSA Augustin',
        quittance: 'QUIT-2026-' + String(e.id).replace(/\D/g, '').slice(-4),
      });
      fait.echeances++;
    });

    return fait;
  }

  global.SIGH.semerAchats = semerAchats;
  global.SIGH.peuplerParcours = peupler;
  global.SIGH.PERIODE_SEED = { debut: C.iso(DEBUT), fin: C.iso(FIN), jours: JOURS };
})(window);
