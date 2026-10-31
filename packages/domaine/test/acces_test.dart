// Rejoue les vecteurs des écrans d'accès et de support (prototype_html/build/vecteurs-acces.js) : les dix écrans RÉELS pilotés dans Chrome,
// horloge figée au 30/10/2026 10 h.
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

import 'aide_vecteurs.dart';

typedef M = Map<String, Object?>;
M obj(Object? o) => (o as Map).cast<String, Object?>();
List<M> fl(Object? v) => [for (final x in (v as List)) obj(x)];

final v = lireVecteurs('acces');
final manifesteJson = obj(jsonDecode(File('../referentiels/data/manifeste.json').readAsStringSync()));
final manifeste = Manifeste.depuisJson(manifesteJson);
bool alias(String domaine, String code) => manifeste.rangees.any((r) => r.domaine == domaine && r.code == code && r.alias);
String sp(Object? s) => '$s'.replaceAll(RegExp(r'\s+'), ' ').trim();

void main() {
  group('connexion', () {
    test('trois tentatives vides : les messages de la maquette, le troisième annonce le verrouillage', () {
      final essais = fl(obj(v['connexion'])['essaisVides']);
      for (var i = 0; i < 3; i++) {
        expect(accMessageSaisieVide(i + 1), essais[i]['texte'], reason: 'tentative ${i + 1}');
      }
      expect(accMessageSaisieVide(7), essais[2]['texte']);
    });

    test('le refus du serveur est le même pour un identifiant inconnu et pour un mot de passe faux', () {
      expect(accMessageRefus, obj(obj(v['connexion'])['refusServeur'])['texte']);
    });

    test('la page n’offre ni sélecteur de profil, ni mot de passe pré-rempli (20/10/2026)', () {
      final c = obj(v['connexion']);
      expect(c['nbSelect'], 0);
      final champs = fl(c['champs']);
      expect(champs.map((x) => x['type']), ['text', 'password', 'checkbox']);
    });

    final utilisateurs = <M>[
      {'identifiant': 'e.orou', 'nomComplet': 'Orou Ezin', 'role': 'reception', 'statut': 'actif', 'mfa': false},
      {'identifiant': 'a.ferme', 'nomComplet': 'Compte fermé', 'role': 'caissier', 'statut': 'archive'},
      {'identifiant': 'p.pharma', 'nomComplet': 'Ancien pharmacien', 'role': 'pharmacien', 'statut': 'actif'},
    ];
    AccDecision eval(String id) => accEvaluer(
        identifiant: id, utilisateurs: utilisateurs, rolesArchives: {'pharmacien'}, libelleRole: (r) => r == 'pharmacien' ? 'Pharmacien' : r);

    test('un compte actif est reconnu ; le mot de passe n’est JAMAIS vérifié et la décision le dit', () {
      final d = eval(' e.orou ');
      expect(d.accepte, isTrue);
      expect(d.compte!.role, 'reception');
      expect(d.motDePasseVerifie, isFalse);
      expect(accMotDePasseVerifie, isFalse);
    });

    test('identifiant inconnu → refus générique, même texte que le serveur', () {
      final d = eval('inconnu.xyz');
      expect(d.issue, AccIssue.refuse);
      expect(d.message, obj(obj(v['connexion'])['refusServeur'])['texte']);
      expect(d.motif, 'Identifiant inconnu');
    });

    test('compte archivé → refus nommé (RG-14) ; rôle archivé → refus nommé avec le profil', () {
      expect(eval('a.ferme').message, 'Ce compte a été archivé : il n’ouvre plus de session (RG-14).');
      final r = eval('p.pharma');
      expect(r.issue, AccIssue.roleArchive);
      expect(r.message, 'Connexion refusée — le profil « Pharmacien » a été retiré.');
      expect(r.motif, 'Rôle archivé — accès retiré par l’administrateur');
      final t = accTentative(identifiant: 'p.pharma', decision: r, maintenant: DateTime(2026, 10, 30, 10));
      expect(t['identifiant'], 'p.pharma');
      expect(t['role'], 'pharmacien');
      expect(t['traitee'], false);
      expect(t['poste'], 'Écran de connexion');
      expect(accLignesRefus(r, '30/10/2026 10:00').map((l) => l.$1), ['Compte', 'Profil demandé', 'Date et heure', 'Suite donnée']);
    });
  });

  group('mot de passe oublié et réinitialisation', () {
    test('la réinitialisation ne contrôle que la concordance (la politique est affichée, non appliquée)', () {
      final r = obj(v['reinit']);
      expect(accControlerReinitialisation('Motdepasse#2026', 'autre'), fl(r['discordance']).single['titre']);
      expect(accControlerReinitialisation('a', 'a'), isNull, reason: 'la maquette accepte « a » : écart consigné');
      expect(accRegleMotDePasse, (r['regles'] as List).cast<String>());
    });
  });

  group('verrouillage de session', () {
    final l = obj(v['verrou']);
    test('quinze minutes par défaut', () {
      expect(accDelaiVerrou.inMinutes, l['delaiDefautMinutes']);
      expect(accSousTitreVerrou(accDelaiVerrou), contains('après 15 minutes d’inactivité'));
    });

    test('à l’horloge injectée : pas verrouillé à quinze minutes pile, verrouillé au-delà ; un geste relance le compte à rebours', () {
      final t0 = DateTime(2026, 10, 30, 10);
      final k = AccVerrou()..activite(t0);
      expect(k.echu(t0.add(const Duration(minutes: 14, seconds: 59))), isFalse);
      expect(k.echu(t0.add(const Duration(minutes: 15))), isFalse);
      expect(k.echu(t0.add(const Duration(minutes: 15, seconds: 1))), isTrue);
      k.activite(t0.add(const Duration(minutes: 10)));
      expect(k.echu(t0.add(const Duration(minutes: 20))), isFalse);
      expect(k.echu(t0.add(const Duration(minutes: 25, seconds: 1))), isTrue);
    });

    test('la session est SUSPENDUE : l’adresse de retour est à USAGE UNIQUE', () {
      final t0 = DateTime(2026, 10, 30, 10);
      final k = AccVerrou()..activite(t0);
      k.verrouiller(t0, 'm2-agenda', onglet: 'semaine');
      expect(k.verrouille, isTrue);
      expect(k.retour!.adresse(), (obj(l['avecRetour'])['navigation'] as List).single);
      final r = k.deverrouiller(t0);
      expect(r, const AccRetour('m2-agenda', 'semaine'));
      expect(k.deverrouiller(t0), isNull, reason: 'consommée une seule fois');
      expect(k.verrouille, isFalse);
      expect(obj(l['avecRetour'])['retourConsommeApres'], isTrue);
    });

    test('le verrouillage ne compte plus le temps pendant qu’il est posé ; « autre compte » efface tout', () {
      final t0 = DateTime(2026, 10, 30, 10);
      final k = AccVerrou()..activite(t0);
      k.verrouiller(t0, 'm8-caisse');
      expect(k.echu(t0.add(const Duration(hours: 3))), isFalse);
      k.abandonner();
      expect(k.retour, isNull);
      expect(k.verrouille, isFalse);
      expect(obj(l['autreCompte'])['retourApres'], isTrue);
    });

    test('l’adresse de retour accepte .php et .html, l’ancre porte l’onglet', () {
      expect(accRetourDepuisAdresse('m2-agenda.php#onglet=semaine'), const AccRetour('m2-agenda', 'semaine'));
      expect(accRetourDepuisAdresse('m2-agenda.html'), const AccRetour('m2-agenda'));
      expect(accRetourDepuisAdresse(null), isNull);
      expect(accRetourDepuisAdresse(''), isNull);
    });

    test('le message annonce l’écran à retrouver ; une adresse inconnue du manifeste n’en annonce pas', () {
      final textes = (obj(l['avecRetour'])['textes'] as List).cast<String>();
      expect(textes, contains(accMessageRetour('Agenda')));
      expect(textes, contains(accTitreRetour));
      expect((obj(l['retourInconnu'])['textes'] as List).any((t) => '$t'.startsWith('Au déverrouillage')), isFalse);
      expect(accMessageRetour(null), isNull);
    });
  });

  group('aide, contact éditeur, plan du site', () {
    final a = obj(v['aide']);
    test('les quatre chiffres de l’aide sont dérivés du manifeste', () {
      final c = accChiffresAide(manifeste, (a['nbRoles'] as num).toInt());
      final k = fl(a['kpis']);
      expect([c.modules, c.ecrans, c.regles, c.profils], [for (final x in k) int.parse(sp(x['valeur']))]);
    });

    test('un résumé par module, les neuf questions, mot pour mot', () {
      final mods = fl(a['modules']);
      final mm = accModules(manifeste);
      expect(mm.length, mods.length);
      for (var i = 0; i < mm.length; i++) {
        expect(mm[i].label, mods[i]['titre']);
        expect(mm[i].code, mods[i]['code']);
        expect(mm[i].domaine, (mods[i]['domaine'] as String).replaceFirst('Domaine ', ''));
        expect(accResumeModule(mm[i].code), mods[i]['resume']);
      }
      final faq = fl(a['faq']);
      expect(accFaq.length, faq.length);
      for (var i = 0; i < faq.length; i++) {
        expect(accFaq[i].q, faq[i]['q']);
        expect(sp(accTexteSansBalises(accFaq[i].r)), sp(faq[i]['r']));
      }
      expect([for (final l in a['apropos'] as List) (l as List)[1]],
          ['Prototype v1.0 — août 2026', 'Dr MASSENON Rhodes', 'CLINIQUE NASSIERA TOO SARL', '3201642748214', 'RB/NAT/2016-B-268']);
      expect(accEditeur['version'], 'Prototype v1.0 — août 2026');
    });

    final c = obj(v['contact']);
    test('contrôles et toasts', () {
      expect(accControlerMessage('', 'x'), fl(c['refusMessage']).single['titre']);
      expect(accControlerMessage('o', ' '), isNotNull);
      expect(accControlerMessage('o', 'm'), isNull);
      expect(accControlerAnomalie(null, 'x'), fl(c['refusAnomalie']).single['titre']);
      expect(accControlerAnomalie('M8', ''), isNotNull);
      expect(accToastDemande('message'), fl(c['toastMessage']).single['titre']);
      expect(accToastDemande('anomalie'), fl(c['toastAnomalie']).single['titre']);
      expect(accDetailDemande('SUP-2026-0001'), fl(c['toastMessage']).single['detail']);
    });

    test('les fiches écrites : mêmes champs que la maquette', () {
      final fiches = fl(c['fiches']);
      final msg = fiches.firstWhere((f) => f['type'] == 'message');
      final ano = fiches.firstWhere((f) => f['type'] == 'anomalie');
      for (final f in [msg, ano]) {
        f.removeWhere((k, _) => ['statut', 'reference', 'date', 'auteur', 'etat'].contains(k));
      }
      expect(accDemandeMessage('Question sur la comptabilité', 'Comment lire la balance ?'), {...msg, 'module': null, 'etapes': null, 'capture': null});
      expect(accDemandeAnomalie('M8', 'Le reçu ne se détaille pas', '1. Encaisser 2. Imprimer', null), {...ano, 'capture': null});
    });

    test('la référence suit le registre (pas un compteur de page), de l’année courante', () {
      expect(accReferenceSupport(2026, const []), 'SUP-2026-0001');
      expect(accReferenceSupport(2026, ['SUP-2026-0001', 'SUP-2026-0007', 'SUP-2025-0099']), 'SUP-2026-0008');
      expect(accReferenceSupport(2027, ['SUP-2026-0007']), 'SUP-2027-0001');
    });

    test('options du module concerné : celles de la maquette, dans l’ordre', () {
      final o = accOptionsModules(manifeste);
      final att = fl(c['optionsModule']);
      expect(o.length, att.length);
      for (var i = 0; i < o.length; i++) {
        expect(o[i].code, att[i]['valeur']);
        expect(o[i].libelle, att[i]['label']);
      }
    });

    test('plan du site : domaines, modules, écrans, pied et pages système identiques à la maquette', () {
      final p = obj(v['plan']);
      final plan = accPlanDuSite(manifeste, accEcransSysteme(manifeste));
      final sections = fl(p['sections']);
      expect(plan.sections.length, sections.length - 1, reason: 'la dernière section est « Accès et pages système »');
      for (var i = 0; i < plan.sections.length; i++) {
        expect(plan.sections[i].domaine, sections[i]['titre'], reason: 'domaine $i');
        final ms = fl(sections[i]['modules']);
        expect(plan.sections[i].modules.length, ms.length, reason: plan.sections[i].domaine);
        for (var j = 0; j < ms.length; j++) {
          expect(plan.sections[i].modules[j].label, ms[j]['titre']);
          expect(plan.sections[i].modules[j].code, ms[j]['code']);
          final att = fl(ms[j]['ecrans']);
          expect(plan.sections[i].modules[j].ecrans.map((e) => e.id), att.map((e) => (e['href'] as String).replaceAll(RegExp(r'^pages/|\.php$'), '')),
              reason: ms[j]['titre'].toString());
          // Les rangées ALIAS de la maquette rebaptisent certains écrans (« Référentiel tarifaire public ») : le manifeste engendré ne porte pas ces
          // intitulés propres à la rangée (écart consigné) ; les rangées canoniques se comparent au libellé.
          if (!alias(plan.sections[i].domaine, plan.sections[i].modules[j].code)) {
            expect(plan.sections[i].modules[j].ecrans.map((e) => e.label), att.map((e) => e['label']), reason: ms[j]['titre'].toString());
          }
        }
      }
      expect(plan.pied, p['pied']);
      expect(plan.systeme.map((e) => e.label), fl(sections.last['liensSysteme']).map((e) => e['label']));
    });
  });
}
