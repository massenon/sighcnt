import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../donnees/magasin.dart' show EcritureRefusee;
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'pai_commun.dart';

/// `m11-validation` — « Validation de la paie » : aucun bulletin ne se diffuse sans la validation FORMELLE de la Direction. Un lot = une période ; valider
/// le lot passe tous ses bulletins « à valider » en « validé » (annulable, journalisé). Signer n'est pas saisir : la commande « Valider le lot » est
/// derrière le droit d'écrire DE L'ÉCRAN (la Direction l'a par surcharge d'écran, le module M11 lui restant en lecture) — ABSENTE sans lui, jamais grisée.
///
/// A2 : « signer n'est pas saisir ». Le comptable (qui génère) n'a que la lecture de cet écran ; le validateur est l'agent CONNECTÉ (E687 corrigé : plus
/// de nom écrit en dur) et il ne peut pas être celui qui a généré le lot (refus nommé). B6 : valider un lot pose l'ÉCRITURE DE PAIE en brouillon (RG-10
/// contrôlé avant écriture, refus nommé sinon), et un lot validé se DIFFUSE (statut « Diffusé »), commande absente sans le droit d'écrire.
///
/// Écarts portés : (E685) la maquette offrait le bouton à tout profil qui ouvre l'écran (corrigé à la maquette, porté derrière `droit.editer`).
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
        message:
            'Cette validation autorise la diffusion de ${l.nb} bulletin(s) pour un net à payer total de ${money(l.net)}. L’opération est journalisée au nom de l’agent connecté, et l’écriture de paie est posée en brouillon.',
        libelleOk: 'Valider la paie');
    if (!ok || !ctx.mounted) return;
    final col = c.magasin.collection('bulletins');
    final lot = col.actives.where((b) => b['periode'] == l.periode && b['statutBulletin'] == 'a_valider').toList();
    // A2 : le validateur est l'agent connecté, jamais celui qui a généré.
    final validateur = c.utilisateur.isEmpty ? 'Utilisateur non identifié' : c.utilisateur;
    final refus = paiControleSeparation(lot, validateur);
    if (refus != null) {
      c.magasin.journaliser('Validation de paie refusée', 'M11', 'BulletinPaie', l.periode, null, {'motif': refus});
      ToastsSigh.afficher(ctx, 'Validation refusée.', type: TypeToast.erreur, detail: refus);
      return;
    }
    // B6 : la pièce comptable d'abord (RG-10 contrôlé) ; refusée, rien n'est validé.
    final ecritures = c.magasin.collection('ecritures');
    final piece = paiPieceDePaie(l.periode, lot, date: iso(c.aujourdhui), ecritures: ecritures.toutes, montantTexte: money);
    if (!piece.ok) {
      c.magasin.journaliser('Écriture de paie refusée, déséquilibre', 'M12', 'Ecriture', 'PAIE-${l.periode}', null, {'debit': piece.debit, 'credit': piece.credit});
      ToastsSigh.afficher(ctx, 'Validation refusée.', type: TypeToast.erreur, detail: piece.refus);
      return;
    }
    final annulations = <VoidCallback>[];
    try {
      for (final f in piece.fiches) {
        annulations.add(ecritures.inserer({'statut': 'brouillon', ...f}, prefixe: 'ECR').annuler);
      }
    } on EcritureRefusee {
      // le journal refuse (exercice clos) : on défait ce qui a été posé, rien n'est validé
      for (final u in annulations) {
        u();
      }
      ToastsSigh.afficher(ctx, 'Validation refusée.', type: TypeToast.erreur, detail: 'L’écriture de paie de ${l.periode} est refusée par le journal (exercice clos).');
      return;
    }
    for (final b in lot) {
      annulations.add(col.mettreAJour(b['id'], {'statutBulletin': 'valide', 'validePar': validateur, 'dateValidation': iso(c.aujourdhui), 'ecritureNumero': piece.numero}));
    }
    ToastsSigh.afficher(ctx, 'Paie de ${l.periode} validée par $validateur.',
        type: TypeToast.succes,
        detail: '${lot.length} bulletin(s) autorisé(s) à la diffusion ; écriture ${piece.numero} posée en brouillon.',
        annuler: () {
          for (final u in annulations) {
            u();
          }
        });
  }

  Future<void> _diffuser(BuildContext ctx, ContexteEcran c, PaiLot l) async {
    final ok = await confirmerSigh(ctx,
        titre: 'Diffuser la paie de ${l.periode} ?',
        message: 'Les bulletins validés (${l.aDiffuser}) seront remis aux agents. La diffusion est journalisée au nom de l’agent connecté.',
        libelleOk: 'Diffuser');
    if (!ok || !ctx.mounted) return;
    final col = c.magasin.collection('bulletins');
    final annulations = [
      for (final b in col.actives.where((b) => b['periode'] == l.periode && b['statutBulletin'] == 'valide'))
        col.mettreAJour(b['id'], {'statutBulletin': 'diffuse', 'diffusePar': c.utilisateur.isEmpty ? 'Utilisateur non identifié' : c.utilisateur, 'dateDiffusion': iso(c.aujourdhui)})
    ];
    ToastsSigh.afficher(ctx, 'Paie de ${l.periode} diffusée.', type: TypeToast.succes, detail: '${annulations.length} bulletin(s) remis aux agents.', annuler: () {
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
                    texte: (l) => n(l['aValider']) != 0 ? '${l['aValider']} à valider' : (_lot(l).aDiffuser > 0 ? 'Validé' : 'Diffusé'),
                    rendu: (_, l) => n(l['aValider']) != 0
                        ? BadgeSigh('${l['aValider']} à valider', ton: TonSigh.attention)
                        : (_lot(l).aDiffuser > 0 ? const BadgeSigh('Validé', ton: TonSigh.succes) : const BadgeSigh('Diffusé', ton: TonSigh.navy))),
              ],
              actionsLigne: (ctx, l) => [
                BoutonIcone(icone: LucideIcons.printer, libelle: 'Journal de paie', onPressed: () => _journal(context, c, _lot(l))),
                if (_lot(l).aValider > 0 && c.droit.editer)
                  BoutonSigh(libelle: 'Valider le lot', icone: LucideIcons.badgeCheck, taille: TailleBouton.sm, variante: VarianteBouton.succes, onPressed: () => _valider(context, c, _lot(l)))
                else if (_lot(l).aDiffuser > 0 && c.droit.editer)
                  BoutonSigh(libelle: 'Diffuser', icone: LucideIcons.send, taille: TailleBouton.sm, variante: VarianteBouton.primaire, onPressed: () => _diffuser(context, c, _lot(l))),
              ],
            ),
        ]);
      },
    );
  }
}
