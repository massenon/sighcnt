import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'm14_aide.dart';

/// Aides communes aux tests des écrans de M10 (B) : les relevés de la maquette (packages/domaine/test/vecteurs/rhb.json) et quelques gestes.
final vecteursRhb = (jsonDecode(File('../../packages/domaine/test/vecteurs/rhb.json').readAsStringSync()) as Map).cast<String, Object?>();
Map<String, Object?> maquette(String cle) => ((vecteursRhb['jeuDeLaMaquette'] as Map)[cle] as Map).cast<String, Object?>();
List<Map<String, Object?>> liste(Object? v) => [for (final x in (v as List)) (x as Map).cast<String, Object?>()];
Map<String, Object?> dico(Object? v) => (v as Map).cast<String, Object?>();

/// Le jour du jeu : les grilles et les primes portent des valeurs le 16/08/2026.
final auj16 = DateTime(2026, 8, 16, 12);

String norm(Object? s) => '$s'.replaceAll(RegExp(r'\s+'), ' ').trim();

Map<String, String> kpis(WidgetTester t) => {for (final k in t.widgetList<KpiSigh>(find.byType(KpiSigh))) k.libelle: k.valeur};

/// Règle le filtre [nom] de la barre de filtres.
Future<void> regler(WidgetTester t, String nom, String valeur) async {
  t.widget<FormulaireSigh>(find.byKey(Key('rhb:filtre:$nom'))).controleur.poser(nom, valeur);
  await t.pump(const Duration(milliseconds: 50));
}

/// Le texte d'un champ du formulaire ouvert (clé `kit:champ:<nom>`).
Future<void> taper(WidgetTester t, String champ, String texte) => saisir(t, champ, texte);

/// Le magasin de test : le jeu du poste, sans écriture résiduelle.
Magasin magasinRhb() => magasinM14();

/// Touche le bouton portant [libelle] (bouton plein ou icône à infobulle).
Future<void> toucherBouton(WidgetTester t, String libelle) async {
  final b = find.widgetWithText(BoutonSigh, libelle);
  if (b.evaluate().isNotEmpty) return toucherM14(t, b.first);
  return toucherM14(t, find.byTooltip(libelle).first);
}

/// La première fiche de la collection (les insertions se font EN TÊTE, comme la maquette).
Map<String, Object?> premiere(Magasin m, String nom) => m.collection(nom).toutes.first;

/// Retire d'un fiche les champs que le magasin pose lui-même.
Map<String, Object?> net(Map<String, Object?> x) => {
      for (final e in x.entries)
        if (!{'id', '_creePar', '_creeLe', '_modifiePar', '_modifieLe', '_archivePar', '_archiveLe', '_motifArchivage', 'modifiePar', 'modifieePar', 'archivePar', 'archiveePar'}.contains(e.key)) e.key: e.value
    };
