import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/mes_poste.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/modules/auth/acc_session.dart';

import 'aide_polices.dart';
import 'm14_aide.dart';
import 'rhb_aide.dart';

/// m10-mes (lot L7, Direction, 09/11/2026, Planning Q5, Q6, Q8) : l'espace « Mes » de l'agent, la copie de la fiche de paie pour le téléphone, « Mon assurance du personnel ».
/// Les règles (rubriques, refus nommés, copie de l'agent seul) sont rejouées sur les vecteurs de la maquette par `packages/domaine/test/mes_pointage_test.dart` ; ici l'ÉCRAN
/// monté sur le magasin du poste, les gestes accomplis, ce qui est écrit, et l'état d'affichage au verrou et à la déconnexion (poste partagé).
const _jour = '2026-08-16';

String _nom(String role) => agentDemonstration(role, nom: donneesNav.matrice.libelle(role)).nom;

/// Un agent du personnel au nom de l'agent de démonstration du rôle, ses pièces (dont des pièces d'un autre agent), son dossier patient et une demande ancienne sans montant.
Magasin _magasin(String role) {
  final m = magasinRhb();
  m.collection('personnel').inserer({'id': 'EMPMES', 'statut': 'actif', 'nomComplet': _nom(role), 'matricule': '888', 'fonction': 'medecin', 'service': 'Médecine générale', 'poste': 'Médecin'},
      prefixe: 'EMP');
  final b = m.collection('bulletins');
  for (final (id, emp, statut) in [('BMA1', 'EMPMES', 'diffuse'), ('BMA2', 'EMPMES', 'diffuse'), ('BMA3', 'EMPMES', 'valide'), ('BMB1', 'EMP01', 'diffuse')]) {
    b.inserer({'id': id, 'statut': 'actif', 'reference': 'BP-$id', 'periode': '2026-07', 'employeId': emp, 'brut': 100000, 'totalPrimes': 5000, 'totalRetenues': 12000, 'net': 88000, 'statutBulletin': statut, 'dateDiffusion': '2026-08-01'},
        prefixe: 'BP');
  }
  m.collection('patients').inserer({'id': 'PMES', 'statut': 'actif', 'nom': 'MES', 'prenom': 'Agent', 'code': 'CNT/888/26', 'personnelId': 'EMPMES'}, prefixe: 'PAT');
  m.collection('consultations').inserer({'id': 'CMES', 'statut': 'actif', 'patientId': 'PMES', 'date': '2026-01-06', 'type': 'Consultation', 'motif': 'Contrôle', 'tarif': 5000, 'medecin': 'X'}, prefixe: 'CS');
  m.collection('demandesAnalyses').inserer({'id': 'DMES', 'statut': 'actif', 'patientId': 'PMES', 'analyse': 'L01', 'dateHeure': '2026-01-05T08:00:00'}, prefixe: 'DA');
  return m;
}

void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  group('m10-mes : l\'espace de l\'agent', () {
    casM14('un agent voit les dix-sept rubriques, sa fiche de paie ÉMISE seule, et aucune commande de réglage de la mère', (t) async {
      await ouvrirM14(t, _magasin('medecin'), 'm10-mes', horloge: auj16, role: 'medecin');
      expect(rubriquesMes.length, 17);
      for (final r in rubriquesMes) {
        expect(find.byKey(Key('mes:rubrique:${r.id}')), findsOneWidget, reason: r.libelle);
      }
      expect(find.widgetWithText(BoutonSigh, 'Régler'), findsNothing);
      await toucherM14(t, find.byKey(const Key('mes:rubrique:fiche_paie')));
      final txt = texteAffiche(t);
      expect([txt.contains('bp-bma1'), txt.contains('bp-bma2')], [true, true]);
      expect([txt.contains('bp-bma3'), txt.contains('bp-bmb1')], [false, false], reason: 'ni la pièce validée non diffusée, ni celle d\'un autre agent');
      expect(txt.contains(sansEspaces('Copie chiffrée sur le téléphone : activée').toLowerCase()), isTrue);
      expect(MesAffichage.rubrique, 'fiche_paie');
    });

    casM14('un compte sans agent du personnel (poste partagé, compte du poste) : « Espace non disponible », refus nommé COMPTE_NON_NOMINATIF dit à l\'écran', (t) async {
      await ouvrirM14(t, magasinRhb(), 'm10-mes', horloge: auj16, role: 'caissier');
      expect(find.text('Espace non disponible'), findsOneWidget);
      expect(find.textContaining('ne correspond à aucun agent du personnel'), findsOneWidget);
      expect(find.byKey(const Key('mes:rubrique:fiche_paie')), findsNothing);
    });

    casM14('l\'administrateur règle la copie au geste : une version du paramètre, ancienne et nouvelle valeur au journal ; la copie est alors refusée en le nommant', (t) async {
      final m = _magasin('admin');
      await ouvrirM14(t, m, 'm10-mes', horloge: auj16, role: 'admin');
      expect(find.text('Copie de la fiche de paie sur le téléphone'), findsOneWidget);
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Régler'));
      final ctl = t.widget<FormulaireSigh>(find.byType(FormulaireSigh).last).controleur;
      ctl.poser('oui', false);
      await t.pump();
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
      expect(find.text('Réglage enregistré.'), findsOneWidget);
      final e = EspaceMesPoste(m, auteur: () => _nom('admin'), role: 'admin', horloge: () => DateTime(2026, 8, 16, 9));
      expect(e.copiePaieActive(), isFalse);
      final j = m.collection('audit').toutes.firstWhere((x) => x['reference'] == 'paieCopieTelephone');
      expect(j['action'], 'Copie de la fiche de paie sur le téléphone');
      expect([(j['avant'] as Map)['valeur'], (j['apres'] as Map)['valeur']], [true, false], reason: 'l\'ancienne et la nouvelle valeur au journal (RG-12)');
      final refus = e.copiePaie();
      expect(refus.refus!.code, 'COPIE_PAIE_DESACTIVEE');
      final versions = m.collection('parametres').toutes.where((v) => v['cle'] == 'paie.copieFichePaieTelephone').toList();
      expect(versions.length, 1, reason: 'une NOUVELLE version posée (le défaut n\'est semé qu\'au démarrage de la mère) : rien n\'est réécrit');
      expect([versions.single['valeur'], versions.single['dateEffet']], [false, '2026-08-16']);
    });

    casM14('« Mon assurance du personnel » : lecture seule, « Non renseigné » pour la demande sans montant (jamais le prix courant), le tarif porté pour la consultation', (t) async {
      await ouvrirM14(t, _magasin('medecin'), 'm10-mes', horloge: auj16, role: 'medecin');
      await toucherM14(t, find.byKey(const Key('mes:rubrique:assurance')));
      expect(find.textContaining('Lecture seule.'), findsOneWidget);
      expect(find.text('Non renseigné'), findsOneWidget);
      final txt = texteAffiche(t);
      expect(txt.contains(sansEspaces(money(5000, avecDevise: false))), isTrue, reason: 'le tarif PORTÉ par la consultation');
      expect(txt.contains(sansEspaces('1 sans montant renseigné (non comptées)').toLowerCase()), isTrue);
      expect(find.widgetWithText(BoutonSigh, 'Nouveau'), findsNothing);
      expect(find.widgetWithText(BoutonSigh, 'Enregistrer'), findsNothing);
    });

    casM14('l\'écran de gestion de l\'assurance du personnel dit « Non renseigné » pour une hospitalisation sans montant (E747) et n\'invente aucun zéro', (t) async {
      final m = magasinRhb();
      await ouvrirM14(t, m, 'm10-assurance-personnel', horloge: auj16, role: 'admin');
      expect(find.text('Non renseigné'), findsWidgets);
      expect(texteAffiche(t).contains(sansEspaces('sans montant renseigné (non comptées)').toLowerCase()), isTrue);
    });
  });

  group('poste partagé : verrou et déconnexion', () {
    test('au verrou la rubrique ouverte est gardée ; à la déconnexion tout part, l\'agent suivant arrive sur la première rubrique', () {
      final s = SessionPoste.ouverte('medecin', nom: 'Agent A', horloge: () => DateTime(2026, 8, 16, 9));
      MesAffichage.rubrique = 'conges';
      expect(s.verrouillerMaintenant('m10-mes'), isTrue);
      expect(MesAffichage.rubrique, 'conges', reason: 'le verrou garde la rubrique : retour à l\'écran quitté');
      s.deverrouiller();
      MesAffichage.rubrique = 'conges';
      s.deconnecter();
      expect(MesAffichage.rubrique, isNull, reason: 'la déconnexion efface tout');
      MesAffichage.rubrique = 'primes';
      s.abandonner();
      expect(MesAffichage.rubrique, isNull, reason: '« Se connecter avec un autre compte » efface aussi');
    });
    test('purger ne touche que l\'affichage : aucune donnée n\'est gardée par l\'espace', () {
      MesAffichage.rubrique = 'agenda';
      MesAffichage.purger(garderRubrique: true);
      expect(MesAffichage.rubrique, 'agenda');
      MesAffichage.purger();
      expect(MesAffichage.rubrique, isNull);
    });
  });
}
