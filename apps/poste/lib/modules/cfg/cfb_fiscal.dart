import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'cfa_commun.dart';
import 'cfb_commun.dart';
import 'cfb_configuration_fiscale.dart';

const _mono = 'LiberationMono';

String _dateFr(Object? iso) => iso == null || '$iso'.isEmpty ? '' : dateFR(DateTime.parse(isoJour(iso)));
String _dateHeureFr(Object? iso) {
  final d = DateTime.tryParse('${iso ?? ''}');
  return d == null ? '' : dateHeure(d.toLocal());
}

/// `libelleEcheanceObligation(o)` : « le 10 du mois suivant » ou « le 10 mars ».
String _libelleEcheance(Fiche o) => o['periodicite'] == 'mensuelle' ? 'le ${o['jour']} du mois suivant' : 'le ${o['jour']} ${paiMois[nombreOuZero(o['mois']).toInt()]}';

/// Les fiches d'obligations en vigueur relues sur la forme du calendrier (pour les fonctions de `cfb_regles.dart`).
List<CfbObligation> _calendrier(List<Fiche> fiches) => [for (final f in fiches) cfbObligationDepuisFiche(f)];

/// Les écouteurs des quatre écrans : identité, obligations, historique, échéances, exercices.
Listenable _ecoute(Magasin m) =>
    Listenable.merge([for (final n in const ['identiteLegale', 'obligationsFiscales', 'historiqueObligations', 'echeancesFiscales', 'exercices']) m.collection(n)]);

// =============================================================================================================================================
// cfg-fiscalite
// =============================================================================================================================================

/// `cfg-fiscalite` : « Paramètres fiscaux (IFU / RCCM) ». LA PART FISCALE DE L'IDENTITÉ SE SAISIT ET SE VALIDE ICI (Direction, 06/11/2026) : le formulaire
/// écrit la MÊME fiche que `cfg-branding` (ses champs à lui : forme, IFU, RCCM, autorisation, adresse fiscale, devise, régime de TVA). Avant la première
/// validation, « Enregistrer » corrige la version en force ; après, il ouvre la modale de portée (date d'effet, motif) et crée une version. « Valider »
/// est réservé à la Direction, à la DAF et à l'administrateur. Numérotation et calendrier en lecture ; la table des obligations déclaratives se DÉRIVE
/// des obligations mensuelles en vigueur (E2273).
class EcranFiscalite extends StatefulWidget with EcranMaquette {
  const EcranFiscalite({super.key});
  @override
  String get titre => 'Paramètres fiscaux (IFU / RCCM)';
  @override
  String get description => 'Identité fiscale de l’établissement (vérifiée et validée), numérotation des documents et calendrier des obligations.';
  @override
  String get regle =>
      'L’identité légale se vérifie et se valide à la première configuration, puis se modifie par versions datées : une pièce émise garde l’en-tête de sa date. La validation appartient à la Direction, à la DAF ou à l’administrateur système ; elle est journalisée (RG-12) et ne modifie aucune valeur.';

  @override
  State<EcranFiscalite> createState() => _EtatFiscalite();
}

/// Les champs que `cfg-fiscalite` écrit (`CHAMPS_FISCAUX`).
const List<String> champsFiscaux = ['forme', 'ifu', 'rccm', 'autorisation', 'bp', 'devise', 'codeDevise', 'regimeTva'];

class _EtatFiscalite extends State<EcranFiscalite> {
  ControleurFormulaire? _f;
  int? _versionFormulaire;
  bool _amorce = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_amorce) return;
    _amorce = true;
    ConfigurationFiscalePoste.amorcer(ContexteEcran.of(context).magasin);
  }

  @override
  void dispose() {
    _f?.dispose();
    super.dispose();
  }

  /// Le formulaire se reconstruit quand la version en force change (après un enregistrement, une nouvelle version).
  ControleurFormulaire _formulaire(IdentiteImprimee i) {
    if (_f != null && _versionFormulaire == i.version) return _f!;
    _f?.dispose();
    _versionFormulaire = i.version;
    return _f = ControleurFormulaire([
      ChampDef.section('Identification fiscale de l’établissement (version ${i.version ?? 1} en force)'),
      const ChampDef(nom: 'nom', libelle: 'Dénomination sociale', col: ColChamp.plein, aide: 'Se modifie à l’écran Identité & papier à en-tête.'),
      const ChampDef(nom: 'forme', libelle: 'Forme juridique', col: ColChamp.plein),
      const ChampDef(nom: 'ifu', libelle: 'IFU (13 chiffres)', requis: true),
      const ChampDef(nom: 'rccm', libelle: 'RCCM', requis: true),
      const ChampDef(nom: 'autorisation', libelle: 'Autorisation d’ouverture', col: ColChamp.plein),
      const ChampDef(nom: 'bp', libelle: 'Adresse fiscale (adresse postale imprimée)', col: ColChamp.plein),
      const ChampDef(nom: 'devise', libelle: 'Devise', col: ColChamp.tiers),
      const ChampDef(nom: 'codeDevise', libelle: 'Code ISO de la devise', col: ColChamp.tiers),
      const ChampDef(
          nom: 'regimeTva',
          libelle: 'Régime de TVA',
          col: ColChamp.tiers,
          aide: 'Porté tel qu’affiché ; le MECeF applique l’exonération relevée sur la facture de référence (divergence signalée, E2272).'),
    ], {
      'nom': i.nom,
      'forme': i.forme,
      'ifu': i.ifu,
      'rccm': i.rccm,
      'autorisation': i.autorisation,
      'bp': i.bp,
      'devise': i.devise,
      'codeDevise': i.codeDevise,
      'regimeTva': i.regimeTva,
    });
  }

  void _enregistrer(BuildContext ctx, ConfigurationFiscalePoste cf) {
    final v = _f!.valider();
    if (v == null) {
      ToastsSigh.afficher(ctx, 'Le formulaire comporte des erreurs.', type: TypeToast.erreur);
      return;
    }
    cfbEnregistrerIdentiteDepuis(ctx, cf, 'cfg-fiscalite', {for (final k in champsFiscaux) k: v[k]}, apres: () {
      if (mounted) setState(() => _versionFormulaire = null);
    });
  }

  Widget _tableVersions(ConfigurationFiscalePoste cf) {
    final a = isoJour(cf.maintenant);
    final versions = cf.versions.actives.toList()..sort((x, y) => nombreOuZero(y['version']).compareTo(nombreOuZero(x['version'])));
    return MiniTableauSigh(
        vide: 'Aucune version : réinitialiser le jeu de démonstration.',
        colonnes: [
          ColonneMini('Version', (v) => 'v${v['version']}', rendu: (v) => _mono12('v${v['version']}')),
          ColonneMini('En force', (v) => '', rendu: (v) {
            final enForce = (v['debut'] == null || isoJour(v['debut']).compareTo(a) <= 0) && (v['fin'] == null || isoJour(v['fin']).compareTo(a) >= 0);
            if (enForce) return const BadgeSigh('Aujourd’hui', ton: TonSigh.succes);
            return v['debut'] != null && isoJour(v['debut']).compareTo(a) > 0 ? const BadgeSigh('À venir', ton: TonSigh.info) : const BadgeSigh('Antérieure');
          }),
          ColonneMini('Du', (v) => v['debut'] != null ? _dateFr(v['debut']) : 'ouverture du dossier'),
          ColonneMini('Au', (v) => v['fin'] != null ? _dateFr(v['fin']) : 'en force'),
          ColonneMini('IFU / RCCM', (v) => '${v['ifu']} / ${v['rccm']}'),
          ColonneMini('Validée', (v) => v['valideLe'] != null ? '${_dateHeureFr(v['valideLe'])} par ${v['validePar']}' : 'À valider',
              rendu: (v) => v['valideLe'] != null ? Text('${_dateHeureFr(v['valideLe'])} par ${v['validePar']}') : const BadgeSigh('À valider', ton: TonSigh.attention)),
          ColonneMini('Motif', (v) => '${v['motif'] ?? (v['version'] == 1 ? 'semence (arbitrage du 31/08/2026)' : '—')}'),
        ],
        lignes: versions);
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final cf = ConfigurationFiscalePoste(c);
    return ListenableBuilder(
        listenable: _ecoute(c.magasin),
        builder: (context, _) {
          final i = cf.identiteImprimee();
          final f = _formulaire(i);
          final enVigueur = cf.obligationsALaDate();
          final mensuelles = [for (final o in enVigueur) if (o['periodicite'] == 'mensuelle') o];
          final echeances = cfbEcheances(c.aujourdhui, obligations: _calendrier(enVigueur));
          final note = cfbNoteProches(echeances, dateFR);
          final lignes = [
            for (final e in echeances)
              {
                'code': e.code,
                'libelle': e.obligation.libelle,
                'periodicite': e.obligation.periodicite,
                'echeance': cfbIso(e.echeance),
                'jours': e.jours,
                'reporte': e.reporte,
                'note': e.obligation.note,
              }
          ];
          final declaratives = [
            for (final o in mensuelles) {'d': '${o['libelle']} (${o['code']})', 'p': 'Mensuelle', 'e': 'le ${o['jour']} du mois suivant', 'ecran': 'm11-cotisations'},
            {'d': 'Transmission des factures normalisées', 'p': 'Continue', 'e': 'À l’émission', 'ecran': 'mecef-transmission'},
            {'d': 'États financiers de synthèse', 'p': 'Annuelle', 'e': 'Clôture de l’exercice, dépôt au 30 avril', 'ecran': 'm12-etats-financiers'},
          ];
          final futures = cfbNoteVersionsAVenir(cf);
          final valider = cfbBoutonValider(context, cf, identite: true, libelle: 'l’identité légale');
          return cfaPile([
            cfbBandeauEtat(cf, identite: true, libelle: 'identité légale'),
            if (futures != null) futures,
            cfbNote('Ces paramètres sont partagés avec le module MECeF. Une modification s’applique aux documents émis à partir de sa date d’effet ; les pièces antérieures gardent leur en-tête.'),
            CarteSigh(
                titre: 'Identification fiscale de l’établissement',
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  FormulaireSigh(controleur: f),
                  const SizedBox(height: 16),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    // Écrire l'identité est une écriture : la commande est ABSENTE sans le droit (fileul compris, la coque retire le droit).
                    if (c.droit.editer) BoutonSigh(key: const Key('cfb:fiscalite:enregistrer'), libelle: 'Enregistrer', icone: LucideIcons.save, onPressed: () => _enregistrer(context, cf)),
                    if (valider != null) valider,
                    cfbLien(c, cfbEcranMecefConfig, 'Configuration MECeF'),
                  ]),
                ])),
            CarteSigh(titre: 'Versions de l’identité légale', child: _tableVersions(cf)),
            CarteSigh(
                titre: 'Numérotation des documents',
                child: MiniTableauSigh(colonnes: [
                  ColonneMini('Type de document', (x) => '${x['type']}'),
                  ColonneMini('Préfixe', (x) => '${x['prefixe']}', rendu: (x) => _mono12('${x['prefixe']}')),
                  ColonneMini('Format', (x) => '${x['format']}'),
                  ColonneMini('Séquence', (x) => '${x['sequence']}'),
                ], lignes: [
                  for (final n in cfbNumerotation) {'type': n.$1, 'prefixe': n.$2, 'format': n.$3, 'sequence': n.$4}
                ])),
            CarteSigh(
                titre: 'Obligations déclaratives (dérivées des obligations en vigueur)',
                child: MiniTableauSigh(colonnes: [
                  ColonneMini('Déclaration', (x) => '${x['d']}'),
                  ColonneMini('Périodicité', (x) => '${x['p']}'),
                  ColonneMini('Échéance', (x) => '${x['e']}'),
                  ColonneMini('Écran producteur', (x) => 'Éditer',
                      rendu: (x) => BoutonSigh(libelle: 'Éditer', variante: VarianteBouton.secondaire, taille: TailleBouton.sm, onPressed: () => c.aller('${x['ecran']}'))),
                ], lignes: declaratives)),
            cfaKpis(cfbKpisFiscalite(echeances)),
            if (note != null) cfbNote(note, ton: 'warning', icone: LucideIcons.alarmClock),
            TableauSigh(
              titre: 'Calendrier fiscal et social',
              lignes: lignes,
              taillePage: 20,
              triInitial: 'jours',
              nomExport: 'calendrier-fiscal',
              filtres: const [FiltreTableau(nom: 'periodicite', libelle: 'Périodicité', options: [OptionChamp('mensuelle', 'Mensuelle'), OptionChamp('annuelle', 'Annuelle')])],
              colonnes: [
                ColonneTableau(cle: 'code', libelle: 'Code', sansCoupure: true, rendu: (_, e) => _mono12('${e['code']}')),
                const ColonneTableau(cle: 'libelle', libelle: 'Obligation'),
                ColonneTableau(
                    cle: 'periodicite',
                    libelle: 'Périodicité',
                    texte: (e) => e['periodicite'] == 'mensuelle' ? 'Mensuelle' : 'Annuelle',
                    rendu: (_, e) => e['periodicite'] == 'mensuelle' ? const BadgeSigh('Mensuelle', ton: TonSigh.info) : const BadgeSigh('Annuelle', ton: TonSigh.navy)),
                ColonneTableau(
                    cle: 'echeance',
                    libelle: 'Prochaine échéance',
                    sansCoupure: true,
                    texte: (e) => dateFR(DateTime.parse('${e['echeance']}')),
                    rendu: (_, e) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                          Text(dateFR(DateTime.parse('${e['echeance']}')), style: const TextStyle(fontSize: 14, height: 20 / 14, color: JetonsShell.slate700)),
                          if (e['reporte'] == true) const Text('reportée : jour ouvrable', style: TextStyle(fontSize: 10, height: 14 / 10, color: JetonsShell.warning600)),
                        ])),
                ColonneTableau(
                    cle: 'jours',
                    libelle: 'Dans',
                    droite: true,
                    texte: (e) => cfbLibelleDelai(e['jours'] as int),
                    rendu: (_, e) {
                      final j = e['jours'] as int;
                      if (j < 0) return const Text('passée', style: TextStyle(fontSize: 12, height: 16 / 12, color: JetonsShell.slate400));
                      return Text('$j j',
                          style: TextStyle(
                              fontSize: 14,
                              height: 20 / 14,
                              fontWeight: j <= 10 ? FontWeight.w600 : FontWeight.w400,
                              color: j <= 10 ? JetonsShell.danger600 : (j <= 30 ? JetonsShell.warning600 : JetonsShell.slate600)));
                    }),
                ColonneTableau(cle: 'note', libelle: 'Règle appliquée', rendu: (_, e) => Text('${e['note']}', style: const TextStyle(fontSize: 12, height: 16 / 12, color: JetonsShell.slate500))),
              ],
            ),
            cfbNote(
                'Impôt sur les sociétés. L’impôt de l’exercice se paie par anticipation : l’impôt de l’année précédente est divisé en quatre acomptes, versés les 10 mars, 10 juin, 10 septembre et 10 décembre. Le 30 avril de l’année suivante, la liquidation du solde ajuste à la hausse ou à la baisse, en même temps que le dépôt des états financiers.',
                icone: LucideIcons.landmark),
            cfaSource('${cfbCalendrierFiscal.first.source} : le calendrier de la CCIB et des acomptes d’impôt sur les sociétés a été confirmé par la Direction le 25/08/2026 (déclaration prévisionnelle de fin de mois, puis deux tranches de 50 % aux 10 mars et 10 juin pour la CCIB ; quatre acomptes aux 10 mars, 10 juin, 10 septembre et 10 décembre pour l’impôt sur les sociétés, liquidation du solde et dépôt des états financiers au 30 avril de l’année suivante).'),
          ]);
        });
  }
}

Widget _mono12(String t, {Color couleur = JetonsShell.slate900}) =>
    Text(t, style: TextStyle(fontFamily: _mono, fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w600, color: couleur));

// =============================================================================================================================================
// cfg-comptabilite
// =============================================================================================================================================

Widget _encart(String titre, String texte, {bool navy = false, Key? key}) => Container(
    key: key,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
        color: navy ? JetonsShell.navy50 : JetonsShell.slate50, borderRadius: BorderRadius.circular(8), border: Border.all(color: navy ? JetonsShell.navy200 : JetonsShell.slate200)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(titre.toUpperCase(),
          style: TextStyle(fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w600, letterSpacing: 0.6, color: navy ? JetonsShell.navy700 : JetonsShell.slate500)),
      const SizedBox(height: 4),
      Text(texte, style: const TextStyle(fontSize: 14, height: 20 / 14, color: JetonsShell.slate700)),
    ]));

/// `cfg-comptabilite` : « Paramètres comptables & obligations ». La RÉFÉRENCE documentaire des obligations, VALIDÉE par la Direction ; chaque ligne est une
/// fiche de `obligationsFiscales`, modifiable ou retirable à une DATE D'EFFET (modale de portée) : la version sortante va à `historiqueObligations`, les
/// échéances payées sont conservées, les non payées régénérées (E2273). Les paramètres ORTB suivent la même règle (E2274). CNSS, VPS et ITS restent
/// arrêtés par le CDCT : lecture seule. Il ne calcule ni ne paie : le suivi des paiements est à `m12-echeances`.
class EcranComptabilite extends StatefulWidget with EcranMaquette {
  const EcranComptabilite({super.key});
  @override
  String get titre => 'Paramètres comptables & obligations';
  @override
  String get description =>
      'Obligations fiscales et sociales de la clinique : périodicités, tranches, déclarations préalables et redevances, vérifiées et validées, modifiables par versions datées.';
  @override
  String get regle =>
      'Cet écran est la référence documentaire des obligations, validée par la Direction. Il ne calcule ni ne paie : le suivi des paiements et leur validation se tiennent à l’écran Échéances fiscales & paiements. Une obligation se modifie à une date d’effet : les échéances payées sont conservées, les non payées régénérées. Toute échéance tombant un week-end est reportée au jour ouvrable suivant.';

  @override
  State<EcranComptabilite> createState() => _EtatComptabilite();
}

final List<OptionChamp> _moisOptions = [for (var i = 0; i < 12; i++) OptionChamp('$i', paiMoisCap(i))];

/// `champsObligation(o, creation)` : le formulaire d'une obligation (le code ne change pas après la création).
List<ChampDef> _champsObligation(Fiche? o, bool creation) => [
      ChampDef(
          nom: 'code',
          libelle: 'Code',
          requis: creation,
          aide: creation
              ? 'Majuscules, chiffres et traits d’union (ex. : TPS-1). Il identifie l’obligation au journal et ne change plus.'
              : 'Le code identifie l’obligation : il ne change pas.'),
      const ChampDef(nom: 'libelle', libelle: 'Intitulé', requis: true, col: ColChamp.plein),
      const ChampDef(
          nom: 'periodicite',
          libelle: 'Périodicité',
          type: TypeChamp.select,
          requis: true,
          col: ColChamp.tiers,
          options: [OptionChamp('mensuelle', 'Mensuelle'), OptionChamp('annuelle', 'Annuelle')]),
      const ChampDef(nom: 'jour', libelle: 'Jour de l’échéance', type: TypeChamp.nombre, requis: true, col: ColChamp.tiers),
      ChampDef(nom: 'mois', libelle: 'Mois (annuelle)', type: TypeChamp.select, col: ColChamp.tiers, options: _moisOptions, condition: (controle: 'periodicite', quand: ['annuelle'])),
      const ChampDef(nom: 'part', libelle: 'Part réglée à cette échéance (%)', type: TypeChamp.nombre, col: ColChamp.tiers, aide: 'Vide si l’échéance règle l’obligation entière.'),
      const ChampDef(nom: 'declaration', libelle: 'Déclaration préalable'),
      const ChampDef(nom: 'note', libelle: 'Règle appliquée', type: TypeChamp.textarea, lignes: 2, col: ColChamp.plein),
    ];

Map<String, Object?> _valeursObligation(Fiche? o) => {
      'code': o?['code'] ?? '',
      'libelle': o?['libelle'] ?? '',
      'periodicite': o?['periodicite'] ?? 'annuelle',
      'jour': o?['jour'] != null ? '${o!['jour']}' : '10',
      'mois': o?['mois'] != null ? '${o!['mois']}' : '',
      'part': o?['part'] != null ? '${o!['part']}' : '',
      'declaration': o?['declaration'] ?? '',
      'note': o?['note'] ?? '',
    };

class _EtatComptabilite extends State<EcranComptabilite> {
  bool _amorce = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_amorce) return;
    _amorce = true;
    ConfigurationFiscalePoste.amorcer(ContexteEcran.of(context).magasin);
  }

  void _rafraichir() {
    if (mounted) setState(() {});
  }

  String Function(String) _impact(ConfigurationFiscalePoste cf, String code) => (dateIso) {
        final i = cfbEcheancesImpactees(cf.echeances.toutes, code, dateIso);
        return 'Sur l’exercice ${i.exercice} : ${nombre(i.payees)} échéance(s) payée(s) CONSERVÉE(S) (leur quittance ne bouge pas), '
            '${nombre(i.nonPayees)} échéance(s) non payée(s) RÉGÉNÉRÉE(S) à partir du ${_dateFr(dateIso)}. Le comptable en est informé.';
      };

  void _annoncer(BuildContext ctx, ConfigurationFiscalePoste cf, String verbe) {
    final e = cf.derniereRegeneration;
    ToastsSigh.afficher(ctx, 'Obligation $verbe.',
        type: TypeToast.succes,
        detail: e == null
            ? null
            : '${nombre(e.conservees)} échéance(s) payée(s) conservée(s), ${nombre(e.archivees)} non payée(s) régénérée(s), ${nombre(e.creees)} recréée(s) depuis la version en vigueur au ${_dateFr(e.dateEffet)}.');
  }

  /// `modifierObligationUI(o)` : les valeurs, puis la modale de portée.
  void _modifier(BuildContext ctx, ConfigurationFiscalePoste cf, Fiche o) {
    final f = ControleurFormulaire(_champsObligation(o, false), _valeursObligation(o));
    afficherModale<void>(ctx,
        titre: 'Modifier l’obligation ${o['code']}',
        sousTitre: '${o['libelle']}',
        taille: TailleModale.lg,
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          const NoteSigh('La modification est datée : la version actuelle reste en vigueur jusqu’à la veille de la date d’effet, et les échéances déjà payées ne bougent pas.',
              icone: LucideIcons.calendarClock),
          const SizedBox(height: 12),
          FormulaireSigh(controleur: f),
        ]),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  key: const Key('cfb:obligation:continuer'),
                  libelle: 'Continuer',
                  icone: LucideIcons.arrowRight,
                  onPressed: () {
                    final v = f.valider();
                    if (v == null) {
                      ToastsSigh.afficher(ctx, 'Le formulaire comporte des erreurs.', type: TypeToast.erreur);
                      return;
                    }
                    fermer();
                    cfbModalePortee(ctx,
                        cf: cf,
                        sousTitre: '${o['code']} : ${o['libelle']}',
                        explication: 'L’échéance change pour l’avenir : à partir de la date d’effet, les échéances non payées sont régénérées ; avant, rien ne bouge.',
                        minimum: o['dateEffet'],
                        impact: _impact(cf, '${o['code']}'),
                        appliquer: (dateEffet, motif) {
                          try {
                            final r = cf.modifierObligation(o, v, dateEffet: dateEffet, motif: motif);
                            if (!r.ok) return r.refus;
                          } on EcritureRefusee catch (e) {
                            return CfbRefus('FILEUL_LECTURE_SEULE', e.motif);
                          }
                          _annoncer(ctx, cf, 'modifiée');
                          _rafraichir();
                          return null;
                        });
                  }),
            ]);
  }

  /// `creerObligationUI()`.
  void _creer(BuildContext ctx, ConfigurationFiscalePoste cf) {
    final f = ControleurFormulaire(_champsObligation(null, true), _valeursObligation(null));
    afficherModale<void>(ctx,
        titre: 'Nouvelle obligation fiscale ou sociale',
        taille: TailleModale.lg,
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          const NoteSigh(
              'Une obligation nouvelle prend effet à une date et cite le texte qui l’institue (motif). Ses échéances de l’exercice sont engendrées à partir de la date d’effet, et elle devra être validée.',
              icone: LucideIcons.calendarPlus),
          const SizedBox(height: 12),
          FormulaireSigh(controleur: f),
        ]),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  key: const Key('cfb:obligation:continuer'),
                  libelle: 'Continuer',
                  icone: LucideIcons.arrowRight,
                  onPressed: () {
                    final v = f.valider();
                    if (v == null) {
                      ToastsSigh.afficher(ctx, 'Le formulaire comporte des erreurs.', type: TypeToast.erreur);
                      return;
                    }
                    fermer();
                    final code = '${v['code']}'.toUpperCase();
                    cfbModalePortee(ctx,
                        cf: cf,
                        sousTitre: '$code : ${v['libelle']}',
                        explication: 'L’obligation existe à partir de la date d’effet ; ses échéances antérieures ne sont pas créées.',
                        placeholderMotif: 'Texte de loi, note de la DGI, décision de la Direction…',
                        libelleAppliquer: 'Créer l’obligation',
                        appliquer: (dateEffet, motif) {
                          try {
                            final r = cf.creerObligation(v, dateEffet: dateEffet, motif: motif);
                            if (!r.ok) return r.refus;
                          } on EcritureRefusee catch (e) {
                            return CfbRefus('FILEUL_LECTURE_SEULE', e.motif);
                          }
                          _annoncer(ctx, cf, '$code créée');
                          _rafraichir();
                          return null;
                        });
                  }),
            ]);
  }

  /// `retirerObligationUI(o)` : droit `annuler` (DAF et administrateur) ; le moteur refait le contrôle (`RETRAIT_RESERVE`).
  void _retirer(BuildContext ctx, ConfigurationFiscalePoste cf, Fiche o) => cfbModalePortee(ctx,
      cf: cf,
      sousTitre: 'Retrait de ${o['code']} : ${o['libelle']}',
      explication:
          'L’obligation cesse à la veille de la date d’effet : ses échéances non payées à partir de cette date sont archivées, les payées restent. La dernière version va à l’historique, marquée retirée.',
      minimum: o['dateEffet'],
      impact: _impact(cf, '${o['code']}'),
      placeholderMotif: 'Texte qui supprime l’obligation, ou décision de la Direction',
      libelleAppliquer: 'Retirer l’obligation',
      appliquer: (dateEffet, motif) {
        try {
          final r = cf.retirerObligation(o, dateEffet: dateEffet, motif: motif);
          if (!r.ok) return r.refus;
        } on EcritureRefusee catch (e) {
          return CfbRefus('FILEUL_LECTURE_SEULE', e.motif);
        }
        _annoncer(ctx, cf, '${o['code']} retirée');
        _rafraichir();
        return null;
      });

  /// `modifierOrtbUI(ortb)`.
  void _modifierOrtb(BuildContext ctx, ConfigurationFiscalePoste cf, Fiche ortb) {
    Fiche red(String id) => ((ortb['redevances'] as List? ?? const []).whereType<Map>().where((x) => x['id'] == id).firstOrNull ?? const {}).cast<String, Object?>();
    final radio = red('radio'), tele = red('tele');
    final f = ControleurFormulaire([
      const ChampDef.section('Redevance Radio (tous les salariés)'),
      const ChampDef(nom: 'radioMontant', libelle: 'Montant annuel (FCFA)', type: TypeChamp.nombre, requis: true),
      ChampDef(nom: 'radioMois', libelle: 'Mois de prélèvement', type: TypeChamp.select, requis: true, options: _moisOptions),
      const ChampDef.section('Redevance Télé (au-delà du seuil de salaire brut)'),
      const ChampDef(nom: 'seuilTele', libelle: 'Seuil de salaire brut (FCFA)', type: TypeChamp.nombre, requis: true, aide: 'La télé est due STRICTEMENT au-dessus de ce seuil, en sus de la radio.'),
      const ChampDef(nom: 'teleMontant', libelle: 'Montant annuel (FCFA)', type: TypeChamp.nombre, requis: true),
      ChampDef(nom: 'teleMois', libelle: 'Mois de prélèvement', type: TypeChamp.select, requis: true, options: _moisOptions),
    ], {
      'radioMontant': '${radio['montant'] ?? ''}',
      'radioMois': '${radio['mois'] ?? ''}',
      'seuilTele': '${ortb['seuilTele'] ?? ''}',
      'teleMontant': '${tele['montant'] ?? ''}',
      'teleMois': '${tele['mois'] ?? ''}',
    });
    afficherModale<void>(ctx,
        titre: 'Modifier les paramètres ORTB',
        sousTitre: 'Deux redevances qui se cumulent',
        taille: TailleModale.lg,
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          const NoteSigh('Les paramètres sont lus à la date du bulletin : un bulletin déjà émis garde ses lignes ORTB, un seuil relevé en septembre ne touche pas le bulletin de juin.',
              icone: LucideIcons.radio),
          const SizedBox(height: 12),
          FormulaireSigh(controleur: f),
        ]),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  key: const Key('cfb:ortb:continuer'),
                  libelle: 'Continuer',
                  icone: LucideIcons.arrowRight,
                  onPressed: () {
                    final v = f.valider();
                    if (v == null) {
                      ToastsSigh.afficher(ctx, 'Le formulaire comporte des erreurs.', type: TypeToast.erreur);
                      return;
                    }
                    fermer();
                    cfbModalePortee(ctx,
                        cf: cf,
                        sousTitre: 'Paramètres ORTB',
                        explication:
                            'Les bulletins dont la période de paie commence à la date d’effet ou après lisent les nouveaux paramètres ; les bulletins antérieurs ne sont jamais recalculés.',
                        minimum: ortb['dateEffet'],
                        placeholderMotif: 'Décision de la Direction, texte de l’ORTB…',
                        appliquer: (dateEffet, motif) {
                          try {
                            final r = cf.modifierOrtb({
                              'seuilTele': v['seuilTele'],
                              'radio': {'montant': v['radioMontant'], 'mois': v['radioMois']},
                              'tele': {'montant': v['teleMontant'], 'mois': v['teleMois']},
                            }, dateEffet: dateEffet, motif: motif);
                            if (!r.ok) return r.refus;
                          } on EcritureRefusee catch (e) {
                            return CfbRefus('FILEUL_LECTURE_SEULE', e.motif);
                          }
                          ToastsSigh.afficher(ctx, 'Paramètres ORTB modifiés.', type: TypeToast.succes, detail: 'En vigueur à partir du ${_dateFr(dateEffet)} ; à revalider.');
                          _rafraichir();
                          return null;
                        });
                  }),
            ]);
  }

  /// `commandesObligation(o)` : Modifier (droit éditer), Retirer (droit annuler). ABSENTES sans droit ; « tenue par la mère » sur un fileul.
  Widget _commandes(BuildContext ctx, ContexteEcran c, ConfigurationFiscalePoste cf, Fiche o) {
    if (cf.fileul) return const Text('tenue par la mère', style: TextStyle(fontSize: 12, height: 16 / 12, color: JetonsShell.slate400));
    return Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.end, children: [
      if (c.droit.editer) BoutonIcone(key: Key('cfb:modifier:${o['code']}'), icone: LucideIcons.pencil, libelle: 'Modifier (version datée)', onPressed: () => _modifier(ctx, cf, o)),
      if (c.droit.annuler) BoutonIcone(key: Key('cfb:retirer:${o['code']}'), icone: LucideIcons.archive, libelle: 'Retirer (version datée)', onPressed: () => _retirer(ctx, cf, o)),
    ]);
  }

  Widget _bloc(BuildContext ctx, ContexteEcran c, ConfigurationFiscalePoste cf, String titre, String sousTitre, List<Fiche> lignes) => Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: JetonsShell.slate200)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(titre, style: const TextStyle(fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600, color: JetonsShell.slate800)),
        Padding(padding: const EdgeInsets.only(top: 2, bottom: 8), child: Text(sousTitre, style: const TextStyle(fontSize: 12, height: 16 / 12, color: JetonsShell.slate500))),
        for (final e in lignes)
          Container(
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: JetonsShell.slate100))),
              child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                _mono12(_libelleEcheance(e).replaceFirst(RegExp(r'^le '), ''), couleur: JetonsShell.navy700),
                const SizedBox(width: 8),
                Expanded(child: Text('${e['libelle']}${e['part'] != null ? ' (${e['part']} %)' : ''}', style: const TextStyle(fontSize: 12, height: 16 / 12, color: JetonsShell.slate600))),
                _commandes(ctx, c, cf, e),
              ])),
      ]));

  Widget _tableHistorique(ConfigurationFiscalePoste cf) {
    final rows = cf.historique.actives.toList()..sort((a, b) => '${b['remplaceeLe'] ?? ''}'.compareTo('${a['remplaceeLe'] ?? ''}'));
    String version(Fiche h) => h['type'] == 'parametres'
        ? 'Seuil télé ${money(h['seuilTele'], avecDevise: false)}, cumul ${money(h['cumulMaximum'], avecDevise: false)}'
        : '${_libelleEcheance(h)}${h['part'] != null && nombreOuZero(h['part']) < 100 ? ', ${h['part']} %' : ''}';
    return MiniTableauSigh(
        vide: 'Aucune version antérieure : les obligations sont celles du calendrier confirmé le 25/08/2026.',
        colonnes: [
          ColonneMini('Code', (h) => '${h['code']}', rendu: (h) => _mono12('${h['code']}')),
          ColonneMini('Version', version),
          ColonneMini('En vigueur du', (h) => h['dateEffet'] != null ? _dateFr(h['dateEffet']) : 'ouverture'),
          ColonneMini('Au', (h) => h['dateFin'] != null ? _dateFr(h['dateFin']) : '—'),
          ColonneMini('Remplacée le', (h) => '${h['remplaceeLe'] != null ? _dateHeureFr(h['remplaceeLe']) : '—'} par ${h['remplaceePar'] ?? '—'}'),
          ColonneMini('Motif', (h) => '${h['retiree'] == true ? 'Retirée ' : ''}${h['motifRemplacement'] ?? '—'}',
              rendu: (h) => Row(mainAxisSize: MainAxisSize.min, children: [
                    if (h['retiree'] == true) ...[const BadgeSigh('Retirée', ton: TonSigh.danger), const SizedBox(width: 4)],
                    Flexible(child: Text('${h['motifRemplacement'] ?? '—'}', style: const TextStyle(fontSize: 12, height: 16 / 12))),
                  ])),
        ],
        lignes: rows);
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final cf = ConfigurationFiscalePoste(c);
    return ListenableBuilder(
        listenable: _ecoute(c.magasin),
        builder: (context, _) {
          final cal = cf.obligationsALaDate();
          final mensuelles = [for (final e in cal) if (e['periodicite'] == 'mensuelle') e];
          final acomptes = [for (final e in cal) if (RegExp(r'^IS-\d$').hasMatch('${e['code']}')) e];
          final soldes = [for (final e in cal) if (e['code'] == 'IS-SOLDE' || e['code'] == 'ETATS-FIN') e];
          List<Fiche> famille(String f) => [for (final e in cal) if (e['famille'] == f) e];
          final joursMensuels = <int>{for (final e in mensuelles) nombreOuZero(e['jour']).toInt()};
          final titreMensuelles = 'Obligations mensuelles${joursMensuels.length == 1 ? ' : le ${joursMensuels.first} du mois suivant' : ''}';
          final ortb = cf.ortbALaDate();
          final p = PaiParametresOrtb.depuisFiche(ortb);
          final (noteOrtb, agentOrtb) = cfbTextesOrtb(p);
          final fileul = cf.fileul;
          final valider = cfbBoutonValider(context, cf, identite: false, libelle: 'les obligations');
          final ccibTranche = cfbCcibTotal ~/ 2;
          return cfaPile([
            cfbBandeauEtat(cf, identite: false, libelle: 'liste des obligations'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (!fileul && c.droit.editer) BoutonSigh(key: const Key('cfb:nouvelle-obligation'), libelle: 'Nouvelle obligation', icone: LucideIcons.plus, onPressed: () => _creer(context, cf)),
              if (valider != null) valider,
              BoutonSigh(libelle: 'Suivi des échéances', icone: LucideIcons.calendarClock, variante: VarianteBouton.secondaire, onPressed: () => c.aller('m12-echeances')),
            ]),
            cfaKpis(cfbKpisComptabilite(obligations: _calendrier(cal))),
            CarteSigh(
                titre: titreMensuelles,
                child: cfaPile([
                  cfbNote(
                      '${mensuelles.map((e) => e['code']).join(', ')} se paient chaque mois, pour le mois d’exercice précédent, au jour porté par chaque obligation. Une déclaration précède le paiement. Si le jour tombe un samedi ou un dimanche, le jour ouvrable qui suit immédiatement fait foi.'),
                  MiniTableauSigh(colonnes: [
                    ColonneMini('Code', (e) => '${e['code']}', rendu: (e) => _mono12('${e['code']}')),
                    ColonneMini('Obligation', (e) => '${e['libelle']}'),
                    ColonneMini('Échéance', _libelleEcheance),
                    ColonneMini('Déclaration préalable', (e) => cfaOuTiret(e['declaration'])),
                    ColonneMini('Version', (e) => e['dateEffet'] != null ? 'depuis le ${_dateFr(e['dateEffet'])}' : 'd’origine'),
                    ColonneMini('', (e) => '', droite: true, rendu: (e) => _commandes(context, c, cf, e)),
                  ], lignes: mensuelles),
                  _encart('Assiettes arrêtées par le CDCT §10.10 (lecture seule)',
                      '${cfbTexteAssiettes()} Ces taux ne se modifient pas ici : ils sont arrêtés par le cahier des charges ; les rendre datés est un chantier nommé.'),
                ], espace: 12)),
            CarteSigh(
                titre: 'Impôt sur les sociétés : quatre acomptes et une liquidation',
                child: cfaPile([
                  cfbNote(
                      'L’impôt se paie par anticipation : l’impôt de l’exercice précédent est divisé en quatre acomptes égaux, versés au cours de l’exercice courant. Exemple donné par le comptable : un impôt de 2 000 000 FCFA en 2025 donne quatre acomptes de 500 000 FCFA en 2026.',
                      icone: LucideIcons.landmark),
                  MiniTableauSigh(colonnes: [
                    ColonneMini('Acompte', (e) => '${e['libelle']}'),
                    ColonneMini('Échéance', _libelleEcheance),
                    ColonneMini('Part', (e) => '${e['part']} % de l’impôt de l’exercice précédent'),
                    ColonneMini('', (e) => '', droite: true, rendu: (e) => _commandes(context, c, cf, e)),
                  ], lignes: acomptes),
                  _encart('Le 30 avril de l’année suivante',
                      'Deux opérations, dans cet ordre : la liquidation du solde ajuste ce qui a été versé en acomptes (la clinique complète si l’impôt réel dépasse les acomptes, l’État rembourse dans le cas inverse), puis intervient le dépôt des états financiers de l’exercice clos.',
                      navy: true),
                  MiniTableauSigh(colonnes: [
                    ColonneMini('Code', (e) => '${e['code']}', rendu: (e) => _mono12('${e['code']}')),
                    ColonneMini('Obligation', (e) => '${e['libelle']}'),
                    ColonneMini('Échéance', _libelleEcheance),
                    ColonneMini('', (e) => '', droite: true, rendu: (e) => _commandes(context, c, cf, e)),
                  ], lignes: soldes),
                ], espace: 12)),
            CarteSigh(
                titre: 'Patente, CCIB et TVM : une fois par an',
                child: LayoutBuilder(builder: (ctx, k) {
                  final blocs = [
                    _bloc(context, c, cf, 'Patente', 'Une fois par an, avec possibilité de régler en deux tranches.', famille('PATENTE')),
                    _bloc(context, c, cf, 'CCIB', '${money(cfbCcibTotal)} par an, en deux tranches égales de ${money(ccibTranche)} (montant à confirmer par le cabinet comptable).', famille('CCIB')),
                    _bloc(context, c, cf, 'TVM', 'Taxe sur véhicules à moteur. Une fois par an, en une seule fois.', famille('TVM')),
                  ];
                  if (k.maxWidth < 768) return cfaPile(blocs, espace: 12);
                  return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    for (var i = 0; i < blocs.length; i++) ...[if (i > 0) const SizedBox(width: 12), Expanded(child: blocs[i])]
                  ]);
                })),
            CarteSigh(
                titre: 'Redevances ORTB : prélevées sur les salaires',
                actions: [
                  if (!fileul && c.droit.editer)
                    BoutonSigh(key: const Key('cfb:modifier-ortb'), libelle: 'Modifier les paramètres ORTB', icone: LucideIcons.pencil, taille: TailleBouton.sm, variante: VarianteBouton.secondaire, onPressed: () => _modifierOrtb(context, cf, ortb)),
                  BoutonSigh(libelle: 'Suivi nominatif', icone: LucideIcons.radio, taille: TailleBouton.sm, onPressed: () => c.aller('m11-ortb')),
                ],
                child: cfaPile([
                  cfbNote(noteOrtb, ton: 'warning', icone: LucideIcons.radio),
                  MiniTableauSigh(colonnes: [
                    ColonneMini('Redevance', (t) => '${t['libelle']}'),
                    ColonneMini('Catégorie', (t) => '${t['categorie']}', rendu: (t) => BadgeSigh('${t['categorie']}', ton: t['id'] == 'radio' ? TonSigh.info : TonSigh.navy)),
                    ColonneMini('Assiette', (t) => '${t['assiette']}'),
                    ColonneMini('Montant', (t) => money(t['montant'], avecDevise: false), droite: true),
                    ColonneMini('Mois de prélèvement', (t) => '${t['moisLabel']}'),
                  ], lignes: [
                    for (final r in p.redevances) {'id': r.id, 'libelle': r.libelle, 'categorie': r.categorie, 'assiette': r.assiette, 'montant': r.montant, 'moisLabel': r.moisLabel}
                  ]),
                  _encart('Ce que supporte un agent', agentOrtb, key: const Key('cfb:ortb:agent')),
                  cfbNote(
                      'Le prélèvement est annuel, non mensuel : chaque redevance n’apparaît que sur le bulletin de son mois. Les porter chaque mois majorerait les retenues de onze douzièmes. Les deux parts restent distinguées jusqu’au bulletin et à l’état des cotisations. Paramètres ${ortb['dateEffet'] != null ? 'en vigueur depuis le ${_dateFr(ortb['dateEffet'])}' : 'd’origine (précision de la Direction du 20/08/2026)'}.'),
                ], espace: 12)),
            CarteSigh(titre: 'Versions antérieures des obligations et des paramètres ORTB', child: _tableHistorique(cf)),
            CarteSigh(
                titre: 'Principes de tenue',
                child: DescListeSigh([
                  ('Report d’échéance', 'Une échéance tombant un samedi ou un dimanche est reportée au jour ouvrable suivant.'),
                  ('Déclaration préalable', '${nombre(cal.where((e) => e['declaration'] != null).length)} obligations exigent une déclaration avant paiement : elle est signalée à l’échéance.'),
                  ('Versions datées', 'Une obligation modifiée ou retirée garde sa version antérieure à l’historique ; les échéances payées ne bougent jamais.'),
                  ('Équilibre des écritures', 'RG-10 : aucune écriture ne se valide si le débit ne balance pas le crédit.'),
                  ('Continuité de l’exercice', 'Le logiciel ne se clôture pas en fin d’année : verrouiller une période empêche d’y saisir, pas d’y lire.'),
                  ('Valorisation des sorties', 'Paramétrable, prix de vente par défaut, conformément à l’annotation du 30/12/2024.'),
                  ('Journalisation', 'RG-12 : chaque paiement validé, chaque version et chaque validation porte son auteur et sa date.'),
                ])),
            cfaSource(
                'Précisions du comptable de la clinique (réunion du 19 août 2026), complétées des arbitrages de la Direction des 20 et 25 août 2026 ; validation et versions datées : décision de la Direction du 06/11/2026.'),
          ]);
        });
  }
}
