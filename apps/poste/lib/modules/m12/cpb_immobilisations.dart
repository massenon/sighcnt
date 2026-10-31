import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m14/crud_m14.dart';
import 'cpb_commun.dart';

/// `m12-immobilisations` — « Immobilisations & amortissements » : le registre, le plan d'amortissement SEMESTRIEL, les cessions et le report au bilan.
/// L'amortissement court de la DATE D'ACQUISITION à aujourd'hui, par pas de six mois ; le dernier semestre SOLDE le reliquat ; un bien CÉDÉ cesse de
/// s'amortir à sa date de sortie et quitte le bilan (sa fiche reste au registre). Les totaux du registre SONT les colonnes BRUT / AMORT. / NET de l'actif
/// immobilisé du bilan, rattachées par le COMPTE SYSCOHADA, jamais par la catégorie. Les règles sont dans le domaine (`cpb_gestion.dart`).
///
/// Écarts E772 / E773 : référence tirée des biens existants (« IM-011 », non « IM-001 » redonné par le compteur de page) et conservée à la modification
/// — corrigés dans la maquette d'abord.
/// Écart E778 : l'état « Cédé » SANS date de sortie sort le bien du bilan mais ne l'arrête pas d'amortir (le terme du calcul reste aujourd'hui) ; porté
/// fidèlement. Écart E779 : le plan de l'état imprimé s'ouvre sur « Durée — linéaire, pas semestriel » même pour un bien dont le plan est semestriel.
class EcranImmobilisations extends StatelessWidget with EcranMaquette {
  const EcranImmobilisations({super.key});

  @override
  String get titre => 'Immobilisations & amortissements';

  @override
  String get description => 'Registre des immobilisations, plan d’amortissement SEMESTRIEL, cessions et report au bilan.';

  @override
  String get regle =>
      'L’amortissement court de la date d’acquisition à aujourd’hui, par pas de six mois : l’annuité ne se constate qu’à la clôture et donnait le même amortissement à un bien acquis en février et à un bien acquis en novembre. Un bien cédé cesse de s’amortir à sa date de sortie et quitte le bilan — sa fiche, elle, reste au registre. Les totaux du registre SONT les colonnes BRUT / AMORT. / NET de l’actif immobilisé du bilan.';

  static const categories = [
    'Matériel médical',
    'Matériel de laboratoire',
    'Matériel technique',
    'Matériel de transport',
    'Mobilier médical',
    'Matériel informatique',
    'Installations'
  ];
  static const etats = ['En service', 'En maintenance', 'Hors service', 'Cédé'];
  static const motifs = ['Cession', 'Réforme', 'Destruction', 'Vol ou perte', 'Don'];

  static String _cessionLibre(Fiche i) => ('${i['dateCession'] ?? ''}').isEmpty
      ? 'Au patrimoine'
      : '${dateDe(i['dateCession'])} — ${(i['motifSortie'] ?? '') == '' ? 'sortie' : i['motifSortie']}${n(i['valeurCession']) != 0 ? ', cédé ${money(i['valeurCession'])}' : ''}';

  static void _imprimerFiche(BuildContext ctx, ContexteEcran c, Fiche im) {
    final plan = cpbPlanAmortissement(im, c.aujourdhui);
    afficherApercu(
        ctx,
        pieceM9(c,
            titre: 'Fiche d’immobilisation & plan d’amortissement',
            sousTitre: '${im['designation']} — ${im['reference']}',
            cartouche: [
              ('Bien', '${im['designation']}'),
              ('Référence', '${im['reference']}'),
              ('Catégorie', '${im['categorie']}'),
              ('Compte d’immobilisation', '${im['compte']}'),
              ('Date d’acquisition', dateDe(im['dateAcquisition'])),
              ('Valeur d’acquisition', money(im['valeurAcquisition'])),
              ('Durée', '${im['dureeAmortissement']} ans — linéaire, pas semestriel'),
              ('Dotation semestrielle', money(cpbDotationSemestre(im))),
              ('Semestres courus', '${cpbSemestresEcoules(im, c.aujourdhui)} / ${cpbSemestresTotal(im)}'),
              ('Amortissements cumulés', money(cpbAmortiCumule(im, c.aujourdhui))),
              ('VALEUR NETTE COMPTABLE', money(cpbVnc(im, c.aujourdhui))),
              ('Cession / sortie',
                  ('${im['dateCession'] ?? ''}').isEmpty ? 'Au patrimoine' : '${dateDe(im['dateCession'])} — ${(im['motifSortie'] ?? '') == '' ? 'sortie' : im['motifSortie']}'),
            ],
            blocs: [
              // LE TOTAL EST CALCULÉ depuis les lignes imprimées : la somme des dotations doit faire la valeur d'acquisition.
              BlocTableau(TableauEtat(libelleTotal: 'TOTAL DES DOTATIONS', colonnes: [
                ColonneEtat(libelle: 'Période', valeur: (l) => l['periode']),
                ColonneEtat(libelle: 'Dotation', droite: true, valeur: (l) => m(l['dotation']), somme: (l) => n(l['dotation'])),
                ColonneEtat(libelle: 'Amortissement cumulé', droite: true, valeur: (l) => m(l['cumul'])),
                ColonneEtat(libelle: 'Valeur nette comptable', droite: true, valeur: (l) => m(l['vnc'])),
                ColonneEtat(libelle: 'État', valeur: (l) => l['couru'] == true ? 'Couru' : 'À venir'),
              ], lignes: [
                for (final l in plan) {'periode': l.periode, 'dotation': l.dotation, 'cumul': l.cumul, 'vnc': l.vnc, 'couru': l.couru}
              ])),
              BlocTexte(
                  'Le total des dotations égale la valeur d’acquisition : le dernier semestre solde le reliquat d’arrondi. La valeur nette comptable au ${dateFR(c.aujourdhui)} est de ${money(cpbVnc(im, c.aujourdhui))} — c’est elle qui est reportée à l’actif immobilisé du bilan.',
                  italique: true),
            ],
            signatures: const [signComptable, signDafCompta]));
  }

  static void _imprimerReport(BuildContext ctx, ContexteEcran c, List<Fiche> rows) {
    final r = cpbReportBilan(rows, c.aujourdhui);
    afficherApercu(
        ctx,
        pieceM9(c,
            titre: 'Report des immobilisations à l’actif du bilan',
            sousTitre: 'Situation au ${dateFR(c.aujourdhui)}',
            cartouche: [
              ('Biens au patrimoine', nombre(r.auBilan)),
              ('Biens sortis', nombre(r.sorties)),
              ('Mode d’amortissement', 'Linéaire, pas semestriel'),
            ],
            tableaux: [
              TableauEtat(libelleTotal: 'TOTAL ACTIF IMMOBILISÉ', colonnes: [
                ColonneEtat(libelle: 'Réf.', valeur: (l) => l['ref']),
                ColonneEtat(libelle: 'Rubrique', valeur: (l) => l['libelle']),
                // Le total ne compte QUE les lignes de détail : additionner aussi les sous-totaux de famille doublerait la colonne.
                ColonneEtat(libelle: 'Brut', droite: true, valeur: (l) => m(l['brut']), somme: (l) => l['sousTotal'] == true ? 0 : n(l['brut'])),
                ColonneEtat(libelle: 'Amort. et dépréc.', droite: true, valeur: (l) => m(l['amort']), somme: (l) => l['sousTotal'] == true ? 0 : n(l['amort'])),
                ColonneEtat(libelle: 'Net', droite: true, valeur: (l) => m(l['net']), somme: (l) => l['sousTotal'] == true ? 0 : n(l['net'])),
              ], lignes: [for (final l in r.lignes) _ligneReport(l)])
            ],
            signatures: const [signComptable, signDafCompta]));
  }

  static Fiche _ligneReport(CpbLigneReport l) =>
      {'ref': l.ref, 'libelle': l.sousTotal ? l.libelle : '   ${l.libelle}', 'nb': l.nb, 'brut': l.brut, 'amort': l.amort, 'net': l.net, 'sousTotal': l.sousTotal};

  /// « Report au bilan » : ce tableau EST la rubrique « Immobilisations corporelles » (AI) de l'actif du bilan.
  static Widget _reportBilan(BuildContext ctx, ContexteEcran c, List<Fiche> rows) {
    final r = cpbReportBilan(rows, c.aujourdhui);
    final lignes = [for (final l in [...r.lignes, r.total]) _ligneReport(l)];
    return pile([
      const NoteSigh(
          'Ce tableau EST la rubrique « Immobilisations corporelles » (AI) de l’actif du bilan : ses trois colonnes sont celles de la liasse — BRUT, AMORT. et DÉPRÉC., NET. Le rattachement se fait par le compte SYSCOHADA porté par chaque bien, jamais par sa catégorie d’usage.',
          icone: LucideIcons.link),
      CarteSigh(
          titre: 'Report à l’actif immobilisé — rubrique par rubrique',
          sansRemplissage: true,
          child: MiniTableauSigh(colonnes: [
            ColonneMini('Réf.', (l) => '${l['ref']}'),
            ColonneMini('Rubrique du bilan', (l) => '${l['libelle']}'.trim()),
            ColonneMini('Biens', (l) => '${l['nb']}', droite: true),
            ColonneMini('Brut', (l) => m(l['brut']), droite: true),
            ColonneMini('Amort. et dépréc.', (l) => m(l['amort']), droite: true),
            ColonneMini('Net', (l) => m(l['net']), droite: true),
          ], lignes: lignes)),
      if (r.sorties > 0)
        NoteSigh(
            '${nombre(r.sorties)} bien(s) sorti(s) du patrimoine ne figurent PAS dans ce report : un bien cédé n’est plus à l’actif. Ils restent au registre, avec leur date et leur motif de sortie.',
            ton: TonSigh.attention,
            icone: LucideIcons.logOut),
      Wrap(spacing: 8, runSpacing: 8, children: [
        BoutonSigh(libelle: 'Ouvrir les états financiers', icone: LucideIcons.arrowRight, onPressed: () => c.aller('m12-etats-financiers')),
        BoutonSigh(
            libelle: 'Imprimer le report',
            icone: LucideIcons.printer,
            variante: VarianteBouton.secondaire,
            onPressed: () => _imprimerReport(ctx, c, rows)),
      ]),
    ], ecart: 12);
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('immobilisations');
    return ListenableBuilder(
      listenable: col,
      builder: (context, _) {
        final auj = c.aujourdhui;
        double amorti(Fiche i) => cpbAmortiCumule(i, auj);
        double vnc(Fiche i) => cpbVnc(i, auj);
        return CrudM14(
          collection: col,
          entite: 'immobilisation',
          entiteP: 'immobilisations',
          prefixeId: 'IMM',
          triInitial: 'valeurAcquisition',
          sensInitial: 'desc',
          taillePage: 15,
          valeursCreation: {'dateAcquisition': iso(auj), 'dureeAmortissement': '5', 'etat': 'En service', 'compte': '241000'},
          titreDetail: (i) => '${i['designation']}',
          sousTitreDetail: (i) => '${i['reference']}',
          colonnes: [
            ColonneTableau(
                cle: 'reference',
                libelle: 'N°',
                sansCoupure: true,
                texte: (i) => '${i['reference']}',
                rendu: (_, i) => Text('${i['reference']}', style: mono)),
            const ColonneTableau(cle: 'designation', libelle: 'Désignation'),
            ColonneTableau(cle: 'categorie', libelle: 'Catégorie', texte: (i) => '${i['categorie']}', rendu: (_, i) => BadgeSigh('${i['categorie']}', ton: TonSigh.navy)),
            ColonneTableau(
                cle: 'dateAcquisition', libelle: 'Date d’acquisition', sansCoupure: true, valeur: (i) => i['dateAcquisition'], texte: (i) => dateDe(i['dateAcquisition'])),
            ColonneTableau(
                cle: 'valeurAcquisition',
                libelle: 'Valeur d’acquisition',
                droite: true,
                valeur: (i) => n(i['valeurAcquisition']),
                texte: (i) => m(i['valeurAcquisition']),
                rendu: (_, i) => Text(m(i['valeurAcquisition']),
                    style: const TextStyle(color: JetonsShell.slate700, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()]))),
            ColonneTableau(
                cle: 'dureeAmortissement',
                libelle: 'Durée',
                droite: true,
                valeur: (i) => n(i['dureeAmortissement']),
                texte: (i) => '${i['dureeAmortissement']} ans (${cpbSemestresTotal(i)} sem.)'),
            // CESSION / SORTIE : un bien sorti reste au registre — c'est la pièce qu'on ressort au contrôle — mais il cesse de s'amortir et sort du bilan.
            ColonneTableau(
                cle: 'dateCession',
                libelle: 'Cession / sortie',
                sansCoupure: true,
                texte: (i) => ('${i['dateCession'] ?? ''}').isEmpty ? '' : dateDe(i['dateCession']),
                rendu: (_, i) => ('${i['dateCession'] ?? ''}').isEmpty
                    ? const Text('—', style: TextStyle(color: JetonsShell.slate300, fontSize: 14, height: 20 / 14))
                    : Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        Text(dateDe(i['dateCession']),
                            style: const TextStyle(color: JetonsShell.slate700, fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w500)),
                        Text('${(i['motifSortie'] ?? '') == '' ? 'Sortie' : i['motifSortie']}${n(i['valeurCession']) != 0 ? ' · ${m(i['valeurCession'])}' : ''}',
                            style: const TextStyle(color: JetonsShell.slate400, fontSize: 12, height: 16 / 12)),
                      ])),
            ColonneTableau(
                cle: 'cumul',
                libelle: 'Amort. cumulé',
                droite: true,
                valeur: amorti,
                texte: (i) => m(amorti(i)),
                rendu: (_, i) => Text(m(amorti(i)),
                    style: const TextStyle(color: JetonsShell.danger600, fontSize: 14, height: 20 / 14, fontFeatures: [FontFeature.tabularFigures()]))),
            ColonneTableau(
                cle: 'vnc',
                libelle: 'Valeur nette',
                droite: true,
                valeur: vnc,
                texte: (i) => m(vnc(i)),
                rendu: (_, i) => Text(m(vnc(i)),
                    style: const TextStyle(color: JetonsShell.navy900, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()]))),
            ColonneTableau(
                cle: 'etat',
                libelle: 'État',
                texte: (i) => '${i['etat'] ?? ''}',
                rendu: (_, i) => BadgeSigh('${i['etat'] ?? ''}', ton: i['etat'] == 'En service' ? TonSigh.succes : TonSigh.attention)),
          ],
          filtres: [
            FiltreTableau(nom: 'categorie', libelle: 'Catégorie', options: [for (final x in categories) OptionChamp(x)]),
            FiltreTableau(nom: 'etat', libelle: 'État', options: [for (final x in etats) OptionChamp(x)]),
          ],
          kpis: (rows) {
            // Ces trois totaux SONT les colonnes BRUT, AMORT. et NET de la rubrique AI du bilan ; les biens SORTIS en sont exclus.
            final t = cpbTotauxImmobilisations(rows, auj);
            return [
              KpiSigh(libelle: 'Immobilisations', valeur: nombre(rows.length), indice: '${nombre(t.sorties)} sortie(s) du patrimoine', icone: LucideIcons.building, ton: TonSigh.navy),
              KpiSigh(libelle: 'Valeur d’acquisition (BRUT)', valeur: money(t.brut), indice: 'Colonne BRUT du bilan — rubrique AI', icone: LucideIcons.banknote, ton: TonSigh.info),
              KpiSigh(libelle: 'Amortissements cumulés', valeur: money(t.amort), indice: 'Colonne AMORT. et DÉPRÉC. du bilan', icone: LucideIcons.trendingDown, ton: TonSigh.attention),
              KpiSigh(
                  libelle: 'Valeur nette comptable',
                  valeur: money(t.net),
                  indice: 'Colonne NET du bilan — reportée à l’actif immobilisé',
                  icone: LucideIcons.wallet,
                  ton: TonSigh.succes),
            ];
          },
          ongletsApres: (ctx) => [
            OngletDef(id: 'bilan', libelle: 'Report au bilan', construire: (ctx) => _reportBilan(ctx, c, col.actives)),
          ],
          champs: (ctx, record) => [
            const ChampDef(nom: 'designation', libelle: 'Désignation du bien', requis: true, col: ColChamp.plein),
            ChampDef(nom: 'categorie', libelle: 'Catégorie', type: TypeChamp.select, requis: true, options: [for (final x in categories) OptionChamp(x)]),
            const ChampDef(nom: 'dateAcquisition', libelle: 'Date d’acquisition', type: TypeChamp.date, requis: true),
            ChampDef(
                nom: 'valeurAcquisition',
                libelle: 'Valeur d’acquisition (FCFA)',
                type: TypeChamp.nombre,
                requis: true,
                valider: (v, _) => (num.tryParse('$v'.replaceAll(',', '.')) ?? 0) < 0 ? 'La valeur doit être supérieure ou égale à 0.' : null),
            ChampDef(
                nom: 'dureeAmortissement',
                libelle: 'Durée d’amortissement (années)',
                type: TypeChamp.nombre,
                requis: true,
                valider: (v, _) {
                  final d = num.tryParse('$v'.replaceAll(',', '.')) ?? 0;
                  return d < 1 ? 'La valeur doit être supérieure ou égale à 1.' : (d > 30 ? 'La valeur doit être inférieure ou égale à 30.' : null);
                }),
            ChampDef(nom: 'compte', libelle: 'Compte d’immobilisation', type: TypeChamp.select, options: [
              for (final p in cpbComptesImmobilisation()) OptionChamp(p.$1, '${p.$1} — ${p.$2}')
            ]),
            const ChampDef(nom: 'fournisseur', libelle: 'Fournisseur'),
            ChampDef(nom: 'etat', libelle: 'État', type: TypeChamp.select, options: [for (final x in etats) OptionChamp(x)]),
            const ChampDef.section('Cession ou sortie du patrimoine'),
            const ChampDef(
                nom: 'dateCession',
                libelle: 'Date de cession / sortie',
                type: TypeChamp.date,
                aide: 'Renseignée, elle ARRÊTE l’amortissement à cette date et sort le bien du bilan.'),
            ChampDef(
                nom: 'valeurCession',
                libelle: 'Prix de cession (FCFA)',
                type: TypeChamp.nombre,
                valider: (v, _) => (num.tryParse('$v'.replaceAll(',', '.')) ?? 0) < 0 ? 'La valeur doit être supérieure ou égale à 0.' : null),
            ChampDef(nom: 'motifSortie', libelle: 'Motif de la sortie', type: TypeChamp.select, options: [for (final x in motifs) OptionChamp(x)]),
          ],
          // La référence se lit sur les biens EXISTANTS (E772) et ne change pas à la modification (E773).
          transformer: (ctx, s, record) => {
            'designation': s['designation'],
            'categorie': s['categorie'],
            'dateAcquisition': s['dateAcquisition'],
            'valeurAcquisition': num.tryParse('${s['valeurAcquisition']}'.replaceAll(',', '.')) ?? 0,
            'dureeAmortissement': num.tryParse('${s['dureeAmortissement']}'.replaceAll(',', '.')) ?? 0,
            'compte': s['compte'] ?? '',
            'fournisseur': s['fournisseur'] ?? '',
            'etat': s['etat'] ?? '',
            'dateCession': s['dateCession'] ?? '',
            'valeurCession': ('${s['valeurCession'] ?? ''}').isEmpty ? null : num.tryParse('${s['valeurCession']}'.replaceAll(',', '.')),
            'motifSortie': s['motifSortie'] ?? '',
            if (record == null) 'reference': cpbReferenceSuivante('IM-', 3, col.toutes),
          },
          detail: (ctx, im) {
            final plan = cpbPlanAmortissement(im, auj);
            final cede = cpbCede(im);
            return pile([
              KpiGrilleSigh(colonnes: 3, kpis: [
                KpiSigh(libelle: 'Valeur d’acquisition', valeur: money(im['valeurAcquisition']), icone: LucideIcons.banknote, ton: TonSigh.navy),
                KpiSigh(libelle: 'Amortissements cumulés', valeur: money(amorti(im)), icone: LucideIcons.trendingDown, ton: TonSigh.attention),
                KpiSigh(libelle: 'Valeur nette comptable', valeur: money(vnc(im)), icone: LucideIcons.wallet, ton: TonSigh.succes),
              ]),
              DescListeSigh([
                ('Référence', '${im['reference']}'),
                ('Désignation', '${im['designation']}'),
                ('Catégorie', '${im['categorie']}'),
                ('Compte', '${im['compte']}'),
                ('Date d’acquisition', dateDe(im['dateAcquisition'])),
                ('Durée d’amortissement', '${im['dureeAmortissement']} ans, soit ${cpbSemestresTotal(im)} semestres'),
                ('Dotation semestrielle', money(cpbDotationSemestre(im))),
                ('Semestres courus', '${cpbSemestresEcoules(im, auj)} / ${cpbSemestresTotal(im)} (${cpbAnneesEcoulees(im, auj)} an(s) écoulé(s))'),
                ('Cession / sortie', _cessionLibre(im)),
                ('Fournisseur', '${im['fournisseur'] ?? ''}'),
                ('État', BadgeSigh('${im['etat'] ?? ''}', ton: im['etat'] == 'En service' ? TonSigh.succes : TonSigh.attention)),
              ]),
              if (cede)
                NoteSigh(
                    'Bien SORTI du patrimoine le ${dateDe(im['dateCession'])} : son amortissement est ARRÊTÉ à cette date et il ne figure plus au bilan. La fiche reste au registre — c’est elle qu’on ressort au contrôle.',
                    ton: TonSigh.attention,
                    icone: LucideIcons.logOut),
              CarteSigh(
                  titre: 'Plan d’amortissement — pas SEMESTRIEL',
                  child: pile([
                    MiniTableauSigh(colonnes: [
                      ColonneMini('Période', (l) => '${l['periode']}'),
                      ColonneMini('Base amortissable', (l) => m(l['base']), droite: true),
                      ColonneMini('Dotation', (l) => m(l['dotation']), droite: true),
                      ColonneMini('Amort. cumulé', (l) => m(l['cumul']), droite: true),
                      ColonneMini('Valeur nette', (l) => m(l['vnc']), droite: true),
                      ColonneMini('Couru', (l) => l['couru'] == true ? 'Couru' : 'À venir',
                          rendu: (l) => l['couru'] == true ? const BadgeSigh('Couru', ton: TonSigh.succes) : const BadgeSigh('À venir')),
                    ], lignes: [
                      for (final l in plan) {'periode': l.periode, 'base': l.base, 'dotation': l.dotation, 'cumul': l.cumul, 'vnc': l.vnc, 'couru': l.couru}
                    ]),
                    const NoteSigh(
                        'L’amortissement court de la date d’acquisition à aujourd’hui, par pas de six mois : l’annuité ne se constate qu’à la clôture, et elle donnait le même amortissement à un bien acquis en février et à un bien acquis en novembre.',
                        icone: LucideIcons.calendarRange),
                  ], ecart: 8)),
            ], ecart: 16);
          },
          etat: (ctx, im) => _imprimerFiche(ctx, c, im),
        );
      },
    );
  }
}
