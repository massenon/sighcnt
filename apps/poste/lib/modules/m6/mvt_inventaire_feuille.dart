import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'mvt_commun.dart';

/// Le contexte d'une feuille d'inventaire. Dans la maquette il voyage par l'ADRESSE (`#magasin=gros&type=Mensuel…`) : une modale tient son contexte
/// de l'écran qui l'ouvre, une page se charge à froid et ne sait rien. Ici la navigation ne porte pas de paramètres : le registre dépose l'en-tête
/// dans [AdresseFeuille.enAttente], la feuille le consomme UNE fois à l'ouverture (usage unique, comme le retour du verrou de session). Ouverte
/// à froid, la feuille prend les valeurs par défaut de la maquette : magasin gros, type « Ponctuel », tous les articles.
class EnteteInventaire {
  const EnteteInventaire({this.magasin = 'gros', this.type = 'Ponctuel', this.date, this.perimetre = 'Tous les articles', this.operateur, this.retour = 'm6-inventaire'});
  final String magasin;
  final String type;
  final String? date;
  final String perimetre;
  final String? operateur;
  final String retour;
}

class AdresseFeuille {
  AdresseFeuille._();
  static EnteteInventaire? enAttente;
  static EnteteInventaire? _consommer() {
    final e = enAttente;
    enAttente = null;
    return e;
  }
}

/// `m6-inventaire-feuille` — la feuille de comptage : une PAGE, pas une fenêtre (on y compte deux cents articles, un par un, la main sur le rayon).
///
/// ELLE PORTE SUR UN MAGASIN NOMMÉ. Le stock théorique lu, l'écart calculé et la régularisation écrite portent tous sur CE stock — gros ou détail,
/// jamais le total des deux : compter les rayons de la pharmacie d'urgence et régulariser le magasin central était le défaut corrigé le 21/09/2026.
/// Les règles (théorique, écart au CUMP, un mouvement de régularisation par écart, jamais sous zéro) sont dans `packages/domaine`.
///
/// ON NE QUITTE PAS LA PAGE À LA VALIDATION, et c'est délibéré : l'annulation est une FONCTION — elle restitue les stocks et retire les mouvements —
/// et une fonction ne traverse pas une navigation. Partir au registre afficherait un message d'où « Annuler » aurait disparu, juste après
/// l'opération qui en a le plus besoin. La feuille se referme donc sur son résultat, et c'est l'agent qui repart.
class EcranInventaireFeuille extends StatefulWidget with EcranMaquette {
  const EcranInventaireFeuille({super.key});

  @override
  String get titre => 'Feuille d’inventaire';

  @override
  String get description => 'Comptage physique article par article sur un magasin nommé, écarts calculés en direct et valorisés au CUMP.';

  @override
  String get regle =>
      'Le comptage porte sur un magasin nommé : le stock théorique, l’écart et la régularisation ne concernent que lui. La validation écrit un mouvement de régularisation par écart (RG-03, justificatif = référence de l’inventaire) — le stock ne se corrige jamais sans laisser de trace, et jamais en dessous de zéro.';

  /// « Valider l'inventaire » dans l'en-tête de la page : un raccourci vers la même fonction que le bouton du pied.
  @override
  List<Widget> actionsEntete(BuildContext context) {
    final c = ContexteEcran.maybeOf(context);
    if (c == null || !c.droit.editer) return const [];
    return [
      BoutonSigh(libelle: 'Valider l’inventaire', icone: LucideIcons.check, taille: TailleBouton.sm, onPressed: () => _EtatFeuille._courant?.valider()),
    ];
  }

  @override
  State<EcranInventaireFeuille> createState() => _EtatFeuille();
}

class _EtatFeuille extends State<EcranInventaireFeuille> {
  static _EtatFeuille? _courant;

  late final EnteteInventaire _entete;
  late final String _magasin;
  late final String _date;
  late final String _operateur;
  List<Fiche> _cible = const [];
  final Map<String, TextEditingController> _saisies = {};
  final Map<String, String> _edites = {};
  String _filtre = '';
  Fiche? _valide;
  bool _pret = false;

  String get _label => magasinLabelInventaire(_magasin);

  void _preparer(ContexteEcran c) {
    _pret = true;
    _courant = this;
    _entete = AdresseFeuille._consommer() ?? const EnteteInventaire();
    _magasin = _entete.magasin == 'detail' ? 'detail' : 'gros';
    _date = _entete.date ?? iso(c.aujourdhui);
    _operateur = _entete.operateur ?? c.utilisateur;
    _cible = ciblesInventaire(produitsActifs(c), _entete.perimetre);
  }

  @override
  void dispose() {
    if (_courant == this) _courant = null;
    for (final t in _saisies.values) {
      t.dispose();
    }
    super.dispose();
  }

  /// Le stock physique compté : l'article jamais touché garde son théorique (écart nul) ; un champ vidé vaut zéro (`Number('') || 0`).
  Fiche _ligne(Fiche p) => ligneComptage(p, _magasin, _edites.containsKey('${p['id']}') ? _edites['${p['id']}'] : stockTheorique(p, _magasin));

  TextEditingController _ctl(Fiche p) =>
      _saisies.putIfAbsent('${p['id']}', () => TextEditingController(text: nombreBrut(stockTheorique(p, _magasin))));

  static String nombreBrut(num v) => v == v.truncate() ? '${v.toInt()}' : '$v';

  void valider() {
    if (!mounted || _valide != null) return;
    final c = ContexteEcran.of(context);
    if (!c.droit.editer) return;
    final m = c.magasin;
    final inventaires = m.collection('inventaires');
    final mouvements = m.collection('mouvements');
    final produits = m.collection('produits');
    final v = validerInventaire(
      entete: {'magasin': _magasin, 'type': _entete.type, 'date': _date, 'perimetre': _entete.perimetre, 'operateur': _operateur},
      cible: _cible,
      physiques: {for (final e in _edites.entries) e.key: n(e.value)},
      inventaires: inventaires.toutes,
      mouvements: mouvements.toutes,
    );
    final annulations = <VoidCallback>[];
    final res = inventaires.inserer(v.inventaire, prefixe: 'INV');
    annulations.add(res.annuler);
    // La régularisation : le magasin compté, et le total qui en découle — un mouvement par écart, justificatif = n° d'inventaire (RG-03).
    for (var i = 0; i < v.produits.length; i++) {
      produits.mettreAJour(v.produits[i].id, v.produits[i].patch);
      annulations.add(mouvements.inserer(v.mouvements[i], prefixe: 'MVT').annuler);
    }
    final avant = v.avant;
    final nbEcarts = v.inventaire['nbEcarts'];
    annonce(context, 'Inventaire ${v.inventaire['reference']} validé — $nbEcarts écart(s) régularisé(s) sur le ${_label.toLowerCase()}.',
        duree: const Duration(seconds: 12), annuler: () {
      for (final a in avant) {
        produits.mettreAJour(a.id, a.patch);
      }
      for (final u in annulations) {
        u();
      }
    });
    setState(() => _valide = res.fiche);
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    if (!_pret) _preparer(c);
    if (!c.droit.editer) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const NoteSigh('Votre profil consulte les inventaires sans les saisir. Le comptage appartient au gestionnaire de stock et au pharmacien.',
            ton: TonSigh.attention, icone: LucideIcons.lock),
        const SizedBox(height: 12),
        BoutonSigh(libelle: 'Revenir au registre', icone: LucideIcons.arrowLeft, variante: VarianteBouton.secondaire, onPressed: () => c.aller(_entete.retour)),
      ]);
    }
    final vals = [for (final p in _cible) _ligne(p)];
    final ecarts = vals.where((x) => n(x['ecart']) != 0).toList();
    final valeurEcarts = ecarts.fold<num>(0, (a, x) => a + n(x['valeur']));
    final principal = _valide == null ? _comptage(vals) : _resultat(c, _valide!);
    final aside = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      CarteSigh(
          titre: 'Enchaînement du parcours',
          child: Column(children: [
            _etape('Lancement', '${_entete.type} — $_label', 'Étape 1', JetonsShell.success600),
            _etape('Comptage physique', '${nombre(_cible.length)} article(s) au périmètre « ${_entete.perimetre} »', 'Étape 2', JetonsShell.navy700),
            _etape('Validation', 'L’inventaire est enregistré et les écarts régularisés', 'Étape 3', JetonsShell.info600),
            _etape('Mouvements de régularisation', 'Un mouvement par écart, justificatif = n° d’inventaire (M6)', 'Étape 4', JetonsShell.warning600),
            _etape('État d’inventaire', 'Pièce signée magasinier, pharmacien et DAF', 'Étape 5', JetonsShell.slate600, dernier: true),
          ])),
      const SizedBox(height: 16),
      CarteSigh(
          titre: 'Écarts constatés',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            KpiSigh(libelle: 'Articles inventoriés', valeur: nombre(vals.length), icone: LucideIcons.package),
            const SizedBox(height: 12),
            KpiSigh(
                libelle: 'Écarts constatés',
                valeur: nombre(ecarts.length),
                icone: LucideIcons.triangleAlert,
                ton: ecarts.isNotEmpty ? TonSigh.attention : TonSigh.succes),
            const SizedBox(height: 12),
            KpiSigh(libelle: 'Valeur des écarts', valeur: money(valeurEcarts), icone: LucideIcons.wallet, ton: valeurEcarts < 0 ? TonSigh.danger : TonSigh.succes),
          ])),
      const SizedBox(height: 16),
      CarteSigh(
          titre: 'La feuille en cours',
          child: DescListeSigh([
            ('Magasin', _label),
            ('Type', _entete.type),
            ('Date', dateDe(_date)),
            ('Périmètre', _entete.perimetre),
            ('Réalisé par', _operateur),
          ])),
      const SizedBox(height: 16),
      CarteSigh(
          titre: 'Ce que la validation écrit',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: const [
            NoteSigh('RG-03 — chaque écart engendre un mouvement de stock portant la référence de l’inventaire en justificatif. Le stock ne peut pas devenir négatif.',
                icone: LucideIcons.shieldCheck),
            SizedBox(height: 12),
            NoteSigh('La régularisation porte sur le magasin compté et sur lui seul.', ton: TonSigh.attention, icone: LucideIcons.package),
          ])),
    ]);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      LayoutBuilder(builder: (_, w) {
        if (w.maxWidth >= 1024) {
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 2, child: principal),
            const SizedBox(width: 16),
            Expanded(child: aside),
          ]);
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [principal, const SizedBox(height: 16), aside]);
      }),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.only(top: 16),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: JetonsShell.slate200))),
        child: Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: [
          BoutonSigh(libelle: 'Annuler', icone: LucideIcons.x, variante: VarianteBouton.secondaire, onPressed: () => c.aller(_entete.retour)),
          BoutonSigh(libelle: 'Valider l’inventaire', icone: LucideIcons.check, onPressed: valider),
        ]),
      ),
    ]);
  }

  Widget _etape(String titre, String detail, String date, Color couleur, {bool dernier = false}) => Padding(
        padding: EdgeInsets.only(bottom: dernier ? 0 : 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(top: 5), child: Container(width: 10, height: 10, decoration: BoxDecoration(color: couleur, shape: BoxShape.circle))),
          const SizedBox(width: 10),
          Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(titre, style: const TextStyle(color: JetonsShell.slate800, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w500)),
            Text(detail, style: const TextStyle(color: JetonsShell.slate500, fontSize: 12, height: 16 / 12)),
            Text(date, style: const TextStyle(color: JetonsShell.slate400, fontSize: 11, height: 15 / 11)),
          ])),
        ]),
      );

  // --------------------------------------------------------------------------
  // Le comptage
  // --------------------------------------------------------------------------
  Widget _comptage(List<Fiche> vals) {
    final q = _filtre.trim().toLowerCase();
    final visibles = [
      for (final x in vals)
        if (q.isEmpty || '${(x['produit'] as Map)['designation']} ${(x['produit'] as Map)['code']}'.toLowerCase().contains(q)) x
    ];
    Widget entete(String t, {bool droite = false, int flex = 1}) => Expanded(
        flex: flex,
        child: Text(t.toUpperCase(), textAlign: droite ? TextAlign.right : TextAlign.left, style: const TextStyle(color: JetonsShell.slate500, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.6)));
    return CarteSigh(
      titre: 'Comptage — ${_entete.perimetre}',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        NoteSigh(
            'Saisir le stock physique compté pour chaque article. Les écarts avec le stock théorique du $_label sont calculés en direct et valorisés au CUMP.',
            icone: LucideIcons.clipboardList),
        const SizedBox(height: 12),
        TextField(
            key: const Key('inv:filtre'),
            style: styleSaisie,
            decoration: decorationChamp(indicatif: 'Filtrer par désignation ou code…'),
            onChanged: (v) => setState(() => _filtre = v)),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(border: Border.all(color: JetonsShell.slate200), borderRadius: BorderRadius.circular(8)),
          child: Column(children: [
            Container(
                color: JetonsShell.slate50,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(children: [
                  entete('Article', flex: 4),
                  entete('Théorique', droite: true),
                  entete('Physique', droite: true, flex: 2),
                  entete('Écart', droite: true),
                  entete('Valeur', droite: true, flex: 2),
                ])),
            SizedBox(
              height: 512,
              child: ListView.builder(
                itemCount: visibles.length,
                itemBuilder: (_, i) => _rangee(visibles[i]),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _rangee(Fiche x) {
    final pr = x['produit'] as Fiche;
    final e = n(x['ecart']);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: JetonsShell.slate100))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(
            flex: 4,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${pr['designation']}', style: const TextStyle(color: JetonsShell.slate700, fontSize: 14, height: 20 / 14)),
              Text('${pr['code']}', style: styleMono.copyWith(color: JetonsShell.slate400)),
            ])),
        Expanded(child: Text(nombre(x['theorique']), textAlign: TextAlign.right, style: const TextStyle(color: JetonsShell.slate700, fontSize: 14))),
        Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                  width: 96,
                  child: TextField(
                    key: Key('inv:${pr['code']}'),
                    controller: _ctl(pr),
                    textAlign: TextAlign.right,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: styleSaisie,
                    decoration: decorationChamp(),
                    onChanged: (v) => setState(() => _edites['${pr['id']}'] = v),
                  )),
            )),
        Expanded(
            child: Text('${e > 0 ? '+' : ''}${nombre(e)}',
                textAlign: TextAlign.right,
                style: TextStyle(
                    color: e == 0 ? JetonsShell.slate700 : (e < 0 ? JetonsShell.danger600 : JetonsShell.success600),
                    fontSize: 14,
                    fontWeight: e == 0 ? null : FontWeight.w600))),
        Expanded(flex: 2, child: Text(m(x['valeur']), textAlign: TextAlign.right, style: const TextStyle(color: JetonsShell.slate700, fontSize: 14))),
      ]),
    );
  }

  // --------------------------------------------------------------------------
  // La feuille se referme sur son résultat
  // --------------------------------------------------------------------------
  Widget _resultat(ContexteEcran c, Fiche enr) => CarteSigh(
        titre: 'Inventaire ${enr['reference']} — validé',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DescListeSigh([
            ('Référence', enr['reference']),
            ('Magasin', _label),
            ('Type', enr['type']),
            ('Périmètre', enr['perimetre']),
            ('Articles inventoriés', nombre(enr['nbArticles'])),
            ('Écarts régularisés', nombre(enr['nbEcarts'])),
            ('Valeur des écarts', money(enr['valeurEcart'] ?? 0)),
          ]),
          const SizedBox(height: 12),
          const NoteSigh(
              'Les mouvements de régularisation sont écrits (RG-03). Tant que le message est affiché, « Annuler » revient sur l’opération entière — stocks et mouvements compris.',
              icone: LucideIcons.undo2),
          const SizedBox(height: 12),
          Align(
              alignment: Alignment.centerLeft,
              child: BoutonSigh(
                  libelle: 'Revenir au registre des inventaires', icone: LucideIcons.arrowLeft, onPressed: () => c.aller(_entete.retour))),
        ]),
      );
}
