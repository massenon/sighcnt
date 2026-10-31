import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';
import 'm14_aide.dart';

/// m14-taches : un INSTANTANÉ du planificateur du serveur de la maquette (le poste ne planifie rien). Le calcul du retard est rejoué sur les vecteurs de la
/// maquette par packages/domaine/test/securite_test.dart ; ici, l'écran — et ce qu'il refuse.
void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  casM14('registre du jeu : six tâches, leur fréquence, leur dernier résultat, quarante exécutions', (t) async {
    final m = magasinM14();
    final taches = m.collection('tachesPlanifiees').actives;
    expect(taches.length, 6);
    await ouvrirM14(t, m, 'm14-taches');
    for (final k in ['Tâches actives', 'En erreur', 'En retard sur leur fréquence', 'Alertes ouvertes (dernière passe)']) {
      expect(find.text(k), findsOneWidget, reason: k);
    }
    for (final e in ['TÂCHE', 'FRÉQUENCE', 'DERNIÈRE EXÉCUTION', 'RÉSULTAT', 'DURÉE', 'ALERTES', 'DÉBUT (UTC)', 'DÉCLENCHÉE PAR']) {
      expect(find.text(e), findsWidgets, reason: e);
    }
    expect(find.text('Registre des tâches'), findsOneWidget);
    expect(find.text('Dernières exécutions'), findsOneWidget);
    for (final x in taches) {
      expect(find.text('${x['libelle']}'), findsOneWidget);
      expect(find.text('toutes les ${x['frequence_min']} min'), findsWidgets);
    }
    expect(find.text('Exécuter'), findsNWidgets(6));
    // Les alertes ouvertes de la dernière passe : la somme des tâches (13 + 0 + 54 + 0 + 0 + 51 au moment de l'export).
    final alertes = taches.fold<int>(0, (a, x) => a + ((x['alertes'] as num?)?.toInt() ?? 0));
    expect(find.text('$alertes'), findsWidgets);
    expect(m.collection('executionsTaches').actives.length, 40);
    expect(find.textContaining('instantané du planificateur'), findsOneWidget);
  });

  casM14('le retard est jugé sur l\'horloge du poste : trois périodes sans exécution, et le bandeau le dit', (t) async {
    final m = magasinM14();
    // Le jour de l'export : rien n'est en retard. Une semaine plus tard, plus rien n'a tourné — personne ne planifie ici.
    await ouvrirM14(t, m, 'm14-taches', horloge: DateTime(2026, 10, 31, 0, 30));
    expect(find.textContaining('n’ont pas tourné à leur fréquence'), findsNothing);
    await ouvrirM14(t, m, 'm14-taches', horloge: DateTime(2026, 11, 7, 10));
    final b = secBilanTaches(m.collection('tachesPlanifiees').actives, DateTime(2026, 11, 7, 10));
    expect(b.enRetard, 6);
    expect(find.textContaining('6 tâche(s) n’ont pas tourné à leur fréquence.'), findsOneWidget);
  });

  casM14('« Exécuter » est REFUSÉE en le disant : le poste n\'a pas de planificateur, rien n\'est écrit', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'm14-taches');
    final avant = m.collection('audit').toutes.length;
    final journal = m.collection('executionsTaches').toutes.length;
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Exécuter').first);
    expect(find.textContaining('Exécution refusée : ce poste n’a pas de planificateur.'), findsOneWidget);
    expect(find.textContaining('s’exécute dans le serveur de la maquette (api/cron.php)'), findsOneWidget);
    expect(m.collection('audit').toutes.length, avant);
    expect(m.collection('executionsTaches').toutes.length, journal);
  });

  casM14('registre vide : quatre zéros, aucun retard, « Aucune exécution enregistrée. »', (t) async {
    final m = Magasin({for (final n in Magasin.collectionsDuJeu) n: <Fiche>[]}, 'POSTE', const {});
    await ouvrirM14(t, m, 'm14-taches');
    expect(find.text('Aucune exécution enregistrée.'), findsOneWidget);
    expect(find.textContaining('n’ont pas tourné'), findsNothing);
    expect(find.text('Exécuter'), findsNothing);
  });

  casM14('lecture seule : « Exécuter » est ABSENTE (jamais grisée)', (t) async {
    await ouvrirM14(t, magasinM14(), 'm14-taches',
        role: 'da', donnees: donneesLectureSeule('da', 'm14-taches'));
    expect(find.text('Tâches actives'), findsOneWidget);
    expect(find.text('Exécuter'), findsNothing);
  });
}
