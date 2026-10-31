// Rejoue les vecteurs de CFG (B) (prototype_html/build/vecteurs-cfg-b.js) : les neuf écrans RÉELS pilotés dans Chrome sur le jeu du poste, horloge figée au
// 30/10/2026 10 h. Ici, les RÈGLES : indicateurs, fiches nées des saisies, valorisation mesurée, échéances à neuf dates, canaux, mot de passe, fermetures
// d'activité, corbeille, bilan d'un vidage.
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

typedef M = Map<String, Object?>;
M obj(Object? o) => (o as Map).cast<String, Object?>();
List<M> liste(Object? o) => [for (final x in (o as List)) obj(x)];
M lire(String nom) => obj(jsonDecode(File('test/vecteurs/$nom.json').readAsStringSync()));
const jeuDir = '../../apps/poste/assets/donnees/jeu';
List<M> jeu(String nom) => liste(jsonDecode(File('$jeuDir/$nom.json').readAsStringSync()));
List<M> actives(String nom) => [for (final f in jeu(nom)) if (f['statut'] != 'archive') f];

/// Les espaces (ordinaires, fines, insécables) ne comptent pas dans une comparaison de libellés.
String s(Object? v) => '$v'.replaceAll(RegExp(r'[\s  ]'), '');

void kpis(List<CfaKpi> obtenus, Object? attendus, {String ctx = ''}) {
  final a = (attendus as List).map(obj).toList();
  expect(obtenus.length, a.length, reason: ctx);
  for (var i = 0; i < a.length; i++) {
    expect(obtenus[i].libelle, a[i]['libelle'], reason: ctx);
    expect(s(obtenus[i].valeur), s(a[i]['valeur']), reason: '$ctx ${a[i]['libelle']}');
    expect(obtenus[i].indice, a[i]['indice'], reason: '$ctx indice ${a[i]['libelle']}');
  }
}

String jjmmaaaa(DateTime d) => dateFR(d);

void main() {
  final v = lire('cfb');
  final c = obj(v['constantes']);

  group('référentiels statiques = ceux de la maquette', () {
    test('sources de vérité, règles, valorisation, familles et groupes', () {
      final src = liste(c['sourcesVerite']);
      expect(cfbSourcesVerite.length, src.length);
      for (var i = 0; i < src.length; i++) {
        expect(cfbSourcesVerite[i].document, src[i]['document']);
        expect(cfbSourcesVerite[i].devient, src[i]['devient']);
        expect(cfbSourcesVerite[i].module, src[i]['module']);
        expect(cfbSourcesVerite[i].ecran, src[i]['ecran']);
        expect(cfbSourcesVerite[i].statut, src[i]['statut']);
      }
      final ps = obj(c['paramStock']);
      expect(cfbValorisationDefaut, ps['valorisationSortie']);
      expect([for (final o in cfbOptionsValorisation) o.$1], [for (final o in liste(ps['options'])) o['id']]);
      expect(cfbFamillesArticles.map((f) => f.$2).toList(), liste(c['famillesArticles']).map((f) => f['label']).toList());
      expect(cfbGroupesArticles.map((f) => f.$2).toList(), liste(c['groupesArticles']).map((f) => f['label']).toList());
      expect(cfbNs131.reference, obj(c['ns131'])['reference']);
      expect(cfbNs132.dateEffet, obj(c['ns132'])['dateEffet']);
      expect(cfbReglesGestion.length, 14);
    });

    test('calendrier fiscal, taux de paie et redevances ORTB (ceux du moteur de paie)', () {
      final cal = liste(c['calendrierFiscal']);
      expect(cfbCalendrierFiscal.length, cal.length);
      for (var i = 0; i < cal.length; i++) {
        final e = cfbCalendrierFiscal[i];
        expect([e.code, e.libelle, e.periodicite, e.jour, e.mois, e.part, e.declaration, e.note],
            [cal[i]['code'], cal[i]['libelle'], cal[i]['periodicite'], cal[i]['jour'], cal[i]['mois'], cal[i]['part'], cal[i]['declaration'], cal[i]['note']],
            reason: '${cal[i]['code']}');
      }
      expect(cfbCcibTotal, obj(obj(c['montantsFiscaux'])['ccib'])['total']);
      final pp = obj(c['paramPaie']);
      expect(paiCnssPatronale, obj(pp['cnss'])['patronale']);
      expect(paiCnssOuvriere, obj(pp['cnss'])['ouvriere']);
      expect(paiVpsTaux, obj(pp['vps'])['taux']);
      final ortb = obj(pp['ortb']);
      expect(paiSeuilTele, ortb['seuilTele']);
      expect(cfbCumulOrtbMaximum(), ortb['cumulMaximum']);
      expect(paiRedevances.map((r) => [r.id, r.montant, r.mois]).toList(), liste(ortb['redevances']).map((r) => [r['id'], r['montant'], r['mois']]).toList());
    });

    test('notifications, profils sonores, essentielles et libellés de collection', () {
      final mat = liste(obj(v['notifications'])['matrice']);
      expect(cfbNotifications.length, mat.length);
      for (var i = 0; i < mat.length; i++) {
        expect([cfbNotifications[i].libelle, cfbNotifications[i].detail, cfbNotifications[i].destinataires], [mat[i]['libelle'], mat[i]['detail'], mat[i]['dest']]);
        expect([cfbNotifications[i].app, cfbNotifications[i].sms, cfbNotifications[i].mail], mat[i]['canaux']);
      }
      expect(cfbProfilsAudio.map((p) => [p.$1, p.$2, p.$5]).toList(), liste(c['profilsAudio']).map((p) => [p['id'], p['label'], p['note']]).toList());
      expect(cfbParamsNotifDefaut, {...obj(c['defautsNotif']), 'volume': 0.8});
      expect(cfbEssentielles, c['essentielles']);
      final lib = obj(c['libelles']);
      for (final k in lib.keys) {
        expect(cfbLibelleCollection(k), (obj(lib[k])['module'], obj(lib[k])['entite']), reason: k);
      }
    });
  });

  group('cfg-centres-couts', () {
    final cc = obj(v['centres']);
    test('indicateurs sur les centres actifs, avant et après chaque création', () {
      kpis(cfbKpisCentres(actives('centresCouts')), obj(cc['lecture'])['kpis']);
      final apres1 = [...actives('centresCouts'), cfbFicheCentre({'libelle': 'A', 'type': 'support', 'responsable': ''}, jeu('centresCouts').length)];
      kpis(cfbKpisCentres(apres1), obj(cc['creationSansCode'])['kpis']);
    });
    test('code attribué sans saisie : CC + rang (archivées comprises) sur deux chiffres ; un code saisi est gardé tel quel', () {
      final sans = obj(cc['creationSansCode']);
      final attendue = liste(sans['fiche']).single;
      final f = cfbFicheCentre({'libelle': 'Centre Test Alpha', 'type': 'support', 'responsable': '', 'source': 'Décision de la Direction'}, jeu('centresCouts').length);
      expect(f['code'], attendue['code']);
      expect(f['code'], 'CC08');
      final avec = liste(obj(cc['creationAvecCode'])['fiche']).single;
      expect(cfbFicheCentre({'libelle': 'Centre Test Beta', 'code': 'XYZ', 'type': 'exploitation', 'responsable': 'TEST Resp', 'source': 'Décision de la Direction'}, 8)['code'], avec['code']);
    });
  });

  group('cfg-regles', () {
    final r = obj(v['regles']);
    final produits = actives('produits');
    test('indicateurs de la matrice', () => kpis(cfbKpisRegles(), obj(r['lecture'])['kpis']));
    test('« Groupes et familles » : une ligne par famille, rangée par groupe, avec quantités et valeurs du jeu', () {
      final t = liste(obj(r['lecture'])['tableaux']).first;
      final lignes = cfbParFamille(produits);
      final att = (t['lignes'] as List).cast<List>();
      expect(lignes.length, att.length);
      for (var i = 0; i < att.length; i++) {
        expect([lignes[i].groupe, lignes[i].famille, s(nombre(lignes[i].articles)), s(nombre(lignes[i].quantite)), s(money(lignes[i].valeur, avecDevise: false))],
            [att[i][0], att[i][1], s(att[i][2]), s(att[i][3]), s(att[i][4])]);
      }
    });
    test('effet mesuré : écart, nombre d’articles divergents, les deux phrases', () {
      final e = cfbEffetValorisation(produits);
      final (p1, p2) = cfbTextesEffet(e, produits.length);
      final carte = (r['cartesTexte'] as List)[0] as String;
      expect(s(carte), contains(s(p1)));
      expect(s(carte), contains(s(p2)));
      expect(e.divergents, 49);
    });
    test('texte de l’effet au-delà de 5 000 F : la phrase d’arrondi disparaît', () {
      final (p1, _) = cfbTextesEffet((ecart: 12345.4, divergents: 3), 10);
      expect(p1, 'Écart entre les deux méthodes : ${money(12345)} sur l’ensemble du stock.');
      expect(cfbTextesEffet((ecart: -245.6, divergents: 1), 10).$1, contains(money(246)));
    });
    test('confirmation du passage au CUMP : titre, message, badge de statut', () {
      final (titre, message) = cfbConfirmationValorisation(cfbOptionsValorisation[1]);
      final conf = r['confirmation'] as String;
      expect(conf, startsWith(titre));
      expect(conf, contains(message));
      expect(cfbTonStatutSource('Intégré'), 'success');
      expect(cfbTonStatutSource('Intégré — partiel'), 'warning');
      expect(cfbTonStatutSource('Intégré — tarifs à confirmer'), 'warning');
      expect(cfbTonStatutSource('À importer'), 'warning');
    });
    test('matrice et règles de gestion = lignes affichées', () {
      final t = liste(obj(r['lecture'])['tableaux']);
      final rg = (t[2]['lignes'] as List).cast<List>();
      expect(rg.length, cfbReglesGestion.length);
      for (var i = 0; i < rg.length; i++) {
        expect([rg[i][0], rg[i][1], rg[i][2]], [cfbReglesGestion[i].code, cfbReglesGestion[i].regle, cfbReglesGestion[i].module]);
      }
      final ver = (t[3]['lignes'] as List).cast<List>();
      expect(ver[0][0], cfbNs131.reference);
      expect(ver[1][0], cfbNs132.reference);
      expect([cfbMoteurPilote(cfbNs131), cfbMoteurPilote(cfbNs132)], [ver[0][5], ver[1][5]]);
    });
  });

  group('cfg-fiscalite', () {
    final f = obj(v['fiscalite']);
    for (final j in liste(f['dates'])) {
      final jour = (j['jour'] as List).cast<int>();
      test('échéances au ${jour[2]}/${jour[1] + 1}/${jour[0]}', () {
        final auj = DateTime(jour[0], jour[1] + 1, jour[2], 10);
        final l = cfbEcheances(auj);
        kpis(cfbKpisFiscalite(l), j['kpis']);
        final note = cfbNoteProches(l, jjmmaaaa);
        final attNote = (j['notes'] as List).cast<String>().where((n) => n.contains('échéance(s) dans les trente jours'));
        if (note == null) {
          expect(attNote, isEmpty);
        } else {
          expect(attNote.single, note);
        }
        // le tableau : trié par délai (stable), 6 colonnes
        final tri = trierPar(l, (e) => e.jours);
        final att = (liste(j['tableaux'])[2]['lignes'] as List).cast<List>();
        expect(tri.length, att.length);
        for (var i = 0; i < att.length; i++) {
          expect(tri[i].code, att[i][0], reason: 'rang $i');
          final date = jjmmaaaa(tri[i].echeance) + (tri[i].reporte ? ' reportée — jour ouvrable' : '');
          expect(att[i][3], date, reason: tri[i].code);
          expect(att[i][4], cfbLibelleDelai(tri[i].jours), reason: tri[i].code);
        }
      });
    }
    test('un samedi ou un dimanche est reporté au jour ouvrable SUIVANT, jamais avancé', () {
      expect(cfbJourOuvrable(DateTime(2026, 10, 10)), DateTime(2026, 10, 12)); // samedi
      expect(cfbJourOuvrable(DateTime(2027, 1, 10)), DateTime(2027, 1, 11)); // dimanche
      expect(cfbJourOuvrable(DateTime(2026, 11, 10)), DateTime(2026, 11, 10)); // mardi
    });
    test('le jour même, l’échéance du matin est déjà passée : elle bascule au mois suivant', () {
      final its = cfbCalendrierFiscal.first;
      expect(cfbProchaineEcheance(its, DateTime(2026, 11, 10, 10)).echeance, DateTime(2026, 12, 10));
      expect(cfbProchaineEcheance(its, DateTime(2026, 11, 9, 10)).echeance, DateTime(2026, 11, 10));
    });
  });

  group('cfg-comptabilite', () {
    final cp = obj(v['comptabilite']);
    test('indicateurs', () => kpis(cfbKpisComptabilite(), obj(cp['lecture'])['kpis']));
    test('assiettes, redevances ORTB et acomptes = ceux de la carte', () {
      final t = (cp['cartesTexte'] as List).cast<String>();
      expect(t[0], contains(cfbTexteAssiettes()));
      final (note, agent) = cfbTextesOrtb();
      expect(s(t[3]), contains(s(note)));
      expect(s(t[3]), contains(s(agent)));
      final acomptes = cfbAcomptesIs();
      expect(acomptes.length, 4);
      final tab = liste(obj(cp['lecture'])['tableaux'])[1]['lignes'] as List;
      for (var i = 0; i < 4; i++) {
        expect([tab[i][0], tab[i][1], tab[i][2]], [acomptes[i].libelle, cfbEcheanceAcompte(acomptes[i]), '${acomptes[i].part} % de l’impôt de l’exercice précédent']);
      }
    });
  });

  group('cfg-notifications', () {
    final n = obj(v['notifications']);
    test('indicateurs : comptés sur les canaux par défaut ; 20 canaux actifs après la saisie du vecteur', () {
      final defaut = [for (final x in cfbNotifications) cfbCanaux(x, null)];
      kpis(cfbKpisNotifications(defaut), n['kpis']);
      expect(cfbCanauxActifs(defaut), 20);
      // le vecteur décoche le canal 0 et coche le 4 : 20 canaux restent actifs
      final mod = [for (final x in cfbNotifications) cfbCanaux(x, null)];
      mod[0]['app'] = false;
      mod[1]['sms'] = true; // la case 4 de la grille = le SMS du deuxième événement
      expect(cfbCanauxActifs(mod), 20);
    });
    test('canaux enregistrés relus, sinon ceux par défaut', () {
      expect(cfbCanaux(cfbNotifications[2], {'rupture': {'app': false, 'sms': true, 'mail': true}}), {'app': false, 'sms': true, 'mail': true});
      expect(cfbCanaux(cfbNotifications[2], {}), {'app': true, 'sms': true, 'mail': false});
    });
    test('paramètres : défauts surchargés ; profil inconnu → Standard ; note d’attente', () {
      expect(cfbParamsNotif(null), obj(n['params0']));
      expect(cfbParamsNotif({'profil': 'critique', 'temporisation': 240})['temporisation'], 240);
      expect(cfbProfilAudio('critique').$5, obj(n['profilCritique'])['note']);
      expect(cfbProfilAudio('inconnu').$1, 'standard');
      for (final x in liste(n['variantes'])) {
        expect(cfbNoteAttente(x['att'] as int), (x['notes'] as List).where((t) => '$t'.contains('alerte(s) en attente')).single);
      }
      expect(cfbTemporisations.map((t) => [t.$1.toString(), t.$2]).toList(), liste(n['selects'])[1]['options']);
    });
  });

  group('cfg-compte', () {
    final cm = obj(v['compte']);
    test('mot de passe : confirmation d’abord, puis douze caractères ; la politique affichée n’est pas contrôlée', () {
      expect(cfbRefusMotDePasse('MotDePasse#2026X', 'MotDePasse#2027X'), 'Les deux mots de passe ne correspondent pas.');
      expect(cfbRefusMotDePasse('Court#1', 'Court#1'), 'Le mot de passe doit comporter au moins 12 caractères.');
      expect(cfbRefusMotDePasse('Exact12Chars', 'Exact12Chars'), isNull);
      expect(cfbRefusMotDePasse('aaaaaaaaaaaa', 'aaaaaaaaaaaa'), isNull);
      expect(obj(cm['mdpDivergent'])['toasts'], [
        ['Les deux mots de passe ne correspondent pas.']
      ]);
      expect(obj(cm['mdpCourt'])['toasts'], [
        ['Le mot de passe doit comporter au moins 12 caractères.']
      ]);
    });
    test('authentification à deux facteurs cochée d’office pour admin, direction, dm, da — et pour eux seuls', () {
      final parRole = obj(cm['parRole']);
      for (final role in parRole.keys) {
        expect(cfbMfaParDefaut(role), obj(parRole[role])['mfa'], reason: role);
      }
    });
  });

  group('cfg-modules', () {
    final md = obj(v['modules']);
    final rangees = jeu('modulesManifeste');
    final fiches = jeu('modulesActifs');
    test('écrans au périmètre et modules du logiciel = ceux du manifeste de la maquette', () {
      expect(cfbTousEcrans(rangees).length, md['tousEcrans']);
      final att = (md['modulesListe'] as List).cast<List>();
      final l = cfbListeModules(rangees);
      expect(l.map((m) => [m.code, m.label, m.icone, m.domaine, m.nbEcrans]).toList(), att);
    });
    test('indicateurs à l’ouverture : deux activités fermées, deux écrans retirés', () {
      final f = CfbFermetures.depuis(fiches);
      final ecrans = cfbTousEcrans(rangees);
      final retires = ecrans.where((e) => !f.ecranActif(e.id, e.module)).toList();
      kpis(cfbKpisModules(ecrans: ecrans.length, fermees: fiches.where((x) => x['statut'] != 'archive' && x['actif'] == false).length, retires: retires.length), obj(md['lecture'])['kpis']);
      final att = (liste(obj(md['lecture'])['tableaux'])[1]['lignes'] as List).cast<List>();
      expect(retires.map((e) => [e.label, e.moduleLabel, e.domaine, '${f.fermeturePour(e.id, e.module)?['motif'] ?? ''}']).toList(), att);
    });
    test('fermer M7 retire ses neuf écrans, sur 11 retirés ; la rouvrir les rend', () {
      final fm = {'module': 'M7', 'libelle': 'Module — Achats & Fournisseurs', 'actif': false, 'motif': 'x'};
      final f = CfbFermetures.depuis([...fiches, fm]);
      final ecrans = cfbTousEcrans(rangees);
      final retires = ecrans.where((e) => !f.ecranActif(e.id, e.module)).length;
      kpis(cfbKpisModules(ecrans: ecrans.length, fermees: 3, retires: retires), obj(md['fermerM7'])['kpis']);
      expect(f.ecranActif('m7-commandes', 'M7'), obj(md['fermerM7'])['ecransActifs']);
      expect(CfbFermetures.depuis([...fiches, {...fm, 'actif': true}]).ecranActif('m7-commandes', 'M7'), obj(md['rouvrirM7'])['ecranActif']);
    });
    test('fermeture de deux écrans nommés : les autres écrans du module restent ouverts', () {
      final fe = {'module': 'M6', 'libelle': 'Écrans de test', 'ecrans': ['m6-pertes', 'm6-lots'], 'actif': false, 'motif': 'Deux écrans fermés pour le test'};
      final f = CfbFermetures.depuis([...fiches, fe]);
      final o = obj(md['fermerEcrans']);
      expect([f.ecranActif('m6-pertes', 'M6'), f.ecranActif('m6-lots', 'M6'), f.ecranActif('m6-stock', 'M6')], [o['pertesActif'], o['lotsActif'], o['autreActif']]);
      expect(f.fermeturePour('m6-lots', 'M6')?['motif'], o['fermeturePour']);
    });
    test('une fiche ARCHIVÉE ne ferme plus rien (RG-14)', () {
      final fe = {'module': 'M6', 'ecrans': ['m6-pertes', 'm6-lots'], 'actif': false, 'statut': 'archive'};
      final f = CfbFermetures.depuis([...fiches, fe]);
      final o = obj(md['archivee']);
      expect([f.ecranActif('m6-pertes', 'M6'), f.ecranActif('m6-lots', 'M6')], [o['pertesActif'], o['lotsActif']]);
    });
    test('le NOYAU ne se ferme pas, quelle que soit la porte — refus nommé', () {
      final r = cfbRefusNoyau({'module': 'CFG', 'actif': true}, fermer: true)!;
      final o = obj(md['fermerNoyau']);
      expect([r.$1, r.$2], (o['toasts'] as List).first);
      expect(cfbRefusNoyau({'module': 'DASH'}, fermer: true), isNotNull);
      expect(cfbRefusNoyau({'module': 'CFG'}, fermer: false), isNull);
      expect(cfbRefusNoyau({'module': 'CFG', 'ecrans': ['cfg-tarifs']}, fermer: true), isNull);
      expect(cfbRefusNoyau({'module': 'M7'}, fermer: true), isNull);
    });
    test('code d’une activité déclarée : module + libellé en majuscules, hors A-Z0-9, huit caractères', () {
      expect(cfbCodeActivite('CFG', 'Activité noyau test'), obj(obj(md['declarerCfg'])['fiche'])['code']);
      expect(cfbCodeActivite('M6', 'Écrans de test'), obj(obj(md['declarerEcrans'])['fiche'])['code']);
    });
    test('confirmations : fermer / rouvrir, un module entier ou des écrans nommés', () {
      final (t1, m1, b1) = cfbConfirmationBascule({'module': 'M7', 'libelle': 'Module — Achats & Fournisseurs'}, fermer: true);
      expect(md['fermerM7Confirmation'], startsWith(t1));
      expect(s(md['fermerM7Confirmation']), contains(s(m1.replaceAll('\n\n', ' '))));
      expect(b1, 'Fermer l’activité');
      final (t2, m2, b2) = cfbConfirmationBascule({'module': 'M7', 'libelle': 'Module — Achats & Fournisseurs'}, fermer: false);
      expect(md['rouvrirM7Confirmation'], contains(t2));
      expect(s(md['rouvrirM7Confirmation']), contains(s(m2)));
      expect(b2, 'Rouvrir l’activité');
      expect(cfbPortee({'module': 'M7'}), 'Module M7 entier');
      expect(cfbPortee({'module': 'M5', 'ecrans': ['m5-banque-sang']}), '1 écran(s)');
    });
  });

  group('cfg-systeme', () {
    final sy = obj(v['systeme']);
    const techniques = {'rolesBase', 'modulesManifeste'};
    final noms = [
      for (final f in Directory(jeuDir).listSync().whereType<File>().map((f) => f.uri.pathSegments.last).where((n) => n.endsWith('.json') && n != 'referentiels.json'))
        f.replaceAll('.json', '')
    ].where((n) => !techniques.contains(n)).toList();
    // Le vecteur date du moment où le jeu comptait ses collections d'alors : les collections ajoutées depuis (support, appels…) ne font pas partie du bilan mesuré.
    final connues = {for (final x in (sy['collections'] as List).cast<List>()) x[0] as String};
    final fiches = {for (final n in noms.where(connues.contains)) n: jeu(n)};
    test('contenu du jeu : collections, enregistrements, actifs, archivés', () {
      final stats = [for (final n in fiches.keys) cfbStatCollection(n, fiches[n]!)];
      final att = {for (final x in (sy['collections'] as List).cast<List>()) x[0] as String: x};
      expect(stats.length, att.length);
      // Le vecteur a créé deux centres de coûts avant de mesurer : +2 sur cette seule collection.
      expect(stats.fold<int>(0, (a, x) => a + x.total) + 2, 11452);
      for (final x in stats) {
        final plus = x.nom == 'centresCouts' ? 2 : 0;
        expect([x.total + plus, x.actifs + plus, x.archives], [att[x.nom]![1], att[x.nom]![2], att[x.nom]![3]], reason: x.nom);
      }
    });
    test('bilan d’un vidage : 103 tables d’activité, 9 549 fiches ; 44 tables de paramétrage préservées', () {
      final conservees = {...cfbEssentielles, ...techniques};
      final plan = cfbPlanVidage({for (final n in fiches.keys) n: fiches[n]!.length}, conservees);
      final vd = obj(obj(sy['reinit'])['vider']);
      expect(plan.tables, vd['attenduTables']);
      expect(plan.enregistrements, vd['attenduLignes']);
      expect(plan.collections.toSet(), (vd['videes'] as List).cast<String>().toSet().difference(techniques));
      expect(cfbToastVidage(plan), ((vd['toasts'] as List).first as List).first);
      expect(fiches.length - plan.tables, 44);
    });
    test('corbeille : le libellé d’un élément, l’ordre par date d’archivage décroissante', () {
      final brute = liste(sy['corbeilleBrute']);
      final lignes = <CfbLigneCorbeille>[];
      for (final n in fiches.keys) {
        for (final f in fiches[n]!.where((f) => f['statut'] == 'archive')) {
          final (mod, ent) = cfbLibelleCollection(n);
          lignes.add(CfbLigneCorbeille(collection: n, module: mod, entite: ent, libelle: cfbLibelleElement(f), refId: '${f['id']}'));
        }
      }
      expect(lignes.map((l) => [l.id, l.module, l.entite, l.libelle]).toSet(), brute.map((b) => [b['id'], b['module'], b['entite'], b['libelle']]).toSet());
      expect(cfbLibelleElement({'nom': 'DUPONT', 'prenom': 'Aïcha'}), 'DUPONT Aïcha');
      expect(cfbLibelleElement({'nom': 'DUPONT'}), 'DUPONT');
      expect(cfbLibelleElement({'designation': 'Gants', 'code': 'X'}), 'Gants');
      expect(cfbLibelleElement({'id': 'Z1'}), 'Z1');
      final tri = cfbTrierCorbeille([
        const CfbLigneCorbeille(collection: 'a', module: 'M', entite: 'e', libelle: 'l', refId: '1', archiveLe: '2026-01-02'),
        const CfbLigneCorbeille(collection: 'a', module: 'M', entite: 'e', libelle: 'l', refId: '2'),
        const CfbLigneCorbeille(collection: 'a', module: 'M', entite: 'e', libelle: 'l', refId: '3', archiveLe: '2026-03-04'),
      ]);
      expect(tri.map((l) => l.refId), ['3', '1', '2']);
    });
  });
}
