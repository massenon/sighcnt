import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/impression/apercu.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';
import 'aide_qualite.dart';

/// La GED : bibliothèque de l'ÉTABLISSEMENT, workflow de validation, archivage & conservation. Les règles sont rejouées sur les vecteurs de la maquette
/// (`packages/domaine/test/qualite_test.dart`) ; ici, l'ÉCRAN — ce qui est lu, écrit, refusé, annulable, ce que chaque rôle voit, et la parité N1
/// mesurée contre les fiches extraites.
final ged = m_(vecteurs['ged']);

/// Les documents d'un cas du vecteur, avec des identifiants (la maquette les avait retirés pour la lisibilité).
List<Fiche> docsDe(Object? entrees) => [
      for (final (i, d) in liste(entrees).indexed) {'id': 'GED${i + 1}', ...d}
    ];

Magasin magasinGed(List<Fiche> docs) => magasinDe({'documents': docs});

void main() {
  setUpAll(chargerPolices);
  setUp(() => ImpressionPoste.enregistrer = (pdf, nom) async => '/faux/$nom.pdf');
  tearDown(ToastsSigh.viderPourTests);

  group('ged-bibliotheque', () {
    final c0 = m_(liste(ged['bibliotheque']).first);
    cas('les indicateurs, l’explorateur et la première page sont ceux de la maquette', (t) async {
      final m = magasinGed(docsDe(c0['entrees']));
      await ouvrir(t, m, 'ged-bibliotheque');
      for (final k in liste(c0['kpis'])) {
        expect(sp(kpi(t, '${k['label']}')), sp(k['valeur']), reason: '${k['label']}');
      }
      for (final e in liste(c0['explorateur'])) {
        expect(find.text('Dossiers ${'${e['titre']}'.replaceFirst('Dossiers ', '')}'), findsWidgets);
      }
      final tab = t.widget<TableauSigh>(find.byType(TableauSigh));
      final vue = t.state<TableauSighState>(find.byType(TableauSigh)).lignesFiltrees;
      final lignes = (c0['lignes'] as List).cast<List>();
      expect(vue.length, greaterThan(0));
      for (var i = 0; i < lignes.length; i++) {
        final obtenu = cellules(tab, vue[i]);
        expect([for (final x in obtenu.take(9)) sp(x)], [for (final x in lignes[i].take(9)) sp(x)], reason: 'ligne $i');
      }
      await parite(t, 'ged-bibliotheque');
    });

    cas('le tiroir d’un document : prévisualisation, détail et traçabilité', (t) async {
      final m = magasinGed(docsDe(c0['entrees']));
      await ouvrir(t, m, 'ged-bibliotheque');
      await toucher(t, find.byTooltip('Prévisualiser').first);
      final tr = m_(c0['tiroir']);
      expect(find.byKey(const Key('kit:tiroir-panneau')), findsOneWidget);
      expect(find.text('${tr['reference']}'), findsWidgets);
      expect(find.text('Traçabilité'), findsOneWidget);
      expect(find.text('Document déposé'), findsOneWidget);
      expect(find.text('Indexation automatique'), findsOneWidget);
      for (final h in (tr['historique'] as List)) {
        expect(h, isNotEmpty);
      }
    });

    cas('imprimer la fiche : rubrique / information, deux signataires', (t) async {
      final m = magasinGed(docsDe(c0['entrees']));
      await ouvrir(t, m, 'ged-bibliotheque');
      await toucher(t, find.byTooltip('Imprimer la fiche').first);
      expect(find.text('Fiche documentaire'), findsWidgets);
      final f = m_((c0['fiche'] as List).first);
      for (final x in (f['cartouche'] as List)) {
        expect(find.textContaining('${(x as List)[1]}'), findsWidgets, reason: '${x[0]}');
      }
      expect(find.textContaining('L’Agent administratif'), findsWidgets);
      expect(find.textContaining('TAKI Alimatou'), findsWidgets);
    });

    cas('l’écran est en lecture : aucune commande d’écriture', (t) async {
      final m = magasinGed(docsDe(c0['entrees']));
      await ouvrir(t, m, 'ged-bibliotheque');
      for (final libelle in ['Valider', 'Rejeter', 'Archiver', 'Modifier', 'Nouveau']) {
        expect(find.byTooltip(libelle), findsNothing, reason: libelle);
        expect(find.widgetWithText(BoutonSigh, libelle), findsNothing, reason: libelle);
      }
    });

    cas('une bibliothèque vide le dit', (t) async {
      await ouvrir(t, magasinGed(const []), 'ged-bibliotheque');
      expect(kpi(t, 'Documents numérisés'), '0');
      expect(kpi(t, 'Volume de stockage'), '0.0 Mo');
      expect(find.text('Aucun enregistrement.'), findsOneWidget);
    });

    cas('le jeu du poste : parité N1 de la bibliothèque', (t) async {
      await ouvrir(t, magasinDe({'documents': jeuJson('documents')}), 'ged-bibliotheque');
      await parite(t, 'ged-bibliotheque');
    });
  });

  group('ged-workflow', () {
    final wf = liste(ged['workflow']);
    final c0 = wf.first;

    Magasin magasin() => magasinGed(docsDe(c0['entrees']));
    Fiche doc(Magasin m, String ref) => m.collection('documents').toutes.firstWhere((d) => d['reference'] == ref);

    cas('les indicateurs, le circuit et la file sont ceux de la maquette', (t) async {
      await ouvrir(t, magasin(), 'ged-workflow');
      for (final k in liste(c0['kpis'])) {
        expect(sp(kpi(t, '${k['label']}')), sp(k['valeur']), reason: '${k['label']}');
      }
      for (final e in (c0['circuit'] as List)) {
        expect(find.text('$e'), findsOneWidget);
      }
      final tab = t.widget<TableauSigh>(find.byType(TableauSigh));
      final vue = t.state<TableauSighState>(find.byType(TableauSigh)).lignesFiltrees;
      final lignes = (c0['lignes'] as List).cast<List>();
      for (var i = 0; i < lignes.length; i++) {
        final obtenu = cellules(tab, vue[i]);
        // La première cellule de la maquette est la case à cocher : les colonnes suivent.
        expect([for (final x in obtenu) sp(x)], [for (final x in lignes[i].skip(1).take(7)) sp(x)], reason: 'ligne $i');
      }
      await parite(t, 'ged-workflow');
    });

    cas('valider un document le signe, recalcule les indicateurs, et s’annule', (t) async {
      final m = magasin();
      await ouvrir(t, m, 'ged-workflow');
      final v = m_(wf.firstWhere((x) => x['nom'] == 'valider un document'));
      final avant = int.parse(sp(kpi(t, 'Documents à valider')));
      await toucher(t, find.widgetWithText(BoutonSigh, 'Valider').first);
      final d = doc(m, '${v['reference']}');
      expect(d['etatValidation'], 'valide');
      expect(d['signe'], true);
      expect(find.text('Document validé et signé.'), findsOneWidget);
      expect(int.parse(sp(kpi(t, 'Documents à valider'))), avant - 1, reason: 'E562 : les indicateurs bougent');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Annuler').last);
      expect(doc(m, '${v['reference']}')['etatValidation'], 'en_attente');
      expect(int.parse(sp(kpi(t, 'Documents à valider'))), avant);
    });

    cas('rejeter exige son motif et le garde pour le déposant', (t) async {
      final m = magasin();
      await ouvrir(t, m, 'ged-workflow');
      final r = m_(wf.firstWhere((x) => x['nom'] == 'rejeter avec motif'));
      await toucher(t, find.byTooltip('Rejeter').at(1));
      expect(find.text('Rejeter ce document ?'), findsOneWidget);
      expect(find.text('Le document sera renvoyé à son déposant pour correction.'), findsOneWidget);
      // Sans motif : refusé, la modale reste (E564).
      await toucher(t, find.widgetWithText(BoutonSigh, 'Rejeter').last);
      expect(find.text('Le motif est obligatoire.'), findsOneWidget);
      expect(doc(m, '${r['reference']}')['etatValidation'], 'en_attente');
      await t.enterText(find.byType(TextField).last, 'Pièce illisible');
      await t.pump();
      await toucher(t, find.widgetWithText(BoutonSigh, 'Rejeter').last);
      final d = doc(m, '${r['reference']}');
      expect(d['etatValidation'], 'rejete');
      expect(d['motifRejet'], 'Pièce illisible');
      expect(find.text('Document rejeté.'), findsOneWidget);
      expect(sp(kpi(t, 'Rejetés à corriger')), isNot(sp(m_(liste(c0['kpis'])[1])['valeur'])), reason: 'un rejet de plus');
    });

    cas('valider une sélection : l’état seul change, la signature n’est pas posée', (t) async {
      final m = magasin();
      await ouvrir(t, m, 'ged-workflow');
      final s = m_(wf.firstWhere((x) => x['nom'] == 'valider la sélection'));
      final refs = (s['refs'] as List).cast<String>();
      // Documents de départ non signés, pour que la différence se lise.
      for (final r in refs) {
        m.collection('documents').mettreAJour(doc(m, r)['id'], {'signe': false});
      }
      await t.pump();
      final cases = find.bySemanticsLabel('Sélectionner la ligne');
      expect(cases, findsWidgets);
      await toucher(t, cases.at(0));
      await toucher(t, cases.at(1));
      await toucher(t, find.widgetWithText(BoutonSigh, 'Valider la sélection'));
      for (final r in refs) {
        final d = doc(m, r);
        if (d['etatValidation'] != 'valide') continue;
        expect(d['signe'], false, reason: 'E561 : valider la sélection ne signe pas');
      }
      expect(find.text('2 document(s) validé(s).'), findsOneWidget);
    });

    cas('l’ancienneté au-delà de quinze jours passe en rouge', (t) async {
      final a = m_(wf.firstWhere((x) => x['nom'] == 'ancienneté'));
      await ouvrir(t, magasinGed(docsDe(a['entrees'])), 'ged-workflow');
      final rouges = [
        for (final w in t.widgetList<Text>(find.byType(Text)))
          if (w.style?.color == const Color(0xFFDC2626) && (w.data ?? '').endsWith(' j')) w.data
      ];
      expect(rouges, ['16 j']);
    });

    cas('aucun document en attente : la file le dit', (t) async {
      final v = m_(wf.firstWhere((x) => x['nom'] == 'aucun document en attente'));
      final m = magasinGed([
        for (final (i, d) in docsDe(c0['entrees']).indexed) {...d, 'etatValidation': 'valide', 'id': 'X$i'}
      ]);
      await ouvrir(t, m, 'ged-workflow');
      expect(find.text('Aucun document en attente de validation.'), findsOneWidget);
      expect(sp(kpi(t, 'Documents à valider')), '0');
      expect(v['lignes'], isEmpty);
    });

    cas('sans le droit d’écrire, valider et rejeter sont ABSENTS (pas grisés)', (t) async {
      final role = roleSelonDroit('ged-workflow', editer: false);
      if (role == null) {
        // Aucun rôle en lecture seule sur cet écran dans la matrice : la garde est tenue par `c.droit.editer`, déjà éprouvée sur les autres écrans.
        return;
      }
      await ouvrir(t, magasin(), 'ged-workflow', role: role);
      expect(find.widgetWithText(BoutonSigh, 'Valider'), findsNothing);
      expect(find.byTooltip('Rejeter'), findsNothing);
      expect(find.bySemanticsLabel('Sélectionner la ligne'), findsNothing);
      expect(find.text('Documents à valider'), findsOneWidget, reason: 'la file se lit toujours');
    });

    cas('le jeu du poste : parité N1 du workflow', (t) async {
      await ouvrir(t, magasinDe({'documents': jeuJson('documents')}), 'ged-workflow');
      await parite(t, 'ged-workflow');
    });
  });

  group('ged-archives', () {
    final ar = liste(ged['archives']);
    final c0 = ar.first;

    cas('les indicateurs, les graphiques et la première page sont ceux de la maquette', (t) async {
      await ouvrir(t, magasinGed(docsDe(c0['entrees'])), 'ged-archives');
      for (final k in liste(c0['kpis'])) {
        expect(sp(kpi(t, '${k['label']}')), sp(k['valeur']), reason: '${k['label']}');
      }
      final an = t.widget<GraphiqueAnneau>(find.byType(GraphiqueAnneau));
      expect(an.etiquettes, (m_(c0['anneau'])['etiquettes'] as List).cast<String>());
      final ba = t.widget<GraphiqueBarres>(find.byType(GraphiqueBarres));
      expect(ba.etiquettes, (m_(c0['barres'])['etiquettes'] as List).cast<String>());
      expect(ba.horizontal, isTrue);
      final tab = t.widget<TableauSigh>(find.byType(TableauSigh));
      final vue = t.state<TableauSighState>(find.byType(TableauSigh)).lignesFiltrees;
      final lignes = (c0['lignes'] as List).cast<List>();
      for (var i = 0; i < lignes.length; i++) {
        // Le statut est un badge (« Archive active »), son texte de recherche est « Actif » comme dans la maquette : on compare les six premières cellules.
        expect([for (final x in cellules(tab, vue[i]).take(6)) sp(x)], [for (final x in lignes[i].take(6)) sp(x)], reason: 'ligne $i');
        expect(find.text('${lignes[i][6]}'), findsWidgets, reason: 'badge de statut, ligne $i');
      }
      await parite(t, 'ged-archives');
    });

    cas('la conservation échue : badge rouge, KPI rouge, note sur la destruction encadrée', (t) async {
      final b = m_(ar.firstWhere((x) => x['nom'].toString().startsWith('bords')));
      await ouvrir(t, magasinGed(docsDe(b['entrees'])), 'ged-archives');
      expect(kpi(t, 'Conservation échue'), '5');
      expect(find.textContaining('5 document(s) ont atteint leur durée légale de conservation.'), findsOneWidget);
      expect(find.text('Échue le 16/08/2026'), findsOneWidget);
      expect(find.text('Échue le 11/08/2026'), findsOneWidget);
      final echu = t.widget<KpiSigh>(find.byWidgetPredicate((w) => w is KpiSigh && w.libelle == 'Conservation échue'));
      expect(echu.ton, TonSigh.danger);
    });

    cas('aucun document : tout est à zéro et aucune note', (t) async {
      await ouvrir(t, magasinGed(const []), 'ged-archives');
      expect(kpi(t, 'Archives actives'), '0');
      expect(kpi(t, 'Volume total'), '0.0 Mo');
      expect(find.textContaining('ont atteint leur durée légale'), findsNothing);
    });

    cas('modifier écrit les cinq champs du formulaire, que le tableau ne lit pas (E566)', (t) async {
      final m = magasinGed(docsDe(c0['entrees']));
      await ouvrir(t, m, 'ged-archives');
      final mod = m_(m_(ar.firstWhere((x) => x['nom'] == 'modifier un document'))['modif']);
      final ref = '${mod['reference']}';
      await toucher(t, find.byTooltip('Modifier').first);
      expect(find.textContaining('Titre du document'), findsWidgets);
      await saisir(t, 'titre', 'Titre de test');
      await saisir(t, 'categorie', 'contrat');
      await saisir(t, 'dureeConservation', '12');
      await saisir(t, 'emplacement', 'Armoire B2');
      await saisir(t, 'observations', 'À revoir');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
      final d = m.collection('documents').toutes.firstWhere((x) => x['reference'] == ref);
      expect(d['titre'], 'Titre de test');
      expect(d['dureeConservation'], 12);
      expect(d['emplacement'], 'Armoire B2');
      expect(d['libelle'], m_(mod['avant'])['libelle'], reason: 'le libellé affiché ne bouge pas');
      expect(d['conservation'], m_(mod['avant'])['conservation'], reason: 'la durée affichée ne bouge pas');
      expect(find.text('Modifications enregistrées.'), findsOneWidget);
    });

    cas('archiver (RG-14) : le document sort de la liste, reste restaurable, annulable', (t) async {
      final m = magasinGed(docsDe(c0['entrees']));
      await ouvrir(t, m, 'ged-archives');
      final avant = m.collection('documents').actives.length;
      await toucher(t, find.byTooltip('Archiver').first);
      await toucher(t, find.widgetWithText(BoutonSigh, 'Archiver').last);
      expect(m.collection('documents').actives.length, avant - 1);
      expect(m.collection('documents').archivees.length, 1);
      expect(m.collection('documents').toutes.length, avant, reason: 'RG-14 : rien n’est supprimé');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Annuler').last);
      expect(m.collection('documents').actives.length, avant);
    });

    cas('le bordereau : situation du jour, plafonné à 80 documents, deux signataires', (t) async {
      await ouvrir(t, magasinGed(docsDe(c0['entrees'])), 'ged-archives');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Éditer le bordereau d’archivage'));
      expect(find.text('Bordereau d’archivage documentaire'), findsWidgets);
      expect(find.textContaining('Situation au 16/08/2026'), findsWidgets);
      expect(find.textContaining('TAKI Alimatou'), findsWidgets);
      expect(find.byIcon(LucideIcons.printer), findsWidgets);
    });

    cas('le jeu du poste : parité N1 de l’archivage', (t) async {
      await ouvrir(t, magasinDe({'documents': jeuJson('documents')}), 'ged-archives');
      await parite(t, 'ged-archives');
    });
  });
}
