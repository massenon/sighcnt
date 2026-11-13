// Rejoue les vecteurs des FICHIERS NUMÉRISÉS (prototype_html/build/vecteurs-fichiers.js) : la maquette réelle pilotée dans Chrome et son serveur PHP (lot D5). Ici, les RÈGLES :
// empreinte SHA-256, format lu sur les octets, contrôle d'un fichier déclaré, taille maximale réglée en base, zones et droit de lire un type, noms normalisés, doublons,
// rattachement et retrait (RG-14), registre par empreinte, réponses du serveur à chaque profil, extracteur de texte PDF.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

typedef M = Map<String, Object?>;
M obj(Object? o) => (o as Map).cast<String, Object?>();
List<M> liste(Object? o) => [for (final x in (o as List)) obj(x)];
final v = obj(jsonDecode(File('test/vecteurs/fichiers.json').readAsStringSync()));
final dossierFixtures = '../../apps/poste/test/fixtures/fichiers';

/// Les octets d'un fichier du vecteur : versionné (fixtures) ou DÉRIVÉ (refabriqué ici).
Uint8List octetsDe(String nom) {
  final dv = obj(v['derives']);
  if (dv.containsKey(nom)) {
    final d = obj(dv[nom]);
    if (d['source'] == null) return Uint8List.fromList(List.filled(d['octets'] as int, (d['octet'] as int?) ?? 0));
    final src = File('$dossierFixtures/${d['source']}').readAsBytesSync();
    return Uint8List.fromList([...src, ...List.filled(d['remplissage'] as int, 32)]);
  }
  return File('$dossierFixtures/$nom').readAsBytesSync();
}

List<int>? inflaterIo(List<int> flux) {
  try {
    return ZLibCodec().decode(flux);
  } catch (_) {}
  try {
    return ZLibCodec(raw: true).decode(flux.sublist(2));
  } catch (_) {}
  try {
    return ZLibCodec(raw: true).decode(flux);
  } catch (_) {}
  return null;
}

String ns(Object? s) => '$s';

void main() {
  group('SHA-256', () {
    test('les entrées synthétiques (frontières de bloc) donnent l’empreinte de Node', () {
      for (final c in liste(v['sha256'])) {
        final List<int> b = c['texte'] != null
            ? utf8.encode('${c['texte']}')
            : [for (var i = 0; i < (c['taille'] as int); i++) (i * 31 + 7) & 255];
        expect(sha256Octets(b), c['sha256'], reason: '${c['texte'] ?? c['taille']}');
      }
    });
    test('le flux découpé en morceaux irréguliers donne la même empreinte', () {
      final b = Uint8List.fromList([for (var i = 0; i < 100000; i++) (i * 13 + 5) & 255]);
      final f = Sha256Flux();
      var i = 0;
      var pas = 1;
      while (i < b.length) {
        final fin = (i + pas > b.length) ? b.length : i + pas;
        f.ajouter(Uint8List.sublistView(b, i, fin));
        i = fin;
        pas = pas * 3 + 1;
        if (pas > 9000) pas = 7;
      }
      expect(f.hex(), sha256Octets(b));
    });
    test('une liste non typée (List<int>) donne la même empreinte qu’un Uint8List', () {
      final l = <int>[for (var i = 0; i < 300; i++) i & 255];
      expect(sha256Octets(l), sha256Octets(Uint8List.fromList(l)));
    });
    test('empreinteValide : 64 hexadécimaux minuscules, rien d’autre', () {
      expect(empreinteValide('a' * 64), isTrue);
      expect(empreinteValide('A' * 64), isFalse);
      expect(empreinteValide('a' * 63), isFalse);
      expect(empreinteValide('../${'a' * 61}'), isFalse);
    });
  });

  group('données de la maquette (D.DOCUMENTS)', () {
    test('formats, tailles, types et zones = ceux de la maquette', () {
      final d = obj(v['donnees']);
      final f = liste(d['FORMATS']);
      expect(fichierFormats.length, f.length);
      for (var i = 0; i < f.length; i++) {
        expect(fichierFormats[i].id, f[i]['id']);
        expect(fichierFormats[i].mime, f[i]['mime']);
        expect(fichierFormats[i].ext, f[i]['ext']);
        expect(fichierFormats[i].familles, f[i]['familles']);
      }
      expect(fichierTailleDefaut, d['TAILLE_DEFAUT']);
      expect(fichierTaillePlancher, d['TAILLE_PLANCHER']);
      expect(fichierTaillePlafond, d['TAILLE_PLAFOND']);
      final t = liste(d['TYPES_PATIENT']);
      expect([for (final x in docTypesPatient) '${x.libelle}|${x.zone}'], [for (final x in t) '${x['libelle']}|${x['zone']}']);
      expect(docRolesZone2, d['ROLES_ZONE_2']);
    });
  });

  group('format lu sur les octets, empreinte', () {
    test('chaque fichier : format lu des premiers octets et SHA-256 = ceux de la maquette', () {
      for (final c in liste(v['octets'])) {
        final b = octetsDe('${c['fichier']}');
        expect(b.length, c['taille'], reason: '${c['fichier']}');
        expect(fichierFormatDesOctets(b), c['format'], reason: '${c['fichier']}');
        expect(sha256Octets(b), c['sha256'], reason: '${c['fichier']}');
      }
    });
    test('une extension mensongère ne change pas le format lu', () {
      expect(fichierFormatDesOctets(octetsDe('png-nomme-pdf.pdf')), 'png');
      expect(fichierFormatDesOctets(octetsDe('pdf-nomme-jpg.jpg')), 'pdf');
      expect(fichierFormatDesOctets(octetsDe('faux-camoufle.pdf')), isNull);
      expect(fichierFormatDesOctets(Uint8List(0)), isNull);
      expect(fichierFormatDesOctets([0x25, 0x50, 0x44]), isNull, reason: '« %PD » seul n’est pas un PDF');
    });
  });

  group('contrôle d’un fichier déclaré', () {
    test('format par le nom ou le type, vide, taille : mêmes verdicts, mêmes refus nommés', () {
      final cs = liste(v['controles']);
      expect(cs.length, greaterThan(50));
      for (final c in cs) {
        final tm = c['tailleMax'] == null ? fichierTailleDefaut : (c['tailleMax'] as int);
        final r = fichierControler(nom: '${c['nom']}', mime: '${c['mime']}', taille: c['taille'] as int, famille: '${c['famille']}', tailleMax: fichierTailleMax(c['reglage'] == null ? null : obj(c['reglage'])));
        final ctx = '${c['nom']} ${c['famille']} ${c['taille']} max=$tm';
        expect(r.refus == null, c['ok'], reason: ctx);
        expect(r.format?.id, c['format'], reason: ctx);
        if (!(c['ok'] as bool)) {
          expect(r.refus!.code, c['code'], reason: ctx);
          expect(r.refus!.motif, c['motif'], reason: ctx);
          expect(r.refus!.geste, c['geste'], reason: ctx);
        }
      }
    });
    test('un WEBP est refusé au courrier et admis au dossier patient', () {
      expect(fichierControler(nom: 'a.webp', mime: '', taille: 10, famille: 'courrier', tailleMax: 1000).refus!.code, 'FORMAT_REFUSE');
      expect(fichierControler(nom: 'a.webp', mime: '', taille: 10, famille: 'patient', tailleMax: 1000).refus, isNull);
    });
  });

  group('taille maximale réglée en base', () {
    test('lecture : réglage valide, absent, négatif, texte, plafonné', () {
      for (final c in liste(v['tailleMax'])) {
        final rg = c['reglage'] == null ? null : obj(c['reglage']);
        expect(fichierTailleMax(rg), c['tailleMax'], reason: jsonEncode(rg));
        expect(fichierTailleMaxReglee(rg), c['reglee'], reason: jsonEncode(rg));
      }
    });
    test('réglage : réservé à l’administrateur et à la DAF, borné, motivé ; mêmes refus nommés', () {
      for (final c in liste(v['reglage'])) {
        final r = fichierDefinirTailleMax(role: '${c['role']}', octets: c['octets'], motif: c['motifSaisi'] as String?, reglage: {'tailleMax': 7 * 1024 * 1024});
        final ctx = '${c['role']} ${c['octets']} ${c['motifSaisi']}';
        expect(r.ok, c['ok'], reason: ctx);
        if (r.ok) {
          expect(r.tailleMax, c['tailleMax'], reason: ctx);
          expect(r.avant, c['avant'], reason: ctx);
        } else {
          expect(r.refus!.code, c['code'], reason: ctx);
          expect(r.refus!.motif, c['motif'], reason: ctx);
          expect(r.refus!.geste, c['geste'], reason: ctx);
        }
      }
    });
  });

  group('zones et droit de lire un type de document', () {
    test('chaque type × chaque rôle : même décision, même zone, même motif que PR.peutVoirDocument', () {
      for (final z in liste(v['zones'])) {
        final type = z['type'] as String?;
        expect(docZoneDe(type), z['zone'], reason: '$type');
        final roles = obj(z['roles']);
        for (final e in roles.entries) {
          final r = docPeutVoir(type, e.key);
          final a = obj(e.value);
          expect(r.autorise, a['autorise'], reason: '$type ${e.key}');
          expect(r.zone, a['zone']);
          expect(r.motif, a['motif']);
        }
      }
    });
    test('un type inconnu se range à la zone la plus stricte', () {
      expect(docZoneDe('Type inconnu'), 2);
      expect(docPeutVoir('Type inconnu', 'reception').autorise, isFalse);
      expect(docPeutVoir('Pièce d’identité', 'reception').autorise, isTrue);
    });
  });

  group('noms normalisés', () {
    test('courrier AAAA-MM-JJ_ARR_NNNN.ext et patient AAAA-MM-JJ_CODE_type_NNN.ext', () {
      for (final c in liste(v['noms'])) {
        final f = c['fiche'] == null ? null : obj(c['fiche']);
        expect(docNomNormalise('${c['famille']}', f, '${c['ext']}'), c['nom'], reason: jsonEncode(c));
      }
    });
    test('sans diacritiques : NFD de la maquette (œ, æ, ß, ø, ł restent tels quels)', () {
      for (final c in liste(v['diacritiques'])) {
        expect(sansDiacritiques('${c['texte']}').toLowerCase(), c['sans'], reason: '${c['texte']}');
      }
    });
    test('slug et empreinte abrégée', () {
      for (final c in liste(v['slugs'])) {
        expect(docSlug(c['texte']), c['slug'], reason: '${c['texte']}');
      }
      for (final c in liste(v['abrege'])) {
        expect(docAbrege(c['sha']), c['abrege']);
      }
    });
    test('le nom suit la fiche quand sa date change, la référence jamais', () {
      final f = {'date': '2026-08-20', 'reference': 'ARR-2026-0042', 'sens': 'arrivee'};
      final fichier = {'nomNormalise': docNomNormalise('courrier', f, 'pdf'), 'nom': 'x.pdf'};
      final r = fichierRecalculerNom('courrier', {...f, 'date': '2026-09-02'}, fichier);
      expect(r['nomNormalise'], '2026-09-02_ARR_0042.pdf');
      expect(r['nom'], 'x.pdf');
    });
  });

  group('dépôt : le geste contre le serveur réel', () {
    final fiches = <M>[];
    for (final c in liste(v['depots'])) {
      test('${c['cas']}${c['note'] != null ? ' (${c['note']})' : ''}', () {
        final famille = '${c['famille']}';
        final b = octetsDe('${c['fichier']}');
        final cas = '${c['cas']}';
        // Les fiches du cas : la fiche courante porte déjà le fichier dans les cas de doublon.
        final existantes = <M>[];
        FicheDoc? courante;
        bool Function(FicheDoc)? portee;
        if (cas == 'doublon-meme-fiche') {
          courante = {'id': 'C1', 'reference': 'ARR-2026-0900', 'statut': 'actif', 'fichier': {'sha256': sha256Octets(octetsDe('scan.png')), 'nom': 'deja.pdf', 'nomNormalise': '2026-08-20_ARR_0900.pdf'}};
          existantes.add(courante);
        } else if (cas == 'doublon-meme-dossier') {
          existantes.add({'id': 'D2', 'reference': 'GED-90002', 'patientId': 'P1', 'statut': 'actif', 'fichier': {'sha256': sha256Octets(octetsDe('scan.jpg')), 'nom': 'facture.png', 'nomNormalise': '2026-08-13_CNT-9-26_facture_002.png'}});
          portee = (f) => f['patientId'] == 'P1';
        }
        fiches.addAll(existantes);
        final tm = cas == 'taille-reglee' ? 100 * 1024 : fichierTailleDefaut;
        final r = fichierPreparerDepot(
            nom: '${c['nom']}', mime: '${c['mime']}', octets: b, famille: famille, tailleMax: tm, fiches: existantes, ficheCourante: courante, portee: portee);
        if (c['ok'] == true) {
          expect(r.refus, isNull, reason: '${r.refus}');
          final dep = obj(c['depot']);
          expect(r.sha256, dep['sha256']);
          expect(r.format!.id, dep['format']);
          expect(b.length, dep['taille']);
          expect(r.format!.mime, dep['mime']);
          expect(fichierExtDeMime(r.format!.mime), dep['ext'] == 'jpg' ? 'jpg' : dep['ext']);
        } else {
          expect(r.refus, isNotNull);
          expect(r.refus!.code, c['code']);
          expect(r.refus!.motif, c['motif']);
          expect(r.refus!.geste, c['geste']);
        }
      });
    }
  });

  group('doublon (fonction seule)', () {
    test('mêmes fiches, mêmes empreintes, mêmes verdicts', () {
      final d = obj(v['doublons']);
      final lues = {
        for (final f in liste(d['fiches'])) '${f['reference']}': {'id': f['id'], 'reference': f['reference'], 'statut': f['statut'], 'fichier': f['fichier']}
      };
      // Dans l'ORDRE de la collection de la maquette : quand plusieurs fiches portent la même empreinte, la première nommée est celle de l'avertissement.
      final fiches = [for (final r in (d['ordre'] as List)) if (lues.containsKey(r)) lues['$r']!];
      FicheDoc? parRef(String? r) => r == null ? null : fiches.firstWhere((f) => f['reference'] == r);
      for (final c in liste(d['cas'])) {
        final sha = '${c['sha']}' * 32;
        final courante = parRef(c['courante'] as String?);
        final r = fichierDoublon(fiches, sha, ficheCourante: courante, portee: c['portee'] == true ? (f) => f['reference'] == 'ARR-2026-0953' : null);
        expect(r == null, c['aucun'], reason: jsonEncode(c));
        expect(r?.memeFiche?['reference'], c['memeFiche'], reason: jsonEncode(c));
        expect(r?.autre?['reference'], c['autre'], reason: jsonEncode(c));
      }
    });
  });

  group('rattachement, retrait (RG-14), annulation, registre par empreinte', () {
    final r = obj(v['rattachement']);
    final depot = obj(r['depot']);
    test('l’objet fichier de la fiche = celui du rattachement de la maquette', () {
      final fiche = {'reference': 'ARR-2026-0960', 'sens': 'arrivee', 'date': '2026-08-20'};
      final f = fichierConstruire(famille: 'courrier', fiche: fiche, depot: depot, nomOrigine: 'Courrier.pdf', deposePar: 'AGENT VECTEUR', deposeLe: obj(r['rattache'])['fichier'] is Map ? '${obj(obj(r['rattache'])['fichier'])['deposeLe']}' : '');
      expect(f, obj(obj(r['rattache'])['fichier']));
      expect(f, obj(r['nomConstruit']));
      expect(courrierNumerise({'fichier': f}), isTrue);
    });
    test('le registre par empreinte : mêmes champs, texte normalisé, sans compteur synchronisé', () {
      final reg = obj(r['registre']);
      final e = fichierEntreeRegistre(depot: depot, premiereDate: '${reg['premiereDate']}');
      final attendu = {...reg}..removeWhere((k, _) => const ['nbReferences', 'statut', '_creePar', '_creeLe'].contains(k));
      expect(e, attendu);
      expect(reg['nbReferences'], 1);
      expect(fichierNbReferences([{'statut': 'actif', 'fichier': obj(obj(r['rattache'])['fichier'])}], '${depot['sha256']}'), 1);
      expect(fichierNbReferences([{'statut': 'archive', 'fichier': obj(obj(r['rattache'])['fichier'])}], '${depot['sha256']}'), 0);
    });
    test('le retrait n’efface rien : fichier à vide, historique allongé, annulation qui remet les deux', () {
      final avant = obj(r['rattache']);
      final audit = obj(r['auditRetrait']);
      final retire = obj(r['retire']);
      final x = fichierRetirer(fiche: avant, motif: 'Mauvais scan, à refaire', retirePar: 'AGENT VECTEUR', retireLe: '${obj(liste(retire['fichiersRetires']).first)['retireLe']}')!;
      expect(x.patch['fichier'], isNull);
      expect(x.patch['fichiersRetires'], retire['fichiersRetires']);
      expect(audit['action'], 'Pièce numérisée retirée de la fiche');
      final apresAnnulation = obj(r['apresAnnulationRetrait']);
      expect(x.annulation['fichier'], apresAnnulation['fichier']);
      expect(x.annulation['fichiersRetires'], apresAnnulation['fichiersRetires'] ?? []);
      expect(fichierRetirer(fiche: {'reference': 'X'}, motif: 'x', retirePar: 'a', retireLe: 'b'), isNull, reason: 'une fiche sans fichier ne se retire pas');
      expect(r['retraitSansFichier'], isTrue);
    });
    test('retraits successifs : l’historique s’allonge, le motif est borné à 200 caractères', () {
      final deux = obj(r['apresDeuxRetraits']);
      final hist = liste(deux['fichiersRetires']);
      expect(hist.length, 2);
      expect('${hist.last['motif']}'.length, 200);
      final x = fichierRetirer(fiche: {'fichier': {'sha256': 'e' * 64}, 'fichiersRetires': [hist.first]}, motif: 'M' * 300, retirePar: 'a', retireLe: 'b')!;
      expect((x.patch['fichiersRetires'] as List).length, 2);
      expect('${((x.patch['fichiersRetires'] as List).last as Map)['motif']}'.length, 200);
    });
    test('numerise est DÉRIVÉ du fichier : jamais un champ saisi', () {
      for (final c in liste(v['numerise'])) {
        expect(courrierNumerise(c['fiche'] == null ? null : obj(c['fiche'])), c['numerise'], reason: jsonEncode(c['fiche']));
      }
    });
    test('registre : texte normalisé, ajout seul par empreinte', () {
      final es = liste(obj(v['textes'])['entrees']);
      final a = es[0];
      expect(a['texteIndexe'], isTrue);
      expect('${a['texte']}', fichierNormaliserMots(['Hyperglycémie', 'AMOXICILLINE', 'é', 'Éther', 'ok', 'ok']));
      expect(es[1]['texte'], '');
      expect(fichierIdRegistre('f1' * 32), a['id']);
    });
  });

  group('recherche dans le texte indexé', () {
    test('sans accent ni casse, texte de la pièce compris ; l’indice dit ce que la recherche ne lit pas', () {
      final fiche = {'fichier': {'sha256': 'aa' * 32, 'nom': 'Convocation.pdf', 'nomNormalise': '2026-08-20_ARR_0042.pdf'}};
      final t = fichierTexteRecherche(fiche, dateFr: '20/08/2026', texteIndexe: fichierNormaliserMots(['Hyperglycémie', 'Amoxicilline']), observations: 'Réunion');
      expect(fichierCorrespond(t, 'HYPERGLYCEMIE'), isTrue);
      expect(fichierCorrespond(t, 'amoxicilline'), isTrue);
      expect(fichierCorrespond(t, 'reunion'), isTrue);
      expect(fichierCorrespond(t, '20/08/2026'), isTrue);
      expect(fichierCorrespond(t, 'convocation'), isTrue);
      expect(fichierCorrespond(t, 'inexistant'), isFalse);
      expect(fichierIndiceNonIndexe(0), isNull);
      expect(fichierIndiceNonIndexe(1), '1 pièce numérisée n’a pas de texte indexé (image sans couche texte) : la recherche par le contenu ne la lit pas, seules ses données de fiche sont cherchées.'.replaceAll('ne la lit pas, seules ses', 'ne les lit pas, seules leurs'));
      expect(fichierIndiceNonIndexe(3), startsWith('3 pièces numérisées n’ont pas de texte indexé'));
    });
  });

  group('le serveur : ce qu’il répond à chaque profil', () {
    final rbac = MatriceDroits.depuisJson(obj(jsonDecode(File('../rbac/data/rbac.json').readAsStringSync())));
    test('la règle par famille du serveur = la matrice rbac.json (écrans m13-courriers et m1-documents) pour chaque rôle', () {
      final regles = obj(v['regles']);
      final roles = obj(regles['roles']);
      expect(v['regles'], v['reglesGenerees'], reason: 'api/regles-fichiers.json est engendré de rbac.json');
      for (final role in (v['roles'] as List).cast<String>()) {
        final r = roles[role] == null ? {'courrier': [0, 0, 0], 'patient': [0, 0, 0]} : obj(roles[role]);
        for (final famille in fichierFamilles) {
          final d = rbac.droit(role, fichierEcranDeFamille(famille));
          expect([d.voir ? 1 : 0, d.editer ? 1 : 0, d.annuler ? 1 : 0], r[famille], reason: '$role $famille');
        }
      }
    });
    test('dépôt par rôle, famille et type : même refus (code, motif, geste) ou même autorisation que le serveur', () {
      final depots = liste(obj(v['serveur'])['depots']);
      expect(depots.length, greaterThan(100));
      for (final c in depots) {
        final role = '${c['role']}';
        final famille = '${c['famille']}';
        final r = fichierRefusDroit(role: role, famille: famille, geste: 'editer', type: c['type'] as String?, droitEcran: rbac.droit(role, fichierEcranDeFamille(famille)));
        final ctx = '$role $famille ${c['type']}';
        expect(r == null, c['ok'], reason: ctx);
        if (r != null) {
          expect(r.code, c['code'], reason: ctx);
          expect(r.motif, c['motif'], reason: ctx);
          expect(r.geste, c['geste'], reason: ctx);
        }
      }
    });
    test('lecture par rôle : zone 2 refusée aux profils non cliniques, courrier selon le droit de l’écran', () {
      final lectures = liste(obj(v['serveur'])['lectures']);
      for (final c in lectures) {
        if (c['type'] == 'nonrattachee') continue;
        final role = '${c['role']}';
        final famille = '${c['famille']}';
        final type = c['type'] == 'zone2' ? '__zone2__' : (c['type'] == 'zone1' ? 'Pièce d’identité' : null);
        final r = fichierRefusDroit(role: role, famille: famille, geste: 'voir', type: type, droitEcran: rbac.droit(role, fichierEcranDeFamille(famille)));
        final ctx = '$role $famille ${c['type']}';
        expect(r == null, c['ok'], reason: ctx);
        if (r != null) {
          expect(r.code, c['code'], reason: ctx);
          expect(r.motif, c['motif'], reason: ctx);
        }
      }
    });
    test('contrôle du contenu et refus du serveur : mêmes codes et textes', () {
      for (final c in liste(obj(v['serveur'])['refus'])) {
        final cas = '${c['cas']}';
        if (cas == 'exe') {
          final r = fichierControlerContenu(octetsDe('faux.exe'), 'courrier').refus!;
          expect([r.code, r.motif, r.geste], [c['code'], c['motif'], c['geste']]);
        } else if (cas == 'webp-courrier') {
          final r = fichierControlerContenu(octetsDe('scan.webp'), 'courrier').refus!;
          expect([r.code, r.motif, r.geste], [c['code'], c['motif'], c['geste']]);
        } else if (cas == 'webp-patient-ok') {
          expect(fichierControlerContenu(octetsDe('scan.webp'), 'patient').refus, isNull);
          expect(c['statut'], 200);
        }
      }
    });
  });

  group('extracteur de texte PDF local (le même que celui du serveur)', () {
    for (final c in liste(v['extracteur'])) {
      test('${c['fichier']}', () {
        final b = octetsDe('${c['fichier']}');
        final fmt = fichierFormatDesOctets(b)!;
        final r = indexerFichier(b, fmt, inflaterIo);
        expect(r.pages, c['pages']);
        expect(r.texteIndexe, c['texteIndexe']);
        expect([...r.mots]..sort(), (c['mots'] as List).cast<String>(), reason: '${c['fichier']}');
        expect(r.motsTronques, c['motsTronques']);
        expect(r.raison, c['raison']);
      });
    }
    test('jamais une liste vide présentée comme un contenu vide : un scan image dit sa raison', () {
      final r = indexerFichier(octetsDe('scan-image.pdf'), 'pdf', inflaterIo);
      expect(r.texteIndexe, isFalse);
      expect(r.raison, isNotNull);
      expect(r.mots, isEmpty);
    });
    test('un fichier qui n’est pas un PDF ne plante jamais l’extracteur', () {
      expect(pdfExtraireTexte(octetsDe('faux.exe'), inflaterIo).raison, 'pas un PDF');
      expect(pdfExtraireTexte(Uint8List(0), inflaterIo).raison, 'pas un PDF');
      expect(pdfExtraireTexte(utf8.encode('%PDF-1.4 \u0000\u0000 << << [ ( <'), inflaterIo).indexe, isFalse);
    });
  });
}
