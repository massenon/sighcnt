import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'besoins_commun.dart';

/// `m7-receptions` — « Réceptions & contrôles » : réception physique d'une commande validée, vérification contradictoire par 2 à 3 personnes, entrée en
/// stock gros et CUMP recalculé. Le calcul est dans `packages/domaine` (`achats/reception.dart`) et rejoué sur les vecteurs de la maquette.
class EcranReceptions extends StatelessWidget with EcranMaquette {
  const EcranReceptions({super.key});

  @override
  String get titre => 'Réceptions & contrôles';

  @override
  String get description =>
      'Réception physique des livraisons, vérification contradictoire par 2 à 3 personnes et entrée en stock gros.';

  @override
  String get regle =>
      'La vérification est réalisée par 2 à 3 personnes (processus de la clinique). Après validation, les quantités reçues sont enregistrées au stock gros et le CUMP est recalculé.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('commandes');
    return ListenableBuilder(
      listenable: col,
      builder: (context, _) {
        final actives = col.actives;
        final aRecevoir = commandesAReceptionner(actives);
        final k = indicateursReceptions(actives);
        final ex = ((c.magasin.referentiels['paramFiscal'] as Map?)?['exemple']
                as Map?)
            ?.cast<String, Object?>() ??
            const <String, Object?>{};
        final num_ = (((c.magasin.referentiels['paramFiscal'] as Map?)?['numerotation']
                as Map?)?['modele']) ??
            '';
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              KpiGrilleSigh(kpis: [
                KpiSigh(
                    libelle: 'Commandes à réceptionner',
                    valeur: nombre(k.aReceptionner),
                    icone: LucideIcons.packageOpen,
                    ton: TonSigh.attention),
                KpiSigh(
                    libelle: 'Réceptions réalisées',
                    valeur: nombre(k.realisees),
                    icone: LucideIcons.circleCheck,
                    ton: TonSigh.succes),
                KpiSigh(
                    libelle: 'Valeur attendue',
                    valeur: money(k.valeurAttendue),
                    icone: LucideIcons.wallet,
                    ton: TonSigh.info),
                KpiSigh(
                    libelle: 'Fournisseurs concernés',
                    valeur: nombre(k.fournisseurs),
                    icone: LucideIcons.truck,
                    ton: TonSigh.neutre),
              ]),
              const SizedBox(height: 16),
              // Modèle de référence : la liasse SoBAPS analysée lors du cadrage.
              CarteSigh(
                  titre: 'Modèle de référence — liasse SoBAPS du cadrage',
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        MiniTableauSigh(colonnes: [
                          ColonneMini('Étape', (x) => '${x['etape']}'),
                          ColonneMini('Document', (x) => '${x['num']}',
                              rendu: (x) => refMono(x['num'])),
                          ColonneMini('Date', (x) => '${x['date']}'),
                          ColonneMini('Montant', (x) => '${x['montant']}',
                              droite: true),
                        ], lignes: [
                          {
                            'etape': '1. Pro-forma / bon de commande',
                            'num': ex['proforma'],
                            'date': '09/07/2026',
                            'montant': m(ex['totalTTC'])
                          },
                          {
                            'etape': '2. Bordereau de livraison',
                            'num': ex['bonLivraison'],
                            'date': '10/07/2026',
                            'montant': m(ex['totalTTC'])
                          },
                          {
                            'etape': '3. Facture de vente normalisée',
                            'num': ex['facture'],
                            'date': '10/07/2026',
                            'montant': m(ex['totalTTC'])
                          },
                        ]),
                        const SizedBox(height: 12),
                        NoteSigh(
                            'Les trois documents portent le même montant : c’est ce rapprochement que le système contrôle. La convention de numérotation du fournisseur est $num_ — B pour le bon, L pour la livraison, F pour la facture.',
                            icone: LucideIcons.fileCheck2),
                        const SizedBox(height: 12),
                        NoteSigh(
                            'La facture est certifiée MECeF : code DGI ${ex['codeMecef']}, total HT ${money(ex['totalHT'])}, AIB 1 % ${money(ex['aib'])}, net à payer ${money(ex['totalTTC'])}. La TVA y est portée à zéro, les produits de santé étant exonérés.',
                            ton: TonSigh.succes,
                            icone: LucideIcons.shieldCheck),
                      ])),
              const SizedBox(height: 16),
              TableauSigh(
                titre: 'Commandes en attente de réception',
                lignes: aRecevoir,
                taillePage: 10,
                nomExport: 'receptions-attendues',
                messageVide: 'Aucune commande en attente de réception.',
                colonnes: [
                  ColonneTableau(
                      cle: 'reference',
                      libelle: 'N° commande',
                      sansCoupure: true,
                      texte: (x) => '${x['reference']}',
                      rendu: (_, x) => refMono(x['reference'])),
                  ColonneTableau(
                      cle: 'date',
                      libelle: 'Date',
                      sansCoupure: true,
                      texte: (x) => dateDe(x['date'])),
                  const ColonneTableau(cle: 'fournisseurNom', libelle: 'Fournisseur'),
                  ColonneTableau(
                      cle: 'nbLignes',
                      libelle: 'Articles',
                      droite: true,
                      valeur: (x) => lignesDeBon(x).length,
                      texte: (x) => '${lignesDeBon(x).length}'),
                  ColonneTableau(
                      cle: 'montant',
                      libelle: 'Montant',
                      droite: true,
                      texte: (x) => m(x['montant'])),
                  const ColonneTableau(cle: 'valideePar', libelle: 'Validée par'),
                ],
                // E79 : réceptionner ÉCRIT (bordereau, entrée en stock, CUMP) — absent pour un profil qui lit l'écran.
                actionsLigne: (ctx, x) => [
                  if (c.droit.editer)
                    BoutonSigh(
                        libelle: 'Réceptionner',
                        icone: LucideIcons.packageCheck,
                        taille: TailleBouton.sm,
                        onPressed: () => _receptionner(context, x)),
                ],
              ),
            ]);
      },
    );
  }
}

void _receptionner(BuildContext ecran, Fiche cmd) {
  afficherModale<void>(ecran,
      titre: 'Réception de la commande ${cmd['reference']}',
      sousTitre: '${cmd['fournisseurNom']} — ${money(cmd['montant'])}',
      taille: TailleModale.xl,
      corps: _ModaleReception(
          contexte: ContexteEcran.of(ecran), ecran: ecran, commande: cmd),
      pied: null);
}

class _ModaleReception extends StatefulWidget {
  const _ModaleReception(
      {required this.contexte, required this.ecran, required this.commande});
  final ContexteEcran contexte;
  final BuildContext ecran;
  final Fiche commande;
  @override
  State<_ModaleReception> createState() => _EtatModaleReception();
}

class _EtatModaleReception extends State<_ModaleReception> {
  late final ControleurFormulaire _f;
  late final List<Fiche> _lignes;
  late final List<TextEditingController> _recus;

  @override
  void initState() {
    super.initState();
    _lignes = lignesDeBon(widget.commande);
    // Par défaut, tout ce qui est commandé est reçu.
    _recus = [
      for (final l in _lignes) TextEditingController(text: '${l['quantite']}')
    ];
    _f = ControleurFormulaire([
      const ChampDef(
          nom: 'referenceBL',
          libelle: 'N° bordereau de livraison',
          requis: true,
          indicatif: 'ex. 26LNA00026'),
      const ChampDef(
          nom: 'date',
          libelle: 'Date de réception',
          type: TypeChamp.date,
          requis: true),
      const ChampDef(nom: 'controleur1', libelle: 'Contrôleur 1', requis: true),
      const ChampDef(nom: 'controleur2', libelle: 'Contrôleur 2', requis: true),
      const ChampDef(nom: 'controleur3', libelle: 'Contrôleur 3 (facultatif)'),
      const ChampDef(
          nom: 'observations',
          libelle: 'Observations',
          type: TypeChamp.textarea,
          lignes: 2,
          col: ColChamp.plein),
    ], {
      'date': iso(widget.contexte.aujourdhui),
      'controleur1': 'MAMAN Zoukanéri',
      'controleur2': 'DIEYABIDI Aïssatou',
    });
    for (final r in _recus) {
      r.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _f.dispose();
    for (final r in _recus) {
      r.dispose();
    }
    super.dispose();
  }

  num _recu(int i) => nombreOuZero(_recus[i].text);

  void _valider(VoidCallback fermer) {
    final c = widget.contexte;
    final v = _f.valider();
    if (v == null) {
      dire(widget.ecran, 'Le formulaire comporte des erreurs.',
          type: TypeToast.erreur);
      return;
    }
    // La saisie est indexée par article (la dernière ligne d'un article en double l'emporte, comme la maquette).
    final recus = <String, num>{
      for (final (i, l) in _lignes.indexed) '${l['produitId']}': _recu(i)
    };
    final produitsCol = c.magasin.collection('produits');
    final calc = calculerReception(
        commande: widget.commande,
        recus: recus,
        entete: v,
        produits: produitsCol.actives,
        mouvements: c.magasin.collection('mouvements').toutes);
    final annulations = <VoidCallback>[];
    final bl = c.magasin
        .collection('livraisons')
        .inserer({...calc.livraison, 'statut': 'actif'}, prefixe: 'LIV');
    annulations.add(bl.annuler);
    final mouvements = c.magasin.collection('mouvements');
    for (final (i, maj) in calc.majProduits.indexed) {
      // Entrée en stock gros et recalcul du CUMP, un mouvement par article.
      annulations.add(produitsCol.mettreAJour(maj.id, maj.patch));
      annulations.add(mouvements
          .inserer({...calc.mouvements[i], 'statut': 'actif'}, prefixe: 'MOU')
          .annuler);
    }
    annulations.add(c.magasin
        .collection('commandes')
        .mettreAJour(widget.commande['id'], calc.patchCommande));
    fermer();
    dire(widget.ecran, calc.message,
        type: calc.type == 'success' ? TypeToast.succes : TypeToast.attention,
        detail: 'Stock gros mis à jour, CUMP recalculé.',
        annuler: () {
          for (final u in annulations.reversed) {
            u();
          }
        });
  }

  @override
  Widget build(BuildContext context) {
    Widget cel(Widget w, {bool droite = false}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Align(
            alignment: droite ? Alignment.centerRight : Alignment.centerLeft,
            child: w));
    Widget tete(String t, {bool droite = false}) => cel(
        Text(t.toUpperCase(),
            style: const TextStyle(
                color: JetonsShell.slate500,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
        droite: droite);
    return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const NoteSigh(
              'Saisir les quantités réellement reçues. Tout écart entre la commande et la livraison est signalé et pris en compte lors de la livraison suivante.'),
          const SizedBox(height: 16),
          FormulaireSigh(controleur: _f),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
                border: Border.all(color: JetonsShell.slate200),
                borderRadius: BorderRadius.circular(8)),
            child: Table(columnWidths: const {
              0: FlexColumnWidth(3),
              1: FlexColumnWidth(1),
              2: FixedColumnWidth(120),
              3: FlexColumnWidth(1),
            }, children: [
              TableRow(
                  decoration: const BoxDecoration(color: JetonsShell.slate50),
                  children: [
                    tete('Article'),
                    tete('Commandé', droite: true),
                    tete('Reçu', droite: true),
                    tete('Écart', droite: true),
                  ]),
              for (final (i, l) in _lignes.indexed)
                TableRow(
                    decoration: const BoxDecoration(
                        border:
                            Border(top: BorderSide(color: JetonsShell.slate100))),
                    children: [
                      cel(Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${l['produit']}',
                                style: const TextStyle(
                                    color: JetonsShell.slate700, fontSize: 14)),
                            Text('${l['unite']}',
                                style: const TextStyle(
                                    color: JetonsShell.slate400, fontSize: 12)),
                          ])),
                      cel(Text(nombre(l['quantite'])), droite: true),
                      cel(
                          SizedBox(
                              width: 96,
                              child: TextField(
                                  key: Key('recu:$i'),
                                  controller: _recus[i],
                                  textAlign: TextAlign.right,
                                  keyboardType: TextInputType.number,
                                  style: styleSaisie,
                                  decoration: decorationChamp())),
                          droite: true),
                      cel(
                          Builder(builder: (_) {
                            final e = ecartLigne(_recu(i), n(l['quantite']));
                            return Text(
                                '${e > 0 ? '+' : ''}${nombre(e)}',
                                key: Key('ecart:$i'),
                                style: TextStyle(
                                    fontWeight:
                                        e == 0 ? FontWeight.w400 : FontWeight.w600,
                                    color: e == 0
                                        ? JetonsShell.slate900
                                        : JetonsShell.danger600));
                          }),
                          droite: true),
                    ]),
            ]),
          ),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            BoutonSigh(
                libelle: 'Annuler',
                variante: VarianteBouton.secondaire,
                onPressed: () => Navigator.of(context).pop()),
            const SizedBox(width: 8),
            BoutonSigh(
                libelle: 'Valider la réception',
                icone: LucideIcons.packageCheck,
                onPressed: () => _valider(() => Navigator.of(context).pop())),
          ]),
        ]);
  }
}
