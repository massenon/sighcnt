import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/donnees_navigation.dart';
import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../donnees/organigramme_poste.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m14/commun_m14.dart';
import 'cfa_commun.dart';

/// `cfg-organisation` — « Organisation & organigramme » : deux référentiels administrables. Les SECTEURS de la NS 145/08/DA/CNT/2026 donnent la maille
/// réelle des habilitations ; l'ORGANIGRAMME pilote la matrice RBAC (chaque poste porte un rôle). RG-14 — retirer un secteur ou un poste l'archive.
class EcranOrganisation extends StatelessWidget with EcranMaquette {
  const EcranOrganisation({super.key});
  @override
  String get titre => 'Organisation & organigramme';
  @override
  String get description => 'Secteurs de la clinique, structure hiérarchique et rôles qui en découlent.';
  @override
  String get regle =>
      'Deux référentiels administrables. Les secteurs (NS 145/08/DA/CNT/2026) donnent la maille réelle des habilitations et de l’évaluation des services. L’organigramme pilote la matrice RBAC : chaque poste porte un rôle qui détermine son périmètre d’accès. RG-14 — retirer un secteur ou un poste l’archive : rien n’est supprimé, tout se restaure.';

  @override
  List<Widget> actionsEntete(BuildContext context) {
    final c = ContexteEcran.of(context);
    return [
      BoutonSigh(libelle: 'Personnel', icone: LucideIcons.users, variante: VarianteBouton.secondaire, onPressed: () => c.aller('m10-personnel')),
      BoutonSigh(libelle: 'Rôles & permissions', icone: LucideIcons.keyRound, variante: VarianteBouton.secondaire, onPressed: () => c.aller('m14-roles')),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final secteurs = c.magasin.collection('secteurs');
    final postes = c.magasin.collection('postes');
    return ListenableBuilder(
        listenable: Listenable.merge([secteurs, postes]),
        builder: (ctx, _) {
          final nbRoles = rolesDe(c.magasin).length;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            cfaLectureSeule(c),
            cfaKpis(cfaKpisOrganisation(
                secteurs: secteurs.actives.length, postes: postes.actives.length, effectif: cfaEffectifTotal(cfaArbre(postes.actives)), roles: nbRoles)),
            const SizedBox(height: 16),
            OngletsSigh(onglets: [
              OngletDef(id: 'secteurs', libelle: 'Secteurs (NS 145)', compte: secteurs.actives.length, construire: (_) => const _OngletSecteurs()),
              OngletDef(id: 'organigramme', libelle: 'Organigramme', compte: postes.actives.length, construire: (_) => const _OngletOrganigramme()),
              OngletDef(id: 'roles', libelle: 'Poste → rôle → accès', construire: (_) => const _OngletRoles()),
            ]),
          ]);
        });
  }
}

List<OptionChamp> _optionsRoles(Magasin m) => [for (final r in rolesDe(m)) OptionChamp(r.id, r.label)];

Widget _badgeRole(Magasin m, Object? role) => BadgeSigh(libelleRole(m, role), ton: TonSigh.navy);

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Onglet « Secteurs (NS 145) »
// ---------------------------------------------------------------------------------------------------------------------------------------------

class _OngletSecteurs extends StatelessWidget {
  const _OngletSecteurs();

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('secteurs');
    return ListenableBuilder(
        listenable: col,
        builder: (ctx, _) {
          final rows = trierPar(col.actives, (s) => s['ordre']);
          return cfaPile([
            NoteSigh(
                '${CfaNs145.reference} — ${CfaNs145.objet}, signée le ${dateFR(DateTime.parse(CfaNs145.dateSignature))} par ${CfaNs145.signataire}, avec effet au ${dateFR(DateTime.parse(CfaNs145.dateEffet))}. Une note ultérieure se saisit ici : le référentiel est versionné par sa source, pas par le code.',
                icone: LucideIcons.fileCheck2),
            CfaTableau(
              collection: 'secteurs',
              entite: 'Secteur',
              titreCreation: 'Nouveau secteur',
              prefixeId: 'SEC',
              taillePage: 20,
              triInitial: 'ordre',
              nomExport: 'secteurs',
              colonnes: [
                ColonneTableau(cle: 'code', libelle: 'Code', sansCoupure: true, texte: (s) => '${s['code'] ?? ''}', rendu: (_, s) => cfaCode(s['code'])),
                ColonneTableau(cle: 'libelle', libelle: 'Secteur', texte: (s) => '${s['libelle'] ?? ''}', rendu: (_, s) => cfaGras('${s['libelle'] ?? ''}')),
                ColonneTableau(
                    cle: 'responsable',
                    libelle: 'Responsable',
                    texte: (s) => '${s['responsable'] ?? ''} ${s['qualification'] ?? ''}'.trim(),
                    rendu: (_, s) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                          Text(cfaOuTiret(s['responsable']), style: const TextStyle(fontSize: 14, height: 20 / 14, color: JetonsShell.slate700)),
                          Text('${s['qualification'] ?? ''}', style: const TextStyle(fontSize: 12, height: 16 / 12, color: JetonsShell.slate400)),
                        ])),
                ColonneTableau(
                    cle: 'adjoint',
                    libelle: 'Adjoint',
                    texte: (s) => cfaVrai(s['adjoint']) ? '${s['adjoint']}' : 'non désigné',
                    rendu: (_, s) => cfaVrai(s['adjoint'])
                        ? Text('${s['adjoint']}', style: const TextStyle(fontSize: 14, height: 20 / 14, color: JetonsShell.slate700))
                        : const Text('non désigné', style: TextStyle(fontSize: 12, height: 16 / 12, color: JetonsShell.slate300))),
                ColonneTableau(cle: 'role', libelle: 'Rôle RBAC', texte: (s) => libelleRole(c.magasin, s['role']), rendu: (_, s) => _badgeRole(c.magasin, s['role'])),
              ],
              champs: (e) => [
                const ChampDef(nom: 'libelle', libelle: 'Secteur', requis: true, col: ColChamp.plein),
                const ChampDef(nom: 'code', libelle: 'Code', aide: 'Trois lettres, laisser vide pour une attribution automatique.'),
                ChampDef(
                    nom: 'role',
                    libelle: 'Rôle RBAC rattaché',
                    type: TypeChamp.select,
                    requis: true,
                    options: _optionsRoles(c.magasin),
                    aide: 'Détermine ce que les agents de ce secteur peuvent voir et faire.'),
                const ChampDef(nom: 'responsable', libelle: 'Responsable', col: ColChamp.plein),
                const ChampDef(nom: 'adjoint', libelle: 'Responsable adjoint', col: ColChamp.plein),
                const ChampDef(nom: 'qualification', libelle: 'Qualification'),
                const ChampDef(nom: 'source', libelle: 'Note de service d’origine', col: ColChamp.plein),
              ],
              valeursInitiales: () => {'role': 'agentadmin', 'source': 'Décision de la Direction'},
              fiche: (s, e) => e == null ? cfaFicheSecteur(s, col.toutes.length) : {...s},
              actions: [
                BoutonSigh(
                    libelle: 'Imprimer la répartition',
                    icone: LucideIcons.printer,
                    variante: VarianteBouton.secondaire,
                    taille: TailleBouton.sm,
                    onPressed: () => cfaImprimer(context,
                        titre: 'Répartition des secteurs de la clinique',
                        sousTitre: CfaNs145.reference,
                        cartouche: [
                          ('Objet', CfaNs145.objet),
                          ('Secteurs', nombre(rows.length)),
                          ('Date d’effet', dateFR(DateTime.parse(CfaNs145.dateEffet))),
                          ('Date d’édition', dateFR(c.aujourdhui)),
                        ],
                        blocs: [
                          BlocTableau(TableauEtat(colonnes: [
                            ColonneEtat(libelle: 'N°', droite: true, valeur: (l) => l['ordre']),
                            ColonneEtat(libelle: 'Secteur', valeur: (l) => l['libelle']),
                            ColonneEtat(libelle: 'Responsable', valeur: (l) => cfaOuTiret(l['responsable'])),
                            ColonneEtat(libelle: 'Responsable adjoint', valeur: (l) => cfaOuTiret(l['adjoint'])),
                            ColonneEtat(libelle: 'Qualification', valeur: (l) => cfaOuTiret(l['qualification'])),
                          ], lignes: rows)),
                        ],
                        signatures: const [Signature('La Directrice Administrative', nom: 'TAKI Alimatou épse BASSONGUI')])),
              ],
            ),
            cfaSource(CfaNs145.source),
          ], espace: 12);
        });
  }
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Onglet « Organigramme »
// ---------------------------------------------------------------------------------------------------------------------------------------------

class _OngletOrganigramme extends StatelessWidget {
  const _OngletOrganigramme();

  Widget _noeud(Magasin m, OrgNoeud n, int niveau) {
    final carte = Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
          color: niveau == 0 ? JetonsShell.navy50 : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: niveau == 0 ? JetonsShell.navy300 : JetonsShell.slate200)),
      child: Row(children: [
        Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(color: niveau == 0 ? JetonsShell.navy900 : JetonsShell.slate100, borderRadius: BorderRadius.circular(8)),
            child: Icon(niveau == 0 ? LucideIcons.crown : LucideIcons.user, size: 14, color: niveau == 0 ? Colors.white : JetonsShell.slate500)),
        const SizedBox(width: 8),
        Flexible(child: Text(n.poste, style: const TextStyle(fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600, color: JetonsShell.slate800))),
        const SizedBox(width: 8),
        BadgeSigh('(${(cfaNombre(n.fiche['effectif']) ?? 0).toString().padLeft(2, '0')})'),
        if (cfaVrai(n.fiche['titulaire'])) ...[
          const SizedBox(width: 8),
          Flexible(
              child: Text('${n.fiche['titulaire']}${_titre(n.titreAgent)}${cfaVrai(n.fiche['chef']) ? ' — chef de service' : ''}',
                  style: const TextStyle(fontSize: 12, height: 16 / 12, color: JetonsShell.slate500))),
        ],
        if (cfaVrai(n.fiche['role'])) ...[const Spacer(), _badgeRole(m, n.fiche['role'])],
      ]),
    );
    return Container(
        padding: niveau > 0 ? const EdgeInsets.only(left: 16) : EdgeInsets.zero,
        margin: niveau > 0 ? const EdgeInsets.only(left: 24) : EdgeInsets.zero,
        decoration: niveau > 0 ? const BoxDecoration(border: Border(left: BorderSide(color: JetonsShell.slate200))) : null,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [carte, for (final e in n.enfants) _noeud(m, e, niveau + 1)]));
  }

  static String _titre(String? t) => t == null || t.isEmpty ? '' : ' ($t)';

  /// Les champs d'un poste. À la modification, le rattachement ne propose ni le poste lui-même ni ses rattachés (cycle), et le titre de l'agent s'ajoute.
  static List<ChampDef> champsPoste(Magasin m, Fiche? e) {
    final plats = m.collection('postes').actives;
    final interdits = e == null ? <String>[] : orgDescendants('${e['id']}', plats);
    final autres = trierPar([for (final p in plats) if (e == null || (p['id'] != e['id'] && !interdits.contains('${p['id']}'))) p], (p) => p['poste']);
    return [
      const ChampDef(nom: 'poste', libelle: 'Intitulé du poste', requis: true, col: ColChamp.plein),
      ChampDef(
          nom: 'parentId',
          libelle: 'Rattaché à',
          type: TypeChamp.select,
          options: [const OptionChamp('', '— Sommet de l’organigramme —'), for (final p in autres) OptionChamp('${p['id']}', '${p['poste']}')],
          aide: 'Déplacer un poste ici le réaffecte, lui et les postes qu’il porte. Un poste ne se rattache ni à lui-même ni à l’un de ses rattachés.'),
      const ChampDef(nom: 'effectif', libelle: 'Effectif', type: TypeChamp.nombre, requis: true),
      const ChampDef(
          nom: 'titulaire',
          libelle: 'Titulaire / chef de service',
          col: ColChamp.plein,
          aide: 'Une autre personne est affectée au poste : renommer le titulaire ici, la feuille imprimée suit.'),
      ChampDef(nom: 'role', libelle: 'Rôle RBAC', type: TypeChamp.select, requis: true, options: _optionsRoles(m)),
      const ChampDef(nom: 'chef', libelle: 'Chef de service (C/S)', type: TypeChamp.case_),
      if (e != null)
        const ChampDef(
            nom: 'titreAgent',
            libelle: 'Titre du titulaire dans l’organigramme',
            col: ColChamp.plein,
            aide: 'Porté par l’AGENT, pas par le poste (par exemple « SG » pour le surveillant général, qui est un infirmier). Il ne change aucun droit. Vide : aucun titre.'),
    ];
  }

  /// Un refus du domaine se DIT : motif et geste de correction, jamais un échec muet.
  static void _dire(BuildContext ctx, RefusRh r) => ToastsSigh.afficher(ctx, r.motif, type: TypeToast.erreur, detail: r.geste);

  static void _modifier(BuildContext ctx, OrganigrammePoste org, Fiche p) {
    final m = org.m;
    final ctl = ControleurFormulaire(champsPoste(m, p), {
      for (final e in p.entries) e.key: e.value is num ? '${e.value}' : e.value,
      'titreAgent': org.titreDe(p) ?? '',
    });
    afficherModale<void>(ctx,
        titre: 'Modifier le poste',
        sousTitre: '${p['poste']}',
        taille: TailleModale.lg,
        corps: FormulaireSigh(controleur: ctl),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: 'Enregistrer',
                  icone: LucideIcons.save,
                  onPressed: () {
                    final saisie = ctl.valider();
                    if (saisie == null) {
                      ToastsSigh.afficher(ctx, 'Le formulaire comporte des erreurs.', type: TypeToast.erreur);
                      return;
                    }
                    final r = org.modifier('${p['id']}', saisie);
                    if (r.refus != null) {
                      _dire(ctx, r.refus!);
                      return;
                    }
                    fermer();
                    if (r.inchange) {
                      ToastsSigh.afficher(ctx, 'Aucune modification.', type: TypeToast.info);
                    } else {
                      ToastsSigh.afficher(ctx, 'Modifications enregistrées.', type: TypeToast.succes, annuler: r.annuler);
                    }
                  }),
            ]);
  }

  static void _archiver(BuildContext ctx, OrganigrammePoste org, Fiche p) async {
    final motif = await confirmerAvecMotif(ctx,
        titre: 'Archiver ce poste ?',
        message: 'Archivage logique (RG-14) : le poste reste consultable à la corbeille et l’opération est annulable.',
        libelleOk: 'Archiver',
        dangereux: true);
    if (motif == null || !ctx.mounted) return;
    final r = org.archiver('${p['id']}');
    if (r.refus != null) {
      _dire(ctx, r.refus!);
      return;
    }
    ToastsSigh.afficher(ctx, 'Poste archivé.', type: TypeToast.succes, annuler: r.annuler, messageAnnulation: 'Archivage annulé.');
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('postes');
    final pers = c.magasin.collection('personnel');
    final org = OrganigrammePoste(c.magasin,
        droitEditer: c.droit.editer,
        droitAnnuler: c.droit.annuler,
        rolesConnus: {for (final r in rolesDe(c.magasin)) r.id},
        maintenant: () => c.aujourdhui,
        auteur: () => acteur(c).nom);
    return ListenableBuilder(
        listenable: Listenable.merge([col, pers]),
        builder: (ctx, _) {
          final plats = col.actives;
          final racines = org.arbre();
          String nomDe(Object? id) => plats.where((p) => p['id'] == id).map((p) => '${p['poste']}').firstOrNull ?? '—';
          String titulaireTexte(Fiche p) => '${p['titulaire']}${_titre(org.titreDe(p))}${cfaVrai(p['chef']) ? ' — chef de service' : ''}';
          // L'IMPRESSION REPRODUIT LA MISE EN PAGE DE L'ORGANIGRAMME PAPIER (A4 paysage, boîtes et connecteurs) : le contenu vient de la collection des postes, jamais d'un texte
          // en dur ; ce qui s'y corrige (intitulé, effectif, titulaire, titre de l'agent, rattachement) se retrouve sur la feuille. Aucune étoile (O5).
          void imprimer() {
            final mise = orgMiseEnPage(racines);
            afficherApercu(
                ctx,
                PieceA4(
                    titre: 'ORGANIGRAMME DE LA CLINIQUE NASSIERA TOO',
                    paysage: true,
                    lieuDate: false,
                    blocs: [
                      mise == null ? const BlocTexte(orgTexteAucunPoste, italique: true) : BlocOrganigramme(mise),
                      const BlocTexte('Effectif entre parenthèses. C/S : chef de service.'),
                    ],
                    reference: PieceA4.reference_(c.aujourdhui, ImpressionPoste.prochainNumero()),
                    utilisateur: acteur(c).nom,
                    edite: c.aujourdhui));
          }

          return cfaPile([
            const NoteSigh(
                'L’organigramme imprimé suit la collection des postes de cet écran : un intitulé, un effectif, un titulaire, un titre ou un rattachement corrigé ici se retrouve sur la feuille. Il part de l’organigramme papier de la clinique mais n’est pas figé : réaffecter un poste, renommer son titulaire quand une autre personne est affectée, poser le titre d’un agent (« SG » pour le surveillant général, qui est un infirmier : le titre est porté par l’agent, pas par le poste) ou archiver un poste se fait ici, et chaque geste est journalisé. Aucune étoile n’est tracée.',
                icone: LucideIcons.printer),
            CarteSigh(
                titre: 'Organigramme de la Clinique NASSIERA TOO',
                actions: [BoutonSigh(libelle: 'Imprimer l’organigramme', icone: LucideIcons.printer, variante: VarianteBouton.secondaire, taille: TailleBouton.sm, onPressed: imprimer)],
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (final r in racines) _noeud(c.magasin, r, 0)])),
            CfaTableau(
              collection: 'postes',
              titre: 'Postes — création, réaffectation et archivage',
              entite: 'Poste',
              titreCreation: 'Nouveau poste ou département',
              prefixeId: 'PST',
              taillePage: 20,
              nomExport: 'postes',
              archivable: false,
              modifiable: false,
              colonnes: [
                ColonneTableau(cle: 'poste', libelle: 'Poste', texte: (p) => '${p['poste'] ?? ''}', rendu: (_, p) => cfaGras('${p['poste'] ?? ''}')),
                ColonneTableau(
                    cle: 'parentId',
                    libelle: 'Rattaché à',
                    texte: (p) => nomDe(p['parentId']),
                    rendu: (_, p) => cfaVrai(p['parentId'])
                        ? Text(nomDe(p['parentId']), style: const TextStyle(fontSize: 14, height: 20 / 14, color: JetonsShell.slate600))
                        : const BadgeSigh('Sommet', ton: TonSigh.navy)),
                const ColonneTableau(cle: 'effectif', libelle: 'Effectif', droite: true),
                ColonneTableau(
                    cle: 'titulaire',
                    libelle: 'Titulaire',
                    texte: (p) => cfaVrai(p['titulaire']) ? titulaireTexte(p) : 'vacant',
                    rendu: (_, p) => cfaVrai(p['titulaire'])
                        ? Text(titulaireTexte(p), style: const TextStyle(fontSize: 14, height: 20 / 14, color: JetonsShell.slate700))
                        : const Text('vacant', style: TextStyle(fontSize: 12, height: 16 / 12, color: JetonsShell.slate300))),
                ColonneTableau(cle: 'role', libelle: 'Rôle RBAC', texte: (p) => libelleRole(c.magasin, p['role']), rendu: (_, p) => _badgeRole(c.magasin, p['role'])),
              ],
              champs: (e) => champsPoste(c.magasin, e),
              valeursInitiales: () => {'effectif': '1', 'role': 'agentadmin'},
              // Le moteur refuse en nommant (rattachement à un poste archivé, effectif non entier…) : rien n'est écrit.
              avant: (ctx2, saisie, existante) {
                final r = org.controler(null, saisie);
                if (r != null) {
                  _dire(ctx2, r);
                  return false;
                }
                return true;
              },
              fiche: (s, e) => cfaFichePoste(s),
              // LES GESTES SUR UN POSTE PASSENT PAR LE MOTEUR : réaffecter, renommer le titulaire, poser le titre de l'agent et archiver sont contrôlés (cycle, parent archivé,
              // agent introuvable, poste qui porte encore des postes), refusés en le nommant, et journalisés. Une commande dont le droit manque est ABSENTE.
              actionsLigneSup: (ctx2, f) => [
                if (c.droit.editer) BoutonIcone(icone: LucideIcons.pencil, libelle: 'Modifier', onPressed: () => _modifier(ctx2, org, f)),
                if (c.droit.annuler) BoutonIcone(icone: LucideIcons.archive, libelle: 'Archiver', onPressed: () => _archiver(ctx2, org, f)),
              ],
            ),
            cfaSource('Organigramme de la Clinique NASSIERA TOO — document de cadrage, désormais administrable.'),
          ], espace: 12);
        });
  }
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Onglet « Poste → rôle → accès » (calculé : lecture seule)
// ---------------------------------------------------------------------------------------------------------------------------------------------

class _OngletRoles extends StatelessWidget {
  const _OngletRoles();

  @override
  Widget build(BuildContext context) {
    final nav = cfaNavigationChargee;
    if (nav != null) return _corps(context, nav);
    return FutureBuilder<DonneesNavigation>(
        future: cfaNavigation(),
        builder: (ctx, snap) => snap.hasData ? _corps(ctx, snap.data!) : const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())));
  }

  Widget _corps(BuildContext context, DonneesNavigation nav) {
    final c = ContexteEcran.of(context);
    final plats = c.magasin.collection('postes').actives;
    final memo = <String, List<String>>{};
    // DROITS À CHAUD (A4) : la matrice en force est l'engendrée superposée aux fiches `rbac` et `modulesActifs`, calculée UNE fois pour les 16 postes.
    final vive = nav.aChaud(c.magasin);
    List<String> modules(Object? role) => memo.putIfAbsent('$role', () => cfaModulesDuRole(c.magasin, vive, '$role'));
    final lignes = [
      for (final p in plats) {'poste': p['poste'], 'effectif': p['effectif'], 'titulaire': cfaOuTiret(p['titulaire']), 'role': p['role']}
    ];
    return cfaPile([
      const NoteSigh(
          'État calculé — lecture seule. Cette correspondance est calculée depuis l’organigramme et la matrice RBAC. Pour la modifier, changer le rôle du poste dans l’onglet Organigramme, ou la matrice dans Rôles & permissions.',
          ton: TonSigh.neutre,
          icone: LucideIcons.lock),
      TableauSigh(
        lignes: lignes,
        taillePage: 20,
        nomExport: 'organigramme-rbac',
        colonnes: [
          const ColonneTableau(cle: 'poste', libelle: 'Poste'),
          const ColonneTableau(cle: 'effectif', libelle: 'Effectif', droite: true),
          const ColonneTableau(cle: 'titulaire', libelle: 'Titulaire / chef de service'),
          ColonneTableau(cle: 'role', libelle: 'Rôle RBAC', texte: (l) => libelleRole(c.magasin, l['role']), rendu: (_, l) => _badgeRole(c.magasin, l['role'])),
          ColonneTableau(
              cle: 'modules',
              libelle: 'Modules accessibles',
              texte: (l) => modules(l['role']).join(', '),
              rendu: (_, l) => Wrap(spacing: 4, runSpacing: 4, children: [for (final m in modules(l['role'])) BadgeSigh(m)])),
        ],
      ),
    ], espace: 12);
  }
}
