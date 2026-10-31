import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'cpc_commun.dart';

/// `m12-echeances` — « Échéances fiscales & paiements » : le SUIVI des obligations du calendrier fiscal (ce qui est dû, ce qui approche, ce qui est
/// réglé). La référence documentaire des règles est `cfg-comptabilite` ; cet écran ne calcule que des ÉTATS, jamais stockés.
///
/// Une échéance dépassée et non réglée est un risque de pénalité : elle est signalée à l'ouverture (barre de notification et alerte), pas seulement
/// listée. La validation d'un paiement porte son auteur, sa date et sa référence de quittance (RG-12) ; elle s'annule avec un motif, la trace du paiement
/// initial restant au journal d'audit. Règles dans `cpc_echeances.dart` (rejouées sur les vecteurs de la maquette).
///
/// Écarts : E804 (corrigé dans la maquette d'abord : « La prochaine obligation tombe le undefined ») ; E806 (la maquette offre « Valider le paiement » et
/// « Annuler la validation » à tout profil qui ouvre l'écran, y compris en lecture seule — au poste elles sont ABSENTES sans le droit d'écrire) ; E807
/// (l'alerte sonore de l'ouverture est le message seul : le poste ne porte pas encore le canal audio).
class EcranEcheances extends StatefulWidget with EcranMaquette {
  const EcranEcheances({super.key});

  @override
  String get titre => 'Échéances fiscales & paiements';

  @override
  String get description => 'Suivi des obligations fiscales et sociales : ce qui est dû, ce qui approche, ce qui est réglé.';

  @override
  String get regle =>
      'Chaque obligation du calendrier est déroulée sur l’exercice. Une échéance dépassée et non réglée est signalée à l’ouverture de l’écran — une pénalité se constate rarement à temps. La validation d’un paiement porte son auteur, sa date et sa référence de quittance (RG-12).';

  @override
  List<Widget> actionsEntete(BuildContext context) => [
        BoutonSigh(
            libelle: 'Obligations & règles',
            icone: LucideIcons.bookOpenCheck,
            variante: VarianteBouton.secondaire,
            onPressed: () => ContexteEcran.of(context).aller('cfg-comptabilite')),
      ];

  @override
  State<EcranEcheances> createState() => _EtatEcheances();
}

class _EtatEcheances extends State<EcranEcheances> {
  Timer? _alerte;
  bool _demarre = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_demarre) return;
    _demarre = true;
    final c = ContexteEcran.of(context);
    // « Le comptable ne consulte pas l'écran tous les jours ; c'est l'écran qui doit l'avertir » : l'alerte part 800 ms après l'ouverture.
    _alerte = Timer(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      final a = cpcAlerteOuverture(_lignes(c));
      if (a == null) return;
      ToastsSigh.afficher(context, a.message,
          type: a.type == 'error' ? TypeToast.erreur : TypeToast.attention, detail: a.detail, duree: const Duration(seconds: 9));
    });
  }

  @override
  void dispose() {
    _alerte?.cancel();
    super.dispose();
  }

  List<Fiche> _lignes(ContexteEcran c) => cpcLignesEcheances(c.magasin.collection('echeancesFiscales').actives, c.aujourdhui);

  TonSigh _ton(String t) => switch (t) {
        'succes' => TonSigh.succes,
        'danger' => TonSigh.danger,
        'attention' => TonSigh.attention,
        'info' => TonSigh.info,
        _ => TonSigh.neutre,
      };

  static String _d(Object? v) => dateDe(v);

  // ----------------------------------------------------------------------------------------------------------------------------------------------
  // LA BARRE DE NOTIFICATION
  // ----------------------------------------------------------------------------------------------------------------------------------------------
  Widget _alerteCarte(BuildContext ctx, ContexteEcran c, CpcAlerteEcheance a) {
    final (fond, bord, texte, fort, icone) = switch (a.ton) {
      'danger' => (JetonsShell.danger50, JetonsShell.danger200, JetonsShell.danger800, JetonsShell.danger900, LucideIcons.alarmClock),
      'warning' => (JetonsShell.warning50, JetonsShell.warning200, JetonsShell.warning800, JetonsShell.warning900, LucideIcons.coins),
      'info' => (JetonsShell.info50, JetonsShell.info200, JetonsShell.info800, JetonsShell.info900, LucideIcons.fileSignature),
      _ => (JetonsShell.success50, JetonsShell.success200, JetonsShell.success800, JetonsShell.success900, LucideIcons.circleCheck),
    };
    return Container(
      key: Key('cpc:alerte:${a.ton}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: fond, border: Border.all(color: bord), borderRadius: BorderRadius.circular(8)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 2), child: Icon(icone, size: 16, color: texte)),
        const SizedBox(width: 12),
        Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(a.titre, style: TextStyle(color: fort, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600)),
          Padding(padding: const EdgeInsets.only(top: 2), child: Text(a.detail, style: TextStyle(color: texte, fontSize: 12, height: 16 / 12))),
        ])),
        if (a.cible != null && c.droit.editer)
          BoutonSigh(
              libelle: 'Valider le paiement',
              taille: TailleBouton.sm,
              variante: a.ton == 'danger' ? VarianteBouton.danger : VarianteBouton.primaire,
              icone: LucideIcons.check,
              onPressed: () => _valider(ctx, c, a.cible!)),
      ]),
    );
  }

  // ----------------------------------------------------------------------------------------------------------------------------------------------
  // VALIDER UN PAIEMENT EFFECTUÉ
  // ----------------------------------------------------------------------------------------------------------------------------------------------
  void _valider(BuildContext ctx, ContexteEcran c, Fiche e) {
    final f = ControleurFormulaire([
      const ChampDef(nom: 'datePaiement', libelle: 'Date du paiement', type: TypeChamp.date, requis: true),
      ChampDef(
          nom: 'montant',
          libelle: 'Montant réglé (FCFA)',
          type: TypeChamp.nombre,
          requis: true,
          valider: (v, _) => (double.tryParse('$v') ?? 0) < 1 ? 'La valeur minimale est 1.' : null),
      ChampDef(nom: 'moyen', libelle: 'Moyen de règlement', type: TypeChamp.select, requis: true, options: [for (final m in cpcMoyensReglement) OptionChamp(m)]),
      const ChampDef(nom: 'reference', libelle: 'Référence de quittance', requis: true, aide: 'Numéro du reçu délivré par l’administration.'),
      const ChampDef(nom: 'valideePar', libelle: 'Validé par', requis: true),
      const ChampDef(nom: 'observation', libelle: 'Observation', type: TypeChamp.textarea, lignes: 2, col: ColChamp.plein),
    ], {'datePaiement': iso(c.aujourdhui), 'valideePar': acteurDe(c)});
    final j = e['jours'] as int;
    afficherModale<void>(ctx,
        titre: 'Valider le paiement — ${e['code']}',
        sousTitre: '${e['libelle']} · échéance du ${_d(e['echeance'])}',
        taille: TailleModale.lg,
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DescListeSigh([
            ('Obligation', '${e['libelle']}'),
            ('Période', '${e['periode']}'),
            ('Échéance', '${_d(e['echeance'])}${e['reportee'] == true ? ' (reportée au jour ouvrable)' : ''}'),
            ('Part', e['part'] != null && e['part'] != 0 ? '${e['part']} %' : '—'),
            ('Déclaration préalable', '${e['declaration'] ?? 'aucune'}'),
          ]),
          const SizedBox(height: 12),
          FormulaireSigh(controleur: f),
          const SizedBox(height: 12),
          j < 0
              ? NoteSigh('Échéance dépassée de ${j.abs()} jour(s). Une pénalité de retard peut s’appliquer : la consigner en observation.',
                  ton: TonSigh.danger, icone: LucideIcons.alarmClock)
              : const NoteSigh(
                  'La validation est journalisée avec son auteur, sa date et sa référence de quittance (RG-12). Elle reste annulable.'),
        ]),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: 'Confirmer le paiement',
                  icone: LucideIcons.check,
                  onPressed: () {
                    final v = f.valider();
                    if (v == null) return;
                    final montant = double.parse('${v['montant']}');
                    final annuler = c.magasin.collection('echeancesFiscales').mettreAJour(
                        e['id'],
                        cpcPatchPaiement(
                            datePaiement: '${v['datePaiement']}',
                            montant: montant,
                            moyen: '${v['moyen']}',
                            reference: '${v['reference']}',
                            valideePar: '${v['valideePar']}',
                            observation: '${v['observation'] ?? ''}'));
                    c.magasin.journaliser('Paiement fiscal validé', 'M12', '${e['libelle']}', '${e['code']}', {'etat': 'non réglée'},
                        {'montant': montant, 'reference': '${v['reference']}'});
                    fermer();
                    ToastsSigh.afficher(ctx, '${e['code']} — paiement de ${money(montant)} validé.',
                        type: TypeToast.succes, detail: 'Quittance ${v['reference']}', annuler: annuler);
                  }),
            ]);
  }

  Future<void> _annuler(BuildContext ctx, ContexteEcran c, Fiche e) async {
    final motif = await confirmerAvecMotif(ctx,
        titre: 'Annuler la validation du paiement ${e['code']} ?',
        message:
            'L’échéance redeviendra due. L’annulation est journalisée — elle ne fait pas disparaître la trace du paiement initialement enregistré.',
        libelleOk: 'Annuler la validation',
        dangereux: true);
    if (motif == null || !ctx.mounted) return;
    final annuler = c.magasin.collection('echeancesFiscales').mettreAJour(e['id'], cpcPatchAnnulation(motif));
    ToastsSigh.afficher(ctx, 'Validation annulée — l’échéance redevient due.', type: TypeToast.attention, annuler: annuler);
  }

  void _rappeler(BuildContext ctx, Fiche e) {
    final r = cpcRappel(e);
    ToastsSigh.afficher(ctx, r.message, type: TypeToast.info, detail: r.detail, duree: const Duration(seconds: 9));
  }

  // ----------------------------------------------------------------------------------------------------------------------------------------------
  // CONSULTER ET IMPRIMER
  // ----------------------------------------------------------------------------------------------------------------------------------------------
  void _fiche(BuildContext ctx, ContexteEcran c, Fiche e) {
    final paye = e['paye'] == true;
    afficherTiroir<void>(ctx,
        titre: '${e['code']} — ${e['libelle']}',
        sousTitre: '${e['periode']} · échéance du ${_d(e['echeance'])}',
        largeurMax: 672,
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DescListeSigh([
            ('Obligation', '${e['libelle']}'),
            ('Périodicité', '${e['periodicite']}'),
            ('Période concernée', '${e['periode']}'),
            ('Échéance', '${_d(e['echeance'])}${e['reportee'] == true ? ' — reportée au jour ouvrable suivant' : ''}'),
            ('Part', e['part'] != null && e['part'] != 0 ? '${e['part']} %' : '—'),
            ('Déclaration préalable', '${e['declaration'] ?? 'aucune'}'),
            ('État', cpcEtat('${e['etat']}').$2),
            ('Montant réglé', e['montant'] != null && e['montant'] != 0 ? money(e['montant']) : '—'),
            ('Quittance', '${e['reference'] ?? '—'}'),
            ('Validé par', '${e['valideePar'] ?? '—'}'),
          ]),
          const SizedBox(height: 16),
          NoteSigh('${e['note'] ?? ''}'),
        ]),
        pied: (fermer) => [
              if (paye)
                BoutonSigh(libelle: 'Éditer la quittance', icone: LucideIcons.printer, onPressed: () => _quittance(ctx, c, e))
              else if (c.droit.editer)
                BoutonSigh(
                    libelle: 'Valider le paiement',
                    icone: LucideIcons.check,
                    onPressed: () {
                      fermer();
                      _valider(ctx, c, e);
                    }),
            ]);
  }

  void _quittance(BuildContext ctx, ContexteEcran c, Fiche e) {
    final montant = e['montant'] != null && e['montant'] != 0 ? money(e['montant']) : '—';
    afficherApercu(
        ctx,
        pieceM9(c,
            titre: 'Justificatif de paiement — obligation fiscale',
            sousTitre: '${e['code']} · ${e['libelle']}',
            cartouche: [
              ('Obligation', '${e['libelle']}'),
              ('Code', '${e['code']}'),
              ('Période', '${e['periode']}'),
              ('Échéance', _d(e['echeance'])),
              ('Date de paiement', e['datePaiement'] != null ? _d(e['datePaiement']) : '—'),
              ('Montant réglé', montant),
              ('Moyen', '${e['moyen'] ?? '—'}'),
              ('Quittance', '${e['reference'] ?? '—'}'),
            ],
            blocs: [
              BlocTableau(TableauEtat(colonnes: [
                ColonneEtat(libelle: 'Rubrique', valeur: (l) => l['k']),
                ColonneEtat(libelle: 'Information', valeur: (l) => l['v']),
              ], lignes: [
                {'k': 'Obligation', 'v': '${e['libelle']}'},
                {'k': 'Base réglementaire', 'v': '${e['note']}'},
                {'k': 'Part acquittée', 'v': e['part'] != null && e['part'] != 0 ? '${e['part']} %' : 'Intégralité'},
                {'k': 'Déclaration préalable', 'v': '${e['declaration'] ?? 'Sans objet'}'},
                {'k': 'Référence de quittance', 'v': '${e['reference'] ?? '—'}'},
                {'k': 'Validé par', 'v': '${e['valideePar'] ?? '—'}'},
                {'k': 'Observation', 'v': '${e['observation'] ?? '—'}'},
              ])),
            ],
            signatures: [Signature('Le Comptable', nom: '${e['valideePar'] ?? 'KASSA Augustin'}'), signDafCompta]));
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return ListenableBuilder(
      listenable: c.magasin.collection('echeancesFiscales'),
      builder: (context, _) {
        final rows = _lignes(c);
        int nb(String s) => rows.where((e) => e['etat'] == s).length;
        final retard = nb('en_retard'), aPayer = nb('a_payer');
        final familles = <String>{for (final e in rows) '${e['famille']}'}.toList()..sort();
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          KpiGrilleSigh(kpis: [
            KpiSigh(
                libelle: 'En retard',
                valeur: nombre(retard),
                icone: LucideIcons.alarmClock,
                ton: retard > 0 ? TonSigh.danger : TonSigh.succes,
                indice: retard > 0 ? 'Risque de pénalité' : 'Aucun retard'),
            KpiSigh(libelle: 'À payer sous 10 jours', valeur: nombre(aPayer), icone: LucideIcons.coins, ton: aPayer > 0 ? TonSigh.attention : TonSigh.succes),
            KpiSigh(libelle: 'Déclarations attendues', valeur: nombre(nb('declaration')), icone: LucideIcons.fileSignature, ton: TonSigh.info),
            KpiSigh(
                libelle: 'Réglées sur l’exercice',
                valeur: nombre(nb('payee')),
                icone: LucideIcons.circleCheck,
                ton: TonSigh.succes,
                indice: '${nombre(rows.length)} échéances au total'),
          ]),
          const SizedBox(height: 16),
          for (final a in cpcBarreEcheances(rows)) _alerteCarte(context, c, a),
          const SizedBox(height: 8),
          TableauSigh(
            titre: 'Échéances de l’exercice ${c.aujourdhui.year}',
            lignes: rows,
            nomExport: 'echeances-fiscales',
            taillePage: 20,
            triInitial: 'echeance',
            filtres: [
              FiltreTableau(
                  nom: 'etat',
                  libelle: 'État',
                  options: [for (final s in cpcEtatsEcheance) OptionChamp(s.$1, s.$2)],
                  correspond: (l, v) => l['etat'] == v),
              FiltreTableau(
                  nom: 'famille',
                  libelle: 'Obligation',
                  options: [for (final f in familles) OptionChamp(f)],
                  correspond: (l, v) => '${l['famille']}' == v),
              FiltreTableau(
                  nom: 'periodicite',
                  libelle: 'Périodicité',
                  options: const [OptionChamp('mensuelle', 'Mensuelle'), OptionChamp('annuelle', 'Annuelle')],
                  correspond: (l, v) => l['periodicite'] == v),
            ],
            alClicLigne: (e) => _fiche(context, c, e),
            colonnes: [
              ColonneTableau(
                  cle: 'code',
                  libelle: 'Code',
                  sansCoupure: true,
                  rendu: (_, e) => monoTexte(e['code'], couleur: JetonsShell.slate800, poids: FontWeight.w600)),
              ColonneTableau(
                  cle: 'libelle',
                  libelle: 'Obligation',
                  texte: (e) => '${e['libelle']} ${e['periode']}${e['part'] != null && (e['part'] as num) < 100 ? ' · tranche de ${e['part']} %' : ''}',
                  rendu: (_, e) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        Text('${e['libelle']}',
                            overflow: TextOverflow.ellipsis, style: const TextStyle(color: JetonsShell.slate800, fontSize: 14, height: 20 / 14)),
                        Text('${e['periode']}${e['part'] != null && (e['part'] as num) < 100 ? ' · tranche de ${e['part']} %' : ''}',
                            overflow: TextOverflow.ellipsis, style: const TextStyle(color: JetonsShell.slate400, fontSize: 12, height: 16 / 12)),
                      ])),
              ColonneTableau(
                  cle: 'echeance',
                  libelle: 'Échéance',
                  sansCoupure: true,
                  valeur: (e) => e['echeance'],
                  texte: (e) => '${_d(e['echeance'])}${e['reportee'] == true ? ' reportée — jour ouvrable' : ''}',
                  rendu: (_, e) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        Text(_d(e['echeance']), style: const TextStyle(color: JetonsShell.slate700, fontSize: 14, height: 20 / 14)),
                        if (e['reportee'] == true)
                          const Text('reportée — jour ouvrable', style: TextStyle(color: JetonsShell.warning600, fontSize: 10, height: 14 / 10)),
                      ])),
              ColonneTableau(
                  cle: 'jours',
                  libelle: 'Délai',
                  droite: true,
                  texte: (e) => e['paye'] == true ? '—' : ((e['jours'] as int) < 0 ? '${(e['jours'] as int).abs()} j de retard' : 'dans ${e['jours']} j'),
                  rendu: (_, e) {
                    final j = e['jours'] as int;
                    if (e['paye'] == true) return const Text('—', style: TextStyle(color: JetonsShell.slate400, fontSize: 12, height: 16 / 12));
                    if (j < 0) {
                      return Text('${j.abs()} j de retard',
                          style: const TextStyle(color: JetonsShell.danger600, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600));
                    }
                    return Text('dans $j j',
                        style: TextStyle(
                            color: j <= 10 ? JetonsShell.warning700 : JetonsShell.slate600,
                            fontSize: 14,
                            height: 20 / 14,
                            fontWeight: j <= 10 ? FontWeight.w600 : FontWeight.w400));
                  }),
              ColonneTableau(
                  cle: 'etat',
                  libelle: 'État',
                  texte: (e) => cpcEtat('${e['etat']}').$2,
                  rendu: (_, e) => BadgeSigh(cpcEtat('${e['etat']}').$2, ton: _ton(cpcEtat('${e['etat']}').$3))),
              ColonneTableau(
                  cle: 'montant',
                  libelle: 'Montant réglé',
                  droite: true,
                  texte: (e) => e['montant'] != null && e['montant'] != 0 ? '${e['montant']}' : '',
                  rendu: (_, e) => e['montant'] != null && e['montant'] != 0
                      ? Text(m(e['montant']), style: const TextStyle(color: JetonsShell.slate800, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600))
                      : const Text('—', style: TextStyle(color: JetonsShell.slate300, fontSize: 12, height: 16 / 12))),
              ColonneTableau(
                  cle: 'valideePar',
                  libelle: 'Validé par',
                  texte: (e) => e['valideePar'] != null ? '${e['valideePar']} ${e['reference'] ?? ''}' : 'non réglée',
                  rendu: (_, e) => e['valideePar'] != null
                      ? Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                          Text('${e['valideePar']}', style: const TextStyle(color: JetonsShell.slate600, fontSize: 12, height: 16 / 12)),
                          Text('${e['reference'] ?? ''}', style: const TextStyle(color: JetonsShell.slate400, fontSize: 10, height: 14 / 10)),
                        ])
                      : const Text('non réglée', style: TextStyle(color: JetonsShell.slate300, fontSize: 12, height: 16 / 12))),
            ],
            actionsLigne: (cx, e) => e['paye'] == true
                ? [
                    BoutonIcone(icone: LucideIcons.printer, libelle: 'Éditer la quittance', onPressed: () => _quittance(context, c, e)),
                    if (c.droit.editer)
                      BoutonIcone(icone: LucideIcons.undo2, libelle: 'Annuler la validation', onPressed: () => _annuler(context, c, e)),
                  ]
                : [
                    if (c.droit.editer)
                      BoutonIcone(icone: LucideIcons.check, libelle: 'Valider le paiement effectué', onPressed: () => _valider(context, c, e)),
                    BoutonIcone(icone: LucideIcons.bell, libelle: 'Rappeler cette échéance', onPressed: () => _rappeler(context, e)),
                  ],
          ),
        ]);
      },
    );
  }
}
