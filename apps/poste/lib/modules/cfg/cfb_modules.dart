import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'cfa_commun.dart';
import 'cfb_commun.dart';

/// `cfg-modules` — « Activité des modules » : ouvrir ou fermer les activités que la clinique exerce. Fermer une activité la retire du ruban, de la recherche
/// et de ses adresses POUR TOUS LES RÔLES, administrateur compris : ce n'est pas une habilitation, c'est une activité qui n'a pas lieu. Rien n'est supprimé :
/// la réouverture rend les écrans et leurs données en l'état. Chaque module M1…M14/MECEF/GED/RAP/PIL se pilote d'une bascule dérivée du manifeste ; le
/// NOYAU (CFG, DASH) ne se ferme pas — refus nommé, et bascule absente de sa carte. Une fiche ARCHIVÉE ne ferme plus rien (RG-14).
///
/// Ce que la fermeture retire AU POSTE : voir `cfbFermetures` — la coque lit `rbac.json` (engendré) et ne relit pas la collection `modulesActifs` ;
/// c'est une proposition du rapport, pas encore câblée (E203, E886).
class EcranModules extends StatelessWidget with EcranMaquette {
  const EcranModules({super.key});
  @override
  String get titre => 'Activité des modules';
  @override
  String get description => 'Ouvrir ou fermer les activités que la clinique exerce. Un module fermé disparaît du menu sans rien perdre.';
  @override
  String get regle =>
      'Fermer une activité la retire du méga-menu, de la recherche et de ses adresses, pour tous les rôles. Ce n’est pas une habilitation : c’est une activité que l’établissement ne pratique pas. Rien n’est supprimé — la réouverture rend l’écran et ses données en l’état. Depuis la vague 50, chaque module M1…M14 se pilote ici d’une bascule — un autre établissement active seulement ce qu’il exerce — et fermer un module n’empêche jamais un autre de travailler : les stocks, la paie ou les RH fonctionnent Accueil et Soins fermés. Seul le NOYAU (Configuration, tableaux de bord) ne se ferme pas : un interrupteur qui se coupe lui-même ne se rallume plus.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return ListenableBuilder(
        listenable: Listenable.merge([c.magasin.collection('modulesActifs'), c.magasin.collection('modulesManifeste')]),
        builder: (ctx, _) => _Corps(c: c));
  }
}

IconData _icone(String nom) => switch (nom) {
      'calendar-days' => LucideIcons.calendarDays,
      'users' => LucideIcons.users,
      'bed-double' => LucideIcons.bedDouble,
      'baby' => LucideIcons.baby,
      'flask-conical' => LucideIcons.flaskConical,
      'pill' => LucideIcons.pill,
      'truck' => LucideIcons.truck,
      'receipt' => LucideIcons.receipt,
      'shield-check' => LucideIcons.shieldCheck,
      'file-badge' => LucideIcons.fileBadge,
      'book-open-check' => LucideIcons.bookOpenCheck,
      'id-card' => LucideIcons.idCard,
      'banknote' => LucideIcons.banknote,
      'mail' => LucideIcons.mail,
      'folder-open' => LucideIcons.folderOpen,
      'printer' => LucideIcons.printer,
      'shield' => LucideIcons.shield,
      'sliders-horizontal' => LucideIcons.slidersHorizontal,
      'refresh-cw' => LucideIcons.refreshCw,
      'cloud' => LucideIcons.cloud,
      'chart-no-axes-combined' => LucideIcons.chartNoAxesCombined,
      'gauge' => LucideIcons.gauge,
      _ => LucideIcons.box,
    };

class _Corps extends StatelessWidget {
  const _Corps({required this.c});
  final ContexteEcran c;

  CollectionMagasin get _col => c.magasin.collection('modulesActifs');

  List<Fiche> get _rangees => c.magasin.collection('modulesManifeste').toutes;

  // --- les gestes -------------------------------------------------------------------------------------------------------------------------

  Future<void> _basculer(BuildContext ctx, Fiche f) async {
    final fermer = f['actif'] != false;
    // Le NOYAU ne se ferme pas, quelle que soit la porte : refuser EN LE DISANT vaut mieux qu'un interrupteur qui se coupe lui-même.
    final refus = cfbRefusNoyau(f, fermer: fermer);
    if (refus != null) {
      ToastsSigh.afficher(ctx, refus.$1, type: TypeToast.erreur, detail: refus.$2);
      return;
    }
    final (titre, message, ok) = cfbConfirmationBascule(f, fermer: fermer);
    String? motif;
    if (fermer) {
      motif = await confirmerAvecMotif(ctx, titre: titre, message: message, libelleOk: ok, dangereux: true);
      if (motif == null) return;
    } else {
      if (!await confirmerSigh(ctx, titre: titre, message: message, libelleOk: ok)) return;
    }
    if (!ctx.mounted) return;
    final jour = cfbIso(c.aujourdhui);
    final avant = f['actif'];
    _col.mettreAJour(f['id'], {
      'actif': !fermer,
      'motif': fermer ? (cfaVrai(motif) ? motif : f['motif']) : f['motif'],
      'fermeLe': fermer ? jour : null,
      'fermePar': fermer ? c.utilisateur : null,
      'rouvertLe': fermer ? null : jour,
      'rouvertPar': fermer ? null : c.utilisateur,
    });
    c.magasin.journaliser(fermer ? 'Fermeture d’une activité' : 'Réouverture d’une activité', 'CFG', 'Activité', '${f['code']}', {'actif': avant}, {'actif': !fermer});
    ToastsSigh.afficher(ctx, fermer ? 'Activité fermée.' : 'Activité rouverte.',
        type: TypeToast.succes,
        detail: fermer ? 'Les écrans concernés quittent le menu ; leurs données restent intactes.' : 'Les écrans réapparaissent au menu avec leurs données.');
  }

  void _basculerModule(BuildContext ctx, CfbModuleRuban m) {
    var fiche = cfbFicheModule(_col.actives, m.code);
    // La fiche naît OUVERTE au premier geste : la fermeture, avec son motif, est un second geste délibéré.
    fiche ??= _col.inserer({'statut': 'actif', 'code': 'MODULE-${m.code}', 'module': m.code, 'libelle': 'Module — ${m.label}', 'actif': true, 'motif': null}, prefixe: 'MOD').fiche;
    _basculer(ctx, fiche);
  }

  void _declarer(BuildContext ctx, List<CfbEcranModule> ecrans, List<CfbModuleRuban> modules) {
    final ctl = ControleurFormulaire([
      const ChampDef(nom: 'libelle', libelle: 'Intitulé de l’activité', requis: true, col: ColChamp.plein),
      ChampDef(nom: 'module', libelle: 'Module concerné', type: TypeChamp.select, requis: true, options: [for (final m in modules) OptionChamp(m.code, '${m.code} — ${m.label}')]),
      ChampDef(
          nom: 'ecrans',
          libelle: 'Écrans concernés',
          type: TypeChamp.multiselect,
          col: ColChamp.plein,
          options: [for (final e in ecrans) OptionChamp(e.id, '${e.moduleLabel} · ${e.label}')],
          aide: 'Laisser vide pour piloter le module entier.'),
      const ChampDef(
          nom: 'motif',
          libelle: 'Motif',
          type: TypeChamp.textarea,
          lignes: 2,
          requis: true,
          col: ColChamp.plein,
          aide: 'Pourquoi la clinique n’exerce pas cette activité — le motif s’affiche à l’écran.'),
    ]);
    afficherModale<void>(ctx,
        titre: 'Piloter une activité',
        taille: TailleModale.lg,
        corps: cfaPile([
          cfbNote('Déclarer une activité permet de l’ouvrir ou la fermer par la suite. Elle est créée ouverte : la fermeture est un second geste, délibéré.'),
          FormulaireSigh(controleur: ctl),
        ], espace: 12),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: 'Déclarer',
                  icone: LucideIcons.plus,
                  onPressed: () {
                    final v = ctl.valider();
                    if (v == null) return;
                    fermer();
                    final r = _col.inserer({
                      'statut': 'actif',
                      'libelle': v['libelle'],
                      'module': v['module'],
                      'ecrans': [for (final e in (v['ecrans'] as List? ?? const [])) '$e'],
                      'motif': v['motif'],
                      'code': cfbCodeActivite('${v['module']}', '${v['libelle']}'),
                      'actif': true,
                    }, prefixe: 'MOD');
                    ToastsSigh.afficher(ctx, 'Activité déclarée.', type: TypeToast.succes, detail: '${r.fiche['libelle']} — ouverte.', annuler: r.annuler, messageAnnulation: 'Déclaration annulée — la fiche est archivée.');
                  }),
            ]);
  }

  // --- les composants ---------------------------------------------------------------------------------------------------------------------

  Widget _carteModule(BuildContext ctx, CfbModuleRuban m) {
    final fiche = cfbFicheModule(_col.actives, m.code);
    final ferme = fiche != null && fiche['actif'] == false;
    final noyau = cfbNoyau[m.code];
    final detail = noyau != null
        ? 'NOYAU : $noyau'
        : '${nombre(m.nbEcrans)} écran(s) · ${m.domaine}${ferme && cfaVrai(fiche['fermeLe']) ? ' · fermé le ${dateFR(DateTime.parse('${fiche['fermeLe']}'))}' : ''}';
    return Opacity(
        opacity: ferme ? 0.75 : 1,
        child: CarteSigh(
            child: Row(children: [
          Icon(_icone(m.icone), size: 24, color: ferme ? JetonsShell.slate400 : JetonsShell.navy600),
          const SizedBox(width: 12),
          Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${m.code} — ${m.label}', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w500, color: JetonsShell.slate800)),
            Text(detail, style: const TextStyle(fontSize: 12, height: 16 / 12, color: JetonsShell.slate400)),
          ])),
          const SizedBox(width: 8),
          if (noyau != null)
            const BadgeSigh('Toujours ouvert', ton: TonSigh.navy)
          else if (ferme)
            const BadgeSigh('Fermé', ton: TonSigh.attention)
          else
            const BadgeSigh('Ouvert', ton: TonSigh.succes),
          if (noyau == null && c.droit.editer)
            BoutonIcone(
                icone: ferme ? LucideIcons.toggleRight : LucideIcons.toggleLeft,
                libelle: ferme ? 'Rouvrir le module ${m.code}' : 'Fermer le module ${m.code}',
                onPressed: () => _basculerModule(ctx, m)),
        ])));
  }

  @override
  Widget build(BuildContext context) {
    final fiches = _col.actives;
    final fermees = fiches.where((f) => f['actif'] == false).toList();
    final ecrans = cfbTousEcrans(_rangees);
    final modules = cfbListeModules(_rangees);
    final fermetures = CfbFermetures.depuis(_col.toutes);
    final retires = ecrans.where((e) => !fermetures.ecranActif(e.id, e.module)).toList();
    final lignes = [
      for (final f in fiches) {...f, 'portee': cfbPortee(f)}
    ];
    return cfaPile([
      cfaLectureSeule(c),
      cfaKpis(cfbKpisModules(ecrans: ecrans.length, fermees: fermees.length, retires: retires.length)),
      cfbNote(
          'Une activité fermée n’est pas supprimée. Ses écrans, ses données de démonstration et son paramétrage restent en place : rouvrir l’activité les rend en l’état. C’est ce qui distingue cette page d’une suppression, et ce qui permet de fermer sans crainte.',
          icone: LucideIcons.archiveRestore),
      TableauSigh(
        titre: 'Activités pilotées',
        lignes: lignes,
        recherche: false,
        taillePage: 15,
        nomExport: 'activite-modules',
        messageVide: 'Aucune activité pilotée — toutes les activités du logiciel sont ouvertes.',
        colonnes: [
          ColonneTableau(
              cle: 'libelle',
              libelle: 'Activité',
              texte: (f) => '${f['libelle']} ${f['portee']}',
              rendu: (_, f) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text('${f['libelle']}', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w500, color: JetonsShell.slate800)),
                    Text('${f['portee']}', style: const TextStyle(fontSize: 12, height: 16 / 12, color: JetonsShell.slate400)),
                  ])),
          ColonneTableau(cle: 'module', libelle: 'Module', sansCoupure: true, rendu: (_, f) => BadgeSigh('${f['module']}', ton: TonSigh.navy)),
          ColonneTableau(
              cle: 'actif',
              libelle: 'État',
              texte: (f) => f['actif'] == false ? 'fermée' : 'ouverte',
              rendu: (_, f) => f['actif'] == false ? const BadgeSigh('Fermée', ton: TonSigh.attention) : const BadgeSigh('Ouverte', ton: TonSigh.succes)),
          ColonneTableau(
              cle: 'motif',
              libelle: 'Motif',
              rendu: (_, f) => Text(cfaOuTiret(f['motif']), style: const TextStyle(fontSize: 12, height: 16 / 12, color: JetonsShell.slate500))),
          ColonneTableau(
              cle: 'fermeLe',
              libelle: 'Depuis le',
              droite: true,
              sansCoupure: true,
              texte: (f) => f['actif'] == false && cfaVrai(f['fermeLe']) ? dateFR(DateTime.parse('${f['fermeLe']}')) : '—',
              rendu: (_, f) => f['actif'] == false && cfaVrai(f['fermeLe'])
                  ? Text(dateFR(DateTime.parse('${f['fermeLe']}')), style: const TextStyle(fontSize: 12, height: 16 / 12, color: JetonsShell.slate500))
                  : const Text('—', style: TextStyle(fontSize: 12, height: 16 / 12, color: JetonsShell.slate300))),
        ],
        actions: [
          if (c.droit.editer)
            BoutonSigh(libelle: 'Piloter une activité', icone: LucideIcons.plus, taille: TailleBouton.sm, onPressed: () => _declarer(context, ecrans, modules)),
        ],
        actionsLigne: (ctx, f) => [
          if (c.droit.editer)
            BoutonIcone(
                icone: f['actif'] == false ? LucideIcons.toggleRight : LucideIcons.toggleLeft,
                libelle: f['actif'] == false ? 'Rouvrir cette activité' : 'Fermer cette activité',
                onPressed: () => _basculer(ctx, f)),
        ],
      ),
      CarteSigh(
          titre: 'Modules du logiciel — activer seulement ce que l’établissement exerce',
          child: cfaPile([
            cfbNote(
                'Fermer un module n’empêche jamais un autre de travailler. Les stocks, la paie ou les ressources humaines fonctionnent Accueil et Soins fermés : les files que le module fermé alimentait cessent simplement de se remplir, ses données restent en place, et la saisie directe des autres postes demeure ouverte — c’est la doctrine du laboratoire (saisie manuelle) et de l’accueil externe, appliquée partout.',
                icone: LucideIcons.unplug),
            LayoutBuilder(builder: (ctx, k) {
              final n = k.maxWidth >= 1280 ? 3 : (k.maxWidth >= 768 ? 2 : 1);
              final l = (k.maxWidth - 12 * (n - 1)) / n;
              return Wrap(spacing: 12, runSpacing: 12, children: [for (final m in modules) SizedBox(width: l, child: _carteModule(ctx, m))]);
            }),
          ], espace: 12)),
      if (retires.isNotEmpty)
        CarteSigh(
            titre: 'Écrans actuellement retirés du méga-menu',
            child: MiniTableauSigh(colonnes: [
              ColonneMini('Écran', (e) => '${e['label']}'),
              ColonneMini('Module', (e) => '${e['moduleLabel']}'),
              ColonneMini('Domaine', (e) => '${e['domaine']}'),
              ColonneMini('Motif', (e) => '${e['motif']}', rendu: (e) => Text('${e['motif']}', style: const TextStyle(fontSize: 12, height: 16 / 12, color: JetonsShell.slate500))),
            ], lignes: [
              for (final e in retires)
                {'label': e.label, 'moduleLabel': e.moduleLabel, 'domaine': e.domaine, 'motif': '${fermetures.fermeturePour(e.id, e.module)?['motif'] ?? '—'}'}
            ])),
    ]);
  }
}
