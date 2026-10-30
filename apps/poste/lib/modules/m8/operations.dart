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

DateTime _jour(Object? s) {
  final d = DateTime.tryParse('$s');
  return d == null ? DateTime(1970) : DateTime(d.year, d.month, d.day);
}

/// `m8-operations` — toute opération de caisse, quelle que soit la pièce émise ; l'INVENTAIRE arrête la caisse sur une période et se compare
/// à l'espèce comptée : un écart doit être expliqué avant clôture, jamais absorbé en silence.
class EcranOperations extends StatefulWidget with EcranMaquette {
  const EcranOperations({super.key});

  @override
  String get description =>
      'Tickets, factures et avoirs passés en caisse, avec inventaire journalier ou hebdomadaire.';

  @override
  String get regle =>
      'Toute opération de caisse est ici, quelle que soit la pièce émise. L’inventaire arrête la caisse sur une période et se compare à l’espèce comptée ; un écart doit être expliqué avant clôture, jamais absorbé en silence.';

  @override
  String get titre => 'Opérations de caisse';

  @override
  List<Widget> actionsEntete(BuildContext context) {
    final c = ContexteEcran.of(context);
    return [
      BoutonSigh(
          libelle: 'Recettes par période',
          icone: LucideIcons.trendingUp,
          variante: VarianteBouton.secondaire,
          onPressed: () => c.aller('m8-recettes')),
      if (c.droit.editer)
        BoutonSigh(
            libelle: 'Émettre une facture',
            icone: LucideIcons.receipt,
            onPressed: () => c.aller('m8-facturation')),
    ];
  }

  @override
  State<EcranOperations> createState() => _EcranOperationsState();
}

class _EcranOperationsState extends State<EcranOperations> {
  ControleurFormulaire? _f;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _f ??= ControleurFormulaire([
      ChampDef(
          nom: 'periode',
          libelle: 'Périodicité',
          type: TypeChamp.select,
          col: ColChamp.tiers,
          options: [
            for (final p in periodes.take(3)) OptionChamp(p.id, p.label)
          ]),
      const ChampDef(
          nom: 'au',
          libelle: 'Arrêtée au',
          type: TypeChamp.date,
          col: ColChamp.tiers),
    ], {
      'periode': 'jour',
      'au': iso(ContexteEcran.of(context).aujourdhui)
    })
      ..addListener(() => setState(() {}));
  }

  Bornes _b() => bornes('${_f!['periode']}', _jour(_f!['au']));

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('factures');
    return ListenableBuilder(
      listenable: col,
      builder: (context, _) {
        final b = _b();
        final ops = [
          for (final f in col.actives)
            if (dansBornes(_jour(f['date']), b)) f
        ];
        final avoirs = ops.where((f) => n(f['montantTTC']) < 0).toList();
        num som(Iterable<Fiche> r, String k) =>
            r.fold<num>(0, (a, x) => a + n(x[k]));
        final encaisse = som(ops, 'montantPaye');
        final parMode = <String, num>{};
        for (final f in ops) {
          final k = '${f['modePaiement'] ?? 'non_precise'}';
          parMode[k] = (parMode[k] ?? 0) + n(f['montantPaye']);
        }
        final ventilation = [
          for (final e
              in (parMode.entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value))))
            <String, Object?>{'mode': modeLabel(e.key), 'montant': e.value}
        ];
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CarteSigh(
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                    Expanded(child: FormulaireSigh(controleur: _f!)),
                    const SizedBox(width: 12),
                    if (c.droit.editer)
                      BoutonSigh(
                          libelle: 'Inventaire de caisse',
                          icone: LucideIcons.clipboardCheck,
                          onPressed: () => _inventaire(context, b, ops)),
                  ])),
              const SizedBox(height: 16),
              KpiGrilleSigh(kpis: [
                KpiSigh(
                    libelle: 'Opérations',
                    valeur: nombre(ops.length),
                    icone: LucideIcons.scrollText,
                    indice: '${dateFR(b.debut)} → ${dateFR(b.fin)}'),
                KpiSigh(
                    libelle: 'Encaissé',
                    valeur: money(encaisse),
                    icone: LucideIcons.banknote,
                    ton: TonSigh.succes),
                KpiSigh(
                    libelle: 'Reste à encaisser',
                    valeur: money(som(ops, 'reliquat')),
                    icone: LucideIcons.hourglass,
                    ton: TonSigh.attention),
                KpiSigh(
                    libelle: 'Avoirs',
                    valeur: nombre(avoirs.length),
                    icone: LucideIcons.fileMinus,
                    ton: avoirs.isNotEmpty ? TonSigh.danger : TonSigh.neutre,
                    indice: money(som(avoirs, 'montantTTC').abs())),
              ]),
              const SizedBox(height: 16),
              CarteSigh(
                  titre: 'Ventilation des encaissements',
                  sansRemplissage: true,
                  child: MiniTableauSigh(
                      vide: 'Aucune donnée.',
                      colonnes: [
                        ColonneMini('Mode de règlement', (r) => '${r['mode']}'),
                        ColonneMini('Montant', (r) => m(r['montant']),
                            droite: true),
                        ColonneMini(
                            'Part',
                            (r) => encaisse != 0
                                ? '${(n(r['montant']) * 100 / encaisse).round()} %'
                                : '—',
                            droite: true),
                      ],
                      lignes: ventilation)),
              const SizedBox(height: 16),
              TableauSigh(
                titre: 'Pièces passées en caisse',
                lignes: ops,
                taillePage: 15,
                triInitial: 'date',
                sensInitial: 'desc',
                nomExport: 'operations-caisse',
                messageVide: 'Aucune opération sur la période.',
                filtres: [
                  FiltreTableau(
                      nom: 'piece',
                      libelle: 'Type de pièce',
                      options: const [
                        OptionChamp('facture', 'Factures'),
                        OptionChamp('avoir', 'Avoirs'),
                        OptionChamp('proforma', 'Pro-forma')
                      ],
                      correspond: (f, v) => v == 'avoir'
                          ? n(f['montantTTC']) < 0
                          : (v == 'proforma'
                              ? f['proforma'] == true
                              : n(f['montantTTC']) >= 0 &&
                                  f['proforma'] != true)),
                  const FiltreTableau(
                      nom: 'statutPaiement',
                      libelle: 'Règlement',
                      options: [
                        OptionChamp('soldee', 'Soldée'),
                        OptionChamp('partielle', 'Partielle'),
                        OptionChamp('impayee', 'Impayée')
                      ]),
                ],
                colonnes: [
                  ColonneTableau(
                      cle: 'numero',
                      libelle: 'Pièce',
                      sansCoupure: true,
                      texte: (f) => '${f['numero']}',
                      rendu: (_, f) =>
                          Row(mainAxisSize: MainAxisSize.min, children: [
                            Text('${f['numero']}',
                                style: const TextStyle(
                                    fontFamily: 'LiberationMono',
                                    fontSize: 12,
                                    color: JetonsShell.slate700)),
                            if (n(f['montantTTC']) < 0)
                              const Padding(
                                  padding: EdgeInsets.only(left: 4),
                                  child:
                                      BadgeSigh('Avoir', ton: TonSigh.danger)),
                            if (f['operationDissociee'] == true)
                              const Padding(
                                  padding: EdgeInsets.only(left: 4),
                                  child: BadgeSigh('Comptoir')),
                          ])),
                  ColonneTableau(
                      cle: 'date',
                      libelle: 'Date',
                      sansCoupure: true,
                      texte: (f) => dateDe(f['date']),
                      valeur: (f) => f['date']),
                  ColonneTableau(
                      cle: 'patient',
                      libelle: 'Patient',
                      texte: (f) => '${f['patient'] ?? ''}',
                      rendu: (_, f) => Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('${f['patient'] ?? ''}',
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: JetonsShell.slate700,
                                        fontSize: 14,
                                        height: 20 / 14)),
                                Text(
                                    f['operationDissociee'] == true
                                        ? 'hors dossier'
                                        : '${f['patientCode'] ?? '—'}',
                                    style: const TextStyle(
                                        fontFamily: 'LiberationMono',
                                        fontSize: 12,
                                        color: JetonsShell.slate400)),
                              ])),
                  const ColonneTableau(cle: 'type', libelle: 'Nature'),
                  ColonneTableau(
                      cle: 'montantTTC',
                      libelle: 'Montant',
                      droite: true,
                      texte: (f) => m(f['montantTTC'])),
                  ColonneTableau(
                      cle: 'montantPaye',
                      libelle: 'Encaissé',
                      droite: true,
                      texte: (f) => m(f['montantPaye']),
                      rendu: (_, f) => Text(m(f['montantPaye']),
                          style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: JetonsShell.slate700))),
                  ColonneTableau(
                      cle: 'modePaiement',
                      libelle: 'Règlement',
                      texte: (f) => modeLabel(f['modePaiement'])),
                ],
              ),
            ]);
      },
    );
  }

  /// L'inventaire arrête la caisse et confronte le THÉORIQUE (espèces encaissées sur la période) au COMPTÉ.
  void _inventaire(BuildContext ctx, Bornes b, List<Fiche> ops) {
    final c = ContexteEcran.of(ctx);
    final theorique = ops
        .where((f) => (f['modePaiement'] ?? 'especes') == 'especes')
        .fold<num>(0, (a, x) => a + n(x['montantPaye']));
    final form = ControleurFormulaire(const [
      ChampDef(
          nom: 'compte',
          libelle: 'Espèces comptées en caisse (FCFA)',
          type: TypeChamp.nombre,
          requis: true),
      ChampDef(nom: 'agent', libelle: 'Agent de caisse', requis: true),
      ChampDef(
          nom: 'observation',
          libelle: 'Observation',
          type: TypeChamp.textarea,
          lignes: 2,
          col: ColChamp.plein),
    ], {
      'compte': '${theorique.round()}',
      'agent': c.utilisateur
    });
    afficherModale<void>(ctx,
        titre: 'Inventaire de caisse — ${b.label.toLowerCase()}',
        taille: TailleModale.lg,
        corps: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              DescListeSigh([
                ('Périodicité', b.label),
                ('Période', '${dateFR(b.debut)} → ${dateFR(b.fin)}'),
                ('Opérations', nombre(ops.length)),
                (
                  'Encaissé toutes formes',
                  money(ops.fold<num>(0, (a, x) => a + n(x['montantPaye'])))
                ),
                ('Dont espèces (théorique)', money(theorique)),
              ]),
              const SizedBox(height: 12),
              FormulaireSigh(controleur: form),
              const SizedBox(height: 12),
              ListenableBuilder(
                  listenable: form,
                  builder: (_, __) {
                    final e = n(form['compte']) - theorique;
                    return e == 0
                        ? const NoteSigh(
                            'Caisse juste. L’espèce comptée correspond au théorique.',
                            ton: TonSigh.succes,
                            icone: LucideIcons.circleCheck)
                        : NoteSigh(
                            'Écart de ${money(e.abs())} — ${e > 0 ? 'excédent' : 'manquant'}. Un écart doit être expliqué avant clôture : il figurera sur l’état d’inventaire.',
                            ton: TonSigh.attention,
                            icone: LucideIcons.triangleAlert);
                  }),
            ]),
        pied: (fermer) => [
              BoutonSigh(
                  libelle: 'Annuler',
                  variante: VarianteBouton.secondaire,
                  onPressed: fermer),
              BoutonSigh(
                  libelle: 'Éditer l’inventaire',
                  icone: LucideIcons.printer,
                  onPressed: () {
                    final v = form.valider();
                    if (v == null) return;
                    final compte = n(v['compte']);
                    final ecart = compte - theorique;
                    fermer();
                    afficherApercu(
                        ctx,
                        PieceA4(
                          titre:
                              'Inventaire de caisse — ${b.label.toLowerCase()}',
                          sousTitre: '${dateFR(b.debut)} au ${dateFR(b.fin)}',
                          reference: PieceA4.reference_(
                              c.aujourdhui, ImpressionPoste.prochainNumero()),
                          utilisateur: c.utilisateur,
                          edite: c.aujourdhui,
                          cartouche: [
                            ('Périodicité', b.label),
                            ('Arrêté au', dateFR(b.fin)),
                            ('Opérations', nombre(ops.length)),
                            ('Agent de caisse', '${v['agent']}'),
                            ('Théorique espèces', money(theorique)),
                            ('Compté', money(compte)),
                          ],
                          blocs: [
                            BlocTableau(TableauEtat(colonnes: [
                              ColonneEtat(
                                  libelle: 'Rubrique', valeur: (r) => r['k']),
                              ColonneEtat(
                                  libelle: 'Montant',
                                  valeur: (r) => r['v'],
                                  droite: true),
                            ], lignes: [
                              {
                                'k': 'Encaissements de la période',
                                'v': m(ops.fold<num>(
                                    0, (a, x) => a + n(x['montantPaye'])))
                              },
                              {'k': 'Dont espèces', 'v': m(theorique)},
                              {'k': 'Espèces comptées', 'v': m(compte)},
                              {
                                'k': ecart == 0
                                    ? 'Écart'
                                    : (ecart > 0
                                        ? 'Excédent constaté'
                                        : 'Manquant constaté'),
                                'v': m(ecart.abs())
                              },
                            ])),
                            if ('${v['observation'] ?? ''}'.isNotEmpty)
                              BlocTexte('Observation : ${v['observation']}'),
                          ],
                          signatures: [
                            Signature('L’agent de caisse',
                                nom: '${v['agent']}'),
                            const Signature('La Directrice Administrative',
                                nom: 'TAKI Alimatou')
                          ],
                        ));
                  }),
            ]);
  }
}
