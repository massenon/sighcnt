import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';
import 'm11_aide.dart';

/// M11 — bulletins, validation de la Direction, heures supplémentaires, avances, prêts-études : les valeurs attendues sont celles que les écrans RÉELS de
/// la maquette ont affichées (pilote `vecteurs-paie.js`, horloge au 30/10/2026 10 h). Les gestes (génération, validation du lot, déclaration, avance, prêt)
/// sont accomplis par les boutons ; la fiche écrite est comparée à celle que la maquette a écrite, champ par champ.
void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);
  final v = vecteurs();
  final g = mm(v['gestes']);
  final paie = mm(g['paie']);

  /// Les champs de la fiche écrite comparés à ceux de la maquette (les champs techniques `id`, `statut`, `_…` sont laissés de côté).
  void memeFiche(Map<String, Object?> obtenu, Map<String, Object?> attendu, String ctx, {Set<String> sauf = const {}}) {
    for (final e in attendu.entries) {
      if (e.key == 'id' || e.key == 'statut' || e.key.startsWith('_') || sauf.contains(e.key)) continue;
      expect(obtenu[e.key], e.value, reason: '$ctx · ${e.key}');
    }
  }

  group('m11-bulletins', () {
    cas('registre vide : quatre KPI à zéro, aucune ligne ; la note dit d’où viennent les bulletins', (t) async {
      await ouvrir(t, magasin(), 'm11-bulletins');
      expect(kpisAffiches(t), kpisVecteur(mm(paie['bulletinsVide'])['kpis']));
      expect(textes(t), contains('Les bulletins sont produits par le moteur de calcul : ils ne sont pas modifiables directement. Toute correction passe par la reprise du calcul de la période.'));
      expect(find.text('Nouveau'), findsNothing);
    });

    cas('88 bulletins (octobre et mai) : KPI, première page triée par période décroissante, filtre « Période » = écran réel', (t) async {
      final m = magasin();
      poserBulletins(m);
      await ouvrir(t, m, 'm11-bulletins');
      final b = mm(paie['bulletins']);
      expect(kpisAffiches(t), kpisVecteur(b['kpis']));
      final lignes = cellulesVecteur(b['table']);
      for (final cel in lignes.take(15)) {
        for (final x in cel.skip(1).take(10).where((x) => x.isNotEmpty)) {
          expect(textes(t), contains(x), reason: 'ligne ${cel[1]} : $x');
        }
      }
      expect(textes(t).any((x) => x.contains('Affichage de 1 à 15 sur 88 enregistrements')), true);
      await filtrer(t, 'Période', 'Mai 2026');
      expect(textes(t).any((x) => x.contains('Affichage de 1 à 15 sur 44 enregistrements')), true);
      expect(mm(b['filtresResultats'])['Période|Mai 2026'], hasLength(15));
      await filtrer(t, 'Période', 'Janvier 2026');
      expect(find.text('Aucun résultat pour cette recherche.'), findsOneWidget);
    });

    cas('le tiroir d’un bulletin : gains, retenues avec le DÉTAIL ORTB (tiret hors du mois), « Imprimer » seul — ni Modifier ni Archiver', (t) async {
      final m = magasin();
      poserBulletins(m);
      await ouvrir(t, m, 'm11-bulletins');
      final tir = mm(mm(paie['bulletins'])['tiroir']);
      await toucher(t, find.text('BP-00044'));
      await t.pumpAndSettle();
      final tt = textes(t);
      for (final tb in lm(tir['tables'])) {
        for (final l in tb['lignes'] as List) {
          for (final cel in (l as List)) {
            expect(tt, contains('$cel'), reason: 'cellule « $cel »');
          }
        }
      }
      expect(tt, contains('Redevance ORTB / Radio'));
      expect(find.text('Imprimer'), findsOneWidget);
      expect(find.text('Modifier'), findsNothing);
      expect(find.text('Archiver'), findsNothing, reason: '`readonly` : un bulletin émis ne s’efface pas, même pour l’administrateur');
      await toucher(t, find.text('Imprimer'));
      await t.pumpAndSettle();
      final piece = mm(tir['piece']);
      final pt = textes(t);
      expect(pt, contains('Bulletin de paie'));
      for (final tb in lm(piece['tables'])) {
        for (final l in tb['lignes'] as List) {
          for (final cel in (l as List)) {
            if ('$cel'.isEmpty) continue;
            expect(pt, contains('$cel'), reason: 'bulletin imprimé : « $cel »');
          }
        }
      }
    });

    cas('un bulletin stocké AVANT la correction (sans détail ORTB) : « Redevance ORTB — Non applicable » à l’impression, comme la maquette — rien n’est inventé', (t) async {
      final m = magasin();
      final b = {...bulletinsVecteur().first}..remove('detailOrtb');
      m.collection('bulletins').inserer({...b, 'statut': 'actif'});
      await ouvrir(t, m, 'm11-bulletins');
      await toucher(t, find.text('${b['reference']}'));
      await t.pumpAndSettle();
      expect(textes(t), contains('Redevance ORTB'));
      expect(find.text('Redevance ORTB / Radio'), findsNothing);
      await toucher(t, find.text('Imprimer'));
      await t.pumpAndSettle();
      expect(textes(t), contains('Non applicable'));
    });
  });

  group('m11-validation', () {
    cas('aucun bulletin : état vide, KPI à zéro, et le lien mène au calcul', (t) async {
      await ouvrir(t, magasin(), 'm11-validation');
      final vide = mm(paie['validationVide']);
      expect(kpisAffiches(t), kpisVecteur(vide['kpis']));
      expect(find.text('Aucun bulletin généré.'), findsOneWidget);
      expect(find.text('Lancer le calcul de la paie puis générer les bulletins avant de les soumettre à validation.'), findsOneWidget);
      await toucher(t, find.text('Calculer la paie'));
      await t.pumpAndSettle();
      expect(find.text('Calcul de la paie'), findsWidgets);
    });

    cas('deux lots : KPI et tableau = écran réel ; « Valider le lot » demande confirmation, écrit l’agent connecté (E687), pose l’écriture de paie et s’annule', (t) async {
      final m = magasin();
      poserBulletins(m);
      await ouvrir(t, m, 'm11-validation');
      final val = mm(paie['validation']);
      expect(kpisAffiches(t), kpisVecteur(val['kpis']));
      final lignes = cellulesVecteur(val['table']);
      for (final cel in lignes) {
        for (final x in cel.where((x) => x.isNotEmpty && x != 'Valider le lot')) {
          expect(textes(t), contains(x), reason: 'lot ${cel[0]} : $x');
        }
      }
      expect(find.text('Valider le lot'), findsNWidgets(2));
      // le lot de mai (première ligne de la maquette)
      await toucher(t, find.text('Valider le lot').first);
      await t.pumpAndSettle();
      expect(find.text('Valider la paie de Mai 2026 ?'), findsOneWidget);
      expect(find.textContaining('journalisée au nom de l’agent connecté'), findsOneWidget);
      await toucher(t, find.text('Valider la paie'));
      await t.pumpAndSettle();
      final col = m.collection('bulletins');
      final mai = col.actives.where((b) => b['periode'] == 'Mai 2026').toList();
      final agent = m.utilisateur;
      expect(agent, isNotEmpty);
      expect(mai.length, 44);
      expect(mai.every((b) => b['statutBulletin'] == 'valide' && b['validePar'] == agent && b['dateValidation'] == '2026-10-30' && b['ecritureNumero'] == 'SAL-2026-00128'), true,
          reason: 'validePar est l’agent connecté, plus un nom écrit en dur');
      expect(col.actives.where((b) => b['periode'] == 'Octobre 2026').every((b) => b['statutBulletin'] == 'a_valider'), true, reason: 'l’autre lot reste à valider');
      expect(find.text('Paie de Mai 2026 validée par $agent.'), findsOneWidget);
      expect(find.text('44 bulletin(s) autorisé(s) à la diffusion ; écriture SAL-2026-00128 posée en brouillon.'), findsOneWidget);
      expect(find.text('Valider le lot'), findsOneWidget, reason: 'le lot validé n’offre plus la commande');
      expect(find.text('Diffuser'), findsOneWidget, reason: 'le lot validé offre la diffusion');
      expect(kpisAffiches(t)['Bulletins validés'], '44');
      expect(kpisAffiches(t)['Bulletins à valider'], '44');
      // l'écriture de paie : les lignes de la maquette (compte, libellé, montants), en brouillon, équilibrées
      final posees = m.collection('ecritures').actives.where((e) => e['pieceId'] == 'PAIE-Mai 2026').toList();
      final attendues = lm(mm(mm(mm(paie['validation'])['ecart'])['inserts'])['ecritures']);
      String cle(Map<String, Object?> f) => '${f['numero']}|${f['compte']}|${f['libelle']}|${nombreOuZero(f['debit']).round()}|${nombreOuZero(f['credit']).round()}|${f['statut']}|${f['centreCout']}';
      expect({for (final f in posees) cle(f)}, {for (final a in attendues) cle(a)});
      expect(posees.fold<num>(0, (a, f) => a + nombreOuZero(f['debit'])), posees.fold<num>(0, (a, f) => a + nombreOuZero(f['credit'])), reason: 'RG-10');
      // « Annuler » du message : l'état d'avant revient, l'écriture sort du journal (archivée, jamais supprimée)
      await toucher(t, find.text('Annuler').last);
      expect(col.actives.where((b) => b['periode'] == 'Mai 2026').every((b) => b['statutBulletin'] == 'a_valider'), true);
      expect(m.collection('ecritures').actives.where((e) => e['pieceId'] == 'PAIE-Mai 2026'), isEmpty);
      expect(m.collection('ecritures').toutes.where((e) => e['pieceId'] == 'PAIE-Mai 2026').length, attendues.length, reason: 'rien n’est supprimé (RG-14)');
      expect(col.actives.length, 88, reason: 'rien n’est supprimé');
    });

    cas('A2 : celui qui a généré ne valide pas (refus nommé, rien d’écrit) ; un lot déséquilibré est refusé avant toute écriture (RG-10) ; un second lot de la même période aussi', (t) async {
      final m = magasin();
      poserBulletins(m);
      await ouvrir(t, m, 'm11-validation');
      final sep = mm(paie['separation']);
      String toast(Object? x) => sp((mm(x)['toasts'] as List).single as String);
      // le lot de mai a été généré par la personne connectée : refus nommé
      final col = m.collection('bulletins');
      for (final b in col.actives.where((b) => b['periode'] == 'Mai 2026').toList()) {
        col.mettreAJour(b['id'], {'genereePar': m.utilisateur});
      }
      await toucher(t, find.text('Valider le lot').first);
      await t.pumpAndSettle();
      await toucher(t, find.text('Valider la paie'));
      await t.pumpAndSettle();
      expect(find.text('Validation refusée.'), findsOneWidget);
      expect(find.textContaining('Séparation des tâches : la paie de Mai 2026 a été générée par ${m.utilisateur}'), findsOneWidget);
      expect(toast(sep['memePersonne']), startsWith('Validation refusée. Séparation des tâches : la paie de Septembre 2026 a été générée par'));
      expect(col.actives.where((b) => b['periode'] == 'Mai 2026').every((b) => b['statutBulletin'] == 'a_valider'), true);
      expect(m.collection('ecritures').actives.where((e) => '${e['pieceId']}'.startsWith('PAIE-')), isEmpty);
      await t.pump(const Duration(seconds: 10));
      // un lot dont le net a été trafiqué : l'écart est dit, rien n'est validé
      for (final b in col.actives.where((b) => b['periode'] == 'Mai 2026').toList()) {
        col.mettreAJour(b['id'], {'genereePar': 'Autre agent'});
      }
      final premier = col.actives.firstWhere((b) => b['periode'] == 'Mai 2026');
      col.mettreAJour(premier['id'], {'net': nombreOuZero(premier['net']) + 777});
      await toucher(t, find.text('Valider le lot').first);
      await t.pumpAndSettle();
      await toucher(t, find.text('Valider la paie'));
      await t.pumpAndSettle();
      expect(find.textContaining('n’est pas équilibrée (RG-10)'), findsOneWidget);
      expect(textes(t).any((x) => x.contains('écart ${sp(money(777))}')), true);
      expect(col.actives.where((b) => b['periode'] == 'Mai 2026').every((b) => b['statutBulletin'] == 'a_valider'), true);
      expect(m.collection('ecritures').toutes.where((e) => '${e['pieceId']}'.startsWith('PAIE-')), isEmpty);
      await t.pump(const Duration(seconds: 10));
      // un lot de la même période a déjà son écriture : refus nommé
      col.mettreAJour(premier['id'], {'net': premier['net']});
      m.collection('ecritures').inserer({'statut': 'brouillon', 'pieceId': 'PAIE-Mai 2026', 'numero': 'SAL-2026-00128', 'compte': '422000', 'debit': 0, 'credit': 1, 'date': '2026-10-30'}, prefixe: 'ECR');
      await toucher(t, find.text('Valider le lot').first);
      await t.pumpAndSettle();
      await toucher(t, find.text('Valider la paie'));
      await t.pumpAndSettle();
      expect(find.textContaining('La paie de Mai 2026 a déjà son écriture (SAL-2026-00128)'), findsOneWidget);
      expect(col.actives.where((b) => b['periode'] == 'Mai 2026').every((b) => b['statutBulletin'] == 'a_valider'), true);
    });

    cas('B6 : « Diffuser » rend un lot validé aux agents (statut Diffusé), annulable ; la commande est ABSENTE sans le droit d’écrire', (t) async {
      final m = magasin();
      poserBulletins(m);
      final col = m.collection('bulletins');
      for (final b in col.actives.where((b) => b['periode'] == 'Mai 2026').toList()) {
        col.mettreAJour(b['id'], {'statutBulletin': 'valide'});
      }
      await ouvrir(t, m, 'm11-validation');
      expect(find.text('Diffuser'), findsOneWidget);
      expect(find.text('Valider le lot'), findsOneWidget, reason: 'octobre reste à valider');
      expect(textes(t), contains('Validé'));
      await toucher(t, find.text('Diffuser'));
      await t.pumpAndSettle();
      expect(find.text('Diffuser la paie de Mai 2026 ?'), findsOneWidget);
      await toucher(t, find.text('Diffuser').last);
      await t.pumpAndSettle();
      final mai = col.actives.where((b) => b['periode'] == 'Mai 2026').toList();
      expect(mai.every((b) => b['statutBulletin'] == 'diffuse' && b['diffusePar'] == m.utilisateur && b['dateDiffusion'] == '2026-10-30'), true);
      expect(find.text('Paie de Mai 2026 diffusée.'), findsOneWidget);
      expect(find.text('Diffuser'), findsNothing);
      expect(textes(t), contains('Diffusé'));
      await toucher(t, find.text('Annuler').last);
      expect(col.actives.where((b) => b['periode'] == 'Mai 2026').every((b) => b['statutBulletin'] == 'valide'), true);
      // sans le droit d'écrire sur l'écran, la commande n'existe pas
      await ouvrir(t, m, 'm11-validation', role: 'direction', nav: navAvecDroit('direction', 'm11-validation', [1, 0, 0]));
      expect(find.text('Diffuser'), findsNothing);
      expect(find.text('Valider le lot'), findsNothing);
    });

    cas('« Valider la paie » refusé au dialogue : rien ne change', (t) async {
      final m = magasin();
      poserBulletins(m);
      await ouvrir(t, m, 'm11-validation');
      await toucher(t, find.text('Valider le lot').first);
      await t.pumpAndSettle();
      await toucher(t, find.text('Annuler').last);
      await t.pumpAndSettle();
      expect(m.collection('bulletins').actives.every((b) => b['statutBulletin'] == 'a_valider'), true);
    });

    cas('droits : la Direction valide (surcharge d’écran) ; sans le droit d’écrire, « Valider le lot » est ABSENT et le journal reste offert', (t) async {
      final m = magasin();
      poserBulletins(m);
      await ouvrir(t, m, 'm11-validation', role: 'direction');
      expect(find.text('Valider le lot'), findsNWidgets(2), reason: 'la validation de la paie est le geste de la Direction : signer n’est pas saisir, l’écran lui est accordé nommément');
      await ouvrir(t, m, 'm11-validation', role: 'comptable');
      expect(find.text('Valider le lot'), findsNothing, reason: 'A2 : le comptable génère, il ne valide pas (écran en lecture sur sa fiche RBAC)');
      expect(find.byTooltip('Journal de paie'), findsWidgets, reason: 'il lit le lot et imprime le journal');
      await ouvrir(t, m, 'm11-calcul', role: 'comptable');
      expect(find.text('Générer les bulletins'), findsOneWidget, reason: 'le comptable garde la génération des bulletins');
      // la même Direction, réduite à la LECTURE de l'écran (matrice modifiée) : la commande disparaît, le journal reste offert
      await ouvrir(t, m, 'm11-validation', role: 'direction', nav: navAvecDroit('direction', 'm11-validation', [1, 0, 0]));
      expect(find.text('Valider le lot'), findsNothing);
      expect(find.byTooltip('Journal de paie'), findsWidgets);
      expect(find.text('Validation de la paie'), findsWidgets);
      // un profil qui n'a pas l'écran : il ne s'ouvre pas
      await ouvrir(t, m, 'm11-validation', role: 'dm');
      expect(find.text('Valider le lot'), findsNothing);
    });

    cas('le journal de paie du lot (mai) : cartouche, lignes triées par agent, totaux refaits, « Bon à payer »', (t) async {
      final m = magasin();
      poserBulletins(m);
      await ouvrir(t, m, 'm11-validation');
      await toucher(t, find.byTooltip('Journal de paie').first);
      await t.pumpAndSettle();
      final piece = mm(mm(paie['validation'])['journal']);
      final tt = textes(t);
      expect(tt, contains('Journal de paie — validation'));
      for (final c in lm([for (final x in piece['cartouche'] as List) {'c': x}])) {
        final cel = c['c'] as List;
        if (cel[0] == 'Date d’édition') continue;
        expect(tt, contains(sp('${cel[0]} : ${cel[1]}')), reason: 'cartouche ${cel[0]}');
      }
      final pied = (mm((piece['tables'] as List).first)['pied'] as List).cast<String>();
      for (final x in pied.where((x) => x.isNotEmpty && x != 'TOTAL')) {
        expect(tt, contains(x), reason: 'total $x');
      }
      expect(tt, contains('Bon à payer'));
    });
  });

  group('m11-heures-sup', () {
    cas('vingt déclarations : KPI et première ligne = écran réel ; filtre « Période »', (t) async {
      await ouvrir(t, magasin(), 'm11-heures-sup');
      final l = mm(mm(g['heuresSup'])['lecture']);
      expect(kpisAffiches(t), kpisVecteur(l['kpis']));
      expect(libellesKpi(t), ['Déclarations', 'Heures déclarées', 'Montant à payer', 'En attente de validation']);
      for (final x in cellulesVecteur(l['table']).first.skip(1).where((x) => x.isNotEmpty)) {
        expect(textes(t), contains(x), reason: 'première ligne : $x');
      }
      expect(find.text('Tous les déclarations'), findsOneWidget);
    });

    cas('« Nouveau » : formulaire de la maquette, valeurs initiales, refus du formulaire incomplet, puis la fiche écrite = celle de la maquette', (t) async {
      final m = magasin();
      await ouvrir(t, m, 'm11-heures-sup');
      final hs = mm(g['heuresSup']);
      await toucher(t, find.text('Nouveau'));
      await t.pumpAndSettle();
      for (final l in (hs['formulaire'] as List).cast<String>()) {
        expect(textes(t).any((x) => x == l || x == l.replaceAll(' *', '') || x.startsWith(l.replaceAll(' *', ''))), true, reason: 'champ « $l »');
      }
      final n0 = m.collection('heuresSup').actives.length;
      await toucher(t, find.text('Créer'));
      expect(find.text('Le formulaire comporte des erreurs.'), findsOneWidget);
      expect(m.collection('heuresSup').actives.length, n0, reason: 'rien n’est écrit sur un formulaire incomplet');
      final a = mm(mm(hs['creation'])['agent']);
      await choisir(t, 'employeId', '${a['matricule']} — IDRISSOU ANIKI Baba-Toundé');
      await saisir(t, 'heures', '10');
      await saisir(t, 'majoration', '50');
      await choisir(t, 'motif', 'Urgence');
      await toucher(t, find.descendant(of: find.byKey(const Key('kit:champ:valide')), matching: find.byType(InkWell)).first);
      await toucher(t, find.text('Créer'));
      await t.pumpAndSettle();
      final f = m.collection('heuresSup').actives.first;
      final att = inserts(hs['creation'], 'heuresSup').single;
      memeFiche(f, att, 'déclaration');
      expect(f['reference'], 'HS-0021', reason: 'la série suit le registre : HS-0001 existe déjà au jeu, la première déclaration n’est PAS HS-0001 (E680)');
      expect(f['tauxHoraire'], 822);
      expect(f['montant'], 8220);
      expect(find.text('Nouveau déclaration créé.'), findsOneWidget);
      expect(kpisAffiches(t), kpisVecteur(mm(hs['creation'])['kpis']));
    });

    cas('la modification garde le NUMÉRO et recalcule le taux et le montant (E683) ; la fiche existante n’est jamais renumérotée', (t) async {
      final m = magasin();
      await ouvrir(t, m, 'm11-heures-sup');
      await toucher(t, find.text('HS-0001'));
      await t.pumpAndSettle();
      await toucher(t, find.text('Modifier'));
      await t.pumpAndSettle();
      await saisir(t, 'heures', '7');
      await toucher(t, find.text('Enregistrer'));
      await t.pumpAndSettle();
      final f = m.collection('heuresSup').actives.firstWhere((x) => x['id'] == 'HS0001');
      final patch = mm(modifs(mm(g['heuresSup'])['modification'], 'heuresSup').single['patch']);
      expect(f['heures'], patch['heures']);
      expect(f['montant'], patch['montant']);
      expect(f['reference'], 'HS-0001', reason: 'la maquette d’avant la correction renumérotait en HS-0023');
      expect(find.text('Modifications enregistrées.'), findsOneWidget);
    });

    cas('l’archivage demande un MOTIF, est annulable et ne supprime rien (RG-14) ; la déclaration quitte les KPI', (t) async {
      final m = magasin();
      await ouvrir(t, m, 'm11-heures-sup');
      final avant = m.collection('heuresSup').actives.length;
      await toucher(t, find.byTooltip('Archiver').first);
      await t.pumpAndSettle();
      expect(find.text('Archiver cet enregistrement ?'), findsOneWidget);
      await toucher(t, find.text('Archiver').last);
      await t.pumpAndSettle();
      expect(find.text('Archiver cet enregistrement ?'), findsOneWidget, reason: 'sans motif, la fenêtre reste ouverte');
      await t.enterText(find.byType(TextField).last, 'Doublon');
      await toucher(t, find.text('Archiver').last);
      await t.pumpAndSettle();
      expect(m.collection('heuresSup').actives.length, avant - 1);
      expect(m.collection('heuresSup').archivees.length, 1);
      await toucher(t, find.text('Annuler').last);
      expect(m.collection('heuresSup').actives.length, avant);
    });

    cas('le taux horaire ne dépend que du salaire de base et de la majoration (0 vaut 25 %)', (t) async {
      final m = magasin();
      await ouvrir(t, m, 'm11-heures-sup');
      final z = inserts(mm(g['heuresSup'])['creationMajorationZero'], 'heuresSup').single;
      expect(z['majoration'], 0);
      expect(z['tauxHoraire'], paiTauxHoraire(mm(g['heuresSup'])['creationMajorationZero'] is Map ? (mm(mm(g['heuresSup'])['creationMajorationZero'])['salaireBase'] as num) : 0, 25));
    });
  });

  group('m11-avances', () {
    cas('douze avances : KPI et lignes = écran réel ; la note dit que la mensualité est retenue automatiquement', (t) async {
      await ouvrir(t, magasin(), 'm11-avances');
      final l = mm(mm(g['avances'])['lecture']);
      expect(kpisAffiches(t), kpisVecteur(l['kpis']));
      for (final cel in cellulesVecteur(l['table']).take(3)) {
        for (final x in cel.skip(1).where((x) => x.isNotEmpty)) {
          expect(textes(t), contains(x), reason: 'ligne ${cel[1]} : $x');
        }
      }
      expect(textes(t), contains('La mensualité de remboursement est automatiquement retenue sur le bulletin de paie tant que l’avance n’est pas soldée.'));
    });

    cas('plus de trois mois de salaire : REFUS nommé, rien n’est écrit ; pile au plafond : accepté, mensualité arrondie', (t) async {
      final m = magasin();
      await ouvrir(t, m, 'm11-avances');
      final av = mm(g['avances']);
      final a = mm(av['refusPlafond']);
      await toucher(t, find.text('Nouveau'));
      await t.pumpAndSettle();
      await choisir(t, 'employeId', '11 — IDRISSOU ANIKI Baba-Toundé (salaire ${money(a['salaireBase'])})');
      await saisir(t, 'montant', '${(a['salaireBase'] as num) * 3 + 1}');
      await saisir(t, 'nbMensualites', '7');
      await choisir(t, 'motif', 'Frais de santé');
      final n0 = m.collection('avances').actives.length;
      await toucher(t, find.text('Créer'));
      await t.pumpAndSettle();
      expect(textes(t), contains((a['toasts'] as List).single));
      expect(find.text('Créer'), findsOneWidget, reason: 'la fenêtre reste ouverte sur un refus');
      expect(m.collection('avances').actives.length, n0);
      await saisir(t, 'montant', '${(a['salaireBase'] as num) * 3}');
      await toucher(t, find.text('Créer'));
      await t.pumpAndSettle();
      final f = m.collection('avances').actives.first;
      memeFiche(f, inserts(av['creationPlafond'], 'avances').single, 'avance au plafond');
      expect(f['mensualite'], 40714);
      expect(f['rembourse'], 0);
      expect(f['reference'], 'AVS-0013', reason: 'la série suit le registre (E680)');
    });

    cas('modifier une avance déjà en partie remboursée GARDE « remboursé » et le numéro (E683, E684) ; la mensualité se recalcule', (t) async {
      final m = magasin();
      await ouvrir(t, m, 'm11-avances');
      await toucher(t, find.text('AVS-0011'));
      await t.pumpAndSettle();
      await toucher(t, find.text('Modifier'));
      await t.pumpAndSettle();
      await saisir(t, 'nbMensualites', '4');
      await toucher(t, find.text('Enregistrer'));
      await t.pumpAndSettle();
      final f = m.collection('avances').actives.firstWhere((x) => x['id'] == 'AV0011');
      final patch = mm(modifs(mm(g['avances'])['modification'], 'avances').single['patch']);
      expect(f['nbMensualites'], patch['nbMensualites']);
      expect(f['mensualite'], patch['mensualite']);
      expect(f['rembourse'], 20000, reason: 'ce que l’agent a déjà rendu ne se remet pas à zéro');
      expect(f['reference'], 'AVS-0011');
    });

    cas('« Imprimer » : la demande d’avance — cartouche, tableau, phrase d’engagement, trois signatures', (t) async {
      await ouvrir(t, magasin(), 'm11-avances');
      await toucher(t, find.text('AVS-0009'));
      await t.pumpAndSettle();
      await toucher(t, find.text('Imprimer'));
      await t.pumpAndSettle();
      final piece = mm(mm(mm(g['avances'])['tiroir'])['piece']);
      final tt = textes(t);
      expect(tt, contains(piece['titre']));
      for (final c in lm([for (final x in piece['cartouche'] as List) {'c': x}])) {
        final cel = c['c'] as List;
        expect(tt, contains(sp('${cel[0]} : ${cel[1]}')), reason: 'cartouche ${cel[0]}');
      }
      for (final l in mm((piece['tables'] as List).first)['lignes'] as List) {
        for (final cel in (l as List)) {
          expect(tt, contains('$cel'), reason: 'tableau : $cel');
        }
      }
      expect(tt.any((x) => x.startsWith('Il est accordé à AGOSSOU Yahouza, matricule 9')), true);
      expect(tt.any((x) => x.contains('jusqu’à apurement complet.')), true);
      for (final s in lm(piece['signatures'])) {
        expect(tt, contains(s['role']));
      }
    });
  });

  group('m11-prets-etudes', () {
    cas('douze prêts : KPI et lignes = écran réel (reste dû, échéances « retenues / total »)', (t) async {
      await ouvrir(t, magasin(), 'm11-prets-etudes');
      final l = mm(mm(g['prets'])['lecture']);
      expect(kpisAffiches(t), kpisVecteur(l['kpis']));
      for (final cel in cellulesVecteur(l['table']).take(5)) {
        for (final x in cel.where((x) => x.isNotEmpty)) {
          expect(textes(t), contains(x), reason: 'ligne ${cel[0]} : $x');
        }
      }
      expect(find.text('Nouveau prêt ou avance'), findsOneWidget);
    });

    cas('le tiroir : l’échéancier calculé, une échéance par mois, la note du seul mois', (t) async {
      await ouvrir(t, magasin(), 'm11-prets-etudes');
      final tir = mm(lm(mm(g['prets'])['tiroirs'])[1]);
      await toucher(t, find.byTooltip('Consulter').at(1));
      await t.pumpAndSettle();
      final tt = textes(t);
      for (final tb in lm(tir['tables'])) {
        for (final l in tb['lignes'] as List) {
          for (final cel in (l as List)) {
            expect(tt, contains('$cel'), reason: 'échéancier : $cel');
          }
        }
      }
      expect(tt, contains('Reste à recouvrer'));
      expect(tt, contains('Chaque échéance figure au bulletin du seul mois indiqué. La porter tous les mois la prélèverait autant de fois qu’il y a de bulletins.'));
    });

    cas('création : formulaire incomplet refusé ; 100 001 F sur 3 échéances = 33 333 + 33 333 + 33 335 (le reliquat tombe sur la dernière)', (t) async {
      final m = magasin();
      await ouvrir(t, m, 'm11-prets-etudes');
      final pr = mm(g['prets']);
      await toucher(t, find.text('Nouveau prêt ou avance'));
      await t.pumpAndSettle();
      final n0 = m.collection('pretsEtudes').actives.length;
      await toucher(t, find.text('Créer'));
      expect(find.text('Le formulaire comporte des erreurs.'), findsOneWidget);
      expect(m.collection('pretsEtudes').actives.length, n0);
      await choisir(t, 'employeId', 'KINNOU A. Ganiou');
      await saisir(t, 'objet', 'Formation continue');
      await saisir(t, 'montant', '100001');
      await dater(t, 'dateAccord', 15);
      await saisir(t, 'premiereEcheance', '2026-12');
      await saisir(t, 'nbEcheances', '3');
      await saisir(t, 'autorisePar', 'TAKI Alimatou');
      await toucher(t, find.text('Créer'));
      await t.pumpAndSettle();
      final f = m.collection('pretsEtudes').actives.first;
      final att = inserts(pr['creation'], 'pretsEtudes').single;
      memeFiche(f, att, 'prêt', sauf: {'dateAccord'});
      expect(f['reference'], 'PRT-0013', reason: 'la série suit le registre : PRT-0001 existe déjà au jeu (E680)');
      expect(f['retenues'], isEmpty);
      expect('${f['dateAccord']}'.endsWith('-15'), true, reason: 'la date choisie au sélecteur');
      expect(find.text('Prêt créé.'), findsOneWidget);
      expect(kpisAffiches(t), kpisVecteur(mm(pr['creation'])['kpis']));
      await toucher(t, find.byTooltip('Consulter').first);
      await t.pumpAndSettle();
      for (final l in mm(lm(mm(pr['tiroirCree'])['tables']).first)['lignes'] as List) {
        for (final cel in (l as List)) {
          expect(textes(t), contains('$cel'), reason: 'échéancier du prêt créé : $cel');
        }
      }
    });

    cas('modifier le nombre d’échéances recalcule l’échéancier ; archiver demande un motif, ne supprime pas (RG-14) et sort le prêt des KPI', (t) async {
      final m = magasin();
      await ouvrir(t, m, 'm11-prets-etudes');
      final avant = m.collection('pretsEtudes').actives.length;
      await toucher(t, find.byTooltip('Modifier').first);
      await t.pumpAndSettle();
      await saisir(t, 'nbEcheances', '2');
      await toucher(t, find.text('Enregistrer'));
      await t.pumpAndSettle();
      expect(find.text('Modifications enregistrées.'), findsOneWidget);
      final premier = m.collection('pretsEtudes').actives.firstWhere((x) => x['nbEcheances'] == 2);
      expect(paiEcheancier(premier).length, 2);
      expect(paiEcheancier(premier).fold<num>(0, (a, e) => a + e.montant), premier['montant']);
      await toucher(t, find.byTooltip('Archiver').first);
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).last, 'Erreur de saisie');
      await toucher(t, find.text('Archiver').last);
      await t.pumpAndSettle();
      expect(m.collection('pretsEtudes').actives.length, avant - 1);
      expect(m.collection('pretsEtudes').archivees.length, 1);
      expect(m.collection('pretsEtudes').toutes.length, avant, reason: 'rien n’est supprimé');
    });

    cas('droits : sans le droit d’écrire, ni « Nouveau prêt ou avance », ni Modifier, ni Archiver ; la consultation reste offerte', (t) async {
      await ouvrir(t, magasin(), 'm11-prets-etudes', role: 'direction');
      expect(find.text('Nouveau prêt ou avance'), findsNothing);
      expect(find.byTooltip('Modifier'), findsNothing);
      expect(find.byTooltip('Archiver'), findsNothing);
      expect(find.byTooltip('Consulter'), findsWidgets);
    });
  });
}
