// LA SAUVEGARDE HORS SITE (lot 5, ADR-0007) : les règles pures rejouées sur les vecteurs du banc (`packages/sync/banc/vecteurs-sauvegarde.js`, exécutable de référence
// `sauvegarde-regles.js`), plus ce que le banc ne peut pas dire : les défauts semés, la famille réservée, le contrôle du réglage de la clinique.
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

import 'aide_vecteurs.dart';

Map<String, Object?>? _refus(RefusSauvegarde? r) => r?.toJson();

void main() {
  final v = lireVecteurs('sauvegarde_horssite');
  final cas = liste(v['cas']);

  group('vecteurs du banc (${cas.length} cas)', () {
    for (final c in cas) {
      final e = (c['entree'] as Map).cast<String, Object?>();
      test('${c['op']} : ${c['nom']}', () {
        switch (c['op']) {
          case 'decouper':
            memes([for (final p in shDecouper(e['longueur'] as int, e['tailleBloc'] as int)) p.toJson()], c['attendu'], 'decouper');
          case 'tailleChiffree':
            expect(shTailleChiffree(e['longueur'] as int, e['tailleBloc'] as int), c['attendu']);
          case 'verifierReglage':
            memes(_refus(shVerifierReglage(e)), c['attendu'], 'reglage');
          case 'verifierPlan':
            memes(_refus(shVerifierPlan(octetsCopie: e['octetsCopie'] as int, etat: (e['etat'] as Map?)?.cast<String, Object?>())), c['attendu'], 'plan');
          case 'rotation':
            final copies = [for (final x in liste(e['copies'])) CopieVue.depuisJson(x)];
            final r = shRotation(copies, e['garder'], e['plancher'] as int, e['plafond'] as int);
            memes(r.ok ? {'ok': true, 'gardees': r.gardees, 'archiver': r.archiver} : r.refus!.toJson(), c['attendu'], 'rotation');
          case 'ordrePurge':
            final copies = [for (final x in liste(e['copies'])) CopieVue.depuisJson(x)];
            memes(shOrdrePurge(copies, e['plancher'] as int), c['attendu'], 'purge');
          case 'manifeste':
            memes(shManifeste(type: e['type'] as String, elements: liste(e['elements']), tailleBloc: e['tailleBloc'] as int), c['attendu'], 'manifeste');
          case 'verifierManifeste':
            memes(_refus(shVerifierManifeste(e['manifeste'])), c['attendu'], 'verifierManifeste');
          default:
            fail('op inconnue : ${c['op']}');
        }
      });
    }
  });

  group('réglage de la clinique', () {
    test('DÉSACTIVÉE par défaut : le réglage semé et la définition du paramètre', () {
      expect(const ReglageHorsSite().actif, isFalse);
      final d = definitionDeParametre(shCleActif)!;
      expect(d.defaut, isFalse);
      expect(d.famille, 'horssite');
      expect(d.mobile, isFalse);
    });

    test('les onze paramètres sont déclarés avec un défaut, dans la famille réservée : jamais un téléphone, jamais le panneau générique', () {
      final cles = [
        shCleActif, shCleDestinationMagasin, shCleDestinationFichiers, shCleDossierMagasin, shCleDossierFichiers, shCleFrequence, shCleHeureControle, shCleCopiesMagasin, shCleCopiesFichiers,
        shCleTailleBloc, shCleBlocsControles,
      ];
      for (final c in cles) {
        final d = definitionDeParametre(c);
        expect(d, isNotNull, reason: c);
        expect(d!.famille, 'horssite');
        expect(d.mobile, isFalse, reason: c);
        expect(d.sensible, isFalse);
      }
      expect(parFamillesJamaisMobile, contains('horssite'));
      expect(parFamillesReglageDedie, contains('horssite'));
      expect(definitionDeParametre(shCleDestinationMagasin)!.defaut, 'relais');
      expect(definitionDeParametre(shCleDestinationFichiers)!.defaut, 'aucune');
      expect(definitionDeParametre(shCleCopiesMagasin)!.defaut, shCopiesMagasinDefaut);
      expect(definitionDeParametre(shCleTailleBloc)!.defaut, 1024 * 1024);
      expect(definitionDeParametre(shCleFrequence)!.defaut, 60);
    });

    test('seuls l\'administrateur et la DAF règlent', () {
      expect(shPeutRegler('admin'), isTrue);
      expect(shPeutRegler('da'), isTrue);
      for (final r in ['soignant', 'comptable', 'caissier', 'pharmacien', 'laborantin']) {
        expect(shPeutRegler(r), isFalse, reason: r);
      }
    });

    test('activer sans AUCUNE destination est refusé en le nommant ; un type sans destination est permis si l\'autre en a une', () {
      final r = shVerifierReglageClinique(const ReglageHorsSite(actif: true, magasin: ReglageType(destination: 'aucune', dossier: '', copies: 7)));
      expect(r!.code, 'DESTINATION_ABSENTE');
      expect(r.geste, isNotEmpty);
      expect(shVerifierReglageClinique(const ReglageHorsSite(actif: true)), isNull);
      expect(shVerifierReglageClinique(const ReglageHorsSite()), isNull);
    });

    test('une destination « dossier » sans chemin, et des bornes dépassées, sont refusées en nommant le réglage', () {
      expect(shVerifierReglageClinique(const ReglageHorsSite(actif: true, fichiers: ReglageType(destination: 'dossier', dossier: ' ', copies: 14)))!.code, 'DOSSIER_ABSENT');
      expect(shVerifierReglageClinique(const ReglageHorsSite(tailleBloc: 10))!.code, 'TAILLE_BLOC_HORS_BORNES');
      expect(shVerifierReglageClinique(const ReglageHorsSite(magasin: ReglageType(destination: 'relais', dossier: '', copies: 1)))!.code, 'ROTATION_HORS_BORNES');
      expect(shVerifierReglageClinique(const ReglageHorsSite(frequenceMinutes: 5))!.code, 'FREQUENCE_HORS_BORNES');
      expect(shVerifierReglageClinique(const ReglageHorsSite(heureControle: 24))!.code, 'HEURE_HORS_BORNES');
      expect(shVerifierReglageClinique(const ReglageHorsSite(blocsControles: 201))!.code, 'BLOCS_CONTROLES_HORS_BORNES');
    });

    test('un état de destination sans quota n\'est PAS compté comme zéro : jamais un refus d\'espace fabriqué', () {
      expect(shVerifierPlan(octetsCopie: 10 * 1024 * 1024 * 1024, etat: {'limites': <String, Object?>{}, 'utilise': 0}), isNull);
      expect(shVerifierPlan(octetsCopie: 1, etat: null), isNull);
    });
  });
}
