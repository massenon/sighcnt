import 'package:flutter/material.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';

/// Briques communes aux huit écrans de M10 (B). Les règles chiffrées sont dans `packages/domaine/lib/src/rh/rhb_regles.dart` ; ce fichier ne porte que
/// de la mise en page et la lecture du magasin du poste.

const rhbSignSurveillant = Signature('Le Surveillant Général', nom: 'GARBA Yahouza');
const rhbSignDaf = Signature('La Directrice Administrative', nom: 'TAKI Alimatou');
const rhbSignDm = Signature('Le Directeur Médical', nom: 'BASSONGUI Chabi Séko');
const rhbSignDirecteurAdmin = Signature('La Directrice de l’Administration et des Finances', nom: 'TAKI Alimatou');

/// Reconstruit la vue quand l'une des collections [collections] change (insertion, mise à jour, archivage, annulation).
class RhbEcoute extends StatefulWidget {
  const RhbEcoute({super.key, required this.collections, required this.construire});
  final List<String> collections;
  final Widget Function(BuildContext contexte, ContexteEcran c) construire;
  @override
  State<RhbEcoute> createState() => _RhbEcouteState();
}

class _RhbEcouteState extends State<RhbEcoute> {
  final List<CollectionMagasin> _cols = [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final m = ContexteEcran.of(context).magasin;
    final neuves = [for (final n in widget.collections) m.collection(n)];
    var identique = neuves.length == _cols.length;
    for (var i = 0; identique && i < neuves.length; i++) {
      identique = identical(neuves[i], _cols[i]);
    }
    if (identique) return;
    for (final c in _cols) {
      c.removeListener(_maj);
    }
    _cols
      ..clear()
      ..addAll(neuves);
    for (final c in _cols) {
      c.addListener(_maj);
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
  Widget build(BuildContext context) => widget.construire(context, ContexteEcran.of(context));
}

/// Un champ de la barre de filtres (`label.label` + `select` / `input`) : son propre contrôleur, lisible et réglable par son [nom].
class RhbFiltre {
  RhbFiltre(this.def, [Object? initial]) : controleur = ControleurFormulaire([def], {def.nom: initial ?? ''});
  final ChampDef def;
  final ControleurFormulaire controleur;
  String get valeur => '${controleur[def.nom] ?? ''}';
  void poser(String v) => controleur.poser(def.nom, v);
}

/// La barre de filtres d'un écran de statistiques : `card-body grid gap-3 md:grid-cols-3 lg:grid-cols-6` (ou `flex flex-wrap items-end gap-3`).
Widget rhbBarre(List<RhbFiltre> filtres, {List<Widget> boutons = const [], int colonnes = 6, Key? cle}) => CarteSigh(
      key: cle,
      child: LayoutBuilder(builder: (_, c) {
        final n = c.maxWidth >= 1024 ? colonnes : (c.maxWidth >= 768 ? 3 : 1);
        final l = (c.maxWidth - 12 * (n - 1)) / n;
        return Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.end, children: [
          for (final f in filtres) SizedBox(width: l, child: FormulaireSigh(key: Key('rhb:filtre:${f.def.nom}'), controleur: f.controleur)),
          if (boutons.isNotEmpty) Wrap(spacing: 8, runSpacing: 8, children: boutons),
        ]);
      }),
    );

/// `grid gap-4 lg:grid-cols-3` : trois cartes de graphiques côte à côte dès 1024 px.
Widget rhbTroisCartes(List<Widget> cartes) => LayoutBuilder(builder: (_, c) {
      final n = c.maxWidth >= 1024 ? 3 : 1;
      final l = (c.maxWidth - 16 * (n - 1)) / n;
      return Wrap(spacing: 16, runSpacing: 16, children: [for (final k in cartes) SizedBox(width: l, child: k)]);
    });

/// `K.charts` : deux cartes côte à côte dès 1024 px.
Widget rhbDeuxCartes(List<Widget> cartes) => LayoutBuilder(builder: (_, c) {
      final n = c.maxWidth >= 1024 ? 2 : 1;
      final l = (c.maxWidth - 16 * (n - 1)) / n;
      return Wrap(spacing: 16, runSpacing: 16, children: [for (final k in cartes) SizedBox(width: l, child: k)]);
    });

Widget rhbEspace(List<Widget> enfants, {double gap = 16}) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final (i, w) in enfants.indexed) ...[if (i > 0) SizedBox(height: gap), w]
    ]);

/// Le bandeau de lecture seule du socle : posé quand l'écran se modifie et que le profil n'a pas le droit d'écrire.
Widget rhbLectureSeule(ContexteEcran c) => (!c.droit.editer && c.droit.voir)
    ? Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: NoteSigh('Lecture seule : le profil « ${c.role} » consulte cet écran sans pouvoir y écrire. Les droits se règlent dans la matrice des rôles.',
            ton: TonSigh.attention))
    : const SizedBox.shrink();

TonSigh rhbTon(String t) => switch (t) {
      'success' => TonSigh.succes,
      'info' => TonSigh.info,
      'warning' => TonSigh.attention,
      'danger' => TonSigh.danger,
      'navy' => TonSigh.navy,
      _ => TonSigh.neutre,
    };

/// `String(x)` d'une valeur nulle ou absente → texte vide.
String rhbTexte(Object? v) => v == null ? '' : '$v';

/// Les fiches ACTIVES d'une collection du magasin.
List<Fiche> rhbActives(ContexteEcran c, String nom) => c.magasin.collection(nom).actives;

PieceA4 rhbPiece(ContexteEcran c,
        {required String titre,
        String? sousTitre,
        List<(String, String)> cartouche = const [],
        List<TableauEtat> tableaux = const [],
        List<BlocPiece> blocs = const [],
        List<(String, String)> filtres = const [],
        List<Signature> signatures = const []}) =>
    PieceA4(
        titre: titre,
        sousTitre: sousTitre,
        reference: PieceA4.reference_(c.aujourdhui, ImpressionPoste.prochainNumero()),
        utilisateur: c.utilisateur,
        edite: c.aujourdhui,
        cartouche: cartouche,
        tableaux: tableaux,
        blocs: blocs,
        filtres: filtres,
        signatures: signatures);

const TextStyle rhbPetit = TextStyle(color: JetonsShell.slate400, fontSize: 12, height: 16 / 12);
const TextStyle rhbCorps = TextStyle(color: JetonsShell.slate800, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w500);

/// Intitulé d'agent : nom en 14/20 (500) et, dessous, un détail en 12/16.
Widget rhbAgentCellule(String nom, String detail) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(nom, overflow: TextOverflow.ellipsis, style: rhbCorps),
      Text(detail, overflow: TextOverflow.ellipsis, style: rhbPetit),
    ]);

/// LA QUESTION QUI COMPTE — la portée d'une modification (régime de travail, grille des primes, barème NS 131). Une règle de référence qui change alors que des
/// pièces ont été émises sous l'ancienne se VERSIONNE par date, elle ne s'écrase pas : la Direction tranche, à chaque modification, entre « à venir seulement »
/// (le choix prudent, présélectionné) et « rétroactif ». Le contexte [ctx] est celui de l'ÉCRAN (la modale vit au-dessus de la coque).
Future<void> rhbDemanderPortee(BuildContext ctx,
    {required String sousTitre,
    required String alerteTitre,
    required String alerteTexte,
    required TonSigh tonAlerte,
    Widget? tableau,
    required (String, String) futur,
    required (String, String) tout,
    required void Function(String portee) appliquer}) {
  var portee = 'futur';
  Widget option(StateSetter maj, String id, (String, String) t, String badge, TonSigh ton) {
    final choisi = portee == id;
    return InkWell(
      key: Key('rhb:portee:$id'),
      onTap: () => maj(() => portee = id),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: choisi ? JetonsShell.navy50 : null,
            border: Border.all(color: choisi ? JetonsShell.navy400 : JetonsShell.slate200)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(choisi ? Icons.radio_button_checked : Icons.radio_button_off, size: 18, color: choisi ? JetonsShell.navy700 : JetonsShell.slate400),
          const SizedBox(width: 12),
          Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t.$1, style: const TextStyle(color: JetonsShell.slate800, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(t.$2, style: const TextStyle(color: JetonsShell.slate500, fontSize: 12, height: 16 / 12)),
          ])),
          const SizedBox(width: 8),
          BadgeSigh(badge, ton: ton),
        ]),
      ),
    );
  }

  return afficherModale<void>(ctx,
      titre: 'Portée de la modification',
      sousTitre: sousTitre,
      taille: TailleModale.lg,
      corps: StatefulBuilder(
          builder: (_, maj) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                NoteSigh('$alerteTitre $alerteTexte', ton: tonAlerte, icone: Icons.warning_amber_rounded),
                if (tableau != null) ...[const SizedBox(height: 12), tableau],
                const SizedBox(height: 12),
                option(maj, 'futur', futur, 'Recommandé', TonSigh.succes),
                const SizedBox(height: 12),
                option(maj, 'tout', tout, 'Rétroactif', TonSigh.danger),
              ])),
      pied: (fermer) => [
            BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
            BoutonSigh(
                libelle: 'Appliquer',
                icone: Icons.check,
                onPressed: () {
                  fermer();
                  appliquer(portee);
                }),
          ]);
}

/// La porte du barème NS 131 (`SIGH.baremeModifiable`) : une bascule d'exploitation, FERMÉE par défaut. Elle s'ouvre depuis « Paramètres système » (module CFG),
/// jamais depuis l'écran des évaluations. Le poste la range dans la collection `reglages` (une fiche par clé) en attendant que CFG soit porté.
bool rhbPorteBaremeOuverte(ContexteEcran c) =>
    c.magasin.collection('reglages').actives.any((f) => f['id'] == 'baremeModifiable' && f['valeur'] == true);

/// `C.referenceSuivante(prefixe, largeur, fiches)` : le plus grand rang déjà écrit pour ce préfixe, plus un.
String rhbReferenceSuivante(String prefixe, int largeur, Iterable<Fiche> fiches) {
  var max = 0;
  for (final f in fiches) {
    final r = '${f['reference'] ?? ''}';
    if (r.startsWith(prefixe)) {
      final n = int.tryParse(RegExp(r'^\d+').firstMatch(r.substring(prefixe.length))?.group(0) ?? '') ?? 0;
      if (n > max) max = n;
    }
  }
  return '$prefixe${(max + 1).toString().padLeft(largeur, '0')}';
}

/// `G.TONES` (charts.js).
const rhbTonNavy = Color(0xFF12315E);
const rhbTonBleu = Color(0xFF3765A6);
const rhbTonVert = Color(0xFF22A170);
const rhbTonOrange = Color(0xFFF98307);
const rhbTonRouge = Color(0xFFEF4444);

/// Les agents ACTIFS, triés par nom complet (`C.sortBy(personnel(), 'nomComplet')`).
List<Fiche> rhbPersonnelTrie(ContexteEcran c) => trierPar(rhbActives(c, 'personnel'), (e) => e['nomComplet']);
