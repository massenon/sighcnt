import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'tba_commun.dart';

/// Les rappels du matin déjà montrés : UN par jour et par poste (la maquette l'écrit dans `sessionStorage`). Rouvrir la page dix fois ne doit pas
/// rouvrir la modale dix fois, sinon on la ferme sans la lire — et le jour où elle compte, elle est balayée du même geste.
final Expando<Set<String>> _rappelsMontres = Expando('rappels du laboratoire');

/// `dash-laborantin` — « Tableau de bord — Laboratoire » : les DEUX verrous. Ce que le biologiste regarde en premier, c'est ce qui attend SA
/// signature ; à l'ouverture, un rappel dit ce qui attend le poste (prélèvements à faire, échantillons reçus à saisir).
class EcranDashLaborantin extends StatefulWidget with EcranMaquette {
  const EcranDashLaborantin({super.key});

  @override
  String get titre => 'Tableau de bord — Laboratoire';

  @override
  String get description =>
      'Demandes d’analyses, résultats à saisir, consommation de réactifs et banque de sang.';

  @override
  State<EcranDashLaborantin> createState() => _EtatDashLaborantin();
}

class _EtatDashLaborantin extends State<EcranDashLaborantin> {
  @override
  void initState() {
    super.initState();
    // Le rappel s'ouvre AVANT le rendu dans la maquette (crochet `avant`) : ici dès la première image.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _rappel(ContexteEcran.of(context));
    });
  }

  void _rappel(ContexteEcran c) {
    final jour = iso(c.aujourdhui);
    final montres = (_rappelsMontres[c.magasin] ??= <String>{});
    if (montres.contains(jour)) return;
    final r = tbaRappelBiologiste(tbaActives(c, 'demandesAnalyses'));
    // Une modale qui annonce « rien à faire » coûte un clic pour aucune information.
    if (r == null) return;
    montres.add(jour);
    afficherModale<void>(
      context,
      titre: 'Rappel du laboratoire',
      sousTitre: 'Ce qui attend votre poste ce matin',
      corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (r.aPrelever > 0)
          _BlocRappel(
              titre: 'analyse(s) réglée(s) à la caisse, prélèvement à faire',
              detail:
                  'Le patient a payé : il peut être appelé en salle de prélèvement. Tant que le prélèvement n’est pas fait, aucun résultat ne peut être saisi.',
              nb: r.aPrelever,
              ton: TonSigh.attention,
              icone: LucideIcons.syringe,
              ecran: 'm5-prelevement',
              bouton: 'Salle de prélèvement',
              aller: c.aller),
        if (r.aSaisir > 0)
          _BlocRappel(
              titre: 'échantillon(s) reçu(s), résultat à renseigner',
              detail:
                  'L’échantillon est parvenu au laboratoire. Le prescripteur ne verra rien tant que le résultat n’est pas saisi PUIS validé biologiquement.',
              nb: r.aSaisir,
              ton: TonSigh.info,
              icone: LucideIcons.filePenLine,
              ecran: 'm5-resultats',
              bouton: 'Saisie des résultats',
              aller: c.aller),
        const NoteSigh(
            'Ce rappel s’affiche une fois par jour à l’ouverture de votre poste. Le détail reste disponible à tout moment depuis la cloche et depuis vos écrans.',
            ton: TonSigh.neutre),
      ]),
      pied: (fermer) => [BoutonSigh(libelle: 'J’ai pris connaissance', icone: LucideIcons.check, onPressed: fermer)],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return ListenableBuilder(
      listenable: tbaEcoute(c, ['demandesAnalyses', 'taches', 'produits']),
      builder: (context, _) {
        final d = tbaLaborantin(
            demandes: tbaActives(c, 'demandesAnalyses'), produits: tbaActives(c, 'produits'), analyses: c.magasin.referentiel('analyses'));
        final mois = parMois(const [], 'date', ref: c.aujourdhui).etiquettes;
        return TbaDash(
          alerte: tbaFileDuPoste(c, 'prelevement',
              titre: 'Prélèvements à réaliser',
              vide: 'Aucun prélèvement en attente.',
              action: 'Ouvrir les demandes',
              ecran: 'm5-demandes'),
          premier: d.premier,
          rapides: [
            tbaAccesRapides(c, const [
              ('m5-demandes', 'inbox', 'Demandes d’analyses', 'File de prélèvement'),
              ('m5-resultats', 'file-pen-line', 'Saisir un résultat', 'Validation biologique'),
              ('m5-reactifs', 'test-tube', 'Réactifs', 'Consommation et seuils'),
              ('m5-banque-sang', 'droplet', 'Banque de sang', 'Poches et donneurs'),
            ]),
            tbaCarte('Ce que vous faites ici — vos parcours', const ParcoursSigh(_parcours)),
          ],
          kpis: d.kpis,
          sections: [
            // Écart E920 : la maquette TIRE AU HASARD (C.seeded) ces valeurs — « Analyses les plus demandées » et « Analyses réalisées » ne sont
            // lues dans aucun registre. Portées fidèlement (même générateur, mêmes graines), dites ici et au rapport.
            tbaCarte('Analyses les plus demandées', ClassementTba([for (final a in d.analysesDemandees) (a.$1, a.$2)]),
                actions: [tbaLien(c, 'm5-catalogue', 'Catalogue des 48 analyses', 'list')]),
            tbaDeuxCartes(
              CarteSigh(
                  titre: 'Analyses réalisées (12 mois)',
                  child: GraphiqueLigne(etiquettes: mois, series: [SerieGraphique('Analyses', d.analysesRealisees, couleur: JetonsShell.info500)])),
              CarteSigh(
                  titre: 'Répartition par catégorie d’analyse',
                  child: GraphiqueAnneau(etiquettes: d.categories.etiquettes, valeurs: d.categories.series.first.donnees)),
            ),
          ],
        );
      },
    );
  }
}

class _BlocRappel extends StatelessWidget {
  const _BlocRappel(
      {required this.titre, required this.detail, required this.nb, required this.ton, required this.icone, required this.ecran, required this.bouton, required this.aller});
  final String titre, detail, ecran, bouton;
  final int nb;
  final TonSigh ton;
  final IconData icone;
  final void Function(String) aller;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: ton.fond50, border: Border.all(color: ton.bordure200), borderRadius: BorderRadius.circular(8)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: ton.bordure200.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(8)),
              child: Icon(icone, size: 20, color: ton.texteBadge)),
          const SizedBox(width: 12),
          Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${nombre(nb)} $titre', style: TextStyle(color: ton.texte900, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600)),
            Text(detail, style: TextStyle(color: ton.texteBadge, fontSize: 12, height: 16 / 12)),
          ])),
          const SizedBox(width: 12),
          BoutonSigh(
              libelle: bouton,
              taille: TailleBouton.sm,
              variante: VarianteBouton.secondaire,
              onPressed: () {
                Navigator.of(context).pop();
                aller(ecran);
              }),
        ]),
      );
}

const _parcours = [
  ParcoursTba('Recevoir un prélèvement', 'test-tube', 'Salle de prélèvement', 'Le patient a réglé, il peut être appelé.', [
    EtapeTba('Appeler le patient et prélever', ecran: 'm5-prelevement', detail: 'Le patient peut repartir dès le prélèvement fait.'),
    EtapeTba('Acheminer l’échantillon avec son bon', ecran: 'm5-prelevement'),
    EtapeTba('Marquer l’échantillon reçu', ecran: 'm5-prelevement', detail: 'Aucun résultat ne se saisit sur un prélèvement non reçu.'),
  ]),
  ParcoursTba('Rendre un résultat', 'file-check-2', 'Saisir', 'Les deux validations, dans l’ordre.', [
    EtapeTba('Saisir les variables',
        ecran: 'm5-resultats', detail: 'Unités et valeurs de référence pré-insérées ; les bornes suppléées sont marquées.'),
    EtapeTba('Valider TECHNIQUEMENT', ecran: 'm5-resultats', detail: 'Atteste la saisie. Le prescripteur ne voit toujours rien.'),
    EtapeTba('Valider BIOLOGIQUEMENT',
        ecran: 'm5-resultats', detail: 'C’est vous qui avez prélevé, c’est vous qui validez : la chaîne ne se rompt pas.'),
    EtapeTba('Le prescripteur lit', poste: 'Consultation'),
    EtapeTba('Remettre au patient externe', ecran: 'm5-resultats'),
  ]),
  ParcoursTba('Corriger un résultat rendu', 'rotate-ccw', 'Rectifier', 'Une erreur est découverte après validation.', [
    EtapeTba('Rectifier avec motif obligatoire', ecran: 'm5-resultats', detail: 'La version lue par le médecin est conservée ; la nouvelle est numérotée.'),
    EtapeTba('Le prescripteur est notifié', poste: 'Consultation', detail: 'Il doit savoir que ce qu’il a lu a changé.'),
  ]),
  ParcoursTba('Tenir les réactifs', 'flask-conical', 'Réactifs', 'Rupture et péremption.', [
    EtapeTba('Vérifier les seuils',
        ecran: 'm5-reactifs', detail: 'Un seuil non fixé n’est pas un seuil de zéro : aucune alerte n’est possible.'),
    EtapeTba('Demander le réapprovisionnement', poste: 'Stock'),
  ]),
];
