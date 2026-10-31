import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'pil_commun.dart';

/// Les statistiques CLINIQUES du pilotage : m5-stats-examens, m2-stats-echographie (imagerie médicale), m2-stats-consultations, m3-stats-bloc,
/// m3-stats-hospitalisations, m4-stats-maternite. Tout est CALCULÉ depuis les registres (jamais fourni) par `pilotage/pil_stats.dart` du domaine, rejoué
/// sur les vecteurs des écrans réels de la maquette ; l'écran peint la vue et ne recalcule rien.

/// Une carte de graphique cherchée par son titre dans la vue ; absente (aucune donnée), elle dit pourquoi au lieu de disparaître.
Widget _carteGraphique(PilVue v, String titre, String vide, IconData icone, {double hauteur = 260}) {
  PilGraphique? g;
  for (final x in v.graphiques) {
    if (x.titre == titre) g = x;
  }
  return CarteSigh(titre: titre, child: g != null ? pilGraphique(g, hauteur: hauteur) : VideSigh(vide, icone: icone));
}

// =====================================================================================================================================================
// m5-stats-examens
// =====================================================================================================================================================

/// `m5-stats-examens` — « Statistiques des examens » : les examens du laboratoire selon PLUSIEURS AXES (service demandeur, sexe, tranche d'âge, interne ou
/// externe, plage de dates). Chaque axe est un FILTRE : les compteurs, les graphiques et le tableau se recalculent sur la population filtrée, jamais fournis.
class EcranStatsExamens extends StatefulWidget with EcranMaquette {
  const EcranStatsExamens({super.key});

  @override
  String get titre => 'Statistiques des examens';

  @override
  String get description => 'Les examens du laboratoire selon plusieurs axes : service demandeur, âge, sexe, période, interne ou externe.';

  @override
  String get regle =>
      'La demande écrite du laboratoire : « les statistiques des examens selon plusieurs axes ». Chaque axe est un filtre — les compteurs, les graphiques et le tableau se recalculent sur la population filtrée, jamais fournis. Le périmètre suit le RBAC du manifeste.';

  @override
  State<EcranStatsExamens> createState() => _EtatStatsExamens();
}

class _EtatStatsExamens extends State<EcranStatsExamens> {
  ControleurFormulaire? _f;

  ControleurFormulaire _creer(List<String> services) => ControleurFormulaire([
        const ChampDef(nom: 'du', libelle: 'Du', type: TypeChamp.date),
        const ChampDef(nom: 'au', libelle: 'Au', type: TypeChamp.date),
        ChampDef(nom: 'service', libelle: 'Service demandeur', type: TypeChamp.select, options: [
          const OptionChamp('', 'Tous les services'),
          for (final s in services) OptionChamp(s),
        ]),
        const ChampDef(nom: 'sexe', libelle: 'Sexe', type: TypeChamp.select, options: [
          OptionChamp('', 'Deux sexes'),
          OptionChamp('F', 'Féminin'),
          OptionChamp('M', 'Masculin'),
        ]),
        ChampDef(nom: 'age', libelle: 'Tranche d’âge', type: TypeChamp.select, options: [
          const OptionChamp('', 'Tous les âges'),
          for (final t in pilTranchesAgeExamens) OptionChamp(t.$1, t.$2),
        ]),
        const ChampDef(nom: 'origine', libelle: 'Origine', type: TypeChamp.select, options: [
          OptionChamp('', 'Internes et externes'),
          OptionChamp('interne', 'Patients internes'),
          OptionChamp('externe', 'Patients externes'),
        ]),
      ]);

  @override
  void dispose() {
    _f?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    _f ??= _creer(pilServicesExamens(pilActives(c, 'demandesAnalyses')));
    final f = _f!;
    return ListenableBuilder(
      listenable: Listenable.merge([pilEcoute(c, ['demandesAnalyses', 'patients']), f]),
      builder: (context, _) {
        final dem = pilActives(c, 'demandesAnalyses'), pat = pilActives(c, 'patients');
        final filtre = PilFiltreExamens(
            du: pilBorne(f, 'du'), au: pilBorne(f, 'au'), service: pilBorne(f, 'service'), sexe: pilBorne(f, 'sexe'), age: pilBorne(f, 'age'), origine: pilBorne(f, 'origine'));
        final v = pilStatsExamens(dem, pat, filtre, c.aujourdhui);
        final detail = pilDetailExamens(pilExamensRetenus(dem, pat, filtre, c.aujourdhui));
        return pilPile([
          pilBandeau(f, const ['du', 'au', 'service', 'sexe', 'age', 'origine'], colonnes: 6),
          pilKpis(v.kpis, const [LucideIcons.flaskConical, LucideIcons.fileCheck2, LucideIcons.siren, LucideIcons.userPlus]),
          pilDeux(
              _carteGraphique(v, 'Par section d’examen', 'Aucun examen dans la population filtrée.', LucideIcons.flaskConical),
              _carteGraphique(v, 'Par service demandeur', 'Aucun service à compter.', LucideIcons.building2)),
          _carteGraphique(v, 'Par tranche d’âge', '', LucideIcons.chartColumn, hauteur: 220),
          TableauSigh(
            titre: 'Détail par examen',
            taillePage: 15,
            nomExport: 'stats-examens',
            messageVide: 'Rien à compter sur ces axes.',
            lignes: [for (final d in detail) {'examen': d.$1, 'compte': d.$2}],
            colonnes: [
              const ColonneTableau(cle: 'examen', libelle: 'Examen'),
              ColonneTableau(cle: 'compte', libelle: 'Demandes', droite: true, texte: (r) => nombre(r['compte'])),
            ],
          ),
          pilSource('Registre demandesAnalyses du magasin — recalculé à chaque filtre. Les axes sont ceux de la demande écrite du laboratoire (reunions/).'),
        ]);
      },
    );
  }
}

// =====================================================================================================================================================
// m2-stats-echographie
// =====================================================================================================================================================

/// `m2-stats-echographie` — « Statistiques de l'imagerie médicale » : examens par type, par mois, délais et part obstétricale, calculés depuis les
/// demandes et les comptes rendus. Un indicateur à zéro se lit : il dit qu'aucun registre ne porte la donnée, pas que l'activité n'existe pas.
class EcranStatsImagerie extends StatelessWidget with EcranMaquette {
  const EcranStatsImagerie({super.key});

  @override
  String get titre => 'Statistiques de l’imagerie médicale';

  @override
  String get description => 'Activité d’imagerie calculée depuis les registres : examens par type, par mois, délais et part obstétricale.';

  @override
  String get regle =>
      'Les chiffres sont calculés depuis les demandes et les comptes rendus — jamais fournis. Un indicateur à zéro se lit : il dit qu’aucun registre ne porte la donnée, pas que l’activité n’existe pas.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return ListenableBuilder(
      listenable: pilEcoute(c, ['demandesImagerie', 'resultatsImagerie']),
      builder: (context, _) {
        final v = pilStatsImagerie(pilActives(c, 'demandesImagerie'), pilActives(c, 'resultatsImagerie'));
        return pilPile([
          pilKpis(v.kpis, const [LucideIcons.scanLine, LucideIcons.fileCheck2, LucideIcons.baby, LucideIcons.clock]),
          pilDeux(
              _carteGraphique(v, 'Examens par type', 'Aucun compte rendu à compter.', LucideIcons.scanLine),
              _carteGraphique(v, 'Évolution mensuelle', 'Aucun mois à tracer.', LucideIcons.calendar)),
          CarteSigh(
              titre: 'Par réalisateur — le pied des pièces réelles porte « Réalisé par »',
              child: PilClassementSigh(v.classements.first.items)),
          pilSource('Registres demandesImagerie et resultatsImagerie du magasin — indicateurs recalculés à chaque affichage.'),
        ]);
      },
    );
  }
}

// =====================================================================================================================================================
// m2-stats-consultations
// =====================================================================================================================================================

/// `m2-stats-consultations` — « Statistiques des consultations » : par praticien (et son service à l'organigramme), par type, dans le temps. Le « secteur »
/// affiché est le service du praticien à l'organigramme : la consultation ne porte pas de secteur propre, et l'écran le dit plutôt que d'inventer une donnée.
class EcranStatsConsultations extends StatefulWidget with EcranMaquette {
  const EcranStatsConsultations({super.key});

  @override
  String get titre => 'Statistiques des consultations';

  @override
  String get description => 'L’activité de consultation par praticien, par type et dans le temps — calculée depuis le registre.';

  @override
  String get regle =>
      'Par praticien et par type, depuis le registre des consultations. Le « secteur » affiché est le service du praticien à l’organigramme — la consultation ne porte pas de secteur propre, et l’écran le dit plutôt que d’inventer une donnée.';

  @override
  State<EcranStatsConsultations> createState() => _EtatStatsConsultations();
}

class _EtatStatsConsultations extends State<EcranStatsConsultations> {
  final ControleurFormulaire _f = pilControleurPlage();

  @override
  void dispose() {
    _f.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([pilEcoute(c, ['consultations', 'personnel']), _f]),
      builder: (context, _) {
        final v = pilStatsConsultations(pilActives(c, 'consultations'), pilActives(c, 'personnel'), pilBorne(_f, 'du'), pilBorne(_f, 'au'), c.aujourdhui);
        return pilPile([
          pilBandeauPlage(_f),
          pilKpis(v.kpis, const [LucideIcons.stethoscope, LucideIcons.calendar, LucideIcons.users, LucideIcons.house]),
          CarteSigh(titre: 'Par praticien — et son service à l’organigramme', child: PilClassementSigh(v.classements.first.items)),
          pilDeux(
              _carteGraphique(v, 'Par type', '', LucideIcons.chartColumn),
              _carteGraphique(v, 'Évolution mensuelle', '', LucideIcons.calendar, hauteur: 240)),
          pilSource('Registre des consultations du magasin — indicateurs recalculés à chaque affichage.'),
        ]);
      },
    );
  }
}

// =====================================================================================================================================================
// m3-stats-bloc
// =====================================================================================================================================================

/// `m3-stats-bloc` — « Statistiques du bloc & de l'anesthésie » : comptes rendus opératoires, d'anesthésie et CPA. Les interventions SANS CPA sont comptées —
/// signalées, jamais bloquées : l'urgence n'attend pas une fiche. Un incident per-opératoire compte dès qu'il est NOMMÉ.
class EcranStatsBloc extends StatefulWidget with EcranMaquette {
  const EcranStatsBloc({super.key});

  @override
  String get titre => 'Statistiques du bloc & de l’anesthésie';

  @override
  String get description => 'Comptes rendus opératoires, comptes rendus d’anesthésie et CPA — calculés depuis les registres du bloc.';

  @override
  String get regle =>
      'Les interventions sans CPA sont comptées — signalées, jamais bloquées : l’urgence n’attend pas une fiche. Un incident per-opératoire compte dès qu’il est nommé — « aucun incident » s’écrit et ne compte pas.';

  @override
  State<EcranStatsBloc> createState() => _EtatStatsBloc();
}

class _EtatStatsBloc extends State<EcranStatsBloc> {
  final ControleurFormulaire _f = pilControleurPlage();

  @override
  void dispose() {
    _f.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([pilEcoute(c, ['crOperatoires', 'crAnesthesie', 'cpa']), _f]),
      builder: (context, _) {
        final v = pilStatsBloc(pilActives(c, 'crOperatoires'), pilActives(c, 'crAnesthesie'), pilActives(c, 'cpa'), pilBorne(_f, 'du'), pilBorne(_f, 'au'));
        return pilPile([
          pilBandeauPlage(_f),
          pilKpis(v.kpis.take(4).toList(), const [LucideIcons.scissors, LucideIcons.syringe, LucideIcons.stethoscope, LucideIcons.shieldAlert]),
          CarteSigh(
              titre: 'Interventions par opérateur',
              child: v.classements.isNotEmpty
                  ? PilClassementSigh(v.classements.first.items)
                  : const VideSigh('Aucun compte rendu opératoire au registre.', icone: LucideIcons.scissors)),
          pilDeux(
              _carteGraphique(v, 'Anesthésies par technique', 'Aucun compte rendu d’anesthésie.', LucideIcons.syringe, hauteur: 220),
              _carteGraphique(v, 'Conclusions des CPA', 'Aucune CPA au registre.', LucideIcons.stethoscope, hauteur: 220)),
          pilKpis(v.kpis.skip(4).toList(), const [LucideIcons.triangleAlert, LucideIcons.clock]),
          pilSource('Registres crOperatoires, crAnesthesie et cpa du magasin.'),
        ]);
      },
    );
  }
}

// =====================================================================================================================================================
// m3-stats-hospitalisations
// =====================================================================================================================================================

/// `m3-stats-hospitalisations` — « Statistiques des hospitalisations » : séjours, durée moyenne, occupation des lits et motifs d'admission. La durée moyenne
/// de séjour ne se calcule que sur les séjours TERMINÉS (un séjour en cours est toujours plus court que ce qu'il sera) ; le taux d'occupation se lit à une
/// DATE, quand la durée se lit sur une PÉRIODE.
class EcranStatsHospitalisations extends StatefulWidget with EcranMaquette {
  const EcranStatsHospitalisations({super.key});

  @override
  String get titre => 'Statistiques des hospitalisations';

  @override
  String get description => 'Séjours, durée moyenne, occupation des lits et motifs d’admission — calculés depuis le registre.';

  @override
  String get regle =>
      'La durée moyenne de séjour ne se calcule que sur les séjours TERMINÉS : un séjour en cours est toujours plus court que ce qu’il sera, et l’inclure abaisserait la moyenne sans que rien ne le signale. Le taux d’occupation rapporte les lits occupés au parc réel des chambres — il se lit à une DATE, quand la durée se lit sur une PÉRIODE.';

  @override
  State<EcranStatsHospitalisations> createState() => _EtatStatsHospitalisations();
}

class _EtatStatsHospitalisations extends State<EcranStatsHospitalisations> {
  final ControleurFormulaire _f = pilControleurPlage();

  @override
  void dispose() {
    _f.dispose();
    super.dispose();
  }

  void _etat(BuildContext ctx, ContexteEcran c, PilHospitalisations h) {
    final du = pilBorne(_f, 'du'), au = pilBorne(_f, 'au');
    ColonneEtat n(String l, num Function(Map<String, Object?>) k) =>
        ColonneEtat(libelle: l, valeur: (r) => nombre(k(r)), droite: true, somme: k);
    afficherApercu(
        ctx,
        PieceA4(
          titre: 'Statistiques des hospitalisations',
          sousTitre: 'Période : ${du.isNotEmpty ? dateFR(DateTime.parse(du)) : 'origine'} au ${au.isNotEmpty ? dateFR(DateTime.parse(au)) : dateFR(c.aujourdhui)}',
          reference: PieceA4.reference_(c.aujourdhui, ImpressionPoste.prochainNumero()),
          utilisateur: c.utilisateur,
          edite: c.aujourdhui,
          cartouche: pilCartoucheHospitalisations(h, du, au),
          blocs: [
            BlocTableau(TableauEtat(colonnes: [
              ColonneEtat(libelle: 'Type de chambre', valeur: (r) => '${r['type']}'),
              ColonneEtat(libelle: 'Prix de journée', valeur: (r) => money(r['tarif'], avecDevise: false), droite: true),
              n('Séjours', (r) => r['sejours'] as num),
              n('Journées', (r) => r['journees'] as num),
              ColonneEtat(libelle: 'Durée moyenne', valeur: (r) => '${pilTexteNombre(r['dms'] as num)} j', droite: true),
              ColonneEtat(libelle: 'Produit théorique', valeur: (r) => money(r['produit'], avecDevise: false), droite: true, somme: (r) => r['produit'] as num),
            ], lignes: [
              for (final r in h.parType)
                {'type': r.type, 'tarif': r.tarif, 'sejours': r.sejours, 'journees': r.journees, 'dms': r.dms, 'produit': r.produit}
            ])),
            const BlocTexte(
                'La durée moyenne ne porte que sur les séjours TERMINÉS : un séjour en cours est toujours plus court que ce qu’il sera. Le produit théorique applique le prix de journée aux journées constatées — il ne remplace pas la facturation réelle.',
                italique: true),
          ],
          signatures: const [Signature('Le Directeur Médical'), Signature('La Directrice de l’Administration et des Finances')],
        ));
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([pilEcoute(c, ['admissions']), _f]),
      builder: (context, _) {
        final h = pilStatsHospitalisations(pilActives(c, 'admissions'), pilBorne(_f, 'du'), pilBorne(_f, 'au'), c.aujourdhui, refMois: c.aujourdhui);
        final v = h.vue;
        return pilPile([
          pilBandeauPlage(_f),
          pilKpis(v.kpis, const [LucideIcons.bedDouble, LucideIcons.checkCircle2, LucideIcons.calendarDays, LucideIcons.timer, LucideIcons.activity, LucideIcons.layoutGrid]),
          pilCarteTable(v.tables[0], titre: 'Par type de chambre'),
          pilDeux(
              _carteGraphique(v, 'Diagnostics d’entrée les plus fréquents', 'Aucun séjour sur la période.', LucideIcons.bedDouble, hauteur: 240),
              _carteGraphique(v, 'Séjours par mois', '', LucideIcons.calendar, hauteur: 240)),
          pilCarteTable(v.tables[1], titre: 'Durée moyenne par diagnostic — sur les séjours terminés'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            BoutonSigh(key: const Key('pil:editer-etat'), libelle: 'Éditer l’état', icone: LucideIcons.printer, onPressed: () => _etat(context, c, h)),
          ]),
          pilSource('Registre des admissions et référentiel des chambres — recalculé à chaque affichage.'),
        ]);
      },
    );
  }
}

// =====================================================================================================================================================
// m4-stats-maternite
// =====================================================================================================================================================

/// `m4-stats-maternite` — « Statistiques maternité & naissances » : les indicateurs DHIS2/SNIS du rapport officiel du 27/08/2026, CALCULÉS depuis les
/// registres (CPN, accouchements, naissances, PF, SONU) — un chiffre fourni à la main divergerait du registre au premier correctif.
class EcranStatsMaternite extends StatelessWidget with EcranMaquette {
  const EcranStatsMaternite({super.key});

  @override
  String get titre => 'Statistiques maternité & naissances';

  @override
  String get description => 'Indicateurs DHIS2/SNIS : CPN, SP, MILDA, GAR, accouchements, PF, vaccination et mortalité.';

  @override
  String get regle =>
      'Chaque indicateur est calculé depuis les registres (CPN, accouchements, naissances, PF, SONU) — le rapport demande leur agrégation automatique pour la saisie DHIS2, et un chiffre fourni à la main divergerait du registre au premier correctif.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return ListenableBuilder(
      listenable: pilEcoute(c, ['grossesses', 'accouchements', 'naissances', 'planificationFamiliale', 'registreSONU', 'soinsCuratifsMaternite']),
      builder: (context, _) {
        final v = pilStatsMaternite(
            grossesses: pilActives(c, 'grossesses'),
            accouchements: pilActives(c, 'accouchements'),
            naissances: pilActives(c, 'naissances'),
            planification: pilActives(c, 'planificationFamiliale'),
            sonu: pilActives(c, 'registreSONU'),
            curatifs: pilActives(c, 'soinsCuratifsMaternite'));
        return pilPile([
          pilKpis(v.kpis.take(4).toList(), const [LucideIcons.shieldCheck, LucideIcons.tent, LucideIcons.triangleAlert, LucideIcons.heartHandshake]),
          pilKpis(v.kpis.skip(4).toList(), const [LucideIcons.shield, LucideIcons.cross, LucideIcons.ambulance, LucideIcons.siren]),
          pilDeux(
              _carteGraphique(v, 'Types d’accouchement', '', LucideIcons.baby),
              _carteGraphique(v, 'Méthodes PF adoptées', '', LucideIcons.heartHandshake)),
          pilCarteTable(v.tables.first, titre: 'Vaccination et soins de naissance (J0)'),
          pilSource('Rapport officiel maternité du 27/08/2026 — §5.3 : « calcul automatique des indicateurs DHIS2/SNIS ». Les chiffres sont recalculés à chaque affichage depuis les registres.'),
        ]);
      },
    );
  }
}
