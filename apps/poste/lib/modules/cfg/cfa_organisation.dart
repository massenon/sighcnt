import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/donnees_navigation.dart';
import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
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

  Widget _noeud(Magasin m, CfaNoeud n, int niveau) {
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
        BadgeSigh('(${n.effectif.toString().padLeft(2, '0')})'),
        if (cfaVrai(n.fiche['titulaire'])) ...[
          const SizedBox(width: 8),
          Flexible(
              child: Text('${n.fiche['titulaire']}${cfaVrai(n.fiche['chef']) ? ' — chef de service' : ''}',
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

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('postes');
    return ListenableBuilder(
        listenable: col,
        builder: (ctx, _) {
          final plats = col.actives;
          final racines = cfaArbre(plats);
          String nomDe(Object? id) => plats.where((p) => p['id'] == id).map((p) => '${p['poste']}').firstOrNull ?? '—';
          void imprimer() => cfaImprimer(context,
              titre: 'Organigramme de la Clinique NASSIERA TOO',
              sousTitre: 'Structure organisationnelle et correspondance des rôles',
              cartouche: [
                ('Effectif total', '${nombre(cfaEffectifTotal(racines))} agents'),
                ('Postes distincts', nombre(plats.length)),
                ('Rôles définis', nombre(rolesDe(c.magasin).length)),
                ('Date d’édition', dateFR(c.aujourdhui)),
              ],
              blocs: [
                BlocTableau(TableauEtat(colonnes: [
                  ColonneEtat(libelle: 'Poste', valeur: (l) => l['poste']),
                  ColonneEtat(libelle: 'Rattaché à', valeur: (l) => nomDe(l['parentId'])),
                  ColonneEtat(libelle: 'Effectif', droite: true, valeur: (l) => l['effectif']),
                  ColonneEtat(libelle: 'Titulaire / chef de service', valeur: (l) => cfaOuTiret(l['titulaire'])),
                  ColonneEtat(libelle: 'Rôle dans le système', valeur: (l) => libelleRole(c.magasin, l['role'])),
                ], lignes: plats)),
              ],
              signatures: const [Signature('La Directrice Administrative', nom: 'TAKI Alimatou'), cfaSignDm]);
          return cfaPile([
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
                    texte: (p) => cfaVrai(p['titulaire']) ? '${p['titulaire']}${cfaVrai(p['chef']) ? ' — chef de service' : ''}' : 'vacant',
                    rendu: (_, p) => cfaVrai(p['titulaire'])
                        ? Text('${p['titulaire']}${cfaVrai(p['chef']) ? ' — chef de service' : ''}', style: const TextStyle(fontSize: 14, height: 20 / 14, color: JetonsShell.slate700))
                        : const Text('vacant', style: TextStyle(fontSize: 12, height: 16 / 12, color: JetonsShell.slate300))),
                ColonneTableau(cle: 'role', libelle: 'Rôle RBAC', texte: (p) => libelleRole(c.magasin, p['role']), rendu: (_, p) => _badgeRole(c.magasin, p['role'])),
              ],
              champs: (e) {
                final autres = trierPar([for (final p in plats) if (e == null || p['id'] != e['id']) p], (p) => p['poste']);
                return [
                  const ChampDef(nom: 'poste', libelle: 'Intitulé du poste', requis: true, col: ColChamp.plein),
                  ChampDef(
                      nom: 'parentId',
                      libelle: 'Rattaché à',
                      type: TypeChamp.select,
                      options: [const OptionChamp('', '— Sommet de l’organigramme —'), for (final p in autres) OptionChamp('${p['id']}', '${p['poste']}')],
                      aide: 'Déplacer un poste ici le réaffecte, lui et les postes qu’il porte.'),
                  const ChampDef(nom: 'effectif', libelle: 'Effectif', type: TypeChamp.nombre, requis: true),
                  const ChampDef(nom: 'titulaire', libelle: 'Titulaire / chef de service', col: ColChamp.plein),
                  ChampDef(nom: 'role', libelle: 'Rôle RBAC', type: TypeChamp.select, requis: true, options: _optionsRoles(c.magasin)),
                  const ChampDef(nom: 'chef', libelle: 'Chef de service', type: TypeChamp.case_),
                ];
              },
              valeursInitiales: () => {'effectif': '1', 'role': 'agentadmin'},
              fiche: (s, e) => cfaFichePoste(s),
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
    List<String> modules(Object? role) => memo.putIfAbsent('$role', () => cfaModulesDuRole(c.magasin, nav, '$role'));
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
