import 'package:flutter/material.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'tba_commun.dart';

/// `dash-admin-agent` — « Tableau de bord — Agent administratif » : l'agent administratif tient les courriers et les échéances de l'établissement ;
/// les courriers en attente de traitement priment. Tous les indicateurs sont COMPTÉS depuis les collections (un indicateur écrit en dur affiche la
/// même valeur quoi qu'il se passe — le badge « 4 » de la vague 36).
class EcranDashAgentAdmin extends StatelessWidget with EcranMaquette {
  const EcranDashAgentAdmin({super.key});

  @override
  String get titre => 'Tableau de bord — Agent administratif';

  @override
  String get description =>
      'Courriers, réunions, événements, notes de service et gestion documentaire.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return ListenableBuilder(
      listenable: tbaEcoute(c, ['courriers', 'reunions', 'documents']),
      builder: (context, _) {
        final d = tbaAgentAdmin(
            courriers: tbaActives(c, 'courriers'),
            reunions: tbaActives(c, 'reunions'),
            documents: tbaActives(c, 'documents'),
            auj: c.aujourdhui);
        return TbaDash(
          premier: d.premier,
          rapides: [
            tbaAccesRapides(c, const [
              ('m13-courriers', 'mail', 'Courriers', 'Départ et arrivée'),
              ('m13-reunions', 'users', 'Réunions', 'Convocations et comptes rendus'),
              ('m13-notes-service', 'file-text', 'Notes de service', 'Versions en vigueur'),
              ('ged-bibliotheque', 'folder-open', 'Gestion documentaire', 'Bibliothèque et archivage'),
            ]),
          ],
          kpis: d.kpis,
          sections: [
            tbaCarte(
                'Notes de service en vigueur',
                tbaMiniTableau([
                  ColonneMini('Référence', (n) => '${n['reference']}', rendu: (n) => tbaMono(n['reference'])),
                  ColonneMini('Objet', (n) => '${n['objet']}'),
                  ColonneMini('Signature', (n) => tbaDate(n['dateSignature'])),
                  ColonneMini('Statut', (n) => '', rendu: (n) => BadgeSigh('${n['statut']}', ton: TonSigh.succes)),
                ], [
                  for (final n in d.notes) {'reference': n.reference, 'objet': n.objet, 'dateSignature': n.dateSignature, 'statut': n.statut}
                ]),
                sansRemplissage: true),
          ],
        );
      },
    );
  }
}
