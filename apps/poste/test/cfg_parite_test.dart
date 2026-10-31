import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/controleur_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/core/parametres_poste.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/main.dart';
import 'package:sigh_poste/mere/activation.dart';
import 'package:sigh_poste/mere/client_mere.dart';

import 'activation_test.dart' show FauxService;
import 'aide_polices.dart';
import 'parite/extracteur.dart';

/// MESURE DE PARITÉ N1 (contenu) des écrans de CFG portés, même méthode que `parite_ecrans_test.dart` (jeu complet, horloge épinglée au 30/10/2026
/// 10 h, rôle admin) mais limitée aux écrans de ce module : chacun DOIT être à 100 % — le test échoue en nommant ce qui manque.
const ecransMesures = [
  'cfg-natures-facture',
  'cfg-organisation',
  'cfg-tarifs',
  'cfg-catalogue',
  'cfg-branding',
  'cfg-entetes',
];

void main() {
  setUpAll(chargerPolices);
  final donnees = DonneesNavigation.depuisDossier();

  for (final id in ecransMesures) {
    testWidgets('N1 = 100 % : $id', (t) async {
      final f = (jsonDecode(File('../../docs/architecture/ecrans/$id.json').readAsStringSync()) as Map).cast<String, Object?>();
      t.view.physicalSize = const Size(1440, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      final client = ClientMere(base: Uri.parse('http://x'), secretAdmin: 's', client: MockClient((r) async => http.Response('[]', 200)));
      final act = ActivationMere(stockage: StockageMemoire(), service: FauxService(), relaisPour: (_, __) => throw StateError('hors sujet'));
      final ctl = ControleurPoste(activation: act, config: const ConfigPoste(mode: ModePoste.fileul, role: 'admin', nomPoste: 'Test'));
      await t.pumpWidget(SighPoste(
          donnees: donnees,
          controleur: ctl,
          client: client,
          ecranInitial: id,
          horloge: () => DateTime(2026, 10, 30, 10),
          magasin: Magasin.depuisDossier(Magasin.collectionsDuJeu)));
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      final p = comparerContenu(id, f, textesVisibles(t));
      // ignore: avoid_print
      print('N1 $id : ${p.presents}/${p.attendus} = ${(p.taux * 100).toStringAsFixed(1)} %');
      expect(p.manquants, isEmpty, reason: '$id : il manque ${p.manquants}');
      await t.pump(const Duration(seconds: 10));
    });
  }
}
