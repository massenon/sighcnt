import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m14/sauvegardes.dart' show enregistrerSauvegarde;
import 'mrb_commun.dart';
import 'mrb_source.dart';

/// `mere-journal-technique` : le journal technique du service de la mère (M-08). Lecture seule : le service écrit, la console montre.
/// Source : `GET /admin/journal` (au plus 500 lignes, du plus récent au plus ancien). Le compte « 24 h » est celui des lignes LUES : quand la
/// lecture est tronquée dans la fenêtre, l'écran le dit au lieu de présenter un minimum comme un total.
const int mrbLimiteJournal = 500;

class EcranJournalTechnique extends StatefulWidget with EcranMaquette {
  const EcranJournalTechnique({super.key});
  @override
  String get titre => 'Journal technique';
  @override
  String get description => 'Évènements du service de la mère : démarrages, erreurs, alertes, sauvegardes, liaison avec le relais.';
  @override
  String get regle =>
      'Ce journal est celui du service de la mère (table des évènements). Par construction il ne reçoit aucune donnée de santé. '
      'La console le lit sans pouvoir le modifier : le service écrit, l’administrateur consulte et exporte.';

  @override
  State<EcranJournalTechnique> createState() => _EtatJournal();
}

class _EtatJournal extends MrbEtatEcran<EcranJournalTechnique, List<MrbLigneJournal>> {
  @override
  Future<List<MrbLigneJournal>> charger(MrbSource s) => s.journal(limite: mrbLimiteJournal);

  Future<void> _exporter(BuildContext contexte, String nom, String csv) async {
    try {
      final chemin = await enregistrerSauvegarde(nom, csv);
      if (contexte.mounted) ToastsSigh.afficher(contexte, 'Journal exporté : $chemin', type: TypeToast.succes);
    } catch (e) {
      if (contexte.mounted) ToastsSigh.afficher(contexte, 'Export impossible : $e', type: TypeToast.erreur);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final lignes = donnees;
    final compte = lignes == null
        ? null
        : mrbCompterJournal(lignes, maintenantMs: c.aujourdhui.millisecondsSinceEpoch, limite: mrbLimiteJournal);
    final indice = compte == null ? null : (compte.tronque ? 'au moins : journal lu sur $mrbLimiteJournal lignes' : '24 dernières heures');
    String? n(int? v) => v == null ? null : '$v';
    final sources = <String>{for (final l in lignes ?? const <MrbLigneJournal>[]) l.source}.toList()..sort();
    final rows = <Ligne>[
      for (final l in lignes ?? const <MrbLigneJournal>[])
        {'quand': l.quand, 'niveau': l.niveau, 'source': l.source, 'message': l.message}
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      mrbBandeauPanne(panne),
      mrbGrilleKpi([
        mrbKpi('Évènements (24 h)', n(compte?.evenements), indice: indice, icone: LucideIcons.listChecks),
        mrbKpi('Alertes', n(compte?.alertes), indice: indice, ton: (compte?.alertes ?? 0) > 0 ? TonSigh.attention : TonSigh.succes, icone: LucideIcons.bell),
        mrbKpi('Erreurs', n(compte?.erreurs), indice: indice, ton: (compte?.erreurs ?? 0) > 0 ? TonSigh.danger : TonSigh.succes, icone: LucideIcons.circleAlert),
      ]),
      const SizedBox(height: 16),
      CarteSigh(
        titre: 'Évènements',
        sansRemplissage: true,
        child: MrbTableau(
          nomExport: 'journal-technique-mere',
          alExporter: (nom, csv) => _exporter(context, nom, csv),
          messageVide: enCours ? 'Lecture du journal en cours.' : (panne != null ? 'Journal non lu : le service ne répond pas.' : 'Aucun évènement enregistré.'),
          filtres: [
            FiltreTableau(nom: 'niveau', libelle: 'Niveau', options: const [
              OptionChamp('info', 'Information'),
              OptionChamp('alerte', 'Alerte'),
              OptionChamp('erreur', 'Erreur'),
            ]),
            FiltreTableau(nom: 'source', libelle: 'Source', options: [for (final s in sources) OptionChamp(s)]),
          ],
          colonnes: [
            ColonneTableau(
                cle: 'quand', libelle: 'Quand', sansCoupure: true, valeur: (l) => l['quand'], texte: (l) => mrbDateHeureMs(l['quand']! as int)),
            ColonneTableau(
                cle: 'niveau',
                libelle: 'Niveau',
                texte: (l) => switch (l['niveau']) { 'alerte' => 'Alerte', 'erreur' => 'Erreur', _ => 'Information' },
                rendu: (_, l) => BadgeSigh(
                    switch (l['niveau']) { 'alerte' => 'Alerte', 'erreur' => 'Erreur', _ => 'Information' },
                    ton: switch (l['niveau']) { 'alerte' => TonSigh.attention, 'erreur' => TonSigh.danger, _ => TonSigh.neutre })),
            const ColonneTableau(cle: 'source', libelle: 'Source'),
            const ColonneTableau(cle: 'message', libelle: 'Message'),
          ],
          lignes: rows,
        ),
      ),
    ]);
  }
}
