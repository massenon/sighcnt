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
import 'mvt_inventaire_feuille.dart';

/// `m6-inventaire` — « Inventaires » : l'historique des inventaires et leur lancement. Le comptage lui-même se fait sur la PAGE
/// `m6-inventaire-feuille`. UN INVENTAIRE PORTE SUR UN MAGASIN NOMMÉ (gros ou détail) : il comptait le stock TOTAL et régularisait
/// systématiquement le stock GROS, si bien que compter les rayons de la pharmacie d'urgence faisait apparaître un écart sur tout ce que le
/// magasin central détenait. Les deux stocks se comptent séparément parce qu'ils se tiennent dans deux pièces différentes.
class EcranInventaires extends StatelessWidget with EcranMaquette {
  const EcranInventaires({super.key});

  @override
  String get titre => 'Inventaires';

  @override
  String get description =>
      'Inventaire mensuel et annuel : comparaison automatique entre stock physique saisi et stock théorique du système.';

  @override
  String get regle =>
      'L’inventaire remplace la comparaison manuelle actuelle : les écarts sont calculés automatiquement et valorisés au CUMP avant régularisation.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('inventaires');
    return ListenableBuilder(
      listenable: Listenable.merge([col, c.magasin.collection('produits')]),
      builder: (context, _) {
        final rows = col.actives;
        final produits = produitsActifs(c);
        final dernier = rows.isEmpty ? null : (trierPar(rows, (r) => r['date'], descendant: true).first)['date'];
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          KpiGrilleSigh(kpis: [
            KpiSigh(libelle: 'Inventaires réalisés', valeur: nombre(rows.length), icone: LucideIcons.clipboardCheck),
            KpiSigh(libelle: 'Références à inventorier', valeur: nombre(produits.length), icone: LucideIcons.package, ton: TonSigh.info),
            KpiSigh(libelle: 'Valeur théorique', valeur: money(valeurStock(produits)), icone: LucideIcons.wallet, ton: TonSigh.succes),
            KpiSigh(libelle: 'Dernier inventaire', valeur: dernier == null ? 'Aucun' : dateDe(dernier), icone: LucideIcons.calendarCheck, ton: TonSigh.neutre),
          ]),
          const SizedBox(height: 16),
          TableauSigh(
            titre: 'Historique des inventaires',
            lignes: rows,
            taillePage: 10,
            triInitial: 'date',
            sensInitial: 'desc',
            nomExport: 'inventaires',
            messageVide: 'Aucun inventaire enregistré.',
            indiceVide: 'Lancer un inventaire pour comparer le stock physique au stock théorique.',
            actions: [
              if (c.droit.editer)
                BoutonSigh(libelle: 'Lancer un inventaire', icone: LucideIcons.play, taille: TailleBouton.sm, onPressed: () => _lancer(context, c)),
            ],
            alClicLigne: (i) => _consulter(context, i),
            colonnes: [
              ColonneTableau(cle: 'reference', libelle: 'N°', sansCoupure: true, texte: (i) => '${i['reference']}', rendu: (_, i) => reference(i['reference'])),
              ColonneTableau(cle: 'date', libelle: 'Date', sansCoupure: true, texte: (i) => dateDe(i['date'])),
              ColonneTableau(cle: 'type', libelle: 'Type', texte: (i) => '${i['type']}', rendu: (_, i) => BadgeSigh('${i['type']}', ton: TonSigh.navy)),
              const ColonneTableau(cle: 'perimetre', libelle: 'Périmètre'),
              const ColonneTableau(cle: 'nbArticles', libelle: 'Articles', droite: true),
              ColonneTableau(
                  cle: 'nbEcarts',
                  libelle: 'Écarts',
                  droite: true,
                  texte: (i) => n(i['nbEcarts']) > 0 ? '${i['nbEcarts']}' : 'Aucun',
                  rendu: (_, i) => n(i['nbEcarts']) > 0
                      ? Text('${i['nbEcarts']}', style: const TextStyle(color: JetonsShell.danger600, fontSize: 14, fontWeight: FontWeight.w600))
                      : const BadgeSigh('Aucun', ton: TonSigh.succes)),
              ColonneTableau(
                  cle: 'valeurEcart',
                  libelle: 'Valeur des écarts',
                  droite: true,
                  texte: (i) => m(n(i['valeurEcart'])),
                  rendu: (_, i) {
                    final v = n(i['valeurEcart']);
                    return Text(m(v),
                        style: TextStyle(color: v < 0 ? JetonsShell.danger600 : (v > 0 ? JetonsShell.success600 : JetonsShell.slate700), fontSize: 14, fontWeight: v != 0 ? FontWeight.w600 : null));
                  }),
              const ColonneTableau(cle: 'operateur', libelle: 'Réalisé par'),
              ColonneTableau(
                  cle: 'statutInv',
                  libelle: 'Statut',
                  texte: (i) => i['statutInv'] == 'valide' ? 'Validé' : 'Brouillon',
                  rendu: (_, i) => statutBadge(i['statutInv'] == 'valide' ? 'valide' : 'brouillon')),
            ],
            actionsLigne: (ctx, i) => [
              BoutonIcone(icone: LucideIcons.eye, libelle: 'Consulter', onPressed: () => _consulter(context, i)),
              BoutonIcone(icone: LucideIcons.printer, libelle: 'Imprimer l’état', onPressed: () => _etat(context, i)),
            ],
          ),
        ]);
      },
    );
  }

  /// Lancer un inventaire : le magasin d'abord — DEUX et non trois, un article ne porte que `stockGros` et `stockDetail`. Offrir « Stock
  /// laboratoire » ferait compter une quantité qui n'existe sur aucune fiche, et la régularisation retomberait sur le magasin central.
  void _lancer(BuildContext ctx, ContexteEcran c) {
    final f = ControleurFormulaire([
      const ChampDef(
          nom: 'magasin',
          libelle: 'Magasin inventorié',
          type: TypeChamp.select,
          requis: true,
          recherche: false,
          aide: 'Le comptage et la régularisation portent sur CE stock seulement.',
          col: ColChamp.plein,
          options: [
            OptionChamp('gros', 'Stock gros (magasin central)'),
            OptionChamp('detail', 'Stock détail (pharmacie d’urgence)'),
          ]),
      const ChampDef(
          nom: 'type', libelle: 'Type d’inventaire', type: TypeChamp.select, requis: true, options: [OptionChamp('Hebdomadaire'), OptionChamp('Mensuel'), OptionChamp('Annuel'), OptionChamp('Tournant'), OptionChamp('Ponctuel')]),
      const ChampDef(nom: 'date', libelle: 'Date', type: TypeChamp.date, requis: true),
      ChampDef(
          nom: 'perimetre',
          libelle: 'Périmètre',
          type: TypeChamp.select,
          requis: true,
          options: [const OptionChamp('Tous les articles'), for (final cat in categoriesProduit) OptionChamp(cat.$2)]),
      const ChampDef(nom: 'operateur', libelle: 'Réalisé par', requis: true),
    ], {
      'date': iso(c.aujourdhui),
      'operateur': c.utilisateur,
    });
    afficherModale<void>(ctx,
        titre: 'Lancer un inventaire',
        taille: TailleModale.md,
        corps: FormulaireSigh(controleur: f),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: 'Ouvrir la feuille de saisie',
                  icone: LucideIcons.clipboardList,
                  onPressed: () {
                    final v = f.valider();
                    if (v == null) return;
                    fermer();
                    // La feuille a QUITTÉ la modale : on y compte deux cents articles, un par un, la main sur le rayon.
                    AdresseFeuille.enAttente = EnteteInventaire(
                        magasin: '${v['magasin']}', type: '${v['type']}', date: '${v['date']}', perimetre: '${v['perimetre']}', operateur: '${v['operateur']}');
                    c.aller('m6-inventaire-feuille');
                  }),
            ]);
  }

  void _consulter(BuildContext ctx, Fiche i) {
    final ecarts = [for (final l in (i['lignes'] as List? ?? const [])) if (n((l as Map)['ecart']) != 0) l.cast<String, Object?>()];
    afficherTiroir<void>(ctx,
        titre: 'Inventaire ${i['reference']}',
        sousTitre: '${i['type']} — ${dateDe(i['date'])}',
        largeurMax: 768,
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DescListeSigh([
            ('Référence', i['reference']),
            ('Type', i['type']),
            ('Périmètre', i['perimetre']),
            ('Date', dateDe(i['date'])),
            ('Réalisé par', i['operateur']),
            ('Articles inventoriés', nombre(i['nbArticles'])),
            ('Écarts', nombre(i['nbEcarts'])),
            ('Valeur des écarts', money(i['valeurEcart'] ?? 0)),
          ]),
          const SizedBox(height: 16),
          ecarts.isNotEmpty
              ? CarteSigh(
                  titre: 'Écarts constatés',
                  sansRemplissage: true,
                  child: MiniTableauSigh(colonnes: [
                    ColonneMini('Article', (l) => '${l['designation']}'),
                    ColonneMini('Théorique', (l) => nombre(l['theorique']), droite: true),
                    ColonneMini('Physique', (l) => nombre(l['physique']), droite: true),
                    ColonneMini('Écart', (l) => '${n(l['ecart']) > 0 ? '+' : ''}${nombre(l['ecart'])}',
                        droite: true,
                        rendu: (l) => Text('${n(l['ecart']) > 0 ? '+' : ''}${nombre(l['ecart'])}',
                            style: TextStyle(color: n(l['ecart']) < 0 ? JetonsShell.danger600 : JetonsShell.success600, fontSize: 14, fontWeight: FontWeight.w600))),
                    ColonneMini('Valeur', (l) => m(l['valeur']), droite: true),
                  ], lignes: ecarts))
              : const VideSigh('Aucun écart constaté : stock physique conforme au stock théorique.', icone: LucideIcons.circleCheck),
        ]),
        pied: (fermer) => [BoutonSigh(libelle: 'Imprimer l’état', icone: LucideIcons.printer, onPressed: () => _etat(ctx, i))]);
  }

  /// L'état d'inventaire : tous les articles comptés, le total des écarts CALCULÉ, trois signatures (magasinier, pharmacien, DAF).
  Future<void> _etat(BuildContext ctx, Fiche i) {
    final c = ContexteEcran.of(ctx);
    return afficherApercu(
        ctx,
        PieceA4(
          titre: 'État d’inventaire',
          sousTitre: '${i['reference']} — ${i['type']}',
          reference: PieceA4.reference_(c.aujourdhui, ImpressionPoste.prochainNumero()),
          utilisateur: c.utilisateur,
          edite: c.aujourdhui,
          cartouche: [
            ('Référence', '${i['reference']}'),
            ('Type', '${i['type']}'),
            ('Périmètre', '${i['perimetre']}'),
            ('Date', dateDe(i['date'])),
            ('Réalisé par', '${i['operateur']}'),
            ('Valeur des écarts', money(i['valeurEcart'] ?? 0)),
          ],
          tableaux: [
            TableauEtat(colonnes: [
              ColonneEtat(libelle: 'Code', valeur: (l) => l['code']),
              ColonneEtat(libelle: 'Désignation', valeur: (l) => l['designation']),
              ColonneEtat(libelle: 'Unité', valeur: (l) => l['unite']),
              ColonneEtat(libelle: 'Stock théorique', valeur: (l) => nombre(l['theorique']), droite: true),
              ColonneEtat(libelle: 'Stock physique', valeur: (l) => nombre(l['physique']), droite: true),
              ColonneEtat(libelle: 'Écart', valeur: (l) => '${n(l['ecart']) > 0 ? '+' : ''}${nombre(l['ecart'])}', droite: true),
              ColonneEtat(libelle: 'Valeur écart', valeur: (l) => m(l['valeur']), droite: true, somme: (l) => n(l['valeur'])),
            ], lignes: [for (final l in (i['lignes'] as List? ?? const [])) (l as Map).cast<String, Object?>()])
          ],
          signatures: const [
            Signature('Le Gestionnaire de Stock', nom: 'MAMAN Zoukanéri'),
            Signature('Le Pharmacien', nom: 'DIEYABIDI Aïssatou'),
            Signature('La Directrice Administrative', nom: 'TAKI Alimatou'),
          ],
        ));
  }
}
