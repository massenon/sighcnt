// LOT 8 : la vue unifiée du dossier patient (« Pièces produites par le logiciel »), élargie aux comptes rendus de maternité et aux fiches de consultation, rejouée sur les vecteurs de la
// maquette (`pieces_produites.json`, tirés par `prototype_html/build/vecteurs-pieces.js` : `SIGH.piecesProduites` sous quatre profils). Des RENVOIS, jamais des copies ; la zone médicale
// (RG-13) ferme la vue entière à qui ne la lit pas.
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

import 'aide_vecteurs.dart';

void main() {
  final V = lireVecteurs('pieces_produites');
  final magasin = (V['magasin'] as Map).cast<String, Object?>();
  final collections = <String, List<Map<String, Object?>>>{
    for (final e in magasin.entries)
      e.key: [
        for (final f in liste(e.value))
          if (f['statut'] != 'archive') f
      ]
  };
  // Les écrans que chaque profil ouvre : lus du vecteur lui-même (le renvoi absent du vecteur est un écran fermé au profil).
  Set<String> ouverts(Map<String, Object?> cas) => {
        for (final p in liste(cas['pieces']))
          for (final l in liste(p['lignes']))
            if (l['ecran'] != null) '${l['ecran']}'
      };

  for (final cas in liste(V['cas'])) {
    final role = '${(cas['profil'] as Map)['role']}';
    group('profil $role', () {
      for (final p in liste(cas['pieces'])) {
        test('dossier ${p['patientId']}', () {
          // Le profil laborantin ne voit que les analyses qu'il habilite : le vecteur donne la décision, la règle d'habilitation est celle des vecteurs `resultats.json`.
          // La session que la maquette portait au tirage (le profil posé PAR-DESSUS la session d'ouverture) : le vecteur la consigne.
          final brute = (cas['session'] as Map).cast<String, Object?>();
          final session = SessionLabo(role: brute['role'] as String?, fonction: brute['fonction'] as String?, secteur: brute['secteur'] as String?, id: brute['id'] as String?, nom: brute['nom'] as String?);
          // Les écrans ouverts sont ceux que le vecteur nomme pour AU MOINS une ligne du profil ; une famille dont le renvoi est nul pour ce profil n'est pas ouverte.
          final ecransOuverts = <String>{
            for (final f in {'m2-ordonnances', 'm5-impression-resultats', 'm3-bloc-cro', 'm2-imagerie-demandes', 'm4-comptes-rendus', 'm2-consultation-fiche'})
              if (ouverts(cas).contains(f)) f
          };
          final lignes = patPiecesProduites(
              patientId: '${p['patientId']}',
              collections: collections,
              peutVoirResultat: (d) => peutVoirResultat(d, session).autorise,
              renvoi: (e) => ecransOuverts.contains(e) ? e : null);
          final obtenu = [for (final l in lignes) {'famille': l.famille, 'reference': l.reference, 'date': l.date, 'resume': l.resume, 'ecran': l.ecran}];
          memes(obtenu, p['lignes'], 'lignes');
        });
      }
    });
  }

  test('la zone médicale ferme la vue entière : le vecteur dit qui la lit (docPeutVoir), le poste la vérifie avant tout renvoi', () {
    for (final cas in liste(V['cas'])) {
      final role = '${(cas['profil'] as Map)['role']}';
      expect(docPeutVoir('Compte rendu médical', role).autorise, cas['zone2'], reason: role);
    }
  });

  test('un compte rendu de maternité ou une fiche de consultation d\'un AUTRE patient, ou archivé, n\'est jamais listé', () {
    final lignes = patPiecesProduites(patientId: 'P1', collections: collections, peutVoirResultat: (_) => true, renvoi: (_) => null);
    final refs = {for (final l in lignes) l.reference};
    expect(refs, isNot(contains('CRM-0003')), reason: 'autre patient');
    expect(refs, isNot(contains('DOS-00003')), reason: 'autre patient');
    expect(refs, isNot(contains('CRM-0004')), reason: 'archivé');
    expect(refs, containsAll(['CRM-0001', 'CRM-0002', 'DOS-00001', 'DOS-00002']));
    expect(patPiecesProduites(patientId: 'P3', collections: collections, peutVoirResultat: (_) => true, renvoi: (_) => null), isEmpty);
  });
}
