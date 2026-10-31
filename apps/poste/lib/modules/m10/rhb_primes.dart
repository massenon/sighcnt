import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'rhb_commun.dart';

/// `m10-primes` — « Primes diverses (NS 132) » : la grille des primes par fonction et les primes ACQUISES du mois, calculées depuis le planning validé (RG-11).
/// La grille est DATÉE : une prime relevée le 20 août ne change pas la prime de juillet, déjà calculée et souvent payée. Chaque modification demande sa portée.
class EcranPrimes extends StatelessWidget with EcranMaquette {
  const EcranPrimes({super.key});

  @override
  String? get titre => 'Primes diverses (NS 132)';

  @override
  String get description => 'Grille des primes par fonction et calcul des primes acquises à partir du planning validé.';

  @override
  String get regle =>
      'Grille de la note $rhbNs132Reference, en vigueur depuis le ${dateFR(DateTime.parse(rhbNs132DateEffet))}. RG-11 — les primes de garde et de permanence sont calculées automatiquement à partir du planning validé.';

  @override
  Widget build(BuildContext context) =>
      RhbEcoute(collections: const ['grillePrimes', 'historiquePrimes', 'beneficiairesPrimes', 'planning', 'personnel'], construire: _corps);

  Widget _corps(BuildContext context, ContexteEcran c) => rhbEspace([
        _Grille(contexte: context),
        _Acquises(contexte: context),
      ]);
}

/// `C.slug` : sans accents, minuscules, tout ce qui n'est pas alphanumérique devient un tiret.
String rhbSlug(String s) {
  const de = 'àâäáãåçéèêëíìîïñóòôöõúùûüýÿÀÂÄÁÃÅÇÉÈÊËÍÌÎÏÑÓÒÔÖÕÚÙÛÜÝ';
  const vers = 'aaaaaaceeeeiiiinooooouuuuyyAAAAAACEEEEIIIINOOOOOUUUUY';
  final b = StringBuffer();
  for (final r in s.runes) {
    final ch = String.fromCharCode(r);
    final i = de.indexOf(ch);
    b.write(i >= 0 ? vers[i] : ch);
  }
  return b.toString().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');
}

class _Grille extends StatelessWidget {
  const _Grille({required this.contexte});
  final BuildContext contexte;

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final grille = rhbActives(c, 'grillePrimes');
    final anciennes = rhbActives(c, 'historiquePrimes');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      CarteSigh(
        titre: 'Grille des primes — $rhbNs132Reference',
        sansRemplissage: true,
        actions: [
          const BadgeSigh('Version $rhbNs132Version — $rhbNs132Statut', ton: TonSigh.succes),
          const SizedBox(width: 8),
          if (c.droit.editer)
            BoutonSigh(libelle: 'Nouvelle prime', icone: LucideIcons.plus, taille: TailleBouton.sm, onPressed: () => _editer(context, c, null)),
          const SizedBox(width: 8),
          BoutonSigh(libelle: 'Imprimer la note', icone: LucideIcons.printer, taille: TailleBouton.sm, variante: VarianteBouton.secondaire, onPressed: () => _imprimerNote(context, c)),
        ],
        child: MiniTableauSigh(colonnes: [
          ColonneMini('Prime', (p) => '', rendu: (p) => Text('${p['label']}', style: rhbCorps)),
          ColonneMini('Mode', (p) => '', rendu: (p) => BadgeSigh(p['mode'] == 'fixe' ? 'Forfait mensuel' : 'Par occurrence', ton: p['mode'] == 'fixe' ? TonSigh.navy : TonSigh.info)),
          for (final f in rhbColonnesPrimes)
            ColonneMini(rhbFonctionLabel(f).toUpperCase(), (p) => '', droite: true, rendu: (p) {
              final v = (p['montants'] as Map?)?[f];
              return v is num && v != 0
                  ? Text(money(v, avecDevise: false), style: const TextStyle(color: JetonsShell.slate800, fontSize: 14, fontWeight: FontWeight.w600))
                  : const Text('—', style: TextStyle(color: JetonsShell.slate300, fontSize: 14));
            }),
          ColonneMini('En vigueur', (p) => '', droite: true, rendu: (p) => Text(p['dateEffet'] != null ? dateFR(DateTime.parse('${p['dateEffet']}')) : '—', style: const TextStyle(color: JetonsShell.slate500, fontSize: 12))),
          ColonneMini('', (p) => '', droite: true, rendu: (p) => Row(mainAxisSize: MainAxisSize.min, children: [
                if (p['mode'] == 'fixe') BoutonIcone(icone: LucideIcons.users, libelle: 'Bénéficiaires du forfait', onPressed: () => _beneficiaires(context, c, p)),
                if (c.droit.editer) BoutonIcone(icone: LucideIcons.pencil, libelle: 'Modifier cette prime', onPressed: () => _editer(context, c, p)),
                if (c.droit.annuler) BoutonIcone(icone: LucideIcons.archive, libelle: 'Retirer cette prime', onPressed: () => _retirer(context, c, p)),
              ])),
        ], lignes: grille),
      ),
      if (anciennes.isNotEmpty) ...[
        const SizedBox(height: 16),
        CarteSigh(
            titre: 'Versions antérieures',
            sansRemplissage: true,
            child: MiniTableauSigh(colonnes: [
              ColonneMini('Prime', (v) => '${v['label']}'),
              ColonneMini('En vigueur du', (v) => v['dateEffet'] != null ? dateFR(DateTime.parse('${v['dateEffet']}')) : '—'),
              ColonneMini('au', (v) => v['dateFin'] != null ? dateFR(DateTime.parse('${v['dateFin']}')) : 'en cours'),
              ColonneMini('Montants', (v) {
                final m = (v['montants'] as Map?) ?? const {};
                final s = [for (final e in m.entries) '${rhbFonctionLabel(e.key)} ${money(e.value, avecDevise: false)}'].join(' · ');
                return s.isEmpty ? '—' : s;
              }),
              ColonneMini('Remplacée par', (v) => '${v['remplaceePar'] ?? '—'}'),
            ], lignes: trierPar(anciennes, (v) => v['dateFin'], descendant: true))),
        const SizedBox(height: 16),
        const NoteSigh(
            'Ces versions ne sont pas de l’archive décorative : c’est en elles que le bulletin de paie retrouve le montant applicable à un mois passé. Les retirer rendrait un bulletin ancien irreproductible.',
            icone: LucideIcons.history),
      ],
    ]);
  }

  void _editer(BuildContext ctx, ContexteEcran c, Fiche? prime) {
    final creation = prime == null;
    final ctl = ControleurFormulaire([
      const ChampDef(nom: 'label', libelle: 'Intitulé de la prime', requis: true, col: ColChamp.plein),
      const ChampDef(
          nom: 'mode',
          libelle: 'Mode de calcul',
          type: TypeChamp.select,
          requis: true,
          options: [OptionChamp('fixe', 'Forfait mensuel'), OptionChamp('occurrence', 'Par occurrence')],
          aide: 'Le forfait s’applique chaque mois ; l’occurrence se multiplie par le nombre relevé au planning.'),
      for (final f in rhbColonnesPrimes)
        ChampDef(
            nom: 'm_$f',
            libelle: rhbFonctionLabel(f),
            type: TypeChamp.nombre,
            aide: 'FCFA — vide si non éligible',
            valider: (v, _) => (num.tryParse('$v'.replaceAll(',', '.')) ?? 0) < 0 ? 'Un montant ne peut pas être négatif.' : null),
    ], creation
        ? {'mode': 'fixe'}
        : {
            'label': prime['label'],
            'mode': prime['mode'],
            for (final f in rhbColonnesPrimes) 'm_$f': '${((prime['montants'] as Map?)?[f]) ?? ''}',
          });
    afficherModale<void>(ctx,
        titre: creation ? 'Nouvelle prime' : 'Modifier « ${prime['label']} »',
        sousTitre: rhbNs132Reference,
        taille: TailleModale.lg,
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          NoteSigh(
              'RG-11 — les primes de garde et de permanence sont calculées à partir du planning validé ; ce que l’on règle ici, c’est le montant unitaire par fonction. ${creation ? 'Une prime créée hors note de service devra être couverte par un avenant.' : 'La portée de la modification vous sera demandée à l’enregistrement.'}',
              ton: TonSigh.attention,
              icone: LucideIcons.shieldAlert),
          const SizedBox(height: 12),
          FormulaireSigh(controleur: ctl),
        ]),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: creation ? 'Créer la prime' : 'Enregistrer',
                  icone: creation ? LucideIcons.plus : LucideIcons.save,
                  onPressed: () {
                    final v = ctl.valider();
                    if (v == null) return;
                    final montants = <String, int>{};
                    for (final f in rhbColonnesPrimes) {
                      final n = num.tryParse('${v['m_$f'] ?? ''}'.replaceAll(',', '.')) ?? 0;
                      if (n > 0) montants[f] = n.toInt();
                    }
                    fermer();
                    if (creation) {
                      c.magasin.collection('grillePrimes').inserer({
                        'statut': 'actif',
                        'primeId': rhbSlug('${v['label']}'),
                        'label': v['label'],
                        'mode': v['mode'],
                        'montants': montants,
                        'dateEffet': iso(c.aujourdhui),
                        'version': rhbNs132Version + 1,
                        'source': 'Créée dans l’application le ${dateFR(c.aujourdhui)}',
                      }, prefixe: 'GPR');
                      ToastsSigh.afficher(ctx, 'Prime créée.', type: TypeToast.succes, detail: '${v['label']}');
                      return;
                    }
                    _portee(ctx, c, prime, {'label': v['label'], 'mode': v['mode'], 'montants': montants});
                  }),
            ]);
  }

  /// LA QUESTION QUI ENGAGE — la portée d'une modification de prime. Une prime de garde relevée de 2 000 à 2 500 FCFA change le bulletin du mois ; vaut-elle aussi
  /// pour les gardes de juillet, déjà payées ? La réponse appartient à la Direction, et elle est posée à CHAQUE modification.
  void _portee(BuildContext ctx, ContexteEcran c, Fiche prime, Map<String, Object?> valeurs) {
    final avantM = (prime['montants'] as Map?) ?? const {};
    final apresM = (valeurs['montants'] as Map).cast<String, Object?>();
    final ecarts = [
      for (final f in rhbColonnesPrimes)
        if (((apresM[f] as num?) ?? 0) - ((avantM[f] as num?) ?? 0) != 0)
          {'label': rhbFonctionLabel(f), 'avant': (avantM[f] as num?) ?? 0, 'apres': (apresM[f] as num?) ?? 0, 'delta': ((apresM[f] as num?) ?? 0) - ((avantM[f] as num?) ?? 0)}
    ];
    final dEffet = '${prime['dateEffet'] ?? rhbNs132DateEffet}';
    rhbDemanderPortee(ctx,
        sousTitre: '${prime['label']}',
        alerteTitre: 'Cette modification touche des salaires.',
        alerteTexte: ecarts.isNotEmpty
            ? '${nombre(ecarts.length)} montant(s) modifié(s). Les primes des mois déjà calculés — et pour certaines déjà payées — dépendent de cette grille.'
            : 'Aucun montant n’est modifié ; seul l’intitulé ou le mode change.',
        tonAlerte: TonSigh.danger,
        tableau: ecarts.isEmpty
            ? null
            : CarteSigh(
                sansRemplissage: true,
                child: MiniTableauSigh(colonnes: [
                  ColonneMini('Fonction', (x) => '${x['label']}'),
                  ColonneMini('Avant', (x) => (x['avant'] as num) > 0 ? money(x['avant'], avecDevise: false) : '—', droite: true),
                  ColonneMini('Après', (x) => (x['apres'] as num) > 0 ? money(x['apres'], avecDevise: false) : '—', droite: true),
                  ColonneMini('Écart', (x) => '', droite: true, rendu: (x) {
                    final d = x['delta'] as num;
                    return Text('${d > 0 ? '+' : ''}${money(d, avecDevise: false)}', style: TextStyle(color: d > 0 ? JetonsShell.danger700 : JetonsShell.success700, fontSize: 14, fontWeight: FontWeight.w600));
                  }),
                ], lignes: ecarts)),
        futur: (
          'Primes en cours et à venir seulement',
          'La version actuelle est archivée avec sa période de validité, et la nouvelle prend effet le ${dateFR(c.aujourdhui)}. Les bulletins déjà édités restent reproductibles à l’identique.'
        ),
        tout: (
          'Y compris les primes déjà calculées',
          'La grille est réécrite depuis sa date d’effet d’origine (${dateFR(DateTime.parse(dEffet))}). Les bulletins passés recalculeront des montants différents de ceux qui ont été remis aux agents. À réserver à la correction d’une erreur de saisie.'
        ),
        appliquer: (portee) {
          if (portee == 'futur') {
            // On fige la version sortante avant de la remplacer : c'est elle que le bulletin d'un mois passé ira relire.
            c.magasin.collection('historiquePrimes').inserer({
              'statut': 'actif',
              'primeId': prime['primeId'],
              'label': prime['label'],
              'mode': prime['mode'],
              'montants': {...avantM.cast<String, Object?>()},
              'dateEffet': dEffet,
              'dateFin': iso(ajouterJours(c.aujourdhui, -1)),
              'remplaceePar': 'Version du ${dateFR(c.aujourdhui)}',
              'archiveePar': c.utilisateur,
            }, prefixe: 'HPR');
          }
          final annuler = c.magasin.collection('grillePrimes').mettreAJour(prime['id'], {
            ...valeurs,
            'dateEffet': portee == 'futur' ? iso(c.aujourdhui) : dEffet,
            'version': ((prime['version'] as num?) ?? 1).toInt() + 1,
            'portee': portee,
            'modifieeLe': iso(c.aujourdhui),
            'modifieePar': c.utilisateur,
          });
          c.magasin.journaliser('Modification de la grille des primes', 'M10', 'Prime', '${prime['primeId']}', {'montants': avantM}, {'montants': apresM, 'portee': portee});
          ToastsSigh.afficher(ctx, 'Grille des primes modifiée.',
              type: portee == 'tout' ? TypeToast.attention : TypeToast.succes,
              detail: portee == 'tout'
                  ? 'Application RÉTROACTIVE — les bulletins passés changeront de montant.'
                  : 'Applicable à compter du ${dateFR(c.aujourdhui)} ; l’historique est préservé.',
              annuler: annuler);
        });
  }

  /// Une prime retirée reçoit une DATE DE FIN (E651 levé) : la paie la lit jusqu'à ce jour inclus, et plus jamais après.
  void _retirer(BuildContext ctx, ContexteEcran c, Fiche prime) {
    final ctl = ControleurFormulaire(const [
      ChampDef(
          nom: 'dateFin',
          libelle: 'Dernier jour de la prime',
          type: TypeChamp.date,
          requis: true,
          aide: 'La paie lit la prime jusqu’à cette date incluse, et plus après.'),
      ChampDef(nom: 'motif', libelle: 'Motif du retrait', type: TypeChamp.textarea, lignes: 2, requis: true, col: ColChamp.plein),
    ], {'dateFin': iso(ajouterJours(c.aujourdhui, -1))});
    afficherModale<void>(ctx,
        titre: 'Retirer la prime « ${prime['label']} » ?',
        sousTitre: rhbNs132Reference,
        taille: TailleModale.lg,
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          const NoteSigh(
              'Attention. Cette prime cesse d’être calculée après sa date de fin. Les bulletins déjà édités ne changent pas : les versions antérieures de la grille restent consultables. Conformément à RG-14, la prime est archivée et non supprimée : elle reste restaurable depuis la corbeille. Une prime instituée par note de service ne peut être retirée que par une note qui l’abroge.',
              ton: TonSigh.attention,
              icone: LucideIcons.shieldAlert),
          const SizedBox(height: 12),
          FormulaireSigh(controleur: ctl),
        ]),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: 'Retirer la prime',
                  icone: LucideIcons.archive,
                  variante: VarianteBouton.danger,
                  onPressed: () {
                    final v = ctl.valider();
                    if (v == null) return;
                    final dateFin = '${v['dateFin']}';
                    final effet = prime['dateEffet'];
                    if (effet != null && effet != '' && dateFin.compareTo('$effet') < 0) {
                      ToastsSigh.afficher(ctx, 'La date de fin précède l’entrée en vigueur de la prime.',
                          type: TypeToast.erreur, detail: 'En vigueur depuis le ${dateFR(DateTime.parse('$effet'))}.');
                      return;
                    }
                    fermer();
                    c.magasin.collection('historiquePrimes').inserer({
                      'statut': 'actif',
                      'primeId': prime['primeId'],
                      'label': prime['label'],
                      'mode': prime['mode'],
                      'montants': {...((prime['montants'] as Map?) ?? const {}).cast<String, Object?>()},
                      'dateEffet': prime['dateEffet'] ?? rhbNs132DateEffet,
                      'dateFin': dateFin,
                      'retiree': true,
                      'remplaceePar': 'Prime retirée : ${v['motif']}',
                      'archiveePar': c.utilisateur,
                    }, prefixe: 'HPR');
                    final annuler = c.magasin.collection('grillePrimes').archiver(prime['id']);
                    ToastsSigh.afficher(ctx, 'Prime retirée de la grille.',
                        type: TypeToast.succes,
                        detail: 'Dernier jour : ${dateFR(DateTime.parse(dateFin))}. Archivage logique (RG-14), restaurable depuis la corbeille.',
                        annuler: annuler);
                  }),
            ]);
  }

  /// LES BÉNÉFICIAIRES D'UN FORFAIT (E654 levé) : une liste DATÉE d'agents. Un forfait se désigne ; tant qu'aucun agent n'est désigné, la règle
  /// d'attente (tous les agents de la fonction) s'applique et l'écran le dit. Une désignation ne se supprime pas : on y met fin à une date.
  void _beneficiaires(BuildContext ctx, ContexteEcran c, Fiche prime) {
    final col = c.magasin.collection('beneficiairesPrimes');
    final eligibles = [
      for (final a in rhbActives(c, 'personnel'))
        if (((prime['montants'] as Map?)?[a['fonction']] as num? ?? 0) > 0) a
    ];
    final ctl = ControleurFormulaire([
      ChampDef(
          nom: 'agents',
          libelle: 'Agents à désigner',
          type: TypeChamp.multiselect,
          requis: true,
          col: ColChamp.plein,
          options: [for (final a in eligibles) OptionChamp('${a['id']}', '${a['nomComplet']} (${rhbFonctionLabel(a['fonction'])})')]),
      const ChampDef(nom: 'debut', libelle: 'Depuis le', type: TypeChamp.date, requis: true),
    ], {'debut': iso(c.aujourdhui)});
    afficherModale<void>(ctx,
        titre: 'Bénéficiaires : ${prime['label']}',
        sousTitre: rhbNs132Reference,
        taille: TailleModale.lg,
        corps: ListenableBuilder(
            listenable: col,
            builder: (_, __) {
              final liste = [for (final x in col.actives) if (x['primeId'] == prime['primeId']) x];
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                NoteSigh(
                    liste.isNotEmpty
                        ? 'Seuls les agents désignés, aux dates indiquées, perçoivent ce forfait.'
                        : 'Aucun bénéficiaire désigné. Règle d’attente : le forfait est versé à tous les agents dont la fonction figure à la grille. Désigner un premier agent la remplace par la liste.',
                    ton: liste.isNotEmpty ? TonSigh.info : TonSigh.attention,
                    icone: LucideIcons.users),
                if (liste.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  MiniTableauSigh(colonnes: [
                    ColonneMini('Agent', (x) => '${x['agent']}'),
                    ColonneMini('Depuis le', (x) => dateFR(DateTime.parse('${x['debut']}'))),
                    ColonneMini('Jusqu’au', (x) => x['fin'] != null && x['fin'] != '' ? dateFR(DateTime.parse('${x['fin']}')) : 'en cours'),
                    ColonneMini('', (x) => '', rendu: (x) {
                      if (!c.droit.editer || (x['fin'] != null && x['fin'] != '')) return const SizedBox.shrink();
                      return BoutonIcone(
                          icone: LucideIcons.calendarX,
                          libelle: 'Mettre fin à la désignation',
                          onPressed: () {
                            final annuler = col.mettreAJour(x['id'], {'fin': iso(c.aujourdhui)});
                            ToastsSigh.afficher(ctx, 'Désignation terminée.',
                                type: TypeToast.succes, detail: '${x['agent']} : jusqu’au ${dateFR(c.aujourdhui)}.', annuler: annuler);
                          });
                    }),
                  ], lignes: trierPar(liste, (x) => '${x['agent']}')),
                ],
                if (c.droit.editer) ...[
                  const SizedBox(height: 12),
                  CarteSigh(
                      titre: 'Désigner des bénéficiaires',
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        FormulaireSigh(controleur: ctl),
                        const SizedBox(height: 12),
                        Align(
                            alignment: Alignment.centerLeft,
                            child: BoutonSigh(
                                libelle: 'Désigner',
                                icone: LucideIcons.userPlus,
                                onPressed: () {
                                  final v = ctl.valider();
                                  if (v == null) return;
                                  final deja = {for (final x in liste) if (x['fin'] == null || x['fin'] == '') '${x['agentId']}'};
                                  final ajoutes = <String>[];
                                  for (final id in ((v['agents'] as List?) ?? const []).map((e) => '$e')) {
                                    if (deja.contains(id)) continue;
                                    final a = eligibles.where((x) => '${x['id']}' == id).firstOrNull;
                                    if (a == null) continue;
                                    col.inserer({
                                      'statut': 'actif',
                                      'primeId': prime['primeId'],
                                      'primeLabel': prime['label'],
                                      'agentId': a['id'],
                                      'agent': a['nomComplet'],
                                      'matricule': a['matricule'],
                                      'debut': v['debut'],
                                      'fin': null,
                                      'designePar': c.utilisateur,
                                    }, prefixe: 'BPR');
                                    ajoutes.add('${a['nomComplet']}');
                                  }
                                  if (ajoutes.isEmpty) {
                                    ToastsSigh.afficher(ctx, 'Ces agents sont déjà désignés.', type: TypeToast.attention);
                                    return;
                                  }
                                  c.magasin.journaliser('Désignation des bénéficiaires d’une prime fixe', 'M10', 'Prime', '${prime['primeId']}', null,
                                      {'agents': ajoutes, 'debut': v['debut']});
                                  ToastsSigh.afficher(ctx, '${ajoutes.length} bénéficiaire(s) désigné(s).', type: TypeToast.succes, detail: '${prime['label']}');
                                })),
                      ])),
                ],
              ]);
            }),
        pied: (fermer) => [BoutonSigh(libelle: 'Fermer', variante: VarianteBouton.secondaire, onPressed: fermer)]);
  }

  void _imprimerNote(BuildContext ctx, ContexteEcran c) {
    afficherApercu(
        ctx,
        rhbPiece(c,
            titre: 'Note de service — primes diverses',
            sousTitre: rhbNs132Reference,
            cartouche: [
              ('Référence', rhbNs132Reference),
              ('Objet', rhbNs132Objet),
              ('Date de signature', dateFR(DateTime.parse(rhbNs132DateSignature))),
              ('Date d’effet', dateFR(DateTime.parse(rhbNs132DateEffet))),
              ('Version', 'v$rhbNs132Version'),
              ('Statut', rhbNs132Statut),
            ],
            blocs: [
              const BlocTexte(
                  'Le Directeur Médical de la Clinique NASSIERA TOO informe le personnel que les diverses primes attribuées se présentent comme ci-après. Cette note de service, qui abroge toute disposition antérieure contraire, sera appliquée à compter de sa date de signature.'),
              BlocTableau(TableauEtat(colonnes: [
                ColonneEtat(libelle: 'PRIMES DIVERSES', valeur: (p) => p['label']),
                for (final f in rhbColonnesPrimes)
                  ColonneEtat(libelle: rhbFonctionLabel(f).toUpperCase(), droite: true, valeur: (p) => ((p['montants'] as Map)[f] ?? 0) != 0 ? nombre((p['montants'] as Map)[f]) : ''),
              ], lignes: [
                for (final p in rhbPrimesOrigine) {'label': p.label, 'montants': p.montants}
              ])),
              const BlocTexte('* Pour les primes qui varient en fonction du nombre — ✱ pour les primes fixes.'),
              const BlocTexte('Reçu par : $rhbNs132RecuPar'),
            ],
            signatures: const [Signature('Le Directeur Médical', nom: rhbNs132Signataire)]));
  }
}

class _Acquises extends StatelessWidget {
  const _Acquises({required this.contexte});
  final BuildContext contexte;

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final lignes = rhbPrimesAcquises(
        personnelActif: rhbActives(c, 'personnel'),
        planningActif: rhbActives(c, 'planning'),
        grille: rhbActives(c, 'grillePrimes'),
        historique: rhbActives(c, 'historiquePrimes'),
        designations: rhbActives(c, 'beneficiairesPrimes'),
        date: iso(c.aujourdhui),
        annee: c.aujourdhui.year,
        mois: c.aujourdhui.month);
    num s(num Function(RhbPrimeAcquise) f) => lignes.fold<num>(0, (a, x) => a + f(x));
    final rows = <Fiche>[
      for (final x in lignes)
        {
          'id': x.id, 'matricule': x.matricule, 'employe': x.employe, 'fonction': x.fonction, 'service': x.service, 'gardes': x.gardes,
          'primeGarde': x.primeGarde, 'permanences': x.permanences, 'primePermanence': x.primePermanence, 'primesFixes': x.primesFixes, 'total': x.total
        }
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      KpiGrilleSigh(kpis: [
        KpiSigh(libelle: 'Agents primés', valeur: nombre(lignes.length), icone: LucideIcons.gift, ton: TonSigh.navy),
        KpiSigh(libelle: 'Primes de garde', valeur: money(s((x) => x.primeGarde)), icone: LucideIcons.moon, ton: TonSigh.danger),
        KpiSigh(libelle: 'Primes de permanence', valeur: money(s((x) => x.primePermanence)), icone: LucideIcons.sun, ton: TonSigh.attention),
        KpiSigh(libelle: 'Total des primes du mois', valeur: money(s((x) => x.total)), icone: LucideIcons.wallet, ton: TonSigh.succes),
      ]),
      const SizedBox(height: 16),
      TableauSigh(
        titre: 'Primes acquises — ${moisAnnee(c.aujourdhui)}',
        lignes: rows,
        taillePage: 20,
        triInitial: 'total',
        sensInitial: 'desc',
        nomExport: 'primes',
        selectionnable: true,
        filtres: [
          FiltreTableau(nom: 'fonction', libelle: 'Fonction', options: [for (final f in rhbFonctions) OptionChamp(f.id, f.label)]),
          FiltreTableau(nom: 'service', libelle: 'Service', options: [for (final x in rhbServices) OptionChamp(x)]),
        ],
        actions: [
          BoutonSigh(libelle: 'Éditer l’état des primes', icone: LucideIcons.printer, taille: TailleBouton.sm, variante: VarianteBouton.secondaire, onPressed: () => _etat(context, c, lignes)),
        ],
        colonnes: [
          const ColonneTableau(cle: 'matricule', libelle: 'Mat.', droite: true, sansCoupure: true),
          const ColonneTableau(cle: 'employe', libelle: 'Agent'),
          ColonneTableau(cle: 'fonction', libelle: 'Fonction', texte: (l) => rhbFonctionLabel(l['fonction']), rendu: (_, l) => BadgeSigh(rhbFonctionLabel(l['fonction']), ton: TonSigh.navy)),
          const ColonneTableau(cle: 'gardes', libelle: 'Gardes', droite: true),
          ColonneTableau(cle: 'primeGarde', libelle: 'Prime de garde', droite: true, texte: (l) => money(l['primeGarde'], avecDevise: false), rendu: (_, l) => Text(money(l['primeGarde'], avecDevise: false))),
          const ColonneTableau(cle: 'permanences', libelle: 'Perm.', droite: true),
          ColonneTableau(cle: 'primePermanence', libelle: 'Prime de permanence', droite: true, texte: (l) => money(l['primePermanence'], avecDevise: false), rendu: (_, l) => Text(money(l['primePermanence'], avecDevise: false))),
          ColonneTableau(cle: 'primesFixes', libelle: 'Primes fixes', droite: true, texte: (l) => money(l['primesFixes'], avecDevise: false), rendu: (_, l) => Text(money(l['primesFixes'], avecDevise: false))),
          ColonneTableau(
              cle: 'total',
              libelle: 'Total',
              droite: true,
              texte: (l) => money(l['total'], avecDevise: false),
              rendu: (_, l) => Text(money(l['total'], avecDevise: false), style: const TextStyle(color: JetonsShell.navy900, fontSize: 14, fontWeight: FontWeight.w700))),
        ],
      ),
    ]);
  }

  void _etat(BuildContext ctx, ContexteEcran c, List<RhbPrimeAcquise> lignes) {
    final tri = trierPar(lignes, (l) => l.employe);
    ColonneEtat m(String l, num Function(Map<String, Object?>) f) => ColonneEtat(libelle: l, droite: true, valeur: (r) => money(f(r), avecDevise: false), somme: f);
    afficherApercu(
        ctx,
        rhbPiece(c,
            titre: 'État des primes diverses',
            sousTitre: '${moisAnnee(c.aujourdhui)} — barème $rhbNs132Reference',
            cartouche: [
              ('Période', moisAnnee(c.aujourdhui)),
              ('Agents primés', nombre(lignes.length)),
              ('Total des primes', money(lignes.fold<num>(0, (a, x) => a + x.total))),
              ('Référence', rhbNs132Reference),
            ],
            tableaux: [
              TableauEtat(colonnes: [
                ColonneEtat(libelle: 'Mat.', valeur: (r) => r['matricule']),
                ColonneEtat(libelle: 'Agent', valeur: (r) => r['employe']),
                ColonneEtat(libelle: 'Fonction', valeur: (r) => rhbFonctionLabel(r['fonction'])),
                ColonneEtat(libelle: 'Gardes', droite: true, valeur: (r) => r['gardes']),
                m('Prime garde', (r) => (r['primeGarde'] as num?) ?? 0),
                ColonneEtat(libelle: 'Perm.', droite: true, valeur: (r) => r['permanences']),
                m('Prime perm.', (r) => (r['primePermanence'] as num?) ?? 0),
                m('Primes fixes', (r) => (r['primesFixes'] as num?) ?? 0),
                m('Total', (r) => (r['total'] as num?) ?? 0),
              ], lignes: [
                for (final x in tri)
                  {
                    'matricule': x.matricule, 'employe': x.employe, 'fonction': x.fonction, 'gardes': x.gardes, 'primeGarde': x.primeGarde,
                    'permanences': x.permanences, 'primePermanence': x.primePermanence, 'primesFixes': x.primesFixes, 'total': x.total
                  }
              ])
            ],
            signatures: const [Signature('Le Responsable RH'), rhbSignDaf, rhbSignDm]));
  }
}
