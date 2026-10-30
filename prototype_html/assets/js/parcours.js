/* =============================================================================
 * PARCOURS — chaîne transactionnelle inter-modules
 * -----------------------------------------------------------------------------
 * draf1 §24-25 : le prototype ne se juge pas au nombre d'écrans mais à sa
 * capacité à faire traverser plusieurs modules à une même opération. Ce fichier
 * porte cette traversée, décrite par la Direction :
 *
 *   le médecin prescrit  →  le gestionnaire de stock est informé des médicaments
 *                        →  le laborantin est informé des analyses, la demande
 *                           est établie d'office (la saisie manuelle reste
 *                           possible pour les patients venus de l'extérieur)
 *                        →  la caisse est informée, le patient règle, la caisse
 *                           valide  →  les médicaments sont délivrés et le
 *                           prélèvement est autorisé.
 *
 * Il est chargé sur toutes les pages, juste après `store` : la chaîne doit
 * fonctionner depuis la consultation comme depuis la caisse ou la pharmacie,
 * alors que chaque page ne charge que le module de son écran.
 *
 * Règles de gestion appliquées ici :
 *   RG-02  médicaments facturés au prix d'achat, sans marge ;
 *   RG-03  toute sortie porte un justificatif, le stock ne devient jamais négatif ;
 *   RG-12  chaque étape est journalisée, aucune action anonyme ;
 *   RG-14  rien n'est supprimé, tout est archivé.
 * ========================================================================== */
(function (global) {
  'use strict';
  var C = global.SIGH.core, S = global.SIGH.store, D = global.SIGH.data;

  /* --- Files d'attente : à qui l'information est adressée ------------------ */
  var TACHES = {
    encaissement: {
      role: 'caissier', module: 'M8', ecran: 'm8-caisse',
      titre: 'Encaisser la prescription', icon: 'coins',
    },
    dispensation: {
      role: 'pharmacien', module: 'M6', ecran: 'm6-dispensation',
      titre: 'Délivrer les médicaments', icon: 'pill',
    },
    prelevement: {
      role: 'laborantin', module: 'M5', ecran: 'm5-demandes',
      titre: 'Prélever et analyser', icon: 'flask-conical',
    },
    acte: {
      role: 'infirmier', module: 'M3', ecran: 'm3-soins',
      titre: 'Exécuter les actes prescrits', icon: 'stethoscope',
    },
    /* Refonte Zone 2 : l'imagerie prescrite depuis la fiche de consultation
       entre dans la même chaîne que le prélèvement — informée tout de suite,
       exécutable après encaissement. */
    imagerie: {
      role: 'echographiste', module: 'M2', ecran: 'm2-dashboard-imagerie',
      titre: 'Réaliser l’examen d’imagerie', icon: 'scan-line',
    },
  };

  function col(nom) { return S.collection(nom, META[nom] || {}); }
  var META = {
    ordonnances: { module: 'M2', entite: 'ordonnance', prefix: 'ORD' },
    taches: { module: 'M14', entite: 'tâche', prefix: 'TCH' },
    demandesAnalyses: { module: 'M5', entite: 'demande d’analyse', prefix: 'DEM' },
    factures: { module: 'M8', entite: 'facture', prefix: 'FAC' },
    mouvements: { module: 'M6', entite: 'mouvement de stock', prefix: 'MVT' },
    prescriptions: { module: 'M2', entite: 'prescription', prefix: 'PRS' },
    administrations: { module: 'M3', entite: 'administration de traitement', prefix: 'ADM' },
    soignants: { module: 'M14', entite: 'soignant', prefix: 'SOI' },
  };

  /* ==========================================================================
   * RÉFÉRENTIELS DE TRAVAIL
   * ======================================================================== */
  function patients() { return S.collection('patients').active(); }
  function produits() { return S.collection('produits').active(); }

  function patientParCode(code) {
    var t = patients().filter(function (p) { return p.code === code; });
    return t[0] || null;
  }
  function produitParId(id) {
    var t = produits().filter(function (p) { return p.id === id; });
    return t[0] || null;
  }
  function analyseParCode(code) {
    var t = D.ANALYSES.filter(function (a) { return a.code === code; });
    return t[0] || null;
  }
  function acteParCode(code) {
    /* Le catalogue des actes vit dans le MAGASIN (administrable depuis
       cfg-tarifs) ; D.ACTES n'en est que la semence. Lire la constante ici,
       c'était facturer un tarif que l'écran de configuration ne pouvait plus
       corriger. */
    var t = S.collection('actes').active().filter(function (a) { return a.code === code; });
    return t[0] || null;
  }

  /* ==========================================================================
   * 1. LE MÉDECIN PRESCRIT
   * --------------------------------------------------------------------------
   * Un seul geste engendre l'ordonnance, les demandes d'analyses, la facture et
   * les trois files d'attente. Rien n'est laissé à une ressaisie.
   * ======================================================================== */
  function prescrire(v) {
    var p = patientParCode(v.patientCode);
    if (!p) throw new Error('Patient introuvable : ' + v.patientCode);

    var date = v.date || new Date().toISOString();
    var numero = 'ORD-' + String(new Date(date).getFullYear()) + '-' + C.pad(col('ordonnances').all().length + 1, 5);

    /* --- Lignes ----------------------------------------------------------- */
    var medicaments = (v.medicaments || []).map(function (l) {
      var prod = produitParId(l.produitId) || {};
      /* RG-02 — prix d'achat, sans marge. */
      var pu = prod.prixAchat != null ? prod.prixAchat : 0;
      var q = Number(l.quantite) || 0;
      return {
        produitId: l.produitId, produit: prod.designation || l.produit || '—',
        unite: prod.unite || '', quantite: q,
        posologie: l.posologie || '', duree: l.duree || '',
        prix: pu, total: pu * q,
      };
    }).filter(function (l) { return l.quantite > 0; });

    var analyses = (v.analyses || []).map(function (code) {
      var a = analyseParCode(code) || {};
      return { code: code, designation: a.designation || code, categorie: a.categorie || '',
        echantillon: a.echantillon || '', delai: a.delai || '', prix: a.prix || 0 };
    });

    var actes = (v.actes || []).map(function (code) {
      var a = acteParCode(code) || {};
      return { code: code, libelle: a.libelle || code, secteur: a.secteur || '', prix: a.prix || 0,
        tarifValide: a.prix != null };
    });

    var mMed = C.sum(medicaments, 'total');
    var mAna = C.sum(analyses, 'prix');
    var mAct = C.sum(actes, function (a) { return a.prix || 0; });

    /* --- L'imagerie médicale (refonte Zone 2, 14/09/2026) -------------------
       La fiche de consultation prescrit l'imagerie DANS LE MÊME GESTE que les
       médicaments et les analyses, et la caisse doit recevoir UNE facture
       globale (METHODOLOGIE §1.5) — deux factures pour une même consultation
       feraient passer le patient deux fois au guichet et laisseraient la part
       assureur coupée en deux pièces. Les demandes sont créées AVANT
       l'ordonnance : un examen sans tarif est refusé en le nommant, et le
       refus ne doit laisser derrière lui ni ordonnance ni facture orpheline. */
    var imagerieCree = (v.imagerie || []).length
      ? creerDemandesImagerie(p, v.imagerie, date, {
        prescripteur: v.medecin, indication: v.indication || v.diagnostic || '',
        urgent: !!v.urgent, secteurDemandeur: v.secteurDemandeur,
        origine: v.origine || 'consultation',
        dossierConsultationId: v.dossierConsultationId || null,
      })
      : { demandes: [], lignes: [] };
    var demandesImagerie = imagerieCree.demandes;
    var imagerie = demandesImagerie.map(function (d) {
      return { code: d.examenCode, examen: d.examen, modalite: d.modalite, prix: d.prix, demandeImagerieId: d.id };
    });
    var mImg = C.sum(imagerie, 'prix');

    /* --- L'ordonnance ------------------------------------------------------ */
    var ord = col('ordonnances').insert({
      numero: numero, date: date,
      patientId: p.id, patientCode: p.code, patient: p.nom + ' ' + p.prenom,
      medecin: v.medecin, diagnostic: v.diagnostic || '', consultationId: v.consultationId || null,
      dossierConsultationId: v.dossierConsultationId || null,
      medicaments: medicaments, analyses: analyses, actes: actes, imagerie: imagerie,
      montantMedicaments: mMed, montantAnalyses: mAna, montantActes: mAct, montantImagerie: mImg,
      montant: mMed + mAna + mAct + mImg,
      urgent: !!v.urgent,
      statutPaiement: 'impayee',
      statutDispensation: medicaments.length ? 'en_attente' : 'sans_objet',
      statutAnalyses: analyses.length ? 'en_attente' : 'sans_objet',
      statutActes: actes.length ? 'en_attente' : 'sans_objet',
      statutImagerie: imagerie.length ? 'en_attente' : 'sans_objet',
    }).record;
    demandesImagerie.forEach(function (d) {
      S.collection('demandesImagerie').update(d.id, { ordonnanceId: ord.id, ordonnanceNumero: numero });
    });

    /* --- Le laboratoire : demandes établies d'office ----------------------- */
    var demandes = analyses.map(function (a) {
      return col('demandesAnalyses').insert({
        reference: C.nextRef('LAB-', 5),
        codeAnalyse: codeAnalyse(date),
        patientId: p.id, patientCode: p.code, patient: p.nom + ' ' + p.prenom,
        analyseCode: a.code, analyse: a.designation, categorie: a.categorie,
        echantillon: a.echantillon, delai: a.delai, prix: a.prix,
        dateHeure: date, prescripteur: v.medecin, laborantin: null,
        urgent: !!v.urgent, etatAnalyse: 'en_attente',
        /* Origine tracée : la demande automatique se distingue de la saisie
           manuelle du laboratoire, qui reste ouverte pour les patients
           adressés par l'extérieur. */
        origine: 'ordonnance', ordonnanceId: ord.id, ordonnanceNumero: numero,
        dossierConsultationId: v.dossierConsultationId || null,
        /* Le secteur prescripteur commande la visibilité du résultat : une
           sage-femme voit ceux de la maternité, pas ceux de la chirurgie. */
        secteurDemandeur: v.secteurDemandeur || (secteurCourant() ? secteurCourant().libelle : null),
        /* Le prélèvement n'est autorisé qu'une fois la caisse passée. */
        bloqueParPaiement: true,
      }).record;
    });

    /* --- La caisse : facture en attente de règlement ------------------------ */
    var taux = p.assureur ? (p.tauxPriseEnCharge || 0) : 0;
    var montant = mMed + mAna + mAct + mImg;
    var partAssurance = Math.round(montant * taux / 100);

    /* Les LIGNES PAYABLES. Chacune sait ce qu'elle couvre — une demande
       d'analyse, un produit, un acte, un examen d'imagerie — pour que le
       règlement de cette ligne débloque exactement ce qu'elle a payé, et rien
       d'autre. */
    var lignesFacture = construireLignes({
      medicaments: medicaments, analyses: analyses, actes: actes,
      autres: imagerieCree.lignes,
      demandes: demandes, taux: taux,
      /* L'agent de la clinique est pris en charge à 100 % par l'établissement.
         Le lien vient du dossier, il ne se saisit pas au guichet. */
      personnelId: p.personnelId || null,
    });

    /* LE TOTAL EST LA SOMME DES LIGNES, jamais un montant calculé à côté.
       C'est le défaut déjà corrigé sur les états imprimés : deux façons de
       compter la même chose divergent au premier correctif. */
    var totalLignes = C.sum(lignesFacture, 'montant');
    var totalAssureur = C.sum(lignesFacture, 'partAssureur');
    var totalPersonnel = C.sum(lignesFacture, 'partPersonnel');
    var totalRemise = C.sum(lignesFacture, 'remise');
    var duPatient = totalLignes - totalAssureur - totalPersonnel;

    var facture = col('factures').insert({
      lignes: lignesFacture,
      numero: 'FP-' + String(new Date(date).getFullYear()) + '-' + C.pad(col('factures').all().length + 1, 5),
      numeroMecef: null,
      patientId: p.id, patient: p.nom + ' ' + p.prenom, patientCode: p.code,
      date: C.iso(new Date(date)), type: 'Prescription',
      montantHT: totalLignes, montantTTC: totalLignes,
      montantBrut: C.sum(lignesFacture, 'montantBrut'), totalRemise: totalRemise,
      partPersonnel: totalPersonnel,
      priseEnChargePersonnel: !!p.personnelId, personnelId: p.personnelId || null,
      assureur: p.assureur || null, tauxPriseEnCharge: taux,
      partAssurance: totalAssureur, partPatient: duPatient,
      montantPaye: 0, reliquat: duPatient,
      modePaiement: null,
      statutPaiement: 'impayee', statutMecef: 'en_attente',
      ordonnanceId: ord.id, ordonnanceNumero: numero,
      dossierConsultationId: v.dossierConsultationId || null,
    }).record;

    col('ordonnances').update(ord.id, { factureId: facture.id, factureNumero: facture.numero });
    demandesImagerie.forEach(function (d) {
      S.collection('demandesImagerie').update(d.id, { factureId: facture.id, factureNumero: facture.numero });
    });

    /* --- Les files d'attente ---------------------------------------------- */
    var taches = [];
    taches.push(creerTache('encaissement', ord, facture, {
      detail: resumeLignes(medicaments, analyses, actes, imagerie), montant: montant, statut: 'en_attente',
    }));
    if (imagerie.length) {
      /* Le poste d'imagerie est informé tout de suite, exécutable après
         encaissement — la même règle que le prélèvement. */
      taches.push(creerTache('imagerie', ord, facture, {
        poste: 'imagerie',
        detail: imagerie.map(function (i) { return i.examen; }).join(', '),
        montant: mImg, statut: 'bloque',
      }));
      notifier({
        type: 'demande_imagerie', poste: 'imagerie',
        libelle: 'Nouvelle demande d’imagerie — ' + p.nom + ' ' + p.prenom,
        detail: imagerie.map(function (i) { return i.examen; }).join(', ')
          + ' — exécutable après passage en caisse',
        priorite: v.urgent ? 'haute' : 'normale',
        patientId: p.id, reference: facture.numero, ordonnanceId: ord.id,
      });
    }
    if (medicaments.length) {
      taches.push(creerTache('dispensation', ord, facture, {
        detail: medicaments.length + ' médicament(s) — ' + C.money(mMed, false),
        montant: mMed,
        /* Informé tout de suite, exécutable après encaissement. */
        statut: 'bloque',
      }));
    }
    if (analyses.length) {
      taches.push(creerTache('prelevement', ord, facture, {
        detail: analyses.length + ' analyse(s) — ' + analyses.map(function (a) { return a.designation; }).join(', '),
        montant: mAna, statut: 'bloque',
      }));
    }
    if (actes.length) {
      taches.push(creerTache('acte', ord, facture, {
        detail: actes.map(function (a) { return a.libelle; }).join(', '),
        montant: mAct, statut: 'bloque',
      }));
    }

    S.log('Prescription', 'M2', 'ordonnance', numero, null, {
      medicaments: medicaments.length, analyses: analyses.length, actes: actes.length,
      imagerie: imagerie.length, montant: montant,
    });

    /* L ordonnance entre au REGISTRE UNIFIÉ des prescriptions. Sans cela,
       « les prescriptions du jour » n en montreraient que la moitié : les soins
       y figureraient, les médicaments non. */
    if (medicaments.length) {
      try { inscrireOrdonnance(col('ordonnances').get(ord.id), v.origine || 'consultation'); }
      catch (e) { /* le registre est secondaire, il ne doit pas casser la prescription */ }
    }

    return {
      ordonnance: col('ordonnances').get(ord.id), demandes: demandes,
      demandesImagerie: demandesImagerie.map(function (d) { return S.collection('demandesImagerie').get(d.id); }),
      facture: facture, taches: taches,
    };
  }

  function resumeLignes(med, ana, act, img) {
    var t = [];
    if (med.length) t.push(med.length + ' médicament(s)');
    if (ana.length) t.push(ana.length + ' analyse(s)');
    if (act.length) t.push(act.length + ' acte(s)');
    if (img && img.length) t.push(img.length + ' examen(s) d’imagerie');
    return t.join(' · ') || 'Prescription sans ligne';
  }

  function creerTache(type, ord, facture, extra) {
    var def = TACHES[type];
    return col('taches').insert(Object.assign({
      type: type, role: def.role, module: def.module, ecran: def.ecran,
      titre: def.titre, icon: def.icon,
      reference: ord.numero, ordonnanceId: ord.id,
      factureId: facture ? facture.id : null, factureNumero: facture ? facture.numero : null,
      patient: ord.patient, patientCode: ord.patientCode,
      date: ord.date, urgent: !!ord.urgent,
      statut: 'en_attente', faitLe: null, faitPar: null,
    }, extra || {})).record;
  }

  /* ==========================================================================
   * 2. LA CAISSE ENCAISSE ET VALIDE
   * --------------------------------------------------------------------------
   * Le règlement débloque tout l'aval : sans lui, ni délivrance ni prélèvement.
   * ======================================================================== */
  /* ==========================================================================
   * LES DEUX VALIDATIONS D'UN RÉSULTAT
   * --------------------------------------------------------------------------
   * « Une première validation technique, puis une validation biologique. Dès
   * que nous faisons la validation biologique, le médecin a le résultat. »
   *
   * Entre les deux, le résultat existe mais reste invisible du prescripteur :
   * c'est la fenêtre de relecture. Elle n'a de sens que si personne ne lit
   * par-dessus l'épaule du laboratoire — d'où le verrou posé dans
   * peutVoirResultat().
   *
   * QUI VALIDE BIOLOGIQUEMENT : le biologiste médical. Le TSL le peut EN SON
   * ABSENCE, et l'intérim est alors tracé sur la pièce. Une clinique de trente
   * agents ne peut pas suspendre ses rendus pendant un congé ; masquer
   * l'intérim reviendrait à faire signer quelqu'un d'autre.
   * ======================================================================== */
  function validerTechnique(demandeId, opts) {
    opts = opts || {};
    var col_ = S.collection('demandesAnalyses');
    var d = col_.get(demandeId);
    if (!d) throw new Error('Demande introuvable.');
    if (!d.valeurs || !Object.keys(d.valeurs).length) {
      throw new Error('Aucun résultat saisi : il n’y a rien à valider.');
    }
    var res = col_.update(demandeId, {
      etatAnalyse: 'valide_technique',
      valideTechniqueLe: new Date().toISOString(),
      valideTechniquePar: opts.utilisateur || S.currentUser(),
    });
    S.log('Validation technique', 'M5', 'ResultatAnalyse', d.reference,
      { etat: d.etatAnalyse }, { etat: 'valide_technique' });
    return { demande: col_.get(demandeId), undo: res.undo };
  }

  /**
   * La validation biologique rend le résultat OPPOSABLE : le prescripteur le
   * voit, la clinique le remet au patient externe. C'est le point de
   * non-retour — au-delà, une correction devient une RECTIFICATION.
   */
  function validerBiologique(demandeId, opts) {
    opts = opts || {};
    var col_ = S.collection('demandesAnalyses');
    var d = col_.get(demandeId);
    if (!d) throw new Error('Demande introuvable.');
    if (d.etatAnalyse !== 'valide_technique') {
      throw new Error('La validation technique doit précéder la validation biologique.');
    }
    var cap = capacites(opts.session);
    if (!cap.validerBiologique) {
      throw new Error(cap.label + ' n’est pas habilité à porter la validation biologique.');
    }
    var interim = cap.validerBiologique === 'interim';

    var res = col_.update(demandeId, {
      etatAnalyse: 'valide',
      valideLe: new Date().toISOString(),
      valideBiologiquePar: opts.utilisateur || S.currentUser(),
      /* L'intérim est PORTÉ SUR LA PIÈCE : le compte rendu dira qui a signé
         et à quel titre. */
      validationInterim: interim,
      qualiteValidateur: interim
        ? cap.label + ' — par intérim du biologiste médical'
        : cap.label,
      version: d.version || 1,
    });
    S.log('Validation biologique', 'M5', 'ResultatAnalyse', d.reference,
      { etat: 'valide_technique' }, { etat: 'valide', interim: interim });

    /* Le prescripteur est informé que son résultat est disponible. */
    notifier({
      type: 'resultat_disponible', poste: 'prescripteur',
      destinataire: d.prescripteur,
      libelle: 'Résultat disponible — ' + d.analyse,
      detail: d.patient + ' (' + d.patientCode + ')',
      demandeId: demandeId, reference: d.reference,
      patientId: d.patientId,
    });

    return { demande: col_.get(demandeId), interim: interim, undo: res.undo };
  }

  /**
   * RECTIFIER un résultat déjà validé biologiquement.
   *
   * « Même si après on vient corriger, peut-être qu'il a déjà lu le premier,
   * et c'est pas cool. » — Exactement. La version précédente est CONSERVÉE,
   * la nouvelle est numérotée, et le prescripteur est notifié que ce qu'il a
   * lu a changé. Écraser en silence laisserait le médecin avec une valeur qui
   * n'existe plus nulle part.
   */
  function rectifierResultat(demandeId, valeurs, opts) {
    opts = opts || {};
    if (!opts.motif) throw new Error('Une rectification doit être motivée.');
    var col_ = S.collection('demandesAnalyses');
    var d = col_.get(demandeId);
    if (!d) throw new Error('Demande introuvable.');
    if (!D.resultatRendu(d.etatAnalyse)) {
      throw new Error('Ce résultat n’a pas été validé biologiquement : le corriger ne demande pas de rectification.');
    }

    var versions = (d.versions || []).slice();
    var numero = (d.version || 1);
    /* On fige la version sortante AVANT de la remplacer : c'est elle que le
       médecin a lue, et elle doit rester consultable. */
    versions.push({
      numero: numero,
      valeurs: Object.assign({}, d.valeurs),
      commentaireGeneral: d.commentaireGeneral || null,
      conclusion: d.conclusion || null,
      valideLe: d.valideLe,
      valideBiologiquePar: d.valideBiologiquePar,
      remplaceeLe: new Date().toISOString(),
      motifRemplacement: opts.motif,
    });

    var res = col_.update(demandeId, {
      valeurs: valeurs,
      versions: versions,
      version: numero + 1,
      etatAnalyse: 'rectifie',
      rectifieLe: new Date().toISOString(),
      rectifiePar: opts.utilisateur || S.currentUser(),
      motifRectification: opts.motif,
      commentaireGeneral: opts.commentaireGeneral != null ? opts.commentaireGeneral : d.commentaireGeneral,
    });

    S.log('Rectification de résultat', 'M5', 'ResultatAnalyse', d.reference,
      { version: numero, valeurs: d.valeurs }, { version: numero + 1, motif: opts.motif });

    /* LA NOTIFICATION EST LE CŒUR DU DISPOSITIF : sans elle, la rectification
       ne vaut pas mieux qu'un écrasement silencieux. */
    notifier({
      type: 'resultat_rectifie', poste: 'prescripteur',
      destinataire: d.prescripteur,
      priorite: 'haute',
      libelle: 'RÉSULTAT RECTIFIÉ — ' + d.analyse,
      detail: d.patient + ' (' + d.patientCode + ') — version ' + (numero + 1)
        + '. Motif : ' + opts.motif + '. Le résultat que vous avez consulté a changé.',
      demandeId: demandeId, reference: d.reference,
      patientId: d.patientId,
    });

    return { demande: col_.get(demandeId), version: numero + 1, undo: res.undo };
  }

  /* ==========================================================================
   * NOTIFICATIONS DE POSTE
   * --------------------------------------------------------------------------
   * Une notification s'adresse à un POSTE, pas à une personne : le
   * prescripteur peut être en congé, c'est le service qui doit voir passer
   * l'information. Elle vit dans sa propre collection pour survivre au
   * rechargement de la page.
   * ======================================================================== */
  function notifier(o) {
    return S.collection('notifications', { module: 'M14', entite: 'notification', prefix: 'NOT' }).insert({
      type: o.type, poste: o.poste || 'tous',
      destinataire: o.destinataire || null,
      libelle: o.libelle, detail: o.detail || null,
      priorite: o.priorite || 'normale',
      demandeId: o.demandeId || null, factureId: o.factureId || null,
      ordonnanceId: o.ordonnanceId || null, patientId: o.patientId || null,
      reference: o.reference || null,
      lue: false, creeLe: new Date().toISOString(),
    }).record;
  }

  /** Les notifications d'un poste, non lues d'abord. */
  function notifications(poste, opts) {
    opts = opts || {};
    var rows = S.collection('notifications', { module: 'M14', entite: 'notification', prefix: 'NOT' })
      .active()
      .filter(function (n) { return !poste || n.poste === poste || n.poste === 'tous'; });
    if (opts.nonLues) rows = rows.filter(function (n) { return !n.lue; });
    return rows.sort(function (a, b) { return String(b.creeLe).localeCompare(String(a.creeLe)); });
  }

  function marquerLue(id) {
    return S.collection('notifications', { module: 'M14', entite: 'notification', prefix: 'NOT' })
      .update(id, { lue: true, lueLe: new Date().toISOString(), luePar: S.currentUser() });
  }

  /* ==========================================================================
   * LE PATIENT EXTERNE
   * --------------------------------------------------------------------------
   * Il arrive avec une ordonnance d'un médecin extérieur. L'accueil TRANSCRIT
   * cette ordonnance — il ne prescrit pas — en cochant les examens dans le
   * catalogue, puis l'envoie à la caisse avec sa facture.
   *
   * Deux règles que ce circuit doit tenir :
   *   — les examens viennent du CATALOGUE, jamais d'un montant libre : sans
   *     lignes, la facture ne peut pas être réglée examen par examen ;
   *   — l'IDENTITÉ est obligatoire. Sans nom, âge, sexe et téléphone, le
   *     résultat ne peut être ni remis ni retrouvé — et c'est au patient
   *     externe qu'on le remet directement.
   * ======================================================================== */
  /* --------------------------------------------------------------------------
   * LE DOSSIER D'UN PATIENT ADRESSÉ DE L'EXTÉRIEUR — UNE SEULE FABRIQUE
   * --------------------------------------------------------------------------
   * Le laboratoire et l'imagerie reçoivent tous deux des patients venus avec
   * une prescription extérieure. Écrire la création du dossier deux fois
   * aurait donné deux formes de patient externe dans la même collection —
   * c'est le défaut déjà payé sur le code patient, qui vivait à deux endroits.
   *
   * Le patient externe reçoit un DOSSIER : sans lui, on ne peut ni lui
   * remettre son résultat, ni le retrouver s'il revient. Il est marqué
   * `externe`, ce qui le distingue de la file de consultation.
   *
   * Le code suit `C.codePatient()` — la fabrique unique du format `CNT/n/AA`.
   * Ce site en construisait un À LA MAIN, à l'ancien format « CNT905/26 » :
   * la règle qui existe en deux exemplaires diverge au premier correctif, et
   * celle-ci avait déjà divergé.
   * ------------------------------------------------------------------------ */
  function dossierExterne(v, date) {
    var patients = S.collection('patients', { module: 'M1', entite: 'Patient' });
    var existant = v.patientId ? patients.get(v.patientId)
      : (v.patientCode ? patientParCode(v.patientCode) : null);
    if (v.patientId && !existant) throw new Error('Patient introuvable au répertoire.');
    if (existant) return existant;
    if (!String(v.nom || '').trim() || !String(v.prenom || '').trim()) {
      throw new Error('Nom et prénoms du patient obligatoires.');
    }
    return patients.insert({
      code: C.codePatient(900 + patients.all().length, new Date(date).getFullYear()),
      nom: String(v.nom).toUpperCase(), prenom: v.prenom,
      sexe: v.sexe || 'M', dateNaissance: v.dateNaissance || null,
      /* Âge DÉCLARÉ, et daté du jour de la déclaration : sans cette date il
         se figerait, et le dossier vieillirait sans que le patient vieillisse. */
      age: (!v.dateNaissance && v.age != null && v.age !== '') ? v.age : null,
      ageReferenceLe: (!v.dateNaissance && v.age != null && v.age !== '') ? C.iso(new Date(date)) : null,
      telephone: v.telephone || null, adresse: v.residence || null,
      quartier: v.residence || null,
      /* La date de création manquait : le répertoire la montre, le KPI
         « créés dans l'année » la compte, et la traçabilité du dossier la
         date — un dossier externe sans elle n'était compté nulle part. */
      dateCreation: C.iso(new Date(date)),
      externe: true, origineDossier: v.origineDossier || 'Patient externe — accueil',
      prescripteurExterieur: v.prescripteur || null,
      assure: !!v.assureur, assureur: v.assureur || null,
      tauxPriseEnCharge: v.assureur ? (Number(v.taux) || 0) : 0,
    }).record;
  }

  function ouvrirDemandeExterne(v) {
    /* L'identité est obligatoire — mais un patient DU RÉPERTOIRE (fiche du
       service, phase 7) la porte déjà : exiger sa ressaisie créerait deux
       vérités. La règle vaut pour l'externe dont on crée le dossier. */
    if (!v || (!v.patientId && (!v.nom || !v.prenom))) {
      throw new Error('Nom et prénoms du patient obligatoires.');
    }
    if (!v.analyses || !v.analyses.length) throw new Error('Cocher au moins un examen au catalogue.');

    var date = v.date || new Date().toISOString();

    /* Le patient externe reçoit un DOSSIER : sans lui, on ne peut ni lui
       remettre son résultat, ni le retrouver s'il revient. Il est marqué
       comme externe, ce qui le distingue de la file de consultation. */
    var p = dossierExterne(v, date);

    /* Les examens, pris au catalogue. */
    var analyses = (v.analyses || []).map(function (code) {
      var a = analyseParCode(code) || {};
      return {
        code: code, designation: a.designation || code, categorie: a.categorie || '',
        echantillon: a.echantillon || '', delai: a.delai || '', prix: a.prix || 0,
      };
    });
    var montant = C.sum(analyses, 'prix');

    /* Les demandes, marquées EXTERNE : le résultat se remet au patient. */
    var demandes = analyses.map(function (a) {
      return S.collection('demandesAnalyses').insert({
        reference: C.nextRef('LAB-', 5),
        codeAnalyse: codeAnalyse(date),
        patientId: p.id, patientCode: p.code, patient: p.nom + ' ' + p.prenom,
        analyseCode: a.code, analyse: a.designation, categorie: a.categorie,
        echantillon: a.echantillon, delai: a.delai, prix: a.prix,
        dateHeure: date,
        prescripteur: v.prescripteur || 'Médecin extérieur',
        laborantin: null,
        urgent: v.urgence === 'bilan' || (v.urgence === 'examen' && v.examenUrgent === a.code),
        etatAnalyse: 'en_attente',
        /* Trois voies désormais : la transcription à l'accueil, la saisie du
           laboratoire, et — phase 7 — la fiche de demande d'examen d'un
           SERVICE (m3-demande-examen, le formulaire papier de reunions/).
           origineDemande 'externe' dit que le résultat se remet au patient ;
           'service' le renvoie au prescripteur, sous le RBAC métier. */
        origine: v.origineFiche || 'accueil-externe',
        origineDemande: v.origineDemande || 'externe',
        serviceDemandeur: v.serviceDemandeur || null,
        secteurDemandeur: v.secteurDemandeur || null,
        indication: v.indication || null,
        hospitalise: !!v.hospitalise,
        bloqueParPaiement: true,
      }).record;
    });

    /* La facture, avec ses lignes payables. */
    var taux = p.assureur ? (p.tauxPriseEnCharge || 0) : 0;
    var partAssurance = Math.round(montant * taux / 100);
    var lignes = construireLignes({
      analyses: analyses, demandes: demandes, taux: taux,
      personnelId: p.personnelId || null,
    });

    var facture = col('factures').insert({
      lignes: lignes,
      numero: 'FE-' + String(new Date(date).getFullYear()) + '-' + C.pad(col('factures').all().length + 1, 5),
      numeroMecef: null,
      patientId: p.id, patient: p.nom + ' ' + p.prenom, patientCode: p.code,
      date: C.iso(new Date(date)), type: 'Analyses — patient externe',
      /* Le total est la somme des lignes, comme sur la facture de
         prescription : deux façons de compter divergeraient. */
      montantHT: C.sum(lignes, 'montant'), montantTTC: C.sum(lignes, 'montant'),
      montantBrut: C.sum(lignes, 'montantBrut'), totalRemise: C.sum(lignes, 'remise'),
      partPersonnel: C.sum(lignes, 'partPersonnel'),
      priseEnChargePersonnel: !!p.personnelId, personnelId: p.personnelId || null,
      assureur: p.assureur || null, tauxPriseEnCharge: taux,
      partAssurance: C.sum(lignes, 'partAssureur'),
      partPatient: C.sum(lignes, 'partPatient'),
      montantPaye: 0, reliquat: C.sum(lignes, 'partPatient'),
      modePaiement: null,
      statutPaiement: 'impayee', statutMecef: 'en_attente',
      origineDemande: 'externe',
      prescripteurExterieur: v.prescripteur || null,
    }).record;

    demandes.forEach(function (d) {
      S.collection('demandesAnalyses').update(d.id, { factureId: facture.id, factureNumero: facture.numero });
    });

    /* La caisse est saisie, le prélèvement attend le règlement. */
    var taches = [];
    taches.push(col('taches').insert({
      type: 'encaissement', poste: 'caisse',
      libelle: 'Patient externe — ' + p.nom + ' ' + p.prenom,
      detail: C.num(analyses.length) + ' examen(s) — ' + C.money(montant, false),
      reference: facture.numero, factureId: facture.id,
      patientId: p.id, patient: p.nom + ' ' + p.prenom,
      montant: montant, statut: 'en_attente', creeLe: date,
    }).record);
    taches.push(col('taches').insert({
      type: 'prelevement', poste: 'laboratoire',
      libelle: 'Patient externe — ' + p.nom + ' ' + p.prenom,
      detail: C.num(analyses.length) + ' examen(s)',
      reference: facture.numero, factureId: facture.id,
      patientId: p.id, patient: p.nom + ' ' + p.prenom,
      statut: 'bloque', creeLe: date,
    }).record);

    S.log('Demande externe ouverte', 'M1', 'DemandeAnalyse', facture.numero, null,
      { patient: p.code, examens: analyses.length, montant: montant });

    return { patient: p, demandes: demandes, facture: facture, taches: taches, montant: montant };
  }

  /* ==========================================================================
   * LA DEMANDE D'IMAGERIE (phase 8, cible Instructions)
   * --------------------------------------------------------------------------
   * L'imagerie suit LES MÊMES ÉTATS que le laboratoire : demandée → payée →
   * exécutée → validée. La demande naît bloquée par le paiement ; c'est
   * l'encaissement de SA ligne qui la libère — la ligne payable porte
   * `demandeImagerieId`, comme la ligne d'analyse porte `demandeId`.
   * UNE fabrique pour toutes les voies (consultation, service, saisie du
   * poste) : deux fabriques divergeraient.
   * ======================================================================== */
  /* --------------------------------------------------------------------------
   * LES DEMANDES D'IMAGERIE — UNE SEULE FABRIQUE, DEUX PORTES (14/09/2026)
   * --------------------------------------------------------------------------
   * La demande d'imagerie naît désormais aussi de la FICHE DE CONSULTATION,
   * dans la même facture que les médicaments et les analyses (METHODOLOGIE
   * §1.5 : UNE facture globale). Recopier ici la création des demandes aurait
   * donné deux formes de demande dès le premier correctif — c'est la leçon du
   * code patient, qui vivait à deux endroits. `prescrire` et
   * `ouvrirDemandeImagerie` appellent donc la MÊME fonction, qui crée les
   * demandes bloquées, applique RG-09 au tarif et REFUSE en nommant l'examen
   * sans prix, puis rend les lignes payables à poser sur la facture.
   *
   * Le catalogue est lu AU MAGASIN (`examensImagerie`, administrable par
   * cfg-imagerie-catalogue), la semence D.IMAGERIE n'étant qu'un repli : lire
   * la constante, c'était ignorer ce que l'écran de configuration corrige.
   * ------------------------------------------------------------------------ */
  function examenImagerieParCode(code) {
    var c = S.collection('examensImagerie').active().filter(function (x) { return x.code === code; })[0];
    if (c) return c;
    return ((D.IMAGERIE && D.IMAGERIE.EXAMENS) || []).filter(function (x) { return x.code === code; })[0] || null;
  }

  function creerDemandesImagerie(p, codes, date, v) {
    var assure = carteValide(p, date);
    var col_ = S.collection('demandesImagerie', { module: 'M2', entite: 'demande d’imagerie', prefix: 'IME' });

    var demandes = codes.map(function (code) {
      var ex = examenImagerieParCode(code);
      /* RG-09 : la validité de la carte À LA DATE décide du tarif. */
      var pr = D.tarifPrix ? D.tarifPrix((ex && ex.tarifCode) || code, assure) : { montant: null };
      return col_.insert({
        reference: C.nextRef('IME-', 5),
        dateHeure: date,
        patientId: p.id, patientCode: p.code, patient: p.nom + ' ' + p.prenom,
        examenCode: code, examen: ex ? ex.label : code,
        /* Copie de lecture : la modalité fait foi au catalogue (vague 61). */
        modalite: D.IMAGERIE && D.IMAGERIE.modaliteDeExamen ? D.IMAGERIE.modaliteDeExamen(ex) : 'echographie',
        prescripteur: v.prescripteur || '—',
        indication: v.indication || '',
        urgent: !!v.urgent,
        secteurDemandeur: v.secteurDemandeur || (secteurCourant() ? secteurCourant().libelle : null),
        origine: v.origine || 'consultation',
        ordonnanceId: v.ordonnanceId || null, ordonnanceNumero: v.ordonnanceNumero || null,
        dossierConsultationId: v.dossierConsultationId || null,
        prix: pr.montant, motifTarif: pr.motif || null,
        statut: 'demandee',
        bloqueParPaiement: true,
      }).record;
    });

    var sansPrix = demandes.filter(function (d) { return d.prix == null; });
    if (sansPrix.length) {
      /* Un tiret n'est pas un zéro : une demande sans tarif validé ne se
         facture pas — elle est refusée EN NOMMANT l'examen. */
      demandes.forEach(function (d) { col_.archive(d.id); });
      throw new Error('Tarif non renseigné pour : '
        + sansPrix.map(function (d) { return d.examen; }).join(', ')
        + '. Le renseigner au référentiel tarifaire avant de facturer.');
    }

    return {
      demandes: demandes,
      /* Les lignes payables : chacune porte `demandeImagerieId`, et c'est ce
         lien que `encaisser` lit pour libérer l'examen NOMMÉ. */
      lignes: demandes.map(function (d) {
        return { categorie: 'imagerie', designation: d.examen,
          quantite: 1, prixUnitaire: d.prix, montant: d.prix,
          demandeImagerieId: d.id };
      }),
    };
  }

  function ouvrirDemandeImagerie(v) {
    if (!v.examens || !v.examens.length) throw new Error('Cocher au moins un examen d’imagerie.');

    var date = v.date || new Date().toISOString();
    /* PATIENT DU RÉPERTOIRE **OU** ADRESSÉ DE L'EXTÉRIEUR (06/09/2026) : une
       échographie prescrite ailleurs se pratique ici comme une analyse
       prescrite ailleurs. La MÊME fabrique que le laboratoire ouvre le
       dossier — le patient externe n'a pas deux formes selon la porte par
       laquelle il entre. */
    var p = (v.patientId || v.patientCode) ? dossierExterne(v, date)
      : dossierExterne(Object.assign({}, v, { origineDossier: 'Patient externe — imagerie' }), date);
    if (!p) throw new Error('Patient introuvable au répertoire.');
    var col_ = S.collection('demandesImagerie', { module: 'M2', entite: 'demande d’imagerie', prefix: 'IME' });

    var cree = creerDemandesImagerie(p, v.examens, date, v);
    var demandes = cree.demandes;

    var taux = p.assureur ? (p.tauxPriseEnCharge || 0) : 0;
    var lignes = construireLignes({
      taux: taux, personnelId: p.personnelId || null,
      autres: cree.lignes,
    });

    var facture = col('factures').insert({
      lignes: lignes,
      numero: 'FI-' + String(new Date(date).getFullYear()) + '-' + C.pad(col('factures').all().length + 1, 5),
      numeroMecef: null,
      patientId: p.id, patient: p.nom + ' ' + p.prenom, patientCode: p.code,
      date: C.iso(new Date(date)), type: 'Imagerie',
      montantHT: C.sum(lignes, 'montant'), montantTTC: C.sum(lignes, 'montant'),
      montantBrut: C.sum(lignes, 'montantBrut'), totalRemise: C.sum(lignes, 'remise'),
      partPersonnel: C.sum(lignes, 'partPersonnel'),
      priseEnChargePersonnel: !!p.personnelId, personnelId: p.personnelId || null,
      assureur: p.assureur || null, tauxPriseEnCharge: taux,
      partAssurance: C.sum(lignes, 'partAssureur'),
      partPatient: C.sum(lignes, 'partPatient'),
      montantPaye: 0, reliquat: C.sum(lignes, 'partPatient'),
      modePaiement: null,
      statutPaiement: 'impayee', statutMecef: 'en_attente',
    }).record;

    demandes.forEach(function (d) {
      col_.update(d.id, { factureId: facture.id, factureNumero: facture.numero });
    });

    var taches = [];
    taches.push(col('taches').insert({
      type: 'encaissement', poste: 'caisse',
      libelle: 'Imagerie — ' + p.nom + ' ' + p.prenom,
      detail: C.num(demandes.length) + ' examen(s) — ' + C.money(facture.montantTTC, false),
      reference: facture.numero, factureId: facture.id,
      patientId: p.id, patient: p.nom + ' ' + p.prenom,
      montant: facture.montantTTC, statut: 'en_attente', creeLe: date,
    }).record);
    taches.push(col('taches').insert({
      type: 'imagerie', poste: 'imagerie',
      libelle: 'Examen d’imagerie — ' + p.nom + ' ' + p.prenom,
      detail: demandes.map(function (d) { return d.examen; }).join(', '),
      reference: facture.numero, factureId: facture.id,
      patientId: p.id, patient: p.nom + ' ' + p.prenom,
      statut: 'bloque', creeLe: date,
    }).record);

    notifier({
      type: 'demande_imagerie', poste: 'imagerie',
      libelle: 'Nouvelle demande d’imagerie — ' + p.nom + ' ' + p.prenom,
      detail: demandes.map(function (d) { return d.examen; }).join(', ')
        + ' — exécutable après passage en caisse',
      priorite: v.urgent ? 'haute' : 'normale',
      patientId: p.id, reference: facture.numero,
    });

    S.log('Demande d’imagerie ouverte', 'M2', 'DemandeImagerie', facture.numero, null,
      { patient: p.code, examens: demandes.length, montant: facture.montantTTC });

    return { patient: p, demandes: demandes.map(function (d) { return col_.get(d.id); }), facture: facture, taches: taches };
  }

  /* ==========================================================================
   * LE CODE D'ANALYSE UNIQUE — NNNNN-AAAA (phase 6, cible Instructions)
   * --------------------------------------------------------------------------
   * Série ANNUELLE, comme les pièces certifiantes : le registre papier du
   * laboratoire repart à 1 chaque année. UNE SEULE fabrique pour toutes les
   * voies — ordonnance, transcription à l'accueil, saisie du laboratoire,
   * jeu de démonstration : deux fabriques divergeraient au premier correctif
   * (c'est le défaut déjà rencontré sur le code patient, qui vivait à deux
   * endroits). La référence LAB-NNNNN reste : elle identifie la DEMANDE dans
   * le logiciel, le code d'analyse identifie le DOSSIER au registre annuel.
   * ======================================================================== */
  function codeAnalyse(date) {
    var d = date ? new Date(date) : new Date();
    var annee = String(isNaN(d.getTime()) ? new Date().getFullYear() : d.getFullYear());
    var max = 0;
    S.collection('demandesAnalyses').all().forEach(function (x) {
      var m = /^(\d{5})-(\d{4})$/.exec(x.codeAnalyse || '');
      if (m && m[2] === annee && +m[1] > max) max = +m[1];
    });
    return C.pad(max + 1, 5) + '-' + annee;
  }

  /* ==========================================================================
   * LE BADGE DU PERSONNEL — numéro de série et charge utile du QR
   * --------------------------------------------------------------------------
   * UNE SEULE fabrique, comme pour le code d'analyse : le numéro est posé à
   * l'émission, relu à la vérification, imprimé sur la carte et scanné au
   * contrôle. Le format retenu — BDG-NNNNN-AAAA — reprend la SÉRIE ANNUELLE
   * des pièces certifiantes, mais reste marqué à VALIDER par la Direction :
   * rien dans les documents de cadrage ne fixe la numérotation des badges, et
   * la clinique tient peut-être déjà un registre papier avec le sien.
   *
   * LA CHARGE UTILE DU QR EST LE POINT LE PLUS IMPORTANT DU MODULE.
   * Elle ne porte QUE le matricule de l'agent et le numéro de série du badge.
   * Ni nom, ni fonction, ni téléphone, ni adresse d'un service extérieur.
   * Trois raisons, et la troisième commande les deux autres :
   *   - un badge se photographie dans un couloir : ce qu'il porte en clair
   *     est lisible par quiconque le croise ;
   *   - le logiciel fonctionne HORS LIGNE — une URL ne mènerait nulle part ;
   *   - la vérification doit passer par le LOGICIEL, seul à savoir si le
   *     badge est encore valide. Un QR qui porterait le nom remplacerait un
   *     contrôle par une simple lecture, et c'est exactement ce qu'un faux
   *     badge cherche à obtenir.
   * ======================================================================== */
  function numeroBadge(date) {
    var d = date ? new Date(date) : new Date();
    var annee = String(isNaN(d.getTime()) ? new Date().getFullYear() : d.getFullYear());
    var max = 0;
    S.collection('badges').all().forEach(function (b) {
      var m = /^BDG-(\d{5})-(\d{4})$/.exec(b.numero || '');
      if (m && m[2] === annee && +m[1] > max) max = +m[1];
    });
    return 'BDG-' + C.pad(max + 1, 5) + '-' + annee;
  }

  /** La charge utile du code QR d'un badge — matricule et n° de série, rien d'autre. */
  function badgeQR(badge) {
    return 'CNT-BDG|MAT:' + (badge.matricule || '') + '|SER:' + (badge.numero || '');
  }

  /**
   * Lecture d'un code présenté au contrôle. On accepte aussi bien la charge
   * utile complète (badge scanné) que le seul numéro de série (saisi à la
   * main quand le QR est abîmé) : refuser la saisie manuelle rendrait le
   * contrôle impossible le jour où il sert le plus.
   */
  function lireBadgeQR(texte) {
    var t = String(texte || '').trim();
    if (!t) return null;
    var m = /^CNT-BDG\|MAT:([^|]*)\|SER:(.+)$/.exec(t);
    if (m) return { matricule: m[1] || null, numero: m[2].trim(), source: 'qr' };
    return { matricule: null, numero: t, source: 'saisie' };
  }

  /* ==========================================================================
   * LE JETON D'UNE FICHE D'ENQUÊTE PARTAGÉE
   * --------------------------------------------------------------------------
   * L'adresse porte un JETON, jamais l'identifiant de l'enquête : sans cela,
   * on énumère les enquêtes en changeant un numéro. Le jeton est long, tiré
   * au hasard, et c'est la fiche du magasin — pas le jeton — qui porte sa
   * date d'expiration et sa révocation : un lien qui vit indéfiniment
   * collecte des réponses des mois après la clôture, et personne ne s'en
   * aperçoit.
   * ======================================================================== */
  function jetonEnquete() {
    var alphabet = 'abcdefghijkmnopqrstuvwxyz23456789'; /* ni l ni 1, ni o ni 0 */
    var out = '';
    for (var i = 0; i < 24; i++) out += alphabet.charAt(Math.floor(Math.random() * alphabet.length));
    return out;
  }

  /* ==========================================================================
   * LES LIGNES PAYABLES D'UNE FACTURE
   * --------------------------------------------------------------------------
   * Une ligne par prestation, et le lien vers ce qu'elle couvre. Sans ce lien,
   * régler « trois examens sur cinq » ne pourrait pas désigner LESQUELS trois
   * passent au laboratoire.
   *
   * Chaque ligne porte sa part patient et sa part assureur : c'est la part
   * PATIENT qui se règle à la caisse, la part assureur suit son propre
   * circuit de recouvrement.
   * ======================================================================== */
  function construireLignes(v) {
    var lignes = [];
    var taux = Number(v.taux) || 0;
    /* La prise en charge de l'établissement se DÉDUIT du dossier : un agent
       n'a pas à la réclamer au guichet, et la lui faire demander reviendrait à
       l'oublier le jour où il est pressé. Ce n'est pas une assurance — aucun
       tiers ne rembourse, aucune créance ne naît. */
    var estAgent = !!v.personnelId;
    var n = 0;

    function ajouter(o) {
      n++;
      var brut = Math.round(Number(o.montant) || 0);
      var remise = Math.round(Number(o.remise) || 0);
      /* RG-02 — pas de remise sur un médicament : il se facture au prix
         d'achat, une remise le vendrait à perte. */
      if (o.categorie === 'medicament') remise = 0;
      var montant = brut - remise;

      var partAssureur = estAgent ? 0 : Math.round(montant * taux / 100);
      var partPersonnel = estAgent ? montant : 0;

      lignes.push({
        id: 'L' + C.pad(n, 3),
        categorie: o.categorie, designation: o.designation,
        quantite: o.quantite != null ? o.quantite : 1,
        prixUnitaire: o.prixUnitaire != null ? o.prixUnitaire : brut,
        prixUnitaireNet: (o.quantite || 1) ? Math.round(montant / (o.quantite || 1)) : montant,
        montantBrut: brut,
        remise: remise,
        motifRemise: remise ? (o.motifRemise || 'Remise accordée') : null,
        montant: montant,
        partAssureur: partAssureur,
        partPersonnel: partPersonnel,
        partPatient: montant - partAssureur - partPersonnel,
        /* Le lien vers ce que la ligne couvre. */
        demandeId: o.demandeId || null,
        produitId: o.produitId || null,
        acteCode: o.acteCode || null,
        demandeImagerieId: o.demandeImagerieId || null,
        /* L'état de règlement, ligne par ligne. */
        statutPaiement: 'du',
        montantRegle: 0, payeLe: null, payePar: null,
      });
    }

    (v.medicaments || []).forEach(function (m) {
      ajouter({
        categorie: 'medicament', designation: m.produit,
        quantite: m.quantite, prixUnitaire: m.prix, montant: m.total,
        produitId: m.produitId,
      });
    });

    (v.analyses || []).forEach(function (a, i) {
      var dem = (v.demandes || [])[i];
      ajouter({
        categorie: 'analyse', designation: a.designation,
        quantite: 1, prixUnitaire: a.prix, montant: a.prix,
        demandeId: dem ? dem.id : null,
      });
    });

    (v.actes || []).forEach(function (a) {
      ajouter({
        categorie: 'acte', designation: a.libelle,
        quantite: 1, prixUnitaire: a.prix || 0, montant: a.prix || 0,
        acteCode: a.code,
      });
    });

    (v.autres || []).forEach(function (o) { ajouter(o); });
    return lignes;
  }

  /* ==========================================================================
   * LA PIÈCE CERTIFIANTE PASSE PAR LA CAISSE (22/09/2026)
   * --------------------------------------------------------------------------
   * Un certificat est une PRESTATION TARIFÉE : la grille lui donne un prix, et
   * la clinique l'encaisse. Il se délivrait pourtant sans qu'aucune pièce de
   * caisse ne naisse — le montant figurait sur la fiche, personne ne savait
   * s'il avait été réglé, et le total des « recettes des certificats » comptait
   * des sommes jamais entrées.
   *
   * L'ÉTAT DE RÈGLEMENT N'EST PAS STOCKÉ SUR LA PIÈCE : il se LIT sur la ligne
   * de facture, comme le laboratoire lit le règlement d'un examen sur la
   * sienne. Le porter en double donnerait deux vérités, et c'est toujours la
   * mauvaise qu'on afficherait.
   *
   * TROIS RÉPONSES, PAS DEUX — la troisième est celle qui manque toujours :
   *   réglé · à encaisser · SANS PIÈCE LIÉE, pour les certificats délivrés
   *   avant que la caisse ne soit dans le circuit. Les dire impayés serait
   *   aussi faux que les dire réglés.
   *
   * L'ASSURANCE NE COUVRE RIEN ICI, SAUF SOS : la répartition suit donc la
   * grille (`assurable === 'sos'`), et non le taux du dossier — un assuré NSIA
   * règle son certificat intégralement.
   * ======================================================================== */
  function facturerPiece(v) {
    var p = v.patient;
    if (!p) throw new Error('Aucun patient : la pièce ne peut pas être facturée.');
    var montant = Math.round(Number(v.montant) || 0);
    if (!(montant > 0)) return null; /* pièce non tarifée : rien à encaisser */

    var date = v.date || new Date().toISOString();
    /* Seul SOS couvre un certificat (mention manuscrite de la grille). */
    var couvert = v.assurable === 'sos' && String(p.assureur || '') === 'SOS' && carteValide(p, date);
    var taux = couvert ? (p.tauxPriseEnCharge || 0) : 0;

    var lignes = construireLignes({
      actes: [{ libelle: v.libelle || 'Pièce certifiante', prix: montant, code: v.acteCode || null }],
      taux: taux, personnelId: p.personnelId || null,
    });
    /* La ligne porte CE QU'ELLE COUVRE : sans ce lien, un règlement partiel ne
       saurait pas désigner la pièce qu'il solde.
       C'est la RÉFÉRENCE qui fait le lien, et non l'identifiant : la facture
       naît AVANT la pièce — on la numérote pour pouvoir la facturer, et elle
       n'est écrite au registre qu'ensuite. Attendre l'identifiant obligerait
       à repasser sur la facture après coup, donc à écrire deux fois. */
    lignes.forEach(function (l) {
      l.pieceRef = v.reference || null;
      if (v.pieceId) l.pieceId = v.pieceId;
    });

    var facture = col('factures').insert({
      lignes: lignes,
      numero: 'FC-' + String(new Date(date).getFullYear()) + '-' + C.pad(col('factures').all().length + 1, 5),
      numeroMecef: null,
      patientId: p.id, patient: p.nom + ' ' + p.prenom, patientCode: p.code,
      date: C.iso(new Date(date)), type: 'Certificat & attestation',
      montantHT: C.sum(lignes, 'montant'), montantTTC: C.sum(lignes, 'montant'),
      montantBrut: C.sum(lignes, 'montantBrut'), totalRemise: C.sum(lignes, 'remise'),
      partPersonnel: C.sum(lignes, 'partPersonnel'),
      priseEnChargePersonnel: !!p.personnelId, personnelId: p.personnelId || null,
      assureur: p.assureur || null, tauxPriseEnCharge: taux,
      partAssurance: C.sum(lignes, 'partAssureur'),
      partPatient: C.sum(lignes, 'partPatient'),
      montantPaye: 0, reliquat: C.sum(lignes, 'partPatient'),
      modePaiement: null,
      statutPaiement: 'impayee', statutMecef: 'en_attente',
      pieceId: v.pieceId || null,
      pieceRef: v.reference || null,
      motifCouverture: couvert
        ? 'Certificat couvert par SOS — seule compagnie conventionnée sur ces pièces'
        : 'Certificat non couvert par les assurances (mention de la grille tarifaire)',
    }).record;

    col('taches').insert({
      type: 'encaissement', poste: 'caisse',
      libelle: (v.libelle || 'Pièce certifiante') + ' — ' + p.nom + ' ' + p.prenom,
      detail: (v.reference || '') + ' — ' + C.money(montant, false),
      reference: facture.numero, factureId: facture.id,
      patientId: p.id, patient: p.nom + ' ' + p.prenom,
      montant: facture.partPatient, statut: 'en_attente', creeLe: date,
    });

    return facture;
  }

  /**
   * L'état de règlement d'une pièce certifiante, LU sur sa facture.
   * @returns {{code:string,label:string,ton:string,detail:string,facture:Object}}
   */
  function statutPiece(piece) {
    if (!piece) return { code: 'inconnu', label: '—', ton: 'neutral', detail: '', facture: null };
    if (!piece.montant) {
      return { code: 'non_tarife', label: 'Non tarifée', ton: 'neutral',
        detail: 'Aucun tarif à la grille : rien à encaisser.', facture: null };
    }
    var f = piece.factureId ? col('factures').get(piece.factureId) : null;
    if (!f) {
      return { code: 'sans_piece', label: 'En attente', ton: 'warning',
        detail: 'Aucune pièce de caisse liée — certificat délivré avant que la caisse ne soit '
          + 'dans le circuit. Ni réglé, ni impayé : on ne sait pas.', facture: null };
    }
    var due = lignesDues(f).length;
    if (!due) {
      return { code: 'regle', label: 'Réglé', ton: 'success',
        detail: 'Réglé à la caisse — pièce ' + f.numero + '.', facture: f };
    }
    return { code: 'a_encaisser', label: 'À encaisser', ton: 'danger',
      detail: 'Le patient doit se présenter à la caisse avec la pièce ' + f.numero
        + ' — reste dû ' + C.money(f.reliquat || f.partPatient, false) + '.', facture: f };
  }

  /** Les lignes encore dues d'une facture, dans l'ordre de la pièce. */
  function lignesDues(facture) {
    return (facture.lignes || []).filter(function (l) { return l.statutPaiement !== 'paye'; });
  }

  /** Les lignes réglées d'une facture. */
  function lignesReglees(facture) {
    return (facture.lignes || []).filter(function (l) { return l.statutPaiement === 'paye'; });
  }

  /* ==========================================================================
   * LE COMPTABLE EST INFORMÉ
   * --------------------------------------------------------------------------
   * « La caisse valide → le comptable est informé. » Informer ne suffit pas :
   * un encaissement qui ne produit pas d'écriture oblige à ressaisir la
   * recette à la main, et c'est exactement ce que la clinique fait aujourd'hui
   * entre PERFECTO et la caisse.
   *
   * L'écriture est EQUILIBRÉE (RG-10) et double quand le patient est assuré :
   *   — débit  571 Caisse            de la part réglée par le patient ;
   *   — débit  411 Clients assurance de la part restant due par l'assureur ;
   *   — crédit 706 Prestations       du total facturé.
   *
   * Elle naît en BROUILLON : la validation comptable reste un geste humain.
   * ======================================================================== */
  var COMPTES_CAISSE = {
    caisse: { num: '571000', libelle: 'Caisse' },
    clientsAssurance: { num: '411110', libelle: 'Clients compagnie d’assurance' },
    prestations: { num: '706000', libelle: 'Services vendus — prestations de soins' },
  };

  /* LA PART ASSUREUR SE CONSTATE UNE SEULE FOIS (correction du 30/10/2026, écart E1 de ECARTS-MAQUETTE.md).
     Elle était ré-inscrite à CHAQUE versement partiel : une facture assurée réglée en deux fois par le patient posait
     deux fois la créance sur la compagnie (411) et deux fois le produit correspondant (706). Désormais le PREMIER
     versement constate la créance assureur ; les suivants ne constatent que ce que le patient verse.
     Au total, sur la vie de la facture : 706 = montant facturé, 411 = part assureur, 571 = part patient. */
  function creanceAssureurDejaConstatee(facture) {
    return col('ecritures').all().some(function (e) {
      return e.pieceId === facture.id && e.compte === COMPTES_CAISSE.clientsAssurance.num && e.statut !== 'archive';
    });
  }

  /* LE NUMÉRO DE PIÈCE EST UNE SÉRIE ANNUELLE (correction du 30/10/2026, écart E3). Il prenait les cinq derniers chiffres
     du numéro de facture — deux factures de deux années pouvaient se heurter, une facture sans chiffres donnait « CAI-2026-8 »
     — et le millésime était écrit en dur. Désormais : le millésime est celui de la date de l'écriture, le rang est le
     suivant de la série de l'année, et les versements d'une même facture REPRENNENT le numéro de sa première écriture. */
  function numeroPieceCaisse(facture, date) {
    var existante = col('ecritures').all().filter(function (e) {
      return e.pieceId === facture.id && e.journal === 'CAI' && e.numero;
    })[0];
    if (existante) return existante.numero;
    var annee = String(date).slice(0, 4);
    var prefixe = 'CAI-' + annee + '-';
    var max = 0;
    col('ecritures').all().forEach(function (e) {
      if (typeof e.numero === 'string' && e.numero.indexOf(prefixe) === 0) {
        var n = parseInt(e.numero.slice(prefixe.length), 10);
        if (n > max) max = n;
      }
    });
    return prefixe + C.pad(max + 1, 5);
  }

  function ecrireEncaissement(facture, montantRegle) {
    var lignes = [];
    var constatee = creanceAssureurDejaConstatee(facture);
    var partAssureur = constatee ? 0 : (Number(facture.partAssureur) || 0);
    var total = montantRegle + partAssureur;
    if (total <= 0) return [];

    var date = C.iso(new Date());
    var numero = numeroPieceCaisse(facture, date);
    var base = {
      numero: numero, date: date,
      journal: 'CAI', journalLibelle: 'Journal de caisse-dépenses',
      libelle: 'Encaissement facture ' + (facture.numero || facture.id)
        + ' — ' + (facture.patient || ''),
      pieceId: facture.id, pieceNumero: facture.numero,
      origine: 'Automatique — Caisse',
      statut: 'brouillon',
    };

    if (montantRegle > 0) {
      lignes.push(Object.assign({}, base, {
        compte: COMPTES_CAISSE.caisse.num, compteLibelle: COMPTES_CAISSE.caisse.libelle,
        debit: montantRegle, credit: 0,
      }));
    }
    if (partAssureur > 0) {
      lignes.push(Object.assign({}, base, {
        compte: COMPTES_CAISSE.clientsAssurance.num,
        compteLibelle: COMPTES_CAISSE.clientsAssurance.libelle,
        debit: partAssureur, credit: 0,
        libelle: base.libelle + ' — part ' + (facture.assureur || 'assureur'),
      }));
    }
    lignes.push(Object.assign({}, base, {
      compte: COMPTES_CAISSE.prestations.num, compteLibelle: COMPTES_CAISSE.prestations.libelle,
      debit: 0, credit: total,
    }));

    /* Contrôle RG-10 avant écriture : un déséquilibre ne doit pas entrer au
       journal, fût-il en brouillon. */
    var debit = lignes.reduce(function (n, l) { return n + l.debit; }, 0);
    var credit = lignes.reduce(function (n, l) { return n + l.credit; }, 0);
    if (debit !== credit) {
      S.log('Écriture d’encaissement refusée — déséquilibre', 'M12', 'Ecriture', numero,
        null, { debit: debit, credit: credit });
      return [];
    }

    var posees = lignes.map(function (l) { return col('ecritures').insert(l).record; });
    S.log('Écriture d’encaissement', 'M12', 'Ecriture', numero, null,
      { debit: debit, credit: credit, lignes: posees.length });
    return posees;
  }

  /* ==========================================================================
   * LE STOCK EST INFORMÉ
   * --------------------------------------------------------------------------
   * « Le stock est informé des stocks épuisés et de l'approvisionnement. »
   * Une délivrance qui fait passer un article sous son seuil doit le dire au
   * gestionnaire — au moment où elle a lieu, et non le jour de l'inventaire.
   *
   * Le seuil est celui que la clinique a fixé (il est absent du document
   * SAGE) : sans seuil, aucune alerte n'est possible, et l'article est
   * signalé comme tel plutôt que passé sous silence.
   * ======================================================================== */
  function alerterStock(produitIds, justificatif) {
    var alertes = [];
    (produitIds || []).forEach(function (id) {
      var prod = produitParId(id);
      if (!prod) return;
      var dispo = prod.stockDetail != null ? prod.stockDetail : prod.stock;
      var seuil = prod.seuilAlerte;
      var niveau = null;
      if (dispo <= 0) niveau = 'rupture';
      else if (seuil != null && seuil !== '' && dispo <= seuil) niveau = 'alerte';
      else if (seuil == null || seuil === '') niveau = 'sansSeuil';
      if (!niveau || niveau === 'sansSeuil') {
        if (niveau === 'sansSeuil') {
          alertes.push({ produit: prod, niveau: niveau, dispo: dispo, seuil: null });
        }
        return;
      }
      /* Une seule tâche ouverte par article : réalerter à chaque sortie
         noierait le gestionnaire sous les doublons. */
      var deja = taches().filter(function (t) {
        return t.type === 'reapprovisionnement' && t.produitId === id
          && t.statut !== 'termine';
      })[0];
      if (deja) {
        col('taches').update(deja.id, {
          stockRestant: dispo,
          libelle: (niveau === 'rupture' ? 'RUPTURE — ' : 'Sous le seuil — ') + prod.designation,
        });
      } else {
        col('taches').insert({
          type: 'reapprovisionnement', poste: 'stock',
          libelle: (niveau === 'rupture' ? 'RUPTURE — ' : 'Sous le seuil — ') + prod.designation,
          produitId: id, produitCode: prod.code,
          stockRestant: dispo, seuil: seuil,
          justificatif: justificatif || null,
          statut: 'en_attente', priorite: niveau === 'rupture' ? 'haute' : 'normale',
          creeLe: new Date().toISOString(),
        });
      }
      alertes.push({ produit: prod, niveau: niveau, dispo: dispo, seuil: seuil });
    });
    return alertes;
  }

  /**
   * encaisser(factureId, opts)
   *
   * opts.lignes   — identifiants des lignes réglées. C'est la forme JUSTE :
   *                 la caisse encaisse des prestations nommées.
   * opts.montant  — forme héritée. Le montant est alors ALLOUÉ aux lignes
   *                 encore dues, dans l'ordre de la pièce, jusqu'à épuisement.
   *                 Une ligne n'est réglée que si elle l'est entièrement :
   *                 un demi-examen ne se prélève pas.
   *
   * Dans les deux cas le résultat est le même — des lignes réglées, nommées,
   * et un déblocage qui ne porte que sur elles.
   */
  function encaisser(factureId, opts) {
    opts = opts || {};
    var fac = col('factures').get(factureId);
    if (!fac) throw new Error('Facture introuvable.');
    if (fac.statutPaiement === 'soldee') return { facture: fac, deja: true, lignesReglees: [] };

    var toutes = fac.lignes || [];
    var duTotal = fac.partPatient != null ? fac.partPatient : fac.montantTTC;

    /* --- Quelles lignes sont réglées par ce versement ? ------------------ */
    var reglees = [];
    var paye = 0;

    if (opts.lignes && opts.lignes.length) {
      var vises = {};
      opts.lignes.forEach(function (id) { vises[id] = true; });
      toutes.forEach(function (l) {
        if (l.statutPaiement === 'paye' || !vises[l.id]) return;
        reglees.push(l); paye += l.partPatient;
      });
    } else if (toutes.length) {
      /* Allocation d'un montant global : les lignes dues, dans l'ordre, tant
         que la somme versée les couvre ENTIÈREMENT. */
      var reste = opts.montant != null ? Number(opts.montant) : duTotal;
      toutes.forEach(function (l) {
        if (l.statutPaiement === 'paye') return;
        if (l.partPatient <= reste) { reglees.push(l); reste -= l.partPatient; paye += l.partPatient; }
      });
    } else {
      /* Facture sans lignes — pièce antérieure au modèle. On conserve le
         comportement par montant plutôt que de la rendre inencaissable. */
      paye = opts.montant != null ? Number(opts.montant) : duTotal;
    }

    /* --- Report sur la facture ------------------------------------------- */
    var lignesMaj = toutes.map(function (l) {
      if (reglees.indexOf(l) === -1) return l;
      return Object.assign({}, l, {
        statutPaiement: 'paye', montantRegle: l.partPatient,
        payeLe: new Date().toISOString(),
        payePar: opts.utilisateur || S.currentUser(),
      });
    });
    var totalPaye = (fac.montantPaye || 0) + paye;
    var restantDu = lignesMaj.length
      ? lignesMaj.filter(function (l) { return l.statutPaiement !== 'paye'; })
        .reduce(function (n, l) { return n + l.partPatient; }, 0)
      : Math.max(0, duTotal - totalPaye);
    var solde = restantDu <= 0;

    col('factures').update(factureId, {
      lignes: lignesMaj,
      montantPaye: totalPaye,
      reliquat: restantDu,
      modePaiement: opts.mode || 'especes',
      statutPaiement: solde ? 'soldee' : (totalPaye > 0 ? 'partielle' : 'impayee'),
      statutMecef: solde ? 'valide' : 'en_attente',
      /* Le point fiscal du dossier : seule la part réglée est normalisée. */
      baseMecef: totalPaye,
      dernierReglement: {
        date: new Date().toISOString(), montant: paye, mode: opts.mode || 'especes',
        lignes: reglees.map(function (l) { return l.id; }),
        encaissePar: opts.utilisateur || S.currentUser(),
      },
    });
    fac = col('factures').get(factureId);

    /* --- Le laboratoire : SEULES les analyses réglées passent ------------- */
    var demandesLiberees = [];
    reglees.forEach(function (l) {
      if (l.categorie !== 'analyse' || !l.demandeId) return;
      var d = S.collection('demandesAnalyses').get(l.demandeId);
      if (!d) return;
      S.collection('demandesAnalyses').update(l.demandeId, {
        bloqueParPaiement: false, statutPaiement: 'soldee',
        etatAnalyse: d.etatAnalyse === 'valide' ? 'valide' : 'attente_prelevement',
        regleLe: new Date().toISOString(),
      });
      demandesLiberees.push(d.reference || d.id);
    });

    /* --- L'imagerie suit la même règle : la séance réglée passe ----------- */
    reglees.forEach(function (l) {
      if (l.categorie !== 'imagerie' || !l.demandeImagerieId) return;
      var di = S.collection('demandesImagerie').get(l.demandeImagerieId);
      if (!di) return;
      S.collection('demandesImagerie').update(l.demandeImagerieId, {
        bloqueParPaiement: false,
        statut: di.statut === 'demandee' ? 'payee' : di.statut,
        regleLe: new Date().toISOString(),
      });
      demandesLiberees.push(di.reference || di.id);
    });

    var debloquees = [];
    if (fac.statutPaiement === 'soldee') {
      /* La tâche de caisse est faite ; celles d'aval s'ouvrent. */
      taches().filter(function (t) { return t.factureId === factureId; }).forEach(function (t) {
        if (t.type === 'encaissement') { terminer(t.id, opts.utilisateur); return; }
        if (t.statut === 'bloque') {
          col('taches').update(t.id, { statut: 'en_attente' });
          debloquees.push(t.type);
        }
      });
      /* Facture soldée : ce qui resterait bloqué faute de ligne — les pièces
         antérieures au modèle par lignes — est libéré ici. Les analyses déjà
         libérées ligne par ligne ne sont pas retouchées. */
      S.collection('demandesAnalyses').all().forEach(function (d) {
        if (!d.bloqueParPaiement) return;
        if (d.factureId === factureId || (fac.ordonnanceId && d.ordonnanceId === fac.ordonnanceId)) {
          S.collection('demandesAnalyses').update(d.id, {
            bloqueParPaiement: false,
            statutPaiement: 'soldee',
            etatAnalyse: d.etatAnalyse === 'valide' ? 'valide' : 'attente_prelevement',
            regleLe: new Date().toISOString(),
          });
          demandesLiberees.push(d.reference || d.id);
        }
      });
      S.collection('demandesImagerie').all().forEach(function (di) {
        if (!di.bloqueParPaiement || di.factureId !== factureId) return;
        S.collection('demandesImagerie').update(di.id, {
          bloqueParPaiement: false,
          statut: di.statut === 'demandee' ? 'payee' : di.statut,
          regleLe: new Date().toISOString(),
        });
        demandesLiberees.push(di.reference || di.id);
      });
      if (fac.ordonnanceId) col('ordonnances').update(fac.ordonnanceId, { statutPaiement: 'soldee' });
    }

    /* Le comptable est informé — par une écriture, pas par un message.
       Elle est posée à CHAQUE versement, y compris partiel : attendre le
       solde laisserait la caisse et la comptabilité divergentes entre-temps. */
    var ecritures = paye > 0 ? ecrireEncaissement(fac, paye) : [];

    S.log('Encaissement', 'M8', 'facture', fac.numero, { statutPaiement: 'impayee' },
      {
        statutPaiement: fac.statutPaiement, montantPaye: totalPaye,
        verse: paye, lignes: reglees.length, restantDu: restantDu,
      });

    return {
      facture: fac, debloquees: debloquees, ecritures: ecritures,
      lignesReglees: reglees, montantRegle: paye,
      restantDu: restantDu, demandesLiberees: demandesLiberees,
    };
  }

  /* ==========================================================================
   * 3. LA PHARMACIE DÉLIVRE
   * --------------------------------------------------------------------------
   * RG-03 : chaque sortie porte son justificatif — le numéro d'ordonnance — et
   * le stock ne peut pas passer sous zéro. Une ligne insuffisante bloque la
   * délivrance entière plutôt que de servir à moitié sans le dire.
   * ======================================================================== */
  function verifierStock(ordonnanceId) {
    var ord = col('ordonnances').get(ordonnanceId);
    if (!ord) throw new Error('Ordonnance introuvable.');
    /* RG-03 : le CUMUL des lignes d'un même produit est contrôlé — deux lignes de 5 sur un stock de 8 passaient chacune seule et laissaient
       un stock NÉGATIF (écart E42, corrigé le 30/10/2026). `disponible` est ce qui reste APRÈS les lignes précédentes du même produit. */
    var prises = {};
    return (ord.medicaments || []).map(function (l) {
      var prod = produitParId(l.produitId);
      var total = prod ? (prod.stockDetail != null ? prod.stockDetail : prod.stock) : 0;
      var dispo = total - (prises[l.produitId] || 0);
      if (prod) prises[l.produitId] = (prises[l.produitId] || 0) + l.quantite;
      return { ligne: l, produit: prod, disponible: dispo, suffisant: prod && dispo >= l.quantite };
    });
  }

  /* Valorisation d'une sortie de stock — paramétrable (annotation manuscrite
     de la réunion du 30/12/2024). Le mouvement porte LES DEUX valeurs : sans
     cela, changer de méthode rendrait l'historique incomparable. */
  function valoriserSortie(produit, quantite) {
    var pv = (produit.prixVente != null ? produit.prixVente : produit.prixAchat) || 0;
    var cump = produit.cump != null ? produit.cump : pv;
    var methode = S.valorisationSortie();
    var retenu = methode === 'cump' ? cump : pv;
    return {
      methode: methode,
      valeur: Math.round(retenu * quantite),
      valeurPrixVente: Math.round(pv * quantite),
      valeurCump: Math.round(cump * quantite),
      ecart: Math.round((pv - cump) * quantite),
    };
  }

  /** Alerte le gestionnaire de stock après une sortie. Voir alerterStock(). */
  function delivrer(ordonnanceId, opts) {
    opts = opts || {};
    var ord = col('ordonnances').get(ordonnanceId);
    if (!ord) throw new Error('Ordonnance introuvable.');
    if (ord.statutPaiement !== 'soldee') throw new Error('Facture non réglée — la délivrance est bloquée.');
    if (ord.statutDispensation === 'servie') return { ordonnance: ord, deja: true };

    var etat = verifierStock(ordonnanceId);
    var manquants = etat.filter(function (e) { return !e.suffisant; });
    if (manquants.length) {
      /* RG-03 — jamais de stock négatif : on refuse et on dit lequel. */
      var e = new Error('Stock insuffisant : ' + manquants.map(function (m) {
        return m.ligne.produit + ' (' + m.disponible + ' pour ' + m.ligne.quantite + ' demandés)';
      }).join(', '));
      e.manquants = manquants;
      throw e;
    }

    var mouvements = etat.map(function (x) {
      var prod = x.produit;
      var reste = (prod.stockDetail != null ? prod.stockDetail : prod.stock) - x.ligne.quantite;
      S.collection('produits').update(prod.id, {
        stockDetail: prod.stockDetail != null ? reste : prod.stockDetail,
        stock: Math.max(0, (prod.stock || 0) - x.ligne.quantite),
      });
      var val = valoriserSortie(prod, x.ligne.quantite);
      return col('mouvements').insert({
        /* Série lue sur les mouvements EXISTANTS, jamais sur un compteur de page qui repart à 1 à chaque chargement (écart E41b, cf. E8). */
        reference: C.referenceSuivante('M', 6, col('mouvements').all()),
        date: new Date().toISOString(),
        produitId: prod.id, produit: prod.designation,
        type: 'sortie', typeLabel: 'Sortie',
        quantite: x.ligne.quantite,
        stockType: 'detail',
        justificatif: 'Ordonnance ' + ord.numero,
        ordonnanceId: ord.id,
        /* Valorisation : méthode retenue et les deux valeurs, pour comparaison. */
        valorisation: val.methode, valeur: val.valeur,
        valeurPrixVente: val.valeurPrixVente, valeurCump: val.valeurCump,
        utilisateur: opts.utilisateur || S.currentUser(),
      }).record;
    });

    col('ordonnances').update(ordonnanceId, {
      statutDispensation: 'servie',
      dispenseLe: new Date().toISOString(),
      dispensePar: opts.utilisateur || S.currentUser(),
    });
    taches().filter(function (t) { return t.ordonnanceId === ordonnanceId && t.type === 'dispensation'; })
      .forEach(function (t) { terminer(t.id, opts.utilisateur); });

    S.log('Dispensation', 'M6', 'ordonnance', ord.numero, { statutDispensation: 'en_attente' },
      { statutDispensation: 'servie', lignes: mouvements.length });

    /* Le gestionnaire de stock est informé au moment où la sortie a lieu, et
       non le jour de l’inventaire : c’est la sortie qui fait passer sous le
       seuil, c’est elle qui doit le dire. */
    var alertes = alerterStock(etat.map(function (x) { return x.produit ? x.produit.id : null; })
      .filter(Boolean), ord.numero);

    return { ordonnance: col('ordonnances').get(ordonnanceId), mouvements: mouvements, alertes: alertes };
  }

  /* ==========================================================================
   * 4. FILES D'ATTENTE
   * ======================================================================== */
  function taches() { return col('taches').active(); }

  /** Ce qui attend un poste de travail : d'abord l'urgent, puis le plus ancien. */
  function aFaire(role, type) {
    return taches().filter(function (t) {
      if (t.statut === 'fait') return false;
      if (role && t.role !== role) return false;
      if (type && t.type !== type) return false;
      return true;
    }).sort(function (a, b) {
      if (!!b.urgent !== !!a.urgent) return b.urgent ? 1 : -1;
      return String(a.date).localeCompare(String(b.date));
    });
  }

  function terminer(tacheId, utilisateur) {
    return col('taches').update(tacheId, {
      statut: 'fait', faitLe: new Date().toISOString(), faitPar: utilisateur || S.currentUser(),
    });
  }

  /** Compteurs d'attente, pour les badges des tableaux de bord. */
  function compteurs(role) {
    var out = { total: 0 };
    aFaire(role).forEach(function (t) {
      out[t.type] = (out[t.type] || 0) + 1;
      if (t.statut === 'en_attente') out.total++;
    });
    return out;
  }

  /** Toutes les pièces attachées à une ordonnance — vue de bout en bout. */
  function dossier(ordonnanceId) {
    var ord = col('ordonnances').get(ordonnanceId);
    if (!ord) return null;
    return {
      ordonnance: ord,
      facture: ord.factureId ? col('factures').get(ord.factureId) : null,
      demandes: S.collection('demandesAnalyses').all().filter(function (d) { return d.ordonnanceId === ordonnanceId; }),
      demandesImagerie: S.collection('demandesImagerie').all().filter(function (d) { return d.ordonnanceId === ordonnanceId; }),
      mouvements: S.collection('mouvements').all().filter(function (m) { return m.ordonnanceId === ordonnanceId; }),
      taches: taches().filter(function (t) { return t.ordonnanceId === ordonnanceId; }),
    };
  }

  /* ==========================================================================
   * PRISE EN CHARGE — répartition ligne par ligne
   * --------------------------------------------------------------------------
   * Le cahier de charge du 30/12/2024 l'exige : « appliquer des pourcentages
   * par article et par prestation », le taux variant « d'une assurance à
   * l'autre et, pour un même assuré, selon la nature de l'article ». Un taux
   * unique par patient ne peut pas exprimer cela.
   *
   * La répartition suit donc quatre questions, dans cet ordre :
   *   1. la carte est-elle valide à la date de facturation ?      (RG-09)
   *   2. la ligne est-elle exclue par la convention ?
   *   3. exige-t-elle un accord préalable, et l'a-t-on ?
   *   4. quelle garantie couvre sa catégorie, à quel taux, sous quel plafond ?
   *
   * Chaque ligne repart avec son MOTIF : une part patient à 100 % doit toujours
   * pouvoir s'expliquer au guichet.
   * ======================================================================== */
  /* Le souscripteur suit la couverture de la DATE : c’est l’employeur qui
     porte la grille, et un assuré qui change d’employeur change de grille. */
  function souscripteurDe(patient, date) {
    if (!patient) return null;
    var id = patient.souscripteurId;
    if (date) {
      var c = couvertureALaDate(patient, date);
      if (c) id = c.souscripteurId || null;
      else return null;
    }
    if (!id) return null;
    return S.collection('souscripteurs').get(id);
  }

  /** Garanties applicables : celles du souscripteur, sinon celles de la compagnie. */
  function garantiesDe(patient, date) {
    /* La grille est celle du souscripteur DE LA DATE : un assuré qui a changé
       d’employeur en cours d’année n’avait pas le même barème en janvier. */
    var sous = souscripteurDe(patient, date);
    if (!sous) return [];
    var toutes = S.collection('garanties').active();
    var propres = toutes.filter(function (g) { return g.souscripteurId === sous.id; });
    if (propres.length) return propres;
    return toutes.filter(function (g) { return !g.souscripteurId && g.assureur === sous.assureur; });
  }

  /* ==========================================================================
   * LA COUVERTURE EST DATÉE — un assuré change d’assureur
   * --------------------------------------------------------------------------
   * Un employé change d’employeur, une convention n’est pas reconduite, un
   * particulier passe d’une compagnie à une autre : la couverture d’un même
   * patient n’est pas la même en janvier et en octobre. Le dossier ne portait
   * qu’un ÉTAT — une compagnie, une police, un taux, une expiration — et le
   * mettre à jour effaçait ce qui l’avait précédé. Conséquence : une facture
   * de mars, relue en novembre, se serait rapportée à la MAUVAISE compagnie,
   * et la créance de l’ancienne serait devenue injustifiable.
   *
   * Le mécanisme est celui de la grille des primes (NS 132) et des plages par
   * lot de réactif, et ce n’est pas un hasard : à chaque fois qu’une donnée
   * de référence change alors que des pièces ont déjà été émises sous
   * l’ancienne, c’est la MÊME réponse — versionner par date, jamais écraser.
   *
   * `debut: null` signifie « depuis l’ouverture du dossier » : la première
   * fiche d’historique est écrite au moment du PREMIER changement, et elle
   * ne peut pas inventer une date d’effet que personne n’a saisie.
   * `fin: null` signifie « en cours ».
   * ======================================================================== */
  function colCouvertures() {
    return S.collection('couverturesAssurance', {
      module: 'M9', entite: 'couverture d’assurance', prefix: 'COU' });
  }

  /** L’historique d’un patient, de la plus récente à la plus ancienne. */
  function historiqueCouverture(patient) {
    if (!patient) return [];
    return colCouvertures().active()
      .filter(function (c) { return c.patientId === patient.id; })
      .sort(function (a, b) {
        return String(b.debut || '0000-00-00').localeCompare(String(a.debut || '0000-00-00'));
      });
  }

  /**
   * La couverture EN FORCE à une date. Sans historique, la fiche du dossier
   * fait foi — c’est la situation des dossiers antérieurs à ce mécanisme, et
   * les traiter comme non couverts inventerait une rupture de droits.
   */
  function couvertureALaDate(patient, date) {
    if (!patient) return null;
    var d = C.iso(date || new Date());
    var hist = historiqueCouverture(patient);
    var enForce = hist.filter(function (c) {
      if (c.debut && d < c.debut) return false;
      if (c.fin && d > c.fin) return false;
      return true;
    })[0];
    if (enForce) return enForce;
    if (hist.length) return null; /* historique connu, et la date est hors de toute période */
    if (!patient.assureur) return null;
    return {
      origine: 'fiche', patientId: patient.id, assureur: patient.assureur,
      assureurNom: patient.assureurNom, numeroPolice: patient.numeroPolice,
      categorieAssurance: patient.categorieAssurance,
      tauxPriseEnCharge: patient.tauxPriseEnCharge,
      carteExpiration: patient.carteExpiration,
      souscripteurId: patient.souscripteurId,
      debut: null, fin: null,
    };
  }

  /**
   * changerCouverture(patient, v) — ferme la couverture en cours à la veille
   * de la date d’effet et en ouvre une nouvelle. RIEN N’EST ÉCRASÉ.
   * Retourne { ok, motif } : un refus se NOMME.
   */
  function changerCouverture(patient, v) {
    if (!patient) return { ok: false, motif: 'Aucun patient désigné.' };
    if (!v || !v.dateEffet) {
      return { ok: false, motif: 'La date d’effet est obligatoire : sans elle, la nouvelle couverture ne pourrait pas se distinguer de l’ancienne sur les pièces déjà émises.' };
    }
    if (!v.motif) {
      return { ok: false, motif: 'Le motif du changement est obligatoire (RG-12) — c’est lui qu’on relit quand une compagnie conteste une prise en charge.' };
    }
    var col = colCouvertures();
    var hist = historiqueCouverture(patient);
    var courante = hist.filter(function (c) { return !c.fin; })[0];

    /* Première mise à jour d’un dossier ancien : la couverture qui s’achève
       n’a jamais été écrite. On l’inscrit AVANT de la clore, faute de quoi
       tout ce qui précède la bascule deviendrait sans couverture connue. */
    if (!courante && patient.assureur) {
      courante = col.insert({
        patientId: patient.id, patientCode: patient.code,
        patient: patient.nom + ' ' + patient.prenom,
        assureur: patient.assureur, assureurNom: patient.assureurNom,
        numeroPolice: patient.numeroPolice, categorieAssurance: patient.categorieAssurance,
        tauxPriseEnCharge: patient.tauxPriseEnCharge, carteExpiration: patient.carteExpiration,
        souscripteurId: patient.souscripteurId,
        debut: null, fin: null, motif: 'Couverture reprise du dossier à la première mise à jour',
      }).record;
    }
    if (courante && courante.debut && v.dateEffet <= courante.debut) {
      return { ok: false, motif: 'La date d’effet (' + C.dateFR(v.dateEffet) + ') doit être postérieure au début de la couverture en cours (' + C.dateFR(courante.debut) + ').' };
    }
    if (courante) col.update(courante.id, { fin: C.iso(C.addDays(v.dateEffet, -1)) });

    var neuve = col.insert({
      patientId: patient.id, patientCode: patient.code,
      patient: patient.nom + ' ' + patient.prenom,
      assureur: v.assureur || null, assureurNom: v.assureurNom || null,
      numeroPolice: v.numeroPolice || null, categorieAssurance: v.categorieAssurance || null,
      tauxPriseEnCharge: Number(v.tauxPriseEnCharge) || 0,
      carteExpiration: v.carteExpiration || null,
      souscripteurId: v.souscripteurId || null,
      debut: C.iso(v.dateEffet), fin: null, motif: v.motif,
    }).record;

    /* La fiche du dossier reflète TOUJOURS la couverture en force AUJOURD’HUI.
       Une bascule datée du mois prochain ne doit pas changer ce que la caisse
       applique ce matin. */
    var auj = couvertureALaDate(patient, new Date()) || {};
    S.collection('patients').update(patient.id, {
      assureur: auj.assureur || null, assureurNom: auj.assureurNom || null,
      numeroPolice: auj.numeroPolice || null, categorieAssurance: auj.categorieAssurance || null,
      tauxPriseEnCharge: auj.tauxPriseEnCharge || 0,
      carteExpiration: auj.carteExpiration || null,
      souscripteurId: auj.souscripteurId || null,
    });
    return { ok: true, couverture: neuve };
  }

  /* RG-09 SE LIT À LA DATE, et la couverture aussi : une facture de mars se
     règle sur la compagnie de mars, pas sur celle d’aujourd’hui. */
  function carteValide(patient, date) {
    if (!patient) return false;
    var c = couvertureALaDate(patient, date);
    if (!c || !c.assureur || !c.carteExpiration) return false;
    return C.toDate(c.carteExpiration).getTime() >= C.toDate(date || new Date()).getTime();
  }

  /* Nombre de mots significatifs partagés par deux libellés : « consultation
     généraliste » colle à « Consultation généraliste » (2) et non à
     « Consultation spécialiste ou professeur » (1). */
  function mots(t) {
    var s = String(t || '').toLowerCase();
    if (s.normalize) s = s.normalize('NFD').replace(/[̀-ͯ]/g, '');
    return s.split(/[^a-z0-9]+/);
  }
  function proximite(a, b) {
    var ma = mots(a).filter(function (m) { return m.length > 3; });
    var mb = mots(b).filter(function (m) { return m.length > 3; });
    var n = 0;
    ma.forEach(function (m) { if (mb.indexOf(m) >= 0) n++; });
    return n;
  }

  function contient(liste, texte) {
    if (!liste || !liste.length || !texte) return null;
    var t = String(texte).toLowerCase();
    for (var i = 0; i < liste.length; i++) {
      var e = String(liste[i]).toLowerCase();
      if (t.indexOf(e) >= 0 || e.indexOf(t) >= 0) return liste[i];
    }
    return null;
  }

  /**
   * repartir(patient, lignes, opts) — lignes : [{libelle, categorie, montant, accordObtenu}]
   * Retourne chaque ligne enrichie de partAssureur, partPatient et motif,
   * plus les totaux de la facture.
   */
  function repartir(patient, lignes, opts) {
    opts = opts || {};
    var date = opts.date || new Date().toISOString();
    var sous = souscripteurDe(patient, date);
    var grille = garantiesDe(patient, date);
    var valide = carteValide(patient, date);

    var detail = (lignes || []).map(function (l) {
      var montant = Number(l.montant) || 0;
      var base = {
        libelle: l.libelle, categorie: l.categorie || 'autre', montant: montant,
        partAssureur: 0, partPatient: montant, taux: 0, plafond: null, garantie: null,
      };

      if (!patient || !patient.assureur) {
        return Object.assign(base, { motif: 'Patient non assuré' });
      }
      if (!valide) {
        /* RG-09 — carte invalide à la date de facturation : facturation intégrale. */
        return Object.assign(base, { motif: 'Carte non valide à la date de facturation (RG-09)' });
      }
      if (!sous) {
        return Object.assign(base, { motif: 'Assuré non rattaché à un souscripteur' });
      }
      if (!grille.length) {
        return Object.assign(base, { motif: 'Convention non saisie pour ' + sous.nom });
      }

      var exclu = contient(sous.actesExclus, l.libelle) || contient(sous.produitsExclus, l.libelle);
      if (exclu) {
        return Object.assign(base, { motif: 'Exclu de la convention : ' + exclu, exclu: true });
      }

      var accord = contient(sous.accordPrealable, l.libelle);
      if (accord && !l.accordObtenu) {
        return Object.assign(base, {
          motif: 'Accord préalable requis et non obtenu : ' + accord,
          accordRequis: accord,
        });
      }

      /* Une catégorie porte souvent plusieurs garanties — le barème distingue
         la consultation généraliste de la consultation spécialiste, plafonnées
         à 5 000 et 10 000 FCFA. Prendre la première venue appliquerait le mauvais
         plafond : on retient celle dont le libellé colle le mieux à la ligne. */
      var candidates = grille.filter(function (x) { return x.categorie === base.categorie; });
      if (!candidates.length) {
        return Object.assign(base, { motif: 'Aucune garantie pour la catégorie « ' + base.categorie + ' »' });
      }
      var g = candidates[0], meilleur = -1;
      candidates.forEach(function (x) {
        var s = proximite(x.libelle, l.libelle);
        if (s > meilleur) { meilleur = s; g = x; }
      });

      var couvert = Math.round(montant * (g.taux || 0) / 100);
      var motif = 'Garantie ' + g.libelle + ' — ' + g.taux + ' %';
      if (g.plafond != null && couvert > g.plafond) {
        couvert = g.plafond;
        motif += ', plafonnée à ' + C.money(g.plafond, false)
          + (g.unitePlafond ? ' ' + libelleUnite(g.unitePlafond) : '');
      }
      return Object.assign(base, {
        partAssureur: couvert, partPatient: montant - couvert,
        taux: g.taux, plafond: g.plafond, garantie: g.libelle, motif: motif,
      });
    });

    return {
      lignes: detail,
      souscripteur: sous, carteValide: valide, grilleSaisie: grille.length > 0,
      total: C.sum(detail, 'montant'),
      partAssureur: C.sum(detail, 'partAssureur'),
      partPatient: C.sum(detail, 'partPatient'),
    };
  }

  function libelleUnite(id) {
    var u = D.UNITES_PLAFOND.filter(function (x) { return x.id === id; })[0];
    return u ? u.label : id;
  }

  /** Catégorie de garantie d'une ligne, déduite de sa nature. */
  function categoriser(ligne) {
    if (ligne.analyseCode || ligne.type === 'analyse') return 'analyse';
    if (ligne.produitId || ligne.type === 'medicament') {
      return /vitamin|fortifiant/i.test(ligne.libelle || ligne.produit || '') ? 'vitamine' : 'medicament';
    }
    var acte = (ligne.code && acteParCode(ligne.code)) || null;
    var secteur = acte ? acte.secteur : (ligne.secteur || '');
    if (/Imagerie/i.test(secteur)) return 'imagerie';
    if (/Maternité/i.test(secteur)) return 'maternite';
    if (/Chirurgie/i.test(secteur)) return 'chirurgie';
    if (/Hospitalisation/i.test(secteur)) return 'hospitalisation';
    if (/Médecine générale/i.test(secteur)) return /[Cc]ertificat/.test(ligne.libelle || '') ? 'certificat' : 'consultation';
    if (/Soins/i.test(secteur)) return 'soin';
    return 'autre';
  }

  /* ==========================================================================
   * HABILITATIONS MÉTIER — ce que l'agent peut VOIR, pas seulement ouvrir
   * --------------------------------------------------------------------------
   * Le manifeste `nav.js` décide des écrans par rôle. Il ne suffit pas : deux
   * agents peuvent ouvrir le même écran et ne devoir y voir ni les mêmes
   * lignes ni les mêmes colonnes. La Direction l'a dit sans ambiguïté — le
   * médecin voit tous les résultats, la sage-femme ceux de la maternité,
   * l'infirmier aucun, l'aide-soignant pas davantage.
   *
   * Trois axes, et non un seul :
   *   RÔLE       → les écrans          (nav.js)
   *   FONCTION   → les capacités       (D.CAPACITES)
   *   SECTEUR    → le périmètre        (collection `secteurs`, NS 145)
   * ======================================================================== */

  /** Fonction déduite d'une session — le rôle sert de repli. */
  var ROLE_VERS_FONCTION = {
    medecin: 'medecin', dm: 'medecin', direction: 'direction', da: 'direction',
    infirmier: 'infirmier', pharmacien: 'dispensatrice', laborantin: 'tsl',
    caissier: 'caissiere', reception: 'accueil', stock: 'stock',
    comptable: 'comptable', rh: 'direction', admin: 'direction',
    agentadmin: 'entretien', ambulancier: 'chauffeur',
  };

  function capacites(session) {
    var s = session || S.session() || {};
    var demandee = s.fonction || null;
    var duRole = ROLE_VERS_FONCTION[s.role] || null;

    /* UNE FONCTION INCONNUE NE FERME PAS L'ÉCRAN EN SILENCE. Elle retombe sur
       la fonction déduite du RÔLE — donnée sûre, venue du manifeste et non
       d'une saisie — et la substitution est signalée. Retomber sur « accueil »,
       le profil le plus restrictif, faisait qu'un agent parfaitement habilité
       ouvrait son poste, ne voyait rien, et lisait qu'il n'avait pas accès. */
    var inconnue = !!(demandee && !D.CAPACITES[demandee]);
    var f = (demandee && D.CAPACITES[demandee]) ? demandee : (duRole || 'accueil');

    return Object.assign({
      fonction: f,
      fonctionInconnue: inconnue ? demandee : null,
    }, D.CAPACITES[f] || D.CAPACITES.accueil);
  }

  /** Secteur d'affectation de l'agent connecté (NS 145). */
  function secteurCourant(session) {
    var s = session || S.session() || {};
    if (!s.secteur) return null;
    var t = S.collection('secteurs').active().filter(function (x) {
      return x.code === s.secteur || x.id === s.secteur;
    });
    return t[0] || null;
  }

  /**
   * peutVoirResultat(demande, session) — décide, et dit pourquoi.
   * Retourne { autorise, motif }. Le motif est destiné à l'écran : un refus
   * muet laisse croire à une donnée manquante plutôt qu'à une restriction.
   */
  function peutVoirResultat(demande, session) {
    var cap = capacites(session);

    /* LE PREMIER VERROU, avant toute question d'habilitation : un résultat
       non validé biologiquement n'existe pas pour le prescripteur. C'est
       toute la raison d'être des deux validations — entre la saisie et la
       validation biologique, le laboratoire relit, et personne d'autre ne
       lit par-dessus son épaule. Le laboratoire, lui, voit son propre
       travail en cours, sans quoi il ne pourrait pas le relire. */
    var duLabo = cap.voirResultats === 'produits' || cap.validerTechnique;
    if (demande && demande.etatAnalyse && !duLabo
      && !D.resultatRendu(demande.etatAnalyse)) {
      return {
        autorise: false,
        motif: 'Résultat non encore validé biologiquement — '
          + D.etatResultat(demande.etatAnalyse).label.toLowerCase()
          + '. Le laboratoire le relit avant de le rendre.',
        enAttenteValidation: true,
      };
    }

    if (cap.voirResultats === 'tous') {
      return { autorise: true, motif: cap.label + ' — accès à tous les résultats' };
    }
    if (cap.voirResultats === 'aucun') {
      return { autorise: false, motif: cap.label + ' — les résultats d’analyses ne lui sont pas accessibles' };
    }
    if (cap.voirResultats === 'produits') {
      /* Le laboratoire voit ce qu'il produit, et le remet aux patients externes. */
      return { autorise: true, motif: 'Laboratoire — résultat produit par le service' };
    }
    if (cap.voirResultats === 'secteur') {
      var sect = secteurCourant(session);
      var demandeur = demande && (demande.secteurDemandeur || demande.secteur);
      var mien = (sect && sect.libelle) || (cap.secteurs || [])[0] || '';
      var ok = demandeur && mien && String(demandeur).toUpperCase().indexOf(String(mien).toUpperCase()) >= 0;
      return {
        autorise: !!ok,
        motif: ok
          ? cap.label + ' — résultat demandé par son secteur (' + demandeur + ')'
          : cap.label + ' — résultat demandé par ' + (demandeur || 'un autre secteur') + ', hors de son périmètre',
      };
    }
    return { autorise: false, motif: 'Périmètre non défini' };
  }

  function peutPrescrire(nature, session) {
    var cap = capacites(session);
    return (cap.prescrire || []).indexOf(nature) >= 0;
  }

  function peutExecuterSoin(session) { return !!capacites(session).executerSoins; }

  /** Filtre une liste de demandes/résultats selon l'habilitation. */
  function filtrerResultats(liste, session) {
    return (liste || []).filter(function (d) { return peutVoirResultat(d, session).autorise; });
  }

  /* ==========================================================================
   * PRISE EN CHARGE DU PERSONNEL
   * --------------------------------------------------------------------------
   * La clinique soigne ses agents à 100 %. Ce n'est PAS une assurance au sens
   * de M9 : aucun tiers ne rembourse, aucune créance ne naît, et la prestation
   * ne constitue ni une recette ni une charge à comptabiliser — c'est un
   * avantage consenti par l'employeur, dont on veut connaître le VOLUME.
   *
   * D'où trois règles que le reste du logiciel doit respecter :
   *   — la part patient est nulle, mais il n'y a pas de part assureur ;
   *   — la ligne ne remonte pas aux recettes ni au relevé assureur ;
   *   — la valeur reste calculée, pour que la Direction sache ce que
   *     l'avantage représente.
   * ======================================================================== */

  /** Le dossier personnel derrière un patient, ou null. */
  function agentDe(patient) {
    if (!patient) return null;
    var id = patient.personnelId || (typeof patient === 'string' ? null : null);
    if (!id) return null;
    return S.collection('personnel').all().filter(function (e) { return e.id === id; })[0] || null;
  }

  /** Le patient est-il un agent de la clinique ? */
  function estPersonnel(patient) {
    return !!(patient && patient.personnelId);
  }

  /**
   * Prise en charge d'une ligne pour un agent : 100 %, sans tiers payeur.
   * Renvoie le même contrat que PR.repartir pour que la facturation n'ait
   * pas à distinguer deux formes de résultat.
   */
  function prendreEnChargePersonnel(patient, lignes) {
    var agent = agentDe(patient);
    return (lignes || []).map(function (l) {
      var base = Number(l.montant) || 0;
      return {
        ligne: l, base: base,
        partAssureur: 0,
        partPatient: 0,
        priseEnChargePersonnel: base,
        taux: 100,
        agent: agent ? agent.nomComplet : (patient && patient.nom),
        matricule: agent ? agent.matricule : (patient && patient.matricule),
        motif: 'Prise en charge du personnel — 100 %, sans contrepartie d’un tiers payeur. '
          + 'Ni recette ni créance : avantage consenti par l’employeur.',
        horsRecettes: true,
      };
    });
  }

  /* ==========================================================================
   * PRESCRIPTION DE SOINS
   * --------------------------------------------------------------------------
   * La clinique distingue deux prescriptions : celle de l'ORDONNANCE, qui
   * porte des médicaments, et celle des SOINS, qui porte des actes. Les
   * confondre rendait invisible tout le travail infirmier — sept infirmiers et
   * trois sages-femmes exécutent des actes que rien ne traçait.
   *
   * Un soin est ADRESSÉ à un secteur : salle de soins, hospitalisation ou
   * maternité. Sans destinataire, il n'apparaîtrait sur aucun poste et ne
   * serait jamais exécuté.
   *
   * Il est facturé au catalogue AMI — donc au bon prix selon que le patient
   * est assuré ou non (voir D.tarifPrix).
   * ======================================================================== */
  function prescrireSoins(v) {
    var p = patientParCode(v.patientCode);
    if (!p) throw new Error('Patient introuvable : ' + v.patientCode);

    var soignant = (col('soignants').active().filter(function (x) {
      return x.id === v.prescripteurId;
    })[0]) || null;
    /* Un infirmier ne prescrit pas. Le contrôle est ici, au moteur : le poser
       dans l'écran laisserait passer toute prescription venue d'ailleurs. */
    if (soignant && !soignant.prescrit) {
      throw new Error(soignant.nomComplet + ' (' + soignant.poste + ') n’est pas habilité à prescrire.');
    }

    var date = v.date || new Date().toISOString();
    /* RG-09 : c’est la validité de la carte À LA DATE qui décide du tarif,
       et non le fait que le patient possède une carte. Une carte expirée
       facture au tarif non assuré, et la ligne le dit. */
    var assure = carteValide(p, date);

    var lignes = (v.actes || []).map(function (a) {
      var code = typeof a === 'string' ? a : a.code;
      var t = D.tarif ? D.tarif(code) : null;
      var pr = D.tarifPrix ? D.tarifPrix(code, assure) : { montant: null, motif: null };
      return {
        acteCode: code,
        libelle: t ? t.libelle : code,
        famille: t ? t.famille : null,
        quantite: Number((typeof a === 'object' && a.quantite) || 1),
        frequence: (typeof a === 'object' && a.frequence) || '',
        duree: (typeof a === 'object' && a.duree) || '',
        /* Le nombre d'administrations attendues : c'est lui qui fait vivre le
           relais. Une seule administration ne quitte jamais la salle de soins. */
        nbAdministrations: Number((typeof a === 'object' && a.nbAdministrations) || 1),
        prix: pr.montant,
        tarif: pr.tarif || null,
        motifTarif: pr.motif || null,
        prixAValider: pr.montant == null,
      };
    });

    var modalite = v.modalite || 'ambulatoire';
    var pres = col('prescriptions').insert({
      reference: C.nextRef('PRS-', 5),
      type: 'soins',
      origine: v.origine || 'consultation',
      date: date,
      patientId: p.id, patientCode: p.code, patient: p.nom + ' ' + p.prenom,
      prescripteurId: v.prescripteurId || null,
      prescripteur: soignant ? soignant.nomComplet : (v.prescripteur || '—'),
      secteurDestinataire: v.secteurDestinataire || 'salle_soins',
      modalite: modalite,
      /* Le secteur qui recevra la PREMIÈRE administration, annoncé d'avance :
         l'écran le dit au prescripteur au moment où il prescrit. */
      premierAdministrateur: D.secteurAdministrateur(modalite, 1).secteur,
      admissionId: v.admissionId || null,
      indication: v.indication || '',
      lignes: lignes,
      montant: lignes.reduce(function (t, l) { return t + (l.prix || 0) * l.quantite; }, 0),
      assure: assure,
      statut: 'en_cours',
      statutPaiement: 'impayee',
    }).record;

    /* La notification s'adresse à un POSTE et non à une personne : l'infirmier
       de garde change, le secteur reste. */
    notifier({
      type: 'prescription_soins',
      poste: v.secteurDestinataire || 'salle_soins',
      libelle: 'Nouvelle prescription de soins — ' + pres.patient,
      detail: pres.reference + ' — ' + lignes.length + ' acte(s) — ' + pres.prescripteur,
      priorite: v.urgent ? 'haute' : 'normale',
      patientId: p.id, reference: pres.reference,
    });

    return pres;
  }

  /* --------------------------------------------------------------------------
   * L'ORDONNANCE ENTRE AU MÊME REGISTRE
   * ------------------------------------------------------------------------
   * Pour que le registre des prescriptions dise la vérité, l'ordonnance doit y
   * figurer aussi. Sans cela, « les prescriptions du jour » n'en montreraient
   * que la moitié.
   * ---------------------------------------------------------------------- */
  function inscrireOrdonnance(ord, origine) {
    return col('prescriptions').insert({
      reference: ord.numero,
      type: 'ordonnance',
      origine: origine || 'consultation',
      date: ord.date,
      patientId: ord.patientId, patientCode: ord.patientCode, patient: ord.patient,
      prescripteurId: ord.prescripteurId || null,
      prescripteur: ord.medecin,
      secteurDestinataire: 'pharmacie',
      modalite: ord.modalite || 'ambulatoire',
      premierAdministrateur: D.secteurAdministrateur(ord.modalite || 'ambulatoire', 1).secteur,
      ordonnanceId: ord.id,
      lignes: (ord.medicaments || []).map(function (m) {
        return {
          produitId: m.produitId, libelle: m.produit, quantite: m.quantite,
          posologie: m.posologie, duree: m.duree, prix: m.prix,
          nbAdministrations: Number(m.nbAdministrations || 1),
        };
      }),
      montant: ord.montantMedicaments || 0,
      statut: 'en_cours',
      statutPaiement: ord.statutPaiement || 'impayee',
    }).record;
  }

  /* ==========================================================================
   * ADMINISTRATION D'UN TRAITEMENT — LA RÈGLE DE RELAIS
   * --------------------------------------------------------------------------
   * Le rang décide du secteur, pas l'inverse. Un poste qui tente d'administrer
   * ce qui ne lui revient pas est refusé EN LE NOMMANT : « cette administration
   * revient à la salle de soins ». Un refus muet ferait croire à une panne.
   * ======================================================================== */
  function rangSuivant(prescriptionId, ligneIndex) {
    return col('administrations').active().filter(function (a) {
      return a.prescriptionId === prescriptionId && a.ligneIndex === ligneIndex;
    }).length + 1;
  }

  function administrer(prescriptionId, opts) {
    opts = opts || {};
    var pres = col('prescriptions').get(prescriptionId);
    if (!pres) throw new Error('Prescription introuvable.');

    var ligneIndex = Number(opts.ligneIndex || 0);
    var ligne = (pres.lignes || [])[ligneIndex];
    if (!ligne) throw new Error('Ligne de prescription introuvable.');

    /* Une prescription non réglée ne s'administre pas : c'est la même règle
       que pour la délivrance et le laboratoire. */
    if (pres.statutPaiement !== 'payee' && !opts.forcer) {
      return { ok: false, motif: 'Prescription non réglée — l’administration reste bloquée jusqu’à l’encaissement.' };
    }

    var rang = rangSuivant(prescriptionId, ligneIndex);
    var attendu = D.secteurAdministrateur(pres.modalite, rang);

    if (opts.secteur && opts.secteur !== attendu.secteur) {
      return {
        ok: false, rang: rang, secteurAttendu: attendu.secteur,
        motif: attendu.motif,
      };
    }

    var exec = (col('soignants').active().filter(function (x) {
      return x.id === opts.executantId;
    })[0]) || null;
    /* Le médecin prescrit, il n'exécute pas les soins ; l'infirmier et la
       sage-femme exécutent. Le contrôle vit au moteur. */
    if (exec && !exec.execute) {
      return {
        ok: false, rang: rang,
        motif: exec.nomComplet + ' (' + exec.poste + ') n’exécute pas les soins.',
      };
    }

    var rec = col('administrations').insert({
      reference: C.nextRef('ADM-', 5),
      prescriptionId: prescriptionId, prescriptionRef: pres.reference,
      ligneIndex: ligneIndex, libelle: ligne.libelle,
      patientId: pres.patientId, patientCode: pres.patientCode, patient: pres.patient,
      dateHeure: opts.dateHeure || new Date().toISOString(),
      rang: rang, total: ligne.nbAdministrations || 1,
      secteur: attendu.secteur, motifSecteur: attendu.motif,
      executantId: opts.executantId || null,
      executant: exec ? exec.nomComplet : (opts.executant || '—'),
      observation: opts.observation || '',
      modalite: pres.modalite,
    }).record;

    /* La prescription se termine quand toutes ses lignes sont servies. */
    var reste = (pres.lignes || []).some(function (l, i) {
      return rangSuivant(prescriptionId, i) <= (l.nbAdministrations || 1);
    });
    if (!reste) col('prescriptions').update(prescriptionId, { statut: 'termine' });

    return { ok: true, administration: rec, rang: rang, secteur: attendu.secteur };
  }

  /* --------------------------------------------------------------------------
   * CE QUI REVIENT À UN POSTE, MAINTENANT
   * ------------------------------------------------------------------------
   * Trois écrans posent la même question — la salle de soins, l'hospitalisation
   * et la maternité. Y répondre une fois évite trois filtres divergents.
   * ---------------------------------------------------------------------- */
  function soinsDuSecteur(secteur) {
    return col('prescriptions').active().filter(function (pres) {
      return pres.statut === 'en_cours';
    }).map(function (pres) {
      var lignes = (pres.lignes || []).map(function (l, i) {
        var rang = rangSuivant(pres.id, i);
        var att = D.secteurAdministrateur(pres.modalite, rang);
        return {
          index: i, ligne: l, rang: rang,
          total: l.nbAdministrations || 1,
          secteur: att.secteur, motif: att.motif,
          du: rang <= (l.nbAdministrations || 1) && att.secteur === secteur,
          bloque: pres.statutPaiement !== 'payee',
        };
      }).filter(function (x) { return x.du; });
      return lignes.length ? { prescription: pres, lignes: lignes } : null;
    }).filter(Boolean);
  }

  /* ==========================================================================
   * CLOISONNEMENT DE L'ACCUEIL
   * --------------------------------------------------------------------------
   * L'accueil a besoin de l'identité, des coordonnées, de la couverture
   * d'assurance et des constantes qu'il relève lui-même. Il n'a aucun besoin
   * du diagnostic, des antécédents, des résultats d'analyse ni du traitement —
   * et RG-13 le lui interdit.
   *
   * DEUX PRINCIPES :
   *   1. Une restriction S'ANNONCE. Un filtre muet fait croire à une donnée
   *      manquante ; l'écran dit qui il est, ce qu'il ne voit pas et pourquoi.
   *   2. TOUTE recherche de dossier par l'accueil est JOURNALISÉE. C'est une
   *      demande expresse de la Direction : le dossier d'un voisin, d'un
   *      notable ou d'un employé se consulte trop facilement quand rien ne
   *      trace qui a regardé quoi.
   * ======================================================================== */
  var CHAMPS_ADMINISTRATIFS = ['code', 'nip', 'nom', 'prenom', 'sexe', 'dateNaissance', 'age',
    'telephone', 'quartier', 'adresse', 'profession', 'ethnie', 'personneContact',
    'assureur', 'assureurNom', 'numeroCarte', 'carteExpiration', 'tauxPriseEnCharge',
    'souscripteur', 'creeLe', 'heureArrivee', 'statut'];

  var CHAMPS_CLINIQUES = ['diagnostic', 'antecedents', 'allergies', 'traitement',
    'groupeSanguin', 'gsRh', 'te', 'hb', 'observations', 'motifConsultation'];

  /** L'accueil voit-il ce champ ? RG-13. */
  function accueilVoitChamp(nom) {
    return CHAMPS_ADMINISTRATIFS.indexOf(nom) !== -1;
  }

  /**
   * Le dossier tel que l'accueil a le droit de le voir. Renvoie la fiche
   * expurgée ET le motif — parce qu'une restriction s'annonce.
   */
  function dossierPourAccueil(patient) {
    if (!patient) return { fiche: null, motif: 'Dossier introuvable.' };
    var out = {};
    Object.keys(patient).forEach(function (k) {
      if (accueilVoitChamp(k) || k === 'id') out[k] = patient[k];
    });
    var masques = Object.keys(patient).filter(function (k) {
      return CHAMPS_CLINIQUES.indexOf(k) !== -1;
    });
    return {
      fiche: out,
      masques: masques,
      motif: 'RG-13 — l’accueil accède aux données administratives et à la couverture d’assurance. '
        + 'Les données cliniques (diagnostic, antécédents, résultats, traitement) lui sont fermées.',
    };
  }

  /**
   * Journalise une recherche de dossier. Demande expresse de la Direction :
   * le dossier d'un voisin ou d'un notable se consulte trop facilement quand
   * rien ne trace qui a regardé quoi.
   *
   * On journalise la CONSULTATION, pas seulement la modification : c'est le
   * regard qui pose problème ici, pas l'écriture.
   */
  function journaliserRecherche(patient, opts) {
    opts = opts || {};
    var s = S.session() || {};
    /* On passe par le mécanisme du magasin et NON par collection().insert() :
       insert() journalise à son tour, et une recherche produisait deux
       entrées — la sienne, plus une entrée fantôme décrivant son écriture. */
    return S.journaliserAcces({
      utilisateur: s.nom || S.currentUser(),
      role: s.role || null,
      action: opts.action || 'Consultation de dossier',
      module: 'M1', entite: 'Dossier patient',
      reference: patient ? patient.code : (opts.terme || null),
      cible: patient ? (patient.code + ' — ' + patient.nom + ' ' + patient.prenom) : (opts.terme || '—'),
      patientId: patient ? patient.id : null,
      ecran: opts.ecran || null,
      motif: opts.motif || null,
      /* Une recherche infructueuse se journalise aussi : chercher le dossier
         de quelqu'un qui n'est pas patient est en soi une information. */
      trouve: !!patient,
    });
  }

  /* ==========================================================================
   * CONTINUITÉ DU PRÉLÈVEMENT ET DE LA VALIDATION
   * --------------------------------------------------------------------------
   * Celui qui a fait le prélèvement est celui qui valide. Règle de PREUVE et
   * non d'organisation : le validateur atteste d'un échantillon, et s'il ne l'a
   * pas vu arriver il atteste de ce qu'un collègue lui a dit.
   *
   * La clinique compte DEUX biologistes médicaux ; la règle a donc un effet
   * réel — elle interdit que l'un valide le prélèvement de l'autre.
   * ======================================================================== */
  function continuiteRespectee(demande, agent) {
    if (!demande) return { ok: false, motif: 'Demande introuvable.' };
    var preleveur = demande.preleveParId || demande.prelevePar || null;
    /* Un prélèvement non encore fait ne peut pas être validé : c'est déjà la
       règle du circuit, on ne la redouble pas ici. */
    if (!preleveur) {
      return { ok: true, motif: 'Aucun prélèvement enregistré — la continuité ne s’applique pas encore.' };
    }
    var memeAgent = preleveur === (agent && (agent.id || agent))
      || preleveur === (agent && agent.nomComplet);
    if (memeAgent) return { ok: true, motif: null };
    return {
      ok: false,
      preleveur: demande.prelevePar || preleveur,
      motif: 'Le prélèvement a été fait par ' + (demande.prelevePar || preleveur)
        + '. C’est à lui de valider : un validateur qui n’a pas vu arriver l’échantillon '
        + 'atteste de ce qu’un collègue lui a dit, et la signature perd sa valeur.',
    };
  }

  /* ==========================================================================
   * BESOIN EN FONDS DE ROULEMENT ET PILOTAGE (BFR_TABLEAU.txt, 22/09/2026)
   * --------------------------------------------------------------------------
   * LE MOTEUR VIT AU SOCLE, ET C'EST LA SEULE PLACE POSSIBLE : le BFR se lit
   * depuis la comptabilité (M12), depuis le pilotage (PIL), depuis les deux
   * tableaux de bord de la Direction et depuis le moteur d'alertes, qui
   * n'appartient à aucun écran. Une page ne charge que le module du sien :
   * poser le calcul dans un module l'aurait rendu invisible aux quatre
   * autres, et quatre copies auraient divergé au premier correctif.
   *
   * IL NE FABRIQUE AUCUNE DONNÉE — il en agrège trois, déjà tenues ailleurs :
   *
   *   créances    ← M9, la MÊME définition que la balance âgée (part assureur
   *                 des factures assurées) + les restes à charge patients ;
   *   stocks      ← M6, valorisés par `S.valeurUnitaire`, donc selon la
   *                 méthode que la Direction a choisie (prix de vente ou
   *                 CUMP) — recalculer ici ferait diverger deux valorisations ;
   *   dettes      ← M7, les factures fournisseurs non réglées.
   *
   *   BFR = créances + stocks − dettes fournisseurs.
   *
   * UN COMPOSANT QUI MANQUE SE DIT. Si une collection n'est pas amorcée, on
   * ne la compte pas pour zéro : `incomplet` porte son nom, et les écrans
   * l'affichent. Un BFR amputé de ses dettes est SURESTIMÉ, et un chiffre
   * faux qui a l'air juste est ce que ce prototype refuse partout ailleurs.
   * ======================================================================== */

  function objectifsPilotage() {
    var col = S.collection('objectifsPilotage', { module: 'M12', entite: 'ObjectifPilotage' });
    var vivants = col.active();
    if (vivants.length) return vivants;
    /* Repli sur la semence : un poste dont la collection a été vidée doit
       encore pouvoir lire ses indicateurs, sans cible arrêtée. */
    return (D.OBJECTIFS_PILOTAGE || []).slice();
  }

  function objectifPilotage(id) {
    return objectifsPilotage().filter(function (o) { return o.id === id; })[0] || null;
  }

  /** La fenêtre d'observation : 90 jours glissants par défaut, bornes nommées. */
  function fenetrePilotage(opts) {
    var o = opts || {};
    var fin = o.fin ? C.toDate(o.fin) : C.aujourdhui();   /* la fenêtre glissante suit l'horloge (vague 68) */
    var debut = o.debut ? C.toDate(o.debut) : C.addDays(fin, -(o.jours || 90));
    return { debut: C.iso(debut), fin: C.iso(fin), jours: Math.max(1, C.daysBetween(debut, fin)) };
  }

  function dansFenetre(d, f) {
    var x = String(d || '').slice(0, 10);
    return !!x && x >= f.debut && x <= f.fin;
  }

  function facturesPilotage() { return S.collection('factures').active(); }

  /**
   * Les trois composantes et leur somme algébrique.
   * @param {Object} [opts] {fin, jours} — la fenêtre sert au CA, pas aux encours :
   *   un encours se lit À UNE DATE, un flux SUR UNE PÉRIODE. Les confondre
   *   ferait croire que le stock détenu dépend de la fenêtre qu'on regarde.
   */
  function bfr(opts) {
    var f = fenetrePilotage(opts);
    var manquants = [];
    var factures = facturesPilotage();

    /* 1 — EN-COURS CLIENTS. La part assureur suit la définition de la balance
       âgée de M9, au mot près : deux définitions du même encours se seraient
       contredites en réunion. */
    var assurees = factures.filter(function (x) { return !!x.assureur; });
    var creancesAssureurs = C.sum(assurees, 'partAssurance');
    var restesACharge = C.sum(factures.filter(function (x) {
      return x.statutPaiement !== 'soldee';
    }), function (x) { return Math.max(0, x.reliquat || 0); });

    /* 2 — STOCKS. La valorisation passe par le magasin, qui connaît la
       méthode en vigueur. */
    var produits = S.collection('produits').active();
    if (!produits.length) manquants.push('les produits du stock');
    var stocks = C.sum(produits, function (p) {
      return (p.stock || 0) * S.valeurUnitaire(p);
    });

    /* 3 — DETTES FOURNISSEURS. « payée » et « soldée » désignent la même
       chose selon l'écran par lequel la pièce est passée : on accepte les
       deux plutôt que d'en compter une comme impayée. */
    var ff = S.collection('facturesFournisseurs').active();
    if (!ff.length) manquants.push('les factures fournisseurs');
    var dettes = C.sum(ff.filter(function (x) {
      return ['payee', 'soldee'].indexOf(String(x.statutPaiement || '')) === -1;
    }), function (x) { return x.montantFacture || 0; });

    var caPeriode = C.sum(factures.filter(function (x) { return dansFenetre(x.date, f); }), 'montantTTC');
    var creances = creancesAssureurs + restesACharge;

    return {
      arrete: f.fin, fenetre: f,
      creancesAssureurs: creancesAssureurs,
      restesACharge: restesACharge,
      creances: creances,
      stocks: stocks,
      dettes: dettes,
      bfr: creances + stocks - dettes,
      caPeriode: caPeriode,
      /* Le BFR ramené en jours d'activité : c'est sous cette forme qu'il se
         compare d'un exercice à l'autre, une valeur absolue ne disant rien
         sans le chiffre d'affaires qui la porte. */
      bfrJours: caPeriode > 0 ? Math.round((creances + stocks - dettes) / (caPeriode / f.jours)) : null,
      nbFacturesAssurees: assurees.length,
      nbDettes: ff.filter(function (x) {
        return ['payee', 'soldee'].indexOf(String(x.statutPaiement || '')) === -1;
      }).length,
      incomplet: manquants,
    };
  }

  /** Les sorties valorisées de la période — le dénominateur de la rotation. */
  function sortiesValorisees(f) {
    var prods = {};
    S.collection('produits').active().forEach(function (p) { prods[p.id] = p; });
    var sortantes = ['sortie', 'perte', 'casse', 'peremption'];
    return C.sum(S.collection('mouvements').active().filter(function (m) {
      return sortantes.indexOf(m.type) !== -1 && dansFenetre(m.date, f);
    }), function (m) {
      var p = prods[m.produitId];
      return (m.quantite || 0) * (p ? S.valeurUnitaire(p) : 0);
    });
  }

  /** Le délai moyen de transmission des pièces assureur, en jours. */
  function delaiTransmission() {
    var meres = S.collection('facturesMere').active().filter(function (m) {
      return m.dateEmission && m.fin;
    });
    if (!meres.length) return null;
    return Math.round(C.sum(meres, function (m) {
      return Math.max(0, C.daysBetween(m.fin, m.dateEmission));
    }) / meres.length);
  }

  /**
   * La grille « objectif fixé / réel atteint ».
   * Chaque ligne porte son état : atteint · vigilance · alerte · indisponible.
   * INDISPONIBLE N'EST PAS ZÉRO — un indicateur qu'on ne sait pas calculer se
   * dit tel quel, faute de quoi la Direction lirait un échec là où il n'y a
   * qu'une donnée manquante.
   */
  function indicateursPilotage(opts) {
    var f = fenetrePilotage(opts);
    var b = bfr(opts);
    var reels = {};

    reels.dso = b.caPeriode > 0 ? Math.round(b.creances / (b.caPeriode / f.jours)) : null;
    reels.bfr_jours = b.bfrJours;

    /* L'ancienneté de la créance la plus vieille encore ouverte : c'est elle
       qui déclenche la relance, pas la moyenne — une moyenne rassurante peut
       cacher une pièce de huit mois. */
    var assurees = facturesPilotage().filter(function (x) { return !!x.assureur && (x.partAssurance || 0) > 0; });
    reels.creance_agee = assurees.length
      ? Math.max.apply(null, assurees.map(function (x) { return C.daysBetween(x.date, f.fin); }))
      : null;

    var lits = (D.CHAMBRES || []).reduce(function (n, ch) { return n + ch.lits.length; }, 0);
    var occupes = S.collection('admissions').active().filter(function (a) { return a.statut === 'en_cours'; }).length;
    reels.occupation_lits = lits ? Math.round(occupes / lits * 1000) / 10 : null;

    var sorties = sortiesValorisees(f);
    reels.rotation_stock = b.stocks > 0 && sorties > 0
      ? Math.round(sorties * (365 / f.jours) / b.stocks * 10) / 10 : null;
    reels.couverture_stock = sorties > 0 ? Math.round(b.stocks / (sorties / f.jours)) : null;

    reels.delai_transmission = delaiTransmission();

    var normalisables = facturesPilotage().filter(function (x) { return !!x.numeroMecef; });
    reels.facturation_normalisee = normalisables.length
      ? Math.round(normalisables.filter(function (x) { return x.statutMecef === 'valide'; }).length
        / normalisables.length * 1000) / 10
      : null;

    return objectifsPilotage().map(function (o) {
      var reel = reels[o.id];
      var etat = 'indisponible';
      if (reel != null) {
        var bas = o.sens !== 'haut';
        var atteint = bas ? reel <= o.cible : reel >= o.cible;
        var franchi = bas ? reel > o.alerte : reel < o.alerte;
        etat = atteint ? 'atteint' : (franchi ? 'alerte' : 'vigilance');
      }
      return {
        id: o.id, axe: o.axe, label: o.label, unite: o.unite,
        cible: o.cible, alerte: o.alerte, sens: o.sens,
        aValider: !!o.aValider, source: o.source, aide: o.aide,
        reel: reel, etat: etat,
        /* L'écart n'a de sens que rapporté au bon côté : un DSO de 30 jours
           pour une cible de 45 est une AVANCE, pas un retard. */
        ecart: reel == null ? null : (o.sens === 'haut' ? reel - o.cible : o.cible - reel),
      };
    });
  }

  /**
   * Les compagnies dont la créance dépasse le seuil d'ancienneté retenu.
   * Consommé par le moteur de notifications : il route, il ne décide pas du
   * seuil — celui-ci vit dans `objectifsPilotage`, où la Direction le règle.
   */
  function alertesRecouvrement(opts) {
    var f = fenetrePilotage(opts);
    var o = objectifPilotage('creance_agee');
    var seuil = o ? o.cible : 60;
    var parCompagnie = {};
    facturesPilotage().forEach(function (x) {
      if (!x.assureur || !(x.partAssurance > 0)) return;
      var jours = C.daysBetween(x.date, f.fin);
      if (jours <= seuil) return;
      var e = parCompagnie[x.assureur] || (parCompagnie[x.assureur] = {
        assureur: x.assureur, montant: 0, nb: 0, jours: 0,
      });
      e.montant += x.partAssurance;
      e.nb += 1;
      e.jours = Math.max(e.jours, jours);
    });
    return Object.keys(parCompagnie).map(function (k) { return parCompagnie[k]; })
      .sort(function (a, b2) { return b2.montant - a.montant; })
      .map(function (e) { return Object.assign({ seuil: seuil }, e); });
  }

  global.SIGH.parcours = {
    continuiteRespectee: continuiteRespectee,
    bfr: bfr, indicateursPilotage: indicateursPilotage,
    alertesRecouvrement: alertesRecouvrement, objectifsPilotage: objectifsPilotage,
    objectifPilotage: objectifPilotage, fenetrePilotage: fenetrePilotage,
    sortiesValorisees: sortiesValorisees, delaiTransmission: delaiTransmission,
    accueilVoitChamp: accueilVoitChamp,
    dossierPourAccueil: dossierPourAccueil,
    journaliserRecherche: journaliserRecherche,
    CHAMPS_CLINIQUES: CHAMPS_CLINIQUES,
    prescrireSoins: prescrireSoins, inscrireOrdonnance: inscrireOrdonnance,
    administrer: administrer, soinsDuSecteur: soinsDuSecteur,
    rangSuivant: rangSuivant,
    ecrireEncaissement: ecrireEncaissement, alerterStock: alerterStock,
    construireLignes: construireLignes, lignesDues: lignesDues, lignesReglees: lignesReglees,
    facturerPiece: facturerPiece, statutPiece: statutPiece,
    ouvrirDemandeExterne: ouvrirDemandeExterne,
    dossierExterne: dossierExterne,
    ouvrirDemandeImagerie: ouvrirDemandeImagerie,
    examenImagerieParCode: examenImagerieParCode,
    codeAnalyse: codeAnalyse,
    numeroBadge: numeroBadge, badgeQR: badgeQR, lireBadgeQR: lireBadgeQR,
    jetonEnquete: jetonEnquete,
    validerTechnique: validerTechnique, validerBiologique: validerBiologique,
    rectifierResultat: rectifierResultat,
    notifier: notifier, notifications: notifications, marquerLue: marquerLue,
    estPersonnel: estPersonnel, agentDe: agentDe,
    prendreEnChargePersonnel: prendreEnChargePersonnel,
    capacites: capacites, secteurCourant: secteurCourant, valoriserSortie: valoriserSortie,
    peutVoirResultat: peutVoirResultat, peutPrescrire: peutPrescrire,
    peutExecuterSoin: peutExecuterSoin, filtrerResultats: filtrerResultats,
    repartir: repartir, garantiesDe: garantiesDe, souscripteurDe: souscripteurDe,
    carteValide: carteValide, categoriser: categoriser, libelleUnite: libelleUnite,
    couvertureALaDate: couvertureALaDate, historiqueCouverture: historiqueCouverture,
    changerCouverture: changerCouverture,
    TACHES: TACHES,
    prescrire: prescrire, encaisser: encaisser, delivrer: delivrer,
    verifierStock: verifierStock,
    taches: taches, aFaire: aFaire, terminer: terminer, compteurs: compteurs,
    dossier: dossier,
  };


  /* ==========================================================================
   * EXERCICES COMPTABLES — sélecteur, lecture seule au moteur, clôture en deux
   * gestes (PRD-M12-cloture-exercice).
   * --------------------------------------------------------------------------
   * LE MOTEUR VIT AU SOCLE : le sélecteur d'exercice est lu par tous les écrans
   * de M12, de M9 et des tableaux de bord, et une page ne charge que le module
   * de son écran. Une clôture est un acte DÉFINITIF : un exercice clos ne se
   * rouvre pas (obligation légale), il se corrige par une écriture de l'exercice
   * suivant. La garde de lecture seule est posée sur la COLLECTION, pas sur
   * l'écran — un champ désactivé dans le navigateur ne protège rien.
   * ======================================================================== */
  var CLE_EXERCICE = 'sigh-cnt:exercice';
  var LETTRABLES = ['40', '41', '42', '43', '44', '47'];

  function anneeDe(date) { var d = C.toDate(date); return d && !isNaN(d) ? d.getFullYear() : null; }
  function anneeCourante() { return C.aujourdhui().getFullYear(); }

  /* Les exercices sont DÉRIVÉS : une fiche par année portée par les écritures,
     plus l'année courante, plus celle de la liasse déposée (close d'office —
     c'est un fait déposé à la DGI, non un exercice du logiciel). */
  function exercices() {
    var col = S.collection('exercices', { module: 'M12', entite: 'Exercice' });
    var annees = {};
    S.collection('ecritures').all().forEach(function (e) { var a = anneeDe(e.date); if (a) annees[a] = true; });
    annees[anneeCourante()] = true;
    if (global.SIGH.liasse && global.SIGH.liasse.DEPOT) {
      annees[global.SIGH.liasse.DEPOT.exerciceN] = true;
      annees[global.SIGH.liasse.DEPOT.exerciceN1] = true;
    }
    var ajoute = false;
    Object.keys(annees).forEach(function (a) {
      a = Number(a);
      if (col.all().some(function (x) { return x.annee === a; })) return;
      var deposee = !!(global.SIGH.liasse && global.SIGH.liasse.DEPOT && (global.SIGH.liasse.DEPOT.exerciceN === a || global.SIGH.liasse.DEPOT.exerciceN1 === a));
      col.all().unshift({
        id: 'EXO-' + a, annee: a, debut: a + '-01-01', fin: a + '-12-31', statut: 'actif',
        etat: deposee ? 'clos' : 'ouvert',
        source: deposee ? 'liasse' : 'journal',
        valideLe: deposee ? global.SIGH.liasse.DEPOT.dateDepot : null,
        validePar: deposee ? 'Liasse déposée à la DGI' : null,
        motif: deposee ? 'Exercice antérieur à la mise en service : fait par la liasse déposée.' : null,
      });
      ajoute = true;
    });
    if (ajoute) S.save();
    return col.all().filter(function (x) { return x.statut !== 'archive'; })
      .sort(function (a, b) { return b.annee - a.annee; });
  }
  function exercice(annee) { return exercices().filter(function (x) { return x.annee === Number(annee); })[0] || null; }
  function etatExercice(annee) { var x = exercice(annee); return x ? x.etat : 'ouvert'; }

  function exerciceChoisi() {
    var v = null;
    try { v = Number(global.localStorage.getItem(CLE_EXERCICE)); } catch (e) { /* stockage refusé */ }
    return v && exercice(v) ? v : anneeCourante();
  }
  function choisirExercice(annee) {
    try { global.localStorage.setItem(CLE_EXERCICE, String(annee)); } catch (e) { /* sans effet */ }
    return Number(annee);
  }

  /* La garde de lecture seule : posée sur la collection, refusée AVANT l'écriture. */
  S.garder('ecritures', function (op, rec) {
    var a = anneeDe(rec && rec.date);
    if (!a) return null;
    if (etatExercice(a) === 'clos') {
      var x = exercice(a);
      return 'Exercice ' + a + ' clos' + (x && x.valideLe ? ' le ' + C.dateFR(x.valideLe) : '')
        + ' — lecture seule. La correction passe par une écriture de l’exercice en cours.';
    }
    return null;
  });

  function sensLettrable(compte) {
    return LETTRABLES.some(function (p) { return String(compte).indexOf(p) === 0; });
  }

  /* Écritures VALIDÉES d'un exercice (un brouillon n'est pas un fait comptable). */
  function ecrituresDe(annee, inclureBrouillons) {
    return S.collection('ecritures').active().filter(function (e) {
      return anneeDe(e.date) === Number(annee) && (inclureBrouillons || e.statut === 'validee');
    });
  }

  function soldesParCompte(lignes) {
    var m = {};
    lignes.forEach(function (e) {
      var k = String(e.compte);
      if (!m[k]) m[k] = { compte: k, libelle: e.compteLibelle || k, debit: 0, credit: 0 };
      m[k].debit += Number(e.debit) || 0; m[k].credit += Number(e.credit) || 0;
    });
    return Object.keys(m).sort().map(function (k) { m[k].solde = m[k].debit - m[k].credit; return m[k]; });
  }

  /* Le résultat : classes 7 (+) moins 6 (−), HAO (8) compris. Positif = bénéfice. */
  function resultatDe(lignes) {
    var r = 0;
    lignes.forEach(function (e) {
      var cl = String(e.compte).charAt(0);
      if (cl === '6' || cl === '7' || cl === '8') r += (Number(e.credit) || 0) - (Number(e.debit) || 0);
    });
    return r;
  }

  /* Lignes de report (classes 1 à 5) vers N+1. Comptes NON lettrables : un solde
     global. Comptes de TIERS : ligne par ligne, uniquement les lignes NON lettrées —
     c'est ce qui permet de suivre sur le nouvel exercice les factures en attente. */
  function lignesDeReport(lignes) {
    var out = [];
    var bilan = lignes.filter(function (e) { return '12345'.indexOf(String(e.compte).charAt(0)) >= 0; });
    var tiers = bilan.filter(function (e) { return sensLettrable(e.compte); });
    var autres = bilan.filter(function (e) { return !sensLettrable(e.compte); });
    soldesParCompte(autres).forEach(function (s) {
      if (Math.abs(s.solde) < 1) return;
      out.push({ compte: s.compte, compteLibelle: s.libelle, debit: s.solde > 0 ? s.solde : 0, credit: s.solde < 0 ? -s.solde : 0, lettrable: false });
    });
    tiers.filter(function (e) { return !e.lettrage; }).forEach(function (e) {
      var net = (Number(e.debit) || 0) - (Number(e.credit) || 0);
      if (Math.abs(net) < 1) return;
      out.push({ compte: String(e.compte), compteLibelle: e.compteLibelle, debit: net > 0 ? net : 0, credit: net < 0 ? -net : 0,
        lettrable: true, pieceOrigine: e.numero, libelle: 'Report — ' + (e.libelle || e.numero) });
    });
    return out;
  }

  /* À-NOUVEAUX PROVISOIRES : tant que N n'est pas clos, N+1 voit un report calculé
     des soldes validés de N, RECALCULÉ à chaque lecture et jamais stocké. Le
     résultat de N (non encore soldé) est porté au compte 131 / 139. */
  function aNouveauxProvisoires(annee) {
    var prec = Number(annee) - 1;
    var ex = exercice(prec);
    if (!ex || ex.etat === 'clos' || ex.source === 'liasse') return [];
    var base = ecrituresDe(prec);
    var lignes = lignesDeReport(base);
    var res = resultatDe(base);
    if (Math.abs(res) >= 1) {
      lignes.push({ compte: res >= 0 ? '131000' : '139000', compteLibelle: res >= 0 ? 'Résultat net : bénéfice' : 'Résultat net : perte',
        debit: res < 0 ? -res : 0, credit: res > 0 ? res : 0, lettrable: false });
    }
    return lignes.map(function (l) {
      return Object.assign({ id: 'PROV-' + annee + '-' + l.compte + '-' + (l.pieceOrigine || 'S'), numero: 'AN-PROV-' + annee,
        date: annee + '-01-01', journal: 'AN', journalLibelle: 'Journal des à-nouveaux (provisoire)',
        libelle: l.libelle || 'À-nouveau provisoire', statut: 'validee', provisoire: true, origine: 'Provisoire — calculé' }, l);
    });
  }

  /* PRÉ-CLÔTURE : contrôles nommés, chacun avec les pièces en cause et l'écran où corriger. */
  function preCloture(annee) {
    annee = Number(annee);
    var tous = ecrituresDe(annee, true);
    var validees = tous.filter(function (e) { return e.statut === 'validee'; });
    var brouillons = tous.filter(function (e) { return e.statut === 'brouillon'; });
    var controles = [];
    controles.push({ id: 'brouillons', bloquant: true, ok: brouillons.length === 0,
      libelle: 'Aucune écriture en brouillon', ecran: 'm12-ecritures',
      detail: brouillons.length ? brouillons.length + ' ligne(s) en brouillon, dont ' + brouillons.slice(0, 4).map(function (e) { return e.numero; })
        .filter(function (v, i, a) { return a.indexOf(v) === i; }).join(', ') + '.' : '' });
    var d = C.sum(validees, 'debit'), c = C.sum(validees, 'credit');
    controles.push({ id: 'equilibre', bloquant: true, ok: Math.abs(d - c) < 1,
      libelle: 'Journal équilibré (RG-10)', ecran: 'm12-balance',
      detail: Math.abs(d - c) < 1 ? '' : 'Écart de ' + C.money(Math.abs(d - c)) + ' entre débit et crédit.' });
    var pieces = {};
    validees.forEach(function (e) { var p = pieces[e.numero] || (pieces[e.numero] = { d: 0, c: 0 }); p.d += Number(e.debit) || 0; p.c += Number(e.credit) || 0; });
    var boiteuses = Object.keys(pieces).filter(function (k) { return Math.abs(pieces[k].d - pieces[k].c) >= 1; });
    controles.push({ id: 'pieces', bloquant: true, ok: boiteuses.length === 0,
      libelle: 'Chaque pièce validée est équilibrée', ecran: 'm12-ecritures',
      detail: boiteuses.length ? boiteuses.length + ' pièce(s) déséquilibrée(s) : ' + boiteuses.slice(0, 4).join(', ') + '.' : '' });
    var an = S.collection('ecritures').active().filter(function (e) { return anneeDe(e.date) === annee + 1 && e.journal === 'AN'; });
    controles.push({ id: 'an-existants', bloquant: true, ok: an.length === 0,
      libelle: 'Aucun à-nouveau déjà écrit sur ' + (annee + 1), ecran: 'm12-ouverture',
      detail: an.length ? 'Des à-nouveaux existent (' + an[0].numero + ') : les archiver avant de clôturer, la clôture écrit les définitifs.' : '' });
    var attente = validees.filter(function (e) { return String(e.compte).indexOf('47') === 0; });
    var solde47 = C.sum(attente, 'debit') - C.sum(attente, 'credit');
    controles.push({ id: 'compte-47', bloquant: false, ok: Math.abs(solde47) < 1,
      libelle: 'Comptes d’attente (47x) soldés', ecran: 'm12-grand-livre',
      detail: Math.abs(solde47) < 1 ? '' : 'Solde de ' + C.money(Math.abs(solde47)) + ' à régulariser.' });
    controles.push({ id: 'ecritures', bloquant: true, ok: validees.length > 0,
      libelle: 'L’exercice porte des écritures validées', ecran: 'm12-ecritures', detail: validees.length ? '' : 'Aucune écriture validée en ' + annee + '.' });
    return { annee: annee, controles: controles, bloquants: controles.filter(function (x) { return x.bloquant && !x.ok; }),
      resultat: resultatDe(validees), nbEcritures: validees.length };
  }

  function acteur() { var s = S.session && S.session(); return (s && (s.nomComplet || s.nom)) || 'Utilisateur'; }
  function roleCourant() { var s = S.session && S.session(); return (s && s.role) || ''; }

  /* GESTE 1 — la demande (comptable). Les contrôles bloquants refusent EN LES NOMMANT. */
  function demanderCloture(annee) {
    annee = Number(annee);
    var x = exercice(annee);
    if (!x) return { ok: false, motif: 'Exercice ' + annee + ' inconnu.' };
    if (x.etat === 'clos') return { ok: false, motif: 'Exercice ' + annee + ' déjà clos.' };
    if (x.etat === 'en_attente_cloture') return { ok: false, motif: 'La clôture de ' + annee + ' attend déjà la validation de la Direction.' };
    var pre = preCloture(annee);
    if (pre.bloquants.length) return { ok: false, motif: 'Pré-clôture refusée — ' + pre.bloquants.map(function (b) { return b.libelle + (b.detail ? ' (' + b.detail + ')' : ''); }).join(' ; '), pre: pre };
    S.collection('exercices').update(x.id, { etat: 'en_attente_cloture', demandeLe: new Date().toISOString(), demandePar: acteur(), resultatPrevu: pre.resultat });
    S.log('Demande de clôture', 'M12', 'Exercice', String(annee), { etat: 'ouvert' }, { etat: 'en_attente_cloture', resultat: pre.resultat });
    notifier({ type: 'cloture', poste: 'direction', libelle: 'Clôture ' + annee + ' à valider', detail: 'Le comptable a demandé la clôture de l’exercice ' + annee + '.', priorite: 'haute', reference: String(annee) });
    return { ok: true, pre: pre };
  }

  /* Empreinte SHA-256 synchrone (FIPS 180-4) de l'export d'archive. */
  function sha256(texte) {
    var K = [0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2];
    var H = [0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19];
    var b = unescape(encodeURIComponent(texte)), l = b.length, w = [], i, j;
    for (i = 0; i < l; i++) w[i >> 2] |= b.charCodeAt(i) << (24 - (i % 4) * 8);
    w[l >> 2] |= 0x80 << (24 - (l % 4) * 8);
    var n = (((l + 8) >> 6) + 1) * 16; w[n - 1] = l * 8; for (i = 0; i < n; i++) w[i] = w[i] | 0;
    var rotr = function (x, k) { return (x >>> k) | (x << (32 - k)); };
    for (i = 0; i < n; i += 16) {
      var s = w.slice(i, i + 16), a = H.slice();
      for (j = 16; j < 64; j++) {
        var s0 = rotr(s[j - 15], 7) ^ rotr(s[j - 15], 18) ^ (s[j - 15] >>> 3), s1 = rotr(s[j - 2], 17) ^ rotr(s[j - 2], 19) ^ (s[j - 2] >>> 10);
        s[j] = (s[j - 16] + s0 + s[j - 7] + s1) | 0;
      }
      for (j = 0; j < 64; j++) {
        var S1 = rotr(a[4], 6) ^ rotr(a[4], 11) ^ rotr(a[4], 25), ch = (a[4] & a[5]) ^ (~a[4] & a[6]);
        var t1 = (a[7] + S1 + ch + K[j] + s[j]) | 0, S0 = rotr(a[0], 2) ^ rotr(a[0], 13) ^ rotr(a[0], 22);
        var mj = (a[0] & a[1]) ^ (a[0] & a[2]) ^ (a[1] & a[2]), t2 = (S0 + mj) | 0;
        a = [(t1 + t2) | 0, a[0], a[1], a[2], (a[3] + t1) | 0, a[4], a[5], a[6]];
      }
      for (j = 0; j < 8; j++) H[j] = (H[j] + a[j]) | 0;
    }
    return H.map(function (v) { return ('00000000' + (v >>> 0).toString(16)).slice(-8); }).join('');
  }

  /* GESTE 2 — la validation (Direction / DAF), par une personne DIFFÉRENTE de celle qui a demandé. */
  function validerCloture(annee, motif) {
    annee = Number(annee);
    var x = exercice(annee);
    if (!x || x.etat !== 'en_attente_cloture') return { ok: false, motif: 'Aucune demande de clôture en attente pour ' + annee + '.' };
    if (['da', 'direction', 'admin'].indexOf(roleCourant()) < 0) return { ok: false, motif: 'La clôture est validée par la Direction ou la Directrice Administrative.' };
    if (!motif || String(motif).trim().length < 3) return { ok: false, motif: 'Un motif est obligatoire pour valider une clôture.' };
    if (x.demandePar === acteur()) return { ok: false, motif: 'Signer n’est pas saisir : la validation doit venir d’une autre personne que le demandeur (' + x.demandePar + ').' };
    var pre = preCloture(annee);
    if (pre.bloquants.length) return { ok: false, motif: 'Contrôles bloquants à nouveau en échec : ' + pre.bloquants.map(function (b) { return b.libelle; }).join(' ; ') };

    var col = S.collection('ecritures', { module: 'M12', entite: 'Écriture' });
    var base = ecrituresDe(annee);
    var res = resultatDe(base);

    /* (1) Détermination du résultat : chaque compte 6/7/8 est soldé vers 131 / 139 — UNE pièce équilibrée. */
    var numOD = 'OD-' + annee + '-RES';
    var odBase = { numero: numOD, date: annee + '-12-31', journal: 'OD', journalLibelle: 'Journal des opérations diverses',
      libelle: 'Détermination du résultat ' + annee, origine: 'Clôture — résultat', statut: 'validee', origineCloture: 'resultat', centreCout: null };
    var lignesOD = [];
    soldesParCompte(base.filter(function (e) { return '678'.indexOf(String(e.compte).charAt(0)) >= 0; })).forEach(function (s) {
      if (Math.abs(s.solde) < 1) return;
      lignesOD.push(Object.assign({}, odBase, { compte: s.compte, compteLibelle: s.libelle, debit: s.solde < 0 ? -s.solde : 0, credit: s.solde > 0 ? s.solde : 0 }));
    });
    if (Math.abs(res) >= 1) {
      lignesOD.push(Object.assign({}, odBase, { compte: res >= 0 ? '131000' : '139000', compteLibelle: res >= 0 ? 'Résultat net : bénéfice' : 'Résultat net : perte',
        debit: res < 0 ? -res : 0, credit: res > 0 ? res : 0 }));
    }
    var dOD = C.sum(lignesOD, 'debit'), cOD = C.sum(lignesOD, 'credit');
    if (Math.abs(dOD - cOD) >= 1) return { ok: false, motif: 'Pièce de résultat déséquilibrée (' + C.money(Math.abs(dOD - cOD)) + ') — clôture refusée (RG-10).' };
    lignesOD.forEach(function (l) { col.insert(l); });

    /* (2) À-nouveaux DÉFINITIFS au 1er janvier N+1, calculés APRÈS la pièce de résultat. */
    var apres = ecrituresDe(annee);
    var report = lignesDeReport(apres);
    var anBase = { numero: 'AN-' + (annee + 1) + '-00001', date: (annee + 1) + '-01-01', journal: 'AN', journalLibelle: 'Journal des à-nouveaux',
      libelle: 'À-nouveaux au 1er janvier ' + (annee + 1), origine: 'Clôture — à-nouveaux', statut: 'validee', origineCloture: 'an', centreCout: null };
    var dAN = 0, cAN = 0;
    report.forEach(function (l) {
      dAN += l.debit; cAN += l.credit;
    });
    if (Math.abs(dAN - cAN) >= 1) {
      /* Les lignes lettrées exclues ne peuvent pas déséquilibrer un report si le lettrage est équilibré :
         un écart dit un lettrage faux, on refuse plutôt que de propager. */
      return { ok: false, motif: 'À-nouveaux déséquilibrés (' + C.money(Math.abs(dAN - cAN)) + ') : vérifier les lettrages. L’exercice reste ouvert.', resteOD: numOD };
    }
    report.forEach(function (l) {
      col.insert(Object.assign({}, anBase, { compte: l.compte, compteLibelle: l.compteLibelle, debit: l.debit, credit: l.credit,
        libelle: l.libelle || anBase.libelle, pieceOrigine: l.pieceOrigine || null }));
    });

    /* (3) Archive : empreinte du journal ARRÊTÉ, puis état « clos » — en dernier. */
    var arret = ecrituresDe(annee);
    var texte = arret.map(function (e) { return [e.numero, e.date, e.journal, e.compte, e.debit, e.credit].join('|'); }).sort().join('\n');
    var empreinte = sha256(texte);
    S.collection('exercices').update(x.id, { etat: 'clos', valideLe: new Date().toISOString(), validePar: acteur(), motif: String(motif).trim(),
      resultat: res, empreinte: empreinte, nbEcrituresArchivees: arret.length, anNumero: anBase.numero });
    if (!exercice(annee + 1)) {
      S.collection('exercices').all().unshift({ id: 'EXO-' + (annee + 1), annee: annee + 1, debut: (annee + 1) + '-01-01', fin: (annee + 1) + '-12-31',
        statut: 'actif', etat: 'ouvert', source: 'journal' });
    }
    S.log('Clôture d’exercice', 'M12', 'Exercice', String(annee), { etat: 'en_attente_cloture' }, { etat: 'clos', resultat: res, empreinte: empreinte });
    notifier({ type: 'cloture', poste: 'comptable', libelle: 'Exercice ' + annee + ' clos', detail: 'Résultat ' + C.money(res) + ' ; à-nouveaux ' + (annee + 1) + ' écrits.', reference: String(annee) });
    S.save();
    /* L'archive de conservation naît AVEC la clôture, par quelque porte qu'elle soit validée : un exercice
       clos sans archive serait un exercice dont la conservation dépend d'un geste qu'on peut oublier. */
    var archive = null;
    try { archive = archiverExercice(annee); } catch (e) { if (global.console) global.console.error('[SIGH] archive de clôture', e); }
    return { ok: true, resultat: res, empreinte: empreinte, lignesAN: report.length, archive: archive ? archive.reference : null };
  }

  /**
   * L'ARCHIVE DE CLÔTURE DANS LA GED. L'obligation de conservation (dix ans, OHADA) se tient là où la
   * clinique range ses pièces. La fiche porte la balance générale de l'exercice figé et son EMPREINTE
   * SHA-256 : l'exercice étant en lecture seule au moteur, le grand livre se rééditera à l'identique, et
   * l'empreinte le prouve. UNE archive par exercice : en déposer deux créerait deux « vérités » à conserver.
   * Retourne la fiche (existante ou nouvelle) ; `.deja` dit qu'elle existait.
   */
  function archiverExercice(annee) {
    var col = S.collection('documents', { module: 'GED', entite: 'Document' });
    var code = 'EX' + annee;
    var deja = col.active().filter(function (d) { return d.codeRattachement === code; })[0];
    if (deja) return Object.assign({}, deja, { deja: true });
    var f = exercice(annee) || { annee: annee };
    var esc = function (v) { v = v == null ? '' : String(v); return /[;"\n]/.test(v) ? '"' + v.replace(/"/g, '""') + '"' : v; };
    var csv = ['Compte;Intitulé;Débit;Crédit'].concat(soldesParCompte(ecrituresDe(annee)).map(function (l) {
      return [l.compte, l.libelle, l.debit, l.credit].map(esc).join(';');
    })).join('\n');
    var an = String(C.aujourdhui().getFullYear()), rang = 0;
    col.all().forEach(function (d) {
      var m = new RegExp('^DOC-' + an + '-(\\d+)$').exec(String(d.reference || ''));
      if (m) rang = Math.max(rang, Number(m[1]));
    });
    var empBalance = sha256(csv);
    var r = col.insert({
      reference: 'DOC-' + an + '-' + ('00000' + (rang + 1)).slice(-5),
      libelle: 'Clôture de l’exercice ' + annee + ' — balance générale (empreinte ' + String(f.empreinte || empBalance).slice(0, 12) + '…)',
      categorie: 'cloture_exercice', rattachement: 'Administration', rattacheA: 'Exercice ' + annee, codeRattachement: code,
      format: 'CSV', taille: csv.length, version: 1, signe: true, archive: true, etatValidation: 'valide', conservation: 10,
      consultations: 0, date: C.iso(C.aujourdhui()), deposePar: (S.session() || {}).nom || '—',
      empreinte: f.empreinte || empBalance, empreinteBalance: empBalance, resultat: f.resultat == null ? null : f.resultat, contenu: csv,
    });
    return Object.assign({}, r.record, { deja: false });
  }

  /* LETTRAGE : un ensemble de lignes d'UN compte de tiers dont le total s'annule. */
  function lettrer(compte, ids) {
    if (!sensLettrable(compte)) return { ok: false, motif: 'Le compte ' + compte + ' n’est pas lettrable (comptes de tiers seulement).' };
    var col = S.collection('ecritures');
    var lignes = (ids || []).map(function (id) { return col.get(id); });
    if (lignes.length < 2 || lignes.some(function (l) { return !l || String(l.compte) !== String(compte) || l.lettrage; }))
      return { ok: false, motif: 'Sélection invalide : au moins deux lignes, du même compte, non encore lettrées.' };
    var net = C.sum(lignes, 'debit') - C.sum(lignes, 'credit');
    if (Math.abs(net) >= 1) return { ok: false, motif: 'Lettrage refusé — l’ensemble ne s’annule pas (écart ' + C.money(Math.abs(net)) + ').' };
    var code = String.fromCharCode(65 + (col.all().filter(function (e) { return e.lettrage; }).map(function (e) { return e.lettrage; })
      .filter(function (v, i, a) { return a.indexOf(v) === i; }).length % 26));
    lignes.forEach(function (l) { col.update(l.id, { lettrage: code, lettreLe: new Date().toISOString(), lettrePar: acteur() }); });
    return { ok: true, code: code, lignes: lignes.length };
  }
  function delettrer(compte, code, motif) {
    if (!motif || String(motif).trim().length < 3) return { ok: false, motif: 'Un motif est obligatoire pour dé-lettrer.' };
    var col = S.collection('ecritures'), n = 0;
    col.all().filter(function (e) { return String(e.compte) === String(compte) && e.lettrage === code; })
      .forEach(function (l) { col.update(l.id, { lettrage: null, delettreLe: new Date().toISOString(), delettreMotif: String(motif).trim() }); n++; });
    return n ? { ok: true, lignes: n } : { ok: false, motif: 'Aucune ligne lettrée « ' + code + ' » sur ce compte.' };
  }

  /** La date tombe-t-elle dans l'exercice choisi ? (écrans de flux : registre fiscal, avoirs…) */
  function dansExerciceChoisi(date) { return !date || anneeDe(date) === exerciceChoisi(); }
  /** La fenêtre de l'exercice choisi : du 1er janvier au 31 décembre, ou à aujourd'hui pour l'année en cours. */
  function fenetreExercice() {
    var a = exerciceChoisi(), auj = C.aujourdhui(), fin = a >= auj.getFullYear() ? auj : new Date(a, 11, 31);
    return { annee: a, debut: C.iso(new Date(a, 0, 1)), fin: C.iso(fin) };
  }

  global.SIGH.exercice = {
    dansExercice: dansExerciceChoisi, fenetre: fenetreExercice,
    liste: exercices, de: exercice, etat: etatExercice, choisi: exerciceChoisi, choisir: choisirExercice,
    anneeDe: anneeDe, ecrituresDe: ecrituresDe, soldes: soldesParCompte, resultat: resultatDe,
    provisoires: aNouveauxProvisoires, preCloture: preCloture, demander: demanderCloture, valider: validerCloture,
    lettrer: lettrer, delettrer: delettrer, lettrable: sensLettrable, sha256: sha256, archiver: archiverExercice,
  };

  /* Le moteur du BFR est EXPOSÉ pour être SONDÉ, jamais recopié : le scénario
     l'interroge et compare ses trois composantes à un recompte du magasin. */
  global.SIGH.bfr = {
    calculer: bfr, indicateurs: indicateursPilotage,
    alertes: alertesRecouvrement, objectifs: objectifsPilotage,
  };
})(window);
