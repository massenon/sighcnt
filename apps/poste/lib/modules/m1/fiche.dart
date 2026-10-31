import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m5/res_commun.dart' show profilLabo;
import 'commun_m1.dart';

List<Fiche> _tri(List<Fiche> l, String cle) =>
    trierPar(l, (f) => f[cle], descendant: true);

String _t(Object? v, [String vide = '—']) => patVrai(v) ? '$v' : vide;

/// `statutAssurance(p)` : trois états dits explicitement — non assuré · carte valide · CARTE NON VALIDE (RG-09 : c'est le seul qui change la facturation).
Widget statutAssuranceM1(FichePat p, bool valide) {
  if (!patVrai(p['assureur'])) {
    return const Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
      BadgeSigh('Non assuré'),
      Text('Facturation intégrale au patient', style: TextStyle(color: JetonsShell.slate500, fontSize: 12, height: 16 / 12)),
    ]);
  }
  return Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
    BadgeSigh(_t(p['assureurNom'], '${p['assureur']}'), ton: TonSigh.navy),
    if (valide)
      const BadgeSigh('Carte valide', ton: TonSigh.succes)
    else
      Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
              color: JetonsShell.danger50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: JetonsShell.danger300)),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(LucideIcons.shieldAlert, size: 14, color: JetonsShell.danger700),
            SizedBox(width: 4),
            Text('CARTE NON VALIDE',
                style: TextStyle(color: JetonsShell.danger700, fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w600)),
          ])),
    Text(
        valide
            ? 'Expire le ${dateFrM1(p['carteExpiration'])}${patVrai(p['souscripteur']) ? ' · ${p['souscripteur']}' : ''}'
            : 'Expirée le ${dateFrM1(p['carteExpiration'])} — facturation intégrale (RG-09)',
        style: TextStyle(color: valide ? JetonsShell.slate500 : JetonsShell.danger700, fontSize: 12, height: 16 / 12)),
  ]);
}

String initiales(String s) => s
    .trim()
    .split(RegExp(r'\s+'))
    .take(2)
    .map((w) => w.isEmpty ? '' : w[0])
    .join()
    .toUpperCase();

/// La fiche patient : DEUX panneaux et un menu collant. L'ordre du DOM est celui du téléphone (le menu d'abord) ; sur grand écran le menu passe à droite.
class FichePatient extends StatefulWidget {
  const FichePatient(this.patient, {super.key});
  final Fiche patient;

  @override
  State<FichePatient> createState() => _FichePatientState();
}

class _FichePatientState extends State<FichePatient> {
  String _courante = 'admin';

  Fiche get p => widget.patient;

  List<Fiche> _sien(ContexteEcran c, String nom) => [
        for (final x in c.magasin.collection(nom).actives)
          if (x['patientId'] == p['id']) x
      ];

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final m = c.magasin;
    final maintenant = c.aujourdhui;
    final couvertures = m.collection('couverturesAssurance').actives;
    final valide = patCarteValide(p, couvertures, maintenant);
    final age = patAge(p, maintenant);
    final consultations = _sien(c, 'consultations').where((x) => x['type'] != 'Domicile').toList();
    final domicile = _sien(c, 'consultations').where((x) => x['type'] == 'Domicile').toList();
    final admissions = _sien(c, 'admissions');
    final observations = _sien(c, 'observations');
    final idsAdm = admissions.map((a) => a['id']).toSet();
    final temperatures = [
      for (final r in m.collection('releves').actives)
        if (idsAdm.contains(r['admissionId'])) r
    ];
    final visites = _sien(c, 'visitesPatients');
    final sorties = [
      for (final a in admissions)
        if (a['statut'] == 'sortie' || patVrai(a['dateSortie'])) a
    ];
    final sortiesAvis = _sien(c, 'sortiesAvisMedical');
    final maternite = _sien(c, 'suiviMaternite');
    final accouchements = _sien(c, 'accouchements');
    final naissances = [
      for (final n in m.collection('naissances').actives)
        if (n['mereId'] == p['id'] || n['patientId'] == p['id']) n
    ];
    final deces = _sien(c, 'deces');
    final analyses = _sien(c, 'demandesAnalyses');
    final imageries = _sien(c, 'demandesImagerie');
    final crImagerie = _sien(c, 'resultatsImagerie');
    final ordonnances = _sien(c, 'ordonnances');
    final factures = _sien(c, 'factures');
    final soins = _sien(c, 'soins');
    final profil = profilLabo(c);

    Widget mini(List<ColonneMini> cols, List<Fiche> l, [String vide = 'Aucune donnée.']) =>
        MiniTableauSigh(colonnes: cols, lignes: l, vide: vide);
    Widget vide(String t, IconData i) => VideSigh(t, icone: i);

    final rubriques = <({String id, String label, int? badge, Widget Function() rendu})>[
      (
        id: 'admin',
        label: 'Administratif',
        badge: null,
        rendu: () => DescListeSigh([
              ('Code dossier', enMono('${p['code']}')),
              ('Nom et prénoms', '${p['nom']} ${p['prenom']}'),
              ('Sexe', p['sexe'] == 'F' ? 'Féminin' : 'Masculin'),
              (
                'Date de naissance',
                patVrai(p['dateNaissance'])
                    ? '${dateFrM1(p['dateNaissance'])}${age != null ? ' ($age ans)' : ''}'
                    : 'Inconnue — ${ageTexte(p, maintenant)}'
              ),
              ('Téléphone', p['telephone']),
              ('Quartier', p['quartier']),
              ('Adresse', p['adresse']),
              ('Personne à prévenir', p['personneAPrevenir']),
              ('Groupe sanguin', p['groupeSanguin']),
              ('Dossier créé le', dateFrM1(p['dateCreation'])),
            ])
      ),
      (
        id: 'medical',
        label: 'Médical',
        badge: consultations.length,
        rendu: () => consultations.isEmpty
            ? vide('Aucune consultation enregistrée.', LucideIcons.stethoscope)
            : mini([
                ColonneMini('Date', (x) => dateFrM1(x['date'])),
                ColonneMini('Motif', (x) => _t(x['motif'], '')),
                ColonneMini('Diagnostic', (x) => _t(x['diagnostic'], '')),
                ColonneMini('Médecin', (x) => _t(x['medecin'], '')),
              ], _tri(consultations, 'date').take(15).toList())
      ),
      (
        id: 'antecedents',
        label: 'Antécédents & allergies',
        badge: null,
        rendu: () => DescListeSigh([
              (
                'Antécédents',
                patListe(p['antecedents']).isNotEmpty
                    ? Wrap(spacing: 4, runSpacing: 4, children: [for (final a in patListe(p['antecedents'])) BadgeSigh(a, ton: TonSigh.attention)])
                    : const BadgeSigh('Aucun antécédent notable', ton: TonSigh.succes)
              ),
              ('Autres antécédents', _t(p['antecedentsAutres'])),
              (
                'Allergies connues',
                patListe(p['allergies']).isNotEmpty
                    ? Wrap(spacing: 4, runSpacing: 4, children: [for (final a in patListe(p['allergies'])) BadgeSigh(a, ton: TonSigh.danger)])
                    : const BadgeSigh('Aucune allergie connue', ton: TonSigh.succes)
              ),
              ('Traitement en cours', _t(p['traitementEnCours'])),
              ('Groupe sanguin', _t(p['groupeSanguin'])),
            ])
      ),
      (
        id: 'soins',
        label: 'Soins',
        badge: soins.length,
        rendu: () => soins.isEmpty
            ? vide('Aucun acte de soins enregistré pour ce patient.', LucideIcons.heartPulse)
            : mini([
                ColonneMini('Date', (x) => '${dateFrM1(x['date'])} à ${x['heure']}'),
                ColonneMini('Acte', (x) => _t(x['acte'], '')),
                ColonneMini('Produit utilisé', (x) => _t(x['produit'])),
                ColonneMini('Soignant', (x) => _t(x['soignant'], '')),
                ColonneMini('État', (x) => '', rendu: (x) => statutBadge(x['etat'] == 'realise' ? 'validee' : 'planifiee')),
              ], _tri(soins, 'date').take(20).toList())
      ),
      (
        id: 'hospi',
        label: 'Hospitalisations',
        badge: admissions.length + observations.length,
        rendu: () {
          final enCours = admissions.where((a) => a['statut'] == 'en_cours').toList();
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (enCours.isNotEmpty) ...[
              NoteSigh(
                  'Patient actuellement hospitalisé — ${enCours.map((a) => 'chambre ${_t(a['chambre'], '?')}, lit ${_t(a['lit'], '?')}').join(' · ')}. Une feuille de température est ouverte tant que le séjour dure.',
                  icone: LucideIcons.bedDouble),
              const SizedBox(height: 12),
            ],
            CarteSigh(
                titre: 'Admissions et lits occupés',
                sansRemplissage: true,
                child: admissions.isEmpty
                    ? vide('Aucune hospitalisation.', LucideIcons.bedDouble)
                    : mini([
                        ColonneMini('Entrée', (x) => dateFrM1(x['dateEntree'])),
                        ColonneMini('Sortie', (x) => patVrai(x['dateSortie']) ? dateFrM1(x['dateSortie']) : 'en cours'),
                        ColonneMini('Chambre', (x) => _t(x['chambre'])),
                        ColonneMini('Lit', (x) => _t(x['lit'])),
                        ColonneMini('Diagnostic', (x) => _t(x['diagnosticEntree'], '')),
                        ColonneMini('Statut', (x) => '', rendu: (x) => statutBadge(x['statut'])),
                      ], _tri(admissions, 'dateEntree'))),
            if (observations.isNotEmpty) ...[
              const SizedBox(height: 12),
              CarteSigh(
                  titre: 'Mises en observation',
                  sansRemplissage: true,
                  child: mini([
                    ColonneMini('Entrée', (x) => '${dateFrM1(x['dateEntree'])} ${heure(dateM1(x['dateEntree']) ?? maintenant)}'),
                    ColonneMini('Motif', (x) => _t(x['motif'], '')),
                    ColonneMini('Unité', (x) => '${x['uniteLabel'] ?? ''}'.replaceAll('Salle d’observation — ', '')),
                    ColonneMini('Constantes', (x) => '${((x['constantes'] as List?) ?? const []).length}', droite: true),
                    ColonneMini('Issue', (x) => _t(x['orientationLabel'], 'en cours')),
                  ], _tri(observations, 'dateEntree'))),
            ],
            const SizedBox(height: 12),
            CarteSigh(
                titre: 'Feuilles de température',
                sansRemplissage: true,
                child: temperatures.isEmpty
                    ? vide('Aucune feuille de température — le patient n’a pas séjourné.', LucideIcons.thermometer)
                    : mini([
                        ColonneMini('Date', (x) => '${dateFrM1(x['date'])}${patVrai(x['heure']) ? ' ${x['heure']}' : ''}'),
                        ColonneMini('Température', (x) => '${patVrai(x['temperature']) ? x['temperature'] : _t(x['matin'])} °C', droite: true),
                        ColonneMini('Tension', (x) => _t(x['tension'])),
                        ColonneMini('Pouls', (x) {
                          final v = x['fc'] ?? x['pouls'];
                          return patVrai(v) ? '$v bpm' : '—';
                        }, droite: true),
                        ColonneMini('Relevé par', (x) => _t(x['saisiPar'] ?? x['soignant'] ?? x['par'])),
                      ], ([...temperatures]..sort((a, b) => '${b['date'] ?? ''}${b['heure'] ?? ''}'.compareTo('${a['date'] ?? ''}${a['heure'] ?? ''}'))).take(20).toList())),
            if (visites.isNotEmpty) ...[
              const SizedBox(height: 12),
              CarteSigh(
                  titre: 'Visites reçues pendant l’hospitalisation',
                  sansRemplissage: true,
                  child: mini([
                    ColonneMini('Date', (x) => dateFrM1(x['date'])),
                    ColonneMini('Visiteur', (x) => _t(x['visiteur'] ?? x['nom'])),
                    ColonneMini('Lien', (x) => _t(x['lien'])),
                    ColonneMini('Heure', (x) => _t(x['heure'])),
                  ], _tri(visites, 'date').take(15).toList())),
            ],
            if (sorties.isNotEmpty || sortiesAvis.isNotEmpty) ...[
              const SizedBox(height: 12),
              CarteSigh(
                  titre: 'Sorties',
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    if (sorties.isNotEmpty)
                      mini([
                        ColonneMini('Date', (x) => dateFrM1(x['dateSortie'] ?? x['date'])),
                        ColonneMini('Diagnostic', (x) => _t(x['diagnosticEntree'] ?? x['motif'])),
                        ColonneMini('État à la sortie', (x) => _t(x['etatSortie'])),
                        ColonneMini('Solde (RG-06)', (x) => '',
                            rendu: (x) => patVrai(x['derogation'])
                                ? const BadgeSigh('Dérogation', ton: TonSigh.attention)
                                : const BadgeSigh('Apuré', ton: TonSigh.succes)),
                      ], _tri(sorties, 'dateSortie')),
                    if (sortiesAvis.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const NoteSigh('Sortie contre avis médical — décharge signée, motif consigné (RG-08).',
                          ton: TonSigh.danger, icone: LucideIcons.triangleAlert),
                      mini([
                        ColonneMini('Date', (x) => dateFrM1(x['date'] ?? x['dateSortie'])),
                        ColonneMini('Motif invoqué', (x) => _t(x['motif'])),
                        ColonneMini('Décharge', (x) => '',
                            rendu: (x) => patVrai(x['decharge'])
                                ? const BadgeSigh('Signée', ton: TonSigh.attention)
                                : const BadgeSigh('Manquante', ton: TonSigh.danger)),
                      ], sortiesAvis),
                    ],
                  ])),
            ],
          ]);
        }
      ),
      (
        id: 'maternite',
        label: 'Maternité',
        badge: maternite.length + accouchements.length,
        rendu: () {
          if (maternite.isEmpty && accouchements.isEmpty && naissances.isEmpty && deces.isEmpty) {
            return vide('Aucun suivi de maternité pour ce dossier.', LucideIcons.baby);
          }
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (maternite.isNotEmpty)
              CarteSigh(
                  titre: 'Suivi de grossesse',
                  sansRemplissage: true,
                  child: mini([
                    ColonneMini('Date prévue', (x) => dateFrM1(patVrai(x['dpa']) ? x['dpa'] : (x['date'] ?? x['_creeLe']))),
                    ColonneMini('Terme', (x) {
                      final t = x['termeSA'] ?? x['terme'] ?? x['semaines'];
                      return t != null && t != '' ? '$t${x['termeSA'] != null ? ' SA' : ''}' : '—';
                    }),
                    ColonneMini('Observations', (x) => _t(x['observations'] ?? x['observation'] ?? x['conclusion'])),
                    ColonneMini('Sage-femme', (x) => _t(x['sageFemme'] ?? x['soignant'])),
                  ], _tri(maternite, 'dpa'))),
            if (accouchements.isNotEmpty) ...[
              const SizedBox(height: 12),
              CarteSigh(
                  titre: 'Accouchements',
                  sansRemplissage: true,
                  child: mini([
                    ColonneMini('Date', (x) => dateFrM1(x['dateHeure'] ?? x['date'] ?? x['dateAccouchement'])),
                    ColonneMini('Type', (x) => _t(x['type'] ?? x['voie'] ?? x['modeAccouchement'])),
                    ColonneMini('Issue', (x) => _t(x['issue'])),
                    ColonneMini('Sage-femme', (x) => _t(x['sageFemme'])),
                  ], _tri(accouchements, 'dateHeure'))),
            ],
            if (naissances.isNotEmpty) ...[
              const SizedBox(height: 12),
              CarteSigh(
                  titre: 'Registre des naissances',
                  sansRemplissage: true,
                  child: mini([
                    ColonneMini('Date', (x) => dateFrM1(x['dateHeure'] ?? x['date'] ?? x['dateNaissance'])),
                    ColonneMini('Enfant', (x) {
                      final n = '${x['nom'] ?? ''} ${x['prenom'] ?? ''}'.trim();
                      return n.isNotEmpty ? n : _t(x['reference']);
                    }),
                    ColonneMini('Sexe', (x) => x['sexe'] == 'F' ? 'Féminin' : 'Masculin'),
                    ColonneMini('Poids', (x) => patVrai(x['poids']) ? '${x['poids']} kg' : '—'),
                    ColonneMini('Apgar 5 min', (x) => x['apgar5'] != null ? '${x['apgar5']}' : '—'),
                  ], _tri(naissances, 'dateHeure'))),
            ],
            if (deces.isNotEmpty) ...[
              const SizedBox(height: 12),
              CarteSigh(
                  titre: 'Registre des décès',
                  sansRemplissage: true,
                  child: mini([
                    ColonneMini('Date', (x) => dateFrM1(x['date'] ?? x['dateDeces'])),
                    ColonneMini('Cause', (x) => _t(x['cause'])),
                    ColonneMini('Constaté par', (x) => _t(x['medecin'])),
                  ], deces)),
            ],
          ]);
        }
      ),
      (
        id: 'laboratoire',
        label: 'Analyses & résultats',
        badge: analyses.length,
        rendu: () {
          if (analyses.isEmpty) return vide('Aucune demande d’analyse pour ce patient.', LucideIcons.flaskConical);
          final vus = filtrerResultats(analyses, profil.session);
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (vus.length < analyses.length) ...[
              NoteSigh(
                  '${analyses.length - vus.length} résultat(s) hors de votre périmètre. ${profil.cap.label} — ${profil.cap.note ?? ''}',
                  ton: TonSigh.attention,
                  icone: LucideIcons.shieldAlert),
              const SizedBox(height: 12),
            ],
            mini([
              ColonneMini('Date', (x) => dateFrM1(x['dateHeure'])),
              ColonneMini('Analyse', (x) => _t(x['analyse'], '')),
              ColonneMini('Prescripteur', (x) => _t(x['prescripteur'], '')),
              ColonneMini('État', (x) => '', rendu: (x) => statutBadge(x['etatAnalyse'])),
              ColonneMini('Résultat', (x) => x['resultat'] != null ? '${x['resultat']}' : '—'),
              ColonneMini('Conclusion', (x) => '',
                  rendu: (x) => !patVrai(x['conclusion'])
                      ? const Text('—')
                      : x['conclusion'] == 'Normal'
                          ? const BadgeSigh('Normal', ton: TonSigh.succes)
                          : BadgeSigh('${x['conclusion']}', ton: TonSigh.attention)),
            ], _tri(vus, 'dateHeure').take(25).toList()),
          ]);
        }
      ),
      (
        id: 'imagerie',
        label: 'Imagerie médicale',
        badge: imageries.isNotEmpty ? imageries.length : crImagerie.length,
        rendu: () => _ongletImagerie(context, c, imageries, crImagerie, profil.session)
      ),
      (
        id: 'ordonnances',
        label: 'Ordonnances',
        badge: ordonnances.length,
        rendu: () => ordonnances.isEmpty
            ? vide('Aucune ordonnance émise pour ce patient.', LucideIcons.scrollText)
            : mini([
                ColonneMini('N°', (x) => '', rendu: (x) => enMono('${x['numero']}')),
                ColonneMini('Date', (x) => dateFrM1(x['date'])),
                ColonneMini('Prescripteur', (x) => _t(x['medecin'], '')),
                ColonneMini('Diagnostic', (x) => _t(x['diagnostic'])),
                ColonneMini('Contenu', (x) {
                  final t = <String>[];
                  int n(String k) => ((x[k] as List?) ?? const []).length;
                  if (n('medicaments') > 0) t.add('${n('medicaments')} médic.');
                  if (n('analyses') > 0) t.add('${n('analyses')} analyse(s)');
                  if (n('actes') > 0) t.add('${n('actes')} acte(s)');
                  return t.isEmpty ? '—' : t.join(' · ');
                }),
                ColonneMini('Montant', (x) => money(x['montant'], avecDevise: false), droite: true),
                ColonneMini('Dispensation', (x) {
                  return '';
                }, rendu: (x) {
                  const mm = {
                    'servie': ('Servie', TonSigh.succes),
                    'en_attente': ('À délivrer', TonSigh.attention),
                  };
                  final r = mm['${x['statutDispensation']}'] ?? ('—', TonSigh.neutre);
                  return BadgeSigh(r.$1, ton: r.$2);
                }),
              ], _tri(ordonnances, 'date').take(20).toList())
      ),
      (
        id: 'domicile',
        label: 'À domicile',
        badge: domicile.length,
        rendu: () => domicile.isEmpty
            ? vide('Aucune consultation ni soin à domicile.', LucideIcons.house)
            : mini([
                ColonneMini('Date', (x) => dateFrM1(x['date'])),
                ColonneMini('Motif', (x) => _t(x['motif'], '')),
                ColonneMini('Praticien', (x) => _t(x['medecin'], '')),
                ColonneMini('Diagnostic', (x) => _t(x['diagnostic'])),
                ColonneMini('Tarif', (x) => money(x['tarif'] ?? 0, avecDevise: false), droite: true),
              ], _tri(domicile, 'date'))
      ),
      (
        id: 'financier',
        label: 'Financier',
        badge: factures.length,
        rendu: () {
          num somme(String k) => factures.fold<num>(0, (a, f) => a + nombreOuZero(f[k]));
          final du = somme('reliquat');
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            KpiGrilleSigh(colonnes: 2, kpis: [
              KpiSigh(libelle: 'Total facturé', valeur: money(somme('montantTTC')), icone: LucideIcons.receipt),
              KpiSigh(
                  libelle: 'Reste à payer',
                  valeur: money(du),
                  icone: LucideIcons.wallet,
                  ton: du > 0 ? TonSigh.danger : TonSigh.succes),
            ]),
            if (patVrai(p['assureur'])) ...[
              const SizedBox(height: 12),
              const NoteSigh(
                  'Patient assuré : les prestations couvertes et non couvertes font deux factures distinctes — pièce -A pour ce que l’assureur prend en charge, pièce -B pour ce qui reste au patient.',
                  icone: LucideIcons.files),
            ],
            const SizedBox(height: 12),
            factures.isEmpty
                ? vide('Aucune facture.', LucideIcons.receipt)
                : mini([
                    ColonneMini('N° facture', (x) => '', rendu: (x) => enMono('${x['numero']}')),
                    ColonneMini('Date', (x) => dateFrM1(x['date'])),
                    ColonneMini('Nature', (x) => _t(x['type'], '')),
                    ColonneMini('Volet', (x) => '', rendu: (x) {
                      if (x['volet'] == 'couvert') return const BadgeSigh('Couvert par l’assureur', ton: TonSigh.succes);
                      if (x['volet'] == 'non_couvert') return const BadgeSigh('Non couvert', ton: TonSigh.attention);
                      return const Text('Pièce unique', style: TextStyle(color: JetonsShell.slate400, fontSize: 12, height: 16 / 12));
                    }),
                    ColonneMini('Montant', (x) => money(x['montantTTC'], avecDevise: false), droite: true),
                    ColonneMini('Part assureur', (x) => patVrai(x['partAssurance']) ? money(x['partAssurance'], avecDevise: false) : '—', droite: true),
                    ColonneMini('Part patient', (x) => money(x['partPatient'] ?? x['montantTTC'], avecDevise: false), droite: true),
                    ColonneMini('Statut', (x) => '', rendu: (x) => statutBadge(x['statutPaiement'])),
                  ], _tri(factures, 'date').take(20).toList()),
          ]);
        }
      ),
      (
        id: 'assurance',
        label: 'Assurance',
        badge: null,
        rendu: () => !patVrai(p['assureur'])
            ? vide('Ce patient n’est couvert par aucune assurance.', LucideIcons.shieldOff)
            : DescListeSigh([
                ('Compagnie', _t(p['assureurNom'], '${p['assureur']}')),
                ('Numéro de police', p['numeroPolice']),
                ('Taux de prise en charge', '${p['tauxPriseEnCharge']} %'),
                ('Expiration de la carte', dateFrM1(p['carteExpiration'])),
                ('Validité (RG-09)',
                    valide ? const BadgeSigh('Carte valide', ton: TonSigh.succes) : const BadgeSigh('Carte expirée', ton: TonSigh.danger)),
              ])
      ),
      (
        id: 'audit',
        label: 'Traçabilité',
        badge: null,
        rendu: () => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _jalon('Dossier créé', 'Code ${p['code']} attribué automatiquement (RG-01)', dateFrM1(p['dateCreation']), JetonsShell.success600),
              if (patVrai(p['_modifieLe']))
                _jalon('Dossier modifié', 'Par ${p['_modifiePar']}', dateHeureM1(p['_modifieLe']), JetonsShell.info600),
              if (patVrai(p['_archiveLe']))
                _jalon('Dossier archivé', _t(p['_motifArchivage']), dateHeureM1(p['_archiveLe']), JetonsShell.warning600),
            ])
      ),
    ];

    final actuelle = rubriques.firstWhere((r) => r.id == _courante, orElse: () => rubriques.first);

    final identite = CarteSigh(
        titre: 'Identité et couverture',
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: JetonsShell.navy50, borderRadius: BorderRadius.circular(8)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: JetonsShell.navy900, shape: BoxShape.circle),
                child: Text(initiales('${p['nom']} ${p['prenom']}'),
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600))),
            const SizedBox(width: 12),
            Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${p['nom']} ${p['prenom']}', style: styleM1(p: FontWeight.w600, c: JetonsShell.slate900)),
              Text('${p['code']}', style: monoM1.copyWith(color: JetonsShell.navy700)),
              Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                      '${p['sexe'] == 'F' ? 'Femme' : 'Homme'} — ${age != null ? '$age ans' : 'âge inconnu'} — Groupe ${_t(p['groupeSanguin'], '?')}',
                      style: styleM1(t: 12, c: JetonsShell.slate500))),
              Padding(padding: const EdgeInsets.only(top: 8), child: statutAssuranceM1(p, valide)),
            ])),
          ]),
        ));

    final histCouv = [
      for (final x in couvertures)
        if (x['patientId'] == p['id']) x
    ];
    final gauche = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      identite,
      if (histCouv.length > 1) ...[
        const SizedBox(height: 16),
        NoteSigh(
            'Ce patient a changé de couverture ${histCouv.length - 1} fois. Les factures antérieures restent rattachées à la compagnie qui couvrait à leur date — l’onglet Assurance en porte le détail.',
            icone: LucideIcons.history),
      ],
      if (patVrai(p['assureur']) && !valide) ...[
        const SizedBox(height: 16),
        NoteSigh(
            'Carte d’assurance expirée le ${dateFrM1(p['carteExpiration'])}. En application de la règle RG-09, la facturation est intégrale au patient tant que la carte n’est pas renouvelée.',
            ton: TonSigh.danger,
            icone: LucideIcons.shieldAlert),
      ],
      if (patListe(p['allergies']).isNotEmpty) ...[
        const SizedBox(height: 16),
        NoteSigh(
            'Allergie(s) déclarée(s) : ${patTexteListe(p['allergies'])}. Vérifier toute prescription et toute dispensation avant délivrance.',
            ton: TonSigh.attention,
            icone: LucideIcons.triangleAlert),
      ],
      const SizedBox(height: 16),
      _carteDossier(context, c),
      const SizedBox(height: 16),
      CarteSigh(titre: actuelle.label, child: actuelle.rendu()),
    ]);

    final menu = CarteSigh(
        titre: 'Rubriques du dossier',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final r in rubriques)
            Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Semantics(
                    button: true,
                    selected: r.id == _courante,
                    child: InkWell(
                        key: Key('m1:rubrique:${r.id}'),
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => setState(() => _courante = r.id),
                        child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                                color: r.id == _courante ? JetonsShell.navy900 : null,
                                borderRadius: BorderRadius.circular(8)),
                            child: Row(children: [
                              Expanded(
                                  child: Text(r.label,
                                      style: TextStyle(
                                          color: r.id == _courante ? Colors.white : JetonsShell.slate600,
                                          fontSize: 14,
                                          height: 20 / 14,
                                          fontWeight: r.id == _courante ? FontWeight.w600 : FontWeight.w400))),
                              if (r.badge != null)
                                Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8),
                                    decoration: BoxDecoration(
                                        color: r.id == _courante ? Colors.white24 : JetonsShell.slate100,
                                        borderRadius: BorderRadius.circular(99)),
                                    child: Text('${r.badge}',
                                        style: TextStyle(
                                            color: r.id == _courante ? Colors.white : JetonsShell.slate500,
                                            fontSize: 12,
                                            height: 16 / 12))),
                            ]))))),
        ]));

    return LayoutBuilder(builder: (_, w) {
      if (w.maxWidth >= 1024) {
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 2, child: gauche),
          const SizedBox(width: 16),
          Expanded(child: menu),
        ]);
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [menu, const SizedBox(height: 16), gauche]);
    });
  }

  Widget _jalon(String titre, String detail, String date, Color couleur) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Container(width: 10, height: 10, decoration: BoxDecoration(color: couleur, shape: BoxShape.circle))),
        const SizedBox(width: 10),
        Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(titre, style: styleM1(p: FontWeight.w500, c: JetonsShell.slate800)),
          Text(detail, style: styleM1(t: 12, c: JetonsShell.slate500)),
          Text(date, style: const TextStyle(color: JetonsShell.slate400, fontSize: 11, height: 15 / 11)),
        ])),
      ]));

  Widget _titreSec(String t) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(t.toUpperCase(),
          style: const TextStyle(
              color: JetonsShell.slate400, fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w600, letterSpacing: 0.6)));

  /// Le dossier de consultation, TOUJOURS visible : le DERNIER dossier ouvert, avec la date de la venue et celle de l'enregistrement.
  Widget _carteDossier(BuildContext context, ContexteEcran c) {
    final dossiers = [
      for (final d in c.magasin.collection('dossiersConsultation').actives)
        if (d['patientId'] == p['id'] || d['patientCode'] == p['code']) d
    ];
    if (dossiers.isEmpty) {
      return const CarteSigh(
          titre: 'Dossier de consultation',
          child: VideSigh(
              'Aucun dossier de consultation ouvert pour ce patient. Le dossier se saisit au poste du praticien, avant la fiche de consultation.',
              icone: LucideIcons.folderHeart));
    }
    final tri = _tri(dossiers, 'dateArrivee');
    final d = tri.first;
    final venue = patVrai(d['dateArrivee'])
        ? '${dateFrM1(d['dateArrivee'])}${patVrai(d['heureArrivee']) ? ' à ${d['heureArrivee']}' : ''}'
        : '—';
    final saisie = patVrai(d['ouvertLe']) ? dateHeureM1(d['ouvertLe']) : '—';
    final cats = [
      for (final k in patCategoriesAntecedent) (k.$2, _t(d['ant_${k.$1}']))
    ];
    final ca = d['constantesAccueil'];
    final ex = patSyntheseExamen(patExamensPhysiquesDe(d));
    return CarteSigh(
        titre: 'Dossier de consultation — ${_t(d['reference'], '')}',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          NoteSigh(
              'Dernier dossier : ${_t(d['reference'])} — venue du $venue, enregistré le $saisie${patVrai(d['soignant']) ? ', par ${d['soignant']}' : ''}.${tri.length > 1 ? ' ${tri.length - 1} dossier(s) antérieur(s) au registre.' : ''}',
              icone: LucideIcons.folderHeart),
          const SizedBox(height: 16),
          DescListeSigh([
            ('Motif de consultation', _t(d['motifVenue'])),
            ('Type de venue', _t(d['typeVenue'])),
            ('Histoire de la maladie', _t(d['histoire'])),
            ('Traitements en cours', _t(d['traitementEnCours'])),
          ]),
          const SizedBox(height: 16),
          _titreSec('Antécédents'),
          DescListeSigh(cats),
          const SizedBox(height: 16),
          _titreSec('Données préalables'),
          DescListeSigh([
            ('Allergies', _t(d['allergies'] ?? p['allergies'])),
            ('Allergies médicamenteuses', _t(d['allergiesMedicamenteuses'])),
            ('Statut vaccinal', _t(d['statutVaccinal'])),
            ('Groupe sanguin', _t(d['groupeSanguin'] ?? p['groupeSanguin'])),
            ('Électrophorèse Hb', _t(d['electrophoreseHb'])),
            ('Dépistage', _t(d['depistage'])),
          ]),
          if (ca is Map) ...[
            const SizedBox(height: 16),
            _titreSec('Constantes reprises de l’accueil'),
            DescListeSigh([
              ('Relevées le', patVrai(ca['date']) ? dateHeureM1(ca['date']) : '—'),
              ('Température', ca['temperature'] != null ? '${ca['temperature']} °C' : '—'),
              ('Tension', _t(ca['tension'])),
              ('Poids', ca['poids'] != null ? '${ca['poids']} kg' : '—'),
              ('Pouls', ca['pouls'] != null ? '${ca['pouls']} /min' : '—'),
            ]),
          ],
          const SizedBox(height: 16),
          if (ex.isNotEmpty) ...[
            _titreSec('Examen physique par appareil (IPPOA)'),
            MiniTableauSigh(colonnes: [
              ColonneMini('Appareil', (x) => '${x['label']}'),
              ColonneMini('Examiné le', (x) => venue),
              ColonneMini('Porté au dossier le', (x) => saisie),
              ColonneMini('Constat', (x) => '',
                  rendu: (x) => x['normal'] == true
                      ? const BadgeSigh('RAS — normal', ton: TonSigh.succes)
                      : Text('${x['texte']}', style: styleM1())),
            ], lignes: [
              for (final l in ex) {'label': l.label, 'normal': l.normal, 'texte': l.texte}
            ]),
          ] else
            const NoteSigh('Aucun appareil renseigné à l’examen physique de ce dossier.',
                ton: TonSigh.neutre, icone: LucideIcons.stethoscope),
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8, children: [
            BoutonSigh(
                libelle: 'Ouvrir le dossier de consultation',
                icone: LucideIcons.folderHeart,
                taille: TailleBouton.sm,
                onPressed: () => c.aller('m2-dossiers-consultation')),
            BoutonSigh(
                libelle: 'Fiche de consultation',
                icone: LucideIcons.clipboardList,
                taille: TailleBouton.sm,
                onPressed: () => c.aller('m2-consultation-fiche')),
          ]),
        ]));
  }

  /// L'onglet « Imagerie médicale » : une VUE des demandes et des comptes rendus, jamais une saisie. Le contenu d'un compte rendu obéit aux droits.
  Widget _ongletImagerie(BuildContext context, ContexteEcran c, List<Fiche> demandes, List<Fiche> crs, SessionLabo session) {
    if (demandes.isEmpty && crs.isEmpty) {
      return const VideSigh('Aucun examen d’imagerie médicale pour ce patient.', icone: LucideIcons.scanLine);
    }
    final lignes = <Fiche>[];
    final lies = <Object?>{};
    for (final d in demandes) {
      final cr = crs.where((x) => x['demandeImagerieId'] == d['id'] || x['demandeId'] == d['id']).firstOrNull;
      if (cr != null) lies.add(cr['id']);
      lignes.add({'dem': d, 'cr': cr, 'date': d['dateHeure'], 'examen': d['examen'], 'code': d['examenCode']});
    }
    for (final cr in crs) {
      if (lies.contains(cr['id'])) continue;
      lignes.add({'dem': null, 'cr': cr, 'date': cr['date'] ?? cr['_creeLe'], 'examen': cr['examen'], 'code': cr['examenCode']});
    }
    final masques = lignes.where((l) => l['cr'] != null && !patPeutLireCR(l['dem'] as Fiche?, l['cr'] as Fiche?, session).ok).length;
    String modalite(Fiche l) {
      const noms = {
        'echographie': 'Échographie',
        'radiographie': 'Radiographie',
        'mammographie': 'Mammographie',
        'scanner': 'Scanner',
        'irm': 'IRM'
      };
      final dem = l['dem'] as Fiche?;
      final m = dem?['modalite'] ?? 'echographie';
      return noms['$m'] ?? '$m';
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (masques > 0) ...[
        NoteSigh(
            '$masques compte(s) rendu(s) hors de votre périmètre. L’examen reste listé — son existence n’est pas un secret médical — mais son contenu obéit aux droits de votre profil.',
            ton: TonSigh.attention,
            icone: LucideIcons.shieldAlert),
        const SizedBox(height: 12),
      ],
      MiniTableauSigh(colonnes: [
        ColonneMini('Date', (l) => dateFrM1(l['date'])),
        ColonneMini('Examen', (l) => _t(l['examen'])),
        ColonneMini('Modalité', modalite),
        ColonneMini('Prescripteur', (l) => _t((l['dem'] as Fiche?)?['prescripteur'] ?? (l['cr'] as Fiche?)?['prescripteur'])),
        ColonneMini('État', (l) => '', rendu: (l) {
          final dem = l['dem'] as Fiche?;
          final cr = l['cr'] as Fiche;
          if (dem == null) {
            final rendu = cr['statut'] == 'rendu';
            return BadgeSigh(rendu ? 'CR rendu (saisie directe)' : 'CR en rédaction (saisie directe)',
                ton: rendu ? TonSigh.succes : TonSigh.navy);
          }
          final e = patEtatsImagerie['${dem['statut']}'] ?? ('${dem['statut']}', 'neutral');
          return BadgeSigh(e.$1, ton: tonDe(e.$2));
        }),
        ColonneMini('Compte rendu', (l) => '', rendu: (l) {
          final cr = l['cr'] as Fiche?;
          if (cr == null) return const Text('non rédigé', style: TextStyle(color: JetonsShell.slate400, fontSize: 12, height: 16 / 12));
          final droit = patPeutLireCR(l['dem'] as Fiche?, cr, session);
          if (!droit.ok) {
            return Tooltip(
                message: droit.motif ?? '',
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(LucideIcons.lock, size: 14, color: JetonsShell.slate400),
                  SizedBox(width: 4),
                  Text('restreint', style: TextStyle(color: JetonsShell.slate400, fontSize: 12, height: 16 / 12)),
                ]));
          }
          return BoutonSigh(
              libelle: 'Lire',
              icone: LucideIcons.fileText,
              taille: TailleBouton.sm,
              onPressed: () => afficherTiroir<void>(context,
                  titre: 'Compte rendu — ${_t(cr['examen'], '')}',
                  sousTitre: '${_t(cr['patient'], '')} · ${_t(cr['reference'], '')}',
                  corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    DescListeSigh([
                      ('Modalité', modalite(l)),
                      ('Date', dateFrM1(cr['date'] ?? (l['dem'] as Fiche?)?['dateHeure'])),
                      ('Indication', _t(cr['indication'] ?? (l['dem'] as Fiche?)?['indication'])),
                      ('Prescripteur', _t(cr['prescripteur'] ?? (l['dem'] as Fiche?)?['prescripteur'])),
                      ('Réalisé par', _t(cr['realisateur'])),
                    ]),
                    if (patVrai(cr['conclusion'])) sectionM1('Conclusion', paragrapheM1('${cr['conclusion']}')),
                  ])));
        }),
      ], lignes: ([...lignes]..sort((a, b) => '${b['date']}'.compareTo('${a['date']}'))).take(30).toList()),
    ]);
  }
}
