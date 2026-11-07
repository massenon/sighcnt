import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../core/donnees_navigation.dart';
import '../core/icones.dart';
import '../core/jetons_shell.dart';
import '../donnees/magasin.dart';
import '../kit/modale.dart';

/// Un résultat de la recherche globale : où il mène (écran, et onglet si c'est une rubrique).
class ResultatRecherche {
  const ResultatRecherche({required this.label, required this.detail, required this.icone, required this.ecran, this.onglet});
  final String label, detail, icone, ecran;
  final String? onglet;
}

class GroupeRecherche {
  const GroupeRecherche(this.groupe, this.resultats);
  final String groupe;
  final List<ResultatRecherche> resultats;
}

/// Un écran est-il ouvert à ce rôle ? Une page d'accueil de module (hub) l'est quand le MODULE est ouvert au rôle ET qu'il en voit un écran : un écran accordé seul
/// par une surcharge (l'aide-soignante et les constantes) n'ouvre pas la page du module.
bool ecranOuvertAuRole(DonneesNavigation nav, String role, String id) {
  final e = nav.manifeste.ecran(id);
  if (e == null) return false;
  if (!e.hub) return nav.matrice.peutVoir(role, id);
  if (!nav.moduleVisible(role, e.module)) return false;
  return nav.manifeste.tousLesEcrans.any((x) => !x.hub && x.module == e.module && nav.matrice.peutVoir(role, x.id));
}

String _tarifCourt(Fiche a) {
  final prix = a['prix'];
  if (prix == null) return 'tarif à valider';
  final base = money(prix, avecDevise: false);
  if (a['tarifProvisoire'] == true) return '$base (valeur d’attente)';
  if (a['nonCouvert'] == true) return '$base · assuré : non couvert';
  final pa = a['prixAssure'];
  if (pa != null && pa != prix) return '$base · assuré ${money(pa, avecDevise: false)}';
  return base;
}

/// `SIGH.app.rechercher(q, role)` de la maquette : les groupes de résultats de la recherche globale pour un rôle. UNE logique, deux habillages (le modal
/// et les vecteurs). Un résultat ne mène JAMAIS où le profil n'a pas accès (RG-13) : écrans, rubriques, et chaque famille de fiches passent par les droits.
List<GroupeRecherche> rechercheGlobale({
  required String requete,
  required String role,
  required DonneesNavigation nav,
  required Magasin magasin,
}) {
  final q = requete.trim();
  if (q.length < 2) return const [];
  bool autorise(String id) => ecranOuvertAuRole(nav, role, id);
  bool ok(String texte) => correspond(texte, q);
  String t(Object? x) => x == null ? '' : '$x';
  final groupes = <GroupeRecherche>[];

  final ecrans = [
    for (final e in nav.manifeste.tousLesEcrans)
      if (!e.standalone && ok('${e.label} ${e.moduleLabel}') && autorise(e.id)) e
  ].take(6).toList();
  if (ecrans.isNotEmpty) {
    groupes.add(GroupeRecherche('Écrans', [
      for (final e in ecrans) ResultatRecherche(label: e.label, detail: e.moduleLabel, icone: e.icone ?? 'circle', ecran: e.id)
    ]));
  }

  // Rubriques : la recherche ouvre la page ET l'onglet concerné.
  final rubriques = [
    for (final r in nav.barre.rubriques)
      if (ok('${r.label} ${r.motsCles}') && autorise(r.ecran)) r
  ].take(6).toList();
  if (rubriques.isNotEmpty) {
    groupes.add(GroupeRecherche('Rubriques', [
      for (final r in rubriques)
        () {
          final e = nav.manifeste.ecran(r.ecran);
          return ResultatRecherche(label: r.label, detail: '${e?.label ?? r.ecran}, onglet', icone: e?.icone ?? 'panel-top', ecran: r.ecran, onglet: r.onglet);
        }()
    ]));
  }

  void famille(String titre, List<Fiche> fiches, bool Function(Fiche) filtre, int max, ResultatRecherche Function(Fiche) vers,
      {String? droit}) {
    if (droit != null && !autorise(droit)) return;
    final l = [
      for (final f in fiches)
        if (filtre(f)) f
    ].take(max).toList();
    if (l.isNotEmpty) groupes.add(GroupeRecherche(titre, [for (final f in l) vers(f)]));
  }

  famille('Patients', magasin.collection('patients').actives, (p) => ok('${t(p['nom'])} ${t(p['prenom'])} ${t(p['code'])}'), 5,
      (p) => ResultatRecherche(
          label: '${t(p['nom'])} ${t(p['prenom'])}', detail: '${t(p['code'])}, ${t(p['quartier'])}', icone: 'user', ecran: 'm1-patients'),
      droit: 'm1-patients');
  famille('Produits', magasin.collection('produits').actives, (p) => ok('${t(p['designation'])} ${t(p['code'])}'), 5,
      (p) => ResultatRecherche(
          label: t(p['designation']), detail: '${t(p['code'])}, stock ${t(p['stock'])} ${t(p['unite'])}', icone: 'pill', ecran: 'm6-produits'),
      droit: 'm6-produits');
  famille('Personnel', magasin.collection('personnel').actives, (e) => ok('${t(e['nomComplet'])} ${t(e['matricule'])} ${t(e['poste'])}'), 5,
      (e) => ResultatRecherche(
          label: t(e['nomComplet']), detail: 'Mat. ${t(e['matricule'])}, ${t(e['poste'])}', icone: 'id-card', ecran: 'm10-personnel'),
      droit: 'm10-personnel');
  // Le catalogue administrable, pas la semence : un acte ajouté ou renommé dans cfg-tarifs se trouve par la recherche.
  famille('Actes & prestations', magasin.collection('actes').actives, (a) => ok('${t(a['libelle'])} ${t(a['secteur'])} ${t(a['code'])}'), 5,
      (a) => ResultatRecherche(
          label: t(a['libelle']), icone: 'stethoscope', detail: '${t(a['secteur'])}, ${_tarifCourt(a)}', ecran: 'cfg-tarifs', onglet: 'actes'),
      droit: 'cfg-tarifs');
  famille('Analyses', magasin.referentiel('analyses'), (a) => ok('${t(a['designation'])} ${t(a['categorie'])} ${t(a['code'])}'), 5,
      (a) => ResultatRecherche(
          label: t(a['designation']),
          icone: 'flask-conical',
          detail: '${t(a['categorie'])}, ${money(a['prix'], avecDevise: false)} · ${t(a['echantillon'])}',
          ecran: 'cfg-tarifs',
          onglet: 'analyses'),
      droit: 'cfg-tarifs');
  famille('Assureurs', magasin.collection('assureurs').actives, (a) => ok('${t(a['nom'])} ${t(a['sigle'])}'), 4,
      (a) => ResultatRecherche(
          label: t(a['nom']),
          detail: 'Convention ${a['convention'] == null || a['convention'] == '' ? 'non renseignée' : t(a['convention'])}',
          icone: 'shield',
          ecran: 'm9-compagnies'),
      droit: 'm9-compagnies');
  famille('Plan comptable', magasin.collection('comptes').actives, (c) => ok('${t(c['numero'])} ${t(c['intitule'])}'), 4,
      (c) => ResultatRecherche(label: '${t(c['numero'])} : ${t(c['intitule'])}', detail: 'SYSCOHADA', icone: 'book-open', ecran: 'm12-plan-comptable'),
      droit: 'm12-plan-comptable');
  return groupes;
}

/// Le modal « Recherche globale » (Ctrl K) : un champ, des résultats groupés, un clic ouvre l'écran visé (et l'onglet d'une rubrique).
Future<void> ouvrirRechercheGlobale(
  BuildContext context, {
  required DonneesNavigation Function() nav,
  required String Function() role,
  required Magasin magasin,
  required void Function(String ecran, {String? onglet}) aller,
}) =>
    afficherModale<void>(context,
        titre: 'Recherche globale',
        corps: _CorpsRecherche(nav: nav, role: role, magasin: magasin, aller: (e, {onglet}) {
          Navigator.of(context, rootNavigator: true).pop();
          aller(e, onglet: onglet);
        }));

class _CorpsRecherche extends StatefulWidget {
  const _CorpsRecherche({required this.nav, required this.role, required this.magasin, required this.aller});
  final DonneesNavigation Function() nav;
  final String Function() role;
  final Magasin magasin;
  final void Function(String ecran, {String? onglet}) aller;

  @override
  State<_CorpsRecherche> createState() => _EtatRecherche();
}

class _EtatRecherche extends State<_CorpsRecherche> {
  final _ctl = TextEditingController();
  String _q = '';

  // Les résultats se calculent au GESTE (saisie), jamais pendant la construction : le premier accès à une collection (le plan comptable assainit ses
  // doublons et journalise) écrit au journal, ce que la construction d'un widget ne doit pas déclencher.
  List<GroupeRecherche> _groupes = const [];

  void _saisie(String v) {
    final q = v.trim();
    setState(() {
      _q = v;
      _groupes = q.length < 2 ? const [] : rechercheGlobale(requete: q, role: widget.role(), nav: widget.nav(), magasin: widget.magasin);
    });
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.trim();
    final groupes = _groupes;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        key: const Key('recherche-champ'),
        controller: _ctl,
        autofocus: true,
        onChanged: _saisie,
        decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
            hintText: 'Patient, produit, employé, écran, acte, analyse, compte…',
            prefixIcon: Icon(LucideIcons.search, size: 16)),
      ),
      const SizedBox(height: 12),
      if (q.length < 2)
        const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text('Saisir au moins 2 caractères.', key: Key('recherche-vide'), style: TextStyle(color: JetonsShell.slate400, fontSize: 12))))
      else if (groupes.isEmpty)
        Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text('Aucun résultat pour « $q ».', key: const Key('recherche-aucun'), style: const TextStyle(color: JetonsShell.slate500, fontSize: 14))))
      else
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 384),
          child: ListView(shrinkWrap: true, children: [
            for (final g in groupes) ...[
              Padding(
                  padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
                  child: Text(g.groupe.toUpperCase(),
                      style: const TextStyle(color: JetonsShell.slate400, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.8))),
              for (final r in g.resultats)
                InkWell(
                  key: Key('resultat:${r.ecran}${r.onglet != null ? '#${r.onglet}' : ''}:${r.label}'),
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => widget.aller(r.ecran, onglet: r.onglet),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    child: Row(children: [
                      Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(color: JetonsShell.slate100, borderRadius: BorderRadius.circular(8)),
                          child: Icon(icone(r.icone), size: 16, color: JetonsShell.slate500)),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(r.label, overflow: TextOverflow.ellipsis, style: const TextStyle(color: JetonsShell.slate800, fontSize: 14, fontWeight: FontWeight.w500)),
                        Text(r.detail, overflow: TextOverflow.ellipsis, style: const TextStyle(color: JetonsShell.slate500, fontSize: 12)),
                      ])),
                      const Icon(LucideIcons.arrowRight, size: 16, color: JetonsShell.slate300),
                    ]),
                  ),
                ),
            ],
          ]),
        ),
    ]);
  }
}
