import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart' show cfbFicheCnssVersement;
import 'package:sigh_poste/donnees/aib_poste.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';
import 'm14_aide.dart';

/// Lot FISC-2 (Direction, 16/11/2026) au poste : « Confirmer » le versement CNSS (geste réservé, référence obligatoire, versionné par date), le SECOND barème de l'AIB
/// (retenue sur la facture d'un tiers) semé sans doublon sur un poste qui n'a que les trois situations de l'acheteur, et l'imputation de l'AIB opération par opération
/// (le logiciel propose, le comptable décide). Les règles sont au domaine (`packages/domaine/test/fisc2_test.dart`, rejouées sur les vecteurs de la maquette) ; ici
/// le BRANCHEMENT au magasin du poste et l'écran.
typedef M = Map<String, Object?>;

Magasin _magasinAib() => Magasin({
      'utilisateurs': <M>[],
      'audit': <M>[],
      'exercices': <M>[],
      'comptes': <M>[
        {'id': 'C1', 'statut': 'actif', 'num': '447000', 'libelle': 'Etat impôts retenu à la source'},
      ],
      'fournisseurs': <M>[],
      'facturesFournisseurs': <M>[],
      'ecritures': <M>[],
    });

AibPoste _aib(Magasin m, {String role = 'comptable', String jour = '2026-11-16'}) =>
    AibPoste(m, auteur: () => 'Comptable de test', role: role, libelleRole: role, fileul: false, horloge: () => DateTime.parse(jour));

void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  group('le second barème de l\'AIB', () {
    test('un poste qui n\'a que les trois situations de l\'acheteur reçoit les deux lignes de la retenue, une seule fois', () {
      final m = _magasinAib();
      final s = m.collection('situationsAib');
      s.ajouterSansJournal({'id': 'SAI01', 'code': 'ifu_actif', 'libelle': 'Acheteur avec IFU actif', 'declencheur': 'ifu_renseigne', 'ordre': 1, 'statut': 'actif'});
      m.collection('baremeAib').ajouterSansJournal({'id': 'BAI003', 'situation': 'ifu_actif', 'taux': 1, 'dateEffet': '2026-01-01', 'dateFin': null, 'statut': 'actif', 'aValider': false});
      AibPoste.amorcer(m);
      AibPoste.amorcer(m);
      expect([for (final f in s.toutes) f['code']].where((c) => c == 'personne_physique').length, 1);
      expect([for (final f in s.toutes) f['code']].where((c) => c == 'personne_morale').length, 1);
      // la fiche de l'acheteur déjà là n'est pas touchée, ses versions non plus : le taux validé reste validé
      expect(m.collection('baremeAib').toutes.where((f) => f['situation'] == 'ifu_actif').length, 1);
      final a = _aib(m);
      expect(a.proposer('personne_physique', '2026-11-16')['taux'], 3);
      expect(a.proposer('personne_morale', '2026-11-16')['taux'], 5);
      expect(a.proposer('personne_morale', '2025-12-31')['code'], 'AIB_SANS_BAREME', reason: 'lu à la date, jamais zéro');
    });
  });

  group('imputer l\'AIB opération par opération', () {
    Map<String, Object?> saisie([Map<String, Object?> sup = const {}]) =>
        {'operation': 'achat_fournisseur', 'reference': 'FF-P-1', 'tiers': 'Fournisseur', 'dateOperation': '2026-11-10', 'base': 100000, 'appliquer': true, 'situation': 'personne_morale', 'taux': 5, 'compte': '447000', ...sup};

    test('sans le geste réservé : refus nommé, rien n\'est écrit', () {
      final m = _magasinAib();
      final r = _aib(m).imputer(saisie(), droit: false);
      expect(r['code'], 'IMPUTATION_AIB_RESERVEE');
      expect(m.collection('imputationsAib').toutes, isEmpty);
    });

    test('le comptable décide : la décision absente est refusée, jamais supposée', () {
      final m = _magasinAib();
      final r = _aib(m).imputer(saisie({'appliquer': null}), droit: true);
      expect(r['code'], 'AIB_DECISION_ABSENTE');
      expect(m.collection('imputationsAib').toutes, isEmpty);
    });

    test('appliquée : 5 % de 100 000 = 5 000, signée, journalisée ; refaite, refusée ; annulée avec un motif, elle redevient imputable', () {
      final m = _magasinAib();
      final a = _aib(m);
      final r = a.imputer(saisie(), droit: true);
      expect(r['ok'], isTrue);
      final f = (r['fiche'] as Map).cast<String, Object?>();
      expect(f['montant'], 5000);
      expect(f['propositionTaux'], 5);
      expect(f['horsProposition'], false);
      expect(f['signeePar'], 'Comptable de test');
      expect(m.collection('audit').toutes.where((x) => x['action'] == 'AIB : imputation').length, 1);
      expect(a.imputer(saisie({'reference': 'ff-p-1', 'appliquer': false, 'motif': 'm'}), droit: true)['code'], 'AIB_DEJA_IMPUTEE');
      expect(a.annuler('${f['id']}', '  ', droit: true)['code'], 'AIB_MOTIF_ABSENT');
      expect(a.annuler('${f['id']}', 'Erreur de saisie', droit: true)['ok'], isTrue);
      expect(m.collection('imputationsAib').parId(f['id'])!['statut'], 'archive', reason: 'archive, jamais supprimée (RG-14)');
      expect(a.imputer(saisie(), droit: true)['ok'], isTrue);
    });

    test('non appliquée : motif obligatoire, aucun taux ni montant écrit', () {
      final m = _magasinAib();
      final a = _aib(m);
      expect(a.imputer(saisie({'appliquer': false, 'situation': null, 'taux': null, 'compte': null}), droit: true)['code'], 'AIB_MOTIF_ABSENT');
      final r = a.imputer(saisie({'appliquer': false, 'situation': null, 'taux': null, 'compte': null, 'motif': 'L\'assureur n\'applique pas l\'AIB'}), droit: true);
      expect(r['ok'], isTrue);
      final f = (r['fiche'] as Map).cast<String, Object?>();
      expect(f.containsKey('taux'), isFalse);
      expect(f.containsKey('montant'), isFalse);
    });

    test('un taux autre que le barème à la date se motive, et se marque hors proposition', () {
      final m = _magasinAib();
      final a = _aib(m);
      expect(a.imputer(saisie({'taux': 4}), droit: true)['code'], 'AIB_MOTIF_ABSENT');
      final r = a.imputer(saisie({'taux': 4, 'motif': 'Taux négocié'}), droit: true);
      expect(r['ok'], isTrue);
      expect(((r['fiche'] as Map)['horsProposition']), true);
    });
  });

  group('« Confirmer » le versement CNSS', () {
    Finder confirmer() => find.byKey(const Key('cfb:confirmer:CNSS-VERSEMENT'));

    // Le versement CNSS n'est pas semé au jeu du poste (voir ECARTS E2797) : le test l'apporte, comme le ferait un jeu régénéré depuis la maquette.
    Magasin avecVersement() => magasinM14()..collection('obligationsFiscales').ajouterSansJournal(cfbFicheCnssVersement());

    casM14('le détenteur du geste voit « Confirmer » sur la seule ligne « à confirmer » ; la référence est obligatoire ; confirmée, l\'obligation est signée et la version « à confirmer » reste à l\'historique', (t) async {
      final m = avecVersement();
      await ouvrirM14(t, m, 'cfg-comptabilite');
      expect(find.byKey(const Key('cfb:a-confirmer:CNSS-VERSEMENT')), findsOneWidget);
      expect(confirmer(), findsOneWidget);
      await toucherM14(t, confirmer());
      // sans référence : le formulaire refuse, rien n'est écrit
      await toucherM14(t, find.byKey(const Key('cfb:confirmer:valider')));
      final avant = m.collection('obligationsFiscales').toutes.firstWhere((o) => o['code'] == 'CNSS-VERSEMENT');
      expect(avant['aConfirmer'], true);
      expect(m.collection('historiqueObligations').toutes, isEmpty);
      await saisir(t, 'reference', 'Courrier CNSS n° 2026/118');
      await toucherM14(t, find.byKey(const Key('cfb:confirmer:valider')));
      final apres = m.collection('obligationsFiscales').toutes.firstWhere((o) => o['code'] == 'CNSS-VERSEMENT');
      expect(apres['aConfirmer'], false);
      expect(apres['confirmationReference'], 'Courrier CNSS n° 2026/118');
      expect(apres['confirmeePar'], isNotEmpty);
      final h = m.collection('historiqueObligations').toutes.where((o) => o['code'] == 'CNSS-VERSEMENT').toList();
      expect(h.length, 1);
      expect(h.first['aConfirmer'], true, reason: 'la version « à confirmer » est gardée, non réécrite');
      expect(m.collection('audit').toutes.where((x) => x['action'] == 'Confirmation d’obligation fiscale').length, 1);
      expect(confirmer(), findsNothing, reason: 'une obligation confirmée n\'a plus la commande');
      expect(find.byKey(const Key('cfb:confirmee:CNSS-VERSEMENT')), findsOneWidget);
    });

    casM14('la fiche RBAC de la DAF retire le geste réservé : « Confirmer » est ABSENT (le domaine refuse aussi), les autres détenteurs le gardent', (t) async {
      final m = avecVersement();
      final fiche = m.collection('rbac').toutes.firstWhere((f) => f['role'] == 'da');
      m.collection('rbac').mettreAJour(fiche['id'], {
        'droitsGestes': {...((fiche['droitsGestes'] as Map?) ?? const {}).cast<String, Object?>(), 'confirmer_obligation_fiscale': false}
      });
      await ouvrirM14(t, m, 'cfg-comptabilite', role: 'da');
      expect(find.byKey(const Key('cfb:a-confirmer:CNSS-VERSEMENT')), findsOneWidget);
      expect(confirmer(), findsNothing);
      await ouvrirM14(t, avecVersement(), 'cfg-comptabilite', role: 'admin');
      expect(confirmer(), findsOneWidget, reason: 'l\'administrateur garde le geste');
    });
  });

  group('le calendrier fiscal mensuel et le barème de l\'AIB sont ouverts au poste', () {
    casM14('le calendrier fiscal mensuel : octobre à la date du poste (le 10 samedi reporté au lundi 12), puis novembre', (t) async {
      final m = magasinM14();
      await ouvrirM14(t, m, 'm12-calendrier-fiscal');
      await t.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('cal:titre')), findsOneWidget);
      expect((t.widget(find.byKey(const Key('cal:titre'))) as Text).data, 'Octobre 2026');
      expect(find.byKey(const Key('cal:jour:2026-10-30')), findsOneWidget);
      expect(find.byKey(const Key('cal:ech:ITS:2026-10-12')), findsOneWidget, reason: 'le 10 octobre est un samedi : reporté au lundi 12, jamais avancé');
      await toucherM14(t, find.byKey(const Key('cal:suivant')));
      expect((t.widget(find.byKey(const Key('cal:titre'))) as Text).data, 'Novembre 2026');
      expect(find.byKey(const Key('cal:ech:ITS:2026-11-10')), findsOneWidget);
    });

    casM14('le barème de l\'AIB : deux barèmes lus, la retenue sur facture d\'un tiers (3 % et 5 %), l\'onglet Imputations et sa commande pour le détenteur du geste', (t) async {
      final m = magasinM14();
      await ouvrirM14(t, m, 'cfg-bareme-aib');
      for (final k in ['Barème de l’AIB', 'Situations actives', 'Versions du barème']) {
        expect(find.text(k), findsWidgets, reason: k);
      }
      expect(find.text('Tiers, personne physique (retenue sur sa facture)'), findsWidgets);
      expect(find.text('Tiers, personne morale (retenue sur sa facture)'), findsWidgets);
      await toucherM14(t, find.textContaining('Imputations ('));
      expect(find.textContaining('Le patient, lui, paie le montant total'), findsOneWidget);
      expect(find.byKey(const Key('aib:imputer')), findsOneWidget);
    });
  });
}
