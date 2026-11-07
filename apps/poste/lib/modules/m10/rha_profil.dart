import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m9/commun.dart' show ecoute;
import 'rha_fiche_employe.dart';

/// `m10-employe-profil` — vue consolidée d'un agent : informations, planning, primes applicables et historique. Un sélecteur à recherche (nom, matricule,
/// poste) désigne l'agent ; le premier par matricule est ouvert d'office ; la fiche est celle du tiroir de `m10-personnel` (`ficheEmploye`).
class EcranProfilEmploye extends StatefulWidget with EcranMaquette {
  const EcranProfilEmploye({super.key});
  @override
  String get titre => 'Fiche employé';
  @override
  String get description => 'Vue consolidée d’un agent : informations, planning, primes applicables et historique.';

  @override
  State<EcranProfilEmploye> createState() => _EcranProfilEmployeState();
}

class _EcranProfilEmployeState extends State<EcranProfilEmploye> {
  ControleurFormulaire? _ctl;

  @override
  void dispose() {
    _ctl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return ListenableBuilder(
        listenable: ecoute(c, ['personnel', 'planning', 'presences', 'conges', 'evaluations', 'assurancesPersonnel', 'grillePrimes']),
        builder: (context, _) {
          final agents = trierPar(c.magasin.collection('personnel').actives, (e) => e['matricule']);
          if (_ctl == null) {
            _ctl = ControleurFormulaire([
              ChampDef(
                  nom: 'agent',
                  libelle: 'Agent',
                  type: TypeChamp.select,
                  recherche: true,
                  options: [for (final e in agents) OptionChamp('${e['id']}', '${e['nomComplet']}')])
            ], {'agent': agents.isEmpty ? '' : '${agents.first['id']}'});
            _ctl!.addListener(() => setState(() {}));
          }
          Fiche? courant;
          for (final e in agents) {
            if (e['id'] == _ctl!['agent']) courant = e;
          }
          courant ??= agents.isEmpty ? null : agents.first;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            CarteSigh(
                child: Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.end, children: [
              ConstrainedBox(constraints: const BoxConstraints(maxWidth: 512, minWidth: 280), child: FormulaireSigh(controleur: _ctl!)),
              BoutonSigh(libelle: 'Retour à la liste', icone: LucideIcons.arrowLeft, variante: VarianteBouton.secondaire, onPressed: () => c.aller('m10-personnel')),
            ])),
            const SizedBox(height: 16),
            CarteSigh(
                child: courant == null
                    ? const VideSigh('Aucun agent enregistré.', icone: LucideIcons.users)
                    : FicheEmploye(key: ValueKey(courant['id']), agent: courant, c: c, ctx: context)),
          ]);
        });
  }
}
