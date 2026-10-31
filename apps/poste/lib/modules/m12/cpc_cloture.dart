import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart' show Signature;
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m6/points_commun.dart' show champUnique, commande;
import 'cpc_commun.dart';

/// `m12-cloture` — « Exercices & clôtures » : sélecteur d'exercice, pré-clôture, clôture EN DEUX GESTES, à-nouveaux et lettrage des tiers.
///
/// La clôture est DÉFINITIVE (obligation légale) : un exercice clos ne se rouvre pas, il se corrige par une écriture de l'exercice suivant. Le comptable
/// DEMANDE, la Direction ou la DAF VALIDE — une autre personne que le demandeur. Le moteur est dans `cpc_exercice.dart` (rejoué sur les vecteurs de la
/// maquette) ; la garde de lecture seule est posée sur la collection `ecritures` du magasin.
///
/// Écarts : E800 (l'acteur d'un geste est le libellé du rôle de la session, le poste ne porte pas d'identité nominative) ; E801 (le sélecteur
/// d'exercice de la coque n'est pas porté : l'exercice choisi est celui de l'horloge, E717) ; E802 (hors du poste : l'archive de clôture dans la GED et
/// l'export CSV de l'exercice clos).
class EcranCloture extends StatefulWidget with EcranMaquette {
  const EcranCloture({super.key});

  @override
  String get titre => 'Exercices & clôtures';

  @override
  String get description =>
      'Sélecteur d’exercice, pré-clôture, clôture en deux gestes, à-nouveaux et lettrage des tiers.';

  @override
  String get regle =>
      'La clôture est définitive (obligation légale) : un exercice clos ne se rouvre pas, il se corrige par une écriture de l’exercice suivant. Le comptable demande, la Direction ou la DAF valide — une autre personne que le demandeur. La caisse continue d’encaisser : le logiciel ne s’arrête pas à la fin de l’année.';

  @override
  State<EcranCloture> createState() => _EtatCloture();
}

String _tronque(String s, int n) => s.length > n ? s.substring(0, n) : s;

class _EtatCloture extends State<EcranCloture> {
  bool _amorce = false;
  late final ControleurFormulaire _compte;
  bool _compteInit = false;
  final Set<Object?> _coches = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_amorce) return;
    _amorce = true;
    final c = ContexteEcran.of(context);
    amorcerExercices(c.magasin, c.aujourdhui);
  }

  List<Fiche> _ecritures(ContexteEcran c) => c.magasin.collection('ecritures').actives;

  // ----------------------------------------------------------------------------------------------------------------------------------------------
  // GESTE 1 — la pré-clôture et la demande
  // ----------------------------------------------------------------------------------------------------------------------------------------------
  void _preCloture(BuildContext ctx, ContexteEcran c, Fiche x, bool peutDemander) {
    final annee = x['annee'] as int;
    final pre = cpcPreCloture(_ecritures(c), annee);
    afficherModale<void>(ctx,
        titre: 'Pré-clôture — exercice $annee',
        taille: TailleModale.lg,
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text.rich(TextSpan(children: [
            TextSpan(text: 'Résultat provisoire de l’exercice $annee : '),
            TextSpan(text: money(pre.resultat), style: const TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(text: ' sur ${nombre(pre.nbEcritures)} ligne(s) validée(s).'),
          ]), style: const TextStyle(color: JetonsShell.slate700, fontSize: 14, height: 20 / 14)),
          const SizedBox(height: 12),
          MiniTableauSigh(colonnes: [
            ColonneMini('Contrôle', (l) => '${l['libelle']}'),
            ColonneMini('Nature', (l) => l['bloquant'] == true ? 'Bloquant' : 'Signalé'),
            ColonneMini('État', (l) => l['ok'] == true ? 'Conforme' : (l['bloquant'] == true ? 'ÉCHEC' : 'À voir')),
            ColonneMini('Détail / où corriger', (l) => l['ok'] == true ? '—' : '${l['detail']} → ${libellesEcransM12[l['ecran']] ?? l['ecran']}'),
          ], lignes: [
            for (final k in pre.controles)
              {'libelle': k.libelle, 'bloquant': k.bloquant, 'ok': k.ok, 'detail': k.detail, 'ecran': k.ecran}
          ]),
        ]),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Fermer', variante: VarianteBouton.secondaire, onPressed: fermer),
              if (peutDemander && pre.bloquants.isEmpty)
                BoutonSigh(
                    libelle: 'Demander la clôture',
                    icone: LucideIcons.lock,
                    onPressed: () {
                      fermer();
                      _demander(ctx, c, x);
                    }),
            ]);
  }

  Future<void> _demander(BuildContext ctx, ContexteEcran c, Fiche x) async {
    final annee = x['annee'] as int;
    final ok = await confirmerSigh(ctx,
        titre: 'Demander la clôture de l’exercice $annee ?',
        message:
            'Les contrôles bloquants sont rejoués. Si tout est conforme, la demande part à la Direction pour validation : tant qu’elle n’est pas validée, rien n’est figé.',
        libelleOk: 'Demander la clôture');
    if (!ok || !ctx.mounted) return;
    final r = cpcDemanderCloture(c.magasin.collection('exercices').toutes, _ecritures(c), annee, acteur: acteurDe(c), maintenant: c.aujourdhui);
    if (!r.ok) {
      ToastsSigh.afficher(ctx, 'Demande refusée.', type: TypeToast.erreur, detail: r.motif);
      return;
    }
    c.magasin.collection('exercices').mettreAJour(x['id'], r.patch!);
    c.magasin.journaliser('Demande de clôture', 'M12', 'Exercice', '$annee', {'etat': 'ouvert'}, {'etat': 'en_attente_cloture', 'resultat': r.pre!.resultat});
    notifier(c,
        type: 'cloture',
        poste: 'direction',
        libelle: 'Clôture $annee à valider',
        detail: 'Le comptable a demandé la clôture de l’exercice $annee.',
        priorite: 'haute',
        reference: '$annee');
    ToastsSigh.afficher(ctx, 'Clôture $annee demandée.', type: TypeToast.succes, detail: 'La Direction doit la valider.');
  }

  // ----------------------------------------------------------------------------------------------------------------------------------------------
  // GESTE 2 — la validation
  // ----------------------------------------------------------------------------------------------------------------------------------------------
  void _valider(BuildContext ctx, ContexteEcran c, Fiche x) {
    final annee = x['annee'] as int;
    final motif = ControleurFormulaire(const [
      ChampDef(nom: 'motif', libelle: 'Motif de la validation (obligatoire)', type: TypeChamp.textarea, col: ColChamp.plein, lignes: 3)
    ]);
    afficherModale<void>(ctx,
        titre: 'Valider la clôture de l’exercice $annee',
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text.rich(TextSpan(children: [
            const TextSpan(text: 'Demandée par '),
            TextSpan(text: '${x['demandePar'] ?? '—'}', style: const TextStyle(fontWeight: FontWeight.w700)),
            const TextSpan(text: '. Cette validation est '),
            const TextSpan(text: 'définitive', style: TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(text: ' : les classes 6, 7 et 8 seront soldées, les à-nouveaux de ${annee + 1} écrits, l’exercice figé. Il ne se rouvre pas.'),
          ]), style: const TextStyle(color: JetonsShell.slate700, fontSize: 14, height: 20 / 14)),
          const SizedBox(height: 12),
          FormulaireSigh(controleur: motif),
        ]),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: 'Valider et clôturer',
                  icone: LucideIcons.lock,
                  variante: VarianteBouton.danger,
                  onPressed: () {
                    final r = cpcValiderCloture(c.magasin.collection('exercices').toutes, _ecritures(c), annee,
                        motif: '${motif['motif'] ?? ''}', acteur: acteurDe(c), role: c.role, maintenant: c.aujourdhui);
                    if (!r.ok) {
                      ToastsSigh.afficher(ctx, 'Clôture refusée.', type: TypeToast.erreur, detail: r.motif);
                      return;
                    }
                    final ecr = c.magasin.collection('ecritures');
                    // (1) la pièce de résultat, (2) les à-nouveaux définitifs — dans l'ordre des insertions de la maquette ; (3) l'exercice « clos », en DERNIER
                    for (final l in r.lignesOD) {
                      ecr.inserer(l, prefixe: 'ECR');
                    }
                    for (final l in r.lignesAN) {
                      ecr.inserer(l, prefixe: 'ECR');
                    }
                    c.magasin.collection('exercices').mettreAJour(x['id'], r.patch!);
                    if (r.exerciceSuivant != null) c.magasin.collection('exercices').inserer(r.exerciceSuivant!);
                    c.magasin.journaliser('Clôture d’exercice', 'M12', 'Exercice', '$annee', {'etat': 'en_attente_cloture'},
                        {'etat': 'clos', 'resultat': r.resultat, 'empreinte': r.empreinte});
                    notifier(c,
                        type: 'cloture',
                        poste: 'comptable',
                        libelle: 'Exercice $annee clos',
                        detail: 'Résultat ${money(r.resultat)} ; à-nouveaux ${annee + 1} écrits.',
                        reference: '$annee');
                    fermer();
                    ToastsSigh.afficher(ctx, 'Exercice $annee clos.',
                        type: TypeToast.succes, detail: 'Résultat ${money(r.resultat)} — ${r.lignesAN.length} ligne(s) d’à-nouveau écrite(s).');
                  }),
            ]);
  }

  void _procesVerbal(BuildContext ctx, ContexteEcran c, Fiche x) {
    final annee = x['annee'] as int;
    final lignes = cpcSoldesParCompte(cpcEcrituresDe(_ecritures(c), annee));
    afficherApercu(
        ctx,
        pieceM9(c,
            titre: 'Procès-verbal de clôture — exercice $annee',
            sousTitre: 'Détermination du résultat et à-nouveaux de l’exercice ${annee + 1}',
            cartouche: [
              ('Exercice', '${x['debut']} → ${x['fin']}'),
              ('Résultat net', money(n(x['resultat']))),
              ('Demandée par', '${x['demandePar'] ?? '—'}'),
              ('Validée par', '${x['validePar'] ?? '—'}'),
              ('Empreinte SHA-256', '${_tronque('${x['empreinte'] ?? ''}', 32)}…'),
              ('Date d’édition', dateFR(c.aujourdhui)),
            ],
            tableaux: [
              TableauEtat(colonnes: [
                ColonneEtat(libelle: 'Compte', valeur: (l) => l['compte']),
                ColonneEtat(libelle: 'Intitulé', valeur: (l) => l['libelle']),
                ColonneEtat(libelle: 'Débit', droite: true, valeur: (l) => m(l['debit']), somme: (l) => n(l['debit'])),
                ColonneEtat(libelle: 'Crédit', droite: true, valeur: (l) => m(l['credit']), somme: (l) => n(l['credit'])),
              ], lignes: lignes)
            ],
            signatures: [Signature('Le Comptable', nom: '${x['demandePar'] ?? ''}'), Signature('La Direction', nom: '${x['validePar'] ?? ''}')]));
  }

  // ----------------------------------------------------------------------------------------------------------------------------------------------
  // LES TROIS ONGLETS
  // ----------------------------------------------------------------------------------------------------------------------------------------------
  Widget _exercices(BuildContext ctx, ContexteEcran c, bool peutDemander, bool peutValider) {
    final lignes = exercicesActifs(c.magasin);
    return TableauSigh(
      titre: 'Exercices comptables',
      lignes: lignes,
      nomExport: 'exercices',
      taillePage: 10,
      recherche: false,
      triInitial: 'annee',
      sensInitial: 'desc',
      colonnes: [
        ColonneTableau(cle: 'annee', libelle: 'Exercice', sansCoupure: true, texte: (x) => 'Exercice ${x['annee']}'),
        ColonneTableau(
            cle: 'debut', libelle: 'Période', texte: (x) => '${dateDe(x['debut'])} → ${dateDe(x['fin'])}'),
        ColonneTableau(
            cle: 'etat',
            libelle: 'État',
            texte: (x) => '${x['etat']}',
            rendu: (_, x) => switch (x['etat']) {
                  'ouvert' => const BadgeSigh('Ouvert', ton: TonSigh.succes),
                  'en_attente_cloture' => const BadgeSigh('En attente de clôture', ton: TonSigh.attention),
                  'clos' => const BadgeSigh('Clos'),
                  _ => BadgeSigh('${x['etat']}')
                }),
        ColonneTableau(
            cle: 'resultat',
            libelle: 'Résultat net',
            droite: true,
            texte: (x) => x['resultat'] == null ? '' : m(x['resultat']),
            rendu: (_, x) => x['resultat'] == null
                ? const Text('—', style: TextStyle(color: JetonsShell.slate400, fontSize: 14, height: 20 / 14))
                : Text(money(x['resultat']), style: const TextStyle(color: JetonsShell.slate700, fontSize: 14, height: 20 / 14))),
        ColonneTableau(
            cle: 'validePar',
            libelle: 'Validée par',
            texte: (x) => x['validePar'] != null ? '${x['validePar']} — ${dateDe(x['valideLe'])}' : '—'),
        ColonneTableau(
            cle: 'empreinte',
            libelle: 'Empreinte',
            texte: (x) => x['empreinte'] != null ? '${'${x['empreinte']}'.substring(0, 12)}…' : '—',
            rendu: (_, x) => x['empreinte'] != null ? monoTexte('${'${x['empreinte']}'.substring(0, 12)}…') : const Text('—')),
      ],
      actionsLigne: (cx, x) => [
        if (x['source'] != 'liasse') ...[
          if (x['etat'] == 'ouvert')
            BoutonSigh(
                libelle: 'Pré-clôture',
                taille: TailleBouton.sm,
                variante: VarianteBouton.secondaire,
                icone: LucideIcons.listChecks,
                onPressed: () => _preCloture(ctx, c, x, peutDemander)),
          if (x['etat'] == 'en_attente_cloture' && peutValider)
            BoutonSigh(libelle: 'Valider la clôture', taille: TailleBouton.sm, icone: LucideIcons.lock, onPressed: () => _valider(ctx, c, x)),
          if (x['etat'] == 'clos')
            BoutonSigh(
                libelle: 'Procès-verbal',
                taille: TailleBouton.sm,
                variante: VarianteBouton.secondaire,
                icone: LucideIcons.printer,
                onPressed: () => _procesVerbal(ctx, c, x)),
        ]
      ],
    );
  }

  Widget _periodes(BuildContext ctx, ContexteEcran c) {
    final annee = exerciceChoisi(c);
    const mois = ['janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'];
    final e = cpcEcrituresDe(_ecritures(c), annee, brouillons: true);
    final lignes = <Fiche>[
      for (var i = 0; i < 12; i++)
        () {
          final sel = [for (final x in e) if (DateTime.tryParse('${x['date']}')?.month == i + 1) x];
          final d = sel.fold<double>(0, (a, x) => a + n(x['debit'])), cr = sel.fold<double>(0, (a, x) => a + n(x['credit']));
          return <String, Object?>{
            'id': '$i',
            'mois': '${mois[i][0].toUpperCase()}${mois[i].substring(1)} $annee',
            'nb': sel.length,
            'debit': d,
            'credit': cr,
            'equilibre': d == cr,
            'brouillons': sel.where((x) => x['statut'] == 'brouillon').length,
          };
        }()
    ];
    return TableauSigh(
      titre: 'Périodes comptables — exercice $annee',
      lignes: lignes,
      nomExport: 'periodes',
      taillePage: 12,
      recherche: false,
      colonnes: [
        const ColonneTableau(cle: 'mois', libelle: 'Période', sansCoupure: true, triable: false),
        const ColonneTableau(cle: 'nb', libelle: 'Écritures', droite: true, triable: false),
        ColonneTableau(cle: 'debit', libelle: 'Total débit', droite: true, triable: false, texte: (p) => m(p['debit'])),
        ColonneTableau(cle: 'credit', libelle: 'Total crédit', droite: true, triable: false, texte: (p) => m(p['credit'])),
        ColonneTableau(
            cle: 'equilibre',
            libelle: 'Équilibre',
            triable: false,
            texte: (p) => p['equilibre'] == true ? 'Équilibrée' : 'Déséquilibrée',
            rendu: (_, p) => n(p['nb']) == 0
                ? const Text('—')
                : (p['equilibre'] == true
                    ? const BadgeSigh('Équilibrée', ton: TonSigh.succes)
                    : BadgeSigh('Écart ${money((n(p['debit']) - n(p['credit'])).abs(), avecDevise: false)}', ton: TonSigh.danger))),
        ColonneTableau(
            cle: 'brouillons',
            libelle: 'Brouillons',
            droite: true,
            triable: false,
            texte: (p) => '${p['brouillons']}',
            rendu: (_, p) => n(p['brouillons']) > 0
                ? Text('${p['brouillons']}', style: const TextStyle(color: JetonsShell.warning600, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600))
                : const Text('—')),
      ],
    );
  }

  Widget _lettrage(BuildContext ctx, ContexteEcran c) {
    final annee = exerciceChoisi(c);
    final toutes = _ecritures(c);
    final tiers = <String>{for (final e in toutes) if (cpcLettrable(e['compte'])) '${e['compte']}'}.toList()..sort();
    final note = const NoteSigh(
        'Un lettrage rapproche des lignes d’un même compte de tiers dont le total s’annule (une facture et son règlement). À la clôture, seules les lignes non lettrées sont reprises une à une aux à-nouveaux.',
        icone: LucideIcons.link);
    if (tiers.isEmpty) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        note,
        const SizedBox(height: 12),
        const Text('Aucun compte de tiers mouvementé.', style: TextStyle(color: JetonsShell.slate500, fontSize: 14, height: 20 / 14)),
      ]);
    }
    if (!_compteInit) {
      _compteInit = true;
      _compte = champUnique(
          ChampDef(
              nom: 'compte',
              libelle: 'Compte',
              type: TypeChamp.select,
              col: ColChamp.plein,
              options: [for (final t in tiers) OptionChamp(t, '$t — ${cpaCompteLibelle(t)}')]),
          tiers.first);
      _compte.addListener(() {
        _coches.clear();
        if (mounted) setState(() {});
      });
    }
    final compte = '${_compte['compte']}';
    final lignes = [
      for (final e in toutes)
        if ('${e['compte']}' == compte && cpaAnnee(e['date']) == annee && e['statut'] == 'validee') e
    ];
    final droit = c.droit.editer;
    final exos = c.magasin.collection('exercices').toutes;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      note,
      const SizedBox(height: 12),
      Row(children: [
        const Text('Compte  ', style: TextStyle(color: JetonsShell.slate700, fontSize: 14)),
        commande(_compte, largeur: 420),
      ]),
      const SizedBox(height: 12),
      TableauSigh(
        key: ValueKey('lettrage-$compte'),
        titre: 'Lignes du compte $compte',
        lignes: lignes,
        nomExport: 'lettrage',
        taillePage: 10,
        colonnes: [
          ColonneTableau(
              cle: 'select',
              libelle: '',
              triable: false,
              texte: (_) => '',
              rendu: (_, e) {
                final lettre = '${e['lettrage'] ?? ''}'.isNotEmpty;
                final clos = cpcEtatExercice(exos, cpaAnnee(e['date']) ?? annee) == 'clos';
                if (lettre || !droit || clos) return const SizedBox.shrink();
                return Checkbox(
                    key: Key('lettrage:${e['id']}'),
                    value: _coches.contains(e['id']),
                    onChanged: (v) => setState(() => v == true ? _coches.add(e['id']) : _coches.remove(e['id'])));
              }),
          ColonneTableau(cle: 'numero', libelle: 'Pièce', sansCoupure: true, texte: (e) => '${e['numero'] ?? ''}', rendu: (_, e) => monoTexte(e['numero'], couleur: JetonsShell.navy800, poids: FontWeight.w600)),
          colDateEcriture(),
          const ColonneTableau(cle: 'libelle', libelle: 'Libellé'),
          colDebitEcriture(),
          colCreditEcriture(),
          ColonneTableau(
              cle: 'lettrage',
              libelle: 'Lettrage',
              texte: (e) => '${e['lettrage'] ?? 'non lettrée'}',
              rendu: (_, e) => '${e['lettrage'] ?? ''}'.isNotEmpty
                  ? BadgeSigh('${e['lettrage']}', ton: TonSigh.succes)
                  : const Text('non lettrée', style: TextStyle(color: JetonsShell.slate400, fontSize: 14, height: 20 / 14))),
        ],
      ),
      if (droit) ...[
        const SizedBox(height: 12),
        Wrap(spacing: 8, children: [
          BoutonSigh(libelle: 'Lettrer la sélection', icone: LucideIcons.link, onPressed: () => _lettrer(ctx, c, compte)),
          BoutonSigh(
              libelle: 'Dé-lettrer un code…',
              icone: LucideIcons.unlink,
              variante: VarianteBouton.secondaire,
              onPressed: () => _delettrer(ctx, c, compte)),
        ]),
      ],
    ]);
  }

  void _lettrer(BuildContext ctx, ContexteEcran c, String compte) {
    final r = cpcLettrer(c.magasin.collection('ecritures').toutes, compte, _coches.toList());
    if (!r.ok) {
      ToastsSigh.afficher(ctx, 'Lettrage refusé.', type: TypeToast.erreur, detail: r.motif);
      return;
    }
    final ecr = c.magasin.collection('ecritures');
    final defaire = <VoidCallback>[];
    final refus = refuseSiClos(ctx, () {
      for (final id in r.ids) {
        defaire.add(ecr.mettreAJour(id, {'lettrage': r.code, 'lettreLe': c.aujourdhui.toUtc().toIso8601String(), 'lettrePar': acteurDe(c)}));
      }
    });
    if (refus) return;
    _coches.clear();
    ToastsSigh.afficher(ctx, 'Lettrage « ${r.code} » posé sur ${r.ids.length} ligne(s).', type: TypeToast.succes);
  }

  void _delettrer(BuildContext ctx, ContexteEcran c, String compte) {
    final f = ControleurFormulaire(const [
      ChampDef(nom: 'code', libelle: 'Code de lettrage à défaire', requis: true, col: ColChamp.plein),
      ChampDef(nom: 'motif', libelle: 'Motif (obligatoire)', type: TypeChamp.textarea, requis: true, col: ColChamp.plein, lignes: 2),
    ]);
    afficherModale<void>(ctx,
        titre: 'Dé-lettrer un code',
        sousTitre: 'Compte $compte',
        taille: TailleModale.sm,
        corps: FormulaireSigh(controleur: f),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: 'Dé-lettrer',
                  icone: LucideIcons.unlink,
                  onPressed: () {
                    final v = f.valider();
                    if (v == null) return;
                    final r = cpcDelettrer(c.magasin.collection('ecritures').toutes, compte, '${v['code']}'.toUpperCase(), '${v['motif']}');
                    if (!r.ok) {
                      ToastsSigh.afficher(ctx, 'Dé-lettrage refusé.', type: TypeToast.erreur, detail: r.motif);
                      return;
                    }
                    final ecr = c.magasin.collection('ecritures');
                    final refus = refuseSiClos(ctx, () {
                      for (final id in r.ids) {
                        ecr.mettreAJour(id, {'lettrage': null, 'delettreLe': c.aujourdhui.toUtc().toIso8601String(), 'delettreMotif': '${v['motif']}'.trim()});
                      }
                    });
                    if (refus) return;
                    fermer();
                    ToastsSigh.afficher(ctx, '${r.ids.length} ligne(s) dé-lettrée(s).', type: TypeToast.succes);
                  }),
            ]);
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([for (final k in ['exercices', 'ecritures', 'comptes', 'notifications']) c.magasin.collection(k)]),
      builder: (context, _) {
        final annee = exerciceChoisi(c);
        final exos = c.magasin.collection('exercices').toutes;
        final cur = cpcExercice(exos, annee);
        final pre = cpcPreCloture(_ecritures(c), annee);
        final etat = '${cur?['etat'] ?? 'ouvert'}';
        final clos = etat == 'clos';
        final peutDemander = c.droit.editer && cpcRolesDemande.contains(c.role);
        final peutValider = cpcRolesValidation.contains(c.role);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          KpiGrilleSigh(kpis: [
            KpiSigh(libelle: 'Exercice affiché', valeur: '$annee', icone: LucideIcons.calendar),
            KpiSigh(
                libelle: 'État',
                valeur: switch (etat) { 'ouvert' => 'Ouvert', 'en_attente_cloture' => 'En attente', _ => 'Clos' },
                icone: LucideIcons.lock,
                ton: clos ? TonSigh.succes : TonSigh.info),
            KpiSigh(
                libelle: clos ? 'Résultat net' : 'Résultat provisoire',
                valeur: money(clos ? n(cur?['resultat']) : pre.resultat),
                icone: LucideIcons.scale,
                ton: TonSigh.neutre),
            KpiSigh(
                libelle: 'Contrôles bloquants en échec',
                valeur: nombre(pre.bloquants.length),
                icone: LucideIcons.shieldAlert,
                ton: pre.bloquants.isNotEmpty ? TonSigh.attention : TonSigh.succes),
          ]),
          const SizedBox(height: 16),
          OngletsSigh(onglets: [
            OngletDef(id: 'exercices', libelle: 'Exercices', construire: (ctx) => _exercices(context, c, peutDemander, peutValider)),
            OngletDef(id: 'periodes', libelle: 'Périodes de l’exercice', construire: (ctx) => _periodes(context, c)),
            OngletDef(id: 'lettrage', libelle: 'Lettrage des tiers', construire: (ctx) => _lettrage(context, c)),
          ]),
        ]);
      },
    );
  }
}
