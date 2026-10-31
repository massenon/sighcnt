import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'cfa_commun.dart';
import 'cfb_commun.dart';

const _mono = 'LiberationMono';

/// `cfg-fiscalite` — « Paramètres fiscaux (IFU / RCCM) » : l'identification fiscale UNIQUE de l'établissement (arbitrage du 31/08/2026), la numérotation des
/// documents, les obligations déclaratives et le CALENDRIER fiscal et social déroulé à la date du poste. Rien ne s'y saisit : les paramètres sont partagés
/// avec le module MECeF. Une échéance qui tombe un samedi ou un dimanche est reportée au jour ouvrable SUIVANT, jamais avancée.
class EcranFiscalite extends StatelessWidget with EcranMaquette {
  const EcranFiscalite({super.key});
  @override
  String get titre => 'Paramètres fiscaux (IFU / RCCM)';
  @override
  String get description => 'Identifiants fiscaux, numérotation des documents et paramètres de la facturation normalisée.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final echeances = cfbEcheances(c.aujourdhui);
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
    return cfaPile([
      cfbNote('Ces paramètres sont partagés avec le module MECeF. Toute modification s’applique immédiatement aux prochains documents émis.'),
      CarteSigh(
          titre: 'Identification fiscale de l’établissement',
          actions: [cfbLien(c, cfbEcranMecefConfig, 'Configuration MECeF')],
          child: DescListeSigh([
            ('Dénomination sociale', IdentiteClinique.nom),
            ('Forme juridique', CfaIdentite.forme),
            ('IFU', Text(IdentiteClinique.ifu, style: const TextStyle(fontFamily: _mono, fontSize: 16, height: 24 / 16, fontWeight: FontWeight.w600, color: JetonsShell.navy900))),
            ('RCCM', Text(IdentiteClinique.rccm, style: const TextStyle(fontFamily: _mono, fontSize: 16, height: 24 / 16, fontWeight: FontWeight.w600, color: JetonsShell.navy900))),
            ('Autorisation d’ouverture', IdentiteClinique.autorisation),
            ('Adresse fiscale', IdentiteClinique.bp),
            ('Devise', 'FCFA (XOF)'),
            ('Régime de TVA', 'Taux normal 18 %'),
          ])),
      CarteSigh(
          titre: 'Numérotation des documents',
          child: MiniTableauSigh(colonnes: [
            ColonneMini('Type de document', (x) => '${x['type']}'),
            ColonneMini('Préfixe', (x) => '${x['prefixe']}',
                rendu: (x) => Text('${x['prefixe']}', style: const TextStyle(fontFamily: _mono, fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w600, color: JetonsShell.slate900))),
            ColonneMini('Format', (x) => '${x['format']}'),
            ColonneMini('Séquence', (x) => '${x['sequence']}'),
          ], lignes: [
            for (final n in cfbNumerotation) {'type': n.$1, 'prefixe': n.$2, 'format': n.$3, 'sequence': n.$4}
          ])),
      CarteSigh(
          titre: 'Obligations déclaratives',
          child: MiniTableauSigh(colonnes: [
            ColonneMini('Déclaration', (x) => '${x['d']}'),
            ColonneMini('Périodicité', (x) => '${x['p']}'),
            ColonneMini('Échéance', (x) => '${x['e']}'),
            ColonneMini('Écran producteur', (x) => 'Éditer',
                rendu: (x) => BoutonSigh(libelle: 'Éditer', variante: VarianteBouton.secondaire, taille: TailleBouton.sm, onPressed: () => c.aller('${x['ecran']}'))),
          ], lignes: [
            for (final o in cfbObligationsDeclaratives) {'d': o.$1, 'p': o.$2, 'e': o.$3, 'ecran': o.$4}
          ])),
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
          ColonneTableau(
              cle: 'code',
              libelle: 'Code',
              sansCoupure: true,
              rendu: (_, e) => Text('${e['code']}', style: const TextStyle(fontFamily: _mono, fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w600, color: JetonsShell.slate900))),
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
                    if (e['reporte'] == true) const Text('reportée — jour ouvrable', style: TextStyle(fontSize: 10, height: 14 / 10, color: JetonsShell.warning600)),
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
          ColonneTableau(
              cle: 'note',
              libelle: 'Règle appliquée',
              rendu: (_, e) => Text('${e['note']}', style: const TextStyle(fontSize: 12, height: 16 / 12, color: JetonsShell.slate500))),
        ],
      ),
      cfbNote(
          'Impôt sur les sociétés. L’impôt de l’exercice se paie par anticipation : l’impôt de l’année précédente est divisé en quatre acomptes, versés les 10 mars, 10 juin, 10 septembre et 10 décembre. Le 30 avril de l’année suivante, la liquidation du solde ajuste à la hausse ou à la baisse, en même temps que le dépôt des états financiers.',
          icone: LucideIcons.landmark),
      cfaSource('${cfbCalendrierFiscal.first.source} — le calendrier de la CCIB et des acomptes d’impôt sur les sociétés a été confirmé par la Direction le 25/08/2026 : déclaration prévisionnelle de fin de mois, puis deux tranches de 50 % aux 10 mars et 10 juin pour la CCIB ; quatre acomptes aux 10 mars, 10 juin, 10 septembre et 10 décembre pour l’impôt sur les sociétés, liquidation du solde et dépôt des états financiers au 30 avril de l’année suivante.'),
    ]);
  }
}

// ---------------------------------------------------------------------------------------------------------------------------------------------

Widget _encart(String titre, String texte, {bool navy = false}) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
        color: navy ? JetonsShell.navy50 : JetonsShell.slate50, borderRadius: BorderRadius.circular(8), border: Border.all(color: navy ? JetonsShell.navy200 : JetonsShell.slate200)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(titre.toUpperCase(),
          style: TextStyle(fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w600, letterSpacing: 0.6, color: navy ? JetonsShell.navy700 : JetonsShell.slate500)),
      const SizedBox(height: 4),
      Text(texte, style: const TextStyle(fontSize: 14, height: 20 / 14, color: JetonsShell.slate700)),
    ]));

Widget _bloc(String titre, String sousTitre, List<(String, String)> lignes) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: JetonsShell.slate200)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(titre, style: const TextStyle(fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600, color: JetonsShell.slate800)),
      Padding(
          padding: const EdgeInsets.only(top: 2, bottom: 8),
          child: Text(sousTitre, style: const TextStyle(fontSize: 12, height: 16 / 12, color: JetonsShell.slate500))),
      for (final l in lignes)
        Container(
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: JetonsShell.slate100))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
              Text(l.$1, style: const TextStyle(fontFamily: _mono, fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w600, color: JetonsShell.navy700)),
              const SizedBox(width: 8),
              Flexible(child: Text(l.$2, style: const TextStyle(fontSize: 12, height: 16 / 12, color: JetonsShell.slate600))),
            ])),
    ]));

Widget _codeMono(Object? t) => Text('$t', style: const TextStyle(fontFamily: _mono, fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w600, color: JetonsShell.slate900));

/// `cfg-comptabilite` — « Paramètres comptables & obligations » : la RÉFÉRENCE documentaire des obligations fiscales et sociales (périodicités, tranches,
/// déclarations préalables, redevances). Il ne calcule ni ne paie : le suivi des paiements est à `m12-echeances`. Les deux écrans ne se fusionnent pas.
class EcranComptabilite extends StatelessWidget with EcranMaquette {
  const EcranComptabilite({super.key});
  @override
  String get titre => 'Paramètres comptables & obligations';
  @override
  String get description => 'Obligations fiscales et sociales de la clinique : périodicités, tranches, déclarations préalables et redevances.';
  @override
  String get regle =>
      'Cet écran est la référence documentaire des obligations. Il ne calcule ni ne paie — le suivi des paiements et leur validation se tiennent à l’écran Échéances fiscales & paiements. Toute échéance tombant un week-end est reportée au jour ouvrable suivant.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final mensuelles = [for (final e in cfbCalendrierFiscal) if (e.periodicite == 'mensuelle') e];
    final (noteOrtb, agentOrtb) = cfbTextesOrtb();
    final ccibTranche = cfbCcibTotal ~/ 2;
    return cfaPile([
      cfaKpis(cfbKpisComptabilite()),
      CarteSigh(
          titre: 'Obligations mensuelles — le 10 du mois suivant',
          child: cfaPile([
            cfbNote(
                'ITS, AIB, VPS et CNSS se paient le 10 de chaque mois, pour le mois d’exercice précédent. Une déclaration précède le paiement. Si le 10 tombe un samedi ou un dimanche, le jour ouvrable qui suit immédiatement fait foi.'),
            MiniTableauSigh(colonnes: [
              ColonneMini('Code', (e) => '${e['code']}', rendu: (e) => _codeMono(e['code'])),
              ColonneMini('Obligation', (e) => '${e['libelle']}'),
              ColonneMini('Échéance', (e) => 'le 10 du mois suivant'),
              ColonneMini('Déclaration préalable', (e) => cfaOuTiret(e['declaration'])),
            ], lignes: [
              for (final e in mensuelles) {'code': e.code, 'libelle': e.libelle, 'declaration': e.declaration}
            ]),
            _encart('Assiettes', cfbTexteAssiettes()),
          ], espace: 12)),
      CarteSigh(
          titre: 'Impôt sur les sociétés — quatre acomptes et une liquidation',
          child: cfaPile([
            cfbNote(
                'L’impôt se paie par anticipation : l’impôt de l’exercice précédent est divisé en quatre acomptes égaux, versés au cours de l’exercice courant. Exemple donné par le comptable — un impôt de 2 000 000 FCFA en 2025 donne quatre acomptes de 500 000 FCFA en 2026.',
                icone: LucideIcons.landmark),
            MiniTableauSigh(colonnes: [
              ColonneMini('Acompte', (e) => '${e['libelle']}'),
              ColonneMini('Échéance', (e) => '${e['echeance']}'),
              ColonneMini('Part', (e) => '${e['part']}'),
            ], lignes: [
              for (final e in cfbAcomptesIs()) {'libelle': e.libelle, 'echeance': cfbEcheanceAcompte(e), 'part': '${e.part} % de l’impôt de l’exercice précédent'}
            ]),
            _encart('Le 30 avril de l’année suivante',
                'Deux opérations, dans cet ordre : la liquidation du solde ajuste ce qui a été versé en acomptes — la clinique complète si l’impôt réel dépasse les acomptes, l’État rembourse dans le cas inverse — puis intervient le dépôt des états financiers de l’exercice clos.',
                navy: true),
          ], espace: 12)),
      CarteSigh(
          titre: 'Patente, CCIB et TVM — une fois par an',
          child: LayoutBuilder(builder: (ctx, k) {
            final blocs = [
              _bloc('Patente', 'Une fois par an, avec possibilité de régler en deux tranches.',
                  const [('31 janvier', 'Date limite de la déclaration prévisionnelle'), ('10 février', '1er acompte — 50 %'), ('30 avril', 'Solde — 50 %')]),
              _bloc('CCIB', '${money(cfbCcibTotal)} par an, en deux tranches égales de ${money(ccibTranche)}.',
                  const [('Fin de mois', 'Déclaration prévisionnelle, avant le 1er acompte'), ('10 mars', '1re tranche — 50 %'), ('10 juin', '2e tranche — 50 %')]),
              _bloc('TVM', 'Taxe sur véhicules à moteur. Une fois par an, en une seule fois.', const [('30 avril', 'Paiement, au plus tard')]),
            ];
            if (k.maxWidth < 768) return cfaPile(blocs, espace: 12);
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (var i = 0; i < blocs.length; i++) ...[if (i > 0) const SizedBox(width: 12), Expanded(child: blocs[i])]
            ]);
          })),
      CarteSigh(
          titre: 'Redevances ORTB — prélevées sur les salaires',
          actions: [
            BoutonSigh(libelle: 'Suivi nominatif', icone: LucideIcons.radio, taille: TailleBouton.sm, onPressed: () => c.aller('m11-ortb')),
          ],
          child: cfaPile([
            cfbNote(noteOrtb, ton: 'warning', icone: LucideIcons.radio),
            MiniTableauSigh(colonnes: [
              ColonneMini('Redevance', (t) => '${t['libelle']}'),
              ColonneMini('Catégorie', (t) => '${t['categorie']}', rendu: (t) => BadgeSigh('${t['categorie']}', ton: t['id'] == 'radio' ? TonSigh.info : TonSigh.navy)),
              ColonneMini('Assiette', (t) => '${t['assiette']}'),
              ColonneMini('Montant', (t) => money(t['montant'], avecDevise: false), droite: true),
              ColonneMini('Mois de prélèvement', (t) => '${t['mois']}'),
            ], lignes: [
              for (final r in paiRedevances) {'id': r.id, 'libelle': r.libelle, 'categorie': r.categorie, 'assiette': r.assiette, 'montant': r.montant, 'mois': r.moisLabel}
            ]),
            _encart('Ce que supporte un agent', agentOrtb),
            cfbNote(
                'Le prélèvement est annuel, non mensuel : chaque redevance n’apparaît que sur le bulletin de son mois. Les porter chaque mois majorerait les retenues de onze douzièmes. Les deux parts restent distinguées jusqu’au bulletin et à l’état des cotisations.'),
          ], espace: 12)),
      CarteSigh(
          titre: 'Principes de tenue',
          child: const DescListeSigh([
            ('Report d’échéance', 'Une échéance tombant un samedi ou un dimanche est reportée au jour ouvrable suivant.'),
            ('Déclaration préalable', 'Six obligations exigent une déclaration avant paiement — elle est signalée à l’échéance.'),
            ('Équilibre des écritures', 'RG-10 — aucune écriture ne se valide si le débit ne balance pas le crédit.'),
            ('Continuité de l’exercice', 'Le logiciel ne se clôture pas en fin d’année : verrouiller une période empêche d’y saisir, pas d’y lire.'),
            ('Valorisation des sorties', 'Paramétrable — prix de vente par défaut, conformément à l’annotation du 30/12/2024.'),
            ('Journalisation', 'RG-12 — chaque paiement validé porte son auteur, sa date et son montant.'),
          ])),
      cfaSource('Précisions du comptable de la clinique — réunion du 19 août 2026, complétées des arbitrages de la Direction du 20 août 2026.'),
    ]);
  }
}
