import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'rha_commun.dart';
import 'rhb_commun.dart';
import 'rhc_commun.dart';

/// `m10-assurance-personnel` — « Assurance du personnel » : la clinique soigne ses agents à 100 %. Ce n'est PAS une assurance au sens de M9 : aucun tiers ne rembourse, aucune
/// créance ne naît, et la prestation ne remonte NI aux recettes NI à la comptabilité. C'est un avantage consenti — dont la Direction doit connaître le volume. D'où le parti pris :
/// AUCUNE SAISIE. L'écran se remplit depuis les consultations, analyses et hospitalisations de l'agent (son dossier patient porte son matricule) ; en ouvrir une ici créerait une
/// seconde vérité, divergente du dossier. Les prestations sont LUES dans leurs collections d'origine, jamais recopiées.
///
/// E747 — une hospitalisation n'a pas de montant dans le jeu : sa valeur s'affiche « 0 » alors qu'elle est INCONNUE (« non calculable » n'est pas zéro). Porté fidèlement, signalé.
/// E748 ✅ corrigé dans la maquette — les analyses prescrites n'étaient JAMAIS comptées (la date était lue sur `date` / `dateDemande`, le poste écrit `dateHeure`, et le prix sur
/// `montant`, absent : 25 analyses d'agents invisibles).
class EcranAssurancePersonnel extends StatefulWidget with EcranMaquette {
  const EcranAssurancePersonnel({super.key});

  @override
  String get titre => 'Assurance du personnel';
  @override
  String get description => 'Prestations dispensées aux agents de la clinique, prises en charge à 100 % — hors recettes et hors comptabilité.';
  @override
  String get regle =>
      'Prise en charge à 100 %, sans tiers payeur. Ces prestations ne constituent ni une recette ni une créance : elles ne figurent ni au relevé assureur, ni au chiffre d’affaires, ni en comptabilité. La valeur affichée mesure l’avantage consenti, elle ne s’encaisse pas. Écran sans saisie — il se remplit depuis le dossier patient de l’agent.';

  @override
  State<EcranAssurancePersonnel> createState() => _EtatAssurance();
}

class _EtatAssurance extends State<EcranAssurancePersonnel> {
  RhbFiltre? _periode, _fonction;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_periode != null) return;
    _periode = RhbFiltre(ChampDef(nom: 'periode', libelle: 'Période', type: TypeChamp.select, options: rhcOptions(rhcPeriodesAssurance)), '365');
    _fonction = RhbFiltre(ChampDef(nom: 'fonction', libelle: 'Fonction', type: TypeChamp.select, options: [
      const OptionChamp('', 'Toutes les fonctions'),
      for (final f in rhbFonctions) OptionChamp(f.id, f.label),
    ]));
    for (final f in [_periode!, _fonction!]) {
      f.controleur.addListener(_maj);
    }
  }

  @override
  void dispose() {
    for (final f in [_periode!, _fonction!]) {
      f.controleur.removeListener(_maj);
    }
    super.dispose();
  }

  void _maj() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => RhbEcoute(collections: const ['patients', 'consultations', 'demandesAnalyses', 'admissions', 'personnel'], construire: _corps);

  List<Fiche> _agents(ContexteEcran c) => [for (final p in rhbActives(c, 'patients')) if (p['personnelId'] != null && p['personnelId'] != '') p];

  List<Fiche> _prestations(ContexteEcran c) {
    final analyses = c.magasin.referentiel('analyses');
    Fiche? analyseDe(Object? a) {
      for (final x in analyses) {
        if (x['code'] == a || x['libelle'] == a) return x;
      }
      return null;
    }

    return rhcPrestations(
        patients: rhbActives(c, 'patients'),
        consultations: rhbActives(c, 'consultations'),
        analyses: rhbActives(c, 'demandesAnalyses'),
        admissions: rhbActives(c, 'admissions'),
        min: rhcBorneMin(_periode!.valeur, c.aujourdhui),
        fonction: _fonction!.valeur,
        prixAnalyse: (a) => analyseDe(a)?['prix'] as num?,
        libelleAnalyse: (a) => '${analyseDe(a)?['libelle'] ?? 'Analyse'}');
  }

  Widget _corps(BuildContext context, ContexteEcran c) {
    final rows = _prestations(c);
    final couverts = _agents(c);
    final libPeriode = rhcLibellePeriodeAssurance(_periode!.valeur);
    return rhbEspace([
      rhbBarre([_periode!, _fonction!], colonnes: 4, boutons: [
        BoutonSigh(libelle: 'Imprimer l’état', icone: LucideIcons.printer, onPressed: () => _imprimer(context, c, rows)),
      ]),
      KpiGrilleSigh(kpis: [
        KpiSigh(libelle: 'Agents ayant un dossier patient', valeur: nombre(couverts.length), icone: LucideIcons.shieldCheck, ton: TonSigh.navy, indice: 'sur ${nombre(rhcPersonnel(c).length)} agents'),
        KpiSigh(libelle: 'Prestations prises en charge', valeur: nombre(rows.length), icone: LucideIcons.stethoscope, ton: TonSigh.info),
        KpiSigh(libelle: 'Valeur de l’avantage', valeur: money(rhcSomme(rows, 'valeur')), icone: LucideIcons.gift, ton: TonSigh.succes, indice: 'Ni recette, ni créance'),
        KpiSigh(libelle: 'Agents effectivement soignés', valeur: nombre(rows.map((r) => r['patientId']).toSet().length), icone: LucideIcons.users, ton: TonSigh.neutre),
      ]),
      const NoteSigh(
          'Ce tableau ne se saisit pas. Il se remplit dès qu’un agent est reçu en consultation, qu’une analyse lui est prescrite ou qu’il est hospitalisé — parce que son dossier patient porte son matricule. Pour corriger une ligne, il faut corriger la prestation d’origine dans son module : une saisie ici créerait une seconde vérité, divergente du dossier.',
          ton: TonSigh.attention,
          icone: LucideIcons.lock),
      if (rows.isEmpty)
        const CarteSigh(
            titre: 'Prestations au personnel',
            child: VideSigh('Aucune prestation sur la période retenue.',
                icone: LucideIcons.shieldCheck, indice: 'Élargir la période, ou vérifier que l’agent dispose bien d’un dossier patient à son nom.'))
      else ...[
        TableauSigh(
          titre: 'Prestations prises en charge — ${_periode!.valeur.isEmpty ? 'toutes périodes' : libPeriode}',
          lignes: rows,
          taillePage: 20,
          triInitial: 'date',
          sensInitial: 'desc',
          nomExport: 'assurance-personnel',
          filtres: [
            FiltreTableau(nom: 'nature', libelle: 'Nature', options: const [OptionChamp('Consultation'), OptionChamp('Analyse'), OptionChamp('Hospitalisation')]),
          ],
          colonnes: [
            ColonneTableau(cle: 'date', libelle: 'Date', sansCoupure: true, texte: (r) => rhcDate(r['date'])),
            ColonneTableau(
                cle: 'agent',
                libelle: 'Agent',
                texte: (r) => '${r['agent']}',
                rendu: (_, r) => rhcDeuxLignes('${r['agent']}', '${'${r['matricule'] ?? ''}'.isEmpty ? '—' : r['matricule']} · ${r['fonctionLabel']}')),
            ColonneTableau(
                cle: 'code',
                libelle: 'Dossier',
                sansCoupure: true,
                texte: (r) => '${r['code']}',
                rendu: (_, r) => Text('${r['code']}', style: const TextStyle(fontFamily: 'LiberationMono', fontSize: 12, height: 16 / 12))),
            ColonneTableau(
                cle: 'nature',
                libelle: 'Nature',
                texte: (r) => '${r['nature']}',
                rendu: (_, r) => BadgeSigh('${r['nature']}', ton: r['nature'] == 'Consultation' ? TonSigh.info : (r['nature'] == 'Analyse' ? TonSigh.navy : TonSigh.attention))),
            const ColonneTableau(cle: 'detail', libelle: 'Détail'),
            const ColonneTableau(cle: 'praticien', libelle: 'Praticien'),
            ColonneTableau(
                cle: 'valeur',
                libelle: 'Valeur',
                droite: true,
                texte: (r) => rhcMontant(r['valeur']),
                rendu: (_, r) => Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                      Text(rhcMontant(r['valeur']), style: const TextStyle(color: Color(0xFF64748B), fontSize: 14, height: 20 / 14)),
                      const Text('pris en charge 100 %', style: TextStyle(color: Color(0xFF15803D), fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w600)),
                    ])),
          ],
          // Le dossier s'ouvre depuis le répertoire des patients (fusion du 31/08/2026) : « m1-dossier » n'a jamais existé.
          actionsLigne: (ctx, r) => [BoutonIcone(icone: LucideIcons.folderOpen, libelle: 'Ouvrir le dossier du patient', onPressed: () => c.aller('m1-patients'))],
        ),
        _graphiques(rows),
      ],
      rhcSource(
          'Prise en charge du personnel à 100 % — décision de la Direction. Ces montants sont volontairement absents du chiffre d’affaires, des relevés assureur et des écritures comptables : les y porter gonflerait des recettes qui n’ont jamais été encaissées.'),
    ]);
  }

  Widget _graphiques(List<Fiche> rows) {
    final parNature = rhcGrouper(rows, (r) => '${r['nature']}');
    final parFonction = rhcGrouper(rows, (r) => '${r['fonctionLabel']}');
    final parMois = rhcGrouper(rows, (r) => '${r['date']}'.substring(0, 7));
    final mois = parMois.keys.toList()..sort();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      rhbTroisCartes([
        CarteSigh(titre: 'Valeur par nature de prestation', child: GraphiqueAnneau(trou: 0, etiquettes: parNature.keys.toList(), valeurs: [for (final l in parNature.values) rhcSomme(l, 'valeur')])),
        CarteSigh(
            titre: 'Prestations par fonction',
            child: GraphiqueBarres(
                horizontal: true,
                etiquettes: parFonction.keys.toList(),
                series: [SerieGraphique('Prestations', [for (final l in parFonction.values) l.length], couleur: rhbTonNavy)])),
        CarteSigh(
            titre: 'Les dix agents les plus pris en charge',
            child: RhaClassement([for (final a in rhcDixPremiersAgents(rows)) (libelle: a.$1, valeur: a.$2, rouge: false)], argent: true)),
      ]),
      if (mois.length > 1) ...[
        const SizedBox(height: 16),
        CarteSigh(
            titre: 'Valeur mensuelle de l’avantage',
            child: GraphiqueLigne(hauteur: 240, etiquettes: [for (final m in mois) rhcMois(m)], series: [SerieGraphique('FCFA', [for (final m in mois) rhcSomme(parMois[m]!, 'valeur')], couleur: rhbTonVert)])),
      ],
    ]);
  }

  void _imprimer(BuildContext ctx, ContexteEcran c, List<Fiche> rows) {
    final parAgent = rhcGrouper(rows, (r) => '${r['agent']}');
    final lignes = trierPar([
      for (final e in parAgent.entries)
        <String, Object?>{
          'agent': e.key,
          'matricule': e.value.first['matricule'] ?? '—',
          'fonction': e.value.first['fonctionLabel'],
          'consultations': e.value.where((x) => x['nature'] == 'Consultation').length,
          'analyses': e.value.where((x) => x['nature'] == 'Analyse').length,
          'hospitalisations': e.value.where((x) => x['nature'] == 'Hospitalisation').length,
          'valeur': rhcSomme(e.value, 'valeur'),
        }
    ], (l) => l['valeur'], descendant: true);
    ColonneEtat n(String lib, String k) => ColonneEtat(libelle: lib, valeur: (r) => nombre(r[k]), droite: true, somme: (r) => r[k] as num);
    final lib = rhcLibellePeriodeAssurance(_periode!.valeur);
    afficherApercu(
        ctx,
        rhbPiece(c,
            titre: 'État de la prise en charge du personnel',
            sousTitre: _periode!.valeur.isNotEmpty ? lib : 'Depuis l’origine',
            cartouche: [
              ('Période', lib),
              ('Agents concernés', nombre(lignes.length)),
              ('Prestations', nombre(rows.length)),
              ('Valeur totale', money(rhcSomme(rows, 'valeur'))),
              ('Établi par', c.utilisateur),
              ('Date d’édition', dateFR(c.aujourdhui)),
            ],
            blocs: [
              BlocTableau(TableauEtat(colonnes: [
                ColonneEtat(libelle: 'Matricule', valeur: (r) => r['matricule']),
                ColonneEtat(libelle: 'Agent', valeur: (r) => r['agent']),
                ColonneEtat(libelle: 'Fonction', valeur: (r) => r['fonction']),
                n('Consult.', 'consultations'),
                n('Analyses', 'analyses'),
                n('Hospit.', 'hospitalisations'),
                ColonneEtat(libelle: 'Valeur prise en charge', valeur: (r) => rhcMontant(r['valeur']), droite: true, somme: (r) => r['valeur'] as num),
              ], lignes: lignes)),
              const BlocTexte(
                  'Les prestations dispensées au personnel de la clinique sont prises en charge à 100 % par l’établissement. Elles ne constituent ni une recette, ni une créance sur un tiers payeur, et ne donnent lieu à aucune écriture comptable. La valeur portée au présent état mesure l’avantage consenti au personnel ; elle ne correspond à aucun encaissement.',
                  italique: true),
            ],
            signatures: [rhbSignDaf, rhbSignDm]));
  }
}
