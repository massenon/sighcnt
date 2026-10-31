import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../donnees/parcours_caisse.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'commun.dart';
import 'factures.dart';
import 'impression.dart';

const _categories = {
  'analyse': 'Analyse',
  'medicament': 'Médicament',
  'acte': 'Acte',
  'consultation': 'Consultation',
  'hospitalisation': 'Hospitalisation',
  'imagerie': 'Imagerie',
};

/// `m8-caisse` — « État de caisse journalier » : l'arrêté est un ÉTAT CALCULÉ (il ne se saisit pas) ; la FILE D'ATTENTE, elle, se traite ici :
/// chaque prescription encaissée débloque aussitôt la délivrance des médicaments et le prélèvement au laboratoire.
class EcranCaisse extends StatefulWidget with EcranMaquette {
  const EcranCaisse({super.key});

  @override
  String get titre => 'État de caisse journalier';

  @override
  String get description =>
      'Arrêté de caisse : encaissements du jour ventilés par mode de règlement et par nature de prestation.';

  @override
  String get regle =>
      'L’arrêté journalier est un état calculé : il découle des paiements et ne se saisit pas. La file d’attente, en revanche, se traite ici : chaque prescription encaissée débloque aussitôt la délivrance des médicaments et le prélèvement au laboratoire.';

  @override
  List<Widget> actionsEntete(BuildContext context) {
    final c = ContexteEcran.of(context);
    return [
      BoutonSigh(
          libelle: 'Ordonnances',
          icone: LucideIcons.fileText,
          variante: VarianteBouton.secondaire,
          onPressed: () => c.aller('m2-ordonnances')),
      if (c.droit.editer)
        BoutonSigh(
            libelle: 'Nouvelle facture',
            icone: LucideIcons.plus,
            onPressed: () => c.aller('m8-facturation')),
    ];
  }

  @override
  State<EcranCaisse> createState() => _EcranCaisseState();
}

class _EcranCaisseState extends State<EcranCaisse> {
  ControleurFormulaire? _f;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _f ??= ControleurFormulaire(const [
      ChampDef(
          nom: 'jour',
          libelle: 'Journée de caisse',
          type: TypeChamp.date,
          col: ColChamp.tiers)
    ], {
      'jour': iso(ContexteEcran.of(context).aujourdhui)
    })
      ..addListener(() => setState(() {}));
  }

  String get _jour => '${_f!['jour']}';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('factures');
    return ListenableBuilder(
      listenable: col,
      builder: (context, _) {
        final f = [
          for (final x in col.actives)
            if ('${x['date']}'.startsWith(_jour)) x
        ];
        num som(Iterable<Fiche> r, String k) =>
            r.fold<num>(0, (a, x) => a + n(x[k]));
        final parMode = [
          for (final mp in modesPaiement.take(4))
            () {
              final sel = [
                for (final x in f)
                  if (x['modePaiement'] == mp.$1) x
              ];
              return <String, Object?>{
                'mode': mp.$2,
                'nb': sel.length,
                'montant': som(sel, 'montantPaye')
              };
            }()
        ];
        final parNature = <String, List<Fiche>>{};
        for (final x in f) {
          parNature.putIfAbsent('${x['type']}', () => []).add(x);
        }
        final jourLisible = () {
          final d = DateTime.tryParse(_jour);
          return d == null ? _jour : dateFR(d);
        }();
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FileAttenteSigh(
                  type: 'encaissement',
                  titre: 'Prescriptions à encaisser',
                  vide: 'Aucune prescription en attente de règlement.',
                  icone: LucideIcons.coins,
                  action: 'Encaisser',
                  surAction: (ctx, t) => _encaisser(ctx, t)),
              const SizedBox(height: 16),
              CarteSigh(
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                    Expanded(child: FormulaireSigh(controleur: _f!)),
                    const SizedBox(width: 12),
                    BoutonSigh(
                        libelle: 'Éditer l’arrêté de caisse',
                        icone: LucideIcons.printer,
                        onPressed: () => _arrete(context, f, parMode)),
                  ])),
              const SizedBox(height: 16),
              KpiGrilleSigh(kpis: [
                KpiSigh(
                    libelle: 'Factures émises',
                    valeur: nombre(f.length),
                    icone: LucideIcons.receipt),
                KpiSigh(
                    libelle: 'Chiffre d’affaires',
                    valeur: money(som(f, 'montantTTC')),
                    icone: LucideIcons.trendingUp,
                    ton: TonSigh.info),
                KpiSigh(
                    libelle: 'Total encaissé',
                    valeur: money(som(f, 'montantPaye')),
                    icone: LucideIcons.banknote,
                    ton: TonSigh.succes),
                KpiSigh(
                    libelle: 'Reliquats du jour',
                    valeur: money(som(f, 'reliquat')),
                    icone: LucideIcons.handCoins,
                    ton: TonSigh.attention),
              ]),
              const SizedBox(height: 16),
              // Registre des pièces du jour : le patient revient avec son reçu, la caisse retrouve sa pièce et REPREND l'encaissement là où il s'était arrêté.
              CarteSigh(
                  titre: 'Pièces de la journée — reçus et reliquats',
                  sansRemplissage: true,
                  child: TableauSigh(
                    lignes: f,
                    messageVide: 'Aucune pièce émise sur cette journée.',
                    colonnes: [
                      const ColonneTableau(cle: 'numero', libelle: 'Pièce'),
                      ColonneTableau(
                          cle: 'patient',
                          libelle: 'Patient',
                          texte: (r) =>
                              '${r['patient']} — ${r['patientCode']}'),
                      const ColonneTableau(cle: 'type', libelle: 'Nature'),
                      ColonneTableau(
                          cle: 'detail',
                          libelle: 'Prestations',
                          triable: false,
                          texte: (r) {
                            final l = (r['lignes'] as List?) ?? const [];
                            if (l.isEmpty) return 'sans détail';
                            return '${l.where((x) => (x as Map)['statutPaiement'] == 'paye').length} réglée(s) sur ${l.length}';
                          }),
                      ColonneTableau(
                          cle: 'montantTTC',
                          libelle: 'Total',
                          droite: true,
                          texte: (r) => money(r['montantTTC'])),
                      ColonneTableau(
                          cle: 'montantPaye',
                          libelle: 'Encaissé',
                          droite: true,
                          texte: (r) => money(r['montantPaye'])),
                      ColonneTableau(
                          cle: 'reliquat',
                          libelle: 'Reste dû',
                          droite: true,
                          texte: (r) => n(r['reliquat']) > 0
                              ? money(r['reliquat'])
                              : 'soldée',
                          rendu: (_, r) => n(r['reliquat']) > 0
                              ? Text(money(r['reliquat']),
                                  style: const TextStyle(
                                      color: JetonsShell.warning700,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14))
                              : const BadgeSigh('soldée', ton: TonSigh.succes)),
                    ],
                    actionsLigne: (ctx, r) => [
                      BoutonIcone(
                          icone: LucideIcons.printer,
                          libelle: 'Réimprimer le reçu détaillé',
                          onPressed: () => imprimerRecu(ctx, r)),
                      // Reprendre l'encaissement : la demande exacte de la Direction pour le patient qui revient.
                      if (n(r['reliquat']) > 0 && c.droit.editer)
                        BoutonSigh(
                            libelle: 'Encaisser le reste',
                            icone: LucideIcons.coins,
                            taille: TailleBouton.sm,
                            onPressed: () => _encaisser(ctx, {
                                  'factureId': r['id'],
                                  'reference': r['numero']
                                })),
                      BoutonIcone(
                          icone: LucideIcons.eye,
                          libelle: 'Voir le détail des prestations',
                          onPressed: () => _detailPiece(ctx, r)),
                    ],
                  )),
              const SizedBox(height: 16),
              CarteSigh(
                  titre: 'Ventilation par mode de règlement',
                  sansRemplissage: true,
                  child: MiniTableauSigh(colonnes: [
                    ColonneMini('Mode de règlement', (r) => '${r['mode']}'),
                    ColonneMini('Opérations', (r) => '${r['nb']}',
                        droite: true),
                    ColonneMini('Montant encaissé', (r) => m(r['montant']),
                        droite: true),
                  ], lignes: parMode)),
              const SizedBox(height: 16),
              CarteSigh(
                  titre: 'Ventilation par nature de prestation',
                  sansRemplissage: true,
                  child: MiniTableauSigh(
                      vide: 'Aucune facture pour cette journée.',
                      colonnes: [
                        ColonneMini('Nature', (r) => '${r['nature']}'),
                        ColonneMini('Factures', (r) => '${r['nb']}',
                            droite: true),
                        ColonneMini('Facturé', (r) => m(r['facture']),
                            droite: true),
                        ColonneMini('Encaissé', (r) => m(r['encaisse']),
                            droite: true),
                      ],
                      lignes: [
                        for (final e in parNature.entries)
                          {
                            'nature': e.key,
                            'nb': e.value.length,
                            'facture': som(e.value, 'montantTTC'),
                            'encaisse': som(e.value, 'montantPaye')
                          }
                      ])),
              const SizedBox(height: 16),
              TableauSigh(
                titre: 'Détail des factures du $jourLisible',
                lignes: f,
                taillePage: 15,
                nomExport: 'caisse-$_jour',
                messageVide: 'Aucune facture émise ce jour.',
                colonnes: [
                  colNumero,
                  colPatient,
                  const ColonneTableau(cle: 'type', libelle: 'Nature'),
                  colMontant,
                  ColonneTableau(
                      cle: 'montantPaye',
                      libelle: 'Encaissé',
                      droite: true,
                      texte: (x) => m(x['montantPaye'])),
                  ColonneTableau(
                      cle: 'modePaiement',
                      libelle: 'Mode',
                      texte: (x) => modeLabel(x['modePaiement']),
                      rendu: (_, x) => BadgeSigh(modeLabel(x['modePaiement']),
                          ton: TonSigh.navy)),
                  colStatutPaiement,
                ],
              ),
            ]);
      },
    );
  }

  /// Détail d'une pièce, prestation par prestation : « quel examen a été payé, on doit savoir ».
  void _detailPiece(BuildContext ctx, Fiche f) {
    final l = lignesDe(f).where((x) => x['id'] != null).toList();
    final payees = [
      for (final x in l)
        if (x['statutPaiement'] == 'paye') x
    ];
    final dues = [
      for (final x in l)
        if (x['statutPaiement'] != 'paye') x
    ];
    Widget tab(List<Fiche> rows, String vide) => rows.isEmpty
        ? Text(vide,
            style: const TextStyle(
                color: JetonsShell.slate400,
                fontSize: 14,
                fontStyle: FontStyle.italic))
        : MiniTableauSigh(colonnes: [
            ColonneMini(
                'Nature',
                (x) =>
                    _categories['${x['categorie']}'] ??
                    '${x['categorie'] ?? '—'}'),
            ColonneMini('Prestation', (x) => '${x['designation']}'),
            ColonneMini('Qté', (x) => nombre(x['quantite'] ?? 1), droite: true),
            ColonneMini(
                'Part assureur',
                (x) =>
                    n(x['partAssureur']) > 0 ? money(x['partAssureur']) : '—',
                droite: true),
            ColonneMini(
                'À la charge du patient', (x) => money(x['partPatient']),
                droite: true),
          ], lignes: rows);
    afficherTiroir<void>(ctx,
        titre: '${f['numero']} — ${f['patient']}',
        sousTitre: '${dateDe(f['date'])} · ${f['type']}',
        corps:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DescListeSigh([
            ('Pièce', f['numero']),
            ('Patient', '${f['patient']} — ${f['patientCode']}'),
            ('Total de la pièce', money(f['montantTTC'])),
            (
              'Part assureur',
              n(f['partAssurance']) > 0 ? money(f['partAssurance']) : '—'
            ),
            ('Part patient', money(f['partPatient'])),
            ('Encaissé', money(f['montantPaye'])),
            ('Reste dû', money(f['reliquat'])),
            (
              'Base MECeF',
              f['baseMecef'] != null
                  ? money(f['baseMecef'])
                  : money(f['montantPaye'])
            ),
          ]),
          const SizedBox(height: 16),
          const Text('Prestations réglées',
              style: TextStyle(
                  color: JetonsShell.slate900,
                  fontSize: 14,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          tab(payees, 'Aucune prestation réglée à ce jour.'),
          const SizedBox(height: 16),
          const Text('Reste à régler',
              style: TextStyle(
                  color: JetonsShell.slate900,
                  fontSize: 14,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          tab(dues, 'Tout est réglé.'),
          if (dues.isNotEmpty) ...[
            const SizedBox(height: 16),
            const NoteSigh(
                'Ces prestations ne sont pas exécutées tant qu’elles ne sont pas réglées : le laboratoire et la pharmacie ne les voient pas. Le patient peut revenir les acquitter — le reçu en fait foi.',
                ton: TonSigh.attention,
                icone: LucideIcons.lock),
          ],
        ]),
        pied: (_) => [
              BoutonSigh(
                  libelle: 'Réimprimer le reçu',
                  icone: LucideIcons.printer,
                  onPressed: () => imprimerRecu(ctx, f))
            ]);
  }

  /// Le caissier COCHE les prestations que le patient règle ; le total suit la sélection, et non l'inverse : c'est ce renversement qui fait qu'un
  /// paiement partiel libère exactement les examens payés.
  void _encaisser(BuildContext ctx, Fiche tache) {
    final c = ContexteEcran.of(ctx);
    final col = c.magasin.collection('factures');
    final fac = col.parId(tache['factureId']);
    if (fac == null) {
      ToastsSigh.afficher(ctx, 'Facture introuvable.', type: TypeToast.erreur);
      return;
    }
    final toutes = [
      for (final l in (fac['lignes'] as List? ?? const []))
        (l as Map).cast<String, Object?>()
    ];
    final lignes = [
      for (final l in toutes)
        if (l['statutPaiement'] != 'paye') l
    ];
    final deja = [
      for (final l in toutes)
        if (l['statutPaiement'] == 'paye') l
    ];
    final choisies = {for (final l in lignes) '${l['id']}'};
    final version = ValueNotifier(0);
    final form = ControleurFormulaire([
      ChampDef(
          nom: 'mode',
          libelle: 'Mode de règlement',
          type: TypeChamp.select,
          options: [for (final x in modesPaiement) OptionChamp(x.$1, x.$2)]),
      const ChampDef(
          nom: 'reference',
          libelle: 'Référence de transaction',
          indicatif: 'N° de transaction, chèque…'),
    ], {
      'mode': 'especes'
    });
    afficherModale<void>(ctx,
        titre: 'Encaisser ${tache['reference']}',
        sousTitre: '${fac['numero']}',
        taille: TailleModale.xl,
        corps: ValueListenableBuilder<int>(
            valueListenable: version,
            builder: (context, _, __) =>
                StatefulBuilder(builder: (context, maj) {
                  final total = lignes
                      .where((l) => choisies.contains('${l['id']}'))
                      .fold<num>(0, (a, l) => a + n(l['partPatient']));
                  final reste =
                      lignes.fold<num>(0, (a, l) => a + n(l['partPatient'])) -
                          total;
                  return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DescListeSigh([
                          ('Patient', fac['patient']),
                          ('Dossier', fac['patientCode']),
                          ('Prescription', tache['reference']),
                          ('Montant total', money(fac['montantTTC'])),
                          (
                            'Part assureur',
                            fac['assureur'] != null
                                ? '${money(fac['partAssurance'])} — ${fac['assureur']}'
                                : 'Sans assurance'
                          ),
                          (
                            'Déjà réglé',
                            deja.isNotEmpty
                                ? '${money(deja.fold<num>(0, (a, l) => a + n(l['partPatient'])))} — ${nombre(deja.length)} prestation(s)'
                                : 'Rien'
                          ),
                        ]),
                        const SizedBox(height: 12),
                        if (lignes.isNotEmpty) ...[
                          const NoteSigh(
                              'Cocher les prestations que le patient règle. Seules les prestations réglées passent au laboratoire et à la pharmacie — un examen non payé reste en attente, nommément, et le patient pourra revenir l’acquitter.',
                              icone: LucideIcons.listChecks),
                          const SizedBox(height: 12),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 288),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                  border:
                                      Border.all(color: JetonsShell.slate200),
                                  borderRadius: BorderRadius.circular(8)),
                              child: SingleChildScrollView(
                                child: Column(children: [
                                  Container(
                                      color: JetonsShell.slate50,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 10),
                                      child: const Row(children: [
                                        SizedBox(width: 40),
                                        Expanded(
                                            child: Text('PRESTATION',
                                                style: TextStyle(
                                                    color: JetonsShell.slate500,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                    letterSpacing: 0.6))),
                                        SizedBox(
                                            width: 110,
                                            child: Text('PART ASSUREUR',
                                                textAlign: TextAlign.right,
                                                style: TextStyle(
                                                    color: JetonsShell.slate500,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                    letterSpacing: 0.6))),
                                        SizedBox(
                                            width: 110,
                                            child: Text('À PAYER',
                                                textAlign: TextAlign.right,
                                                style: TextStyle(
                                                    color: JetonsShell.slate500,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                    letterSpacing: 0.6))),
                                      ])),
                                  for (final l in lignes)
                                    InkWell(
                                      onTap: () => maj(() =>
                                          choisies.contains('${l['id']}')
                                              ? choisies.remove('${l['id']}')
                                              : choisies.add('${l['id']}')),
                                      child: Semantics(
                                        checked:
                                            choisies.contains('${l['id']}'),
                                        label: '${l['designation']}',
                                        excludeSemantics: true,
                                        child: Container(
                                          key: Key('caisse:ligne:${l['id']}'),
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 8),
                                          decoration: const BoxDecoration(
                                              border: Border(
                                                  top: BorderSide(
                                                      color: JetonsShell
                                                          .slate100))),
                                          child: Row(children: [
                                            SizedBox(
                                                width: 40,
                                                child: Container(
                                                    width: 16,
                                                    height: 16,
                                                    decoration: BoxDecoration(
                                                        color: choisies.contains(
                                                                '${l['id']}')
                                                            ? JetonsShell
                                                                .navy900
                                                            : Colors.white,
                                                        border: Border.all(
                                                            color: choisies.contains(
                                                                    '${l['id']}')
                                                                ? JetonsShell
                                                                    .navy900
                                                                : JetonsShell
                                                                    .slate300),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                                4)),
                                                    child: choisies.contains('${l['id']}')
                                                        ? const Icon(
                                                            LucideIcons.check,
                                                            size: 12,
                                                            color: Colors.white)
                                                        : null)),
                                            Expanded(
                                                child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                  Text('${l['designation']}',
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                          color: JetonsShell
                                                              .slate800,
                                                          fontSize: 14,
                                                          fontWeight:
                                                              FontWeight.w500)),
                                                  Text(
                                                      '${_categories['${l['categorie']}'] ?? l['categorie']}${n(l['quantite']) > 1 ? ' · ${nombre(l['quantite'])} × ${m(l['prixUnitaire'])}' : ''}',
                                                      style: const TextStyle(
                                                          color: JetonsShell
                                                              .slate400,
                                                          fontSize: 12)),
                                                ])),
                                            SizedBox(
                                                width: 110,
                                                child: Text(
                                                    n(l['partAssureur']) > 0
                                                        ? m(l['partAssureur'])
                                                        : '—',
                                                    textAlign: TextAlign.right,
                                                    style: const TextStyle(
                                                        color: JetonsShell
                                                            .slate500,
                                                        fontSize: 12))),
                                            SizedBox(
                                                width: 110,
                                                child: Text(m(l['partPatient']),
                                                    textAlign: TextAlign.right,
                                                    style: const TextStyle(
                                                        color: JetonsShell
                                                            .slate700,
                                                        fontSize: 14,
                                                        fontWeight:
                                                            FontWeight.w600))),
                                          ]),
                                        ),
                                      ),
                                    ),
                                ]),
                              ),
                            ),
                          ),
                        ] else
                          const NoteSigh(
                              'Cette facture ne porte pas de lignes détaillées — pièce antérieure au règlement par prestation. L’encaissement portera sur le solde global.',
                              ton: TonSigh.attention),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                              color: JetonsShell.slate50,
                              borderRadius: BorderRadius.circular(8)),
                          child: Row(children: [
                            Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('MONTANT À ENCAISSER',
                                      style: TextStyle(
                                          color: JetonsShell.slate500,
                                          fontSize: 12,
                                          letterSpacing: 0.6)),
                                  Text(
                                      money(lignes.isEmpty
                                          ? fac['reliquat']
                                          : total),
                                      key: const Key('caisse:total'),
                                      style: const TextStyle(
                                          color: JetonsShell.navy900,
                                          fontSize: 18,
                                          fontWeight: FontWeight.w700)),
                                ]),
                            const Spacer(),
                            Flexible(
                                child: Text(
                                    reste > 0
                                        ? 'Reste dû après ce règlement : ${money(reste)} — ${nombre(lignes.length - choisies.length)} prestation(s) non réglée(s), non exécutable(s).'
                                        : 'La facture sera intégralement soldée.',
                                    key: const Key('caisse:reste'),
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(
                                        color: JetonsShell.slate500,
                                        fontSize: 14))),
                          ]),
                        ),
                        const SizedBox(height: 12),
                        FormulaireSigh(controleur: form),
                      ]);
                })),
        pied: (fermer) => [
              BoutonSigh(
                  libelle: 'Annuler',
                  variante: VarianteBouton.secondaire,
                  onPressed: fermer),
              if (lignes.isNotEmpty)
                BoutonSigh(
                    libelle: 'Tout cocher',
                    icone: LucideIcons.checkCheck,
                    variante: VarianteBouton.secondaire,
                    onPressed: () {
                      choisies.addAll([for (final l in lignes) '${l['id']}']);
                      version.value++;
                    }),
              BoutonSigh(
                  libelle: 'Valider l’encaissement',
                  icone: LucideIcons.check,
                  onPressed: () {
                    if (lignes.isNotEmpty && choisies.isEmpty) {
                      ToastsSigh.afficher(ctx, 'Aucune prestation cochée.',
                          type: TypeToast.erreur,
                          detail: 'Cocher au moins une prestation à régler.');
                      return;
                    }
                    ResultatCaisse res;
                    try {
                      res = encaisserFacture(c.magasin, '${fac['id']}',
                          lignes: lignes.isNotEmpty ? choisies.toList() : null,
                          montant: lignes.isEmpty ? n(fac['reliquat']) : null,
                          mode: '${form['mode']}',
                          maintenant: c.aujourdhui);
                    } on RefusCaisse catch (e) {
                      if (e.code == 'VERSEMENT_REFUSE') {
                        ToastsSigh.afficher(ctx, 'Encaissement refusé.',
                            type: TypeToast.erreur,
                            detail: e.motif,
                            duree: const Duration(seconds: 9));
                        return;
                      }
                      ToastsSigh.afficher(
                          ctx, 'Encaissement impossible : ${e.motif}',
                          type: TypeToast.erreur);
                      return;
                    }
                    if ('${form['reference']}'.isNotEmpty)
                      col.mettreAJour(fac['id'],
                          {'referenceTransaction': form['reference']});
                    fermer();
                    final detail = [
                      if (res.demandesLiberees.isNotEmpty)
                        '${nombre(res.demandesLiberees.length)} examen(s) transmis au laboratoire',
                      if (res.debloquees.contains('dispensation'))
                        'pharmacie débloquée',
                      if (res.restantDu > 0)
                        'reste ${money(res.restantDu)} à régler',
                    ];
                    ToastsSigh.afficher(ctx,
                        'Encaissement validé — ${money(res.montantRegle)}.',
                        type: TypeToast.succes,
                        detail: detail.isEmpty
                            ? 'Aucune suite à débloquer.'
                            : detail.join(' · '),
                        annuler: res.annuler,
                        duree: const Duration(seconds: 9));
                    // Le reçu est la pièce que le patient emporte : proposé immédiatement, il nomme ce qui est payé et ce qui reste.
                    afficherModale<void>(ctx,
                        titre: 'Reçu de paiement',
                        sousTitre: '${fac['numero']}',
                        corps: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              DescListeSigh([
                                ('Encaissé', money(res.montantRegle)),
                                (
                                  'Prestations réglées',
                                  nombre(res.lignesReglees.length)
                                ),
                                ('Reste à payer', money(res.restantDu)),
                                (
                                  'Examens transmis au laboratoire',
                                  nombre(res.demandesLiberees.length)
                                ),
                              ]),
                              if (res.restantDu > 0) ...[
                                const SizedBox(height: 12),
                                const NoteSigh(
                                    'Le patient conserve ce reçu : il nomme les prestations restant dues, et lui permet de revenir les acquitter sans reprendre toute la facture.',
                                    ton: TonSigh.attention),
                              ],
                            ]),
                        pied: (f2) => [
                              BoutonSigh(
                                  libelle: 'Fermer',
                                  variante: VarianteBouton.secondaire,
                                  onPressed: f2),
                              BoutonSigh(
                                  libelle: 'Imprimer le reçu',
                                  icone: LucideIcons.printer,
                                  onPressed: () => imprimerRecu(
                                          ctx, col.parId(fac['id'])!,
                                          versement: {
                                            'montant': res.montantRegle,
                                            'modePaiement': form['mode'],
                                            'reference': form['reference']
                                          })),
                            ]);
                  }),
            ]);
  }

  void _arrete(
      BuildContext ctx, List<Fiche> f, List<Map<String, Object?>> parMode) {
    final c = ContexteEcran.of(ctx);
    num som(Iterable<Fiche> r, String k) =>
        r.fold<num>(0, (a, x) => a + n(x[k]));
    final d = DateTime.tryParse(_jour) ?? c.aujourdhui;
    afficherApercu(
        ctx,
        PieceA4(
          titre: 'État de caisse journalier',
          sousTitre: 'Journée du ${dateFR(d)}',
          reference: PieceA4.reference_(
              c.aujourdhui, ImpressionPoste.prochainNumero()),
          utilisateur: c.utilisateur,
          edite: c.aujourdhui,
          cartouche: [
            ('Date', dateFR(d)),
            ('Factures émises', nombre(f.length)),
            ('Chiffre d’affaires', money(som(f, 'montantTTC'))),
            ('Total encaissé', money(som(f, 'montantPaye'))),
            ('Reliquats', money(som(f, 'reliquat'))),
            ('Caissier', c.utilisateur),
          ],
          blocs: [
            BlocTableau(
                TableauEtat(colonnes: [
                  ColonneEtat(
                      libelle: 'Mode de règlement', valeur: (r) => r['mode']),
                  ColonneEtat(
                      libelle: 'Opérations',
                      valeur: (r) => r['nb'],
                      droite: true),
                  ColonneEtat(
                      libelle: 'Montant',
                      valeur: (r) => m(r['montant']),
                      droite: true,
                      somme: (r) => n(r['montant'])),
                ], lignes: parMode),
                titre: 'Ventilation par mode de règlement'),
            BlocTableau(
                TableauEtat(colonnes: [
                  ColonneEtat(
                      libelle: 'N° facture', valeur: (r) => r['numero']),
                  ColonneEtat(libelle: 'Patient', valeur: (r) => r['patient']),
                  ColonneEtat(libelle: 'Nature', valeur: (r) => r['type']),
                  ColonneEtat(
                      libelle: 'Montant',
                      valeur: (r) => m(r['montantTTC']),
                      droite: true,
                      somme: (r) => n(r['montantTTC'])),
                  ColonneEtat(
                      libelle: 'Encaissé',
                      valeur: (r) => m(r['montantPaye']),
                      droite: true,
                      somme: (r) => n(r['montantPaye'])),
                  ColonneEtat(
                      libelle: 'Reste',
                      valeur: (r) => m(r['reliquat']),
                      droite: true,
                      somme: (r) => n(r['reliquat'])),
                ], lignes: f),
                titre: 'Détail des factures'),
          ],
          signatures: [
            Signature('Le Caissier', nom: c.utilisateur),
            const Signature('Le Comptable', nom: 'KASSA Augustin'),
            const Signature('La Directrice Administrative',
                nom: 'TAKI Alimatou')
          ],
        ));
  }
}
