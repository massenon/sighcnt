// Rejoue les VECTEURS exportés de la maquette (prototype_html/build/vecteurs.js) : chaque cas est une entrée et la
// sortie que la MAQUETTE a donnée. Le paquet Dart doit répondre à l'identique — au caractère près, espaces compris.
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

List<Map<String, Object?>> cas(String famille) {
  final f = File('test/vecteurs/$famille.json');
  if (!f.existsSync()) fail('vecteurs absents : lancer `node prototype_html/build/vecteurs.js`');
  return ((jsonDecode(f.readAsStringSync()) as Map)['cas'] as List).cast<Map<String, Object?>>();
}

Object? valeur(Object? v) {
  if (v is Map) {
    if (v['indefini'] == true) return null;
    if (v.containsKey('nombre')) return double.parse(v['nombre']! as String);
  }
  return v;
}

DateTime date(Object? a) {
  final l = (a! as List).cast<int>();
  return DateTime(l[0], l[1] + 1, l[2], l.length > 3 ? l[3] : 0, l.length > 4 ? l[4] : 0);
}

String p2(int n) => n.toString().padLeft(2, '0');
String iso16(DateTime d) => '${d.year}-${p2(d.month)}-${p2(d.day)}T${p2(d.hour)}:${p2(d.minute)}';

void main() {
  group('formats français', () {
    test('money — U+202F entre les milliers, U+00A0 avant la devise', () {
      for (final c in cas('money')) {
        final e = c['entree']! as Map;
        final attendu = (c['sortie']! as Map)['texte'];
        expect(money(valeur(e['valeur']), avecDevise: e['devise']! as bool), attendu, reason: '${c['entree']}');
      }
    });
    test('num — y compris la regex qui groupe aussi les décimales', () {
      for (final c in cas('num')) {
        final e = c['entree']! as Map;
        expect(nombre(valeur(e['valeur']), e['decimales'] as int?), c['sortie'], reason: '${c['entree']}');
      }
    });
    test('pct', () {
      for (final c in cas('pct')) {
        final e = c['entree']! as Map;
        expect(pourcent(valeur(e['valeur']), e['decimales'] as int?), c['sortie'], reason: '${c['entree']}');
      }
    });
    test('nombreEnLettres — accords français', () {
      for (final c in cas('nombreEnLettres')) {
        expect(nombreEnLettres(valeur((c['entree']! as Map)['valeur'])), c['sortie'], reason: '${c['entree']}');
      }
    });
    test('montantEnLettres', () {
      for (final c in cas('montantEnLettres')) {
        expect(montantEnLettres(valeur((c['entree']! as Map)['valeur'])), c['sortie'], reason: '${c['entree']}');
      }
    });
    test('dates', () {
      for (final c in cas('dates')) {
        final d = date((c['entree']! as Map)['date']);
        final s = c['sortie']! as Map;
        expect({
          'dateFR': dateFR(d), 'dateLong': dateLong(d), 'dateJour': dateJour(d), 'heure': heure(d),
          'dateHeure': dateHeure(d), 'iso': iso(d), 'moisAnnee': moisAnnee(d),
        }, s, reason: '${c['entree']}');
      }
    });
  });

  group('référentiels et règles', () {
    test('RG-01 codePatient', () {
      for (final c in cas('codePatient')) {
        final e = c['entree']! as Map;
        expect(codePatient(e['ordre']! as Object, e['annee']! as Object), c['sortie'], reason: '${c['entree']}');
      }
    });
    test('secteurNormalise — six secteurs, ou null', () {
      for (final c in cas('secteurNormalise')) {
        expect(secteurNormalise(valeur((c['entree']! as Map)['cle'])), c['sortie'], reason: '${c['entree']}');
      }
    });
    test('resultatRendu — seul un résultat validé ou rectifié est opposable', () {
      for (final c in cas('resultatRendu')) {
        expect(resultatRendu((c['entree']! as Map)['etat'] as String?), c['sortie'], reason: '${c['entree']}');
      }
    });
  });

  group('périodes', () {
    test('bornes des six périodicités (et période inconnue → journée)', () {
      for (final c in cas('periodes')) {
        final e = c['entree']! as Map;
        final b = bornes(e['periode']! as String, date(e['fin']));
        expect({'debut': iso16(b.debut), 'fin': iso16(b.fin), 'label': b.label, 'jours': b.jours, 'libelle': libellePeriode(b)}, c['sortie'], reason: '${c['entree']}');
      }
    });
    test('plages libres, remises dans l\'ordre', () {
      for (final c in cas('periodesLibres')) {
        final e = c['entree']! as Map;
        final b = bornesLibres(date(e['du']), date(e['au']));
        expect({'debut': iso16(b.debut), 'fin': iso16(b.fin), 'jours': b.jours, 'libelle': libellePeriode(b)}, c['sortie'], reason: '${c['entree']}');
      }
    });
    test('dansBornes — extrémités incluses', () {
      for (final c in cas('dansBornes')) {
        final e = c['entree']! as Map;
        final b = Bornes(date(e['debut']), date(e['fin']), '', 0);
        expect(dansBornes(date(e['date']), b), c['sortie'], reason: '${c['entree']}');
      }
    });
  });
}
