import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_domaine/src/stock/delivrance.dart' as dv show LigneStock;

import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'flux_commun.dart';

/// `m6-dispensation` — « Dispensation ». AUCUNE dispensation manuelle (décision du 02/09/2026) : toute délivrance naît d'une ORDONNANCE du médecin passée en
/// CAISSE ; le justificatif de sortie est le numéro d'ordonnance (RG-03). L'écran est le REGISTRE des délivrances faites ; le geste se fait sur la file de la pharmacie,
/// débloquée par l'encaissement. La commande de création directe est RETIRÉE, pas grisée. RG-02 — prix d'achat sans marge ; RG-05 — FEFO.
///
/// La délivrance est le moteur `delivrerOrdonnance` du domaine (rejoué sur les vecteurs de `PR.delivrer`) : le stock de détail ne devient jamais négatif, une ligne
/// insuffisante bloque la délivrance entière, le refus nomme l'article.
class EcranDispensation extends StatelessWidget with EcranMaquette {
  const EcranDispensation({super.key});

  @override
  String get titre => 'Dispensation';

  @override
  String get description =>
      'Délivrance des médicaments aux patients : décompte du stock de détail et rattachement à la facturation.';

  @override
  String get regle =>
      'Aucune dispensation manuelle (décision du 02/09/2026) : toute délivrance naît d’une ordonnance du médecin, passée en caisse — le justificatif de sortie est le numéro d’ordonnance (RG-03). Cet écran est le REGISTRE des délivrances faites ; le geste se fait sur la file de la pharmacie, débloquée par l’encaissement. RG-02 — prix d’achat sans marge ; RG-05 — FEFO.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final mag = c.magasin;
    final col = mag.collection('dispensations');
    return ListenableBuilder(
      listenable: Listenable.merge([col, mag.collection('produits')]),
      builder: (context, _) {
        final k = kpisDispensation(col.actives, mag.collection('produits').actives);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          FileAttenteSigh(
            type: 'dispensation',
            titre: 'Ordonnances à délivrer',
            vide: 'Aucune ordonnance en attente de délivrance.',
            icone: LucideIcons.pill,
            action: 'Délivrer',
            surAction: (ctx, tache) => _ouvrirDelivrance(ctx, c, tache),
          ),
          const SizedBox(height: 16),
          KpiGrilleSigh(kpis: [
            KpiSigh(
                libelle: 'Dispensations enregistrées',
                valeur: nombre(k.dispensations),
                icone: LucideIcons.handHeart,
                ton: TonSigh.navy),
            KpiSigh(
                libelle: 'Valeur dispensée',
                valeur: money(k.valeur),
                icone: LucideIcons.coins,
                ton: TonSigh.succes),
            KpiSigh(
                libelle: 'Références en pharmacie',
                valeur: nombre(k.references),
                icone: LucideIcons.pill,
                ton: TonSigh.info),
            KpiSigh(
                libelle: 'Ruptures en pharmacie',
                valeur: nombre(k.ruptures),
                icone: LucideIcons.circleX,
                ton: TonSigh.danger),
          ]),
          const SizedBox(height: 16),
          TableauSigh(
            titre: 'Historique des dispensations',
            lignes: col.actives,
            taillePage: 12,
            triInitial: 'date',
            sensInitial: 'desc',
            nomExport: 'dispensations',
            messageVide: 'Aucune dispensation enregistrée.',
            // La commande de création directe est RETIRÉE : la seule porte est la file des délivrances.
            actions: [
              BoutonSigh(
                  libelle: 'File des délivrances (ordonnances encaissées)',
                  icone: LucideIcons.listOrdered,
                  taille: TailleBouton.sm,
                  onPressed: () => c.aller('m6-pharmacie-externe')),
            ],
            colonnes: [
              ColonneTableau(
                  cle: 'reference',
                  libelle: 'N°',
                  sansCoupure: true,
                  texte: (d) => '${d['reference']}',
                  rendu: (_, d) => cellMono('${d['reference']}')),
              ColonneTableau(
                  cle: 'date',
                  libelle: 'Date',
                  sansCoupure: true,
                  texte: (d) => dateDe(d['date'])),
              const ColonneTableau(cle: 'patient', libelle: 'Patient'),
              ColonneTableau(
                  cle: 'nbLignes',
                  libelle: 'Produits',
                  droite: true,
                  valeur: (d) => ((d['lignes'] as List?) ?? const []).length,
                  texte: (d) => '${((d['lignes'] as List?) ?? const []).length}'),
              ColonneTableau(
                  cle: 'montant',
                  libelle: 'Montant',
                  droite: true,
                  texte: (d) => m(d['montant'])),
              const ColonneTableau(cle: 'dispensePar', libelle: 'Dispensé par'),
            ],
            alClicLigne: (d) => _tiroir(context, d),
            actionsLigne: (ctx, d) => [
              BoutonIcone(
                  icone: LucideIcons.printer,
                  libelle: 'Imprimer',
                  onPressed: () => _imprimer(ctx, d)),
            ],
          ),
        ]);
      },
    );
  }

  List<Fiche> _lignes(Fiche d) => [
        for (final l in (d['lignes'] as List? ?? const [])) (l as Map).cast<String, Object?>()
      ];

  void _tiroir(BuildContext ctx, Fiche d) => afficherTiroir<void>(ctx,
      titre: 'Dispensation ${d['reference']}',
      sousTitre: '${d['patient']} — ${dateDe(d['date'])}',
      corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        DescListeSigh([
          ('Référence', d['reference']),
          ('Patient', d['patient']),
          ('Dossier', d['patientCode']),
          ('Date', dateDe(d['date'])),
          ('Dispensé par', d['dispensePar']),
          ('Montant', money(d['montant'])),
        ]),
        const SizedBox(height: 16),
        CarteSigh(
            titre: 'Produits délivrés',
            sansRemplissage: true,
            child: MiniTableauSigh(colonnes: [
              ColonneMini('Produit', (l) => '${l['produit'] ?? ''}'),
              ColonneMini('Quantité', (l) => '${l['quantite']} ${l['unite']}', droite: true),
              ColonneMini('P.U.', (l) => m(l['prix']), droite: true),
              ColonneMini('Montant', (l) => m(n(l['quantite']) * n(l['prix'])), droite: true),
            ], lignes: _lignes(d))),
      ]),
      pied: (_) => [
            BoutonSigh(
                libelle: 'Imprimer le bon',
                icone: LucideIcons.printer,
                onPressed: () => _imprimer(ctx, d)),
          ]);

  /// Le bon de sortie de stock : le total est REFAIT depuis les lignes imprimées — le bon ne peut plus annoncer un montant que son propre détail ne justifie pas.
  PieceA4 pieceBon(Fiche d,
          {required String utilisateur, required DateTime edite, required String reference}) =>
      PieceA4(
        titre: 'Bon de sortie de stock — dispensation',
        sousTitre: '${d['reference']}',
        reference: reference,
        utilisateur: utilisateur,
        edite: edite,
        cartouche: [
          ('Patient', '${d['patient']}'),
          ('Dossier', '${d['patientCode']}'),
          ('Date', dateDe(d['date'])),
          ('Dispensé par', '${d['dispensePar']}'),
          ('Référence', '${d['reference']}'),
          ('Stock', 'Pharmacie de détail'),
        ],
        tableaux: [
          TableauEtat(colonnes: [
            ColonneEtat(libelle: 'Produit', valeur: (l) => l['produit']),
            ColonneEtat(libelle: 'Unité', valeur: (l) => l['unite']),
            ColonneEtat(libelle: 'Quantité', valeur: (l) => l['quantite'], droite: true),
            ColonneEtat(libelle: 'Prix unitaire', valeur: (l) => m(l['prix']), droite: true),
            ColonneEtat(
                libelle: 'Montant',
                valeur: (l) => m(n(l['quantite']) * n(l['prix'])),
                droite: true,
                somme: (l) => n(l['quantite']) * n(l['prix'])),
          ], lignes: _lignes(d)),
        ],
        signatures: [
          Signature('Le Pharmacien', nom: '${d['dispensePar']}'),
          const Signature('Le Patient', mention: 'Réception'),
        ],
      );

  Future<void> _imprimer(BuildContext ctx, Fiche d) {
    final c = ContexteEcran.of(ctx);
    return afficherApercu(
        ctx,
        pieceBon(d,
            utilisateur: c.utilisateur,
            edite: c.aujourdhui,
            reference: PieceA4.reference_(c.aujourdhui, ImpressionPoste.prochainNumero())));
  }

  /// Le détail d'une ordonnance à servir : ce que la pharmacie a en rayon pour chaque ligne, et si la délivrance est possible (RG-03).
  void _ouvrirDelivrance(BuildContext ecran, ContexteEcran c, Fiche tache) {
    final mag = c.magasin;
    final ord = mag.collection('ordonnances').parId(tache['ordonnanceId']);
    if (ord == null) {
      ToastsSigh.afficher(ecran, 'Ordonnance introuvable.', type: TypeToast.erreur);
      return;
    }
    final etat = verifierStock(ord, mag.collection('produits').actives);
    final manque = etat.where((e) => !e.suffisant).toList();
    afficherModale<void>(ecran,
        titre: 'Délivrer ${ord['numero']}',
        sousTitre: '${ord['patient']}',
        taille: TailleModale.lg,
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DescListeSigh([
            ('Patient', ord['patient']),
            ('Dossier', ord['patientCode']),
            ('Prescripteur', ord['medecin']),
            ('Ordonnance', ord['numero']),
            ('Règlement', ord['statutPaiement'] == 'soldee' ? 'Encaissé' : 'NON ENCAISSÉ'),
          ]),
          const SizedBox(height: 12),
          CarteSigh(
              titre: 'Lignes à servir',
              sansRemplissage: true,
              child: MiniTableauSigh(colonnes: [
                ColonneMini('Produit', (e) => '${(e['e'] as dv.LigneStock).ligne['produit']}'),
                ColonneMini('Posologie', (e) {
                  final p = (e['e'] as dv.LigneStock).ligne['posologie'];
                  return p == null || p == '' ? '—' : '$p';
                }),
                ColonneMini('Demandé', (e) => '${(e['e'] as dv.LigneStock).ligne['quantite']}', droite: true),
                ColonneMini('En pharmacie', (e) => _js((e['e'] as dv.LigneStock).disponible), droite: true),
                ColonneMini('Servable', (e) => (e['e'] as dv.LigneStock).suffisant ? 'Oui' : 'Stock insuffisant',
                    rendu: (e) => (e['e'] as dv.LigneStock).suffisant
                        ? const BadgeSigh('Oui', ton: TonSigh.succes)
                        : const BadgeSigh('Stock insuffisant', ton: TonSigh.danger)),
              ], lignes: [
                for (final e in etat) {'e': e}
              ])),
          const SizedBox(height: 12),
          if (manque.isNotEmpty)
            const NoteSigh(
                'RG-03 — le stock ne peut pas devenir négatif. La délivrance est refusée tant qu’une ligne n’est pas couverte : approvisionner la pharmacie par un transfert depuis le magasin, puis revenir ici.',
                ton: TonSigh.danger,
                icone: LucideIcons.triangleAlert)
          else
            const NoteSigh(
                'La sortie portera le numéro d’ordonnance comme justificatif (RG-03) et sera valorisée au prix d’achat (RG-02).',
                ton: TonSigh.info),
        ]),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Fermer', variante: VarianteBouton.secondaire, onPressed: fermer),
              if (manque.isNotEmpty)
                BoutonSigh(
                    libelle: 'Aller aux transferts',
                    icone: LucideIcons.arrowLeftRight,
                    variante: VarianteBouton.secondaire,
                    onPressed: () {
                      fermer();
                      c.aller('m6-transferts');
                    })
              else
                BoutonSigh(
                    libelle: 'Confirmer la délivrance',
                    icone: LucideIcons.check,
                    onPressed: () {
                      if (_delivrer(ecran, c, ord)) fermer();
                    }),
            ]);
  }

  static String _js(num v) => v == v.truncate() ? '${v.truncate()}' : '$v';

  /// Écrit la délivrance. `false` : refusée (le message dit pourquoi), rien n'est écrit.
  bool _delivrer(BuildContext ecran, ContexteEcran c, Fiche ord) {
    final mag = c.magasin;
    final Delivrance r;
    try {
      r = delivrerOrdonnance(
        ordonnance: ord,
        produits: mag.collection('produits').actives,
        taches: mag.collection('taches').actives,
        mouvementsExistants: mag.collection('mouvements').toutes,
        // La méthode de valorisation des sorties est un réglage d'exploitation de la Direction ; le jeu du poste n'en porte pas : prix de vente (= prix d'achat, RG-02).
        methode: 'prixVente',
        utilisateur: c.utilisateur,
        instant: c.aujourdhui.toIso8601String(),
      );
    } on RefusDelivrance catch (e) {
      ToastsSigh.afficher(ecran, 'Délivrance impossible : ${e.motif}', type: TypeToast.erreur);
      return false;
    }
    if (r.deja) return true;
    for (final p in r.produits) {
      mag.collection('produits').mettreAJour(p.id, p.patch);
    }
    for (final mv in r.mouvements) {
      mag.collection('mouvements').inserer(mv, prefixe: 'MVT');
    }
    mag.collection('ordonnances').mettreAJour(ord['id'], r.ordonnancePatch);
    for (final t in r.tachesFermees) {
      mag.collection('taches').mettreAJour(t.id, t.patch);
    }
    appliquerAlertes(mag, ResultatAlertes(r.alertes, [...r.tachesCreees], [...r.tachesMisesAJour]));
    final j = r.journal;
    mag.journaliser('${j['action']}', '${j['module']}', '${j['entite']}', '${j['reference']}', j['avant'], j['apres']);
    ToastsSigh.afficher(ecran, 'Médicaments délivrés — ${r.mouvements.length} sortie(s) de stock.',
        type: TypeToast.succes, detail: 'Justificatif : ${ord['numero']}');
    return true;
  }
}
