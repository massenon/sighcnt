// Rejoue les vecteurs de la consultation engendrés par la maquette (prototype_html/build/vecteurs-consultation.js) : les référentiels, le dossier,
// la fiche (SEULE porte de prescription), la prescription (UNE facture globale), la prescription de soins, l'administration et son relais.
import 'dart:convert';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

import 'aide_vecteurs.dart';

/// Une mémoire qui se comporte comme le magasin de la maquette : insertion EN TÊTE, `statut: 'actif'` par défaut, archivage logique.
class Memoire implements StockCs {
  Memoire(Map<String, List<Map<String, Object?>>> jeux, this.maintenant)
      : _d = {
          for (final e in jeux.entries)
            e.key: [for (final f in e.value) {...f}]
        };
  final Map<String, List<Map<String, Object?>>> _d;
  final Map<String, List<Map<String, Object?>>> referentiels = {};
  @override
  final DateTime maintenant;
  int _n = 0;

  List<Map<String, Object?>> _c(String c) => _d.putIfAbsent(c, () => []);
  @override
  List<Map<String, Object?>> actives(String c) =>
      [for (final f in _c(c)) if (f['statut'] != 'archive') f];
  @override
  List<Map<String, Object?>> toutes(String c) => List.of(_c(c));
  @override
  Map<String, Object?>? parId(String c, Object? id) =>
      _c(c).where((f) => f['id'] == id).firstOrNull;
  @override
  Map<String, Object?> inserer(String c, Map<String, Object?> f) {
    final n = {'statut': 'actif', ...f};
    n['id'] ??= 'X${c.substring(0, 2)}${_n++}';
    _c(c).insert(0, n);
    return n;
  }

  @override
  void mettreAJour(String c, Object? id, Map<String, Object?> patch) =>
      parId(c, id)?.addAll(patch);
  @override
  void archiver(String c, Object? id) {
    final f = parId(c, id);
    if (f != null) f['statut'] = 'archive';
  }

  @override
  void defaire(String c, Object? id) => _c(c).removeWhere((f) => f['id'] == id);
  @override
  List<Map<String, Object?>> referentiel(String nom) => referentiels[nom] ?? [];

  Map<String, List<Map<String, Object?>>> instantane() =>
      {for (final e in _d.entries) e.key: [for (final f in e.value) _copie(f)]};
}

Map<String, Object?> _copie(Map<String, Object?> f) =>
    (jsonDecode(jsonEncode(f)) as Map).cast<String, Object?>();

const _surveilles = [
  'consultations', 'dossiersConsultation', 'ordonnances', 'demandesAnalyses', 'demandesImagerie',
  'factures', 'taches', 'notifications', 'prescriptions', 'administrations'
];

/// Ce que le moteur a écrit : fiches NOUVELLES (par collection) et champs MODIFIÉS — le même écart que le script de la maquette.
({Map<String, List<Map<String, Object?>>> inserts, Map<String, List<({Object? id, Map<String, Object?> patch})>> modifs})
    ecart(Map<String, List<Map<String, Object?>>> avant, Map<String, List<Map<String, Object?>>> apres) {
  final ins = <String, List<Map<String, Object?>>>{};
  final mod = <String, List<({Object? id, Map<String, Object?> patch})>>{};
  for (final n in _surveilles) {
    final a = {for (final f in avant[n] ?? []) f['id']: f};
    for (final f in apres[n] ?? <Map<String, Object?>>[]) {
      if (!a.containsKey(f['id'])) {
        ins.putIfAbsent(n, () => []).add(f);
        continue;
      }
      final b = a[f['id']]!;
      final patch = <String, Object?>{};
      for (final k in f.keys) {
        if (jsonEncode(f[k]) != jsonEncode(b[k])) patch[k] = f[k];
      }
      if (patch.isNotEmpty) mod.putIfAbsent(n, () => []).add((id: f['id'], patch: patch));
    }
  }
  return (inserts: ins, modifs: mod);
}

/// Les clés que la maquette tire du hasard, de l'horloge ou d'un compteur de page : identifiants, horodatages, références de série (écart E341).
const ignorer = {
  'id', 'factureId', 'ordonnanceId', 'demandeId', 'demandeImagerieId', 'derniereFicheId', 'fichesIds', 'ordonnanceIds', 'consultationId',
  'prescriptionId', 'releveId', 'creeLe', 'ouvertLe', 'dossierSaisiLe', 'cloturLe', 'reference', 'statutAvantArchivage', '_motifArchivage',
  'dateHeure', 'lue',
};

/// Les références de série de la maquette (`PRS-00004`) viennent d'un compteur de page (E341) : on compare leur FORME, pas leur rang.
Object? _neutre(Object? x) {
  if (x is String) return x.replaceAll(RegExp(r'(PRS|ADM|LAB|DOS|IME)-\d{5}'), r'$1-#');
  if (x is List) return [for (final e in x) _neutre(e)];
  if (x is Map) return {for (final e in x.entries) e.key: _neutre(e.value)};
  return x;
}

void main() {
  final v = lireVecteurs('consultation');
  final cat = (v['catalogues'] as Map).cast<String, Object?>();
  final jour = DateTime.parse('${v['jourCourant']}T12:00:00');

  Memoire memoire(Map<String, Object?> entree) {
    final m = Memoire({
      'patients': liste(cat['patients']),
      'constantes': liste(cat['releves']),
      'soignants': liste(cat['soignants']),
      'pathologies': liste(cat['pathologies']),
      'produits': liste(cat['produits']),
      'actes': liste(cat['actes']),
      'catalogueTarifs': liste(cat['catalogueTarifs']),
      'examensImagerie': [...liste(cat['examens']), (cat['examenSansTarif'] as Map).cast<String, Object?>()],
      'couverturesAssurance': [],
      'dossiersConsultation': liste(entree['dossiers']),
      'prescriptions': liste(entree['prescriptions']),
      'administrations': liste(entree['administrations']),
    }, jour);
    m.referentiels['analyses'] = liste(cat['analyses']);
    return m;
  }

  void compare(Memoire m, Map<String, Object?> avant, Map<String, Object?> sortie, {String? refus, String? code}) {
    final e = ecart((avant as Map<String, List<Map<String, Object?>>>), m.instantane());
    final attInserts = (sortie['inserts'] as Map).cast<String, Object?>();
    final attModifs = (sortie['modifs'] as Map).cast<String, Object?>();
    expect(e.inserts.keys.toSet(), attInserts.keys.toSet(), reason: 'collections écrites');
    for (final k in attInserts.keys) {
      memes(_neutre(e.inserts[k]), _neutre(attInserts[k]), k, ignorer: ignorer);
    }
    expect(e.modifs.keys.toSet(), attModifs.keys.toSet(), reason: 'collections modifiées');
    for (final k in attModifs.keys) {
      final att = liste(attModifs[k]);
      expect(e.modifs[k]!.length, att.length, reason: '$k : fiches modifiées');
      for (var i = 0; i < att.length; i++) {
        memes(e.modifs[k]![i].patch, att[i]['patch'], '$k.patch', ignorer: ignorer, sousEnsemble: true);
      }
    }
  }

  group('référentiels de la maquette', () {
    test('les quatre états du dossier, dans l’ordre, avec leurs suivants', () {
      final lus = liste((v['referentiels'] as Map)['etatsDossier']);
      expect([for (final e in csEtatsDossier) e['code']], [for (final e in lus) e['code']]);
      expect([for (final e in csEtatsDossier) e['label']],
          ['EN ATTENTE', 'EN CONSULTATION', 'EN ATTENTE LABO', 'CLÔTURÉ']);
    });
    test('toutes les transitions : les sauts sont refusés', () {
      for (final t in liste(v['transitions'])) {
        expect(csTransitionPermise(t['de'], t['vers']), t['permise'], reason: '${t['de']} → ${t['vers']}');
      }
    });
    test('neuf appareils IPPOA, le gynéco-obstétrical réservé aux femmes', () {
      expect(csAppareils.length, 9);
      expect(csAppareils.where((a) => csVrai(a['femme'])).map((a) => a['code']), ['gyneco_obstetrique']);
      expect(csTempsExamenDe(csAppareilExamen('genito_urinaire')).length, 5);
      expect(csTempsExamenDe(csAppareilExamen('orl')).length, 4);
    });
    test('la synthèse de l’examen : seuls les appareils examinés, « RAS » reconnu', () {
      for (final c in liste(v['syntheses'])) {
        final obtenu = csSyntheseExamen((c['examens'] as Map).cast<String, Object?>());
        final att = liste(c['attendu']);
        expect(obtenu.length, att.length);
        for (var i = 0; i < att.length; i++) {
          expect([obtenu[i].code, obtenu[i].label, obtenu[i].normal, obtenu[i].texte],
              [att[i]['code'], att[i]['label'], att[i]['normal'], att[i]['texte']]);
        }
      }
    });
    test('un dossier d’ancienne génération devient un appareil « global »', () {
      expect(csExamensPhysiquesDe({'exam_inspection': 'x', 'exam_palpation': 'y'}),
          (v['ancien'] as Map).cast<String, Object?>());
      expect(csExamensPhysiquesDe(null), isEmpty);
    });
    test('le relais d’administration : ambulatoire → salle de soins ; hospitalier → rang 1 salle de soins, suivants hospitalisation', () {
      expect(csSecteurAdministrateur('ambulatoire', 5).secteur, 'salle_soins');
      expect(csSecteurAdministrateur('hospitalisation', 1).secteur, 'salle_soins');
      expect(csSecteurAdministrateur('hospitalisation', 2).secteur, 'hospitalisation');
      expect(csSecteurAdministrateur('hospitalisation', 2).motif, 'Administration n° 2 : le relais est passé à l’hospitalisation.');
    });
    test('les rubriques chirurgicales ne s’écrivent que par le chirurgien', () {
      expect(csPeutEcrireRubrique('blocPrevu', 'chirurgien').ok, isTrue);
      expect(csPeutEcrireRubrique('blocPrevu', 'medecin').ok, isFalse);
      expect(csPeutEcrireRubrique('histoire', 'medecin').ok, isTrue);
    });
  });

  group('enregistrerDossier', () {
    for (final c in liste((v['cas'] as Map)['dossier'])) {
      test('${c['nom']}', () {
        final entree = (c['entree'] as Map).cast<String, Object?>();
        final m = memoire(entree);
        final avant = m.instantane();
        // Reconstitue l'appel : le script de la maquette enregistre les paramètres dans le nom du cas ; ici on rejoue les mêmes quatre formes.
        final p = _paramsDossier(c['nom'] as String, liste(entree['dossiers']));
        String? refus;
        try {
          csEnregistrerDossier(m, p.v, p.record, const SessionCs(role: 'admin', fonction: 'direction'));
        } on RefusCs catch (e) {
          refus = e.message;
        }
        final s = (c['sortie'] as Map).cast<String, Object?>();
        expect(refus, s['erreur']);
        compare(m, avant, s);
      });
    }
  });

  group('enregistrerFiche — la SEULE porte de prescription', () {
    for (final c in liste((v['cas'] as Map)['fiche'])) {
      test('${c['nom']}', () {
        final entree = (c['entree'] as Map).cast<String, Object?>();
        final m = memoire(entree);
        final avant = m.instantane();
        String? refus, code;
        try {
          csEnregistrerFiche(m, (c['params'] as Map).cast<String, Object?>(),
              const SessionCs(role: 'admin', fonction: 'direction', secteur: 'ADMINISTRATION'));
        } on RefusCs catch (e) {
          refus = e.message;
          code = e.code;
        }
        final s = (c['sortie'] as Map).cast<String, Object?>();
        expect(refus, s['erreur']);
        expect(code, s['code']);
        compare(m, avant, s);
      });
    }
  });

  group('prescrire — UNE facture globale, des tâches bloquées', () {
    for (final c in liste((v['cas'] as Map)['prescrire'])) {
      test('${c['nom']}', () {
        final entree = (c['entree'] as Map).cast<String, Object?>();
        final m = memoire(entree);
        if (entree['avant'] != null) {
          // « second appel » : l'état d'avant est posé tel que la maquette le tenait.
          final av = (entree['avant'] as Map).cast<String, Object?>();
          for (final n in _surveilles) {
            for (final f in liste(av[n]).reversed) {
              m.inserer(n, f);
            }
          }
        }
        final avant = m.instantane();
        String? refus;
        try {
          csPrescrire(m, (c['params'] as Map).cast<String, Object?>(), const SessionCs(role: 'admin', fonction: 'direction'));
        } on RefusCs catch (e) {
          refus = e.message;
        }
        final s = (c['sortie'] as Map).cast<String, Object?>();
        expect(refus, s['erreur']);
        compare(m, avant, s);
      });
    }

    test('RG-09 : carte expirée → aucune part assureur, imagerie et reste au tarif non assuré (E340)', () {
      final c = liste((v['cas'] as Map)['prescrire'])[2];
      final f = liste((c['sortie'] as Map)['inserts'] == null ? [] : ((c['sortie'] as Map)['inserts'] as Map)['factures']).first;
      expect(f['partAssurance'], 0);
      expect(f['tauxPriseEnCharge'], 0);
      expect(f['partPatient'], f['montantTTC']);
    });
    test('toutes les tâches d’aval naissent BLOQUÉES, seule l’encaissement attend le caissier', () {
      final f = liste((v['cas'] as Map)['prescrire'])[0];
      final t = liste(((f['sortie'] as Map)['inserts'] as Map)['taches']);
      expect({for (final x in t) x['type']: x['statut']},
          {'encaissement': 'en_attente', 'imagerie': 'bloque', 'dispensation': 'bloque', 'prelevement': 'bloque', 'acte': 'bloque'});
    });
  });

  group('prescription de soins', () {
    for (final c in liste((v['cas'] as Map)['soins'])) {
      test('${c['nom']}', () {
        final m = memoire((c['entree'] as Map).cast<String, Object?>());
        final avant = m.instantane();
        String? refus;
        try {
          csPrescrireSoins(m, (c['params'] as Map).cast<String, Object?>());
        } on RefusCs catch (e) {
          refus = e.message;
        }
        final s = (c['sortie'] as Map).cast<String, Object?>();
        expect(refus, s['erreur']);
        compare(m, avant, s);
      });
    }
  });

  group('administration et relais', () {
    for (final c in liste((v['cas'] as Map)['administrer'])) {
      test('${c['nom']}', () {
        final entree = (c['entree'] as Map).cast<String, Object?>();
        final m = memoire(entree);
        final p = (c['params'] as Map).cast<String, Object?>();
        final o = (p['opts'] as Map).cast<String, Object?>();
        final avant = m.instantane();
        String? refus;
        ResultatAdministration? r;
        try {
          r = csAdministrer(m, p['modalite'] == null ? 'INCONNUE' : 'PRSX1',
              ligneIndex: (o['ligneIndex'] as num).toInt(),
              secteur: o['secteur'] as String?,
              executantId: o['executantId'],
              observation: o['observation'] as String?,
              forcer: o['forcer'] == true);
        } on RefusCs catch (e) {
          refus = e.message;
        }
        final s = (c['sortie'] as Map).cast<String, Object?>();
        expect(refus, s['erreur']);
        if (r != null) {
          final att = (s['retour'] as Map).cast<String, Object?>();
          expect([r.ok, r.rang, r.secteur, r.secteurAttendu, r.motif],
              [att['ok'], att['rang'], att['secteur'], att['secteurAttendu'], att['motif']]);
        }
        compare(m, avant, s);
      });
    }

    test('soinsDuSecteur : le rang décide du secteur, le règlement de l’exécutabilité', () {
      final c = liste((v['cas'] as Map)['soinsDuSecteur']).first;
      final entree = (c['entree'] as Map).cast<String, Object?>();
      final m = memoire({'prescriptions': entree['prescriptions'], 'administrations': entree['administrations']});
      final att = (c['sortie'] as Map).cast<String, Object?>();
      for (final secteur in att.keys) {
        final lu = csSoinsDuSecteur(m, secteur);
        final a = liste(att[secteur]);
        expect(lu.length, a.length, reason: secteur);
        for (var i = 0; i < a.length; i++) {
          expect(lu[i].prescription['reference'], a[i]['prescription']);
          final al = liste(a[i]['lignes']);
          expect(lu[i].lignes.length, al.length);
          for (var j = 0; j < al.length; j++) {
            final l = lu[i].lignes[j];
            expect([l.index, l.rang, l.total, l.secteur, l.motif, l.du, l.bloque],
                [al[j]['index'], al[j]['rang'], al[j]['total'], al[j]['secteur'], al[j]['motif'], al[j]['du'], al[j]['bloque']]);
          }
        }
      }
    });
  });

  group('lectures des registres', () {
    test('le tableau de morbidité : cas décroissants, ordre du référentiel à égalité', () {
      final cas = csComptagePathologies([
        {'pathologies': ['A', 'B']},
        {'pathologies': ['B']},
        {'pathologies': ['C']},
        {'pathologies': []},
      ]);
      expect(cas, {'A': 1, 'B': 2, 'C': 1});
      final l = csMorbidite([
        {'code': 'A', 'chapitre': 'x'},
        {'code': 'B', 'chapitre': 'x'},
        {'code': 'C', 'chapitre': 'x'},
        {'code': 'D', 'chapitre': 'x'}
      ], cas);
      expect([for (final x in l) x['code']], ['B', 'A', 'C']);
    });
    test('la période du registre des dossiers', () {
      final auj = DateTime(2026, 10, 30);
      expect(csDansPeriode({'dateArrivee': '2026-10-30'}, 'jour', auj), isTrue);
      expect(csDansPeriode({'dateArrivee': '2026-10-29'}, 'jour', auj), isFalse);
      expect(csDansPeriode({'dateArrivee': '2026-10-23'}, 'semaine', auj), isTrue);
      expect(csDansPeriode({'dateArrivee': '2026-10-22'}, 'semaine', auj), isFalse);
    });
  });
}

/// Les paramètres des huit cas du dossier — ceux que le script de la maquette passe à `Z.enregistrerDossier`.
({Map<String, Object?> v, Map<String, Object?>? record}) _paramsDossier(
    String nom, List<Map<String, Object?>> dossiers) {
  Map<String, Object?> complet(String code, [Map<String, Object?> extra = const {}]) => {
        'patientCode': code,
        'soignant': 'BASSONGUI Chabi Séko',
        'typeVenue': 'premiere',
        'dateArrivee': '2026-08-15',
        'heureArrivee': '08h30',
        'motifVenue': 'Fièvre et céphalées',
        'histoire': 'Depuis trois jours',
        'traitementEnCours': '',
        'ant_medicaux': 'HTA',
        'ant_chirurgicaux': '',
        'ant_gyneco_obstetricaux': '',
        'allergies': '',
        'allergiesMedicamenteuses': 'Pénicilline',
        'etatGeneral': 'bon',
        'etatGeneralPrecision': '',
        'examensPhysiques': {
          'cardio_vasculaire': {'inspection': 'RAS', 'auscultation': 'RAS'},
          'orl': {'inspection': 'Angine'}
        },
        'antecedentsObstetricaux': null,
        'examenObstetrical': null,
        'actesChirurgicaux': 'Cure de hernie',
        'indicationOperatoire': '',
        'blocPrevu': '',
        'risqueOperatoire': '',
        ...extra,
      };
  if (nom.startsWith('création complète')) {
    return (
      v: complet('CNT/1001/26', {
        'antecedentsObstetricaux': {'gestite': 2, 'parite': 1, 'pathologies': ['Œuf clair']},
        'examenObstetrical': {'terme': '30 SA'}
      }),
      record: null
    );
  }
  if (nom.startsWith('patient sans relevé')) return (v: complet('CNT/1002/26'), record: null);
  if (nom.startsWith('patient inconnu')) return (v: complet('CNT/9999/26'), record: null);
  if (nom.startsWith('second dossier') || nom.startsWith('un dossier EN ATTENTE')) {
    return (v: complet('CNT/1001/26'), record: null);
  }
  if (nom.startsWith('édition d’un dossier EN ATTENTE')) {
    return (v: complet('CNT/1001/26', {'motifVenue': 'Corrigé'}), record: dossiers.first);
  }
  if (nom.startsWith('édition d’un dossier CLÔTURÉ')) {
    return (v: complet('CNT/1001/26'), record: dossiers.first);
  }
  return (v: complet('CNT/1001/26', {'actesChirurgicaux': 'Nouvel acte'}), record: dossiers.first);
}
