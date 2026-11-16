import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/donnees/magasin.dart';

import 'aide_grand_stock.dart';

/// LOT PLAN-INDIV (16/11/2026) : le PLANNING PERSONNALISÉ d'un agent voyage entre postes, contre la VRAIE mère Dart et de VRAIS moteurs de fileul :
///  - une version définie chez un fileul arrive à la mère et à l'autre fileul ;
///  - identité COMMUNE par le contenu (l'agent et la date d'effet) : deux postes qui définissent la même version, mère coupée, n'en font qu'UNE ;
///  - jamais vers un téléphone (RG-13) : ni par le journal, ni par un lot de tournée.
/// Non éprouvé ici : le relais cPanel réel, deux machines distinctes, Windows. Les régimes individuels (`regimesIndividuels`) ne se synchronisent pas encore (hors lot, dit au rapport).
Fiche version(String matricule, String dateEffet, {String motif = 'Garde du jeudi'}) => {
      'employeId': 'EMP-$matricule',
      'matricule': matricule,
      'employe': 'AGENT $matricule',
      'fonction': 'medecin',
      'periodicite': 'hebdomadaire',
      'jours': [
        {'jour': 4, 'type': 'garde'}
      ],
      'dateEffet': dateEffet,
      'motif': motif,
      'version': 1,
      'statut': 'actif'
    };

Iterable<Fiche> versions(Magasin m, String matricule) => m.collection('planningsPersonnalises').actives.where((v) => v['matricule'] == matricule);

void main() {
  test('PLAN-INDIV : une version écrite chez un fileul arrive à la mère et à l\'autre fileul ; mère coupée, deux postes, même contenu : UNE fiche ; jamais vers un téléphone', () async {
    final c = Clinique(9812, '${Directory.systemTemp.createTempSync('sigh-planindiv-').path}/mere.sqlite');
    await c.demarrer();
    try {
      final f1 = await c.fileul('F1', 'da', 'DA UN');
      final f2 = await c.fileul('F2', 'da', 'DA DEUX');
      await c.tour();
      f1.m.collection('planningsPersonnalises').inserer(version('7001', '2027-01-04'), prefixe: 'PPE');
      bool partout(bool Function(Magasin) p) => [c.mm, f1.m, f2.m].every(p);
      await c.converger(() => partout((m) => versions(m, '7001').length == 1), 'la version de F1 arrive à la mère et à F2', apres: 4);
      for (final m in [c.mm, f2.m]) {
        expect(versions(m, '7001').single['jours'], [
          {'jour': 4, 'type': 'garde'}
        ]);
      }
      // MÈRE COUPÉE : F1 et F2 définissent la MÊME version (même agent, même date d'effet), avec des motifs différents.
      await c.mere.arreter();
      f1.m.collection('planningsPersonnalises').inserer(version('7002', '2027-02-01', motif: 'Un'), prefixe: 'PPE');
      f2.m.collection('planningsPersonnalises').inserer(version('7002', '2027-02-01', motif: 'Deux'), prefixe: 'PPE');
      for (var i = 0; i < 3; i++) {
        await f1.tour();
        await f2.tour();
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
      expect(versions(c.mm, '7002'), isEmpty, reason: 'la mère est coupée : rien n\'est arrivé');
      await c.demarrerMere();
      await c.converger(() => partout((m) => versions(m, '7002').isNotEmpty), 'la mère relancée reçoit les deux écritures', apres: 6);
      for (final m in [c.mm, f1.m, f2.m]) {
        expect(versions(m, '7002').length, 1, reason: 'la même version définie par deux postes : UNE fiche (identité commune par le contenu)');
      }
      // Un rejeu n'ajoute rien.
      final avant = c.mm.collection('planningsPersonnalises').toutes.length;
      await c.converger(() => true, 'rejeu', apres: 4);
      expect(c.mm.collection('planningsPersonnalises').toutes.length, avant);
      // RG-13 : jamais vers un téléphone.
      final mobile = await collectionsRecuesParUnMobile(c.port);
      expect(mobile.where((o) => o.collection == 'planningsPersonnalises'), isEmpty, reason: 'donnée RH de clinique : fermée aux téléphones');
      final h = HttpClient();
      try {
        final code = await (await (await h.postUrl(Uri.parse('http://127.0.0.1:${c.port}/admin/code'))
                  ..headers.contentType = ContentType.json
                  ..headers.set('x-admin', 'secret-test')
                  ..add(utf8.encode(jsonEncode({'etiquette': 'tel', 'role': 'mobile', 'profil': 'soignant', 'fonction': 'infirmier'}))))
                .close())
            .transform(utf8.decoder)
            .join();
        final jetons = await (await (await h.postUrl(Uri.parse('http://127.0.0.1:${c.port}/appairage'))
                  ..headers.contentType = ContentType.json
                  ..add(utf8.encode(jsonEncode({'code': (jsonDecode(code) as Map)['code'], 'uuid': 'tel-planindiv-1', 'plateforme': 'test'}))))
                .close())
            .transform(utf8.decoder)
            .join();
        expect((jsonDecode(jetons) as Map)['jeton'], isNotNull, reason: jetons);
        final rep = await (await h.postUrl(Uri.parse('http://127.0.0.1:${c.port}/admin/lot'))
              ..headers.contentType = ContentType.json
              ..headers.set('x-admin', 'secret-test')
              ..add(utf8.encode(jsonEncode({
                'uuid': 'tel-planindiv-1',
                'fiches': [
                  {'collection': 'planningsPersonnalises', 'id': 'X'}
                ],
                'ttl_ms': 60000
              }))))
            .close();
        final corps = await rep.transform(utf8.decoder).join();
        expect(rep.statusCode, 422, reason: 'un lot de tournée qui la nomme est refusé ($corps)');
        expect((jsonDecode(corps) as Map)['code'], 'gestion_interdite_au_mobile');
      } finally {
        h.close(force: true);
      }
    } finally {
      await c.arreter();
    }
  }, timeout: const Timeout(Duration(minutes: 4)));
}
