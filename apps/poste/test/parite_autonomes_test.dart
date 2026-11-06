import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/main.dart';
import 'package:sigh_poste/modules/auth/acc_session.dart';
import 'package:sigh_poste/shell/contexte_autonome.dart';

import 'aide_polices.dart';
import 'parite/extracteur.dart' as ex;

/// MESURE DE PARITÉ N1 des NEUF écrans AUTONOMES (sans coque) contre les fiches extraites de leurs pages RÉELLES
/// (`docs/architecture/ecrans/<id>.json`, engendrées par `node build/extraire-autonomes.js`) : connexion, mot de passe oublié,
/// réinitialisation, double facteur, écran verrouillé, pages 404 et 403, plan du site, fiche d'enquête publique.
///
/// `extraire-ecrans.js` attend `#page-content`, absent de ces pages : leurs fiches restaient en `acces: "erreur"` et leur statut « porté »
/// n'était pas mesuré. Ici l'écran Flutter est rendu par la COQUE (registre `ecransAUTH` et page publique d'enquête, via [ContexteAutonome]),
/// puis chaque libellé de la fiche (titre, paragraphes, cartes, champs, placeholders, aria-label, commandes) doit figurer à l'écran.
/// Les VALEURS du jeu ne se comparent pas ; la règle est celle de `comparerContenu` (normalisation, chiffres neutralisés).
typedef M = Map<String, Object?>;
M obj(Object? o) => (o as Map).cast<String, Object?>();
List<M> fl(Object? v) => [for (final x in (v as List)) obj(x)];

final donnees = DonneesNavigation.depuisDossier();
final auj = DateTime(2026, 10, 30, 10);

List<M> jeu(String nom) => fl(jsonDecode(File('assets/donnees/jeu/$nom.json').readAsStringSync()));

M? fiche(String id) {
  final f = File('../../docs/architecture/ecrans/$id.json');
  return f.existsSync() ? obj(jsonDecode(f.readAsStringSync())) : null;
}

Magasin poste({List<M> jetons = const [], List<M> enquetes = const []}) => Magasin({
      'audit': const <M>[],
      'utilisateurs': [for (final u in jeu('utilisateurs')) {...u}],
      'rbac': [for (final r in jeu('rbac')) {...r}],
      'tentativesConnexion': const <M>[],
      'personnel': jeu('personnel'),
      'soignants': jeu('soignants'),
      'rolesBase': jeu('rolesBase'),
      'support': const <M>[],
      'jetonsEnquete': jetons,
      'enquetes': enquetes,
      'reponsesEnquetes': const <M>[],
    }, 'POSTE');

/// Ce que l'agent LIT, comme `innerText` + placeholders + aria-label côté maquette : les textes de l'extracteur commun, plus les `hintText`, les
/// étiquettes de sémantique et les libellés de champ.
Set<String> textesAgent(WidgetTester t) {
  final out = ex.textesVisibles(t);
  void ajouter(String? s) {
    if (s != null && s.trim().isNotEmpty) out.add(ex.normaliser(s));
  }

  for (final w in t.widgetList<TextField>(find.byType(TextField))) {
    ajouter(w.decoration?.hintText);
    ajouter(w.decoration?.labelText);
  }
  for (final w in t.widgetList<Semantics>(find.byType(Semantics))) {
    ajouter(w.properties.label);
  }
  for (final w in t.widgetList<Tooltip>(find.byType(Tooltip))) {
    ajouter(w.message);
  }
  for (final w in t.widgetList<Icon>(find.byType(Icon))) {
    ajouter(w.semanticLabel);
  }
  return out;
}

Future<void> monter(WidgetTester t, Magasin m,
    {String? ecran, SessionPoste? session, Map<String, String> parametres = const {}, Size taille = const Size(1440, 900)}) async {
  t.view.physicalSize = taille;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  await t.pumpWidget(SighPoste(
      key: UniqueKey(),
      donnees: donnees,
      config: ConfigPoste(mode: ModePoste.fileul, role: 'admin'),
      ecranInitial: ecran,
      magasin: m,
      session: session,
      parametres: parametres,
      horloge: () => auj));
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> fin(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 10));
  ToastsSigh.viderPourTests();
}

/// Comment chaque écran est monté : `index` par la connexion exigée (personne n'est connecté), le verrou sous la session de l'administrateur du
/// banc, la page publique avec l'enquête et le jeton portés par la fiche (`fixtureEnquete`, posés par l'extracteur), les autres par leur identifiant.
Future<void> ouvrir(WidgetTester t, String id, M f) async {
  switch (id) {
    case 'index':
      await monter(t, poste(), session: SessionPoste(exigeConnexion: true, horloge: () => auj));
    case 'auth-lock':
    case 'auth-2fa':
    case 'plan-du-site':
      await monter(t, poste(),
          ecran: id, session: SessionPoste.ouverte('admin', nom: 'BASSONGUI Chabi Séko', horloge: () => auj), taille: const Size(1440, 40000));
    case 'enquete-publique':
      final fx = obj(f['fixtureEnquete']);
      await monter(t, poste(jetons: [obj(fx['jeton'])], enquetes: [obj(fx['enquete'])]),
          ecran: id, parametres: {'jeton': '${obj(fx['jeton'])['jeton']}'});
    default:
      await monter(t, poste(), ecran: id);
  }
}

/// Écarts ASSUMÉS (E2279) : phrases où la maquette dit honnêtement qu'elle ne branche rien (« Maquette : ... »). Le poste, lui, est branché
/// (demande inscrite au journal, mot de passe tenu par l'administrateur) : recopier ces phrases serait faux pour lui. Tout autre libellé reste exigé.
const ecartsAssumes = <String, List<String>>{
  'auth-forgot': ['cette page n’enregistre aucune demande'],
  'auth-reset': ['maquette : cette page ne modifie aucun mot de passe'],
  'auth-2fa': ['maquette non branchée'],
};

const ecrans = ['index', 'auth-forgot', 'auth-reset', 'auth-2fa', 'auth-lock', 'error-404', 'error-403', 'plan-du-site', 'enquete-publique'];

void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  final rapport = <String, Object?>{};

  for (final id in ecrans) {
    testWidgets('N1 $id : chaque libellé de la page réelle de la maquette figure à l’écran', (t) async {
      final f = fiche(id);
      expect(f, isNotNull, reason: 'fiche absente : node build/extraire-autonomes.js');
      expect(f!['acces'], 'ouvert', reason: '$id : la fiche doit venir de la page réelle (acces ouvert)');
      await ouvrir(t, id, f);
      expect(find.byType(ContexteAutonome), findsOneWidget, reason: '$id doit être servi sans coque');
      final textes = textesAgent(t);
      final p = ex.comparerContenu(id, f, textes);
      // Règle de la mesure commune (« contient »), DURCIE pour les libellés courts : « 4 » ou « M2 » se trouvent dans n'importe quel texte plus long,
      // ils ne prouvent rien. Un libellé de trois caractères au plus doit figurer SEUL, tel quel, comme un texte à part entière.
      final courts = <String>{};
      for (final k in ['titre', 'description', 'cartes', 'champs', 'commandes']) {
        final v = f[k];
        for (final x in (v is List ? v : [v])) {
          if (x is String && x.trim().isNotEmpty && ex.normaliser(x).length <= 3) courts.add(ex.normaliser(x));
        }
      }
      final courtsManquants = [for (final c in courts) if (!textes.contains(c) && !p.manquants.contains(c)) c];
      final assumes = ecartsAssumes[id] ?? const <String>[];
      final manquants = [for (final m in [...p.manquants, ...courtsManquants]) if (!assumes.any((a) => m.contains(a))) m];
      rapport[id] = {'attendus': p.attendus, 'presents': p.attendus - manquants.length, 'manquants': manquants, 'courtsStricts': courts.length};
      expect(manquants, isEmpty, reason: '$id : ${p.attendus - manquants.length}/${p.attendus} présents, manquants $manquants');
      await fin(t);
    });
  }

  tearDownAll(() {
    if (Platform.environment['SIGH_RAPPORT_AUTONOMES'] != null) {
      File(Platform.environment['SIGH_RAPPORT_AUTONOMES']!).writeAsStringSync(const JsonEncoder.withIndent(' ').convert(rapport));
    }
  });
}
