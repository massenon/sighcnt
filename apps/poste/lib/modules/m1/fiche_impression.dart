import 'package:flutter/material.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../donnees/magasin.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m5/res_commun.dart' show profilLabo;
import 'commun_m1.dart';

/// LE DOSSIER PATIENT IMPRIMÉ EST LE DOSSIER ENTIER (05/11/2026, maquette `etatFiche` + `sectionsImprimables`).
///
/// L'état imprimé ne portait que l'identité et vingt consultations : le dossier de consultation, les antécédents, les soins, les hospitalisations, la
/// maternité, les analyses, l'imagerie, les ordonnances, le domicile, les finances, l'assurance et la traçabilité ne sortaient pas. Chaque section reprend
/// les MÊMES données que la rubrique de l'écran (`fiche.dart`), donc les mêmes droits : un résultat d'analyse ou un compte rendu d'imagerie hors du
/// périmètre du profil reste hors du papier.
List<BlocPiece> blocsDossierComplet(ContexteEcran c, Fiche p) {
  final m = c.magasin;
  final maintenant = c.aujourdhui;
  String t(Object? v, [String vide = '—']) => patVrai(v) ? '$v' : vide;
  List<Fiche> tri(List<Fiche> l, String cle) => trierPar(l, (f) => f[cle], descendant: true);
  List<Fiche> sien(String nom) => [
        for (final x in m.collection(nom).actives)
          if (x['patientId'] == p['id']) x
      ];
  String statut(Object? cle) => statutsMetier['$cle']?.$1 ?? (cle == null || cle == '' ? '—' : '$cle');
  BlocTableau kv(String titre, List<(String, String)> lignes) => BlocTableau(
      TableauEtat(colonnes: [
        ColonneEtat(libelle: 'Rubrique', valeur: (l) => l['k']),
        ColonneEtat(libelle: 'Information', valeur: (l) => l['v']),
      ], lignes: [
        for (final l in lignes) {'k': l.$1, 'v': l.$2}
      ]),
      titre: titre);
  BlocTableau tab(String titre, List<(String, String Function(Fiche))> cols, List<Fiche> lignes) =>
      BlocTableau(TableauEtat(colonnes: [for (final k in cols) ColonneEtat(libelle: k.$1, valeur: k.$2)], lignes: lignes), titre: titre);
  BlocTableau vide(String titre, String texte) => kv(titre, [('Information', texte)]);

  final couvertures = m.collection('couverturesAssurance').actives;
  final valide = patCarteValide(p, couvertures, maintenant);
  final age = patAge(p, maintenant);
  final consultations = sien('consultations').where((x) => x['type'] != 'Domicile').toList();
  final domicile = sien('consultations').where((x) => x['type'] == 'Domicile').toList();
  final admissions = sien('admissions');
  final observations = sien('observations');
  final idsAdm = admissions.map((a) => a['id']).toSet();
  final temperatures = [
    for (final r in m.collection('releves').actives)
      if (idsAdm.contains(r['admissionId'])) r
  ];
  final visites = sien('visitesPatients');
  final sorties = [
    for (final a in admissions)
      if (a['statut'] == 'sortie' || patVrai(a['dateSortie'])) a
  ];
  final sortiesAvis = sien('sortiesAvisMedical');
  final maternite = sien('suiviMaternite');
  final accouchements = sien('accouchements');
  final naissances = [
    for (final n in m.collection('naissances').actives)
      if (n['mereId'] == p['id'] || n['patientId'] == p['id']) n
  ];
  final deces = sien('deces');
  final analyses = sien('demandesAnalyses');
  final imageries = sien('demandesImagerie');
  final crImagerie = sien('resultatsImagerie');
  final ordonnances = sien('ordonnances');
  final factures = sien('factures');
  final soins = sien('soins');
  final profil = profilLabo(c);

  final blocs = <BlocPiece>[];

  // --- Identité et couverture ---------------------------------------------------------------------------------------------------------------
  blocs.add(kv('Identité et couverture', [
    ('Code dossier', t(p['code'])),
    ('Nom et prénoms', '${p['nom']} ${p['prenom']}'),
    ('Sexe', p['sexe'] == 'F' ? 'Féminin' : 'Masculin'),
    ('Date de naissance', patVrai(p['dateNaissance']) ? '${dateFrM1(p['dateNaissance'])}${age != null ? ' ($age ans)' : ''}' : 'Inconnue : ${ageTexte(p, maintenant)}'),
    ('Téléphone', t(p['telephone'])),
    ('Quartier', t(p['quartier'])),
    ('Adresse', t(p['adresse'])),
    ('Personne à prévenir', t(p['personneAPrevenir'])),
    ('Groupe sanguin', t(p['groupeSanguin'])),
    ('Dossier créé le', dateFrM1(p['dateCreation'])),
    (
      'Couverture',
      patVrai(p['assureur'])
          ? '${t(p['assureurNom'], '${p['assureur']}')}, ${valide ? 'carte valide' : 'CARTE NON VALIDE'} (au ${dateFrM1(p['carteExpiration'])})'
          : 'Non assuré : facturation intégrale au patient'
    ),
  ]));

  // --- Dossier de consultation (le dernier dossier ouvert) ----------------------------------------------------------------------------------
  final dossiers = [
    for (final d in m.collection('dossiersConsultation').actives)
      if (d['patientId'] == p['id'] || d['patientCode'] == p['code']) d
  ];
  if (dossiers.isEmpty) {
    blocs.add(vide('Dossier de consultation', 'Aucun dossier de consultation ouvert pour ce patient.'));
  } else {
    final d = tri(dossiers, 'dateArrivee').first;
    final venue = patVrai(d['dateArrivee']) ? '${dateFrM1(d['dateArrivee'])}${patVrai(d['heureArrivee']) ? ' à ${d['heureArrivee']}' : ''}' : '—';
    final saisie = patVrai(d['ouvertLe']) ? dateHeureM1(d['ouvertLe']) : '—';
    final ca = d['constantesAccueil'];
    blocs.add(kv('Dossier de consultation', [
      ('Dossier', '${t(d['reference'])}, venue du $venue, enregistré le $saisie${patVrai(d['soignant']) ? ', par ${d['soignant']}' : ''}'),
      ('Motif de consultation', t(d['motifVenue'])),
      ('Type de venue', t(d['typeVenue'])),
      ('Histoire de la maladie', t(d['histoire'])),
      ('Traitements en cours', t(d['traitementEnCours'])),
      for (final k in patCategoriesAntecedent) ('Antécédents : ${k.$2}', t(d['ant_${k.$1}'])),
      ('Allergies', t(d['allergies'] ?? p['allergies'])),
      ('Allergies médicamenteuses', t(d['allergiesMedicamenteuses'])),
      ('Statut vaccinal', t(d['statutVaccinal'])),
      ('Groupe sanguin', t(d['groupeSanguin'] ?? p['groupeSanguin'])),
      ('Électrophorèse Hb', t(d['electrophoreseHb'])),
      ('Dépistage', t(d['depistage'])),
      if (ca is Map) ...[
        ('Constantes de l’accueil, relevées le', patVrai(ca['date']) ? dateHeureM1(ca['date']) : '—'),
        ('Température', ca['temperature'] != null ? '${ca['temperature']} °C' : '—'),
        ('Tension', t(ca['tension'])),
        ('Poids', ca['poids'] != null ? '${ca['poids']} kg' : '—'),
        ('Pouls', ca['pouls'] != null ? '${ca['pouls']} /min' : '—'),
      ],
    ]));
    final ex = patSyntheseExamen(patExamensPhysiquesDe(d));
    blocs.add(ex.isEmpty
        ? vide('Examen physique par appareil (IPPOA)', 'Aucun appareil renseigné à l’examen physique de ce dossier.')
        : tab('Examen physique par appareil (IPPOA)', [
            ('Appareil', (x) => '${x['label']}'),
            ('Examiné le', (x) => venue),
            ('Porté au dossier le', (x) => saisie),
            ('Constat', (x) => x['normal'] == true ? 'RAS : normal' : '${x['texte']}'),
          ], [
            for (final l in ex) {'label': l.label, 'normal': l.normal, 'texte': l.texte}
          ]));
  }

  // --- Médical -------------------------------------------------------------------------------------------------------------------------------
  blocs.add(consultations.isEmpty
      ? vide('Médical', 'Aucune consultation enregistrée.')
      : tab('Médical', [
          ('Date', (x) => dateFrM1(x['date'])),
          ('Motif', (x) => t(x['motif'], '')),
          ('Diagnostic', (x) => t(x['diagnostic'], '')),
          ('Médecin', (x) => t(x['medecin'], '')),
        ], tri(consultations, 'date')));

  // --- Antécédents et allergies --------------------------------------------------------------------------------------------------------------
  blocs.add(kv('Antécédents & allergies', [
    ('Antécédents', patTexteListe(p['antecedents'], 'Aucun antécédent notable')),
    ('Autres antécédents', t(p['antecedentsAutres'])),
    ('Allergies connues', patTexteListe(p['allergies'], 'Aucune allergie connue')),
    ('Traitement en cours', t(p['traitementEnCours'])),
    ('Groupe sanguin', t(p['groupeSanguin'])),
  ]));

  // --- Soins ---------------------------------------------------------------------------------------------------------------------------------
  blocs.add(soins.isEmpty
      ? vide('Soins', 'Aucun acte de soins enregistré pour ce patient.')
      : tab('Soins', [
          ('Date', (x) => '${dateFrM1(x['date'])} à ${x['heure']}'),
          ('Acte', (x) => t(x['acte'], '')),
          ('Produit utilisé', (x) => t(x['produit'])),
          ('Soignant', (x) => t(x['soignant'], '')),
          ('État', (x) => statut(x['etat'] == 'realise' ? 'validee' : 'planifiee')),
        ], tri(soins, 'date')));

  // --- Hospitalisations ----------------------------------------------------------------------------------------------------------------------
  blocs.add(admissions.isEmpty
      ? vide('Hospitalisations', 'Aucune hospitalisation.')
      : tab('Hospitalisations : admissions et lits occupés', [
          ('Entrée', (x) => dateFrM1(x['dateEntree'])),
          ('Sortie', (x) => patVrai(x['dateSortie']) ? dateFrM1(x['dateSortie']) : 'en cours'),
          ('Chambre', (x) => t(x['chambre'])),
          ('Lit', (x) => t(x['lit'])),
          ('Diagnostic', (x) => t(x['diagnosticEntree'], '')),
          ('Statut', (x) => statut(x['statut'])),
        ], tri(admissions, 'dateEntree')));
  if (observations.isNotEmpty) {
    blocs.add(tab('Mises en observation', [
      ('Entrée', (x) => dateFrM1(x['dateEntree'])),
      ('Motif', (x) => t(x['motif'], '')),
      ('Unité', (x) => '${x['uniteLabel'] ?? ''}'.replaceAll('Salle d’observation — ', '')),
      ('Constantes', (x) => '${((x['constantes'] as List?) ?? const []).length}'),
      ('Issue', (x) => t(x['orientationLabel'], 'en cours')),
    ], tri(observations, 'dateEntree')));
  }
  blocs.add(temperatures.isEmpty
      ? vide('Feuilles de température', 'Aucune feuille de température : le patient n’a pas séjourné.')
      : tab('Feuilles de température', [
          ('Date', (x) => '${dateFrM1(x['date'])}${patVrai(x['heure']) ? ' ${x['heure']}' : ''}'),
          ('Température', (x) => '${patVrai(x['temperature']) ? x['temperature'] : t(x['matin'])} °C'),
          ('Tension', (x) => t(x['tension'])),
          ('Pouls', (x) {
            final v = x['fc'] ?? x['pouls'];
            return patVrai(v) ? '$v bpm' : '—';
          }),
          ('Relevé par', (x) => t(x['saisiPar'] ?? x['soignant'] ?? x['par'])),
        ], ([...temperatures]..sort((a, b) => '${b['date'] ?? ''}${b['heure'] ?? ''}'.compareTo('${a['date'] ?? ''}${a['heure'] ?? ''}'))).toList()));
  if (visites.isNotEmpty) {
    blocs.add(tab('Visites reçues pendant l’hospitalisation', [
      ('Date', (x) => dateFrM1(x['date'])),
      ('Visiteur', (x) => t(x['visiteur'] ?? x['nom'])),
      ('Lien', (x) => t(x['lien'])),
      ('Heure', (x) => t(x['heure'])),
    ], tri(visites, 'date')));
  }
  if (sorties.isNotEmpty) {
    blocs.add(tab('Sorties', [
      ('Date', (x) => dateFrM1(x['dateSortie'] ?? x['date'])),
      ('Diagnostic', (x) => t(x['diagnosticEntree'] ?? x['motif'])),
      ('État à la sortie', (x) => t(x['etatSortie'])),
      ('Solde (RG-06)', (x) => patVrai(x['derogation']) ? 'Dérogation' : 'Apuré'),
    ], tri(sorties, 'dateSortie')));
  }
  if (sortiesAvis.isNotEmpty) {
    blocs.add(tab('Sorties contre avis médical (RG-08)', [
      ('Date', (x) => dateFrM1(x['date'] ?? x['dateSortie'])),
      ('Motif invoqué', (x) => t(x['motif'])),
      ('Décharge', (x) => patVrai(x['decharge']) ? 'Signée' : 'Manquante'),
    ], sortiesAvis));
  }

  // --- Maternité -----------------------------------------------------------------------------------------------------------------------------
  if (maternite.isEmpty && accouchements.isEmpty && naissances.isEmpty && deces.isEmpty) {
    blocs.add(vide('Maternité', 'Aucun suivi de maternité pour ce dossier.'));
  }
  if (maternite.isNotEmpty) {
    blocs.add(tab('Maternité : suivi de grossesse', [
      ('Date prévue', (x) => dateFrM1(patVrai(x['dpa']) ? x['dpa'] : (x['date'] ?? x['_creeLe']))),
      ('Terme', (x) {
        final v = x['termeSA'] ?? x['terme'] ?? x['semaines'];
        return v != null && v != '' ? '$v${x['termeSA'] != null ? ' SA' : ''}' : '—';
      }),
      ('Observations', (x) => t(x['observations'] ?? x['observation'] ?? x['conclusion'])),
      ('Sage-femme', (x) => t(x['sageFemme'] ?? x['soignant'])),
    ], tri(maternite, 'dpa')));
  }
  if (accouchements.isNotEmpty) {
    blocs.add(tab('Accouchements', [
      ('Date', (x) => dateFrM1(x['dateHeure'] ?? x['date'] ?? x['dateAccouchement'])),
      ('Type', (x) => t(x['type'] ?? x['voie'] ?? x['modeAccouchement'])),
      ('Issue', (x) => t(x['issue'])),
      ('Sage-femme', (x) => t(x['sageFemme'])),
    ], tri(accouchements, 'dateHeure')));
  }
  if (naissances.isNotEmpty) {
    blocs.add(tab('Registre des naissances', [
      ('Date', (x) => dateFrM1(x['dateHeure'] ?? x['date'] ?? x['dateNaissance'])),
      ('Enfant', (x) {
        final n = '${x['nom'] ?? ''} ${x['prenom'] ?? ''}'.trim();
        return n.isNotEmpty ? n : t(x['reference']);
      }),
      ('Sexe', (x) => x['sexe'] == 'F' ? 'Féminin' : 'Masculin'),
      ('Poids', (x) => patVrai(x['poids']) ? '${x['poids']} kg' : '—'),
      ('Apgar 5 min', (x) => x['apgar5'] != null ? '${x['apgar5']}' : '—'),
    ], tri(naissances, 'dateHeure')));
  }
  if (deces.isNotEmpty) {
    blocs.add(tab('Registre des décès', [
      ('Date', (x) => dateFrM1(x['date'] ?? x['dateDeces'])),
      ('Cause', (x) => t(x['cause'])),
      ('Constaté par', (x) => t(x['medecin'])),
    ], deces));
  }

  // --- Analyses et résultats : les droits du profil s'appliquent au papier comme à l'écran --------------------------------------------------
  if (analyses.isEmpty) {
    blocs.add(vide('Analyses & résultats', 'Aucune demande d’analyse pour ce patient.'));
  } else {
    final vus = filtrerResultats(analyses, profil.session);
    blocs.add(tab(
        vus.length < analyses.length
            ? 'Analyses & résultats (${analyses.length - vus.length} hors de votre périmètre)'
            : 'Analyses & résultats',
        [
          ('Date', (x) => dateFrM1(x['dateHeure'])),
          ('Analyse', (x) => t(x['analyse'], '')),
          ('Prescripteur', (x) => t(x['prescripteur'], '')),
          ('État', (x) => statut(x['etatAnalyse'])),
          ('Résultat', (x) => x['resultat'] != null ? '${x['resultat']}' : '—'),
          ('Conclusion', (x) => t(x['conclusion'])),
        ],
        tri(vus, 'dateHeure')));
  }

  // --- Imagerie médicale ---------------------------------------------------------------------------------------------------------------------
  if (imageries.isEmpty && crImagerie.isEmpty) {
    blocs.add(vide('Imagerie médicale', 'Aucun examen d’imagerie médicale pour ce patient.'));
  } else {
    final lies = <Object?>{};
    final lignes = <Fiche>[];
    for (final d in imageries) {
      final cr = crImagerie.where((x) => x['demandeImagerieId'] == d['id'] || x['demandeId'] == d['id']).firstOrNull;
      if (cr != null) lies.add(cr['id']);
      lignes.add({'dem': d, 'cr': cr, 'date': d['dateHeure'], 'examen': d['examen']});
    }
    for (final cr in crImagerie) {
      if (lies.contains(cr['id'])) continue;
      lignes.add({'dem': null, 'cr': cr, 'date': cr['date'] ?? cr['_creeLe'], 'examen': cr['examen']});
    }
    const noms = {'echographie': 'Échographie', 'radiographie': 'Radiographie', 'mammographie': 'Mammographie', 'scanner': 'Scanner', 'irm': 'IRM'};
    blocs.add(tab('Imagerie médicale', [
      ('Date', (l) => dateFrM1(l['date'])),
      ('Examen', (l) => t(l['examen'])),
      ('Modalité', (l) => noms['${(l['dem'] as Fiche?)?['modalite'] ?? 'echographie'}'] ?? '${(l['dem'] as Fiche?)?['modalite']}'),
      ('Prescripteur', (l) => t((l['dem'] as Fiche?)?['prescripteur'] ?? (l['cr'] as Fiche?)?['prescripteur'])),
      ('État', (l) => l['dem'] == null ? 'Saisie directe' : statut((l['dem'] as Fiche)['statut'])),
      (
        'Compte rendu',
        (l) {
          final cr = l['cr'] as Fiche?;
          if (cr == null) return 'non rédigé';
          return patPeutLireCR(l['dem'] as Fiche?, cr, profil.session).ok ? 'rendu' : 'restreint';
        }
      ),
    ], tri(lignes, 'date')));
  }

  // --- Ordonnances ---------------------------------------------------------------------------------------------------------------------------
  blocs.add(ordonnances.isEmpty
      ? vide('Ordonnances', 'Aucune ordonnance émise pour ce patient.')
      : tab('Ordonnances', [
          ('N°', (x) => t(x['numero'])),
          ('Date', (x) => dateFrM1(x['date'])),
          ('Prescripteur', (x) => t(x['medecin'], '')),
          ('Diagnostic', (x) => t(x['diagnostic'])),
          (
            'Contenu',
            (x) {
              final r = <String>[];
              int n(String k) => ((x[k] as List?) ?? const []).length;
              if (n('medicaments') > 0) r.add('${n('medicaments')} médic.');
              if (n('analyses') > 0) r.add('${n('analyses')} analyse(s)');
              if (n('actes') > 0) r.add('${n('actes')} acte(s)');
              return r.isEmpty ? '—' : r.join(' · ');
            }
          ),
          ('Montant', (x) => money(x['montant'], avecDevise: false)),
          ('Dispensation', (x) => const {'servie': 'Servie', 'en_attente': 'À délivrer'}['${x['statutDispensation']}'] ?? '—'),
        ], tri(ordonnances, 'date')));

  // --- À domicile ----------------------------------------------------------------------------------------------------------------------------
  blocs.add(domicile.isEmpty
      ? vide('À domicile', 'Aucune consultation ni soin à domicile.')
      : tab('À domicile', [
          ('Date', (x) => dateFrM1(x['date'])),
          ('Motif', (x) => t(x['motif'], '')),
          ('Praticien', (x) => t(x['medecin'], '')),
          ('Diagnostic', (x) => t(x['diagnostic'])),
          ('Tarif', (x) => money(x['tarif'] ?? 0, avecDevise: false)),
        ], tri(domicile, 'date')));

  // --- Financier -----------------------------------------------------------------------------------------------------------------------------
  num somme(String k) => factures.fold<num>(0, (a, f) => a + nombreOuZero(f[k]));
  blocs.add(kv('Financier : totaux', [
    ('Total facturé', money(somme('montantTTC'))),
    ('Reste à payer', money(somme('reliquat'))),
  ]));
  if (factures.isNotEmpty) {
    blocs.add(tab('Financier : factures', [
      ('N° facture', (x) => t(x['numero'])),
      ('Date', (x) => dateFrM1(x['date'])),
      ('Nature', (x) => t(x['type'], '')),
      ('Volet', (x) => x['volet'] == 'couvert' ? 'Couvert par l’assureur' : x['volet'] == 'non_couvert' ? 'Non couvert' : 'Pièce unique'),
      ('Montant', (x) => money(x['montantTTC'], avecDevise: false)),
      ('Part assureur', (x) => patVrai(x['partAssurance']) ? money(x['partAssurance'], avecDevise: false) : '—'),
      ('Part patient', (x) => money(x['partPatient'] ?? x['montantTTC'], avecDevise: false)),
      ('Statut', (x) => statut(x['statutPaiement'])),
    ], tri(factures, 'date')));
  }

  // --- Assurance et traçabilité --------------------------------------------------------------------------------------------------------------
  blocs.add(!patVrai(p['assureur'])
      ? vide('Assurance', 'Ce patient n’est couvert par aucune assurance.')
      : kv('Assurance', [
          ('Compagnie', t(p['assureurNom'], '${p['assureur']}')),
          ('Numéro de police', t(p['numeroPolice'])),
          ('Taux de prise en charge', '${p['tauxPriseEnCharge']} %'),
          ('Expiration de la carte', dateFrM1(p['carteExpiration'])),
          ('Validité (RG-09)', valide ? 'Carte valide' : 'Carte expirée'),
        ]));
  blocs.add(kv('Traçabilité', [
    ('Dossier créé', 'Code ${p['code']} attribué automatiquement (RG-01), le ${dateFrM1(p['dateCreation'])}'),
    if (patVrai(p['_modifieLe'])) ('Dossier modifié', 'Par ${p['_modifiePar']}, le ${dateHeureM1(p['_modifieLe'])}'),
    if (patVrai(p['_archiveLe'])) ('Dossier archivé', '${t(p['_motifArchivage'])}, le ${dateHeureM1(p['_archiveLe'])}'),
  ]));
  return blocs;
}

/// `etatFiche` : le dossier patient imprimé, en entier.
void imprimerDossierComplet(BuildContext ctx, Fiche p) {
  final c = ContexteEcran.of(ctx);
  imprimerM1(ctx,
      titre: 'Fiche patient',
      sousTitre: 'Dossier complet ${p['code']}',
      cartouche: [
        ('Patient', '${p['nom']} ${p['prenom']}'),
        ('Code dossier', '${p['code']}'),
        ('Âge', ageTexte(p, c.aujourdhui)),
        ('Groupe sanguin', patVrai(p['groupeSanguin']) ? '${p['groupeSanguin']}' : '—'),
      ],
      blocs: blocsDossierComplet(c, p),
      signatures: const [Signature('Le Secrétaire Médical'), Signature('Le Directeur Médical', nom: 'BASSONGUI Chabi Séko')]);
}
