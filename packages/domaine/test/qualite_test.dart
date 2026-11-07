// Rejoue les vecteurs des enquêtes, de la satisfaction, du centre des validations, de la page publique et de la GED
// (prototype_html/build/vecteurs-qualite.js) : les sept écrans RÉELS pilotés dans Chrome, horloge figée au 16/08/2026 10 h.
import 'dart:math';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

import 'aide_vecteurs.dart';

typedef M = Map<String, Object?>;

M obj(Object? o) => (o as Map).cast<String, Object?>();
List<M> fl(Object? v) => [for (final x in (v as List)) obj(x)];

/// Les espaces fines et insécables de `money()` / `nombre()` se comparent comme des espaces.
String sp(Object? s) => '$s'.replaceAll(RegExp(r'[\s  ]+'), ' ').trim();

/// `compter()` du script : un groupe + son effectif → autant de fiches.
List<M> deplier(Object? v) => [
      for (final g in fl(v))
        for (var i = 0; i < (g['n'] as num); i++) {for (final e in g.entries) if (e.key != 'n') e.key: e.value}
    ];

final aujourdhui = DateTime(2026, 8, 16, 10);
final v = lireVecteurs('qualite');
List<M> cas(String cle) => fl(v[cle]);

void main() {
  group('satisfaction : tout est calculé depuis les réponses', () {
    for (final c in cas('satisfaction')) {
      test(c['nom'] as String, () {
        if (c['entrees'] == null) {
          // Aucune enquête active : l'écran le dit, il ne calcule rien.
          expect(qualEnqueteSatisfaction(const []), isNull);
          expect(sp(c['texte']), contains('Aucune enquête de satisfaction'));
          return;
        }
        final e = obj(obj(c['entrees'])['enquete']);
        final s = qualSatisfaction(e, fl(obj(c['entrees'])['reponses']));
        final k = fl(c['kpis']);
        expect(nombre(s.reponses), sp(k[0]['valeur']), reason: 'réponses');
        expect(s.noteGlobale, k[1]['valeur']);
        expect(sp(s.recommandation), sp(k[2]['valeur']));
        expect(nombre(s.avecCommentaire), sp(k[3]['valeur']));
        final g = c['graphique'];
        if (g == null) {
          expect(s.notes, isEmpty);
        } else {
          final attendu = ((obj(g)['series'] as List).first as Map)['data'] as List;
          expect([for (final n in s.notes) n.moyenne ?? 0], [for (final x in attendu) (x as num).toDouble()]);
          expect([for (final n in s.notes) n.libelle], (obj(g)['etiquettes'] as List).cast<String>());
        }
        final lues = [
          for (final x in s.commentaires) ['« ${x.texte} »', dateFR(DateTime.parse(x.date))]
        ];
        expect(lues, [
          for (final l in (c['commentaires'] as List)) [(l as List)[0], l[1]]
        ]);
      });
    }
  });

  group('un seul générateur : le formulaire naît du modèle', () {
    final enq = cas('enquetes');
    test('les champs engendrés suivent les questions, la question ajoutée au modèle paraît à la saisie', () {
      final c = enq.firstWhere((x) => x['nom'].toString().startsWith('Recueillir'));
      for (final (cle, qs) in [('ouverture1', c['questions']), ('ouverture2', c['questionsApres'])]) {
        final ouv = obj(c[cle]);
        final champs = qualChampsDepuisModele(qs);
        final vus = fl(ouv['champs']).skip(1).toList(); // le premier est le canal
        expect([for (final f in champs) f.nom], [for (final f in vus) f['nom']], reason: cle);
        expect([for (final f in champs) f.type == 'select' ? 'select' : 'textarea'], [for (final f in vus) f['balise']]);
        expect([for (final f in champs) f.requis ? '${f.libelle} *' : f.libelle], (ouv['libelles'] as List).skip(1).cast<String>());
        for (var i = 0; i < champs.length; i++) {
          if (champs[i].type == 'select') expect(champs[i].options, (vus[i]['options'] as List).cast<String>());
        }
      }
      expect(qualChampsDepuisModele(c['questionsApres']).length, qualChampsDepuisModele(c['questions']).length + 1);
    });

    test('les trois types de question', () {
      final c = enq.firstWhere((x) => x['nom'] == 'les trois types de question');
      final champs = qualChampsDepuisModele(obj(c['modele'])['questions']);
      expect([for (final f in champs) f.requis ? '${f.libelle} *' : f.libelle], (c['libelles'] as List).skip(1).cast<String>());
      expect([for (final f in champs) f.options], [for (final f in fl(c['champs']).skip(1)) f['options'] == null ? <String>[] : (f['options'] as List).cast<String>()]);
    });

    test('pleine largeur : seule la mise en page change', () {
      final modele = obj(cas('publique').first['enquete'])['questions'];
      final a = qualChampsDepuisModele(modele), b = qualChampsDepuisModele(modele, pleineLargeur: true);
      expect([for (final f in a) '${f.nom}|${f.libelle}|${f.type}|${f.requis}|${f.options}'], [for (final f in b) '${f.nom}|${f.libelle}|${f.type}|${f.requis}|${f.options}']);
      expect(b.every((f) => f.pleine), isTrue);
      expect(a.any((f) => f.pleine), isFalse);
    });

    test('la réponse recueillie au guichet', () {
      final c = enq.firstWhere((x) => x['nom'].toString().startsWith('Recueillir'));
      final r = qualReponse({'id': 'ENQ0001', 'questions': c['questionsApres']},
          {'Q_ACCUEIL': '5', 'Q_ATTENTE': '3', 'Q_PROPRETE': '4', 'Q_SOINS': '4', 'Q_RECO': 'Plutôt oui', 'Q_LIBRE': 'Mieux indiquer la salle', 'Q_NEUF': 'Oui'},
          aujourdhui: aujourdhui, canal: 'À la sortie', saisiPar: 'BASSONGUI Chabi Séko');
      final attendu = obj(c['reponse']);
      memes(r, attendu, 'reponse', ignorer: {'statut', 'jetonId', 'saisiPar'});
      expect(c['ajoutees'], 1);
    });

    test('un questionnaire sans question ne recueille rien ; une question à choix a besoin de ses choix', () {
      final c = enq.firstWhere((x) => x['nom'] == 'Nouveau modèle');
      expect(obj(c['refusSansQuestion'])['ajoutes'], 0);
      expect((obj(c['refusSansQuestion'])['toasts'] as List).first, contains('Un questionnaire sans question ne recueille rien.'));
      expect((obj(c['refusChoix'])['toasts'] as List).first, contains('Une question à choix a besoin de ses choix.'));
      expect(obj(obj(c['cree'])['questions'] is List ? (obj(c['cree'])['questions'] as List).first : {})['options'], ['Accueil', 'Caisse', 'Labo']);
    });
  });

  group('le lien de partage : un jeton daté et révocable', () {
    final partage = cas('enquetes').firstWhere((x) => x['nom'] == 'Partager à un tiers');
    test('la fiche du lien', () {
      final j = qualNouveauJeton(
          enquete: {'id': 'ENQ0001', 'titre': 'Satisfaction des patients'},
          jeton: 'x',
          anonyme: 'oui',
          usage: 'tablette',
          expireLe: '2026-09-15',
          note: 'Salle d’attente',
          aujourdhui: aujourdhui,
          ouvertPar: 'BASSONGUI Chabi Séko');
      memes(j, obj(partage['jeton']), 'jeton', ignorer: {'statut', 'jeton', 'ouvertPar'});
      expect(partage['formatJeton'], isTrue);
      expect(partage['lienSansIdEnquete'], isTrue);
    });
    test('le jeton tiré a 24 caractères de l’alphabet sans l, 1, o, 0 — et ne contient jamais l’identifiant de l’enquête', () {
      final alea = Random(7);
      final vus = <String>{};
      for (var i = 0; i < 200; i++) {
        final t = qualGenererJeton(alea.nextInt);
        expect(t, matches(RegExp(r'^[a-km-z2-9]{24}$')));
        vus.add(t);
      }
      expect(vus.length, 200);
    });
    test('révoquer ferme la porte sans rien effacer', () {
      final r = cas('enquetes').firstWhere((x) => x['nom'].toString().startsWith('Révoquer'));
      final avant = obj(r['avantRevocation']), apres = obj(r['apresRevocation']);
      final j = obj(partage['jeton']);
      expect(qualJetonOuvert({...j, 'statut': 'actif'}, aLaDate: '2026-08-16'), isTrue);
      expect(sp(fl(avant['kpis'])[3]['valeur']), '1');
      final revoque = {...j, 'statut': 'actif', 'revoqueLe': apres['revoqueLe']};
      expect(qualJetonOuvert(revoque, aLaDate: '2026-08-16'), isFalse);
      final e = qualEtatJeton(revoque, aLaDate: '2026-08-16');
      expect(e.libelle, 'Révoqué le 16/08/2026');
      expect(sp((apres['lignes'] as List).first), contains(e.libelle));
      expect(sp(fl(apres['kpis'])[3]['valeur']), '0', reason: 'plus de lien ouvert');
      expect(apres['boutonRevoquer'], isFalse);
      expect(apres['reponsesConservees'], greaterThan(0));
      expect(sp((avant['lignes'] as List).first), contains('Ouvert'));
    });
  });

  group('la page publique : la même réponse pour inconnu, expiré, révoqué', () {
    final pub = cas('publique');
    final etats = fl(obj(pub[0])['etats']);
    final enquete = obj(obj(pub[0])['enquete']);
    final jetons = [
      for (final e in etats)
        if (e['jeton'] != null) {...obj(e['jeton']), 'statut': obj(e['jeton'])['statut'] ?? 'actif', 'jeton': e['code']}
    ];
    for (final e in etats) {
      test(e['nom'] as String, () {
        final r = qualPagePublique(jetons: jetons, enquetes: [enquete], code: e['code'] as String?, aLaDate: '2026-08-16');
        final fermee = sp(e['texte']).contains('Ce lien n’est plus valable.');
        expect(r == null, fermee);
        if (r != null) {
          expect(sp(e['texte']), contains(qualMentionAnonymat(r.jeton['anonyme'] == true)));
          expect(e['liens'], 0, reason: 'aucun lien vers le logiciel');
          expect(e['menus'], 0, reason: 'ni ruban ni barre');
          final champs = qualChampsDepuisModele(r.enquete['questions'], pleineLargeur: true);
          final noms = [for (final f in fl(e['champs'])) f['nom']];
          expect(noms, [if (r.jeton['anonyme'] != true) '_repondant', for (final f in champs) f.nom]);
          // Aucune donnée médicale : pas de diagnostic, pas de motif de venue.
          expect(sp(e['texte']).toLowerCase(), isNot(contains('diagnostic')));
        } else {
          // Ce qui reste : l'identité de la clinique et le téléphone — jamais le titre d'une enquête.
          expect(sp(e['texte']), isNot(contains('Satisfaction des patients')));
        }
      });
    }
    test('révoqué = inconnu : une seule réponse', () {
      expect(obj(pub[2])['memeReponse'], isTrue);
      final textes = {for (final n in ['révoqué', 'inconnu', 'expiré hier', 'archivé', 'adresse sans jeton', 'jeton valide mais enquête introuvable']) etats.firstWhere((e) => e['nom'] == n)['texte']};
      expect(textes.length, 1);
    });
    test('envoyer une réponse', () {
      for (final e in fl(obj(pub[1])['envois'])) {
        final j = jetons.firstWhere((x) => x['jeton'] == e['code']);
        if (e['ajoutees'] == 0) {
          // Le nominatif sans nom : refusé, rien n'est écrit.
          expect(j['anonyme'], isFalse);
          expect((e['nomRepondant'] as String).isEmpty, isTrue);
          expect((e['toasts'] as List).first, 'Merci de compléter les réponses attendues.');
          continue;
        }
        final r = qualReponse(enquete, obj(e['valeurs']),
            aujourdhui: aujourdhui, canal: qualCanalPublic, jetonId: '<id du lien>', saisiPar: qualSaisiPar(anonyme: j['anonyme'] == true, nom: e['nomRepondant'] as String?));
        memes(r, obj(e['reponse']), 'reponse', ignorer: {'statut'});
        expect(r['canal'], 'Lien public');
        if (j['anonyme'] == true) expect(r['saisiPar'], 'Réponse anonyme — lien partagé');
      }
    });
    test('un jeton se compare à la date : le jour même il est encore ouvert, la veille il ne l’est plus', () {
      bool ouvert(String code) => qualJetonOuvert(jetons.firstWhere((x) => x['jeton'] == code), aLaDate: '2026-08-16');
      expect(ouvert('echeancememe444444444444444'), isTrue);
      expect(ouvert('echu5555555555555555555555'), isFalse);
      expect(ouvert('sansfin8888888888888888888'), isTrue);
      expect(qualEtatJeton(jetons.firstWhere((x) => x['jeton'] == 'echu5555555555555555555555'), aLaDate: '2026-08-16').libelle, 'Expiré le 15/08/2026');
    });
  });

  group('centre des validations : quatre familles, jamais en masse', () {
    for (final c in cas('validations')) {
      test(c['nom'] as String, () {
        final e = obj(c['entrees']);
        final files = qualFilesValidation(
            demandesAnalyses: deplier(e['demandesAnalyses']),
            ecritures: deplier(e['ecritures']),
            besoinsToutes: deplier(e['besoins']),
            commandesToutes: deplier(e['commandes']),
            factures: deplier(e['factures']),
            resultatsImagerie: deplier(e['resultatsImagerie']),
            echeancesFiscales: deplier(e['echeancesFiscales']),
            aujourdhui: '2026-08-16');
        final vues = fl(c['files']);
        expect(files.length, vues.length);
        for (var i = 0; i < files.length; i++) {
          expect(files[i].libelle, (vues[i]['textes'] as List)[0]);
          expect(files[i].sousTitre, (vues[i]['textes'] as List)[1]);
          expect(files[i].compte == null ? '—' : nombre(files[i].compte), sp(vues[i]['compte']), reason: files[i].libelle);
          expect(files[i].nonAmorcee, files[i].compte == null);
        }
        final pros = qualProfessionnels(materiel: deplier(e['materiel']), plagesReactif: deplier(e['plagesReactif']));
        final bilan = qualBilanValidations(files, pros);
        final k = fl(c['kpis']);
        expect(nombre(bilan.gestes), sp(k[0]['valeur']));
        expect(bilan.filesTexte, sp(k[1]['valeur']));
        expect(nombre(bilan.professionnels), sp(k[2]['valeur']));
        expect(nombre(bilan.validees), sp(k[3]['valeur']));
        final lues = c['professionnels'] as List;
        for (var i = 0; i < pros.length; i++) {
          expect(sp(pros[i].titre), sp((lues[i] as List)[0]));
          expect(sp('${pros[i].qui} · ${pros[i].motif}'), sp(lues[i][1]));
        }
      });
    }
    test('arbitrages de la Direction et validations du 01/09, tels que la maquette les écrit', () {
      final c = cas('validations').first;
      final arb = c['arbitrages'] as List;
      expect([for (final a in qualArbitrages) [a.libelle, a.detail]], [for (final a in arb) [(a as List)[0], a[1]]]);
      final val = (c['validees'] as List);
      expect([for (final x in qualValidees) [x.$1, x.$2]], [for (final l in val) [(l as List)[0], l[1]]]);
    });
    test('l’écran n’offre aucune commande de validation : seulement « Y aller » et « Ouvrir »', () {
      final b = (cas('validations').first['boutons'] as List).cast<String>().toSet();
      expect(b.difference({'Y aller', 'Ouvrir'}), isEmpty);
    });
  });

  group('GED — bibliothèque de l’établissement', () {
    for (final c in fl(obj(v['ged'])['bibliotheque'])) {
      test(c['nom'] as String, () {
        final rows = fl(c['entrees'] ?? []);
        final b = qualGedBibliotheque(rows);
        final k = fl(c['kpis']);
        expect([for (final x in [nombre(b.numerises), nombre(b.valides), nombre(b.enAttente), nombre(b.rejetes), nombre(b.signes), nombre(b.archives), b.volume, nombre(b.consultations)]) sp(x)],
            [for (final x in k) sp(x['valeur'])]);
        final ex = fl(c['explorateur']);
        for (var i = 0; i < qualGedRattachements.length; i++) {
          final e = qualGedExplorateur(rows, qualGedRattachements[i]);
          expect(nombre(e.total), sp(ex[i]['total']));
          expect([for (final d in e.parCategorie) [d.$1, '${d.$2}']], [for (final d in (ex[i]['details'] as List)) (d as List).cast<String>()]);
        }
      });
    }
    test('le tiroir d’un document : sa traçabilité', () {
      final c = fl(obj(v['ged'])['bibliotheque']).first;
      final t = obj(c['tiroir']);
      final d = fl(c['entrees']).firstWhere((x) => x['reference'] == t['reference']);
      final trace = qualGedTrace(d);
      expect([for (final e in trace) sp('${e.$1}${e.$2}${e.$3}')], [for (final h in (t['historique'] as List)) sp(h)]);
    });
    test('les catégories sont celles de la maquette', () {
      final c = fl(obj(v['ged'])['bibliotheque']).first;
      final details = [for (final e in fl(c['explorateur'])) for (final d in (e['details'] as List)) (d as List)[0]];
      expect({for (final x in qualGedCategories) x.$2}, details.toSet());
    });
  });

  group('GED — workflow de validation', () {
    final wf = fl(obj(v['ged'])['workflow']);
    test('les indicateurs et l’ancienneté en attente', () {
      for (final c in wf.where((x) => x['entrees'] != null && x['kpis'] != null && x['circuit'] != null)) {
        final rows = fl(c['entrees']);
        final k = fl(c['kpis']);
        expect(nombre(rows.where((d) => d['etatValidation'] == 'en_attente').length), sp(k[0]['valeur']), reason: c['nom'] as String);
        expect(nombre(rows.where((d) => d['etatValidation'] == 'rejete').length), sp(k[1]['valeur']));
        expect(nombre(rows.where((d) => d['etatValidation'] == 'valide').length), sp(k[2]['valeur']));
        expect([for (final e in qualGedEtapes) e.$2], (c['circuit'] as List).cast<String>());
      }
      final a = wf.firstWhere((x) => x['nom'] == 'ancienneté');
      final jours = [for (final d in fl(a['entrees'])) qualGedAnciennete(d, aujourdhui)];
      expect(jours, [0, 1, 15, 16]);
      expect((a['rouges'] as List), ['16 j']);
    });
    test('valider un document le SIGNE ; valider une sélection ne signe pas (écart consigné)', () {
      final un = wf.firstWhere((x) => x['nom'] == 'valider un document');
      expect(qualGedValidationSignee, obj(un['apres']));
      final sel = wf.firstWhere((x) => x['nom'] == 'valider la sélection');
      expect(qualGedValidationSelection['etatValidation'], 'valide');
      expect(qualGedValidationSelection.containsKey('signe'), isFalse);
      expect(fl(sel['apres']).every((x) => x['etatValidation'] == 'valide'), isTrue);
    });
    test('rejeter renvoie le document à son déposant avec son motif', () {
      final rj = wf.firstWhere((x) => x['nom'] == 'rejeter avec motif');
      expect(qualGedRejet('Pièce illisible'), {'etatValidation': 'rejete', 'motifRejet': 'Pièce illisible'});
      expect(obj(rj['apres'])['motifRejet'], 'Pièce illisible');
    });
    test('« En attente depuis » compte des jours entiers jusqu’à aujourd’hui', () {
      final w = wf.first;
      final l = (w['lignes'] as List).cast<List>();
      final enAttente = fl(w['entrees']).where((d) => d['etatValidation'] == 'en_attente').toList();
      final tries = trierPar(enAttente, (d) => d['date'], descendant: true);
      for (var i = 0; i < l.length && i < 15; i++) {
        expect('${qualGedAnciennete(tries[i], aujourdhui)} j', l[i][7]);
        expect(tries[i]['reference'], l[i][1]);
      }
    });
  });

  group('GED — archivage & conservation', () {
    final ar = fl(obj(v['ged'])['archives']);
    for (final c in ar.where((x) => x['kpis'] != null)) {
      test(c['nom'] as String, () {
        final rows = fl(c['entrees']);
        final a = qualGedArchives(rows, aujourdhui);
        final k = fl(c['kpis']);
        expect([for (final x in [nombre(a.actives), nombre(a.definitives), nombre(a.echues), a.volume]) sp(x)], [for (final x in k) sp(x['valeur'])]);
        final an = obj(c['anneau']);
        expect([for (final e in qualGedParConservation(rows)) e.$1], (an['etiquettes'] as List).cast<String>());
        expect([for (final e in qualGedParConservation(rows)) e.$2], [for (final x in ((an['series'] as List).first as Map)['data'] as List) x as num]);
        final ba = obj(c['barres']);
        expect([for (final e in qualGedParCategorie(rows)) e.$1], (ba['etiquettes'] as List).cast<String>());
        expect([for (final e in qualGedParCategorie(rows)) e.$2], [for (final x in ((ba['series'] as List).first as Map)['data'] as List) x as num]);
        if (a.echues > 0) {
          expect(c['noteEchus'], qualGedNoteEchus(a.echues));
        } else {
          expect(c['noteEchus'], isNull);
        }
        // Échéance et statut de chaque ligne de la première page, dans l'ordre de la maquette (date croissante).
        final tries = trierPar(rows, (d) => d['date']);
        final lignes = (c['lignes'] as List).cast<List>();
        for (var i = 0; i < lignes.length; i++) {
          final d = tries[i];
          final e = qualGedEcheance(d)!;
          expect(lignes[i][0], d['reference']);
          expect(lignes[i][5], qualGedExpire(d, aujourdhui) ? 'Échue le ${dateFR(e)}' : dateFR(e), reason: '${d['reference']}');
          expect(lignes[i][6], d['archive'] == true ? 'Archive définitive' : 'Archive active');
        }
      });
    }
    test('l’échéance : le jour même elle est échue (comparée à 10 h), la veille aussi, le lendemain non', () {
      final b = ar.firstWhere((x) => x['nom'].toString().startsWith('bords'));
      final rows = {for (final d in fl(b['entrees'])) d['reference']: d};
      bool echu(String r) => qualGedExpire(rows[r]!, aujourdhui);
      expect(echu('DOC-A-3'), isTrue); // 15/08/2021 + 5 ans : échéance du 15/08/2026, la veille
      expect(echu('DOC-A-1'), isTrue); // 16/08/2021 + 5 ans : échéance du 16/08/2026 à 00 h, avant 10 h
      expect(echu('DOC-A-2'), isFalse); // 17/08/2021 + 5 ans : le lendemain
      expect(echu('DOC-A-6'), isFalse);
    });
    test('l’échéance est CALENDAIRE : 20 ans écoulés tombent le jour de l’anniversaire (écart E565 levé)', () {
      final d = {'date': '2025-04-13', 'conservation': 20};
      expect(dateFR(qualGedEcheance(d)!), '13/04/2045');
      // Un 29 février retombe, hors année bissextile, au 1er mars : la conservation n'est jamais écourtée.
      expect(dateFR(qualGedEcheance({'date': '2024-02-29', 'conservation': 1})!), '01/03/2025');
      expect(dateFR(qualGedEcheance({'date': '2024-02-29', 'conservation': 4})!), '29/02/2028');
      expect(dateFR(qualGedEcheance({'date': '2020-12-31', 'conservation': 5})!), '31/12/2025');
    });
    test('modifier un document écrit les cinq champs du formulaire, que l’écran n’affiche pas', () {
      final m = obj(obj(ar.firstWhere((x) => x['nom'] == 'modifier un document')['modif']));
      final ecrit = obj(m['ecrit']), avant = obj(m['avant']);
      expect(ecrit['libelle'], avant['libelle'], reason: 'le libellé affiché ne bouge pas');
      expect(ecrit['conservation'], avant['conservation'], reason: 'la durée affichée ne bouge pas');
      expect({for (final k in ['titre', 'categorie', 'dureeConservation', 'emplacement', 'observations']) k: ecrit[k]},
          {'titre': 'Titre de test', 'categorie': 'contrat', 'dureeConservation': 12, 'emplacement': 'Armoire B2', 'observations': 'À revoir'});
    });
    test('bordereau d’archivage', () {
      final b = obj((ar.first['bordereau'] as List).first);
      final a0 = qualGedArchives(fl(ar.first['entrees']), aujourdhui);
      expect([for (final c in (b['cartouche'] as List)) sp((c as List)[1])], [nombre(fl(ar.first['entrees']).length), nombre(a0.actives), nombre(a0.definitives), nombre(a0.echues), a0.volume, '16/08/2026'].map(sp).toList());
      expect(b['titre'], 'Bordereau d’archivage documentaire');
      expect(b['sousTitre'], 'Situation au 16/08/2026');
      expect((b['signatures'] as List).length, 2);
      final t = obj((b['tableaux'] as List).first);
      expect(t['entetes'], ['Référence', 'Document', 'Catégorie', 'Date', 'Conservation', 'Échéance', 'Statut']);
      expect(t['nbLignes'], 80, reason: 'plafonné à 80 lignes');
      final tries = trierPar(fl(ar.first['entrees']), (d) => d['date']).take(5).toList();
      final prem = (t['premieres'] as List).cast<List>();
      for (var i = 0; i < 5; i++) {
        expect(prem[i][2], qualGedCategorieLabel(tries[i]['categorie']), reason: 'la catégorie s’imprime en toutes lettres');
        expect(prem[i][5], dateFR(qualGedEcheance(tries[i])!));
      }
    });
  });
}
