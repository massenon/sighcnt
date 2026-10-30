import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'besoins_commun.dart';

/// Le bon de commande imprimé : le total est celui de SES lignes, refait à l'impression — la commande engage la clinique.
PieceA4 pieceCommande(Fiche cm,
    {required String utilisateur,
    required DateTime edite,
    required String reference}) {
  return PieceA4(
    titre: 'Bon de commande',
    sousTitre: '${cm['reference']}',
    reference: reference,
    utilisateur: utilisateur,
    edite: edite,
    cartouche: [
      ('Référence', '${cm['reference']}'),
      ('Date', dateDe(cm['date'])),
      ('Fournisseur', '${cm['fournisseurNom'] ?? ''}'),
      ('Délai de livraison', '${cm['delaiLivraison'] ?? '—'} jours'),
      ('Statut', libelleCommande(cm['statutCommande'])),
      ('Validée par', '${cm['valideePar'] ?? 'En attente'}'),
    ],
    blocs: [
      BlocTableau(TableauEtat(colonnes: [
        ColonneEtat(libelle: 'Désignation', valeur: (l) => l['produit']),
        ColonneEtat(libelle: 'Unité', valeur: (l) => l['unite']),
        ColonneEtat(libelle: 'Quantité', valeur: (l) => l['quantite'], droite: true),
        ColonneEtat(
            libelle: 'Prix unitaire',
            valeur: (l) => m(l['prixUnitaire']),
            droite: true),
        ColonneEtat(
            libelle: 'Montant',
            valeur: (l) => m(l['montant']),
            droite: true,
            somme: (l) => n(l['montant'])),
      ], lignes: lignesDeBonAchat(cm))),
    ],
    signatures: const [
      Signature('Le Gestionnaire de Stock', nom: 'MAMAN Zoukanéri'),
      Signature('La Directrice Administrative',
          nom: directriceAdministrative, mention: 'Bon pour commande (RG-04)'),
    ],
  );
}

/// `m7-commandes` — « Bons de commande » : RG-04, toute commande d'achat de stock gros est validée par la Directrice Administrative AVANT transmission
/// au fournisseur. Les règles sont dans `packages/domaine` (`achats/commandes.dart`).
class EcranCommandes extends StatelessWidget with EcranMaquette {
  const EcranCommandes({super.key});

  @override
  String get titre => 'Bons de commande';

  @override
  String get description =>
      'Commandes fournisseurs, validation par la Directrice Administrative et transmission.';

  @override
  String get regle =>
      'RG-04 — toute commande d’achat de stock gros doit être validée par la Directrice Administrative avant transmission au fournisseur.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('commandes');
    return ListenableBuilder(
      listenable: col,
      builder: (context, _) {
        final actives = col.actives;
        final attente = commandesEnAttente(actives);
        final k = indicateursCommandes(actives);
        final fournisseurs = optionsFournisseurs(c.magasin);
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (attente.isNotEmpty) ...[
                NoteSigh(
                    '${attente.length} commande(s) en attente de validation par la Directrice Administrative. Aucune transmission au fournisseur n’est possible avant cette validation (RG-04).',
                    ton: TonSigh.attention,
                    icone: LucideIcons.shieldAlert),
                const SizedBox(height: 16),
              ],
              KpiGrilleSigh(kpis: [
                KpiSigh(
                    libelle: 'Commandes enregistrées',
                    valeur: nombre(k.enregistrees),
                    icone: LucideIcons.truck),
                KpiSigh(
                    libelle: 'En attente de validation',
                    valeur: nombre(k.enAttente),
                    icone: LucideIcons.hourglass,
                    ton: TonSigh.attention),
                KpiSigh(
                    libelle: 'Montant commandé',
                    valeur: money(k.montant),
                    icone: LucideIcons.wallet,
                    ton: TonSigh.info),
                KpiSigh(
                    libelle: 'Livrées',
                    valeur: nombre(k.livrees),
                    icone: LucideIcons.circleCheck,
                    ton: TonSigh.succes),
              ]),
              const SizedBox(height: 16),
              TableauSigh(
                titre: 'Bons de commande',
                lignes: actives,
                taillePage: 12,
                triInitial: 'date',
                sensInitial: 'desc',
                nomExport: 'bons-commande',
                filtres: [
                  FiltreTableau(nom: 'statutCommande', libelle: 'Statut', options: [
                    for (final s in statutsCommande) OptionChamp(s.valeur, s.libelle)
                  ]),
                  FiltreTableau(
                      nom: 'fournisseur',
                      libelle: 'Fournisseur',
                      options: fournisseurs),
                ],
                actions: [
                  if (c.droit.editer)
                    BoutonSigh(
                        libelle: 'Nouvelle commande',
                        icone: LucideIcons.plus,
                        taille: TailleBouton.sm,
                        onPressed: () => _ouvrir(context, null)),
                ],
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
                      valeur: (x) => lignesDeBonAchat(x).length,
                      texte: (x) => '${lignesDeBonAchat(x).length}'),
                  ColonneTableau(
                      cle: 'montant',
                      libelle: 'Montant',
                      droite: true,
                      texte: (x) => m(x['montant']),
                      rendu: (_, x) => Text(m(x['montant']),
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600))),
                  ColonneTableau(
                      cle: 'delaiLivraison',
                      libelle: 'Délai',
                      droite: true,
                      texte: (x) => '${x['delaiLivraison'] ?? '—'} j'),
                  ColonneTableau(
                      cle: 'statutCommande',
                      libelle: 'Statut',
                      texte: (x) => libelleCommande(x['statutCommande']),
                      rendu: (_, x) => BadgeSigh(
                          libelleCommande(x['statutCommande']),
                          ton: tonAchat(toneCommande(x['statutCommande'])))),
                  ColonneTableau(
                      cle: 'valideePar',
                      libelle: 'Validée par (RG-04)',
                      texte: (x) => '${x['valideePar'] ?? 'En attente'}',
                      rendu: (_, x) => x['valideePar'] != null
                          ? Text('${x['valideePar']}',
                              style: const TextStyle(fontSize: 14))
                          : const Text('En attente',
                              style: TextStyle(
                                  color: JetonsShell.slate400, fontSize: 12))),
                ],
                alClicLigne: (x) => _consulter(context, x),
                actionsLigne: (ctx, x) => [
                  BoutonIcone(
                      icone: LucideIcons.eye,
                      libelle: 'Consulter',
                      onPressed: () => _consulter(context, x)),
                  // LA VALIDATION RG-04 EST L'ACTE DE LA DIRECTRICE ADMINISTRATIVE — mais la maquette l'offre à tout profil qui écrit dans M7 (E72).
                  if (x['statutCommande'] == 'attente_validation' && c.droit.editer)
                    BoutonIcone(
                        icone: LucideIcons.shieldCheck,
                        libelle: 'Valider (DA)',
                        onPressed: () => _valider(context, x)),
                  BoutonIcone(
                      icone: LucideIcons.printer,
                      libelle: 'Imprimer',
                      onPressed: () => _imprimer(context, x)),
                  if (c.droit.editer)
                    BoutonIcone(
                        icone: LucideIcons.pencil,
                        libelle: 'Modifier',
                        onPressed: () => _ouvrir(context, x)),
                ],
              ),
            ]);
      },
    );
  }
}

void _imprimer(BuildContext ctx, Fiche cm) => imprimerPiece(
    ctx,
    (c) => pieceCommande(cm,
        utilisateur: c.utilisateur, edite: c.aujourdhui, reference: refEtat(c)));

Future<void> _valider(BuildContext ecran, Fiche cm) async {
  final c = ContexteEcran.of(ecran);
  final ok = await confirmerSigh(ecran,
      titre: 'Valider la commande ${cm['reference']} ?',
      message:
          'En application de la règle RG-04, cette validation autorise la transmission au fournisseur ${cm['fournisseurNom']} pour un montant de ${money(cm['montant'])}. L’opération est journalisée.',
      libelleOk: 'Valider la commande');
  if (!ok || !ecran.mounted) return;
  final annuler = c.magasin
      .collection('commandes')
      .mettreAJour(cm['id'], validationCommande(jour: iso(c.aujourdhui)));
  dire(ecran, 'Commande validée par la Directrice Administrative.',
      type: TypeToast.succes, annuler: annuler);
}

void _consulter(BuildContext ecran, Fiche cm) {
  final c = ContexteEcran.of(ecran);
  afficherTiroir<void>(ecran,
      titre: 'Commande ${cm['reference']}',
      sousTitre: '${cm['fournisseurNom']} — ${dateDe(cm['date'])}',
      largeurMax: 768,
      corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        DescListeSigh([
          ('Référence', cm['reference']),
          ('Date', dateDe(cm['date'])),
          ('Fournisseur', cm['fournisseurNom']),
          ('Délai de livraison', '${cm['delaiLivraison'] ?? '—'} jours'),
          ('Montant', money(cm['montant'])),
          (
            'Statut',
            BadgeSigh(libelleCommande(cm['statutCommande']),
                ton: tonAchat(toneCommande(cm['statutCommande'])))
          ),
          ('Validée par (RG-04)', cm['valideePar'] ?? 'En attente'),
          (
            'Date de validation',
            cm['dateValidation'] != null ? dateDe(cm['dateValidation']) : '—'
          ),
        ]),
        if (cm['statutCommande'] == 'attente_validation') ...[
          const SizedBox(height: 16),
          const NoteSigh(
              'Cette commande ne peut être transmise au fournisseur tant que la Directrice Administrative ne l’a pas validée (RG-04).',
              ton: TonSigh.attention,
              icone: LucideIcons.shieldAlert),
        ],
        const SizedBox(height: 16),
        CarteSigh(
            titre: 'Articles commandés',
            sansRemplissage: true,
            child: MiniTableauSigh(colonnes: [
              ColonneMini('Article', (l) => '${l['produit']}'),
              ColonneMini('Quantité', (l) => '${l['quantite']} ${l['unite']}',
                  droite: true),
              ColonneMini('P.U.', (l) => m(l['prixUnitaire']), droite: true),
              ColonneMini('Montant', (l) => m(l['montant']), droite: true),
            ], lignes: lignesDeBonAchat(cm))),
      ]),
      pied: (fermer) => [
            if (cm['statutCommande'] == 'attente_validation' && c.droit.editer)
              BoutonSigh(
                  libelle: 'Valider (DA)',
                  icone: LucideIcons.shieldCheck,
                  variante: VarianteBouton.succes,
                  onPressed: () {
                    fermer();
                    _valider(ecran, cm);
                  }),
            BoutonSigh(
                libelle: 'Imprimer',
                icone: LucideIcons.printer,
                onPressed: () => _imprimer(ecran, cm)),
          ]);
}

void _ouvrir(BuildContext ecran, Fiche? record) {
  afficherModale<void>(ecran,
      titre: record != null
          ? 'Modifier la commande ${record['reference']}'
          : 'Nouveau bon de commande',
      taille: TailleModale.xl,
      corps: _ModaleCommande(
          contexte: ContexteEcran.of(ecran), ecran: ecran, record: record),
      pied: null);
}

class _ModaleCommande extends StatefulWidget {
  const _ModaleCommande(
      {required this.contexte, required this.ecran, required this.record});
  final ContexteEcran contexte;
  final BuildContext ecran;
  final Fiche? record;
  @override
  State<_ModaleCommande> createState() => _EtatModaleCommande();
}

class _EtatModaleCommande extends State<_ModaleCommande> {
  late final ControleurFormulaire _f;
  late final List<Fiche> _lignes;
  late final List<Fiche> _produits;

  @override
  void initState() {
    super.initState();
    final c = widget.contexte;
    _lignes = widget.record == null ? [] : lignesDeBonAchat(widget.record!);
    _produits = articlesDuReferentiel(c.magasin);
    _f = ControleurFormulaire([
      const ChampDef(
          nom: 'date',
          libelle: 'Date de la commande',
          type: TypeChamp.date,
          requis: true),
      ChampDef(
          nom: 'fournisseur',
          libelle: 'Fournisseur',
          type: TypeChamp.select,
          requis: true,
          options: optionsFournisseurs(c.magasin)),
      ChampDef(
          nom: 'statutCommande',
          libelle: 'Statut',
          type: TypeChamp.select,
          requis: true,
          options: [
            for (final s in statutsCommande) OptionChamp(s.valeur, s.libelle)
          ]),
      const ChampDef(
          nom: 'observations',
          libelle: 'Observations',
          type: TypeChamp.textarea,
          lignes: 2,
          col: ColChamp.plein),
    ], widget.record ?? {'date': iso(c.aujourdhui), 'statutCommande': 'brouillon'});
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
    final col = c.magasin.collection('commandes');
    final Fiche res;
    try {
      res = commandeEnregistree(
          saisie: v,
          lignes: _lignes,
          existante: widget.record,
          fournisseurs: c.magasin.collection('fournisseurs').actives,
          commandes: col.toutes,
          jour: iso(c.aujourdhui));
    } on RefusAchat catch (e) {
      dire(widget.ecran, e.motif, type: TypeToast.erreur);
      return;
    }
    final VoidCallback annuler;
    final String message;
    if (widget.record != null) {
      annuler = col.mettreAJour(widget.record!['id'], res);
      message = 'Commande mise à jour.';
    } else {
      final ins = col.inserer({...res, 'statut': 'actif'}, prefixe: 'COM');
      annuler = ins.annuler;
      message = 'Commande créée — ${res['reference']}';
    }
    fermer();
    dire(widget.ecran, message, type: TypeToast.succes, annuler: annuler);
  }

  @override
  Widget build(BuildContext context) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FormulaireSigh(controleur: _f),
            const SizedBox(height: 16),
            EditeurLignes(
                ecran: widget.ecran,
                produits: _produits,
                lignes: _lignes,
                commande: true,
                alChange: () {}),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              BoutonSigh(
                  libelle: 'Annuler',
                  variante: VarianteBouton.secondaire,
                  onPressed: () => Navigator.of(context).pop()),
              const SizedBox(width: 8),
              BoutonSigh(
                  libelle:
                      widget.record != null ? 'Enregistrer' : 'Créer la commande',
                  icone: LucideIcons.save,
                  onPressed: () =>
                      _enregistrer(() => Navigator.of(context).pop())),
            ]),
          ]);
}
