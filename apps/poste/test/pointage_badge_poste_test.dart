import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/mes_poste.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/sync/pont_activite.dart';
import 'package:sigh_poste/sync/transcription_mobile.dart' show PieceSync;

import 'aide_polices.dart';
import 'm14_aide.dart';
import 'rhb_aide.dart';

/// Le badge sert de POINTAGE (lot L8, Direction, 09/11/2026, Planning Q7) au poste : les règles (refus nommés, arrivée puis départ, délai, présence « à valider ») sont rejouées
/// sur les vecteurs de la maquette par `packages/domaine/test/mes_pointage_test.dart` ; ici le magasin du poste (ce qui est ÉCRIT : présence, journal, versions du
/// paramètre), l'ÉCRAN de vérification d'un badge, et le voyage des présences par le pont d'activité (hors ligne puis synchronisé).
String _nom(String role) => agentDemonstration(role, nom: donneesNav.matrice.libelle(role)).nom;

Magasin _magasin() {
  final m = magasinRhb();
  m.collection('personnel').inserer({'id': 'EMPBDG', 'statut': 'actif', 'nomComplet': 'KORA Agent', 'matricule': '777', 'fonction': 'infirmier', 'service': 'Médecine générale', 'poste': 'Infirmier'},
      prefixe: 'EMP');
  m.collection('badges').inserer({'id': 'BDGT1', 'statut': 'actif', 'numero': 'BDG-T0001-2026', 'personnelId': 'EMPBDG', 'matricule': '777', 'agent': 'KORA Agent', 'etat': 'remis', 'expireLe': '2099-12-31'},
      prefixe: 'BDG');
  m.collection('badges').inserer({'id': 'BDGT2', 'statut': 'actif', 'numero': 'BDG-T0002-2026', 'personnelId': 'EMPBDG', 'matricule': '777', 'agent': 'KORA Agent', 'etat': 'retire', 'expireLe': '2099-12-31', 'retireLe': '2026-06-01', 'motifRetrait': 'Perte'},
      prefixe: 'BDG');
  return m;
}

PointageBadgePoste _p(Magasin m, String role, DateTime Function() h) => PointageBadgePoste(m, auteur: () => _nom(role), role: role, horloge: h);

void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  group('le pointage au magasin du poste', () {
    test('arrivée, passage trop rapproché refusé, départ sur la même présence : tout est écrit « à valider », chaque passage est journalisé', () {
      final m = _magasin();
      var t = DateTime(2026, 8, 17, 8, 0);
      final p = _p(m, 'surveillant', () => t);
      final a = p.pointer('BDG-T0001-2026');
      expect([a['ok'], a['geste'], a['etat']], [true, 'arrivee', 'a_valider']);
      final pres = m.collection('presences').parId(a['presenceId'])!;
      expect([pres['employeId'], pres['date'], pres['heureArrivee'], pres['origine'], pres['badgeNumero'], pres['validationEtat'], pres['saisiPar']],
          ['EMPBDG', '2026-08-17', '08:00', 'badge', 'BDG-T0001-2026', 'a_valider', _nom('surveillant')]);
      expect(compteRh('presences', pres), isFalse, reason: 'une présence à valider ne compte pas (RG-11)');
      t = DateTime(2026, 8, 17, 8, 3);
      final trop = p.pointer('BDG-T0001-2026');
      expect([trop['ok'], trop['code']], [false, 'POINTAGE_TROP_RAPPROCHE']);
      expect(trop['geste'], 'Attendre 2 minute(s) avant de pointer de nouveau.');
      t = DateTime(2026, 8, 17, 17, 30);
      final d = p.pointer('BDG-T0001-2026');
      expect([d['ok'], d['geste'], d['presenceId']], [true, 'depart', a['presenceId']]);
      final fin = m.collection('presences').parId(a['presenceId'])!;
      expect([fin['heureDepart'], fin['departParBadge']], ['17:30', 'BDGT1']);
      expect(m.collection('presences').toutes.where((x) => x['origine'] == 'badge').length, 1, reason: 'une seule présence, arrivée et départ');
      final j = [for (final x in m.collection('audit').toutes) if (x['action'] == 'Pointage par badge') '${x['motif']}'];
      expect(j.length, 3);
      expect(j.where((x) => x.startsWith('POINTAGE_TROP_RAPPROCHE')).length, 1);
      expect(j.where((x) => x.startsWith('ARRIVEE')).length, 1);
      expect(j.where((x) => x.startsWith('DEPART')).length, 1);
    });

    test('refus nommés d\'un badge retiré, inconnu ; rôle non habilité ; réglage coupé : rien n\'est écrit, chaque refus est journalisé', () {
      final m = _magasin();
      final t = DateTime(2026, 8, 17, 8, 0);
      final surv = _p(m, 'surveillant', () => t);
      expect(surv.pointer('BDG-T0002-2026')['code'], 'BADGE_RETIRE');
      expect(surv.pointer('BDG-INCONNU-0000')['code'], 'BADGE_INCONNU');
      expect(_p(m, 'caissier', () => t).pointer('BDG-T0001-2026')['code'], 'POINTAGE_RESERVE');
      final adm = _p(m, 'admin', () => t);
      expect(adm.regler(actif: false)['ok'], isTrue);
      expect(surv.pointer('BDG-T0001-2026')['code'], 'POINTAGE_DESACTIVE');
      expect(m.collection('presences').toutes.where((x) => x['origine'] == 'badge'), isEmpty);
      expect(m.collection('audit').toutes.where((x) => x['action'] == 'Pointage par badge').length, 4);
    });

    test('le délai et l\'activation sont des paramètres en base, versionnés : valeurs d\'origine (oui, 5 minutes), refus nommés, journal RG-12', () {
      final m = _magasin();
      final t = DateTime(2026, 8, 17, 8, 0);
      final adm = _p(m, 'admin', () => t);
      expect([adm.actif(), adm.delai()], [true, delaiPointageBadgeDefaut]);
      final r = adm.regler(delai: 12, motif: 'Essai');
      expect([r['ok'], r['delai'], r['actif']], [true, 12, true]);
      expect(adm.delai(), 12);
      expect(adm.regler(delai: -1)['code'], 'DELAI_INVALIDE');
      expect(adm.regler(delai: 2.5)['code'], 'DELAI_INVALIDE');
      expect(_p(m, 'medecin', () => t).regler(delai: 3)['code'], 'REGLAGE_RESERVE');
      expect(adm.delai(), 12, reason: 'un refus n\'écrit rien');
      final j = m.collection('audit').toutes.firstWhere((x) => x['reference'] == 'planningBadgeSertDePointage');
      expect([(j['avant'] as Map)['delai'], (j['apres'] as Map)['delai']], [5, 12]);
      expect(m.collection('parametres').toutes.where((v) => v['cle'] == 'planning.delaiEntrePointagesBadge').single['valeur'], 12);
    });
  });

  group('hors ligne puis synchronisé : le pointage voyage par le pont d\'activité', () {
    test('une présence pointée sur un poste hors ligne arrive aux autres, le départ et la validation aussi (champs gardés)', () async {
      expect(collectionsActivite.contains('presences'), isTrue);
      final j = _Journal();
      Magasin poste() => Magasin({'presences': [], 'patients': []});
      final ma = poste(), mm = poste();
      final pa = PontActivite(ma, _Transport(j), etiquette: 'A'), pm = PontActivite(mm, _Transport(j), etiquette: 'M');
      // Hors ligne : l'arrivée s'écrit au poste A sans qu'aucun pont ne tourne.
      final id = ma.collection('presences').inserer({
        'date': '2026-08-17', 'employeId': 'EMPBDG', 'employe': 'KORA Agent', 'etat': 'present', 'heureArrivee': '08:00', 'origine': 'badge', 'validationEtat': 'a_valider', 'statut': 'actif',
      }, prefixe: 'PRS').fiche['id'];
      expect(mm.collection('presences').toutes, isEmpty, reason: 'rien n\'a voyagé tant que le poste est hors ligne');
      for (var i = 0; i < 3; i++) {
        await pa.cycle();
        await pm.cycle();
      }
      final chezM = mm.collection('presences').toutes;
      expect(chezM.length, 1);
      expect([chezM.single['heureArrivee'], chezM.single['origine'], chezM.single['validationEtat']], ['08:00', 'badge', 'a_valider']);
      // Le départ pointé en A et la validation faite à la mère se rejoignent, aucun ne perd l'autre.
      ma.collection('presences').mettreAJour(id, {'heureDepart': '17:30', 'departParBadge': 'BDGT1'});
      mm.collection('presences').mettreAJour(chezM.single['id'], {'validationEtat': 'valide', 'validePar': 'Surveillant'});
      for (var i = 0; i < 4; i++) {
        await pa.cycle();
        await pm.cycle();
      }
      for (final m in [ma, mm]) {
        final f = m.collection('presences').toutes.single;
        expect([f['heureDepart'], f['validationEtat'], f['validePar'], f['heureArrivee']], ['17:30', 'valide', 'Surveillant', '08:00'], reason: 'les deux gestes survivent');
      }
    });
  });

  group('l\'écran « Vérifier un badge » : pointer au geste', () {
    casM14('un habilité pointe : « Arrivée pointée », présence à valider écrite ; le passage suivant est refusé (délai nommé) ; le réglage coupé retire la commande', (t) async {
      final m = _magasin();
      await ouvrirM14(t, m, 'm10-badges-verification', horloge: auj16, role: 'surveillant');
      expect(find.text('Pointage par badge'), findsOneWidget);
      expect(find.widgetWithText(BoutonSigh, 'Pointer'), findsOneWidget);
      expect(find.widgetWithText(BoutonSigh, 'Régler'), findsNothing, reason: 'le surveillant ne règle pas');
      await t.enterText(find.byKey(const Key('rhc:saisie')), 'BDG-T0001-2026');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Pointer'));
      expect(find.text('Arrivée pointée'), findsOneWidget);
      final pres = m.collection('presences').toutes.where((x) => x['origine'] == 'badge').toList();
      expect([pres.length, pres.first['validationEtat'], pres.first['employeId']], [1, 'a_valider', 'EMPBDG']);
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Pointer'));
      expect(find.text('Pointage refusé'), findsOneWidget);
      expect(find.textContaining('moins de 5 minutes'), findsOneWidget);
      expect(m.collection('presences').toutes.where((x) => x['origine'] == 'badge').length, 1);
      // Réglage coupé : la commande est ABSENTE (jamais grisée), « Vérifier » reste.
      _p(m, 'admin', () => auj16).regler(actif: false);
      await ouvrirM14(t, m, 'm10-badges-verification', horloge: auj16, role: 'surveillant');
      expect(find.widgetWithText(BoutonSigh, 'Pointer'), findsNothing);
      expect(find.widgetWithText(BoutonSigh, 'Vérifier'), findsOneWidget);
    });

    casM14('un rôle non habilité (assistant de direction) vérifie sans pointer ni régler : commandes absentes', (t) async {
      await ouvrirM14(t, _magasin(), 'm10-badges-verification', horloge: auj16, role: 'assistant_comptable');
      expect(find.widgetWithText(BoutonSigh, 'Vérifier'), findsOneWidget);
      expect(find.widgetWithText(BoutonSigh, 'Pointer'), findsNothing);
      expect(find.widgetWithText(BoutonSigh, 'Régler'), findsNothing);
    });

    casM14('l\'administrateur règle le délai au geste : valeur d\'attente dite, enregistrement en base, refus d\'un délai invalide', (t) async {
      final m = _magasin();
      await ouvrirM14(t, m, 'm10-badges-verification', horloge: auj16, role: 'admin');
      expect(texteAffiche(t).contains(sansEspaces('5 minutes (valeur d’attente, à valider)').toLowerCase()), isTrue);
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Régler'));
      final ctl = t.widget<FormulaireSigh>(find.byType(FormulaireSigh).last).controleur;
      ctl.poser('delai', '15');
      await t.pump();
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
      expect(find.text('Réglage enregistré.'), findsOneWidget);
      expect(m.collection('parametres').toutes.where((v) => v['cle'] == 'planning.delaiEntrePointagesBadge').single['valeur'], 15);
    });
  });
}

class _Journal {
  final Map<String, Map<String, Map<String, Object?>>> fiches = {};
}

class _Transport implements TransportPont {
  _Transport(this.j);
  final _Journal j;
  @override
  Future<List<PieceSync>> liste(String c) async => [for (final e in (j.fiches[c] ?? {}).entries) PieceSync(e.key, jsonDecode(jsonEncode(e.value)) as Map<String, Object?>)];
  @override
  Future<void> ecrire(String c, String fiche, {required bool existe, required Map<String, Object?> champs}) async {
    final col = j.fiches.putIfAbsent(c, () => {});
    col[fiche] = {...?col[fiche], ...jsonDecode(jsonEncode(champs)) as Map<String, Object?>};
  }
}
