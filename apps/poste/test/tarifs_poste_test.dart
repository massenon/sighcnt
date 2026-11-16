import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/persistance.dart';
import 'package:sigh_poste/donnees/tarifs_poste.dart';

/// LE RÉFÉRENTIEL DE PRIX AU POSTE (lot T6, étape 2) : les deux collections du jeu, les gardes du magasin (une version est IMMUABLE, les listes de lecture ne
/// s'éditent plus pour un prix), la projection de lecture et sa garde de parité, la reprise d'un magasin d'AVANT le référentiel, et le circuit tenu sur le magasin
/// (mère : écrit ; fileul : dépose une demande, la mère applique sous le rôle de son auteur).
final auj = DateTime(2026, 10, 30, 10);
String plus(int n) => tarIso(auj.add(Duration(days: n)));

Magasin jeu() => Magasin.depuisDossier(Magasin.collectionsDuJeu);

TarifsPoste poste(Magasin m, String role, {String nom = 'Agent', bool fileul = false, bool editer = true, String etiquette = 'P'}) => TarifsPoste(m,
    role: role,
    auteur: () => nom,
    fileul: fileul,
    peutEditerEcran: editer,
    peutEditerPour: (r) => const ['admin', 'da', 'direction'].contains(r),
    libelles: const {'da': 'Directrice de l’Administration et des Finances (DAF)', 'direction': 'Direction / Gérance'},
    horloge: () => auj,
    etiquette: etiquette);

DemandeProposition prop(String code, num prix, {String? date, bool valider = false}) =>
    DemandeProposition(code: code, prixNonAssure: prix, etatAssure: 'unique', dateEffet: date ?? plus(3), motif: 'Test T6', valider: valider);

void main() {
  group('le jeu livré porte le référentiel', () {
    test('202 prestations, 241 versions (CERT-CA, lot TARIF-FIX) ; l\'accesseur lit les trois espaces de codes', () {
      final m = jeu();
      final h = TarifsPoste.lire(m);
      expect([h.tarifs.length, h.versions.length], [202, 241]);
      expect(TarifsPoste.prix(m, 'SIV', null, false, aujourdhui: auj).montant, TarifsPoste.prix(m, 'SO02', null, false, aujourdhui: auj).montant, reason: 'SIV est l\'alias de grille de SO02');
      expect(TarifsPoste.prixAnalyse(m, 'L01', aujourdhui: auj), 2000);
      expect(TarifsPoste.prixActe(m, 'MG01', aujourdhui: auj, assure: true), 3000);
      expect(TarifsPoste.prixGrille(m, 'IMG-ECHO-PEL', aujourdhui: auj, assure: false).montant, 9000);
      final actes = TarifsPoste.actes(m, aujourdhui: auj);
      expect(actes.length, 73, reason: 'les 73 actes du jeu (69 + 3 journées + GY-SAA)');
      expect(actes.firstWhere((a) => a['code'] == 'MG01')['prix'], 5000);
    });

    test('la projection de lecture : 39 lignes LABO au démarrage, puis 0 écart de parité ; aucune ligne de journal', () {
      final m = jeu();
      final avant = m.collection('audit').toutes.length;
      expect(TarifsPoste.parites(m, auj).length, 39);
      expect(TarifsPoste.projeter(m, auj), 39);
      expect(TarifsPoste.parites(m, auj), isEmpty, reason: 'garde de parité : la projection dit ce que le référentiel dit');
      expect(TarifsPoste.projeter(m, auj), 0, reason: 'idempotente');
      expect(m.collection('audit').toutes.length, avant, reason: 'ce n\'est pas un geste : aucune ligne de journal');
      expect(m.collection('catalogueTarifs').actives.firstWhere((t) => t['code'] == 'LAB-AKOP')['prixNonAssure'], 2000);
    });

    test('la projection suit le jour : une version à venir bascule le jour dit, sans tâche de minuit', () {
      final m = jeu();
      final t = poste(m, 'da', nom: 'DAF');
      expect(t.proposer(prop('MG01', 5500, date: plus(2), valider: true)).ok, isTrue);
      expect(m.collection('actes').actives.firstWhere((a) => a['code'] == 'MG01')['prix'], 5000, reason: 'à venir : le prix d\'aujourd\'hui ne bouge pas');
      expect(TarifsPoste.projeterSiNouveauJour(m, auj), 0);
      expect(TarifsPoste.projeterSiNouveauJour(m, auj.add(const Duration(days: 2))), greaterThan(0));
      expect(m.collection('actes').actives.firstWhere((a) => a['code'] == 'MG01')['prix'], 5500);
      expect(TarifsPoste.prixActe(m, 'MG01', aujourdhui: auj, date: plus(1)), 5000);
      expect(TarifsPoste.prixActe(m, 'MG01', aujourdhui: auj, date: plus(2)), 5500);
    });
  });

  group('les lecteurs en LISTE résolvent à la date de la PIÈCE, jamais à celle de l\'horloge (sonde de la mutation « prix d\'aujourd\'hui »)', () {
    test('actes, analyses, types de chambre, entrée de grille et grille : l\'ancien prix la veille de la date d\'effet, le nouveau le jour dit', () {
      final m = jeu();
      final t = poste(m, 'da', nom: 'DAF');
      final h = TarifsPoste.lire(m);
      // Un acte, une chambre et une ligne de grille : des versions validées à venir (J+5).
      final grilleEcho = '${h.parGrille['IMG-ECHO-PEL']!['code']}';
      for (final code in ['MG01', 'HO01', grilleEcho]) {
        expect(t.proposer(prop(code, 77777, date: plus(5), valider: true)).ok, isTrue, reason: code);
      }
      // Une analyse : on tranche Oui, à J+5, la proposition de la grille imprimée qui attend.
      final propose = h.versionsDe('L01').last;
      expect(propose['statut'], 'propose');
      expect(t.decider('${propose['id']}', 'oui', dateEffet: plus(5)).ok, isTrue);
      final nouveauL01 = TarifsPoste.lire(m).versionsDe('L01').last['prixNonAssure'];
      expect(nouveauL01, isNot(2000), reason: 'la grille imprimée porte un autre prix que la migration');
      for (final (jour, attendu) in [(plus(4), false), (plus(5), true)]) {
        final nom = attendu ? 'le jour dit' : 'la veille';
        expect(TarifsPoste.actes(m, aujourdhui: auj, date: jour).firstWhere((a) => a['code'] == 'MG01')['prix'], attendu ? 77777 : 5000, reason: 'actes, $nom');
        expect(TarifsPoste.analyses(m, aujourdhui: auj, date: jour).firstWhere((a) => a['code'] == 'L01')['prix'], attendu ? nouveauL01 : 2000, reason: 'analyses, $nom');
        expect(TarifsPoste.typesChambre(m, aujourdhui: auj, date: jour).first['tarif'], attendu ? 77777 : isNot(77777), reason: 'chambres, $nom');
        expect(TarifsPoste.entreeGrille(m, 'IMG-ECHO-PEL', aujourdhui: auj, date: jour)!['prixNonAssure'], attendu ? 77777 : 9000, reason: 'entrée de grille, $nom');
        expect(TarifsPoste.grille(m, aujourdhui: auj, date: jour, famille: 'IMAGERIE').firstWhere((e) => e['code'] == 'IMG-ECHO-PEL')['prixNonAssure'], attendu ? 77777 : 9000, reason: 'grille, $nom');
      }
      // Sans date : le jour de l'horloge fournie (le 30/10), donc l'ancien prix.
      expect(TarifsPoste.actes(m, aujourdhui: auj).firstWhere((a) => a['code'] == 'MG01')['prix'], 5000);
    });
  });

  group('les gardes du magasin tiennent la règle AU MOTEUR (masquer un bouton ne protège rien)', () {
    test('une version est IMMUABLE : le prix, l\'archivage et le retrait d\'une version valide sont refusés', () {
      final m = jeu();
      final col = m.collection('versionsTarif');
      expect(() => col.mettreAJour('SO12@origine@1', {'prixNonAssure': 1}), throwsA(isA<EcritureRefusee>()));
      expect(() => col.archiver('SO12@origine@1'), throwsA(isA<EcritureRefusee>()));
      expect(() => col.mettreAJour('SO12@origine@1', {'statut': 'retire'}), throwsA(isA<EcritureRefusee>()));
      expect(() => col.inserer({'id': 'SO12@origine@1', 'code': 'SO12', 'version': 1}), throwsA(isA<EcritureRefusee>()), reason: 'une version ne se réécrit pas par une insertion');
      final id = col.toutes.firstWhere((v) => v['statut'] == 'propose')['id'];
      expect(() => col.mettreAJour(id, {'statut': 'refuse', 'motifDecision': 'x'}), returnsNormally, reason: 'seule une proposition se décide');
      expect(() => col.mettreAJour(id, {'statut': 'valide'}), throwsA(isA<EcritureRefusee>()), reason: 'une version refusée ne redevient pas valide');
      expect(m.collection('audit').toutes.where((a) => a['action'] == 'Écriture refusée').length, greaterThanOrEqualTo(5), reason: 'RG-12 : chaque refus est journalisé');
    });

    test('`actes`, `analyses` et `catalogueTarifs` ne s\'éditent plus pour un prix ; le libellé reste libre', () {
      final m = jeu();
      final acte = m.collection('actes').actives.firstWhere((a) => a['code'] == 'MG01');
      expect(() => m.collection('actes').mettreAJour(acte['id'], {'prix': 9999}), throwsA(isA<EcritureRefusee>()));
      expect(() => m.collection('actes').mettreAJour(acte['id'], {'secteur': 'Autre secteur'}), returnsNormally);
      final ana = m.collection('analyses').actives.first;
      expect(() => m.collection('analyses').mettreAJour(ana['id'], {'prix': 1}), throwsA(isA<EcritureRefusee>()));
      final t = m.collection('catalogueTarifs').actives.first;
      expect(() => m.collection('catalogueTarifs').mettreAJour(t['id'], {'prixNonAssure': 1}), throwsA(isA<EcritureRefusee>()));
      try {
        m.collection('actes').mettreAJour(acte['id'], {'prix': 9999});
      } on EcritureRefusee catch (e) {
        expect(e.motif, contains('Tarifs et prix'));
      }
    });
  });

  group('le circuit tenu sur le magasin de la mère', () {
    test('propose, décide, journalise une ligne par transition, projette ; le retour part à l\'auteur', () {
      final m = jeu();
      final comptable = poste(m, 'comptable', nom: 'Aude COMPTA');
      final r = comptable.proposer(prop('MG01', 5200, date: plus(1)));
      expect(r.ok, isTrue);
      final id = r.version!['id'] as String;
      expect(r.version!['proposeRole'], 'comptable');
      expect(TarifsPoste.prixActe(m, 'MG01', aujourdhui: auj, date: plus(1)), 5000, reason: 'une proposition ne change RIEN');
      expect(poste(m, 'comptable').decider(id, 'oui').refus!.code, 'VALIDATION_RESERVEE');
      final daf = poste(m, 'da', nom: 'Yvette DAF');
      expect(daf.decider(id, 'non', motif: '').refus!.code, 'MOTIF_REQUIS');
      final oui = daf.decider(id, 'oui');
      expect(oui.ok, isTrue);
      expect(TarifsPoste.prixActe(m, 'MG01', aujourdhui: auj, date: plus(1)), 5200);
      final lignes = m.collection('audit').toutes.where((a) => '${a['action']}'.startsWith('Changement de prix')).map((a) => a['action']).toList();
      expect(lignes, containsAll(['Changement de prix : proposition', 'Changement de prix : validation']));
      // Le retour à l'auteur : une notification adressée au poste du comptable.
      final n = m.collection('notifications').toutes.where((x) => x['type'] == 'prix_decide').toList();
      expect(n.length, 1);
      expect([n.first['poste'], n.first['destinataire']], ['comptable', 'Aude COMPTA']);
      expect(n.first['libelle'], 'Votre changement de prix MG01 a été accepté');
    });

    test('« Valider » en un geste lève le marquage « tarif d\'attente » (version et fiche de l\'analyse) et projette', () {
      final m = jeu();
      // L05 : une analyse SANS ligne de grille (donc sans proposition en attente), au tarif d'attente de la collection `analyses`.
      final fiche = m.collection('analyses').actives.firstWhere((a) => a['code'] == 'L05');
      expect(fiche['tarifProvisoire'], true);
      final prix = (fiche['prix'] as num).toInt();
      final daf = poste(m, 'da', nom: 'Yvette DAF');
      final r = daf.proposer(prop('L05', prix + 100, date: plus(0), valider: true));
      expect(r.ok, isTrue, reason: '${r.refus}');
      expect(r.valideeEnUnGeste, isTrue);
      expect(m.collection('analyses').parId(fiche['id'])!['prix'], prix + 100, reason: 'la projection est refaite à la décision');
      final versions = TarifsPoste.lire(m).versionsDe('L05');
      expect(versions.first['provisoire'], false, reason: 'le Oui arrête le marquage porté par la version 1');
      expect(versions.first['arretePar'], 'Yvette DAF');
      expect(m.collection('analyses').parId(fiche['id'])!['validePar'], 'Yvette DAF', reason: 'la fiche de la famille du centre des validations est validée du même geste');
    });

    test('la durée de validité d\'une pro-forma : 30 jours par défaut, réglage en base, journalisé, réservé', () {
      final m = jeu();
      final daf = poste(m, 'da', nom: 'DAF');
      expect(daf.validiteProformaJours(), 30);
      expect(poste(m, 'caissier').definirValiditeProforma(10).refus!.code, 'REGLAGE_RESERVE');
      expect(daf.definirValiditeProforma('x').refus!.code, 'DUREE_INVALIDE');
      final r = daf.definirValiditeProforma(10, motif: 'test');
      expect([r.ok, r.valeur!.avant], [true, 30]);
      expect(daf.validiteProformaJours(), 10);
      expect(m.collection('audit').toutes.any((a) => a['action'] == 'Validité d’une pro-forma'), isTrue);
    });
  });

  group('un fileul ne peut pas écrire une version : il dépose, la mère applique', () {
    test('la proposition d\'un fileul : aucune version écrite localement, une demande déposée ; la mère l\'applique sous le rôle de son auteur', () {
      final mere = jeu(), fileul = jeu();
      final f = poste(fileul, 'direction', nom: 'La Direction', fileul: true, etiquette: 'F');
      final avant = fileul.collection('versionsTarif').toutes.length;
      final r = f.proposer(prop('MG01', 5300, date: plus(2)));
      expect(r.ok && r.depose, isTrue, reason: '${r.refus}');
      expect(fileul.collection('versionsTarif').toutes.length, avant, reason: 'famille R : la mère seule écrit une version');
      final dem = fileul.collection('propositionsTarif').toutes.single;
      expect([dem['genre'], dem['etat'], dem['demandeRole'], dem['demandePar']], ['proposition', 'deposee', 'direction', 'La Direction']);
      // Le fileul qui tenterait d'écrire quand même est refusé (garde « réglé sur la mère » posée par l'application de la configuration).
      // La demande voyage (le pont) ; la mère l'applique.
      mere.collection('propositionsTarif').appliquerDistante({...dem});
      final m = poste(mere, 'admin', nom: 'Poste mère', etiquette: 'M');
      expect(m.appliquerDemandes(), 1);
      final traitee = mere.collection('propositionsTarif').toutes.single;
      expect([traitee['etat'], traitee['traitePar']], ['appliquee', 'Poste mère']);
      final v = mere.collection('versionsTarif').toutes.firstWhere((x) => x['id'] == traitee['versionId']);
      expect([v['statut'], v['proposePar'], v['proposeRole']], ['propose', 'La Direction', 'direction']);
      expect(m.appliquerDemandes(), 0, reason: 'une demande n\'est appliquée qu\'une fois');
      // La décision de la Direction (fileul) est elle aussi une demande, appliquée par la mère sous le rôle `direction`.
      mere.collection('versionsTarif').toutes; // la mère porte la version ; le fileul la reçoit par la configuration
      fileul.collection('versionsTarif').appliquerDistante({...v});
      final d = f.decider('${v['id']}', 'oui');
      expect(d.ok && d.depose, isTrue, reason: '${d.refus}');
      expect(fileul.collection('versionsTarif').parId(v['id'])!['statut'], 'propose', reason: 'rien n\'est décidé localement');
      final demD = fileul.collection('propositionsTarif').toutes.firstWhere((x) => x['genre'] == 'decision');
      mere.collection('propositionsTarif').appliquerDistante({...demD});
      expect(m.appliquerDemandes(), 1);
      expect(mere.collection('versionsTarif').parId(v['id'])!['statut'], 'valide');
      expect(mere.collection('versionsTarif').parId(v['id'])!['roleDecision'], 'direction');
      expect(TarifsPoste.prixActe(mere, 'MG01', aujourdhui: auj, date: plus(2)), 5300);
    });

    test('la mère REFAIT les contrôles : une demande qui ne passe pas est REFUSÉE avec son code, et le dit au fileul', () {
      final mere = jeu();
      mere.collection('propositionsTarif').appliquerDistante({
        'id': 'DTF1', 'statut': 'actif', 'genre': 'proposition', 'etat': 'deposee', 'demandePar': 'Un caissier', 'demandeRole': 'caissier', 'demandeLe': plus(0),
        'code': 'MG01', 'prixNonAssure': 5400, 'etatAssure': 'unique', 'dateEffet': plus(2), 'motif': 'x',
      });
      mere.collection('propositionsTarif').appliquerDistante({
        'id': 'DTF2', 'statut': 'actif', 'genre': 'proposition', 'etat': 'deposee', 'demandePar': 'Un autre', 'demandeRole': 'comptable', 'demandeLe': plus(0),
        'code': 'MG02', 'prixNonAssure': 0, 'etatAssure': 'unique', 'dateEffet': plus(2), 'motif': 'x', 'valider': true,
      });
      // La mère n'accorde le droit d'éditer qu'aux rôles qu'elle connaît : un caissier, un comptable ne proposent pas, même si la demande le dit.
      final m = TarifsPoste(mere, role: 'admin', auteur: () => 'Poste mère', peutEditerPour: (r) => r == 'comptable', horloge: () => auj);
      expect(m.appliquerDemandes(), 2);
      expect(mere.collection('propositionsTarif').parId('DTF1')!['resultatCode'], 'PROPOSITION_RESERVEE');
      expect(mere.collection('propositionsTarif').parId('DTF2')!['resultatCode'], 'VALIDATION_RESERVEE', reason: 'valider en un geste n\'est pas modifier la fiche');
      expect(mere.collection('versionsTarif').toutes.length, 241, reason: 'aucune version écrite');
    });

    test('sur un fileul, « Oui à tout » dépose une demande par ligne : jamais sans la comparaison affichée', () {
      final fileul = jeu();
      final f = poste(fileul, 'direction', nom: 'La Direction', fileul: true, etiquette: 'F');
      expect(f.deciderTous(comparaisonAffichee: false).refus!.code, 'COMPARAISON_REQUISE');
      final ids = [for (final v in fileul.collection('versionsTarif').toutes.where((v) => v['statut'] == 'propose').take(3)) '${v['id']}'];
      final r = f.deciderTous(comparaisonAffichee: true, ids: ids, dateEffet: plus(5));
      expect(r.ok, isTrue);
      expect(fileul.collection('propositionsTarif').toutes.length, 3);
      expect(fileul.collection('versionsTarif').toutes.where((v) => v['statut'] == 'valide' && v['origine'] == 'semence-grille').length, 0);
      expect(poste(fileul, 'caissier', fileul: true, editer: false).deciderTous(comparaisonAffichee: true, ids: ids).refus!.code, 'VALIDATION_RESERVEE');
    });
  });

  group('la reprise d\'un magasin d\'AVANT le référentiel', () {
    test('le prix facturé hier (collection `actes` relue du disque) devient la version 1 ; les éditions du catalogue sont listées, jamais appliquées', () async {
      final dossier = Directory.systemTemp.createTempSync('tarifs-reprise');
      addTearDown(() => dossier.deleteSync(recursive: true));
      final disque = PersistanceFichiers(dossier.path);
      final m0 = jeu();
      // Le poste d'avant : un acte dont la clinique avait corrigé le prix (la caisse le lisait), une ligne du catalogue éditée (que personne ne lisait).
      final actes = [for (final a in m0.collection('actes').toutes) {...a, if (a['code'] == 'MG01') 'prix': 5700, if (a['code'] == 'MG01') 'prixNonAssure': 5700}];
      await disque.ecrire('actes', actes);
      final cat = [for (final a in m0.collection('catalogueTarifs').toutes) {...a, if (a['code'] == 'IMG-ECHO-PEL') 'prixNonAssure': 9100}];
      await disque.ecrire('catalogueTarifs', cat);
      final m = jeu();
      await m.brancherPersistance(disque);
      expect(m.collectionsLuesDuDisque, containsAll(['actes', 'catalogueTarifs']));
      expect(m.collectionsLuesDuDisque.contains('tarifs'), isFalse);
      final mg = TarifsPoste.reprendre(m, horloge: () => auj);
      expect(mg, isNotNull);
      expect(TarifsPoste.prixActe(m, 'MG01', aujourdhui: auj), 5700, reason: 'le prix facturé hier est la version 1 : une facture émise ne bouge pas');
      expect(TarifsPoste.lire(m).versionsDe('MG01').first['origine'], 'migration');
      expect(TarifsPoste.prixGrille(m, 'IMG-ECHO-PEL', aujourdhui: auj).montant, 9000, reason: 'l\'édition du catalogue, que personne ne lisait, n\'est pas reprise');
      expect(mg!.ecarts.any((e) => e['type'] == 'catalogue-grille' && e['code'] == 'IMG-ECHO-PEL'), isTrue, reason: 'elle est LISTÉE');
      expect(m.collection('audit').toutes.any((a) => '${a['action']}'.startsWith('Reprise des prix')), isTrue);
      expect(TarifsPoste.parites(m, auj), isEmpty);
      // Une seconde reprise (les collections viennent maintenant du disque) ne refait rien.
      await m.ecrireMaintenant();
      final m2 = jeu();
      await m2.brancherPersistance(PersistanceFichiers(dossier.path));
      expect(TarifsPoste.reprendre(m2, horloge: () => auj), isNull);
      expect(TarifsPoste.prixActe(m2, 'MG01', aujourdhui: auj), 5700);
    });

    test('un magasin sans rien sur disque garde le jeu livré ; un fileul ne projette pas (il reçoit les collections de lecture avec la configuration)', () {
      final m = jeu();
      expect(TarifsPoste.reprendre(m, horloge: () => auj), isNull);
      expect(TarifsPoste.parites(m, auj), isEmpty, reason: 'la mère a projeté les 39 lignes LABO');
      final f = jeu();
      expect(TarifsPoste.reprendre(f, horloge: () => auj, fileul: true), isNull);
      expect(TarifsPoste.parites(f, auj).length, 39, reason: 'un fileul ne projette pas : seule la mère réécrit les collections de lecture');
    });
  });
}
