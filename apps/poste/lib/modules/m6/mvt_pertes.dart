import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'mvt_commun.dart';

/// `m6-pertes` — « Pertes, casses & rebuts ». Une perte se déclare ici, mais elle s'enregistre comme un MOUVEMENT de stock — jamais dans un
/// registre parallèle : elle n'existe qu'une fois, et se lit aussi bien ici qu'aux mouvements. RG-03 : le stock ne peut pas devenir négatif, le
/// refus NOMME l'article ; la perte est valorisée au CUMP. La règle est dans `packages/domaine` (`declarerPerte`), rejouée sur des vecteurs de l'écran réel.
///
/// Écarts signalés (docs/architecture/ECARTS-MAQUETTE.md) : la déclaration ne décrémente que le champ `stock` (ni `stockGros` ni `stockDetail`, E20) et
/// n'écrit AUCUNE écriture comptable, bien que la règle de l'écran l'annonce (E21). Portés fidèlement.
class EcranPertes extends StatelessWidget with EcranMaquette {
  const EcranPertes({super.key});

  @override
  String get titre => 'Pertes, casses & rebuts';

  @override
  String get description =>
      'Traçabilité des pertes, bris de flacons, flacons vides et rebuts de stock, avec valorisation comptable de la perte.';

  @override
  String get regle =>
      'Une perte se déclare ici, mais elle s’enregistre comme un mouvement de stock — jamais dans un registre parallèle. RG-03 : chaque sortie porte son justificatif, le stock décroît, et la perte apparaît aussi bien ici qu’aux mouvements parce qu’elle n’existe qu’une fois. Elle est valorisée au CUMP et se répercute en comptabilité.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('mouvements');
    return ListenableBuilder(
      listenable: Listenable.merge([col, c.magasin.collection('produits')]),
      builder: (context, _) {
        final mvts = col.actives.where(estPerte).toList();
        final prods = produitsActifs(c);
        num valeur(Fiche r) => valeurPerte(r, prods);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          KpiGrilleSigh(kpis: [
            KpiSigh(libelle: 'Événements enregistrés', valeur: nombre(mvts.length), icone: LucideIcons.trash2),
            KpiSigh(libelle: 'Unités perdues', valeur: nombre(mvts.fold<num>(0, (a, r) => a + n(r['quantite']))), icone: LucideIcons.packageX, ton: TonSigh.danger),
            KpiSigh(
                libelle: 'Valeur des pertes',
                valeur: money(mvts.fold<num>(0, (a, r) => a + valeur(r))),
                icone: LucideIcons.wallet,
                ton: TonSigh.danger,
                indice: 'Valorisation au CUMP'),
            KpiSigh(libelle: 'Dont péremptions', valeur: nombre(mvts.where((r) => r['type'] == 'peremption').length), icone: LucideIcons.calendarX, ton: TonSigh.attention),
          ]),
          const SizedBox(height: 16),
          const NoteSigh(
              'Chaque perte est valorisée au CUMP et génère une écriture comptable au débit du compte de charges correspondant (module M12).',
              ton: TonSigh.attention,
              icone: LucideIcons.bookOpenCheck),
          const SizedBox(height: 16),
          TableauSigh(
            titre: 'Registre des pertes et casses',
            lignes: mvts,
            taillePage: 15,
            triInitial: 'date',
            sensInitial: 'desc',
            nomExport: 'pertes-casses',
            filtres: const [
              FiltreTableau(nom: 'type', libelle: 'Nature', options: [OptionChamp('perte', 'Perte'), OptionChamp('casse', 'Casse / bris'), OptionChamp('peremption', 'Péremption')])
            ],
            colonnes: [
              ColonneTableau(cle: 'reference', libelle: 'N°', sansCoupure: true, texte: (r) => '${r['reference']}', rendu: (_, r) => reference(r['reference'])),
              ColonneTableau(cle: 'date', libelle: 'Date', sansCoupure: true, texte: (r) => dateDe(r['date'])),
              const ColonneTableau(cle: 'produit', libelle: 'Produit'),
              ColonneTableau(
                  cle: 'type',
                  libelle: 'Nature',
                  texte: (r) => _nature(r),
                  rendu: (_, r) => BadgeSigh(_nature(r), ton: tonDe(typeMouvement(r['type'])?.ton ?? 'danger'))),
              ColonneTableau(cle: 'quantite', libelle: 'Quantité', droite: true, texte: (r) => '${r['quantite']}'),
              ColonneTableau(
                  cle: 'valeur',
                  libelle: 'Valeur perdue',
                  droite: true,
                  valeur: valeur,
                  texte: (r) => m(valeur(r)),
                  rendu: (_, r) => Text(m(valeur(r)), style: const TextStyle(color: JetonsShell.danger600, fontSize: 14, fontWeight: FontWeight.w600))),
              const ColonneTableau(cle: 'justificatif', libelle: 'Justificatif (RG-03)'),
              const ColonneTableau(cle: 'utilisateur', libelle: 'Constaté par'),
            ],
            actions: [
              if (c.droit.editer)
                BoutonSigh(
                    libelle: 'Déclarer une perte',
                    icone: LucideIcons.trash2,
                    taille: TailleBouton.sm,
                    variante: VarianteBouton.danger,
                    onPressed: () => _declarer(context, c)),
              BoutonSigh(
                  libelle: 'Éditer le constat',
                  icone: LucideIcons.printer,
                  taille: TailleBouton.sm,
                  variante: VarianteBouton.secondaire,
                  onPressed: () => afficherApercu(context, _constat(c, mvts, prods))),
            ],
          ),
        ]);
      },
    );
  }

  static String _nature(Fiche r) => '${r['typeLabel'] ?? typeMouvement(r['type'])?.libelle ?? r['type']}';

  PieceA4 _constat(ContexteEcran c, List<Fiche> mvts, List<Fiche> prods) {
    num valeur(Fiche r) => valeurPerte(r, prods);
    final recents = trierPar(mvts, (r) => r['date'], descendant: true).take(60).toList();
    return PieceA4(
      titre: 'Constat de pertes et casses',
      sousTitre: 'Période cumulée — situation au ${dateFR(c.aujourdhui)}',
      reference: PieceA4.reference_(c.aujourdhui, ImpressionPoste.prochainNumero()),
      utilisateur: c.utilisateur,
      edite: c.aujourdhui,
      cartouche: [
        ('Événements', nombre(mvts.length)),
        ('Unités perdues', nombre(mvts.fold<num>(0, (a, r) => a + n(r['quantite'])))),
        ('Valeur totale', money(mvts.fold<num>(0, (a, r) => a + valeur(r)))),
        ('Date d’édition', dateFR(c.aujourdhui)),
      ],
      tableaux: [
        TableauEtat(colonnes: [
          ColonneEtat(libelle: 'Date', valeur: (r) => dateDe(r['date'])),
          ColonneEtat(libelle: 'Produit', valeur: (r) => r['produit']),
          ColonneEtat(libelle: 'Nature', valeur: (r) => r['typeLabel'] ?? ''),
          ColonneEtat(libelle: 'Quantité', valeur: (r) => r['quantite'], droite: true),
          ColonneEtat(libelle: 'Valeur', valeur: (r) => m(valeur(r)), droite: true, somme: valeur),
          ColonneEtat(libelle: 'Justificatif', valeur: (r) => r['justificatif']),
        ], lignes: recents)
      ],
      signatures: const [
        Signature('Le Gestionnaire de Stock', nom: 'MAMAN Zoukanéri'),
        Signature('Le Comptable', nom: 'KASSA Augustin'),
        Signature('La Directrice Administrative', nom: 'TAKI Alimatou'),
      ],
    );
  }

  void _declarer(BuildContext ctx, ContexteEcran c) {
    final prods = produitsActifs(c);
    final f = ControleurFormulaire([
      ChampDef(
          nom: 'produitId',
          libelle: 'Article',
          type: TypeChamp.select,
          requis: true,
          col: ColChamp.plein,
          options: [
            for (final p in prods) OptionChamp('${p['id']}', '${p['designation']} (Stock ${nombre(p['stock'] ?? 0)} ${p['unite'] ?? ''} — CUMP ${m(p['cump'])})')
          ]),
      ChampDef(nom: 'type', libelle: 'Nature de la perte', type: TypeChamp.select, requis: true, options: [for (final t in naturesPerte) OptionChamp(t.$1, t.$2)]),
      ChampDef(nom: 'quantite', libelle: 'Quantité perdue', type: TypeChamp.nombre, requis: true, valider: (v, _) => n(v) < 1 ? 'La valeur minimale est 1.' : null),
      const ChampDef(nom: 'date', libelle: 'Date du constat', type: TypeChamp.date, requis: true),
      const ChampDef(
          nom: 'justificatif',
          libelle: 'Justificatif',
          requis: true,
          col: ColChamp.plein,
          aide: 'RG-03 — toute sortie porte son justificatif : n° de constat, procès-verbal, lot périmé.'),
      const ChampDef(nom: 'constatePar', libelle: 'Constaté par', requis: true),
      const ChampDef(nom: 'observation', libelle: 'Circonstances', type: TypeChamp.textarea, lignes: 2, col: ColChamp.plein),
    ], {
      'date': iso(c.aujourdhui),
      'type': 'casse',
      'quantite': '1',
      'constatePar': c.utilisateur,
    });
    afficherModale<void>(ctx,
        titre: 'Déclarer une perte',
        taille: TailleModale.lg,
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const NoteSigh(
              'La déclaration écrit un mouvement de sortie : le stock décroît d’autant, la perte est valorisée au CUMP et se retrouve aux « Mouvements de stock ». Elle n’est pas consignée dans un registre séparé — il divergerait au premier écart.',
              ton: TonSigh.attention,
              icone: LucideIcons.trash2),
          const SizedBox(height: 12),
          FormulaireSigh(controleur: f),
        ]),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: 'Déclarer la perte',
                  icone: LucideIcons.trash2,
                  variante: VarianteBouton.danger,
                  onPressed: () {
                    final v = f.valider();
                    if (v == null) return;
                    final prod = prods.where((x) => x['id'] == v['produitId']).firstOrNull;
                    if (prod == null) return;
                    final mouvements = c.magasin.collection('mouvements');
                    final produits = c.magasin.collection('produits');
                    final PerteDeclaree r;
                    try {
                      r = declarerPerte(
                          produit: prod,
                          type: '${v['type']}',
                          quantite: n(v['quantite']),
                          date: '${v['date']}',
                          justificatif: '${v['justificatif']}',
                          constatePar: '${v['constatePar']}',
                          observation: '${v['observation'] ?? ''}',
                          utilisateur: c.utilisateur,
                          mouvements: mouvements.toutes);
                    } on RefusStock catch (e) {
                      ToastsSigh.afficher(ctx, e.motif, type: TypeToast.erreur, detail: e.detail);
                      return;
                    }
                    final ins = mouvements.inserer(r.mouvement, prefixe: 'MVT');
                    final undoStock = produits.mettreAJour(prod['id'], {'stock': r.stockApres});
                    c.magasin.journaliser('Déclaration de perte', 'M6', 'MouvementStock', '${r.mouvement['reference']}', {'stock': r.stockAvant},
                        {'stock': r.stockApres, 'type': v['type'], 'valeur': r.valeur});
                    fermer();
                    annonce(ctx, 'Perte déclarée.',
                        detail: r.detail,
                        duree: const Duration(seconds: 8),
                        messageAnnulation: 'Déclaration annulée — le stock est rétabli.',
                        annuler: () {
                          ins.annuler();
                          undoStock();
                        });
                  }),
            ]);
  }
}
