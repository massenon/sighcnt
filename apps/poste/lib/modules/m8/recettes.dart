import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'commun.dart';

DateTime _jour(String s) {
  final d = DateTime.tryParse(s);
  return d == null ? DateTime(1970) : DateTime(d.year, d.month, d.day);
}

/// `m8-recettes` — recettes ENCAISSÉES par journée, semaine, mois, trimestre, semestre ou année, ou sur une plage libre. Calculées depuis les
/// factures : elles ne se saisissent pas ; le facturé non réglé figure à part.
class EcranRecettes extends StatefulWidget with EcranMaquette {
  const EcranRecettes({super.key});

  @override
  String get description =>
      'Recettes encaissées par journée, semaine, mois, trimestre, semestre ou année, avec plage libre.';

  @override
  String get regle =>
      'Les recettes sont calculées depuis les encaissements : elles ne se saisissent pas. Une recette ne compte que ce qui est réellement entré en caisse — le facturé non réglé figure à part.';

  @override
  String get titre => 'Recettes par période';

  @override
  List<Widget> actionsEntete(BuildContext context) {
    final c = ContexteEcran.of(context);
    return [
      BoutonSigh(
          libelle: 'Opérations de caisse',
          icone: LucideIcons.scrollText,
          variante: VarianteBouton.secondaire,
          onPressed: () => c.aller('m8-operations')),
      BoutonSigh(
          libelle: 'État de caisse journalier',
          icone: LucideIcons.calculator,
          variante: VarianteBouton.secondaire,
          onPressed: () => c.aller('m8-caisse')),
    ];
  }

  @override
  State<EcranRecettes> createState() => _EcranRecettesState();
}

class _EcranRecettesState extends State<EcranRecettes> {
  ControleurFormulaire? _f;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_f == null) {
      final auj = ContexteEcran.of(context).aujourdhui;
      _f = ControleurFormulaire([
        ChampDef(
            nom: 'periode',
            libelle: 'Périodicité',
            type: TypeChamp.select,
            col: ColChamp.tiers,
            options: [for (final p in periodes) OptionChamp(p.id, p.label)]),
        const ChampDef(
            nom: 'du',
            libelle: 'Du',
            type: TypeChamp.date,
            col: ColChamp.tiers),
        const ChampDef(
            nom: 'au',
            libelle: 'Au',
            type: TypeChamp.date,
            col: ColChamp.tiers),
        const ChampDef(
            nom: 'libre',
            libelle: 'Plage de dates libre',
            type: TypeChamp.case_),
      ], {
        'periode': 'jour',
        'du': iso(ajouterJours(auj, -29)),
        'au': iso(auj),
        'libre': false
      })
        ..addListener(() => setState(() {}));
    }
  }

  Bornes _plage() {
    final f = _f!;
    if (f['libre'] == true)
      return bornesLibres(_jour('${f['du']}'), _jour('${f['au']}'));
    return bornes('${f['periode']}', _jour('${f['au']}'));
  }

  /// Découpage de la plage en tranches selon la périodicité (la plage libre choisit son pas selon l'étendue).
  List<Bornes> _tranches(Bornes p) {
    var pas = periodes.firstWhere((x) => x.id == _f!['periode']).jours;
    if (_f!['libre'] == true) {
      final jours = joursEntre(p.debut, p.fin) + 1;
      pas = jours > 180 ? 30 : (jours > 45 ? 7 : 1);
    }
    final out = <Bornes>[];
    var curseur = p.debut;
    while (!curseur.isAfter(p.fin) && out.length <= 400) {
      var fin = ajouterJours(curseur, pas - 1);
      if (fin.isAfter(p.fin)) fin = p.fin;
      out.add(Bornes(curseur, fin, '', pas));
      curseur = ajouterJours(fin, 1);
    }
    return out;
  }

  String _lib(Bornes t) =>
      dateFR(t.debut) +
      (iso(t.debut) == iso(t.fin) ? '' : ' → ${dateFR(t.fin)}');

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('factures');
    return ListenableBuilder(
      listenable: col,
      builder: (context, _) {
        final f = _f!;
        final libre = f['libre'] == true;
        final p = _plage();
        final toutes = col.actives;
        List<Fiche> dans(Bornes b) => [
              for (final x in toutes)
                if (dansBornes(_jour('${x['date']}'), b)) x
            ];
        num som(Iterable<Fiche> r, String k) =>
            r.fold<num>(0, (a, x) => a + n(x[k]));
        final pp = dans(p);
        final encaisse = som(pp, 'montantPaye'),
            facture = som(pp, 'montantTTC');
        final lignes = [
          for (final t in _tranches(p))
            () {
              final r = dans(t);
              return <String, Object?>{
                'periode': _lib(t),
                'debut': iso(t.debut),
                'pieces': r.length,
                'facture': som(r, 'montantTTC'),
                'encaisse': som(r, 'montantPaye'),
                'reliquat': som(r, 'reliquat'),
                'assureur': som(r, 'partAssurance')
              };
            }()
        ];
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CarteSigh(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    FormulaireSigh(controleur: f),
                    const SizedBox(height: 12),
                    Align(
                        alignment: Alignment.centerRight,
                        child: BoutonSigh(
                            libelle: 'Éditer l’état',
                            icone: LucideIcons.printer,
                            onPressed: () =>
                                _imprimer(context, p, pp, lignes, libre))),
                  ])),
              const SizedBox(height: 16),
              KpiGrilleSigh(kpis: [
                KpiSigh(
                    libelle: 'Recette encaissée',
                    valeur: money(encaisse),
                    icone: LucideIcons.banknote,
                    ton: TonSigh.succes,
                    indice: '${dateFR(p.debut)} → ${dateFR(p.fin)}'),
                KpiSigh(
                    libelle: 'Montant facturé',
                    valeur: money(facture),
                    icone: LucideIcons.receipt),
                KpiSigh(
                    libelle: 'Reste à encaisser',
                    valeur: money(som(pp, 'reliquat')),
                    icone: LucideIcons.hourglass,
                    ton: TonSigh.attention),
                KpiSigh(
                    libelle: 'Taux de recouvrement',
                    valeur: facture != 0
                        ? '${(encaisse * 100 / facture).round()} %'
                        : '—',
                    icone: LucideIcons.percent,
                    ton: TonSigh.info),
              ]),
              if (lignes.length > 1) ...[
                const SizedBox(height: 16),
                CarteSigh(
                    titre: 'Évolution des encaissements',
                    child: GraphiqueLigne(etiquettes: [
                      for (final l in lignes) '${l['periode']}'
                    ], series: [
                      SerieGraphique('Encaissé',
                          [for (final l in lignes) l['encaisse'] as num]),
                      SerieGraphique('Facturé',
                          [for (final l in lignes) l['facture'] as num]),
                    ])),
              ],
              const SizedBox(height: 16),
              TableauSigh(
                titre:
                    'Recettes — ${libre ? 'plage libre' : p.label.toLowerCase()}',
                lignes: lignes,
                taillePage: 20,
                triInitial: 'debut',
                sensInitial: 'desc',
                nomExport: 'recettes',
                messageVide: 'Aucune recette sur la période.',
                colonnes: [
                  const ColonneTableau(
                      cle: 'periode', libelle: 'Période', sansCoupure: true),
                  const ColonneTableau(
                      cle: 'pieces', libelle: 'Pièces', droite: true),
                  ColonneTableau(
                      cle: 'facture',
                      libelle: 'Facturé',
                      droite: true,
                      texte: (l) => m(l['facture'])),
                  ColonneTableau(
                      cle: 'assureur',
                      libelle: 'Dont part assureur',
                      droite: true,
                      texte: (l) => m(l['assureur'])),
                  ColonneTableau(
                      cle: 'encaisse',
                      libelle: 'Encaissé',
                      droite: true,
                      texte: (l) => m(l['encaisse']),
                      rendu: (_, l) => Text(m(l['encaisse']),
                          style: const TextStyle(
                              color: JetonsShell.success700,
                              fontSize: 14,
                              height: 20 / 14,
                              fontWeight: FontWeight.w600))),
                  ColonneTableau(
                      cle: 'reliquat',
                      libelle: 'Reste à encaisser',
                      droite: true,
                      texte: (l) => m(l['reliquat'])),
                ],
              ),
            ]);
      },
    );
  }

  void _imprimer(BuildContext ctx, Bornes p, List<Fiche> pp,
      List<Map<String, Object?>> lignes, bool libre) {
    final c = ContexteEcran.of(ctx);
    num som(Iterable<Fiche> r, String k) =>
        r.fold<num>(0, (a, x) => a + n(x[k]));
    final lib = libre ? 'Plage libre' : p.label;
    afficherApercu(
        ctx,
        PieceA4(
          titre: 'État des recettes',
          sousTitre: '$lib — ${dateFR(p.debut)} au ${dateFR(p.fin)}',
          reference: PieceA4.reference_(
              c.aujourdhui, ImpressionPoste.prochainNumero()),
          utilisateur: c.utilisateur,
          edite: c.aujourdhui,
          cartouche: [
            ('Périodicité', lib),
            ('Du', dateFR(p.debut)),
            ('Au', dateFR(p.fin)),
            ('Pièces', nombre(pp.length)),
            ('Recette encaissée', money(som(pp, 'montantPaye'))),
            ('Reste à encaisser', money(som(pp, 'reliquat'))),
          ],
          tableaux: [
            TableauEtat(colonnes: [
              ColonneEtat(libelle: 'Période', valeur: (l) => l['periode']),
              ColonneEtat(
                  libelle: 'Pièces',
                  valeur: (l) => l['pieces'],
                  droite: true,
                  somme: (l) => n(l['pieces'])),
              ColonneEtat(
                  libelle: 'Facturé',
                  valeur: (l) => m(l['facture']),
                  droite: true,
                  somme: (l) => n(l['facture'])),
              ColonneEtat(
                  libelle: 'Encaissé',
                  valeur: (l) => m(l['encaisse']),
                  droite: true,
                  somme: (l) => n(l['encaisse'])),
              ColonneEtat(
                  libelle: 'Reste à encaisser',
                  valeur: (l) => m(l['reliquat']),
                  droite: true,
                  somme: (l) => n(l['reliquat'])),
            ], lignes: lignes)
          ],
          signatures: const [
            Signature('L’agent de caisse'),
            Signature('La Directrice Administrative', nom: 'TAKI Alimatou')
          ],
        ));
  }
}
