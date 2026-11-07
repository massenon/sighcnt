// Rejoue les vecteurs de l'accueil M2 (prototype_html/build/vecteurs-agenda.js) : les écrans RÉELS — agenda, rendez-vous & visites, domicile, registre des
// appels, files d'attente, écran d'appel, file par cabinet, agenda du médecin — lus et pilotés dans Chrome à l'horloge figée du 16/08/2026 12:00 (UTC).
// Les jours se lisent à l'heure LOCALE : le banc est en UTC, les tests ne s'exécutent donc que dans ce fuseau.
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

import 'aide_vecteurs.dart';

void main() {
  final v = lireVecteurs('ag_agenda');
  final maintenant = DateTime(2026, 8, 16, 12, 0, 0);
  final horsUtc = DateTime.now().timeZoneOffset != Duration.zero
      ? 'les vecteurs sont engendrés en UTC'
      : null;
  const ignorer = {'id', 'patientId', 'creeLe', 'statutAvantArchivage'};

  AgFiche fiche(Map<String, Object?> m) => {...m};
  List<AgFiche> lot(Object? l) => [for (final m in liste(l)) fiche(m)];
  bool archivee(AgFiche f) => f['statut'] == 'archive';
  List<AgFiche> actives(List<AgFiche> l) => [for (final f in l) if (!archivee(f)) f];
  final patients = lot(v['patients']);
  final medecins = liste(v['medecins']);
  final base = lot(v['agendaFixtures']);
  // Le registre du médecin, des rappels et de la prise de rendez-vous est posé SANS archivage ; seule la lecture de l'agenda archive C00019.
  final sansArchive = [for (final f in base) f['reference'] == 'C00019' ? {...f, 'statut': 'terminee'} : f];

  String valeurs(List<AgKpi> k) => k.map((x) => '${x.libelle}=${x.valeur}').join('|');
  String lus(Object? kpis) =>
      liste(kpis).map((x) => '${x['label']}=${x['valeur']}').join('|');

  group('dates à la manière de JavaScript', () {
    test('une date seule vaut minuit UTC, un instant garde son jour local', () {
      expect(agJour('2026-08-16'), '2026-08-16');
      expect(agJour('2026-08-16T23:30:00.000Z'), '2026-08-16');
      expect(agJour('2026-08-16T09:00'), '2026-08-16');
      expect(agJour('pas une date'), 'NaN-NaN-NaN');
      expect(agJour(null), 'NaN-NaN-NaN');
    });
    test('la référence suivante se lit sur les fiches existantes, archivées comprises', () {
      expect(agReferenceSuivante('C', 5, [{'reference': 'C00009'}, {'reference': 'C00033', 'statut': 'archive'}, {'reference': 'A00099'}]), 'C00034');
      expect(agReferenceSuivante('C', 5, const []), 'C00001');
    });
    test('l’instant s’écrit comme toISOString : millisecondes et Z', () {
      expect(agInstant(DateTime.utc(2026, 8, 16, 12)), '2026-08-16T12:00:00.000Z');
    });
  }, skip: horsUtc);

  group('agenda : lecture', () {
    for (final c in liste(v['agenda'])) {
      test(c['nom'] as String, () {
        final lu = (c['lu'] as Map).cast<String, Object?>();
        final act = actives(base);
        expect(valeurs(agKpisAgenda(act, medecins.length, maintenant)), lus(lu['kpis']));
        final plage = c['plage'] as List?;
        final p = agFenetreParDefaut(maintenant);
        final jours = agJoursFenetre(plage?[0] as String? ?? p.debut, plage?[1] as String? ?? p.fin, maintenant);
        expect(agTitreFenetre(jours), lu['titre']);
        final grille = agGrille(act, jours, maintenant);
        final attendus = liste(lu['jours']);
        expect(grille.length, attendus.length);
        for (final (i, g) in grille.indexed) {
          final a = attendus[i];
          expect(g.entete.toUpperCase(), a['entete']);
          expect(g.mois, a['mois']);
          expect(g.rendezVous.isEmpty, a['aucun'], reason: g.entete);
          expect(g.autres > 0 ? '+ ${g.autres} autre(s)' : null, a['autres'], reason: g.entete);
          expect(g.aujourdhui, a['aujourdhui']);
          expect([
            for (final r in g.rendezVous) [heure(agDate(r['date'])!), r['patient'], r['motif']]
          ], [for (final it in a['items'] as List) it], reason: g.entete);
        }
        expect([for (final e in agChargeParPraticien(act, maintenant)) '${e.libelle}=${e.valeur}'],
            [for (final e in liste(lu['charge'])) '${e['label']}=${e['valeur']}']);
        final rep = agRepartitionParType(act);
        final att = lu['repartition'] as Map;
        expect(rep.libelles, att['labels']);
        expect(rep.valeurs, att['valeurs']);
      });
    }
    test('« Semaine en cours » ramène la plage par défaut', () {
      final p = agFenetreParDefaut(maintenant);
      expect(agTitreFenetre(agJoursFenetre(p.debut, p.fin, maintenant)),
          (v['agendaSemaineEnCours'] as Map)['titre']);
    });
    test('des bornes illisibles retombent sur la plage par défaut', () {
      expect(agJoursFenetre('', '', maintenant).length, 7);
    });
  }, skip: horsUtc);

  group('agenda : le rappel des échéances', () {
    final cas = liste(v['rappels']);
    final filtres = <List<AgFiche>>[
      base,
      [for (final f in base) if (f['reference'] != 'C00008') f],
      [for (final f in base) if (f['reference'] != 'C00008' && f['visiteurNom'] != 'kpade') f],
      <AgFiche>[],
    ];
    for (final (i, c) in cas.indexed) {
      test(c['nom'] as String, () {
        final r = agRappelEcheances(actives(filtres[i]), 0, maintenant);
        final msgs = liste(c['messages']);
        if (msgs.isEmpty) {
          expect(r, isNull);
        } else {
          expect(r!.message, msgs.first['message']);
          expect(r.detail, msgs.first['detail']);
        }
      });
    }
  }, skip: horsUtc);

  group('agenda : prendre un rendez-vous', () {
    for (final c in liste(v['priseRdv'])) {
      test(c['nom'] as String, () {
        final s = (c['saisie'] as Map).cast<String, Object?>();
        final saisie = <String, Object?>{
          for (final k in ['patientCode', 'medecin', 'type', 'date', 'motif']) k: s[k],
          'tarif': '${s['tarif']}'.isEmpty ? null : num.parse('${s['tarif']}'),
          'notifier': s['notifier'],
        };
        final creees = liste(c['creees']);
        if (creees.isEmpty) return; // le formulaire en erreur : l'écran refuse avant la fabrique
        final r = agNouveauRendezVous(saisie, patients: patients, existantes: base);
        memes(r, creees.first, 'rdv', ignorer: ignorer);
        final p = agFenetreParDefaut(maintenant);
        final f = agEtendreFenetre(p.debut, p.fin, '${r['date']}');
        expect([f.debut, f.fin], liste([c['lu']]).first['dates']);
        expect(agTitreFenetre(agJoursFenetre(f.debut, f.fin, maintenant)), liste([c['lu']]).first['titre']);
        final m = (c['messages'] as List).cast<Map>().first;
        if (s['notifier'] == true) {
          final t = agMessageTransmis(r);
          expect([m['message'], m['detail']], [t.message, t.detail]);
        } else {
          final t = agMessageEnregistre(r);
          expect([m['message'], m['detail']], [t.message, t.detail]);
        }
      });
    }
  }, skip: horsUtc);

  group('les suites d’un rendez-vous', () {
    for (final c in liste(v['suites'])) {
      final geste = c['geste'] as String;
      if (geste == 'Annuler le rendez-vous') continue; // l'archivage est celui du magasin (RG-14)
      test(c['nom'] as String, () {
        final avant = fiche((c['avant'] as Map).cast<String, Object?>());
        final saisie = (c['saisie'] as Map?)?.cast<String, Object?>();
        AgFiche? patch;
        if (geste == 'Marquer honoré') patch = agPatchHonore(maintenant);
        if (geste == 'Non honoré') patch = agPatchNonHonore('${saisie!['motif']}', maintenant);
        if (geste == 'Reporter' && '${saisie!['nouvelleDate']}'.isNotEmpty) {
          patch = agPatchReport(avant, '${saisie['nouvelleDate']}', '${saisie['motifReport']}', maintenant);
        }
        if (patch == null) {
          // « reporté sans date » : le formulaire refuse, la fiche ne bouge pas
          memes(c['apres'], c['avant'], 'inchangé', ignorer: ignorer);
          return;
        }
        memes({...avant, ...patch}, c['apres'], 'apres', ignorer: ignorer);
      });
    }
    test('un second report garde la PREMIÈRE date', () {
      final r = agPatchReport({'date': '2026-08-20T10:00', 'dateInitiale': '2026-08-14T10:00'}, '2026-08-30T10:00', 'Autre motif', maintenant);
      expect(r['dateInitiale'], '2026-08-14T10:00');
    });
  }, skip: horsUtc);

  group('rendez-vous & visites : lecture', () {
    final rv = (v['rendezvous'] as Map).cast<String, Object?>();
    final rf = lot(rv['fixtures']);
    final act = actives(rf);
    final liste0 = [for (final f in act) if (!agEstApure(f)) f];
    final defaut = (rv['defaut'] as Map).cast<String, Object?>();

    test('indicateurs : seul ce que l’agenda montre se compte', () {
      final k = agKpisRendezVous(act, maintenant);
      expect(valeurs(k), lus(defaut['kpis']));
      expect(k.map((x) => x.indice).toList(), liste(defaut['kpis']).map((x) => x['indice']).toList());
    });
    test('onglets : agenda, honorés (apurés), archivés', () {
      expect(liste(defaut['onglets'] == null ? [] : [{}]).length, 1);
      final onglets = (defaut['onglets'] as List).cast<String>();
      expect(onglets, [
        'Agenda — à venir, reportés, non honorés${liste0.length}',
        'Honorés (apurés de l’agenda)${act.where(agEstApure).length}',
        'Archivés${rf.where(archivee).length}',
      ]);
    });
    test('la liste est TRIÉE par date décroissante (instants, pas chaînes)', () {
      final tri = trierPar(liste0, (r) => agDate(r['date'])?.millisecondsSinceEpoch, descendant: true);
      final lignes = ((defaut['tables'] as List).first as Map)['lignes'] as List;
      expect([for (final l in lignes) (l as Map)['cellules'][0]], [for (final r in tri.take(12)) r['reference']]);
    });
    for (final f in liste(rv['filtres'])) {
      test('filtre ${f['filtre']} = ${f['valeur']}', () {
        final val = '${f['valeur']}';
        bool garde(AgFiche r) => switch (f['filtre']) {
              'Statut' => r['statut'] == val,
              'À statuer' => agFiltreSouffrance(r, val, maintenant),
              'Type' => r['type'] == val,
              'Praticien' => r['medecin'] == val,
              'Venu' => agFiltreVenu(r, val),
              'Venue' => agFiltreVenue(r, val),
              _ => true,
            };
        final res = liste0.where(garde).toList();
        final tri = trierPar(res, (r) => agDate(r['date'])?.millisecondsSinceEpoch, descendant: true);
        final pied = '${f['pied']}';
        final m = RegExp(r'sur (\d+) enregistrement').firstMatch(pied);
        expect(res.length, m == null ? 0 : int.parse(m.group(1)!));
        expect([for (final r in tri.take(12)) r['reference']], [for (final r in (f['refs'] as List)) r]);
      });
    }
    for (final p in liste(rv['plages'])) {
      test('plage de dates : ${p['nom']}', () {
        final res = liste0.where((r) => agDansPlage(r, 'date', '${p['du']}', '${p['au']}')).toList();
        final m = RegExp(r'sur (\d+) enregistrement').firstMatch('${p['pied']}');
        expect(res.length, m == null ? 0 : int.parse(m.group(1)!));
        // les onglets (leurs compteurs) ne suivent PAS la plage
        expect((p['onglets'] as List).first, 'Agenda — à venir, reportés, non honorés${liste0.length}');
      });
    }
    test('l’onglet Honorés ne suit pas la plage et trie par date décroissante (chaînes)', () {
      final lignes = (((rv['honores'] as Map)['tables'] as List).first as Map)['lignes'] as List;
      final h = agTrierTexte(act.where(agEstApure), (r) => '${r['date']}', descendant: true);
      expect([for (final l in lignes) (l as Map)['cellules'][0]], [for (final r in h.take(15)) r['reference']]);
    });
    test('la fiche : les notes du détail et la note d’assurance', () {
      for (final c in liste(rv['fiches'])) {
        final f = (c['fiche'] as Map?)?.cast<String, Object?>();
        if (f == null) continue;
        final r = rf.firstWhere((x) => x['reference'] == c['reference']);
        final texte = '${f['texte']}';
        for (final n in agNotesDetail(r, maintenant)) {
          expect(texte, contains(n.texte), reason: '${c['nom']}');
        }
        final p = patients.where((x) => x['id'] == r['patientId']).firstOrNull;
        final a = agNoteAssurance(p == null ? null : {...p, 'assureur': p['assureur']});
        if (a != null) expect(texte, contains(a), reason: '${c['nom']}');
        if (!agVrai(r['dateInitiale'])) expect(texte, isNot(contains('date initiale')));
      }
    });
  }, skip: horsUtc);

  group('rendez-vous & visites : écrire', () {
    final rv = (v['rendezvous'] as Map).cast<String, Object?>();
    final rf = lot(rv['fixtures']);
    // Ce que le formulaire livre : TOUS les champs, vides compris.
    AgFiche formulaire(Map<String, Object?> s) => {
          'patientCode': '',
          'visiteurNom': '',
          'visiteurPrenom': '',
          'visiteurQuartier': '',
          'visiteurTelephone': '',
          'medecin': '',
          'type': 'Consultation',
          'date': '',
          'motif': '',
          'diagnostic': '',
          'tarif': 3000,
          'statut': 'planifiee',
          ...s,
          if (s.containsKey('tarif') && s['tarif'] is String)
            'tarif': '${s['tarif']}'.isEmpty ? null : num.parse('${s['tarif']}'),
        };
    for (final c in liste(rv['creations'])) {
      test('création : ${c['nom']}', () {
        final saisie = formulaire((c['saisie'] as Map).cast<String, Object?>());
        final refus = agValiderVenue(saisie);
        final creees = liste(c['creees']);
        final msg = liste(c['messages']).first;
        if (creees.isEmpty) {
          expect(refus, msg['message']);
          return;
        }
        expect(refus, isNull);
        final r = agCompleterVenue(saisie, patients: patients, existantes: rf);
        memes(r, creees.first, 'creation', ignorer: ignorer);
        expect(r['patientCode'] == 'NON-PATIENT' ? r['patientId'] : 'x', r['patientCode'] == 'NON-PATIENT' ? isNull : 'x');
      });
    }
    for (final c in liste(rv['editions'])) {
      test('édition : ${c['nom']}', () {
        final avant = fiche((c['avant'] as Map).cast<String, Object?>());
        final valeurs = (c['valeursAvant'] as Map).cast<String, Object?>();
        final saisie = (c['saisie'] as Map).cast<String, Object?>();
        final f = formulaire({
          ...valeurs,
          'date': agIsoLocal(avant['date']),
          'diagnostic': avant['diagnostic'] ?? '',
          'tarif': avant['tarif'],
          'visiteurPrenom': avant['visiteurPrenom'] ?? '',
          'visiteurTelephone': avant['visiteurTelephone'] ?? '',
          ...saisie,
          if (saisie.containsKey('tarif')) 'tarif': num.parse('${saisie['tarif']}'),
        });
        final patch = agCompleterVenue(f, record: avant, patients: patients, existantes: rf);
        memes({...avant, ...patch}, c['apres'], 'edition', ignorer: ignorer);
        expect(patch['reference'], avant['reference'], reason: 'la référence ne change pas à l’édition');
      });
    }
    for (final c in liste(v['passages'])) {
      test('passage sans rendez-vous : ${c['nom']}', () {
        final s = (c['saisie'] as Map).cast<String, Object?>();
        final saisie = <String, Object?>{
          'patientCode': '',
          'visiteurNom': '',
          'visiteurPrenom': '',
          'visiteurQuartier': '',
          'visiteurTelephone': '',
          'type': 'Consultation',
          'medecin': '',
          'motif': '',
          'orientation': '',
          ...s,
          'tarif': '${s['tarif'] ?? ''}'.isEmpty ? null : num.parse('${s['tarif']}'),
        };
        final creees = liste(c['creees']);
        final msg = liste(c['messages']).first;
        final refus = agValiderVenue(saisie);
        if (creees.isEmpty) {
          expect(refus, msg['message']);
          return;
        }
        final r = agPassage(saisie, patients: patients, existantes: rf);
        memes(r, creees.first, 'passage', ignorer: ignorer);
        final t = agMessagePassage(r, s['priorite'] == true);
        expect([msg['message'], msg['detail']], [t.message, t.detail]);
      });
    }
  }, skip: horsUtc);

  group('interventions à domicile', () {
    final d = (v['domicile'] as Map).cast<String, Object?>();
    final df = lot(d['fixtures']);
    final act = actives(df);
    test('indicateurs : seules les prestations de type Domicile se comptent', () {
      expect(valeurs(agKpisDomicile(act)), lus((d['defaut'] as Map)['kpis']));
    });
    test('l’écran ne présente que le Domicile (E322) : l’onglet et le tableau', () {
      final dom = act.where((r) => r['type'] == 'Domicile').toList();
      expect(((d['defaut'] as Map)['onglets'] as List).first, 'Tous les interventions à domicile${dom.length}');
      expect(((d['defaut'] as Map)['onglets'] as List).last, 'Archivés${df.where(archivee).length}');
      final lignes = ((((d['defaut'] as Map)['tables']) as List).first as Map)['lignes'] as List;
      final tri = trierPar(dom, (r) => agDate(r['date'])?.millisecondsSinceEpoch, descendant: true);
      expect(lignes.length, tri.length);
    });
    test('création : le type est forcé à Domicile, le dossier rattaché, la référence suivante', () {
      final c = (d['creation'] as Map).cast<String, Object?>();
      final s = (c['saisie'] as Map).cast<String, Object?>();
      final saisie = <String, Object?>{
        ...s,
        'diagnostic': '',
        'tarif': num.parse('${s['tarif']}'),
        'fraisDeplacement': num.parse('${s['fraisDeplacement']}'),
        'type': 'Domicile',
      };
      final r = agCompleterPatient(saisie, patients: patients, existantes: df);
      memes(r, liste(c['creees']).first, 'domicile', ignorer: ignorer);
    });
  }, skip: horsUtc);

  group('registre des appels', () {
    final a = (v['appels'] as Map).cast<String, Object?>();
    final af = lot(a['fixtures']);
    test('indicateurs', () {
      expect(valeurs(agKpisAppels(actives(af))), lus((a['defaut'] as Map)['kpis']));
    });
    test('filtres : sens et objet', () {
      for (final f in liste(a['filtres'])) {
        final n = actives(af).where((r) => r[f['filtre'] == 'Sens' ? 'sens' : 'objet'] == f['valeur']).length;
        final m = RegExp(r'sur (\d+) enregistrement').firstMatch('${f['pied']}');
        expect(n, int.parse(m!.group(1)!), reason: '${f['filtre']} ${f['valeur']}');
      }
    });
    test('les objets d’appel sont ceux du standard', () {
      expect(liste(a['filtres']).where((f) => f['filtre'] == 'Objet').map((f) => f['valeur']).toList(), agObjetsAppel);
    });
    test('création : l’appel reçoit la référence suivante de la série (E327), et garde la sienne à l’édition', () {
      final c = (a['creation'] as Map).cast<String, Object?>();
      final r = agCompleterAppel((c['saisie'] as Map).cast<String, Object?>(), existantes: af);
      expect(r['reference'], liste(c['creees']).first['reference']);
      expect(agCompleterAppel({'objet': 'x'}, record: {'reference': 'A00007'}, existantes: af).containsKey('reference'), isFalse);
    });
  }, skip: horsUtc);

  group('file d’attente', () {
    final fl = (v['file'] as Map).cast<String, Object?>();
    final ff = lot(fl['fixtures']);
    test('priorités : libellés, rangs, notes', () {
      expect(agPriorites.map((p) => p.libelle).toList(), ['Urgence vitale', 'Urgence', 'Sur rendez-vous', 'Par ordre d’arrivée']);
      expect(agPriorite('inconnue').code, 'ordre_arrivee');
    });
    test('indicateurs', () {
      expect(valeurs(agKpisFile(ff, maintenant)), lus((fl['defaut'] as Map)['kpis']));
    });
    test('onglets : un par poste, avec le nombre en attente', () {
      expect([for (final p in agPostes) '${p.$2}${agFileTriee(ff, p.$1).length}'], (fl['defaut'] as Map)['onglets']);
    });
    for (final p in liste(fl['postes'])) {
      final code = agPostes.firstWhere((x) => p['onglet'].toString().startsWith(x.$2)).$1;
      test('classement du poste ${p['onglet']}', () {
        final tables = liste((p['lu'] as Map)['tables']);
        final tri = agFileTriee(ff, code);
        if (tables.isEmpty) {
          expect(tri, isEmpty);
          return;
        }
        final lignes = liste(tables.first['lignes']);
        expect([for (final l in lignes) (l['cellules'] as List)[1]], [for (final t in tri) t['numero']]);
        expect([for (final l in lignes) (l['cellules'] as List)[3]], [for (final t in tri) agPriorite(t['priorite']).libelle]);
        expect([for (final l in lignes) (l['cellules'] as List)[5]], [for (final t in tri) '${agAttenteMinutes(t, maintenant)} min']);
      });
    }
    test('écran d’appel : le dernier numéro appelé, les trois suivants, le nombre en attente — des NUMÉROS seulement', () {
      final cartes = agCartesAffichage(ff);
      final att = (fl['affichage'] as List).cast<List>();
      expect(cartes.length, att.length);
      for (final (i, c) in cartes.indexed) {
        expect(c.libelle.toUpperCase(), att[i][0]);
        expect(c.appele ?? '—', att[i][2]);
        expect(c.prochains.isEmpty ? '—' : c.prochains.join(' · '), att[i][4]);
        expect('${c.enAttente} patient(s) en attente', att[i][5]);
      }
      expect(agCartesAffichage(const []).every((c) => c.appele == null && c.prochains.isEmpty && c.enAttente == 0), isTrue);
    });
    test('file par cabinet : deux listes jamais fondues, urgences en tête (E325)', () {
      final cab = agCabinets(ff);
      final att = (fl['cabinet'] as Map).cast<String, Object?>();
      expect(valeurs(agKpisCabinets(cab)), lus(att['kpis']));
      final tables = liste(att['tables']);
      for (final (i, p) in cab.parPraticien.indexed) {
        expect([for (final t in p.$2) agLigneCabinet(t)], [for (final l in tables[i]['lignes'] as List) l]);
      }
      expect([for (final t in cab.vivier) agLigneCabinet(t)], [for (final l in tables.last['lignes'] as List) l]);
      expect(att['cartes'], [
        for (final p in cab.parPraticien) 'Cabinet — ${p.$1} (${p.$2.length})',
        'Vivier commun — par ordre d’arrivée, urgences en tête'
      ]);
      expect(valeurs(agKpisCabinets(agCabinets([for (final t in ff) if (agVrai(t['praticien'])) t]))), lus((fl['cabinetSansVivier'] as Map)['kpis']));
      expect(valeurs(agKpisCabinets(agCabinets(const []))), lus((fl['cabinetVide'] as Map)['kpis']));
    });
    for (final g in liste(fl['gestes'])) {
      final nom = g['nom'] as String;
      if (nom.startsWith('inscrire')) {
        test(nom, () {
          final s = (g['saisie'] as Map).cast<String, Object?>();
          final creees = liste(g['creees']);
          final msg = liste(g['messages']).first;
          if (creees.isEmpty) {
            expect(s['motif'], '');
            expect(msg['message'], 'Le formulaire comporte des erreurs.');
            return;
          }
          final t = agTicket(
              poste: g['poste'] == 'Accueil'
                  ? 'accueil'
                  : agPostes.firstWhere((x) => x.$2 == g['poste']).$1,
              patientCode: '${s['patientCode']}',
              priorite: '${s['priorite']}',
              motif: '${s['motif']}',
              praticien: s['praticien'] as String?,
              patients: patients,
              tous: ff,
              maintenant: maintenant);
          memes(t, creees.first, 'ticket', ignorer: {...ignorer, 'statut'});
          expect(msg['message'], 'Patient inscrit — numéro ${t['numero']}.');
        });
      } else if (nom.startsWith('appeler')) {
        test(nom, () {
          final premier = agFileTriee(ff, 'consultation').first;
          final servi = (g['apres'] as List).cast<Map>().firstWhere((x) => x['numero'] == premier['numero']);
          memes({...premier, ...agPatchAppel('BASSONGUI Chabi Séko', maintenant)}, servi, 'appel', ignorer: {...ignorer, 'statut'});
        });
      } else if (nom.startsWith('priorité avec')) {
        test(nom, () {
          final s = (g['saisie'] as Map).cast<String, Object?>();
          final avant = agFileTriee(ff, 'consultation');
          final cible = avant.last;
          final apres = [for (final t in ff) t['numero'] == cible['numero'] ? {...t, ...agPatchPriorite('${s['priorite']}', '${s['motifChangement']}')} : t];
          expect([for (final t in agFileTriee(apres, 'consultation')) t['numero']], g['apresNumeros']);
        });
      }
    }
    test('le numéro d’appel repart à 1 chaque matin, tous les tickets du jour comptent', () {
      expect(agNumeroAppel('caisse', const [], maintenant), 'C001');
      expect(agNumeroAppel('salle_soins', [{'poste': 'salle_soins', 'arriveeLe': '2026-08-15T09:00:00.000Z'}], maintenant), 'S001');
      expect(agNumeroAppel('imagerie', [{'poste': 'imagerie', 'arriveeLe': '2026-08-16T09:00:00.000Z'}, {'poste': 'imagerie', 'arriveeLe': '2026-08-16T10:00:00.000Z', 'statut': 'archive'}], maintenant), 'I003');
    });
    test('l’attente moyenne est arrondie à la minute, « — » sans patient servi', () {
      expect(agAttenteMoyenne(const []), '—');
      expect(agAttenteMoyenne([{'arriveeLe': '2026-08-16T08:00:00.000Z', 'serviLe': '2026-08-16T08:08:00.000Z'}, {'arriveeLe': '2026-08-16T08:00:00.000Z', 'serviLe': '2026-08-16T08:09:00.000Z'}]), '9 min');
    });
  }, skip: horsUtc);

  group('agenda du médecin', () {
    final m = (v['agendaMedecin'] as Map).cast<String, Object?>();
    final fx = actives(sansArchive);
    test('la liste des praticiens : nom — poste', () {
      expect([for (final x in medecins) {'valeur': x['nomComplet'], 'libelle': '${x['nomComplet']} — ${x['poste']}'}], liste(m['options']));
    });
    for (final p in liste(m['praticiens'])) {
      test('praticien ${p['praticien']}', () {
        final lu = (p['lu'] as Map).cast<String, Object?>();
        final rows = agAgendaDuMedecin(fx, '${p['praticien']}');
        expect(valeurs(agKpisAgendaMedecin(rows, maintenant)), lus(lu['kpis']));
        final tables = liste(lu['tables']);
        if (tables.isEmpty) {
          expect(rows, isEmpty);
          return;
        }
        final lignes = liste(tables.first['lignes']);
        expect(lignes.length, rows.length < 12 ? rows.length : 12);
        for (final (i, r) in rows.take(12).indexed) {
          expect((lignes[i]['cellules'] as List)[0], dateHeure(agDate(r['date'])!));
          expect((lignes[i]['cellules'] as List)[1], '${r['patient']} — ${agVrai(r['patientCode']) ? r['patientCode'] : '—'}');
        }
      });
    }
    test('un registre vide : quatre zéros', () {
      expect(valeurs(agKpisAgendaMedecin(const [], maintenant)), lus((v['agendaMedecinVide'] as Map)['kpis']));
    });
  }, skip: horsUtc);

  test('la page-renvoi des visites ne porte que deux boutons', () {
    expect((v['visites'] as Map)['boutons'], ['Ouvrir Rendez-vous & visites', 'Agenda']);
  });
}
