import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'flux_commun.dart';

/// Les DEUX pharmacies (`ecranPharmacie` de m6-stock.js). Le 25/08/2026 la Direction a tranché : la clinique distingue deux ordonnances, donc deux circuits — ils
/// n'ont ni le même justificatif de sortie, ni le même destinataire, ni le même rythme. La **pharmacie interne** sert les soins d'urgence administrés SUR PLACE : le
/// produit part vers la salle de soins, jamais vers le patient ; la **pharmacie externe** sert la voie orale que le patient EMPORTE. RG-03 s'applique aux deux :
/// toute sortie porte son justificatif (le n° d'ordonnance) et le stock ne devient jamais négatif — le refus NOMME l'article.
///
/// Aucune création manuelle : la délivrance naît d'une ordonnance du médecin passée en caisse. Corrigés dans la maquette avant le portage : E40 (états
/// « soldee » / « servie »), E41 (« inj » = injectable), E44 (message de succès jamais affiché). Portés fidèlement : E45 (stock TOTAL compté et décompté),
/// E46 (l'ordonnance entière passe « servie » dès qu'une ligne est délivrée).
abstract class EcranPharmacie extends StatelessWidget with EcranMaquette {
  const EcranPharmacie(this.voie, {super.key});

  /// `parenterale` (interne) ou `orale` (externe).
  final String voie;

  String get note;

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final m = c.magasin;
    return ListenableBuilder(
      listenable: Listenable.merge([
        m.collection('ordonnances'),
        m.collection('produits'),
        m.collection('taches'),
      ]),
      builder: (context, _) {
        final ls = lignesPharmacie(
            ordonnances: m.collection('ordonnances').actives,
            produits: m.collection('produits').actives,
            voie: voie);
        final st = statsPharmacie(ls);
        final lignes = aDelivrerTriees(ls);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          KpiGrilleSigh(kpis: [
            KpiSigh(
                libelle: 'Lignes de cette pharmacie',
                valeur: nombre(st.lignes),
                icone: LucideIcons.pill,
                ton: TonSigh.navy),
            KpiSigh(
                libelle: 'À délivrer',
                valeur: nombre(st.aDelivrer),
                icone: LucideIcons.packageOpen,
                ton: TonSigh.info),
            KpiSigh(
                libelle: 'Bloquées faute de règlement',
                valeur: nombre(st.bloquees),
                icone: LucideIcons.lock,
                ton: st.bloquees > 0 ? TonSigh.attention : TonSigh.succes),
            KpiSigh(
                libelle: 'Non couvertes par le stock',
                valeur: nombre(st.decouvertes),
                icone: LucideIcons.triangleAlert,
                ton: st.decouvertes > 0 ? TonSigh.danger : TonSigh.succes,
                indice: 'RG-03 : refus nommé'),
          ]),
          const SizedBox(height: 16),
          NoteSigh(note, ton: TonSigh.info, icone: LucideIcons.route),
          const SizedBox(height: 16),
          TableauSigh(
            lignes: [
              for (final l in lignes)
                {
                  'id': l.id,
                  '_ligne': l,
                  'numero': l.numero,
                  'date': l.date,
                  'patient': '${l.patient} — ${l.patientCode}',
                  'designation': l.designation,
                  'quantite': l.quantite,
                  'posologie': l.posologie,
                  'stock': l.stock,
                  'etat': l.etat,
                }
            ],
            nomExport: 'pharmacie',
            messageVide: 'Aucun enregistrement.',
            colonnes: [
              const ColonneTableau(cle: 'numero', libelle: 'Ordonnance'),
              ColonneTableau(
                  cle: 'date',
                  libelle: 'Date',
                  texte: (r) => dateDe((r['_ligne'] as LignePharmacie).date)),
              const ColonneTableau(cle: 'patient', libelle: 'Patient'),
              const ColonneTableau(cle: 'designation', libelle: 'Produit'),
              const ColonneTableau(cle: 'quantite', libelle: 'Quantité', droite: true),
              const ColonneTableau(cle: 'posologie', libelle: 'Posologie'),
              ColonneTableau(
                  cle: 'stock',
                  libelle: 'Stock',
                  droite: true,
                  texte: (r) {
                    final l = r['_ligne'] as LignePharmacie;
                    return l.stock == null ? 'produit inconnu' : nombre(l.stock);
                  },
                  rendu: (_, r) {
                    final l = r['_ligne'] as LignePharmacie;
                    if (l.stock == null) {
                      return const Text('produit inconnu',
                          style: TextStyle(
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                              color: JetonsShell.slate400));
                    }
                    return Text(nombre(l.stock),
                        style: TextStyle(
                            fontSize: 14,
                            height: 20 / 14,
                            fontWeight: l.couvert ? FontWeight.w400 : FontWeight.w600,
                            color: l.couvert ? JetonsShell.slate700 : JetonsShell.danger700));
                  }),
              ColonneTableau(
                  cle: 'etat',
                  libelle: 'État',
                  rendu: (_, r) {
                    final l = r['_ligne'] as LignePharmacie;
                    return BadgeSigh(l.etat,
                        ton: !l.paye
                            ? TonSigh.attention
                            : (!l.couvert ? TonSigh.danger : TonSigh.succes));
                  }),
            ],
            actionsLigne: (ctx, r) {
              final l = r['_ligne'] as LignePharmacie;
              if (!c.droit.editer) return const [];
              if (!l.paye) {
                return [
                  BoutonIcone(
                      icone: LucideIcons.lock,
                      libelle: 'Bloquée : l’ordonnance n’est pas réglée',
                      onPressed: () => ToastsSigh.afficher(ctx,
                          'Délivrance bloquée — l’ordonnance ${l.numero} n’est pas réglée.',
                          type: TypeToast.attention))
                ];
              }
              return [
                BoutonSigh(
                    libelle: 'Délivrer',
                    icone: LucideIcons.check,
                    taille: TailleBouton.sm,
                    onPressed: () => _delivrer(ctx, c, l))
              ];
            },
          ),
        ]);
      },
    );
  }

  Future<void> _delivrer(BuildContext ctx, ContexteEcran c, LignePharmacie l) async {
    final mag = c.magasin;
    final jour = iso(c.aujourdhui);
    final mouvements = mag.collection('mouvements');
    // RG-03 : le refus NOMME l'article. Un refus muet ferait chercher la panne du côté du logiciel.
    final DelivranceLigne d;
    try {
      d = delivrerLigne(l, voie,
          reference: referenceSuivante('MVT-', 5, mouvements.toutes), jour: jour);
    } on RefusDelivrance catch (e) {
      ToastsSigh.afficher(ctx, e.motif, type: TypeToast.erreur);
      return;
    }
    final ok = await confirmerSigh(ctx,
        titre: 'Délivrer ${l.designation} ?',
        message: messageConfirmation(l, voie),
        libelleOk: 'Délivrer');
    if (!ok || !ctx.mounted) return;
    mag.collection('produits').mettreAJour(l.produit!['id'], d.produitPatch);
    mouvements.inserer(d.mouvement, prefixe: 'MVT');
    mag.collection('ordonnances').mettreAJour(l.ordonnance['id'], d.ordonnancePatch);
    appliquerAlertes(
        mag,
        alerterStock(d.alerteProduitIds, produitsParId(mag),
            mag.collection('taches').actives, '${l.numero}', c.aujourdhui.toIso8601String()));
    ToastsSigh.afficher(ctx, d.message, type: TypeToast.succes, detail: d.detail);
  }
}

class EcranPharmacieInterne extends EcranPharmacie {
  const EcranPharmacieInterne({super.key}) : super('parenterale');

  @override
  String get titre => 'Pharmacie interne — urgences';

  @override
  String get description =>
      'Produits administrés sur place : injectables, perfusions et solutés remis à la salle de soins.';

  @override
  String get regle =>
      'Le produit ne quitte pas la clinique : il est délivré à la salle de soins, qui l’administre. Il n’y a pas de vente au comptoir — la sortie de stock est justifiée par une prescription, pas par un ticket. RG-03 s’applique : le refus nomme l’article.';

  @override
  String get note =>
      'Cette pharmacie sert les soins d’urgence administrés sur place. Les produits partent vers la salle de soins, jamais vers le patient directement — c’est le personnel soignant qui les administre, et la traçabilité de l’administration relève de la prescription de soins.';
}

class EcranPharmacieExterne extends EcranPharmacie {
  const EcranPharmacieExterne({super.key}) : super('orale');

  @override
  String get titre => 'Pharmacie externe — voie orale';

  @override
  String get description =>
      'Traitements par voie orale que le patient emporte : délivrance au comptoir sur ordonnance réglée.';

  @override
  String get regle =>
      'Le patient emporte son traitement. La délivrance suppose une ordonnance réglée — c’est la même règle qu’au laboratoire et en salle de soins. RG-03 : toute sortie porte son justificatif, et le stock ne devient jamais négatif.';

  @override
  String get note =>
      'Cette pharmacie sert les traitements par voie orale que le patient emporte. La distinction avec la pharmacie interne n’est pas administrative : les deux circuits n’ont ni le même justificatif de sortie, ni le même destinataire.';
}
