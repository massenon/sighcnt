import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'commun_m14.dart';

/// `m14-roles` — « Rôles & permissions (RBAC) » : la matrice des droits ADMINISTRABLE (vague 15) : voir, éditer, annuler par rôle et par module, réglage
/// écran par écran, création, renommage, archivage (RG-14 : un rôle s'archive, il ne se supprime jamais) et tentatives de connexion refusées.
///
/// COMMENT CET ÉCRAN S'ARTICULE AVEC LE MOTEUR DE DROITS DU POSTE (il ne le réécrit pas) :
///  * `MatriceDroits` (packages/domaine) est ENGENDRÉE depuis `packages/rbac/data/rbac.json` et reste la seule autorité de ce que le poste AFFICHE et
///    AUTORISE : ruban, accès aux écrans, commandes d'écriture ;
///  * cet écran part de la MÊME matrice (la collection `rolesBase`, dérivée de ce JSON par `gen-jeu-securite.js`, lue sans jamais être écrite) et y pose les
///    décisions de l'administrateur, collection `rbac` (une fiche par rôle, calquée sur la maquette), que `packages/domaine/src/securite/sec_roles.dart`
///    applique comme `N.droits()` de la maquette ;
///  * ces décisions sont consignées et journalisées (RG-12) mais `MatriceDroits` ne les relit pas : fermer un module ici ne retire pas encore l'écran du ruban
///    du poste. Le pas suivant est de régénérer la matrice engendrée depuis ces fiches. L'écran le dit en pied de page.
/// La connexion refusée d'un rôle archivé (et sa tentative journalisée dans `tentativesConnexion`) est celle du serveur d'authentification : le poste n'ouvre
/// pas de session par compte, il n'écrit donc jamais de tentative — l'onglet lit celles que la collection porte.
class EcranRoles extends StatelessWidget with EcranMaquette {
  const EcranRoles({super.key});

  @override
  String get description =>
      'Matrice des droits d’accès par rôle et par module : voir, éditer, annuler. Renommage et archivage des rôles.';

  @override
  String get regle =>
      'RG-13 — l’accès aux données médicales est réservé au personnel soignant habilité ; l’accès aux données financières et RH aux profils comptables et RH. RG-14 — un rôle ne se supprime pas, il s’archive : ses comptes cessent alors d’ouvrir une session et chaque tentative est journalisée.';

  @override
  List<Widget> actionsEntete(BuildContext context) {
    final c = ContexteEcran.of(context);
    if (!c.droit.editer) return const [];
    return [
      BoutonSigh(
          libelle: 'Nouveau rôle',
          icone: LucideIcons.userPlus,
          onPressed: () => _creerRole(context, c)),
    ];
  }

  @override
  Widget build(BuildContext context) => const _VueRoles();
}

// --- Lecture du magasin --------------------------------------------------------------------------------------------------------------------------

class _Ctx {
  _Ctx(this.c)
      : m = c.magasin,
        base = c.magasin.collection('rolesBase').toutes,
        sur = surchargesRbac(c.magasin) {
    bases = {for (final b in base) '${b['id']}': b};
    roles = secRoles(base, sur);
    modules = rangeesManifeste(c.magasin);
    universels = {
      for (final r in modules)
        for (final u in ((r['universels'] as List?) ?? const [])) '$u'
    };
  }
  final ContexteEcran c;
  final Magasin m;
  final List<Fiche> base;
  final Map<String, Fiche> sur;
  late final Map<String, Fiche> bases;
  late final List<RoleSec> roles;
  late final List<Fiche> modules;
  late final Set<String> universels;

  List<RoleSec> get actifs => [
        for (final r in roles)
          if (!r.archive) r
      ];
  List<RoleSec> get archives => [
        for (final r in roles)
          if (r.archive) r
      ];
  RoleSec? role(String id) => roles.where((r) => r.id == id).firstOrNull;
  String libelle(String id) => role(id)?.label ?? id;

  DroitSec droit(String role, String code) =>
      secDroitModule(role, code, bases: bases, sur: sur, rolesBase: base);

  DroitSec droitEcran(String role, String ecran, String code) =>
      secDroitEcran(role, ecran, code,
          bases: bases, sur: sur, rolesBase: base, universels: universels);

  List<Fiche> comptes(String role) => [
        for (final u in m.collection('utilisateurs').actives)
          if (u['role'] == role) u
      ];

  /// `ficheRole(roleId)` : la PREMIÈRE fiche du rôle (les doublons se fusionnent à la lecture, l'écriture va à la première).
  Fiche? fiche(String role) =>
      m.collection('rbac').toutes.where((f) => f['role'] == role).firstOrNull;

  /// `enregistrer(roleId, valeurs, journal)` : met à jour la fiche du rôle ou en crée une, puis journalise (RG-12). Rend l'annulation.
  VoidCallback enregistrer(
      String role, Map<String, Object?> valeurs, String journal) {
    final col = m.collection('rbac');
    final f = fiche(role);
    VoidCallback annuler;
    if (f != null) {
      annuler = col.mettreAJour(f['id'], valeurs);
    } else {
      annuler = col.inserer({
        'role': role,
        'libelleOrigine': this.role(role)?.labelOrigine ?? role,
        ...valeurs,
      }, prefixe: 'RBAC').annuler;
    }
    m.journaliser(journal, 'M14', 'Rôle', role, null, valeurs);
    return annuler;
  }
}

String _dateHeureIso(Object? v) {
  final d = secHorodatage(v);
  return d == null ? '—' : dateHeure(d);
}

// --- La vue ---------------------------------------------------------------------------------------------------------------------------------------

class _VueRoles extends StatefulWidget {
  const _VueRoles();
  @override
  State<_VueRoles> createState() => _VueRolesState();
}

class _VueRolesState extends State<_VueRoles> {
  final List<CollectionMagasin> _cols = [];
  String? _ancre;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final m = ContexteEcran.of(context).magasin;
    final voulues = [
      m.collection('rbac'),
      m.collection('tentativesConnexion'),
      m.collection('utilisateurs'),
    ];
    if (_cols.length != voulues.length ||
        [
          for (var i = 0; i < voulues.length; i++)
            identical(_cols[i], voulues[i])
        ].contains(false)) {
      for (final c in _cols) {
        c.removeListener(_maj);
      }
      _cols
        ..clear()
        ..addAll(voulues);
      for (final c in _cols) {
        c.addListener(_maj);
      }
    }
  }

  @override
  void dispose() {
    for (final c in _cols) {
      c.removeListener(_maj);
    }
    super.dispose();
  }

  void _maj() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final x = _Ctx(c);
    final tentatives = c.magasin.collection('tentativesConnexion').actives;
    final nonTraitees = [
      for (final t in tentatives)
        if (secTentativeAExaminer(t)) t
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (nonTraitees.isNotEmpty) ...[
        _AlerteTentatives(
            liste: nonTraitees,
            surExaminer: () => setState(() => _ancre = 'tentatives')),
        const SizedBox(height: 16),
      ],
      KpiGrilleSigh(kpis: [
        KpiSigh(
            libelle: 'Rôles actifs',
            valeur: nombre(x.actifs.length),
            icone: LucideIcons.shield,
            ton: TonSigh.navy),
        KpiSigh(
            libelle: 'Rôles archivés',
            valeur: nombre(x.archives.length),
            icone: LucideIcons.archive,
            ton: x.archives.isNotEmpty ? TonSigh.attention : TonSigh.neutre,
            indice: x.archives.isNotEmpty
                ? 'Leurs comptes ne peuvent plus se connecter'
                : 'Aucun rôle retiré'),
        KpiSigh(
            libelle: 'Modules protégés',
            valeur: nombre(x.modules.length),
            icone: LucideIcons.lock,
            ton: TonSigh.info),
        KpiSigh(
            libelle: 'Tentatives refusées',
            valeur: nombre(nonTraitees.length),
            icone: LucideIcons.shieldAlert,
            ton: nonTraitees.isNotEmpty ? TonSigh.danger : TonSigh.succes,
            indice: nonTraitees.isNotEmpty
                ? 'À examiner'
                : 'Aucune tentative en attente'),
      ]),
      const SizedBox(height: 16),
      OngletsSigh(
        key: ValueKey(_ancre),
        ancre: _ancre,
        onglets: [
          OngletDef(
              id: 'matrice',
              libelle: 'Matrice des droits',
              compte: x.actifs.length,
              construire: (ctx) => _OngletMatrice(x: x)),
          OngletDef(
              id: 'detail',
              libelle: 'Détail par rôle',
              construire: (ctx) => _OngletDetail(x: x)),
          OngletDef(
              id: 'metier',
              libelle: 'Habilitations métier',
              construire: (ctx) => const _OngletMetier()),
          OngletDef(
              id: 'tentatives',
              libelle: 'Tentatives refusées',
              compte: tentatives.length,
              construire: (ctx) => _OngletTentatives(x: x)),
          OngletDef(
              id: 'archives',
              libelle: 'Rôles archivés',
              compte: x.archives.length,
              construire: (ctx) => _OngletArchives(x: x)),
        ],
      ),
      const SizedBox(height: 16),
      const NoteSigh(
          'Articulation avec le moteur de droits du poste : les décisions saisies ici sont consignées dans la collection « rbac » et journalisées (RG-12) ; cette matrice les superpose à la matrice engendrée du poste (rbac.json). Le moteur de droits du poste (MatriceDroits) ne les relit pas encore : le ruban et les accès du poste restent ceux de la matrice engendrée.',
          ton: TonSigh.attention,
          icone: LucideIcons.triangleAlert),
    ]);
  }
}

// --- Barre de notification ---------------------------------------------------------------------------------------------------------------------

class _AlerteTentatives extends StatelessWidget {
  const _AlerteTentatives({required this.liste, required this.surExaminer});
  final List<Fiche> liste;
  final VoidCallback surExaminer;

  @override
  Widget build(BuildContext context) {
    final t = liste.first;
    return Container(
      key: const Key('m14:alerte-tentatives'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
          color: JetonsShell.danger50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: JetonsShell.danger200)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(LucideIcons.shieldAlert,
            size: 20, color: JetonsShell.danger600),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${nombre(liste.length)} tentative(s) de connexion refusée(s)',
              style: const TextStyle(
                  color: JetonsShell.danger900,
                  fontSize: 14,
                  height: 20 / 14,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(
              'Comptes rattachés à un rôle archivé. Dernière : ${secVrai(t['nom']) ? t['nom'] : t['identifiant']} — ${_dateHeureIso(t['horodatage'])}',
              style: const TextStyle(
                  color: JetonsShell.danger800, fontSize: 12, height: 16 / 12)),
        ])),
        const SizedBox(width: 12),
        BoutonSigh(
            libelle: 'Examiner',
            icone: LucideIcons.eye,
            taille: TailleBouton.sm,
            variante: VarianteBouton.danger,
            onPressed: surExaminer),
      ]),
    );
  }
}

// --- Onglet 1 : la matrice ----------------------------------------------------------------------------------------------------------------------

class _OngletMatrice extends StatelessWidget {
  const _OngletMatrice({required this.x});
  final _Ctx x;

  Widget _pastille(DroitSec d) {
    final etat = secEtatCase(d);
    final (fond, texte, icone) = switch (etat) {
      EtatCaseSec.ferme => (
          JetonsShell.slate100,
          JetonsShell.slate300,
          LucideIcons.x
        ),
      EtatCaseSec.lectureSeule => (
          JetonsShell.info100,
          JetonsShell.info700,
          LucideIcons.eye
        ),
      EtatCaseSec.partiel => (
          JetonsShell.warning100,
          JetonsShell.warning700,
          LucideIcons.pencil
        ),
      EtatCaseSec.plein => (
          JetonsShell.success100,
          JetonsShell.success700,
          LucideIcons.check
        ),
    };
    return Tooltip(
        message: secInfobulleCase(d),
        child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
                color: fond, borderRadius: BorderRadius.circular(4)),
            child: Icon(icone, size: 12, color: texte)));
  }

  @override
  Widget build(BuildContext context) {
    final c = x.c;
    const largeRole = 240.0;
    const largeCase = 44.0;
    const largeActions = 170.0;
    final entete = const TextStyle(
        color: JetonsShell.slate500,
        fontSize: 12,
        height: 16 / 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.6);
    Widget cel(Widget w, {Alignment a = Alignment.center}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Align(alignment: a, child: w));
    final table = Table(
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      columnWidths: {
        0: const FixedColumnWidth(largeRole),
        for (var i = 0; i < x.modules.length; i++)
          i + 1: const FixedColumnWidth(largeCase),
        x.modules.length + 1: const FixedColumnWidth(largeActions),
      },
      children: [
        TableRow(
            decoration: const BoxDecoration(
                color: JetonsShell.slate50,
                border:
                    Border(bottom: BorderSide(color: JetonsShell.slate200))),
            children: [
              cel(Text('RÔLE', style: entete), a: Alignment.centerLeft),
              for (final mo in x.modules)
                Tooltip(
                    message: '${mo['label']}',
                    child: cel(Text('${mo['code']}',
                        style: entete.copyWith(
                            fontFamily: 'LiberationMono', letterSpacing: 0)))),
              cel(Text('ACTIONS', style: entete), a: Alignment.centerRight),
            ]),
        for (final r in x.actifs)
          TableRow(
              decoration: const BoxDecoration(
                  border:
                      Border(bottom: BorderSide(color: JetonsShell.slate100))),
              children: [
                cel(
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(r.label,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: JetonsShell.slate800,
                                  fontSize: 14,
                                  height: 20 / 14,
                                  fontWeight: FontWeight.w500)),
                          Text(
                              '${nombre(x.comptes(r.id).length)} compte(s)${r.labelOrigine != r.label ? ' · ex-${r.labelOrigine}' : ''}',
                              style: const TextStyle(
                                  color: JetonsShell.slate400,
                                  fontSize: 12,
                                  height: 16 / 12)),
                        ]),
                    a: Alignment.centerLeft),
                for (final mo in x.modules)
                  cel(_pastille(x.droit(r.id, '${mo['code']}'))),
                cel(
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      if (c.droit.editer) ...[
                        BoutonIcone(
                            icone: LucideIcons.slidersHorizontal,
                            libelle: 'Modifier les droits de ce rôle',
                            onPressed: () => _editerRole(context, x, r)),
                        BoutonIcone(
                            icone: LucideIcons.listTree,
                            libelle: 'Régler écran par écran',
                            onPressed: () => _editerEcrans(context, x, r)),
                        BoutonIcone(
                            icone: LucideIcons.pencil,
                            libelle: 'Renommer ce rôle',
                            onPressed: () => _renommer(context, x, r)),
                      ],
                      if (c.droit.annuler)
                        BoutonIcone(
                            icone: LucideIcons.archive,
                            libelle: 'Archiver ce rôle',
                            onPressed: () => _archiver(context, x, r)),
                    ]),
                    a: Alignment.centerRight),
              ]),
      ],
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const NoteSigh(
          'Chaque case résume les trois droits du rôle sur le module : vert plein accès, bleu lecture seule, gris module fermé. Le détail se règle case par case avec le bouton « Modifier les droits ».'),
      const SizedBox(height: 16),
      CarteSigh(
          titre: 'Matrice des droits d’accès',
          actions: [
            BoutonSigh(
                libelle: 'Imprimer la matrice',
                icone: LucideIcons.printer,
                taille: TailleBouton.sm,
                onPressed: () => _imprimerMatrice(context, x)),
          ],
          sansRemplissage: true,
          child: SingleChildScrollView(
              scrollDirection: Axis.horizontal, child: table)),
    ]);
  }
}

// --- Onglet 2 : le détail lisible par rôle ---------------------------------------------------------------------------------------------------------

class _OngletDetail extends StatelessWidget {
  const _OngletDetail({required this.x});
  final _Ctx x;

  @override
  Widget build(BuildContext context) {
    final c = x.c;
    return CarteSigh(
        titre: 'Niveaux d’accès par rôle',
        child: LayoutBuilder(builder: (_, k) {
          final n = k.maxWidth >= 1024 ? 3 : (k.maxWidth >= 768 ? 2 : 1);
          final l = (k.maxWidth - 12 * (n - 1)) / n;
          return Wrap(spacing: 12, runSpacing: 12, children: [
            for (final r in x.actifs)
              SizedBox(
                  width: l,
                  child: Builder(builder: (context) {
                    final ouverts = [
                      for (final mo in x.modules)
                        if (x.droit(r.id, '${mo['code']}').voir) mo
                    ];
                    final lecture = [
                      for (final mo in ouverts)
                        if (x.droit(r.id, '${mo['code']}').lectureSeule) mo
                    ];
                    return CarteSigh(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Row(children: [
                            Expanded(
                                child: Text(r.label,
                                    style: const TextStyle(
                                        color: JetonsShell.slate800,
                                        fontSize: 14,
                                        height: 20 / 14,
                                        fontWeight: FontWeight.w600))),
                            BadgeSigh(nombre(x.comptes(r.id).length),
                                ton: TonSigh.navy),
                          ]),
                          const SizedBox(height: 8),
                          Wrap(spacing: 4, runSpacing: 4, children: [
                            for (final mo in ouverts)
                              () {
                                final d = x.droit(r.id, '${mo['code']}');
                                return BadgeSigh('${mo['code']}',
                                    ton: d.lectureSeule
                                        ? TonSigh.info
                                        : (d.origine
                                            ? TonSigh.neutre
                                            : TonSigh.succes));
                              }()
                          ]),
                          const SizedBox(height: 8),
                          Text(
                              '${nombre(ouverts.length)} module(s) ouvert(s)${lecture.isNotEmpty ? ' — dont ${nombre(lecture.length)} en lecture seule' : ''}',
                              style: const TextStyle(
                                  color: JetonsShell.slate500,
                                  fontSize: 12,
                                  height: 16 / 12)),
                          if (c.droit.editer) ...[
                            const SizedBox(height: 8),
                            Row(children: [
                              BoutonSigh(
                                  libelle: 'Droits',
                                  icone: LucideIcons.slidersHorizontal,
                                  taille: TailleBouton.sm,
                                  variante: VarianteBouton.secondaire,
                                  onPressed: () => _editerRole(context, x, r)),
                              const SizedBox(width: 4),
                              BoutonSigh(
                                  libelle: 'Renommer',
                                  icone: LucideIcons.pencil,
                                  taille: TailleBouton.sm,
                                  variante: VarianteBouton.secondaire,
                                  onPressed: () => _renommer(context, x, r)),
                            ]),
                          ],
                        ]));
                  })),
          ]);
        }));
  }
}

// --- Onglet 3 : habilitations métier --------------------------------------------------------------------------------------------------------

class _OngletMetier extends StatelessWidget {
  const _OngletMetier();

  @override
  Widget build(BuildContext context) {
    final rows = secHabilitationsMetier();
    BadgeSigh badge(
        Map<String, (String, TonSigh)> m, Object? v, (String, TonSigh) defaut) {
      final x = m['$v'] ?? defaut;
      return BadgeSigh(x.$1, ton: x.$2);
    }

    const resultats = {
      'tous': ('Tous', TonSigh.succes),
      'secteur': ('Son secteur', TonSigh.info),
      'produits': ('Ceux qu’il produit', TonSigh.info),
      'aucun': ('Aucun', TonSigh.neutre),
    };
    const echo = {
      'tous': ('Toutes', TonSigh.succes),
      'secteur': ('Son secteur', TonSigh.info),
      'aucun': ('Aucune', TonSigh.neutre),
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TableauSigh(
        titre: 'Habilitations métier par fonction',
        lignes: rows,
        taillePage: 20,
        nomExport: 'habilitations-metier',
        colonnes: [
          ColonneTableau(
              cle: 'label',
              libelle: 'Fonction',
              rendu: (_, r) => Text('${r['label']}',
                  style: const TextStyle(
                      color: JetonsShell.slate800,
                      fontSize: 14,
                      height: 20 / 14,
                      fontWeight: FontWeight.w500))),
          ColonneTableau(
              cle: 'resultats',
              libelle: 'Résultats d’analyses',
              texte: (r) =>
                  (resultats['${r['resultats']}'] ?? resultats['aucun']!).$1,
              rendu: (_, r) =>
                  badge(resultats, r['resultats'], resultats['aucun']!)),
          ColonneTableau(
              cle: 'echographie',
              libelle: 'Échographies',
              texte: (r) => (echo['${r['echographie']}'] ?? echo['aucun']!).$1,
              rendu: (_, r) => badge(echo, r['echographie'], echo['aucun']!)),
          ColonneTableau(
              cle: 'prescrire',
              libelle: 'Peut prescrire',
              texte: (r) => '${r['natures']}',
              rendu: (_, r) => (r['prescrire'] as int) > 0
                  ? Text('${r['natures']}',
                      style: const TextStyle(
                          color: JetonsShell.slate600,
                          fontSize: 12,
                          height: 16 / 12))
                  : const Text('non',
                      style: TextStyle(
                          color: JetonsShell.slate300,
                          fontSize: 12,
                          height: 16 / 12))),
          ColonneTableau(
              cle: 'soins',
              libelle: 'Exécute les soins',
              texte: (r) => r['soins'] == true ? 'oui' : 'non',
              rendu: (_, r) => r['soins'] == true
                  ? const BadgeSigh('Oui', ton: TonSigh.succes)
                  : const BadgeSigh('Non')),
          ColonneTableau(
              cle: 'note',
              libelle: 'Règle appliquée',
              rendu: (_, r) => Text('${r['note']}',
                  style: const TextStyle(
                      color: JetonsShell.slate500,
                      fontSize: 12,
                      height: 16 / 12))),
        ],
      ),
      const SizedBox(height: 12),
      const NoteSigh(
          'Le rôle ouvre les écrans, la fonction décide des données, le secteur en fixe le périmètre. Ces habilitations-ci s’appliquent aux données, indépendamment de l’écran ouvert.',
          ton: TonSigh.info,
          icone: LucideIcons.quote),
    ]);
  }
}

// --- Onglet 4 : tentatives refusées ----------------------------------------------------------------------------------------------------------

class _OngletTentatives extends StatelessWidget {
  const _OngletTentatives({required this.x});
  final _Ctx x;

  @override
  Widget build(BuildContext context) {
    final c = x.c;
    final col = x.m.collection('tentativesConnexion');
    final rows = [
      for (final t in col.actives)
        {
          ...t,
          'quand': _dateHeureIso(t['horodatage']),
          'roleLabel': x.libelle('${t['role']}'),
        }
    ]..sort((a, b) => '${b['horodatage']}'.compareTo('${a['horodatage']}'));
    if (rows.isEmpty) {
      return const CarteSigh(
          titre: 'Tentatives de connexion refusées',
          child: VideSigh('Aucune tentative refusée.',
              icone: LucideIcons.shieldCheck,
              indice:
                  'Les comptes rattachés à un rôle archivé apparaîtraient ici, avec leur horodatage.'));
    }
    return TableauSigh(
      titre: 'Tentatives de connexion refusées',
      lignes: rows,
      taillePage: 15,
      nomExport: 'tentatives-refusees',
      filtres: [
        FiltreTableau(
            nom: 'traitee',
            libelle: 'Suivi',
            options: const [
              OptionChamp('non', 'À examiner'),
              OptionChamp('oui', 'Examinée')
            ],
            correspond: (r, v) =>
                v == 'oui' ? secVrai(r['traitee']) : !secVrai(r['traitee'])),
      ],
      colonnes: [
        const ColonneTableau(
            cle: 'quand', libelle: 'Date et heure', sansCoupure: true),
        ColonneTableau(
            cle: 'nom',
            libelle: 'Compte',
            texte: (r) => '${r['nom'] ?? ''} ${r['identifiant'] ?? ''}',
            rendu: (_, r) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${secVrai(r['nom']) ? r['nom'] : r['identifiant']}',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: JetonsShell.slate800,
                              fontSize: 14,
                              height: 20 / 14,
                              fontWeight: FontWeight.w500)),
                      Text('${r['identifiant'] ?? ''}',
                          style: const TextStyle(
                              color: JetonsShell.slate400,
                              fontSize: 12,
                              height: 16 / 12)),
                    ])),
        const ColonneTableau(cle: 'roleLabel', libelle: 'Rôle'),
        ColonneTableau(
            cle: 'motif',
            libelle: 'Motif du refus',
            rendu: (_, r) => Text('${r['motif'] ?? ''}',
                style: const TextStyle(
                    color: JetonsShell.danger700,
                    fontSize: 12,
                    height: 16 / 12))),
        ColonneTableau(
            cle: 'traitee',
            libelle: 'Suivi',
            droite: true,
            texte: (r) => secVrai(r['traitee']) ? 'examinée' : 'à examiner',
            rendu: (_, r) => secVrai(r['traitee'])
                ? const BadgeSigh('Examinée', ton: TonSigh.succes)
                : const BadgeSigh('À examiner', ton: TonSigh.danger)),
      ],
      actionsLigne: (context, r) => [
        if (!secVrai(r['traitee']) && c.droit.editer)
          BoutonIcone(
              icone: LucideIcons.check,
              libelle: 'Marquer comme examinée',
              onPressed: () {
                col.mettreAJour(r['id'], {
                  'traitee': true,
                  'examineePar': c.utilisateur,
                  'examineeLe': iso(c.aujourdhui),
                });
                ToastsSigh.afficher(
                    context, 'Tentative marquée comme examinée.',
                    type: TypeToast.succes);
              }),
      ],
    );
  }
}

// --- Onglet 5 : rôles archivés ---------------------------------------------------------------------------------------------------------------

class _OngletArchives extends StatelessWidget {
  const _OngletArchives({required this.x});
  final _Ctx x;

  @override
  Widget build(BuildContext context) {
    final c = x.c;
    if (x.archives.isEmpty) {
      return const CarteSigh(
          titre: 'Rôles archivés',
          child: VideSigh('Aucun rôle archivé.',
              icone: LucideIcons.shieldCheck,
              indice:
                  'Un rôle archivé reste dans le manifeste — il cesse simplement d’ouvrir une session.'));
    }
    final rows = [
      for (final r in x.archives)
        () {
          final f = x.fiche(r.id) ?? const <String, Object?>{};
          final d =
              secVrai(f['archiveLe']) ? secHorodatage(f['archiveLe']) : null;
          return <String, Object?>{
            'role': r.id,
            'label': r.label,
            'comptes': x.comptes(r.id).length,
            'archiveLe': d == null ? '—' : dateFR(d),
            'motif': secVrai(f['motifArchivage']) ? f['motifArchivage'] : '—',
          };
        }()
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const NoteSigh(
          'RG-14 — l’archivage est logique : le rôle n’est pas supprimé, ses habilitations sont conservées et la restauration rend immédiatement l’accès à ses comptes.',
          ton: TonSigh.attention),
      const SizedBox(height: 12),
      TableauSigh(
        titre: 'Rôles archivés',
        lignes: rows,
        taillePage: 10,
        nomExport: 'roles-archives',
        colonnes: [
          ColonneTableau(
              cle: 'label',
              libelle: 'Rôle',
              rendu: (_, r) => Text('${r['label']}',
                  style: const TextStyle(
                      color: JetonsShell.slate800,
                      fontSize: 14,
                      height: 20 / 14,
                      fontWeight: FontWeight.w500))),
          ColonneTableau(
              cle: 'comptes',
              libelle: 'Comptes bloqués',
              droite: true,
              texte: (r) => '${r['comptes']}',
              rendu: (_, r) => (r['comptes'] as int) > 0
                  ? BadgeSigh(nombre(r['comptes']), ton: TonSigh.danger)
                  : const Text('—',
                      style: TextStyle(
                          color: JetonsShell.slate300, fontSize: 12))),
          const ColonneTableau(
              cle: 'archiveLe', libelle: 'Archivé le', sansCoupure: true),
          const ColonneTableau(cle: 'motif', libelle: 'Motif'),
        ],
        actionsLigne: (context, r) => [
          if (c.droit.annuler)
            BoutonIcone(
                icone: LucideIcons.archiveRestore,
                libelle: 'Restaurer ce rôle',
                onPressed: () =>
                    _restaurer(context, x, x.role('${r['role']}')!)),
        ],
      ),
    ]);
  }
}

// --- Les gestes ---------------------------------------------------------------------------------------------------------------------------------

/// Une case à cocher du kit (16 × 16, rayon 4, navy-900 cochée), cliquable et lue par les lecteurs d'écran.
class _CaseDroit extends StatelessWidget {
  const _CaseDroit(
      {super.key,
      required this.valeur,
      required this.alChanger,
      required this.libelle});
  final bool valeur;
  final ValueChanged<bool> alChanger;
  final String libelle;

  @override
  Widget build(BuildContext context) => Semantics(
        checked: valeur,
        label: libelle,
        excludeSemantics: true,
        onTap: () => alChanger(!valeur),
        child: InkWell(
          onTap: () => alChanger(!valeur),
          child: Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
                color: valeur ? JetonsShell.navy900 : Colors.white,
                border: Border.all(
                    color: valeur ? JetonsShell.navy900 : JetonsShell.slate300),
                borderRadius: BorderRadius.circular(4)),
            child: valeur
                ? const Icon(LucideIcons.check, size: 12, color: Colors.white)
                : null,
          ),
        ),
      );
}

/// « Modifier les droits » : trois cases par module, la lecture seule déduite. L'état est tenu PAR CODE : les modules à plusieurs rangées (M1, M2, M12,
/// M13, CFG) restent synchrones (la maquette les laissait diverger à l'écran, le dernier clic gagnant à l'enregistrement — E595).
void _editerRole(BuildContext ctx, _Ctx x, RoleSec r) {
  final c = x.c;
  final etat = <String, CasesDroitsSec>{
    for (final mo in x.modules)
      '${mo['code']}': CasesDroitsSec.depuis(x.droit(r.id, '${mo['code']}')),
  };
  afficherModale<void>(ctx,
      titre: 'Droits du rôle « ${r.label} »',
      sousTitre:
          'Trois droits par module ; la lecture seule est la combinaison « voir sans agir ».',
      taille: TailleModale.xl,
      corps: StatefulBuilder(builder: (context, majEtat) {
        void maj(VoidCallback f) => majEtat(f);
        const tete = TextStyle(
            color: JetonsShell.slate500,
            fontSize: 12,
            height: 16 / 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6);
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const NoteSigh(
                  'RG-13 — le médical reste réservé au soignant habilité, le financier et le RH aux profils comptables et RH. Fermer un module le retire du méga-menu, de la recherche globale et de ses adresses : l’écran devient inatteignable, pas seulement invisible.',
                  ton: TonSigh.attention,
                  icone: LucideIcons.shieldAlert),
              const SizedBox(height: 12),
              Container(
                constraints: const BoxConstraints(maxHeight: 416),
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: JetonsShell.slate200)),
                child: SingleChildScrollView(
                  child: Table(
                    defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                    columnWidths: const {
                      0: FlexColumnWidth(3),
                      1: FixedColumnWidth(70),
                      2: FixedColumnWidth(70),
                      3: FixedColumnWidth(70),
                      4: FixedColumnWidth(110),
                    },
                    children: [
                      TableRow(
                          decoration: const BoxDecoration(
                              color: JetonsShell.slate50,
                              border: Border(
                                  bottom:
                                      BorderSide(color: JetonsShell.slate200))),
                          children: [
                            for (final (i, t) in [
                              'MODULE',
                              'VOIR',
                              'ÉDITER',
                              'ANNULER',
                              'LECTURE SEULE'
                            ].indexed)
                              Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  child: Align(
                                      alignment: i == 0
                                          ? Alignment.centerLeft
                                          : Alignment.center,
                                      child: Text(t, style: tete))),
                          ]),
                      for (final (i, mo) in x.modules.indexed)
                        () {
                          final e = etat['${mo['code']}']!;
                          Widget cel(Widget w,
                                  {Alignment a = Alignment.center}) =>
                              Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  child: Align(alignment: a, child: w));
                          return TableRow(
                              decoration: const BoxDecoration(
                                  border: Border(
                                      bottom: BorderSide(
                                          color: JetonsShell.slate100))),
                              children: [
                                cel(
                                    Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text('${mo['label']}',
                                              style: const TextStyle(
                                                  color: JetonsShell.slate800,
                                                  fontSize: 14,
                                                  height: 20 / 14,
                                                  fontWeight: FontWeight.w500)),
                                          Text(
                                              '${mo['domaine']} · ${mo['code']}',
                                              style: const TextStyle(
                                                  color: JetonsShell.slate400,
                                                  fontSize: 12,
                                                  height: 16 / 12)),
                                        ]),
                                    a: Alignment.centerLeft),
                                cel(_CaseDroit(
                                    key: Key('case:$i:voir'),
                                    libelle: 'Voir ${mo['code']}',
                                    valeur: e.voir,
                                    alChanger: (v) =>
                                        maj(() => e.cocherVoir(v)))),
                                cel(_CaseDroit(
                                    key: Key('case:$i:editer'),
                                    libelle: 'Éditer ${mo['code']}',
                                    valeur: e.editer,
                                    alChanger: (v) =>
                                        maj(() => e.cocherEditer(v)))),
                                cel(_CaseDroit(
                                    key: Key('case:$i:annuler'),
                                    libelle: 'Annuler ${mo['code']}',
                                    valeur: e.annuler,
                                    alChanger: (v) =>
                                        maj(() => e.cocherAnnuler(v)))),
                                cel(_CaseDroit(
                                    key: Key('case:$i:lecture'),
                                    libelle: 'Lecture seule ${mo['code']}',
                                    valeur: e.lecture,
                                    alChanger: (v) =>
                                        maj(() => e.cocherLecture(v)))),
                              ]);
                        }(),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                BoutonSigh(
                    libelle: 'Tout ouvrir',
                    icone: LucideIcons.checkCheck,
                    taille: TailleBouton.sm,
                    variante: VarianteBouton.secondaire,
                    onPressed: () => maj(() =>
                        secBasculerTout(etat.values, ModeToutSec.ouvrir))),
                BoutonSigh(
                    libelle: 'Tout en lecture seule',
                    icone: LucideIcons.eye,
                    taille: TailleBouton.sm,
                    variante: VarianteBouton.secondaire,
                    onPressed: () => maj(() => secBasculerTout(
                        etat.values, ModeToutSec.lectureSeule))),
                BoutonSigh(
                    libelle: 'Tout fermer',
                    icone: LucideIcons.x,
                    taille: TailleBouton.sm,
                    variante: VarianteBouton.secondaire,
                    onPressed: () => maj(() =>
                        secBasculerTout(etat.values, ModeToutSec.fermer))),
              ]),
            ]);
      }),
      pied: (fermer) => [
            BoutonSigh(
                libelle: 'Annuler',
                variante: VarianteBouton.secondaire,
                onPressed: fermer),
            BoutonSigh(
                libelle: 'Enregistrer les droits',
                icone: LucideIcons.save,
                onPressed: () {
                  // Le détail annoncé compte les RANGÉES du manifeste (`modules.filter`), comme la maquette.
                  final lignes = [
                    for (final mo in x.modules) etat['${mo['code']}']!
                  ];
                  final k = secCompteOuverts(lignes);
                  x.enregistrer(
                      r.id,
                      {
                        'droits': {
                          for (final e in etat.entries)
                            e.key: e.value.versFiche()
                        },
                        'statut': 'actif',
                        'definiLe': iso(c.aujourdhui),
                        'definiPar': c.utilisateur,
                      },
                      'Modification des droits RBAC');
                  fermer();
                  ToastsSigh.afficher(
                      ctx, 'Droits du rôle « ${r.label} » enregistrés.',
                      type: TypeToast.succes,
                      detail:
                          '${nombre(k.ouverts)} module(s) ouvert(s), dont ${nombre(k.figes)} en lecture seule.');
                }),
          ]);
}

/// « Régler écran par écran » : un écran l'emporte sur son module ; un écran non réglé le suit.
void _editerEcrans(BuildContext ctx, _Ctx x, RoleSec r) {
  final f = x.fiche(r.id);
  final codes = <String>[];
  final ecransParModule =
      <String, ({String label, List<List<String>> items})>{};
  for (final mo in x.modules) {
    final code = '${mo['code']}';
    if (!codes.contains(code)) {
      codes.add(code);
      ecransParModule[code] = (label: '${mo['label']}', items: []);
    }
    for (final e in (mo['ecrans'] as List)) {
      ecransParModule[code]!.items.add([for (final s in (e as List)) '$s']);
    }
  }
  final etat = <String, CasesDroitsSec>{};
  // Seuls les écrans dont une case a été touchée sont écrits : un écran non réglé suit son module.
  final modifies = <String>{};
  final choix = ControleurFormulaire([
    ChampDef(
        nom: 'module',
        libelle: 'Module',
        type: TypeChamp.select,
        col: ColChamp.plein,
        options: [
          for (final k in codes)
            OptionChamp(k, '$k — ${ecransParModule[k]!.label}')
        ]),
  ], {
    'module': codes.first
  });
  afficherModale<void>(ctx,
      titre: 'Droits par écran — « ${r.label} »',
      sousTitre: 'Un écran l’emporte sur son module',
      taille: TailleModale.xl,
      corps: ListenableBuilder(
          listenable: choix,
          builder: (context, _) => StatefulBuilder(builder: (context, majEtat) {
                final code = '${choix['module']}';
                final mod = ecransParModule[code]!;
                const tete = TextStyle(
                    color: JetonsShell.slate500,
                    fontSize: 12,
                    height: 16 / 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.6);
                return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const NoteSigh(
                          'Un écran non réglé suit son module — il ne faut pas déclarer cent quatre-vingts écrans pour en fermer quatre. Une case décochée ici l’emporte sur le module : c’est ce qui permet d’ouvrir M1 en lecture tout en fermant le dossier médical.',
                          ton: TonSigh.info,
                          icone: LucideIcons.listTree),
                      const SizedBox(height: 12),
                      FormulaireSigh(controleur: choix),
                      const SizedBox(height: 12),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 352),
                        decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: JetonsShell.slate200)),
                        child: SingleChildScrollView(
                          child: Table(
                            defaultVerticalAlignment:
                                TableCellVerticalAlignment.middle,
                            columnWidths: const {
                              0: FlexColumnWidth(3),
                              1: FixedColumnWidth(70),
                              2: FixedColumnWidth(70),
                              3: FixedColumnWidth(70),
                              4: FixedColumnWidth(130),
                            },
                            children: [
                              TableRow(
                                  decoration: const BoxDecoration(
                                      color: JetonsShell.slate50,
                                      border: Border(
                                          bottom: BorderSide(
                                              color: JetonsShell.slate200))),
                                  children: [
                                    for (final (i, t) in [
                                      'ÉCRAN',
                                      'VOIR',
                                      'ÉDITER',
                                      'ANNULER',
                                      'ORIGINE'
                                    ].indexed)
                                      Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 8),
                                          child: Align(
                                              alignment: i == 0
                                                  ? Alignment.centerLeft
                                                  : (i == 4
                                                      ? Alignment.centerRight
                                                      : Alignment.center),
                                              child: Text(t, style: tete))),
                                  ]),
                              for (final (i, it) in mod.items.indexed)
                                () {
                                  final id = it[0];
                                  final cases = etat.putIfAbsent(
                                      id,
                                      () => CasesDroitsSec.depuis(
                                          x.droitEcran(r.id, id, code)));
                                  final regle = (f?['droitsEcrans'] as Map?)
                                          ?.containsKey(id) ==
                                      true;
                                  Widget cel(Widget w,
                                          {Alignment a = Alignment.center}) =>
                                      Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 8),
                                          child: Align(alignment: a, child: w));
                                  return TableRow(
                                      decoration: const BoxDecoration(
                                          border: Border(
                                              bottom: BorderSide(
                                                  color:
                                                      JetonsShell.slate100))),
                                      children: [
                                        cel(
                                            Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(it[1],
                                                      style: const TextStyle(
                                                          color: JetonsShell
                                                              .slate800,
                                                          fontSize: 14,
                                                          height: 20 / 14)),
                                                  Text(id,
                                                      style: styleMono.copyWith(
                                                          color: JetonsShell
                                                              .slate400)),
                                                ]),
                                            a: Alignment.centerLeft),
                                        cel(_CaseDroit(
                                            key: Key('ecran:$i:voir'),
                                            libelle: 'Voir $id',
                                            valeur: cases.voir,
                                            alChanger: (v) => majEtat(() {
                                                  cases.cocherVoir(v);
                                                  modifies.add(id);
                                                }))),
                                        cel(_CaseDroit(
                                            key: Key('ecran:$i:editer'),
                                            libelle: 'Éditer $id',
                                            valeur: cases.editer,
                                            alChanger: (v) => majEtat(() {
                                                  cases.cocherEditer(v);
                                                  modifies.add(id);
                                                }))),
                                        cel(_CaseDroit(
                                            key: Key('ecran:$i:annuler'),
                                            libelle: 'Annuler $id',
                                            valeur: cases.annuler,
                                            alChanger: (v) => majEtat(() {
                                                  cases.cocherAnnuler(v);
                                                  modifies.add(id);
                                                }))),
                                        cel(
                                            regle
                                                ? const BadgeSigh('Réglé',
                                                    ton: TonSigh.navy)
                                                : const Text('suit le module',
                                                    style: TextStyle(
                                                        color: JetonsShell
                                                            .slate400,
                                                        fontSize: 12,
                                                        height: 16 / 12)),
                                            a: Alignment.centerRight),
                                      ]);
                                }(),
                            ],
                          ),
                        ),
                      ),
                    ]);
              })),
      pied: (fermer) => [
            BoutonSigh(
                libelle: 'Annuler',
                variante: VarianteBouton.secondaire,
                onPressed: fermer),
            BoutonSigh(
                libelle: 'Retirer tous les réglages d’écran',
                icone: LucideIcons.rotateCcw,
                variante: VarianteBouton.secondaire,
                onPressed: () {
                  x.enregistrer(r.id, {'droitsEcrans': <String, Object?>{}},
                      'Retrait des réglages d’écran');
                  fermer();
                  ToastsSigh.afficher(ctx, 'Réglages d’écran retirés.',
                      type: TypeToast.succes,
                      detail:
                          'Tous les écrans suivent de nouveau leur module.');
                }),
            BoutonSigh(
                libelle: 'Enregistrer',
                icone: LucideIcons.save,
                onPressed: () {
                  final existants = <String, Object?>{
                    ...((f?['droitsEcrans'] as Map?)?.cast<String, Object?>() ??
                        const {}),
                  };
                  for (final id in modifies) {
                    existants[id] = etat[id]!.versFiche();
                  }
                  x.enregistrer(
                      r.id,
                      {'droitsEcrans': existants, 'statut': 'actif'},
                      'Réglage des droits par écran');
                  fermer();
                  final fermes = existants.values
                      .where((v) => (v as Map)['voir'] != true)
                      .length;
                  ToastsSigh.afficher(ctx, 'Droits par écran enregistrés.',
                      type: TypeToast.succes,
                      detail:
                          '${nombre(existants.length)} écran(s) réglé(s), dont ${nombre(fermes)} fermé(s).');
                }),
          ]);
}

/// Création d'un rôle : il part de ZÉRO, tous les modules fermés nommément (les modules « tous les rôles » du manifeste s'ouvriraient sinon à un rôle
/// qu'on vient d'inventer), l'écran universel fermé lui aussi.
void _creerRole(BuildContext ctx, ContexteEcran c) {
  final x = _Ctx(c);
  final accueils = <List<String>>[
    for (final r in x.modules)
      for (final a in ((r['accueils'] as List?) ?? const []))
        [for (final s in (a as List)) '$s']
  ];
  final ctl = ControleurFormulaire([
    const ChampDef(
        nom: 'libelle',
        libelle: 'Intitulé du rôle',
        requis: true,
        col: ColChamp.plein),
    const ChampDef(
        nom: 'libelleCourt',
        libelle: 'Intitulé abrégé',
        aide: 'Affiché au bandeau, quand la place manque.'),
    const ChampDef(
        nom: 'id',
        libelle: 'Identifiant technique',
        requis: true,
        aide: 'Sans espace ni accent — il sert de clé dans les habilitations.'),
    ChampDef(
        nom: 'couleur',
        libelle: 'Couleur',
        type: TypeChamp.select,
        options: [
          for (final k in secCouleursRole) OptionChamp(k.valeur, k.libelle)
        ]),
    ChampDef(
        nom: 'accueil',
        libelle: 'Écran d’accueil',
        type: TypeChamp.select,
        requis: true,
        options: [for (final a in accueils) OptionChamp(a[0], a[1])]),
    const ChampDef(
        nom: 'motif',
        libelle: 'Raison d’être de ce rôle',
        type: TypeChamp.textarea,
        lignes: 2,
        col: ColChamp.plein),
  ], {
    'couleur': 'neutral',
    'accueil': 'dash-admin'
  });
  afficherModale<void>(ctx,
      titre: 'Nouveau rôle',
      taille: TailleModale.lg,
      corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const NoteSigh(
            'Le rôle est créé tous modules fermés. C’est délibéré : certains modules sont ouverts « à tous les rôles » au manifeste, ce qui a été écrit pour les rôles existants et non pour ceux qu’on inventera ensuite. Ouvrez-lui explicitement ce qu’il doit voir — module par module, puis écran par écran pour les exceptions.',
            ton: TonSigh.attention,
            icone: LucideIcons.shieldAlert),
        const SizedBox(height: 12),
        FormulaireSigh(controleur: ctl),
      ]),
      pied: (fermer) => [
            BoutonSigh(
                libelle: 'Annuler',
                variante: VarianteBouton.secondaire,
                onPressed: fermer),
            BoutonSigh(
                libelle: 'Créer le rôle',
                icone: LucideIcons.userPlus,
                onPressed: () {
                  final v = ctl.valider();
                  if (v == null) {
                    ToastsSigh.afficher(
                        ctx, 'Le formulaire comporte des erreurs.',
                        type: TypeToast.erreur);
                    return;
                  }
                  final nx = _Ctx(c);
                  final id = secIdentifiantRole('${v['id']}');
                  if (id.isEmpty) {
                    ToastsSigh.afficher(ctx, 'Identifiant technique invalide.',
                        type: TypeToast.erreur);
                    return;
                  }
                  if (nx.role(id) != null) {
                    ToastsSigh.afficher(ctx, 'Ce rôle existe déjà.',
                        type: TypeToast.erreur,
                        detail:
                            '${nx.role(id)!.label} porte déjà l’identifiant « $id ».');
                    return;
                  }
                  final z =
                      secZeroDroits(secCodesModules(nx.modules), nx.universels);
                  final libelle = '${v['libelle']}';
                  final fiche = {
                    'nouveau': true,
                    'statut': 'actif',
                    'libelle': libelle,
                    'libelleCourt': secVrai(v['libelleCourt'])
                        ? v['libelleCourt']
                        : libelle,
                    'libelleOrigine': libelle,
                    'couleur': v['couleur'],
                    'accueil': v['accueil'],
                    'motif': v['motif'],
                    'droits': z.droits,
                    'droitsEcrans': z.droitsEcrans,
                  };
                  // Upsert : un rôle archivé qu'on recrée reprend sa fiche plutôt que d'en poser une seconde.
                  final deja = nx.fiche(id);
                  if (deja != null) {
                    nx.m.collection('rbac').mettreAJour(deja['id'], fiche);
                    fermer();
                    ToastsSigh.afficher(ctx, 'Rôle « $libelle » rétabli.',
                        type: TypeToast.succes);
                    return;
                  }
                  nx.m.collection('rbac').inserer({
                    'role': id,
                    ...fiche,
                    'definiLe': iso(c.aujourdhui),
                    'definiPar': c.utilisateur,
                  }, prefixe: 'RBAC');
                  nx.m.journaliser('Création d’un rôle', 'M14', 'Rôle', id,
                      null, {'libelle': libelle});
                  fermer();
                  ToastsSigh.afficher(ctx, 'Rôle « $libelle » créé.',
                      type: TypeToast.succes,
                      duree: const Duration(seconds: 9),
                      detail: secDetailCreationRole(nx.modules.length));
                }),
          ]);
}

void _renommer(BuildContext ctx, _Ctx x, RoleSec r) {
  final ctl = ControleurFormulaire([
    ChampDef(
        nom: 'libelle',
        libelle: 'Intitulé du rôle',
        requis: true,
        aide: 'Intitulé d’origine : ${r.labelOrigine}'),
  ], {
    'libelle': r.label
  });
  afficherModale<void>(ctx,
      titre: 'Renommer le rôle',
      sousTitre: r.labelOrigine,
      taille: TailleModale.md,
      corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const NoteSigh(
            'Le nouvel intitulé s’applique partout — méga-menu, bandeau de session, états imprimés, journal d’audit. Les habilitations ne changent pas : renommer n’est pas redéfinir.'),
        const SizedBox(height: 12),
        FormulaireSigh(controleur: ctl),
      ]),
      pied: (fermer) => [
            BoutonSigh(
                libelle: 'Annuler',
                variante: VarianteBouton.secondaire,
                onPressed: fermer),
            BoutonSigh(
                libelle: 'Renommer',
                icone: LucideIcons.save,
                onPressed: () {
                  final v = ctl.valider();
                  if (v == null) {
                    ToastsSigh.afficher(
                        ctx, 'Le formulaire comporte des erreurs.',
                        type: TypeToast.erreur);
                    return;
                  }
                  final annuler = x.enregistrer(
                      r.id,
                      {'libelle': v['libelle'], 'statut': 'actif'},
                      'Renommage de rôle');
                  fermer();
                  ToastsSigh.afficher(ctx, 'Rôle renommé.',
                      type: TypeToast.succes,
                      detail: '${r.label} → ${v['libelle']}',
                      annuler: annuler);
                }),
          ]);
}

Future<void> _archiver(BuildContext ctx, _Ctx x, RoleSec r) async {
  final c = x.c;
  final comptes = x.comptes(r.id);
  // Le rôle de la session en cours ne s'archive pas : l'administrateur se retirerait la matrice sous les pieds.
  if (c.role == r.id) {
    ToastsSigh.afficher(
        ctx, 'Impossible d’archiver le rôle de la session en cours.',
        type: TypeToast.erreur,
        detail: 'Se connecter avec un autre profil pour procéder.');
    return;
  }
  final motif = await confirmerAvecMotif(ctx,
      titre: 'Archiver le rôle « ${r.label} » ?',
      message: comptes.isNotEmpty
          ? '${nombre(comptes.length)} compte(s) sont rattachés à ce rôle. Ils ne pourront plus ouvrir de session : la connexion sera refusée par une modale d’échec et chaque tentative vous sera signalée sur cet écran.\n\nConformément à RG-14, le rôle n’est pas supprimé — il reste restaurable, avec ses habilitations.'
          : 'Aucun compte n’est rattaché à ce rôle. L’archivage reste logique (RG-14) et se défait.',
      libelleOk: 'Archiver le rôle',
      dangereux: true);
  if (motif == null || !ctx.mounted) return;
  final annuler = x.enregistrer(
      r.id,
      {
        'statut': 'archive',
        'archiveLe': iso(c.aujourdhui),
        'archivePar': c.utilisateur,
        'motifArchivage': motif,
      },
      'Archivage de rôle');
  ToastsSigh.afficher(ctx, 'Rôle archivé.',
      type: TypeToast.succes,
      detail: comptes.isNotEmpty
          ? '${nombre(comptes.length)} compte(s) désormais bloqué(s).'
          : null,
      annuler: annuler,
      messageAnnulation: 'Archivage annulé — le rôle est de nouveau actif.');
}

void _restaurer(BuildContext ctx, _Ctx x, RoleSec r) {
  final c = x.c;
  x.enregistrer(
      r.id,
      {
        'statut': 'actif',
        'restaureLe': iso(c.aujourdhui),
        'restaurePar': c.utilisateur
      },
      'Restauration de rôle');
  ToastsSigh.afficher(ctx, 'Rôle « ${r.label} » restauré.',
      type: TypeToast.succes,
      detail: 'Ses comptes peuvent de nouveau se connecter.');
}

void _imprimerMatrice(BuildContext ctx, _Ctx x) {
  final c = x.c;
  final lignes = <Map<String, Object?>>[
    for (final r in x.actifs)
      () {
        final ouverts = [
          for (final mo in x.modules)
            if (x.droit(r.id, '${mo['code']}').voir) '${mo['code']}'
        ];
        final figes = [
          for (final mo in x.modules)
            if (x.droit(r.id, '${mo['code']}').voir &&
                x.droit(r.id, '${mo['code']}').lectureSeule)
              '${mo['code']}'
        ];
        return {
          'role': r.label,
          'comptes': nombre(x.comptes(r.id).length),
          'modules': ouverts.isEmpty ? '—' : ouverts.join(', '),
          'lecture': figes.isEmpty ? '—' : figes.join(', '),
        };
      }()
  ];
  afficherApercu(
      ctx,
      PieceA4(
        titre: 'Matrice des droits d’accès (RBAC)',
        sousTitre:
            'Politique de sécurité — situation au ${dateFR(c.aujourdhui)}',
        reference: referenceImpression(c),
        utilisateur: c.utilisateur,
        edite: c.aujourdhui,
        cartouche: [
          ('Rôles actifs', nombre(x.actifs.length)),
          ('Rôles archivés', nombre(x.archives.length)),
          ('Modules protégés', nombre(x.modules.length)),
          (
            'Comptes utilisateurs',
            nombre(x.m.collection('utilisateurs').actives.length)
          ),
          ('Date d’édition', dateFR(c.aujourdhui)),
        ],
        blocs: [
          BlocTableau(TableauEtat(colonnes: [
            ColonneEtat(libelle: 'Rôle', valeur: (r) => '${r['role']}'),
            ColonneEtat(
                libelle: 'Comptes',
                droite: true,
                valeur: (r) => '${r['comptes']}'),
            ColonneEtat(
                libelle: 'Modules accessibles',
                valeur: (r) => '${r['modules']}'),
            ColonneEtat(
                libelle: 'Dont lecture seule',
                valeur: (r) => '${r['lecture']}'),
          ], lignes: lignes)),
          const BlocTexte(
              'Conformément à la règle RG-13, l’accès aux données médicales est réservé au personnel soignant habilité, et l’accès aux données financières et de ressources humaines aux profils comptables et RH habilités. Conformément à RG-14, un rôle retiré est archivé et non supprimé. Toute dérogation doit être motivée et tracée.',
              italique: true),
        ],
        signatures: const [
          Signature('L’Administrateur système'),
          Signature('La Directrice Administrative', nom: 'TAKI Alimatou'),
          Signature('Le Directeur Médical', nom: 'BASSONGUI Chabi Séko'),
        ],
      ));
}
