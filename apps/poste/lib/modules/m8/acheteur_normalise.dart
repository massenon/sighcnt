import 'package:flutter/material.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/normalisation_mecef.dart';
import '../../kit/kit.dart';

/// LA FENÊTRE « FACTURE NORMALISÉE » (E2299), une fabrique pour les trois portes d'encaissement (émission, registre des paiements, file de caisse).
///
/// TOUTE VENTE EST NORMALISÉE à la clinique (Direction, 07/11/2026) : il n'y a pas de « facture simple » à choisir. La fenêtre ne sert qu'à saisir
/// l'IFU et le nom de l'acheteur et le taux d'AIB. L'IFU est facultatif pour un particulier (13 chiffres quand il est renseigné) ; un IFU exige
/// un nom. Le contrôle est celui du domaine (`validerAcheteurMecef`), refait AVANT toute écriture : un refus nommé n'écrit rien.
const champsAcheteurNormalise = <ChampDef>[
  ChampDef(
      nom: 'acheteurIfu',
      libelle: 'IFU de l’acheteur',
      type: TypeChamp.texte,
      col: ColChamp.tiers,
      indicatif: '13 chiffres (facultatif pour un particulier)'),
  ChampDef(
      nom: 'acheteurNom',
      libelle: 'Nom de l’acheteur',
      type: TypeChamp.texte,
      col: ColChamp.tiers,
      indicatif: 'Le patient, par défaut'),
  ChampDef(
      nom: 'acheteurAib',
      libelle: 'Taux d’AIB',
      type: TypeChamp.select,
      col: ColChamp.tiers,
      options: [
        OptionChamp('0', 'Aucun'),
        OptionChamp('1', '1 % (taux de la facture de référence, à confirmer)'),
        OptionChamp('5', '5 %'),
      ]),
];

/// Les valeurs initiales de la fenêtre pour une pièce (ce qu'elle porte déjà), le taux par défaut sinon.
Map<String, Object?> valeursAcheteur(Map<String, Object?>? piece) => {
      'acheteurIfu': '${piece?['ifuClient'] ?? ''}',
      'acheteurNom': '${piece?['acheteurNom'] ?? ''}',
      'acheteurAib': '${piece?['aibTaux'] ?? aibTauxParDefaut}',
    };

/// Ce que la fenêtre a saisi, dans la forme de `encaisser` et de `normaliserVente`.
Map<String, Object?> lireAcheteur(ControleurFormulaire f) => {
      'ifu': f['acheteurIfu'],
      'nom': f['acheteurNom'],
      'aibTaux': int.tryParse('${f['acheteurAib']}') ?? f['acheteurAib'],
    };

/// La carte « Facture normalisée » : un petit formulaire à trois champs et la phrase qui dit que ce sont les seuls à saisir.
class SectionAcheteur extends StatelessWidget {
  const SectionAcheteur({super.key, required this.controleur});
  final ControleurFormulaire controleur;

  @override
  Widget build(BuildContext context) => Container(
        key: const Key('mecef:acheteur'),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            border: Border.all(color: JetonsShell.slate200),
            borderRadius: BorderRadius.circular(8)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('FACTURE NORMALISÉE',
              style: TextStyle(
                  color: JetonsShell.navy900,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6)),
          const SizedBox(height: 8),
          FormulaireSigh(controleur: controleur),
          const Text(
              'Toute vente est normalisée : ces trois champs sont les seuls à saisir. L’IFU, s’il est renseigné, compte 13 chiffres.',
              style: TextStyle(color: JetonsShell.slate500, fontSize: 12)),
        ]),
      );
}

/// Le contrôle de la fenêtre AVANT toute écriture : `null` quand elle est valide, sinon le refus nommé (code, motif, geste).
RefusMecef? controlerAcheteur(ControleurFormulaire f) {
  final v = lireAcheteur(f);
  return validerAcheteurMecef(
          ifu: v['ifu'], nom: v['nom'], aibTaux: v['aibTaux'])
      .refus;
}

/// Ce que la normalisation a rendu, dit au guichet : une pièce refusée se DIT, avec son code, son motif et son geste. Rien à dire en mode désactivé.
void annoncerNormalisation(BuildContext ctx, ResultatNormalisation? n) {
  if (n == null || n.ignore) return;
  if (n.ok) {
    ToastsSigh.afficher(ctx, 'Vente normalisée : ${n.numero}.',
        type: TypeToast.succes,
        detail: 'Numéro de démonstration, non fiscal (aucun boîtier branché).');
    return;
  }
  ToastsSigh.afficher(ctx,
      'Normalisation non aboutie (${n.code}) : la vente est encaissée mais pas normalisée.',
      type: TypeToast.attention,
      detail: '${n.motif} ${n.geste}',
      duree: const Duration(seconds: 12));
}
