import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/service_parametres.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/sync/configuration_sync.dart';
import 'package:sigh_poste/sync/pont_activite.dart';
import 'package:sigh_poste/sync/transcription_mobile.dart';
import 'package:sigh_sync/sigh_sync.dart';

/// Lot L0 : les paramètres versionnés par date au poste. Le domaine porte les règles (rejouées sur les vecteurs du banc) ; ici : le branchement au magasin, la
/// garde d'immutabilité tenue AU MOTEUR, la publication par la mère (refus nommé de la mère compris) et la réception par un fileul qui ne peut pas écrire.
typedef M = Map<String, Object?>;

Magasin vide() => Magasin({'utilisateurs': <M>[], 'audit': <M>[]});

void main() {
  const circuit = 'planning.circuitPresences';

  group('service branché sur le magasin', () {
    test('la mère sème un défaut par définition, une seule fois, et le journal le dit (RG-12)', () {
      final m = vide();
      final s = serviceParametres(m, auteur: () => 'Poste mère');
      expect(s.semerDefauts(), definitionsParametres.length);
      expect(s.semerDefauts(), 0);
      expect(m.collection(parCollectionParametres).toutes.length, definitionsParametres.length);
      expect(m.collection('audit').toutes, isNotEmpty);
    });

    test('régler ajoute une version datée : la valeur dépend de la date de la pièce', () {
      final m = vide();
      final s = serviceParametres(m, auteur: () => 'ADJOVI Koffi', horloge: () => DateTime(2026, 11, 9, 9));
      s.semerDefauts();
      final r = s.regler(circuit, 'daf', '2026-12-01', motif: 'Décision de la Direction');
      expect(r.ok, isTrue, reason: '${r.refus}');
      expect(s.valeur(circuit, '2026-11-30'), 'surveillant');
      expect(s.valeur(circuit, '2026-12-01'), 'daf');
      expect(m.collection(parCollectionParametres).parId('$circuit@2026-12-01@1')!['auteur'], 'ADJOVI Koffi');
    });

    test('une valeur déjà utilisée par une pièce ne se réécrit pas : refus nommé, rien d\'écrit', () {
      final m = vide();
      final s = serviceParametres(m, auteur: () => 'ADJOVI Koffi');
      s.semerDefauts();
      expect(s.enregistrerUsage(circuit, '2026-11-08', 'F-1'), isNull);
      final avant = m.collection(parCollectionParametres).toutes.length;
      final r = s.regler(circuit, 'daf', '2026-11-01');
      expect(r.refus!.code, 'parametre_deja_utilise');
      expect(r.refus!.geste, contains('2026-11-08'));
      expect(m.collection(parCollectionParametres).toutes.length, avant);
    });

    test('une version ne se modifie ni ne s\'archive : la garde du moteur refuse (RG-14, immuabilité)', () {
      final m = vide();
      final s = serviceParametres(m, auteur: () => 'ADJOVI Koffi');
      s.semerDefauts();
      final id = Parametres.idVersion(circuit, null, 0);
      expect(() => m.collection(parCollectionParametres).mettreAJour(id, {'valeur': 'daf'}), throwsA(isA<EcritureRefusee>()));
      expect(() => m.collection(parCollectionParametres).archiver(id), throwsA(isA<EcritureRefusee>()));
      expect(m.collection(parCollectionParametres).parId(id)!['valeur'], 'surveillant');
    });
  });

  group('synchronisation', () {
    test('les paramètres et leurs usages voyagent : configuration pour les versions, activité pour les usages', () {
      expect(collectionsConfiguration(), contains(parCollectionParametres));
      expect(collectionsActivite, contains(parCollectionUsages));
      expect(collectionsConfiguration(), isNot(contains(parCollectionUsages)));
    });

    test('la mère publie ses versions ; le fileul les reçoit, les applique, et ne peut pas les écrire', () async {
      final mere = vide();
      final sm = serviceParametres(mere, auteur: () => 'Poste mère');
      sm.semerDefauts();
      sm.regler(circuit, 'daf', '2026-12-01');
      final envoye = <String, M>{};
      await PublicateurConfiguration(mere, (c, f, champs) async => envoye['$c/$f'] = champs, delai: Duration.zero).pousser();
      expect(envoye.keys.where((k) => k.startsWith('$parCollectionParametres/')).length, definitionsParametres.length + 1);

      final fileul = vide();
      final appl = ApplicateurConfiguration(fileul, (c) async => [
            if (c == parCollectionParametres)
              for (final e in envoye.entries)
                if (e.key.startsWith('$c/')) PieceSync(e.key.substring(c.length + 1), e.value)
          ]);
      appl.demarrer(intervalle: const Duration(hours: 1));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      appl.arreter();
      final sf = serviceParametres(fileul, auteur: () => 'Caisse');
      expect(sf.valeur(circuit, '2026-11-30'), 'surveillant');
      expect(sf.valeur(circuit, '2026-12-01'), 'daf', reason: 'le fileul applique la même valeur à la même date');
      // Le fileul n'écrit jamais un paramètre : la collection est protégée « réglé sur la mère ».
      expect(() => sf.regler(circuit, 'surveillant_puis_daf', '2027-01-01'), throwsA(isA<EcritureRefusee>()));
      // Un usage, lui, s'écrit sur le fileul (c'est de l'activité) et remonte à la mère par le pont.
      expect(sf.enregistrerUsage(circuit, '2026-11-20', 'F-1'), isNull);
      expect(fileul.collection(parCollectionUsages).toutes.single['piece'], 'F-1');
    });
  });
}
