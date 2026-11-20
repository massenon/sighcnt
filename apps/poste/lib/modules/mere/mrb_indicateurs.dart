import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'mrb_commun.dart';
import 'mrb_source.dart';

/// `mere-indicateurs` : ce que la mère publie au relais pour la supervision à distance (M-14). Des compteurs, jamais un nom de patient.
///
/// La liste des champs est FERMÉE et vient du moteur (`Pont.demarrer`, `POST /mere/indicateurs`) : `patients_actifs`, `seq_max`, `retard_replication`.
/// Le service ne conserve pas le dernier envoi : l'aperçu est recalculé à l'instant avec les mêmes lectures (fiches patients actives, rang du journal,
/// retard de réplication) et vérifié par `mrbVerifierIndicateurs`. La fréquence d'envoi n'est pas publiée par le service : « non disponible » (E1360).
class _Publication {
  const _Publication(this.sante, this.valeurs);
  final MrbSante sante;

  /// Les trois valeurs telles que l'envoi les calculerait ; `null` : la lecture a échoué, la valeur n'est pas inventée.
  final Map<String, num?> valeurs;
}

class EcranIndicateursPublies extends StatefulWidget with EcranMaquette {
  const EcranIndicateursPublies({super.key});
  @override
  String get titre => 'Indicateurs publiés';
  @override
  String get description => 'Ce que la mère publie au relais pour la supervision à distance : des compteurs, jamais un nom de patient.';
  @override
  String get regle => 'Sert au superadmin en ligne : « la mère est-elle vivante, à jour, sauvegardée ? ». Pas à lire un dossier.';

  @override
  State<EcranIndicateursPublies> createState() => _EtatIndicateurs();
}

class _EtatIndicateurs extends MrbEtatEcran<EcranIndicateursPublies, _Publication> {
  @override
  Future<_Publication> charger(MrbSource s) async {
    final sante = await s.supervision();
    final etat = await s.etat();
    int? patients;
    try {
      patients = await s.patientsActifs();
    } catch (_) {
      patients = null;
    }
    return _Publication(sante, {
      'patients_actifs': patients,
      'seq_max': etat.seqMax,
      'retard_replication': etat.retardRelais,
    });
  }

  @override
  Widget build(BuildContext context) {
    final d = donnees;
    final lues = d == null ? <String, Object?>{} : {for (final e in d.valeurs.entries) if (e.value != null) e.key: e.value};
    final verdict = d == null ? null : mrbVerifierIndicateurs(lues);
    final relais = d?.sante.controle('Relais en ligne');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      mrbBandeauPanne(panne),
      if (relais != null && relais.etat == 'inconnu')
        Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: NoteSigh('Rien ne prouve que ces indicateurs partent : ${relais.detail}', ton: TonSigh.attention, icone: LucideIcons.triangleAlert)),
      mrbGrilleKpi([
        mrbKpi('Fréquence', null, indice: 'Le service de la mère ne publie pas sa fréquence d’envoi.', icone: LucideIcons.timer),
        mrbKpi('Champs publiés', '${mrbChampsPublies.length}', indice: mrbChampsPublies.join(', '), icone: LucideIcons.listChecks),
        mrbKpi('Données de santé', verdict == null ? null : (verdict.sansDonneeDeSante ? 'Aucune' : 'À vérifier'),
            indice: verdict == null
                ? null
                : (verdict.sansDonneeDeSante
                    ? 'Champs en liste fermée, valeurs numériques seulement'
                    : 'Hors liste : ${verdict.horsListe.join(', ')} ; non numériques : ${verdict.nonNumeriques.join(', ')}'),
            ton: verdict == null ? TonSigh.neutre : (verdict.sansDonneeDeSante ? TonSigh.succes : TonSigh.danger),
            icone: LucideIcons.shieldCheck),
      ]),
      const SizedBox(height: 16),
      CarteSigh(
        titre: 'Dernier envoi (aperçu exact)',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: JetonsShell.slate50, borderRadius: BorderRadius.circular(8), border: Border.all(color: JetonsShell.slate200)),
            child: SelectableText(
              key: const Key('mrb:apercu-indicateurs'),
              [
                '{ "indicateurs": {',
                for (final (i, k) in mrbChampsPublies.indexed)
                  '    "$k": ${d == null || d.valeurs[k] == null ? mrbNonDisponible : d.valeurs[k]}${i < mrbChampsPublies.length - 1 ? ',' : ''}',
                '} }',
              ].join('\n'),
              style: const TextStyle(fontFamily: 'LiberationMono', fontSize: 13, height: 20 / 13),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
              'Calculé à l’instant avec les mêmes lectures que l’envoi (fiches patients actives, rang du journal, retard de réplication). Le service ne conserve pas '
              'le dernier envoi. Ces compteurs partent EN CLAIR vers le relais ; tout le reste de ce qui lui est déposé est chiffré.',
              style: TextStyle(fontSize: 12, color: JetonsShell.slate500)),
        ]),
      ),
    ]);
  }
}
