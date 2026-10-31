import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';
import 'm14_aide.dart';

/// m14-sessions : écran CALCULÉ (les sessions ne sont pas des connexions réelles) ; « Clôturer » journalise, il ne ferme rien. Les règles de calcul
/// (graine 3413) sont rejouées sur les vecteurs de la maquette par packages/domaine/test/securite_test.dart.
void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  casM14('douze sessions tirées des comptes actifs, quatre indicateurs, en-têtes de la maquette', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'm14-sessions');
    final attendues = secSessions(m.collection('utilisateurs').actives, aujourdhui);
    expect(attendues.length, 12);
    expect(find.text('Sessions ouvertes'), findsOneWidget);
    expect(find.text('Postes distincts'), findsOneWidget);
    expect(find.text('Verrouillées pour inactivité'), findsOneWidget);
    expect(find.text('Délai de verrouillage'), findsOneWidget);
    expect(find.text('15 min'), findsOneWidget);
    for (final e in ['IDENTIFIANT', 'UTILISATEUR', 'RÔLE', 'POSTE', 'ADRESSE RÉSEAU', 'OUVERTURE', 'INACTIVITÉ', 'ÉTAT']) {
      expect(find.text(e), findsOneWidget, reason: e);
    }
    expect(find.widgetWithText(BoutonSigh, 'Clôturer'), findsNWidgets(12));
    for (final s in attendues) {
      expect(find.text(s.identifiant), findsWidgets, reason: s.identifiant);
    }
    // Verrouillée à partir de quinze minutes d'inactivité, jamais avant.
    expect(attendues.every((s) => s.verrouillage == (s.inactivite >= 15)), isTrue);
    expect(find.text('Verrouillée'), findsNWidgets(attendues.where((s) => s.verrouillage).length));
    expect(find.textContaining('verrouillage automatique de l’écran'), findsOneWidget);
  });

  casM14('« Clôturer » : confirmation nommant le poste, puis une entrée de journal (RG-12) — aucune session n\'est fermée', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'm14-sessions');
    final premiere = secSessions(m.collection('utilisateurs').actives, aujourdhui).first;
    final avant = m.collection('audit').toutes.length;
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Clôturer').first);
    expect(find.text('Clôturer la session de ${premiere.nomComplet} ?'), findsOneWidget);
    expect(find.text('L’utilisateur sera immédiatement déconnecté du poste ${premiere.poste}. L’opération est journalisée.'), findsOneWidget);
    // Annuler la confirmation n'écrit rien.
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Annuler'));
    expect(m.collection('audit').toutes.length, avant);
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Clôturer').first);
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Clôturer la session'));
    expect(find.text('Session clôturée.'), findsOneWidget);
    expect(find.text('${premiere.nomComplet} — ${premiere.poste}'), findsOneWidget);
    final e = m.collection('audit').actives.first;
    expect(e['action'], 'Modification');
    expect(e['module'], 'M14');
    expect(e['entite'], 'SessionUtilisateur');
    expect(e['reference'], premiere.identifiant);
    expect(e['avant'], {'etat': 'ouverte'});
    expect(e['apres'], {'etat': 'close'});
    expect(m.collection('audit').toutes.length, avant + 1);
    // Rien n'a bougé du côté des comptes : la clôture ne désactive personne.
    expect(m.collection('utilisateurs').actives.length, 48);
    expect(find.widgetWithText(BoutonSigh, 'Clôturer'), findsNWidgets(12));
  });

  casM14('l\'écran dit ce qu\'il est : sessions calculées, non relevées', (t) async {
    await ouvrirM14(t, magasinM14(), 'm14-sessions');
    expect(find.textContaining('calculées à partir des comptes actifs, non relevées'), findsOneWidget);
  });

  casM14('lecture seule : « Clôturer » est ABSENTE (jamais grisée)', (t) async {
    await ouvrirM14(t, magasinM14(), 'm14-sessions',
        role: 'da', donnees: donneesLectureSeule('da', 'm14-sessions'));
    expect(find.text('Sessions ouvertes'), findsOneWidget);
    expect(find.widgetWithText(BoutonSigh, 'Clôturer'), findsNothing);
  });
}
