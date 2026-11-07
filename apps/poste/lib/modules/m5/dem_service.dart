import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'dem_commun.dart';

/// `ecranDemandesService(...)` : une VUE du registre des demandes, jamais une seconde collection — la demande n'existe qu'une fois, c'est le
/// SERVICE DEMANDEUR qui la classe ici. Le RBAC métier continue de décider qui lit les résultats.
class EcranDemandesService extends StatelessWidget with EcranMaquette {
  const EcranDemandesService._(this._id, this.titre, this.description,
      this._correspond, this._complement,
      {super.key});

  /// `m5-demandes-maternite`.
  const EcranDemandesService.maternite({Key? key})
      : this._('m5-demandes-maternite', 'Demandes — maternité',
            'Les demandes d’analyses prescrites par la maternité : CPN, bilans d’admission, suites de couches.',
            demServiceMaternite,
            'La sage-femme y suit ses bilans ; le RBAC métier continue de décider qui lit les résultats.',
            key: key);

  /// `m5-demandes-hospitalisation`.
  const EcranDemandesService.hospitalisation({Key? key})
      : this._('m5-demandes-hospitalisation', 'Demandes — hospitalisation',
            'Les demandes d’analyses des patients hospitalisés ou mis en observation.',
            demServiceHospitalisation,
            'Le service d’hospitalisation y voit où en sont les bilans de ses lits, sans ouvrir le registre entier.',
            key: key);

  final String _id;
  @override
  final String titre;
  @override
  final String description;
  final bool Function(Fiche) _correspond;
  final String _complement;

  @override
  String get regle =>
      'Une VUE du registre des demandes, pas une seconde collection : la demande n’existe qu’une fois, c’est le service demandeur qui la classe ici. $_complement';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('demandesAnalyses');
    return ListenableBuilder(
      listenable: col,
      builder: (context, _) {
        final lignes = col.actives.where(_correspond).toList();
        final k = demKpisService(lignes);
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              KpiGrilleSigh(kpis: [
                KpiSigh(
                    libelle: 'Demandes du service',
                    valeur: nombre(k.demandes),
                    icone: LucideIcons.clipboardList),
                KpiSigh(
                    libelle: 'En attente de règlement',
                    valeur: nombre(k.attenteReglement),
                    icone: LucideIcons.wallet,
                    ton: k.attenteReglement > 0
                        ? TonSigh.attention
                        : TonSigh.neutre),
                KpiSigh(
                    libelle: 'À prélever / transmettre',
                    valeur: nombre(k.aPreleverTransmettre),
                    icone: LucideIcons.syringe,
                    ton: k.aPreleverTransmettre > 0
                        ? TonSigh.info
                        : TonSigh.neutre),
                KpiSigh(
                    libelle: 'Résultats rendus',
                    valeur: nombre(k.rendues),
                    icone: LucideIcons.fileCheck2,
                    ton: TonSigh.succes),
              ]),
              const SizedBox(height: 16),
              TableauSigh(
                titre: titre,
                lignes: lignes,
                colonnes: colonnesDemande(),
                nomExport: _id,
                taillePage: 12,
                triInitial: 'dateHeure',
                sensInitial: 'desc',
                messageVide: 'Aucune demande de ce service.',
                alClicLigne: (r) => afficherTiroir<void>(context,
                    titre: '${r['analyse'] ?? ''}',
                    sousTitre:
                        '${r['patient'] ?? ''} — ${vrai(r['codeAnalyse']) ? r['codeAnalyse'] : r['reference']}',
                    largeurMax: 672,
                    corps: detailDemande(r)),
              ),
            ]);
      },
    );
  }
}
