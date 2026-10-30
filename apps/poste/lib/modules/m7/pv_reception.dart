import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';

String _date(Object? v) {
  final d = DateTime.tryParse('${v ?? ''}');
  return d == null ? '' : dateFR(d);
}

/// `String(x)` de JavaScript pour une quantité : « 7 », jamais « 7.0 ».
String _s(Object? v) => v is num && v == v.truncate()
    ? '${v.truncate()}'
    : '${v ?? ''}';

List<Fiche> _lignes(Fiche pv) => [
      for (final l in (pv['lignes'] as List? ?? const []))
        (l as Map).cast<String, Object?>()
    ];

TonSigh _tonConclusion(Object? c) => switch (tonConclusionPv(c)) {
      'succes' => TonSigh.succes,
      'danger' => TonSigh.danger,
      _ => TonSigh.attention,
    };

/// La pièce imprimée : « PROCÈS-VERBAL DE RÉCEPTION », à TROIS signatures (magasinier, DAF, représentant du fournisseur).
///
/// Les colonnes commandée / livrée ne portent PAS de total à l'impression : la maquette déclare `somme` sur elles mais n'active pas
/// `total: true` — additionner des quantités d'articles et d'unités différents ne donnerait aucune grandeur (écart E19, porté fidèlement).
PieceA4 piecePv(Fiche r,
    {required String nature,
    required String utilisateur,
    required DateTime edite,
    required String reference}) {
  final reactifs = nature == natureReactifs;
  return PieceA4(
    titre: 'PROCÈS-VERBAL DE RÉCEPTION',
    sousTitre:
        '${reactifs ? 'Réactifs et consommables de laboratoire' : 'Consommables'} — ${r['reference']}',
    reference: reference,
    utilisateur: utilisateur,
    edite: edite,
    cartouche: [
      ('N° PV', '${r['reference']}'),
      ('Date', _date(r['date'])),
      ('Bon de livraison', '${r['livraisonRef'] ?? ''}'),
      ('Commande', '${r['commandeRef'] ?? '—'}'),
      ('Fournisseur', '${r['fournisseurNom'] ?? '—'}'),
      ('Conclusion', '${r['conclusion']}'),
    ],
    blocs: [
      BlocTableau(TableauEtat(colonnes: [
        ColonneEtat(libelle: 'Article', valeur: (l) => l['produit']),
        ColonneEtat(
            libelle: 'Unité', valeur: (l) => l['unite'] ?? '—'),
        ColonneEtat(
            libelle: 'Qté commandée',
            valeur: (l) => _s(l['commandee']),
            droite: true),
        ColonneEtat(
            libelle: 'Qté livrée', valeur: (l) => _s(l['livree']), droite: true),
        ColonneEtat(
            libelle: 'Écart',
            valeur: (l) => (l['ecart'] ?? 0) == 0 ? '' : _s(l['ecart']),
            droite: true),
      ], lignes: _lignes(r))),
      if (reactifs)
        BlocTexte(
            'Chaîne du froid à l’arrivée : ${r['chaineFroid'] == true ? 'respectée.' : 'ROMPUE — réserve majeure.'}'),
      if ('${r['reserves'] ?? ''}'.isNotEmpty)
        BlocTexte('Réserves : ${r['reserves']}'),
      const BlocTexte(
          'Le présent procès-verbal est établi contradictoirement entre la clinique et le représentant du fournisseur.',
          italique: true),
    ],
    signatures: [
      Signature('Le Magasinier', nom: '${r['magasinier'] ?? ''}'),
      const Signature('La Directrice de l’Administration et des Finances',
          nom: dafSignataire),
      Signature('Le représentant du fournisseur',
          nom: '${r['representantFournisseur'] ?? ''}'),
    ],
  );
}

Future<void> imprimerPv(BuildContext ctx, Fiche r, String nature) {
  final c = ContexteEcran.of(ctx);
  return afficherApercu(
      ctx,
      piecePv(r,
          nature: nature,
          utilisateur: c.utilisateur,
          edite: c.aujourdhui,
          reference: PieceA4.reference_(
              c.aujourdhui, ImpressionPoste.prochainNumero())));
}

/// Le tiroir d'un PV : la fiche, les lignes contrôlées, puis les réserves (texte SAISI, rendu tel quel).
Widget detailPv(Fiche r, String nature) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DescListeSigh([
            ('Référence', r['reference']),
            ('Date', _date(r['date'])),
            ('Bon de livraison', r['livraisonRef']),
            ('Commande', r['commandeRef'] ?? '—'),
            ('Fournisseur', r['fournisseurNom'] ?? '—'),
            if (nature == natureReactifs)
              ('Chaîne du froid', r['chaineFroid'] == true ? 'Respectée' : 'ROMPUE'),
            ('Conclusion', r['conclusion']),
            ('Magasinier', r['magasinier']),
            ('Représentant fournisseur', r['representantFournisseur'] ?? '—'),
          ]),
          const SizedBox(height: 16),
          SectionSigh(
              titre: 'Lignes contrôlées',
              child: MiniTableauSigh(colonnes: [
                ColonneMini('Article', (l) => '${l['produit']}'),
                ColonneMini('Commandée', (l) => _s(l['commandee'])),
                ColonneMini('Livrée', (l) => _s(l['livree'])),
                ColonneMini(
                    'Écart', (l) => (l['ecart'] ?? 0) == 0 ? '—' : _s(l['ecart'])),
              ], lignes: _lignes(r))),
          if ('${r['reserves'] ?? ''}'.isNotEmpty) ...[
            const SizedBox(height: 16),
            NoteSigh('Réserves : ${r['reserves']}',
                ton: TonSigh.attention, icone: LucideIcons.triangleAlert),
          ],
        ]);

/// `ecranPV(nature)` : « PV de réception — consommables » ou « — réactifs ». Une mécanique, deux écrans : les réactifs ajoutent le contrôle de
/// la chaîne du froid. Le PV constate la réception et se signe à trois ; une conclusion « avec réserves » ou « non conforme » EXIGE ses réserves.
class EcranPvReception extends StatelessWidget with EcranMaquette {
  const EcranPvReception.consommables({super.key}) : nature = natureConsommables;
  const EcranPvReception.reactifs({super.key}) : nature = natureReactifs;

  final String nature;

  bool get _reactifs => nature == natureReactifs;

  @override
  String get titre => _reactifs
      ? 'PV de réception — réactifs'
      : 'PV de réception — consommables';

  @override
  String get description => _reactifs
      ? 'Procès-verbaux de réception des réactifs de laboratoire : chaîne du froid, lots, écarts, réserves.'
      : 'Procès-verbaux de réception des consommables : quantités, écarts, réserves et signatures.';

  @override
  String get regle => _reactifs
      ? 'Les réactifs appellent un contrôle propre : la chaîne du froid à l’arrivée fait partie du PV — un réactif arrivé hors température se refuse, et le PV en fait foi devant le fournisseur. Signature à trois, comme pour les consommables.'
      : 'Le PV constate la réception et se signe à trois — magasinier, DAF, représentant du fournisseur. Une conclusion « avec réserves » ou « non conforme » exige ses réserves écrites : une réserve muette ne protège personne.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('pvReceptions');
    return ListenableBuilder(
      listenable: col,
      builder: (context, _) {
        final rows = [
          for (final r in col.actives)
            if (r['nature'] == nature) r
        ];
        final k = resumerPv(rows);
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              KpiGrilleSigh(kpis: [
                KpiSigh(
                    libelle: 'PV établis',
                    valeur: nombre(k.etablis),
                    icone: LucideIcons.clipboardCheck),
                KpiSigh(
                    libelle: 'Conformes',
                    valeur: nombre(k.conformes),
                    icone: LucideIcons.circleCheck,
                    ton: TonSigh.succes),
                KpiSigh(
                    libelle: 'Avec réserves',
                    valeur: nombre(k.avecReserves),
                    icone: LucideIcons.triangleAlert,
                    ton: k.avecReserves > 0 ? TonSigh.attention : TonSigh.neutre),
                KpiSigh(
                    libelle: 'Non conformes',
                    valeur: nombre(k.nonConformes),
                    icone: LucideIcons.circleX,
                    ton: k.nonConformes > 0 ? TonSigh.danger : TonSigh.neutre),
              ]),
              const SizedBox(height: 16),
              TableauSigh(
                titre: 'Registre des procès-verbaux',
                taillePage: 12,
                triInitial: 'date',
                sensInitial: 'desc',
                nomExport: 'pv-reception-$nature',
                messageVide: 'Aucun PV établi.',
                indiceVide:
                    'Un PV se dresse à la réception d’une livraison — bouton « Nouveau PV ».',
                lignes: rows,
                colonnes: [
                  ColonneTableau(
                      cle: 'reference',
                      libelle: 'N° PV',
                      sansCoupure: true,
                      texte: (r) => '${r['reference'] ?? ''}',
                      rendu: (_, r) => Text('${r['reference'] ?? ''}',
                          style: const TextStyle(
                              fontFamily: 'LiberationMono',
                              fontSize: 12,
                              height: 16 / 12,
                              fontWeight: FontWeight.w600,
                              color: JetonsShell.slate800))),
                  ColonneTableau(
                      cle: 'date',
                      libelle: 'Date',
                      sansCoupure: true,
                      texte: (r) => _date(r['date'])),
                  ColonneTableau(
                      cle: 'livraisonRef',
                      libelle: 'Bon de livraison',
                      sansCoupure: true,
                      texte: (r) => '${r['livraisonRef'] ?? ''}',
                      rendu: (_, r) => Text('${r['livraisonRef'] ?? ''}',
                          style: const TextStyle(
                              fontFamily: 'LiberationMono',
                              fontSize: 12,
                              height: 16 / 12,
                              color: JetonsShell.slate800))),
                  const ColonneTableau(
                      cle: 'fournisseurNom', libelle: 'Fournisseur'),
                  ColonneTableau(
                      cle: 'lignes',
                      libelle: 'Lignes',
                      droite: true,
                      valeur: (r) => _lignes(r).length,
                      texte: (r) => '${_lignes(r).length}'),
                  ColonneTableau(
                      cle: 'conclusion',
                      libelle: 'Conclusion',
                      texte: (r) => '${r['conclusion'] ?? ''}',
                      rendu: (_, r) => BadgeSigh('${r['conclusion'] ?? ''}',
                          ton: _tonConclusion(r['conclusion']))),
                  const ColonneTableau(cle: 'magasinier', libelle: 'Magasinier'),
                ],
                alClicLigne: (r) => _consulter(context, r),
                actionsLigne: (ctx, r) => [
                  BoutonIcone(
                      icone: LucideIcons.eye,
                      libelle: 'Consulter',
                      onPressed: () => _consulter(ctx, r)),
                  BoutonIcone(
                      icone: LucideIcons.printer,
                      libelle: 'Imprimer le PV',
                      onPressed: () => imprimerPv(ctx, r, nature)),
                ],
                actions: [
                  if (c.droit.editer)
                    BoutonSigh(
                        libelle: 'Nouveau PV',
                        icone: LucideIcons.plus,
                        taille: TailleBouton.sm,
                        onPressed: () => _nouveau(context)),
                ],
              ),
            ]);
      },
    );
  }

  void _consulter(BuildContext ctx, Fiche r) => afficherTiroir<void>(ctx,
      titre: 'PV ${r['reference']}',
      // Un PV de démonstration fabriqué depuis le catalogue ne porte pas de bon de livraison : le sous-titre affichait « undefined ».
      sousTitre: [r['livraisonRef'], r['fournisseurNom']]
          .where((x) => x != null && '$x'.isNotEmpty)
          .join(' — '),
      corps: detailPv(r, nature),
      pied: (_) => [
            BoutonSigh(
                libelle: 'Imprimer le PV',
                icone: LucideIcons.printer,
                variante: VarianteBouton.secondaire,
                onPressed: () => imprimerPv(ctx, r, nature)),
          ]);

  void _nouveau(BuildContext ctx) {
    final c = ContexteEcran.of(ctx);
    final m = c.magasin;
    final produits = m.collection('produits').actives;
    final livs = livraisonsPourPv(
        m.collection('livraisons').actives, nature, produits);
    if (livs.isEmpty) {
      ToastsSigh.afficher(ctx, messageSansLivraison(nature),
          type: TypeToast.attention);
      return;
    }
    final f = ControleurFormulaire([
      ChampDef(
          nom: 'livraisonRef',
          libelle: 'Bon de livraison',
          type: TypeChamp.select,
          requis: true,
          col: ColChamp.plein,
          options: [
            for (final l in livs)
              OptionChamp('${l['reference']}',
                  '${l['reference']} — ${l['fournisseurNom'] ?? ''}')
          ]),
      ChampDef(
          nom: 'date',
          libelle: 'Date du PV',
          type: TypeChamp.date,
          requis: true),
      if (_reactifs)
        const ChampDef(
            nom: 'chaineFroid',
            libelle: 'Chaîne du froid respectée à l’arrivée',
            type: TypeChamp.case_,
            aide:
                'Un réactif arrivé hors température se refuse — le PV en fait foi.'),
      ChampDef(
          nom: 'conclusion',
          libelle: 'Conclusion du contrôle',
          type: TypeChamp.select,
          requis: true,
          options: [for (final x in conclusionsPv) OptionChamp(x)]),
      const ChampDef(
          nom: 'reserves',
          libelle: 'Réserves et observations',
          type: TypeChamp.textarea,
          col: ColChamp.plein,
          lignes: 3,
          aide:
              'Obligatoires dès que la conclusion n’est pas « Conforme » : une réserve muette ne protège personne.'),
      const ChampDef(
          nom: 'representantFournisseur',
          libelle: 'Représentant du fournisseur (nom)',
          requis: true),
    ], {
      'date': iso(c.aujourdhui),
      'conclusion': conclusionConforme,
      'chaineFroid': true,
    });
    afficherModale<void>(ctx,
        titre: 'Nouveau PV de réception — ${libelleNature(nature)}',
        taille: TailleModale.lg,
        corps: FormulaireSigh(controleur: f),
        pied: (fermer) => [
              BoutonSigh(
                  libelle: 'Annuler',
                  variante: VarianteBouton.secondaire,
                  onPressed: fermer),
              BoutonSigh(
                  libelle: 'Établir le PV',
                  icone: LucideIcons.clipboardCheck,
                  onPressed: () {
                    final v = f.valider();
                    if (v == null) return;
                    final Fiche pv;
                    try {
                      pv = etablirPv(
                          nature: nature,
                          saisie: v,
                          livraisons: m.collection('livraisons').actives,
                          produits: produits,
                          references: [
                            for (final x in m.collection('pvReceptions').toutes)
                              '${x['reference'] ?? ''}'
                          ]);
                    } on RefusPv catch (e) {
                      if (e.motif != null) {
                        ToastsSigh.afficher(ctx, e.motif!,
                            type: TypeToast.erreur);
                      }
                      return;
                    }
                    final r = m
                        .collection('pvReceptions')
                        .inserer(pv, prefixe: 'PVR');
                    fermer();
                    ToastsSigh.afficher(ctx, 'PV ${pv['reference']} établi.',
                        type: TypeToast.succes,
                        detail: '${pv['conclusion']}',
                        annuler: r.annuler);
                    imprimerPv(ctx, r.fiche, nature);
                  }),
            ]);
  }
}
