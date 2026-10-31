import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'pai_commun.dart';

/// `m11-validation` — « Validation de la paie » : aucun bulletin ne se diffuse sans la validation FORMELLE de la Direction. Un lot = une période ; valider
/// le lot passe tous ses bulletins « à valider » en « validé » (annulable, journalisé). Signer n'est pas saisir : la commande « Valider le lot » est
/// derrière le droit d'écrire DE L'ÉCRAN (la Direction l'a par surcharge d'écran, le module M11 lui restant en lecture) — ABSENTE sans lui, jamais grisée.
///
/// Écarts portés : (E685) la maquette offre le bouton à tout profil qui ouvre l'écran ; (E687) elle écrit `validePar` en dur au nom du Directeur Médical,
/// quel que soit l'agent connecté — le journal d'audit (RG-12) garde, lui, le vrai nom de l'agent.
class EcranValidationPaie extends StatelessWidget with EcranMaquette {
  const EcranValidationPaie({super.key});

  @override
  String get titre => 'Validation de la paie';

  @override
  String get description => 'Soumission des bulletins à la Direction pour validation avant diffusion aux agents.';

  @override
  String get regle => 'Aucun bulletin ne peut être diffusé sans validation formelle de la Direction.';

  static Map<String, Object?> _ligne(PaiLot l) => {'id': l.periode, 'periode': l.periode, 'nb': l.nb, 'brut': l.brut, 'cnss': l.cnss, 'net': l.net, 'aValider': l.aValider, 'valides': l.valides, '_l': l};
  static PaiLot _lot(Map<String, Object?> l) => l['_l'] as PaiLot;

  Future<void> _valider(BuildContext ctx, ContexteEcran c, PaiLot l) async {
    final ok = await confirmerSigh(ctx,
        titre: 'Valider la paie de ${l.periode} ?',
        message: 'Cette validation autorise la diffusion de ${l.nb} bulletin(s) pour un net à payer total de ${money(l.net)}. L’opération est journalisée au nom de la Direction.',
        libelleOk: 'Valider la paie');
    if (!ok || !ctx.mounted) return;
    final col = c.magasin.collection('bulletins');
    final annulations = [
      for (final b in col.actives.where((b) => b['periode'] == l.periode && b['statutBulletin'] == 'a_valider'))
        col.mettreAJour(b['id'], {'statutBulletin': 'valide', 'validePar': paiNomDirection, 'dateValidation': iso(c.aujourdhui)})
    ];
    ToastsSigh.afficher(ctx, 'Paie de ${l.periode} validée par la Direction.', type: TypeToast.succes, detail: '${annulations.length} bulletin(s) autorisé(s) à la diffusion.', annuler: () {
      for (final u in annulations) {
        u();
      }
    });
  }

  void _journal(BuildContext ctx, ContexteEcran c, PaiLot l) {
    final b = trierPar(c.magasin.collection('bulletins').actives.where((x) => x['periode'] == l.periode).toList(), (x) => x['employe']);
    num f(Map<String, Object?> r, String k) => nombreOuZero(r[k]);
    afficherApercu(
        ctx,
        pieceM9(c,
            titre: 'Journal de paie — validation',
            sousTitre: l.periode,
            cartouche: [
              ('Période', l.periode),
              ('Bulletins', nombre(l.nb)),
              ('Masse salariale brute', money(l.brut)),
              ('Net à payer', money(l.net)),
              ('CNSS totale', money(l.cnss)),
              ('Date d’édition', dateFR(c.aujourdhui)),
            ],
            tableaux: [
              TableauEtat(colonnes: [
                ColonneEtat(libelle: 'Mat.', valeur: (r) => r['matricule']),
                ColonneEtat(libelle: 'Agent', valeur: (r) => r['employe']),
                ColonneEtat(libelle: 'Service', valeur: (r) => r['service']),
                ColonneEtat(libelle: 'Brut', droite: true, valeur: (r) => money(f(r, 'brut'), avecDevise: false), somme: (r) => f(r, 'brut')),
                ColonneEtat(libelle: 'Retenues', droite: true, valeur: (r) => money(f(r, 'totalRetenues'), avecDevise: false), somme: (r) => f(r, 'totalRetenues')),
                ColonneEtat(libelle: 'Net à payer', droite: true, valeur: (r) => money(f(r, 'net'), avecDevise: false), somme: (r) => f(r, 'net')),
                ColonneEtat(libelle: 'Émargement', valeur: (r) => ''),
              ], lignes: b)
            ],
            signatures: const [
              Signature('Le Responsable RH'),
              signComptable,
              Signature('La Direction', nom: paiNomDirection, mention: 'Bon à payer'),
            ]));
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return ListenableBuilder(
      listenable: c.magasin.collection('bulletins'),
      builder: (context, _) {
        final lots = paiLots(c.magasin.collection('bulletins').actives);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          KpiGrilleSigh(kpis: [
            KpiSigh(libelle: 'Périodes traitées', valeur: nombre(lots.length), icone: LucideIcons.calendar),
            KpiSigh(libelle: 'Bulletins à valider', valeur: nombre(lots.fold<int>(0, (a, l) => a + l.aValider)), icone: LucideIcons.hourglass, ton: TonSigh.attention),
            KpiSigh(libelle: 'Bulletins validés', valeur: nombre(lots.fold<int>(0, (a, l) => a + l.valides)), icone: LucideIcons.badgeCheck, ton: TonSigh.succes),
            KpiSigh(libelle: 'Net à payer cumulé', valeur: money(lots.fold<num>(0, (a, l) => a + l.net)), icone: LucideIcons.wallet, ton: TonSigh.info),
          ]),
          const SizedBox(height: 16),
          if (lots.isEmpty)
            CarteSigh(
                child: VideSigh('Aucun bulletin généré.',
                    icone: LucideIcons.fileText,
                    indice: 'Lancer le calcul de la paie puis générer les bulletins avant de les soumettre à validation.',
                    action: BoutonSigh(libelle: 'Calculer la paie', icone: LucideIcons.calculator, onPressed: () => c.aller('m11-calcul'))))
          else
            TableauSigh(
              titre: 'Lots de paie par période',
              lignes: [for (final l in lots) _ligne(l)],
              nomExport: 'validation-paie',
              taillePage: 12,
              colonnes: [
                const ColonneTableau(cle: 'periode', libelle: 'Période', sansCoupure: true),
                const ColonneTableau(cle: 'nb', libelle: 'Bulletins', droite: true),
                ColonneTableau(cle: 'brut', libelle: 'Masse brute', droite: true, texte: (l) => m(l['brut']), rendu: (_, l) => cellMontant(n(l['brut']))),
                ColonneTableau(cle: 'cnss', libelle: 'CNSS totale', droite: true, texte: (l) => m(l['cnss']), rendu: (_, l) => cellMontant(n(l['cnss']))),
                ColonneTableau(cle: 'net', libelle: 'Net à payer', droite: true, texte: (l) => m(l['net']), rendu: (_, l) => cellTexte(m(l['net']), couleur: JetonsShell.navy900, poids: FontWeight.w700)),
                ColonneTableau(
                    cle: 'aValider',
                    libelle: 'Statut',
                    texte: (l) => n(l['aValider']) != 0 ? '${l['aValider']} à valider' : 'Validé',
                    rendu: (_, l) => n(l['aValider']) != 0 ? BadgeSigh('${l['aValider']} à valider', ton: TonSigh.attention) : const BadgeSigh('Validé', ton: TonSigh.succes)),
              ],
              actionsLigne: (ctx, l) => [
                BoutonIcone(icone: LucideIcons.printer, libelle: 'Journal de paie', onPressed: () => _journal(context, c, _lot(l))),
                if (_lot(l).aValider > 0 && c.droit.editer)
                  BoutonSigh(libelle: 'Valider le lot', icone: LucideIcons.badgeCheck, taille: TailleBouton.sm, variante: VarianteBouton.succes, onPressed: () => _valider(context, c, _lot(l))),
              ],
            ),
        ]);
      },
    );
  }
}
