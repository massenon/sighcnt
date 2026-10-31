import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'mra_source.dart';

/// Ce que l'écran dit d'une valeur que le moteur ne fournit pas. « Non disponible » n'est pas zéro : la valeur existe peut-être, la mère ne la dit pas.
const nonDisponible = 'non disponible';

/// « Non calculable » : la valeur se déduirait de données dont une partie manque.
const nonCalculable = 'non calculable';

const _styleCorps = TextStyle(color: JetonsShell.slate600, fontSize: 14, height: 20 / 14);
const TextStyle styleMraPetit = TextStyle(color: JetonsShell.slate500, fontSize: 12, height: 16 / 12);

/// Résultat d'une lecture : la valeur, ou l'échec nommé du service. Une valeur `null` SANS échec veut dire « la mère n'expose pas cette lecture ».
class LectureMra<T> {
  const LectureMra(this.valeur, [this.echec]);
  final T? valeur;
  final String? echec;
  bool get dispo => valeur != null;
}

/// Écran de la console mère : en-tête déclaré à la manière de `SIGH.screen`, source injectable, rafraîchissement périodique.
abstract class EcranMra extends StatefulWidget with EcranMaquette {
  const EcranMra({super.key, this.source, this.intervalle = const Duration(seconds: 5), this.maintenant});

  /// `null` : la source par défaut de la coque (`FournisseurMra.parDefaut`) ; sans elle l'écran se dessine et dit « non disponible ».
  final SourceMra? source;
  final Duration intervalle;
  final DateTime Function()? maintenant;

  /// Autres écrans de la console proposés en tête de page (identifiant, libellé).
  List<(String, String)> get voisins;

  @override
  String get regle =>
      'Ce module n’existe que sur le poste mère (serveur local). Il n’affiche que ce que le moteur de synchronisation annonce : '
      'ce qu’il ne fournit pas est indiqué « non disponible », jamais remplacé par une valeur supposée.';

  @override
  List<Widget> actionsEntete(BuildContext context) {
    final c = ContexteEcran.of(context);
    return [
      for (final (id, libelle) in [...voisins, ('hub-mere', 'Exploitation de la synchronisation')])
        BoutonSigh(libelle: libelle, variante: VarianteBouton.secondaire, onPressed: () => c.aller(id)),
    ];
  }
}

/// Base commune des états d'écran : charge à l'ouverture et à chaque tour de minuterie, garde la dernière panne pour la bannière.
abstract class EtatEcranMra<W extends EcranMra> extends State<W> {
  Timer? _minuterie;
  final List<String> _pannes = [];
  bool charge = false;

  SourceMra? get source => widget.source ?? FournisseurMra.parDefaut;
  DateTime maintenant() => (widget.maintenant ?? DateTime.now)();

  /// Lit toutes les données de l'écran (appelle [lire] pour chacune) et les range dans l'état.
  Future<void> charger();

  @override
  void initState() {
    super.initState();
    actualiser();
    _minuterie = Timer.periodic(widget.intervalle, (_) => actualiser());
  }

  @override
  void dispose() {
    _minuterie?.cancel();
    super.dispose();
  }

  /// Une lecture : un échec est retenu (bannière) et rendu en `echec`, il ne casse pas les autres lectures de l'écran.
  Future<LectureMra<T>> lire<T>(Future<T?> Function(SourceMra s) f) async {
    final s = source;
    if (s == null) {
      const m = 'source du moteur non branchée';
      if (!_pannes.contains(m)) _pannes.add(m);
      return const LectureMra(null, m);
    }
    try {
      return LectureMra(await f(s));
    } catch (e) {
      final m = '$e';
      _pannes.add(m);
      return LectureMra(null, m);
    }
  }

  Future<void> actualiser() async {
    _pannes.clear();
    await charger();
    if (mounted) setState(() => charge = true);
  }

  String? get panne => _pannes.isEmpty ? null : _pannes.first;

  /// Un geste d'écriture : succès annoncé, refus de la mère affiché avec la cause qu'elle a nommée (jamais reformulée).
  Future<void> geste(Future<Object?> Function(SourceMra s) f, {String? ok}) async {
    final s = source;
    if (s == null) return;
    try {
      await f(s);
      if (ok != null && mounted) ToastsSigh.afficher(context, ok, type: TypeToast.succes);
    } catch (e) {
      if (mounted) ToastsSigh.afficher(context, '$e', type: TypeToast.erreur);
    }
    await actualiser();
  }

  /// Droit d'écrire sur L'ÉCRAN. Une commande interdite est ABSENTE.
  bool get peutEcrire => ContexteEcran.of(context).droit.editer;

  Widget corps(List<Widget> enfants) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (panne != null)
          Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: NoteSigh('Le service de la mère ne répond pas pour une partie des données : $panne', ton: TonSigh.danger)),
        for (final (i, w) in enfants.indexed) Padding(padding: EdgeInsets.only(bottom: i == enfants.length - 1 ? 0 : 16), child: w),
      ]);
}

/// Rangée de KPI : quatre colonnes dès 1024 px, deux dès 640, une en dessous.
Widget grilleKpi(List<KpiSigh> kpis) => LayoutBuilder(builder: (_, c) {
      final n = c.maxWidth >= 1024 ? kpis.length.clamp(1, 4) : (c.maxWidth >= 640 ? 2 : 1);
      final l = (c.maxWidth - 16 * (n - 1)) / n;
      return Wrap(spacing: 16, runSpacing: 16, children: [for (final k in kpis) SizedBox(width: l - 0.01, child: k)]);
    });

/// Valeur de KPI à partir d'une lecture : le nombre, ou « non disponible » avec la raison en indice.
KpiSigh kpiMra(String libelle, Object? valeur, {String? indice, TonSigh ton = TonSigh.navy, IconData? icone}) => KpiSigh(
    libelle: libelle,
    valeur: valeur == null ? nonDisponible : '$valeur',
    ton: valeur == null ? TonSigh.neutre : ton,
    indice: indice,
    icone: icone);

/// Tableau à en-têtes TOUJOURS visibles : sans ligne, le kit n'en dessine pas, et l'agent ne saurait pas ce que la mère n'a pas dit.
/// Avec des lignes, c'est le tableau du kit (recherche, tri, colonnes, export, pagination).
Widget tableauMra(
    {required List<ColonneTableau> colonnes,
    required List<Ligne> lignes,
    required String messageVide,
    String? indiceVide,
    List<FiltreTableau> filtres = const [],
    List<Widget> Function(BuildContext, Ligne)? actionsLigne,
    String nomExport = 'export',
    String? triInitial,
    String sensInitial = 'asc'}) {
  if (lignes.isNotEmpty) {
    return Builder(builder: (ctx) => TableauSigh(
        alExporter: (nom, csv) {
          Clipboard.setData(ClipboardData(text: csv));
          ToastsSigh.afficher(ctx, 'Export « $nom » copié dans le presse-papiers.', type: TypeToast.succes);
        },
        colonnes: colonnes,
        lignes: lignes,
        filtres: filtres,
        actionsLigne: actionsLigne,
        nomExport: nomExport,
        triInitial: triInitial,
        sensInitial: sensInitial,
        messageVide: messageVide));
  }
  return Container(
    decoration: decorationCarte(),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(11),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: JetonsShell.slate200))),
          child: Wrap(spacing: 8, children: const [
            BoutonSigh(libelle: 'Colonnes', icone: LucideIcons.columns3, taille: TailleBouton.sm, variante: VarianteBouton.secondaire),
            BoutonSigh(libelle: 'Exporter', icone: LucideIcons.download, taille: TailleBouton.sm, variante: VarianteBouton.secondaire),
          ]),
        ),
        Container(
          color: JetonsShell.slate50,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(children: [
            for (final c in colonnes)
              Expanded(
                  child: Text(c.libelle.toUpperCase(),
                      style: const TextStyle(color: JetonsShell.slate500, fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w600, letterSpacing: 0.6))),
          ]),
        ),
        VideSigh(messageVide, indice: indiceVide),
      ]),
    ),
  );
}

/// Carte « gestes » : dit à quoi sert chaque commande de la page, et pourquoi une commande attendue n'existe pas.
/// Les commandes par ligne y sont NOMMÉES : l'agent les trouve même quand la liste est vide.
Widget carteGestes(List<(String, String)> gestes, {String titre = 'Gestes'}) => CarteSigh(
    titre: titre,
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final (nom, texte) in gestes)
        Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text.rich(TextSpan(children: [
              TextSpan(text: nom, style: const TextStyle(fontWeight: FontWeight.w600, color: JetonsShell.slate900)),
              TextSpan(text: ' : $texte'),
            ]), style: _styleCorps)),
    ]));

/// Pastille d'état d'un contrôle de santé. « Inconnu » est neutre et ne rassure jamais.
Widget badgeEtat(String etat) {
  final (ton, l) = switch (etat) {
    'ok' => (TonSigh.succes, 'OK'),
    'attention' => (TonSigh.attention, 'À surveiller'),
    'alerte' => (TonSigh.danger, 'ALERTE'),
    _ => (TonSigh.neutre, 'Inconnu'),
  };
  return BadgeSigh(l, ton: ton);
}

String dateHeureMra(DateTime d) {
  final l = d.toLocal();
  String z(int n) => n.toString().padLeft(2, '0');
  return '${z(l.day)}/${z(l.month)}/${l.year} ${z(l.hour)}:${z(l.minute)}';
}

/// Âge lisible depuis [maintenant] (la règle est au domaine).
String ageDepuis(DateTime? d, DateTime maintenant) => mraAgeLisible(d == null ? null : maintenant.difference(d));

/// Nom affiché d'un appareil : son étiquette, sinon son identifiant.
String nomAppareil(String uuid, Iterable<({String uuid, String etiquette})> connus) {
  for (final a in connus) {
    if (a.uuid == uuid) return a.etiquette.isEmpty ? uuid : a.etiquette;
  }
  return uuid;
}
