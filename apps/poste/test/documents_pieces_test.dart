import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';
import 'm14_aide.dart';

/// LOT 8, « Pièces produites par le logiciel » au poste (second onglet de `m1-documents`) : des RENVOIS, jamais des copies, élargis aux comptes rendus de maternité et aux fiches de
/// consultation. La règle est rejouée sur les vecteurs de la maquette par le domaine (`pat_pieces_produites_test.dart`) ; ici, l'ÉCRAN : la zone médicale ferme la vue entière, le bouton
/// « Ouvrir » n'existe que pour qui ouvre l'écran de la pièce, la consultation du dossier est journalisée.
void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  Map<String, Object?> patientAvecPieces(Magasin m) {
    final p = m.collection('patients').actives.first;
    m.collection('crMaternite').inserer({'reference': 'CRM-T001', 'patientId': p['id'], 'dateHeure': '2026-10-20T08:30', 'typeLabel': 'Compte rendu d’accouchement', 'statut': 'actif'});
    m.collection('crMaternite').inserer({'reference': 'CRM-T002', 'patientId': 'AUTRE', 'dateHeure': '2026-10-20T09:30', 'typeLabel': 'Compte rendu d’AMIU', 'statut': 'actif'});
    m.collection('dossiersConsultation').inserer({'reference': 'DOS-T001', 'patientId': p['id'], 'dateArrivee': '2026-10-21', 'motifVenue': 'Contrôle tensionnel', 'statut': 'actif'});
    return p;
  }

  Future<void> ouvrirVue(WidgetTester t, Magasin m, String role) async {
    await ouvrirM14(t, m, 'm1-documents', role: role);
    await toucherM14(t, find.text('Pièces produites par le logiciel'));
    await t.pump(const Duration(milliseconds: 300));
  }

  casM14('un profil clinique : le choix du dossier liste ses renvois (maternité, consultation), pas ceux d\'un autre patient, et « Ouvrir » renvoie à l\'écran', (t) async {
    final m = magasinM14();
    final p = patientAvecPieces(m);
    await ouvrirVue(t, m, 'medecin');
    expect(find.byKey(const Key('pieces:vue')), findsOneWidget);
    expect(find.text('CRM-T001'), findsNothing, reason: 'aucun dossier choisi : aucune pièce');
    await choisirM14(t, 'patientId', '${p['code']} : ${p['nom']} ${p['prenom']}');
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('CRM-T001'), findsOneWidget);
    expect(find.text('DOS-T001'), findsOneWidget);
    expect(find.text('Compte rendu de maternité'), findsWidgets);
    expect(find.text('Fiche de consultation'), findsWidgets);
    expect(find.text('Contrôle tensionnel'), findsOneWidget);
    expect(find.text('CRM-T002'), findsNothing, reason: 'la pièce d\'un autre patient n\'est jamais listée');
    expect(find.byKey(const Key('pieces:ouvrir-CRM-T001')), findsOneWidget, reason: 'le médecin ouvre l\'écran des comptes rendus de maternité');
    expect(find.text('Les pièces produites par le logiciel ne sont jamais copiées ici : ce sont des renvois vers l’écran qui les tient, relus à chaque affichage.'), findsOneWidget);
    expect(m.collection('audit').toutes.any((a) => a['action'] == 'Consultation du dossier documentaire du patient'), isTrue, reason: 'journalisé (RG-12)');
    // Jamais copiées : aucune fiche de document n'a été créée par la consultation.
    expect(m.collection('documentsPatient').toutes.any((d) => d['reference'] == 'CRM-T001'), isFalse);
  });

  casM14('un profil qui ne lit pas la zone médicale : la vue ENTIÈRE est fermée, ni choix de dossier ni un seul renvoi', (t) async {
    final m = magasinM14();
    patientAvecPieces(m);
    await ouvrirVue(t, m, 'reception');
    expect(find.byKey(const Key('pieces:zone-refusee')), findsOneWidget);
    expect(find.textContaining('votre profil ne les lit pas'), findsOneWidget);
    expect(find.byKey(const Key('pieces:vue')), findsNothing);
    expect(find.text('CRM-T001'), findsNothing);
    expect(find.text('Dossier patient'), findsNothing);
  });
}
