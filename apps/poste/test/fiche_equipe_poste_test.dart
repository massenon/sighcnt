import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/planning_rh_poste.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';
import 'm10_aide.dart' as a;

/// LOT SURV (16/11/2026) : la fiche de l'équipe et le périmètre d'équipe au poste. Les règles sont au domaine (vecteurs de la maquette, `packages/domaine/test/fiche_equipe_test.dart`) :
/// ici le BRANCHEMENT (moteur du poste et écran). NON VÉRIFIÉ : Windows, pixels.
typedef M = Map<String, Object?>;

M agent(String id, String nom, String service, {String fonction = 'infirmier'}) => {
      'id': id, 'statut': 'actif', 'nomComplet': nom, 'matricule': 'M-$id', 'fonction': fonction, 'poste': 'Poste $id', 'service': service, 'sexe': 'F',
      'salaireBase': 123456, 'categorie': 'E3-1', 'dateEmbauche': '2015-02-01', 'cnss': 'CNSS-$id', 'telephone': '97000000', 'valeursAttente': {'salaireBase': true},
    };

Magasin magasin() => Magasin({
      'audit': <M>[],
      'personnel': <M>[
        agent('S0', 'Surveillant', 'Soins infirmiers'),
        agent('E1', 'Equipe Un', 'Soins infirmiers'),
        agent('E2', 'Equipe Deux', 'Soins infirmiers'),
        agent('H1', 'Hors Equipe', 'Maternité', fonction: 'sage_femme'),
      ],
      'regimesTravail': <M>[],
      'regimesIndividuels': <M>[],
      'planning': <M>[],
      'planningsPersonnalises': <M>[],
    }, 'POSTE');

PlanningRhPoste moteur(Magasin m, {String nom = 'Surveillant', bool complete = false, Set<String> gestes = const {gesteFicheEquipe, gestePlanningPersonnaliseRh}}) =>
    PlanningRhPoste(m, auteur: () => nom, role: 'surveillant', droitGeste: gestes.contains, lectureCompletePersonnel: () => complete, horloge: () => DateTime.parse('2026-11-09'));

Map<String, Object?> jour(String type) => {'jour': 2, 'type': type};

/// Un type toujours permis (congé), quel que soit le régime.
const vacance = 'conge';

void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  group('le moteur du poste : périmètre d\'équipe (branchement du domaine)', () {
    test('la portée vient des droits : lecture complète, puis geste, sinon aucune', () {
      final m = magasin();
      expect(moteur(m).portee, PorteePersonnel.equipe);
      expect(moteur(m, complete: true).portee, PorteePersonnel.complete);
      expect(moteur(m, gestes: const {}).portee, PorteePersonnel.aucune);
    });

    test('l\'équipe du Surveillant : son service SANS lui-même, projection restreinte (aucune donnée de paie)', () {
      final r = moteur(magasin()).equipeDeLaSession();
      final agents = (r['agents'] as List).cast<M>();
      expect(agents.map((x) => x['id']).toList(), ['E1', 'E2']);
      for (final x in agents) {
        expect(x.keys.toSet().difference(champsFicheEquipeRh.toSet()), isEmpty, reason: 'liste blanche');
        for (final interdit in ['salaireBase', 'categorie', 'dateEmbauche', 'cnss', 'telephone', 'valeursAttente']) {
          expect(x.containsKey(interdit), isFalse, reason: interdit);
        }
      }
      final f = moteur(magasin()).ficheEquipe('E1');
      expect(f['ok'], isTrue);
      expect(moteur(magasin()).ficheEquipe('H1')['code'], 'AGENT_HORS_EQUIPE');
      expect(moteur(magasin()).ficheEquipe('S0')['code'], 'AGENT_HORS_EQUIPE');
      expect(moteur(magasin()).ficheEquipe('X')['code'], 'AGENT_INTROUVABLE');
    });

    test('sans le geste : liste et fiche refusées en nommant le droit ; une session qui n\'est pas un agent n\'a pas d\'équipe', () {
      expect(moteur(magasin(), gestes: const {}).equipeDeLaSession()['code'], 'FICHE_EQUIPE_RESERVEE');
      expect(moteur(magasin(), gestes: const {}).ficheEquipe('E1')['code'], 'FICHE_EQUIPE_RESERVEE');
      expect(moteur(magasin(), nom: 'Inconnu').equipeDeLaSession()['code'], 'EQUIPE_INDETERMINEE');
    });

    test('définir un planning personnalisé : dans l\'équipe oui (écrit), hors équipe, soi-même et session sans agent refusés nommément, rien d\'écrit', () {
      final m = magasin();
      final p = moteur(m);
      Map<String, Object?> def(String id, {PlanningRhPoste? moteur}) =>
          (moteur ?? p).definirPlanningPerso(employeId: id, periodicite: 'hebdomadaire', dateEffet: '2026-11-20', motif: 'Sonde', jours: [jour(vacance)]);
      expect(def('E1')['ok'], isTrue);
      expect(def('H1')['code'], 'AGENT_HORS_EQUIPE');
      expect(def('S0')['code'], 'AGENT_HORS_EQUIPE');
      expect(def('E1', moteur: moteur(m, nom: 'Inconnu'))['code'], 'EQUIPE_INDETERMINEE');
      expect(m.collection('planningsPersonnalises').actives, hasLength(1));
      // Sans le droit du planning : refus du droit, jamais de l'équipe.
      expect(def('E2', moteur: moteur(m, gestes: const {gesteFicheEquipe}))['code'], 'PLANNING_PERSO_RESERVE');
      // Sans le geste de la fiche d'équipe (portée « aucune ») : le moteur refuse en nommant ce droit.
      expect(def('E2', moteur: moteur(m, gestes: const {gestePlanningPersonnaliseRh}))['code'], 'FICHE_EQUIPE_RESERVEE');
      expect(m.collection('planningsPersonnalises').actives, hasLength(1));
    });

    test('appliquer à une période : hors équipe refusé (AGENT_HORS_EQUIPE), dans l\'équipe aperçu puis écriture', () {
      final m = magasin();
      final p = moteur(m);
      expect(p.definirPlanningPerso(employeId: 'E1', periodicite: 'hebdomadaire', dateEffet: '2026-11-09', motif: 'Sonde', jours: [jour(vacance)])['ok'], isTrue);
      expect(p.appliquerPlanningPerso(employeId: 'H1', du: '2026-11-09', au: '2026-11-15')['code'], 'AGENT_HORS_EQUIPE');
      final ap = p.appliquerPlanningPerso(employeId: 'E1', du: '2026-11-09', au: '2026-11-15');
      expect(ap['ok'], isTrue);
      expect(ap['apercu'], isTrue);
      expect(m.collection('planning').actives, isEmpty);
    });

    test('le régime individuel : jamais sans son droit ; avec lui, l\'équipe seulement', () {
      final m = magasin();
      Map<String, Object?> der(PlanningRhPoste p, String id) => p.deroger(employeId: id, dateEffet: '2026-11-20', champs: {'repos': 'repos24'}, motif: 'S');
      expect(der(moteur(m), 'E1')['code'], 'DEROGATION_RESERVEE');
      final avec = moteur(m, gestes: const {gesteFicheEquipe, gesteRegimeIndividuelRh});
      expect(der(avec, 'E1')['ok'], isTrue);
      expect(der(avec, 'H1')['code'], 'AGENT_HORS_EQUIPE');
    });

    test('une valeur d\'attente ne se confirme pas depuis la portée « équipe » ; la lecture complète le permet', () {
      final m = magasin();
      final eq = moteur(m, gestes: const {gesteFicheEquipe, gesteValeurAttenteRh});
      expect(eq.confirmerValeurAttente(employeId: 'E1', champ: 'salaireBase', motif: 'x')['code'], 'VALEUR_ATTENTE_HORS_PORTEE');
      final complet = moteur(m, complete: true, gestes: const {gesteValeurAttenteRh});
      expect(complet.confirmerValeurAttente(employeId: 'E1', champ: 'salaireBase', motif: 'Contrat')['ok'], isTrue);
    });

    test('la lecture complète n\'a AUCUN périmètre d\'équipe (administrateur et DAF d\'origine)', () {
      final m = magasin();
      final p = moteur(m, complete: true, gestes: const {gestePlanningPersonnaliseRh});
      expect(p.definirPlanningPerso(employeId: 'H1', periodicite: 'hebdomadaire', dateEffet: '2026-11-20', motif: 'S', jours: [jour(vacance)])['ok'], isTrue);
    });
  });

  group('l\'écran « Fiche de mon équipe »', () {
    Map<String, List<M>> monde() => {
          'personnel': [
            agent('S0', 'Surveillant', 'Soins infirmiers'),
            agent('E1', 'Equipe Un', 'Soins infirmiers'),
            agent('E2', 'Equipe Deux', 'Soins infirmiers'),
            agent('H1', 'Hors Equipe', 'Maternité', fonction: 'sage_femme'),
          ],
          'planning': const [],
          'planningsPersonnalises': const [],
        };

    testWidgets('le Surveillant lit son équipe sans aucune donnée de paie, le geste du planning donne la commande, le moteur refuse hors équipe', (t) async {
      final m = a.poste(monde());
      await a.ouvrir(t, m, 'm10-fiche-equipe', role: 'surveillant');
      expect(find.text('Fiche de mon équipe'), findsWidgets);
      expect(find.textContaining('Équipe : 2 agent(s)'), findsOneWidget);
      final txt = a.texteAffiche(t);
      for (final interdit in ['salairedebase', 'cnss', 'catégorie', 'dated’embauche', 'ancienneté', 'assurance', 'primes', '123456', 'e3-1', 'hors equipe', 'maternité']) {
        expect(txt.contains(interdit), isFalse, reason: '« $interdit » ne doit pas figurer à l\'écran');
      }
      await a.cliquer(t, find.text('Planning personnalisé'));
      expect(find.widgetWithText(BoutonSigh, 'Définir une version'), findsOneWidget);
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('un rôle sans le geste ne voit pas l\'écran dans la navigation (RG-13)', (t) async {
      expect(a.donnees.matrice.peutVoir('surveillant', 'm10-fiche-equipe'), isTrue);
      for (final r in ['infirmier', 'medecin', 'reception', 'caissier']) {
        expect(a.donnees.matrice.peutVoir(r, 'm10-fiche-equipe'), isFalse, reason: r);
      }
      expect(a.donnees.matrice.peutVoir('surveillant', 'm10-employe-profil'), isFalse);
      expect(a.donnees.matrice.peutVoir('surveillant', 'm10-personnel'), isFalse);
    });
  });
}
