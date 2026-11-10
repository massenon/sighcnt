import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'aide_polices.dart';
import 'm14_aide.dart';
import 'rhb_aide.dart';

/// m10-presences : l'écran MONTÉ sur le jeu du poste, les gestes de l'agent accomplis (filtres avancés, circuit de validation, régularisation), et ce qui est écrit au
/// magasin comparé aux relevés de la maquette (rhb.json). Les règles du circuit sont rejouées par packages/domaine/test/planning_rh_test.dart.
void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  group('m10-presences', () {
    const cle = {
      'Du': 'pr_f_du', 'Au': 'pr_f_au', 'Recherche': 'pr_f_q', 'Agent': 'pr_f_agent', 'Matricule': 'pr_f_matricule', 'Service': 'pr_f_service', 'État': 'pr_f_etat',
      'Motif codé': 'pr_f_motif', 'Retard minimal (minutes après 08:00)': 'pr_f_retard', 'Arrivée de': 'pr_f_hde', 'Arrivée à': 'pr_f_ha', 'Validation': 'pr_f_validation', 'Validé par': 'pr_f_validepar',
    };
    // Le pointage que le relevé de la maquette crée par le formulaire (il naît À VALIDER) précède ses filtres avancés : le même état de départ.
    // (La seconde création du relevé, « sans agent », n'a pas été refusée : la liste présélectionne son premier agent et la maquette a écrit un second pointage.)
    void poserCreation(Magasin m) {
      final c = dico(maquette('presences')['creation']);
      m.collection('presences').inserer({...net(dico(c['nouvelle'])), 'id': 'PRSVEC1', 'statut': 'actif'}, prefixe: 'PRS');
      m.collection('presences').inserer({...net(dico(dico(maquette('presences')['refus'])['secondeFiche'])), 'id': 'PRSVEC2', 'statut': 'actif'}, prefixe: 'PRS');
    }

    Map<String, String> k(WidgetTester t) => kpis(t);

    casM14('ouverture : trente jours, les cinq compteurs de la maquette, les filtres, le registre et ses quatre graphiques', (t) async {
      await ouvrirM14(t, magasinRhb(), 'm10-presences', horloge: auj16);
      final c = liste(maquette('presences')['cas']).first;
      final v = {for (final x in liste(c['kpis'])) x['label'] as String: norm(x['valeur'])};
      expect(v.length, 5);
      for (final e in v.entries) {
        expect(norm(k(t)[e.key]), e.value, reason: e.key);
      }
      for (final x in liste(c['kpis'])) {
        final w = t.widget<KpiSigh>(find.byWidgetPredicate((w) => w is KpiSigh && w.libelle == x['label']));
        expect(w.indice, x['indice'], reason: 'indice ${x['label']}');
      }
      expect(find.text('Registre des présences — 17/07/2026 au 16/08/2026'), findsOneWidget);
      for (final titre in ['Réglages du planning et des présences', 'Filtres avancés des présences', 'Taux de présence par service', 'Répartition des pointages', 'Volume de pointages par service', 'Retards et absences au fil des jours']) {
        expect(find.text(titre), findsWidgets, reason: titre); // « Taux de présence par service » est aussi une pastille du ruban
      }
      for (final l in ['Du', 'Au', 'Recherche', 'Agent', 'Matricule', 'Service', 'État', 'Motif codé', 'Retard minimal (minutes après 08:00)', 'Arrivée de', 'Arrivée à', 'Validation', 'Validé par']) {
        expect(find.text(l), findsWidgets, reason: 'filtre $l');
      }
      expect(find.text('Critère NS 131'), findsOneWidget);
      expect(find.text('Ajouter un pointage'), findsOneWidget);
      expect(find.text('Imprimer l’état'), findsOneWidget);
    });

    casM14('« Mois en cours » et « Sept derniers jours » règlent la plage ET l\'appliquent', (t) async {
      await ouvrirM14(t, magasinRhb(), 'm10-presences', horloge: auj16);
      final cas = liste(maquette('presences')['cas']);
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Mois en cours'));
      expect(find.text('Registre des présences — 01/08/2026 au 16/08/2026'), findsOneWidget);
      expect(norm(k(t)['Pointages comptés']), norm(liste(cas[1]['kpis']).first['valeur']));
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Sept derniers jours'));
      expect(find.text('Registre des présences — 10/08/2026 au 16/08/2026'), findsOneWidget);
      expect(norm(k(t)['Pointages comptés']), norm(liste(cas[2]['kpis']).first['valeur']));
    });

    casM14('les dates s\'appliquent d\'elles-mêmes (plus de bouton « Appliquer »)', (t) async {
      await ouvrirM14(t, magasinRhb(), 'm10-presences', horloge: auj16);
      expect(find.widgetWithText(BoutonSigh, 'Appliquer'), findsNothing);
      await regler(t, 'pr_f_du', '2026-08-01');
      await regler(t, 'pr_f_au', '2026-08-10');
      final c = liste(maquette('presences')['cas']).firstWhere((x) => x['du'] == '2026-08-01' && x['au'] == '2026-08-10');
      expect([for (final x in liste(c['kpis'])) norm(x['valeur'])], [for (final l in ['Pointages comptés', 'Présences', 'Retards', 'Absences', 'À valider']) norm(k(t)[l])]);
    });

    casM14('une plage sans pointage : « Aucun pointage validé sur la plage et les filtres retenus. », aucun graphique', (t) async {
      await ouvrirM14(t, magasinRhb(), 'm10-presences', horloge: auj16);
      await regler(t, 'pr_f_du', '2030-01-01');
      await regler(t, 'pr_f_au', '2030-01-02');
      expect(find.text('Aucun pointage validé sur la plage et les filtres retenus.'), findsOneWidget);
      expect(find.text('Répartition des pointages'), findsNothing);
    });

    casM14('les onze critères de filtre : le registre, les compteurs et le titre se recalculent comme dans la maquette', (t) async {
      final m = magasinRhb();
      poserCreation(m);
      await ouvrirM14(t, m, 'm10-presences', horloge: auj16);
      final f = dico(dico(maquette('presences'))['filtres']);
      for (final cas in liste(f['cas'])) {
        await toucherM14(t, find.widgetWithText(BoutonSigh, 'Effacer les filtres'));
        for (final e in dico(cas['reglage']).entries) {
          await regler(t, cle[e.key]!, '${e.value}');
        }
        final vue = dico(cas['vue']);
        final nom = '${cas['nom']}';
        for (final x in liste(vue['kpis'])) {
          expect(norm(k(t)[x['label']]), norm(x['valeur']), reason: '$nom : ${x['label']}');
        }
        expect(find.text('Registre des présences — ${DateTime.parse('${vue['du']}').day.toString().padLeft(2, '0')}/08/2026 au 31/08/2026${nom == 'plage du jeu' ? '' : ' (filtré)'}'), findsOneWidget, reason: '$nom : titre');
        if (vue['note'] == true) expect(find.text('Aucun pointage validé sur la plage et les filtres retenus.'), findsOneWidget, reason: nom);
        final lignes = (dico(vue['table'])['lignes'] as List).cast<List>();
        if (lignes.isNotEmpty && nom != 'à valider (aucun au jeu)') {
          cellulesAffichees(t, [lignes.first[2], lignes.first[3]], raison: nom);
        }
      }
    });

    casM14('« Imprimer l\'état » : les lignes retenues, les colonnes de la maquette, TOUS les filtres retracés (heures et seuil de retard compris)', (t) async {
      final m = magasinRhb();
      poserCreation(m);
      await ouvrirM14(t, m, 'm10-presences', horloge: auj16);
      final imp = dico(dico(dico(maquette('presences'))['filtres'])['impression']);
      await regler(t, 'pr_f_du', '2026-08-01');
      await regler(t, 'pr_f_au', '2026-08-31');
      await regler(t, 'pr_f_etat', 'retard');
      await regler(t, 'pr_f_hde', '07:30');
      await regler(t, 'pr_f_retard', '15');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Imprimer l’état'));
      expect(find.text(norm(imp['titre'])), findsWidgets);
      final zone = t.widgetList<Text>(find.descendant(of: find.byKey(const Key('impression:filtres')), matching: find.byType(Text))).map((w) => w.data ?? w.textSpan?.toPlainText() ?? '').join('|');
      for (final f in (imp['filtres'] as List)) {
        final l = f as List;
        expect(sansEspaces(zone).contains(sansEspaces('${l[0]}')) && sansEspaces(zone).contains(sansEspaces('${l[1]}')), isTrue, reason: 'filtre ${l[0]} : ${l[1]} dans « $zone »');
      }
      for (final c in ['Mat.', 'Arrivée', 'Justificatif', 'Validation', 'Validé par']) {
        expect(find.text(c), findsWidgets, reason: c);
      }
      expect(find.textContaining('Dont validés'), findsWidgets);
    });

    casM14('ajouter un pointage : il NAÎT À VALIDER (visible, ne compte pas) ; la fiche porte le nom, le matricule et le service de l\'agent', (t) async {
      final m = magasinRhb();
      await ouvrirM14(t, m, 'm10-presences', horloge: auj16);
      final avant = m.collection('presences').toutes.length;
      final retardsAvant = k(t)['Retards'];
      final aValiderAvant = int.parse(norm(k(t)['À valider']));
      final agent = m.collection('personnel').actives.firstWhere((e) => e['nomComplet'] == 'BASSONGUI Chabi Séko');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Ajouter un pointage'));
      expect(find.text('Nouveau pointage'), findsOneWidget);
      for (final l in ['Agent', 'Date du pointage', 'État', 'Heure d’arrivée', 'Heure de départ', 'Motif codé', 'Justificatif (référence du document)', 'Motif / justification']) {
        expect(find.textContaining(l), findsWidgets, reason: l);
      }
      expect(find.text('Certificat médical, ordre de mission, décision de congé'), findsOneWidget);
      await choisirM14(t, 'employeId', '${agent['matricule']} — ${agent['nomComplet']} (${agent['poste']})');
      await choisirM14(t, 'etat', 'Retard');
      await taper(t, 'heureArrivee', '09:15');
      await taper(t, 'heureDepart', '17:00');
      await taper(t, 'motif', 'Embouteillage');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Créer'));
      final c = dico(maquette('presences')['creation']);
      final attendu = net(dico(c['nouvelle']));
      final f = net(premiere(m, 'presences'));
      const session = {'saisiPar', 'saisiLe'};
      expect({for (final e in attendu.entries) if (!session.contains(e.key)) e.key: f[e.key]}, {for (final e in attendu.entries) if (!session.contains(e.key)) e.key: e.value});
      expect([f['validationEtat'], f['etapesFaites']], ['a_valider', isEmpty]);
      expect('${f['saisiPar']}'.isNotEmpty, isTrue, reason: 'RG-12');
      expect(m.collection('presences').toutes.length, avant + 1);
      expect(find.text('Pointage créé.'), findsOneWidget);
      expect(k(t)['Retards'], retardsAvant, reason: 'un pointage à valider ne compte pas');
      expect(int.parse(norm(k(t)['À valider'])), aValiderAvant + 1);
    });

    casM14('le circuit au geste : valider (confirmation, journal), refuser (MOTIF exigé), puis RÉGULARISER le pointage validé', (t) async {
      final m = magasinRhb();
      poserCreation(m);
      final agents3 = m.collection('personnel').actives.skip(5).take(3).toList();
      for (final (i, e) in agents3.indexed.toList().reversed) {
        m.collection('presences').inserer({
          'id': 'PRSCIRC$i', 'statut': 'actif', 'employeId': e['id'], 'employe': e['nomComplet'], 'matricule': e['matricule'], 'service': e['service'], 'date': '2026-08-16',
          'etat': 'retard', 'heureArrivee': '09:${10 + i}', 'validationEtat': 'a_valider', 'etapesFaites': <Object?>[],
        }, prefixe: 'PRS');
      }
      await ouvrirM14(t, m, 'm10-presences', horloge: auj16);
      final c = dico(dico(maquette('presences'))['circuit']);
      await regler(t, 'pr_f_du', '2026-08-16');
      await regler(t, 'pr_f_au', '2026-08-16');
      await regler(t, 'pr_f_validation', 'a_valider');
      for (final x in liste(dico(c['avant'])['kpis'])) {
        expect(norm(k(t)[x['label']]), norm(x['valeur']), reason: 'avant : ${x['label']}');
      }
      // Les commandes de la ligne : valider et refuser (étape du surveillant), modifier, archiver.
      expect(find.byTooltip('Valider ce pointage').evaluate().length, 5);
      expect(find.byTooltip('Refuser ce pointage').evaluate().length, 5);
      // Valider.
      await chercherTableau(t, '${agents3[0]['nomComplet']}');
      await toucherM14(t, find.byTooltip('Valider ce pointage').first);
      expect(find.text('Valider ce pointage ?'), findsOneWidget);
      expect(find.textContaining('Circuit en vigueur : Surveillant seul.'), findsOneWidget);
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Valider'));
      final v = m.collection('presences').parId('PRSCIRC0')!;
      final valide = dico(dico(c['valider'])['fiche']);
      expect([v['validationEtat'], v['circuitUtilise'], v['valideLe']], [valide['validationEtat'], valide['circuitUtilise'], valide['valideLe']]);
      expect(find.text('${dico(dico(c['valider'])['toast'])['message']}'), findsOneWidget);
      // Refuser : sans motif, rien ne se passe ; avec motif, le pointage est refusé et le motif est écrit.
      await chercherTableau(t, '${agents3[1]['nomComplet']}');
      await toucherM14(t, find.byTooltip('Refuser ce pointage').first);
      expect(find.text('Refuser ce pointage ?'), findsOneWidget);
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Refuser'));
      expect(m.collection('presences').parId('PRSCIRC1')!['validationEtat'], 'a_valider');
      await t.enterText(find.byType(TextField).last, 'Pointage contesté');
      await t.pump();
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Refuser'));
      final r = m.collection('presences').parId('PRSCIRC1')!;
      expect([r['validationEtat'], r['motifRefus']], ['refuse', 'Pointage contesté']);
      // Régulariser le pointage VALIDÉ : la commande n'existe que pour lui ; la modification directe est REFUSÉE par le moteur.
      await chercherTableau(t, '');
      await regler(t, 'pr_f_validation', 'valide');
      await regler(t, 'pr_f_agent', '${agents3[0]['id']}');
      expect([for (final x in (c['boutonsValide'] as List)) '$x'], contains('Régulariser ce pointage'));
      await toucherM14(t, find.byTooltip('Régulariser ce pointage').first);
      expect(find.text('Régulariser le pointage'), findsOneWidget);
      for (final l in ['Nouvel état', 'Motif codé', 'Justificatif (référence du document)', 'Motif de la régularisation']) {
        expect(find.textContaining(l), findsWidgets, reason: l);
      }
      final ctl = t.widget<FormulaireSigh>(find.byType(FormulaireSigh).last).controleur;
      ctl.poser('etat', 'present');
      ctl.poser('motifCode', 'maladie');
      ctl.poser('justificatif', 'CERT-7');
      ctl.poser('motif', 'Certificat remis');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Régulariser'));
      final g = m.collection('presences').parId('PRSCIRC0')!;
      final attendu = dico(dico(c['regulariser'])['fiche']);
      expect([g['etat'], g['motifCode'], g['justificatif'], g['validationEtat']], [attendu['etat'], attendu['motifCode'], attendu['justificatif'], 'valide']);
      expect((g['regularisations'] as List).length, 1);
      expect(find.text('Pointage régularisé.'), findsOneWidget);
      expect(find.text('Régularisé 1 fois'), findsOneWidget);
    });

    casM14('un pointage validé ne se MODIFIE pas directement : le moteur refuse, en le disant', (t) async {
      final m = magasinRhb();
      final id = m.collection('presences').actives.first['id'];
      m.collection('presences').mettreAJour(id, {'validationEtat': 'valide'});
      await ouvrirM14(t, m, 'm10-presences', horloge: auj16);
      final avant = m.collection('presences').parId(id)!['etat'];
      expect(() => m.collection('presences').mettreAJour(id, {'etat': avant == 'absent' ? 'present' : 'absent'}), throwsA(isA<EcritureRefusee>()));
      expect(m.collection('presences').parId(id)!['etat'], avant);
    });

    casM14('un pointage sans heure ni motif : les valeurs par défaut de la maquette (aujourd\'hui, présent, 07:45)', (t) async {
      final m = magasinRhb();
      await ouvrirM14(t, m, 'm10-presences', horloge: auj16);
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Ajouter un pointage'));
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Créer'));
      final f = premiere(m, 'presences');
      expect([f['date'], f['etat'], f['heureArrivee']], ['2026-08-16', 'present', '07:45']);
      final premierAgent = (m.collection('personnel').actives.toList()..sort((a, b) => '${a['nomComplet']}'.compareTo('${b['nomComplet']}'))).first;
      expect(f['employeId'], premierAgent['id'], reason: 'la liste présélectionne sa première entrée');
    });

    casM14('modifier un pointage (le droit d\'écrire) et l\'archiver (motif exigé, annulable) — jamais de suppression', (t) async {
      final m = magasinRhb();
      await ouvrirM14(t, m, 'm10-presences', horloge: auj16);
      final avant = m.collection('presences').actives.length;
      await toucherM14(t, find.byTooltip('Modifier').first);
      await choisirM14(t, 'etat', 'Absent');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
      expect(m.collection('presences').actives.where((x) => x['etat'] == 'absent').length, greaterThan(0));
      expect(find.text('Modifications enregistrées.'), findsOneWidget);
      await toucherM14(t, find.byTooltip('Archiver').first);
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Archiver'));
      expect(m.collection('presences').actives.length, avant, reason: 'sans motif, rien n\'est archivé');
      await t.enterText(find.byType(TextField).last, 'Doublon de saisie');
      await t.pump();
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Archiver'));
      expect(m.collection('presences').actives.length, avant - 1);
      expect(m.collection('presences').archivees.length, 1);
    });

    casM14('lecture seule : ni « Ajouter un pointage » ni « Modifier » ni « Archiver », ni commande de validation hors circuit', (t) async {
      await ouvrirM14(t, magasinRhb(), 'm10-presences', horloge: auj16, role: 'da', donnees: donneesLectureSeule('da', 'm10-presences'));
      expect(find.text('Pointages comptés'), findsOneWidget);
      expect(find.text('Ajouter un pointage'), findsNothing);
      expect(find.byTooltip('Modifier'), findsNothing);
      expect(find.byTooltip('Archiver'), findsNothing);
      expect(find.byTooltip('Valider ce pointage'), findsNothing, reason: 'en surveillant seul, la DA n\'est pas l\'étape du circuit');
    });
  });
}

/// La recherche du tableau (hint « Rechercher… ») : filtre le registre sur un nom.
Future<void> chercherTableau(WidgetTester t, String ref) async {
  await t.enterText(find.byWidgetPredicate((w) => w is TextField && (w.decoration?.hintText ?? '').startsWith('Rechercher')).first, ref);
  await t.pump(const Duration(milliseconds: 500));
}
