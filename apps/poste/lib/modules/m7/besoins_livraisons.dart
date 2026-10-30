import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'besoins_commun.dart';

Widget _badgeReception(Object? statut) => statut == 'conforme'
    ? const BadgeSigh('Conforme', ton: TonSigh.succes)
    : const BadgeSigh('Écart constaté', ton: TonSigh.danger);

List<String> _controleurs(Fiche l) => [
      for (final x in (l['controlePar'] as List? ?? const [])) '$x'
    ];

/// Le bordereau de livraison imprimé : quantités commandées, livrées, écart, total refait depuis les lignes, trois signatures.
PieceA4 pieceLivraison(Fiche l,
    {required String utilisateur,
    required DateTime edite,
    required String reference}) {
  return PieceA4(
    titre: 'Bon de livraison',
    sousTitre: '${l['reference']} — ${l['fournisseurNom']}',
    reference: reference,
    utilisateur: utilisateur,
    edite: edite,
    cartouche: [
      ('N° bordereau', '${l['reference']}'),
      ('Commande', '${l['commandeRef'] ?? ''}'),
      ('Fournisseur', '${l['fournisseurNom'] ?? ''}'),
      ('Date', dateDe(l['date'])),
      ('Contrôlé par', _controleurs(l).join(', ')),
      ('Réception', l['statutReception'] == 'conforme' ? 'Conforme' : 'Écart constaté'),
    ],
    blocs: [
      BlocTableau(TableauEtat(colonnes: [
        ColonneEtat(libelle: 'Désignation', valeur: (x) => x['produit']),
        ColonneEtat(libelle: 'Unité', valeur: (x) => x['unite']),
        ColonneEtat(libelle: 'Qté commandée', valeur: (x) => x['quantite'], droite: true),
        ColonneEtat(libelle: 'Qté livrée', valeur: (x) => x['quantiteLivree'], droite: true),
        ColonneEtat(libelle: 'Écart', valeur: (x) => x['ecart'] ?? 0, droite: true),
        ColonneEtat(
            libelle: 'Montant',
            valeur: (x) => m(x['montant']),
            droite: true,
            somme: (x) => n(x['montant'])),
      ], lignes: lignesDeBon(l))),
    ],
    signatures: const [
      Signature('Le Livreur', mention: 'Fournisseur'),
      Signature('Le Gestionnaire de Stock', nom: 'MAMAN Zoukanéri'),
      Signature('Le Contrôleur', mention: 'Vérification contradictoire'),
    ],
  );
}

/// `m7-livraisons` — « Bons de livraison » : bordereaux fournisseurs rapprochés des bons de commande. Le bordereau se corrige (une date mal saisie, un
/// contrôleur oublié) et s'archive — jamais supprimé (RG-14). Ceux de la réception (`m7-receptions`) naissent avec leurs lignes ; la création manuelle
/// n'en porte pas (E78 corrigé : les contrôleurs sont saisis en texte et lus en liste).
class EcranLivraisons extends StatelessWidget with EcranMaquette {
  const EcranLivraisons({super.key});

  @override
  String get titre => 'Bons de livraison';

  @override
  String get description =>
      'Bordereaux de livraison fournisseurs, rapprochés des bons de commande correspondants.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('livraisons');
    return ListenableBuilder(
      listenable: col,
      builder: (context, _) {
        final actives = col.actives;
        final k = indicateursLivraisons(actives);
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              KpiGrilleSigh(kpis: [
                KpiSigh(
                    libelle: 'Bons de livraison',
                    valeur: nombre(k.total),
                    icone: LucideIcons.packageCheck),
                KpiSigh(
                    libelle: 'Réceptions conformes',
                    valeur: nombre(k.conformes),
                    icone: LucideIcons.circleCheck,
                    ton: TonSigh.succes),
                KpiSigh(
                    libelle: 'Avec écart',
                    valeur: nombre(k.avecEcart),
                    icone: LucideIcons.triangleAlert,
                    ton: TonSigh.danger),
                KpiSigh(
                    libelle: 'Valeur livrée',
                    valeur: money(k.valeur),
                    icone: LucideIcons.wallet,
                    ton: TonSigh.info),
              ]),
              const SizedBox(height: 16),
              TableauSigh(
                titre: 'Bons de livraison',
                lignes: actives,
                taillePage: 12,
                triInitial: 'date',
                sensInitial: 'desc',
                nomExport: 'bons-livraison',
                filtres: [
                  FiltreTableau(
                      nom: 'fournisseur',
                      libelle: 'Fournisseur',
                      options: optionsFournisseurs(c.magasin)),
                  const FiltreTableau(
                      nom: 'statutReception',
                      libelle: 'Réception',
                      options: [
                        OptionChamp('conforme', 'Conforme'),
                        OptionChamp('ecart', 'Avec écart'),
                      ]),
                ],
                actions: [
                  if (c.droit.editer)
                    BoutonSigh(
                        libelle: 'Nouveau',
                        icone: LucideIcons.plus,
                        taille: TailleBouton.sm,
                        onPressed: () => _formulaire(context, null)),
                ],
                colonnes: [
                  ColonneTableau(
                      cle: 'reference',
                      libelle: 'N° BL',
                      sansCoupure: true,
                      texte: (l) => '${l['reference']}',
                      rendu: (_, l) => refMono(l['reference'])),
                  ColonneTableau(
                      cle: 'commandeRef',
                      libelle: 'Commande',
                      sansCoupure: true,
                      texte: (l) => '${l['commandeRef'] ?? ''}',
                      rendu: (_, l) => refMono(l['commandeRef'],
                          gras: false, couleur: JetonsShell.slate500)),
                  ColonneTableau(
                      cle: 'date',
                      libelle: 'Date',
                      sansCoupure: true,
                      texte: (l) => dateDe(l['date'])),
                  const ColonneTableau(cle: 'fournisseurNom', libelle: 'Fournisseur'),
                  ColonneTableau(
                      cle: 'nbLignes',
                      libelle: 'Articles',
                      droite: true,
                      valeur: (l) => lignesDeBon(l).length,
                      texte: (l) => '${lignesDeBon(l).length}'),
                  ColonneTableau(
                      cle: 'montant',
                      libelle: 'Montant',
                      droite: true,
                      texte: (l) => m(l['montant'])),
                  ColonneTableau(
                      cle: 'statutReception',
                      libelle: 'Réception',
                      texte: (l) => l['statutReception'] == 'conforme'
                          ? 'Conforme'
                          : 'Écart constaté',
                      rendu: (_, l) => _badgeReception(l['statutReception'])),
                ],
                alClicLigne: (l) => _consulter(context, l),
                // Le bordereau se corrige : une date mal saisie, un contrôleur oublié ou un écart constaté après coup ne doivent pas obliger à ressaisir.
                actionsLigne: (ctx, l) => [
                  BoutonIcone(
                      icone: LucideIcons.printer,
                      libelle: 'Imprimer',
                      onPressed: () => _imprimer(context, l)),
                  if (c.droit.editer)
                    BoutonIcone(
                        icone: LucideIcons.pencil,
                        libelle: 'Modifier',
                        onPressed: () => _formulaire(context, l)),
                  if (c.droit.annuler)
                    BoutonIcone(
                        icone: LucideIcons.archive,
                        libelle: 'Archiver',
                        onPressed: () => _archiver(context, l)),
                ],
              ),
            ]);
      },
    );
  }
}

void _imprimer(BuildContext ctx, Fiche l) => imprimerPiece(
    ctx,
    (c) => pieceLivraison(l,
        utilisateur: c.utilisateur, edite: c.aujourdhui, reference: refEtat(c)));

void _consulter(BuildContext ecran, Fiche l) {
  afficherTiroir<void>(ecran,
      titre: 'Bon de livraison ${l['reference']}',
      sousTitre: '${l['fournisseurNom']} — ${dateDe(l['date'])}',
      largeurMax: 768,
      corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        DescListeSigh([
          ('N° bordereau', l['reference']),
          ('Commande rattachée', l['commandeRef']),
          ('Fournisseur', l['fournisseurNom']),
          ('Date de livraison', dateDe(l['date'])),
          ('Montant', money(l['montant'])),
          ('Contrôlé par', _controleurs(l).join(', ')),
          ('Réception', _badgeReception(l['statutReception'])),
        ]),
        const SizedBox(height: 16),
        CarteSigh(
            titre: 'Articles livrés',
            sansRemplissage: true,
            child: MiniTableauSigh(colonnes: [
              ColonneMini('Article', (x) => '${x['produit']}'),
              ColonneMini('Commandé', (x) => '${x['quantite'] ?? ''}', droite: true),
              ColonneMini('Livré', (x) => '${x['quantiteLivree'] ?? ''}', droite: true),
              ColonneMini('Écart', (x) => '${x['ecart'] ?? ''}',
                  droite: true,
                  rendu: (x) => n(x['ecart']) != 0
                      ? Text('${x['ecart']}',
                          style: const TextStyle(
                              color: JetonsShell.danger600,
                              fontWeight: FontWeight.w600))
                      : const BadgeSigh('OK', ton: TonSigh.succes)),
              ColonneMini('Montant', (x) => m(x['montant']), droite: true),
            ], lignes: lignesDeBon(l))),
      ]),
      pied: (_) => [
            BoutonSigh(
                libelle: 'Imprimer',
                icone: LucideIcons.printer,
                onPressed: () => _imprimer(ecran, l))
          ]);
}

Future<void> _archiver(BuildContext ecran, Fiche l) async {
  final c = ContexteEcran.of(ecran);
  final motif = await confirmerAvecMotif(ecran,
      titre: 'Archiver cet enregistrement ?',
      message:
          'Archivage logique (RG-14) : la donnée reste consultable et l’opération est annulable.',
      libelleOk: 'Archiver',
      dangereux: true);
  if (motif == null || !ecran.mounted) return;
  final col = c.magasin.collection('livraisons');
  col.mettreAJour(l['id'], {'motifArchivage': motif});
  final annuler = col.archiver(l['id']);
  dire(ecran, 'Enregistrement archivé.',
      type: TypeToast.succes, annuler: annuler);
}

void _formulaire(BuildContext ecran, Fiche? record) {
  afficherModale<void>(ecran,
      titre: record != null ? 'Modifier l’enregistrement' : 'Nouveau bon de livraison',
      sousTitre: record != null
          ? '${record['reference']}'
          : 'Les champs marqués d’un astérisque sont obligatoires.',
      taille: TailleModale.lg,
      corps: _ModaleLivraison(
          contexte: ContexteEcran.of(ecran), ecran: ecran, record: record),
      pied: null);
}

class _ModaleLivraison extends StatefulWidget {
  const _ModaleLivraison(
      {required this.contexte, required this.ecran, required this.record});
  final ContexteEcran contexte;
  final BuildContext ecran;
  final Fiche? record;
  @override
  State<_ModaleLivraison> createState() => _EtatModaleLivraison();
}

class _EtatModaleLivraison extends State<_ModaleLivraison> {
  late final ControleurFormulaire _f;

  @override
  void initState() {
    super.initState();
    final c = widget.contexte;
    final r = widget.record;
    _f = ControleurFormulaire([
      const ChampDef(nom: 'commandeRef', libelle: 'Commande rattachée', requis: true),
      ChampDef(
          nom: 'fournisseur',
          libelle: 'Fournisseur',
          type: TypeChamp.select,
          requis: true,
          options: optionsFournisseurs(c.magasin)),
      const ChampDef(
          nom: 'date',
          libelle: 'Date de livraison',
          type: TypeChamp.date,
          requis: true),
      const ChampDef(
          nom: 'montant', libelle: 'Montant livré (FCFA)', type: TypeChamp.nombre),
      const ChampDef(
          nom: 'statutReception',
          libelle: 'Réception',
          type: TypeChamp.select,
          requis: true,
          options: [
            OptionChamp('conforme', 'Conforme'),
            OptionChamp('ecart', 'Écart constaté'),
          ]),
      const ChampDef(
          nom: 'controlePar', libelle: 'Contrôlé par', col: ColChamp.plein),
    ],
        r == null
            ? {'date': iso(c.aujourdhui), 'statutReception': 'conforme'}
            : {
                ...r,
                // Les contrôleurs sont une liste au magasin, un texte au formulaire.
                'controlePar': _controleurs(r).join(','),
                'montant': r['montant'] == null ? '' : '${r['montant']}',
              });
  }

  @override
  void dispose() {
    _f.dispose();
    super.dispose();
  }

  void _enregistrer(VoidCallback fermer) {
    final c = widget.contexte;
    final v = _f.valider();
    if (v == null) {
      dire(widget.ecran, 'Le formulaire comporte des erreurs.',
          type: TypeToast.erreur);
      return;
    }
    final col = c.magasin.collection('livraisons');
    if (widget.record != null) {
      final annuler =
          col.mettreAJour(widget.record!['id'], livraisonModifiee(v));
      fermer();
      dire(widget.ecran, 'Modifications enregistrées.',
          type: TypeToast.succes, annuler: annuler);
    } else {
      final res = livraisonCreee(
          saisie: v,
          fournisseurs: c.magasin.collection('fournisseurs').actives,
          livraisons: col.toutes);
      final ins = col.inserer({...res, 'statut': 'actif'}, prefixe: 'LIV');
      fermer();
      dire(widget.ecran, 'Bon de livraison créé.',
          type: TypeToast.succes, annuler: ins.annuler);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FormulaireSigh(controleur: _f),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              BoutonSigh(
                  libelle: 'Annuler',
                  variante: VarianteBouton.secondaire,
                  onPressed: () => Navigator.of(context).pop()),
              const SizedBox(width: 8),
              BoutonSigh(
                  libelle: widget.record != null ? 'Enregistrer' : 'Créer',
                  icone: widget.record != null ? LucideIcons.save : LucideIcons.plus,
                  onPressed: () =>
                      _enregistrer(() => Navigator.of(context).pop())),
            ]),
          ]);
}
