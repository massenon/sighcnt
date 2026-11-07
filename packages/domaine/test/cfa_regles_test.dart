// Rejoue les vecteurs de CFG (prototype_html/build/vecteurs-cfg.js) : les dix écrans de configuration RÉELS pilotés dans Chrome. Ici, les RÈGLES :
// indicateurs, fiches nées des saisies (codes, rangs, RG-02, NON COUVERT), notes, trames de certificat, aperçus de message, anniversaires.
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

typedef M = Map<String, Object?>;
M obj(Object? o) => (o as Map).cast<String, Object?>();
List<M> liste(Object? o) => [for (final x in (o as List)) obj(x)];
M lire(String nom) => obj(jsonDecode(File('test/vecteurs/$nom.json').readAsStringSync()));
List<M> jeu(String nom) => liste(jsonDecode(File('../../apps/poste/assets/donnees/jeu/$nom.json').readAsStringSync()));
List<M> actives(String nom) => [for (final f in jeu(nom)) if (f['statut'] != 'archive') f];

/// Les espaces (ordinaires, fines, insécables) ne comptent pas dans une comparaison de libellés.
String s(Object? v) => '$v'.replaceAll(RegExp(r'[\s  ]'), '');

void kpis(List<CfaKpi> obtenus, Object? attendus) {
  final a = (attendus as List).cast<List>();
  expect(obtenus.length, a.length);
  for (var i = 0; i < a.length; i++) {
    expect(obtenus[i].libelle, a[i][0]);
    expect(s(obtenus[i].valeur), s(a[i][1]), reason: '${a[i][0]}');
    expect(obtenus[i].indice, a[i][2], reason: 'indice ${a[i][0]}');
  }
}

/// Une fiche née d'une saisie : on compare ce que l'écran a ÉCRIT (champs `id`/`statut`… déjà retirés du vecteur).
void fiche(M obtenue, M attendue, [String ctx = '']) {
  expect(obtenue.keys.toSet(), attendue.keys.toSet(), reason: '$ctx clés');
  for (final k in attendue.keys) {
    final e = attendue[k], o = obtenue[k];
    if (e is List) {
      expect(o, e, reason: '$ctx $k');
    } else if (e is num) {
      expect(o is num ? o.toDouble() : num.tryParse('$o')?.toDouble(), e.toDouble(), reason: '$ctx $k');
    } else {
      expect(o, e, reason: '$ctx $k');
    }
  }
}

CfaFiche sansStatut(CfaFiche f) => {...f}..remove('statut');

void main() {
  final v = lire('cfg');
  final constantes = obj(v['constantes']);
  final jour = '${constantes['jour']}';

  group('référentiels statiques (D.NS145, D.FAMILLES_TARIF, D.IMAGERIE.TYPES)', () {
    test('NS 145', () {
      final n = obj(constantes['ns145']);
      expect(CfaNs145.reference, n['reference']);
      expect(CfaNs145.objet, n['objet']);
      expect(CfaNs145.dateSignature, n['dateSignature']);
      expect(CfaNs145.dateEffet, n['dateEffet']);
      expect(CfaNs145.signataire, n['signataire']);
      expect(CfaNs145.source, n['source']);
    });
    test('familles tarifaires et types de variable', () {
      final f = liste(constantes['famillesTarif']);
      expect(cfaFamillesTarif.map((x) => (x.$1, x.$2, x.$3)).toList(), [for (final x in f) ('${x['code']}', '${x['label']}', '${x['icone']}')]);
      final t = liste(constantes['imagerieTypes']);
      expect(cfaTypesVariableImagerie.map((x) => (x.$1, x.$2)).toList(), [for (final x in t) ('${x['code']}', '${x['label']}')]);
    });
    test('identité : une seule, celle de la maquette', () {
      final b = obj(constantes['brand']);
      expect(CfaIdentite.forme, b['forme']);
      expect(CfaIdentite.adresse, b['adresse']);
      expect(CfaIdentite.telephoneRdv, b['telephoneRdv']);
      expect(CfaIdentite.autorisationExerciceMotif, b['autorisationExerciceMotif']);
      expect(CfaIdentite.logo, b['logo']);
    });
  });

  group('cfg-organisation', () {
    final o = obj(v['organisation']);
    final postes = actives('postes');
    final arbre = cfaArbre(postes);
    test('indicateurs : secteurs, postes, effectif porté (somme de l’arbre), rôles', () {
      kpis(cfaKpisOrganisation(secteurs: actives('secteurs').length, postes: postes.length, effectif: cfaEffectifTotal(arbre), roles: (constantes['roles'] as List).length), o['kpis']);
    });
    test('l’arbre parcourt les postes dans l’ordre du document', () {
      final lus = <String>[];
      void parcourir(CfaNoeud n) {
        lus.add('${n.poste}(${n.effectif.toString().padLeft(2, '0')})');
        n.enfants.forEach(parcourir);
      }
      arbre.forEach(parcourir);
      final attendus = [for (final t in (o['arbre'] as List)) RegExp(r'^(.*?\(\d\d\))').firstMatch('$t')!.group(1)!];
      expect(lus, attendus);
    });
    test('création d’un secteur : code = trois lettres du libellé, rang = nombre de fiches + 1', () {
      final c = obj(v['organisationCreations']);
      for (final cas in ['secteurSansCode', 'secteurAvecCode']) {
        final e = obj(liste(obj(c[cas])['creees']).single);
        final saisie = {...e}..remove('ordre');
        if (obj(obj(c[cas])['saisie'])['code'] == null) saisie.remove('code');
        fiche(cfaFicheSecteur(saisie, obj(c[cas])['nbAvant'] as int), e, cas);
      }
    });
    test('création d’un poste : sans rattachement, un sommet', () {
      final c = obj(obj(v['organisationCreations'])['posteSommet']);
      final e = obj(liste(c['creees']).single);
      final saisie = {...e, 'parentId': ''};
      fiche(cfaFichePoste(saisie), e);
    });
    test('modules d’un rôle : un code par rangée dont un écran est visible', () {
      final rangees = [('M1', ['a', 'b'], false), ('M2', ['c'], true), ('M1', ['d'], false)];
      expect(cfaModulesRole(rangees, (c, e, a) => e == 'b' || e == 'd'), ['M1', 'M1']);
      expect(cfaModulesRole(rangees, (c, e, a) => false), isEmpty);
    });
  });

  group('cfg-tarifs', () {
    final t = obj(v['tarifs']);
    final actes = actives('actes');
    final analyses = actives('analyses');
    test('indicateurs : « à confirmer » = analyses provisoires + actes sans prix', () {
      kpis(
          cfaKpisTarifs(
              produits: actives('produits').length,
              analyses: analyses.length,
              actes: actes.length,
              secteurs: 8,
              aConfirmer: cfaTarifsAConfirmer(analyses, actes)),
          t['kpis']);
    });
    test('notes de l’onglet des actes : trois populations, une population vide n’a pas de note', () {
      final n = cfaNotesActes(actes);
      expect(n.map((x) => s(x.texte)).toList(), [for (final x in (t['notesActes'] as List)) s(x)]);
    });
    test('filtre « Tarif » : cinq lectures, comptes mesurés sur l’écran', () {
      final compte = {for (final o in cfaFiltresTarifActe) o.$1: actes.where((a) => cfaCorrespondTarifActe(a, o.$1)).length};
      final attendu = <String, int>{};
      for (final f in liste(t['filtres'])) {
        final c = (f['compteur'] as List).map((x) => RegExp(r'sur (\d+)').firstMatch('$x')?.group(1)).whereType<String>().toList();
        attendu['${f['valeur']}'] = c.isEmpty ? 0 : int.parse(c.first);
      }
      expect(compte, attendu);
      expect(cfaFiltresTarifActe.map((o) => o.$2).toList(), [for (final f in liste(t['filtres'])) f['libelle']]);
    });
    test('onglet des certificats : les pièces sans tarif sont nommées', () {
      final n = cfaNoteSansTarif(actives('typesPiece'));
      expect(s(n), s((t['notesCertificats'] as List)[1]));
      expect(cfaNoteSansTarif([]), isNull);
    });
    test('créations : RG-02 sur le médicament, code PRD, analyse toujours provisoire, acte sans prix = absent', () {
      final c = obj(v['tarifsCreations']);
      M seule(String k) => obj(liste(obj(c[k])['creees']).single);
      final med = seule('medicament');
      fiche(cfaFicheProduit({'designation': 'Médicament Test A', 'categorie': 'medicament', 'prixAchat': '700', 'prixVente': '900', 'unite': '', 'seuilAlerte': ''}, 184), med, 'médicament');
      expect(med['prixVente'], med['prixAchat']);
      final conso = seule('consommable');
      fiche(cfaFicheProduit({'designation': 'Consommable Test B', 'categorie': 'conso_medical', 'prixAchat': '300', 'prixVente': '450', 'code': 'CTB-1', 'unite': '', 'seuilAlerte': ''}, 184), conso, 'consommable');
      fiche(cfaFicheAnalyse({'designation': 'Analyse Test', 'categorie': 'Hématologie', 'code': '', 'prix': '2500', 'echantillon': '', 'delai': ''}, 48), seule('analyse'), 'analyse');
      fiche(cfaFicheActe({'libelle': 'Acte Test Sans Prix', 'secteur': 'Médecine générale', 'code': '', 'prix': '', 'source': ''}, 73), seule('acteSansPrix'), 'acte sans prix');
      fiche(cfaFicheActe({'libelle': 'Acte Test Prix', 'secteur': 'Médecine générale', 'code': 'TST-9', 'prix': '4000', 'source': ''}, 73), seule('acteAvecPrix'), 'acte avec prix');
    });
  });

  group('cfg-catalogue', () {
    final cat = obj(v['catalogue']);
    final rows = actives('catalogueTarifs');
    test('indicateurs et notes de tête', () {
      kpis(cfaKpisCatalogue(rows), cat['kpis']);
      expect(cfaNotesCatalogue(rows).map((x) => s(x.texte)).toList(), [for (final x in (cat['notes'] as List)) s(x)]);
    });
    test('l’écart est « — » si un prix manque ou si l’acte n’est pas couvert, « + » seulement quand l’assuré paie plus', () {
      var vus = 0;
      for (final f in liste(cat['familles'])) {
        for (final l in (obj(f['tableau'])['lignes'] as List).cast<List>()) {
          final r = rows.firstWhere((x) => x['code'] == l[0]);
          expect(s(cfaEcartTarif(r)), s(l[4]), reason: '${l[0]}');
          vus++;
        }
      }
      expect(vus, greaterThan(40));
      expect(cfaEcartTarif({'prixNonAssure': 1000, 'prixAssure': 1500}), '+${money(500)}');
      expect(cfaEcartTarif({'prixNonAssure': 1000, 'prixAssure': null}), '—');
    });
    test('couverture de la fiche détaillée', () {
      for (final d in liste(v['catalogueDetails'])) {
        final r = rows.firstWhere((x) => x['code'] == d['code']);
        expect(s(obj(d)['tiroir']).contains(s('Couverture${cfaCouverture(r)}')), isTrue, reason: '${d['code']}');
      }
    });
    test('créations : NON COUVERT = non assurable ; prix absent = à valider, jamais zéro', () {
      final c = obj(v['catalogueCreations']);
      M seule(String k) => obj(liste(obj(c[k])['creees']).single);
      fiche(sansStatut(cfaFicheTarif({'code': 'TST-C1', 'libelle': 'Acte Test Complet', 'famille': 'CONSULTATION', 'prixNonAssure': '5000', 'prixAssure': '4000', 'nonCouvert': false, 'source': ''})), seule('complet'), 'complet');
      fiche(sansStatut(cfaFicheTarif({'code': 'TST-C2', 'libelle': 'Acte Test Sans Assuré', 'famille': 'CONSULTATION', 'prixNonAssure': '5000', 'prixAssure': '', 'nonCouvert': false, 'source': ''})), seule('sansPrixAssure'), 'sans assuré');
      fiche(sansStatut(cfaFicheTarif({'code': 'TST-C3', 'libelle': 'Acte Test Non Couvert', 'famille': 'CONSULTATION', 'prixNonAssure': '5000', 'prixAssure': '', 'nonCouvert': true, 'source': 'Document test'})), seule('nonCouvert'), 'non couvert');
      fiche(sansStatut(cfaFicheTarif({'code': 'TST-C4', 'libelle': 'Acte Test Sans Prix', 'famille': 'CONSULTATION', 'prixNonAssure': '', 'prixAssure': '', 'nonCouvert': false, 'source': ''})), seule('sansPrix'), 'sans prix');
    });
  });

  group('cfg-types-piece', () {
    final tp = obj(v['typesPiece']);
    final types = actives('typesPiece');
    test('indicateurs : tarifés, collisions de sigles CONSERVÉES', () {
      kpis(
          cfaKpisTypesPiece(
              types: types.length,
              tarifes: types.where((t) => cfaVrai(t['tarifCode'])).length,
              collisions: types.where((t) => cfaVrai(t['collision'])).length,
              delivrees: 0 /* la base du pilote n'a pas été peuplée de pièces délivrées : le jeu du poste en porte 90 */),
          tp['kpis']);
    });
    test('numérotation : <SIGLE> n°/n°/CNT/<direction>/<année>', () {
      final an = int.parse(jour.substring(0, 4));
      for (final d in liste(tp['details'])) {
        final t = types.firstWhere((x) => '${x['libelle']}' == '${(d['ligne'] as List)[1]}');
        expect(s(d['tiroir']).contains(s('Numérotation${cfaNumerotationPiece(t, an)}')), isTrue, reason: '${t['sigle']}');
      }
    });
    test('création sans tarif', () {
      final e = obj(liste(obj(obj(v['typesPieceCreations'])['sansTarif'])['creees']).single);
      expect(e['sigle'], 'TST');
      expect(e['tarifCode'], '');
    });
  });

  group('cfg-rappels', () {
    final r = obj(v['rappels']);
    test('aperçu : les variables sont remplacées, un jeton inconnu reste tel quel', () {
      for (final a in liste(r['apercus'])) {
        final ligne = (a['ligne'] as List).cast<String>();
        final modele = jeu('modelesMessage').firstWhere((m) => m['libelle'] == ligne[0]);
        final ap = cfaApercuMessage('${modele['texte']}', clinique: IdentiteClinique.nom, telephone: CfaIdentite.telephoneRdv, jour: jour);
        expect(s(a['tiroir']).endsWith(s('Aperçu, variables remplacées$ap')), isTrue, reason: ligne[0]);
        expect(s(cfaCoupeTexte('${modele['texte']}')), s(ligne[2]));
        expect(cfaLibelleOccasion(modele['occasion']), ligne[1]);
      }
      expect(cfaApercuMessage('{{nom}} {{inconnu}}', clinique: 'C', telephone: 'T', jour: jour), '$cfaNomExemple {{inconnu}}');
    });
    test('modèles proposés = ceux que la maquette amorce', () {
      final m = jeu('modelesMessage');
      expect(m.length, cfaModelesProposes.length);
      for (final p in cfaModelesProposes) {
        final x = m.firstWhere((f) => f['occasion'] == p.$1);
        expect(x['libelle'], p.$2);
        expect(x['texte'], p.$3);
      }
    });
    test('variables et occasions', () {
      final lignes = (obj(liste(r['variables']).first)['lignes'] as List).cast<List>();
      expect([for (final x in cfaVariablesMessage) [x.$1, x.$2]], lignes);
      expect(cfaOccasions.length, 6);
    });
    test('anniversaires du jour : un rappel par patient, jamais deux fois le même, refus nommé sans modèle actif', () {
      final a = obj(v['rappelsAnniversaires']);
      final pj = jeu('patients');
      final ids = ['PAT0001', 'PAT0002'];
      final patients = [
        for (var i = 0; i < 2; i++) {...pj.firstWhere((p) => p['id'] == ids[i]), 'dateNaissance': obj(liste(a['patients'])[i])['dateNaissance']}
      ];
      final modeles = jeu('modelesMessage');
      var n = 0;
      final p1 = cfaPreparerAnniversaires(modeles: modeles, patients: patients, rappelsExistants: [], jour: '${a['jour']}', clinique: IdentiteClinique.nom, telephone: CfaIdentite.telephoneRdv, prochaineRef: () => 'RPL-${(++n).toString().padLeft(5, '0')}');
      final attendus = {for (final x in liste(obj(a['premier'])['rappels'])) '${x['reference']}': x};
      expect(p1.rappels.length, attendus.length);
      for (final f in p1.rappels) {
        final e = attendus['${f['reference']}']!;
        for (final k in e.keys) {
          expect(f[k], e[k], reason: '${f['reference']} $k');
        }
      }
      expect(p1.message, obj(liste(obj(a['premier'])['toasts']).first)['message']);
      final p2 = cfaPreparerAnniversaires(modeles: modeles, patients: patients, rappelsExistants: p1.rappels, jour: '${a['jour']}', clinique: IdentiteClinique.nom, telephone: CfaIdentite.telephoneRdv, prochaineRef: () => 'X');
      expect(p2.faits, 0);
      expect(p2.message, obj(liste(obj(a['second'])['toasts']).first)['message']);
      final sans = cfaPreparerAnniversaires(modeles: [for (final m in modeles) {...m, 'actif': false}], patients: patients, rappelsExistants: [], jour: '${a['jour']}', clinique: 'C', telephone: 'T', prochaineRef: () => 'X');
      expect(sans.erreur, obj(liste(a['sansModele']).first)['message']);
      final aucun = cfaPreparerAnniversaires(modeles: modeles, patients: [], rappelsExistants: [], jour: '${a['jour']}', clinique: 'C', telephone: 'T', prochaineRef: () => 'X');
      expect(aucun.message, 'Aucun patient ne fête son anniversaire aujourd’hui.');
    });
  });

  group('cfg-certificats', () {
    final c = obj(v['certificats']);
    final valeurs = obj(c['valeurs']);
    final patient = obj(c['patient']);
    test('la trame de chaque type se compose comme à l’écran, vide (…………… ) puis remplie', () {
      final composes = liste(c['composes']);
      expect(composes.length, cfaTypesCertificat.length);
      for (var i = 0; i < composes.length; i++) {
        final t = cfaTypesCertificat[i];
        expect(composes[i]['carte'], startsWith(t.libelle));
        final base = {'praticien': c['praticien'], 'patient': patient['nom']};
        // Le sexe de l'enfant se présélectionne (« masculin ») : le champ n'est jamais vide.
        final vide = {...base, if (t.id == 'accouchement') 'sexeEnfant': 'masculin'};
        expect(cfaComposerCertificat(t.trame, vide), composes[i]['apercuVide'], reason: '${t.id} vide');
        expect(cfaComposerCertificat(t.trame, {...base, for (final k in t.champs) k: valeurs[k]}), composes[i]['apercuRempli'], reason: '${t.id} rempli');
        // Les champs saisis, dans l'ordre : patient, praticien, date, puis ceux du type.
        expect((composes[i]['champs'] as List).skip(3).toList(), t.champs);
        expect((composes[i]['libelles'] as List).skip(3).toList(), [for (final k in t.champs) '${cfaChampsCertificat[k]!.libelle} *']);
      }
    });
    test('une date ISO s’écrit JJ/MM/AAAA, un nombre sans décimale, une valeur vide devient des points', () {
      expect(cfaComposerCertificat('{a} {b} {c} {d}', {'a': '2026-08-17', 'b': 3.0, 'c': '', 'd': null}), '17/08/2026 3 …………… ……………');
      expect(cfaComposerCertificat('{inconnu}', {}), '……………');
    });
    test('numérotation, indicateurs, ce mois (le numéro du mois seulement)', () {
      expect(cfaNumeroCertificat(0), obj(liste(obj(c['delivrance'])['fiche']).single)['numero']);
      kpis(cfaKpisCertificats(delivres: 1, types: cfaTypesCertificat.length, ceMois: 0, praticiens: 1), c['kpisApres']);
      expect(cfaDelivresCeMois([{'date': '2025-10-01'}, {'date': '2026-10-31'}, {'date': '2026-08-16'}], DateTime(2026, 10, 30)), 2);
    });
  });

  group('cfg-entetes et cfg-branding : UNE identité légale', () {
    final e = obj(v['entetes']);
    final b = obj(v['branding']);
    test('indicateurs : un IFU, un RCCM, une autorisation, tous les états', () {
      kpis(cfaKpisEntetes(), e['kpis']);
    });
    test('la grille de l’identité est celle que l’écran affiche, ligne à ligne', () {
      final texte = s(e['texte']);
      var pos = 0;
      for (final p in cfaGrilleIdentite()) {
        final i = texte.indexOf(s('${p.$1}${p.$2}'), pos);
        expect(i, greaterThanOrEqualTo(0), reason: '${p.$1} : ${p.$2}');
        pos = i;
      }
      expect(s(e['texte']).contains(s(cfaNoteAnciennesPieces)), isTrue);
    });
    test('les valeurs du formulaire d’identité sont celles de C.BRAND de la maquette', () {
      final champs = obj(b['champs']);
      final v0 = cfaValeursIdentite();
      expect(v0.keys.toSet(), champs.keys.toSet());
      for (final k in champs.keys) {
        expect(v0[k], champs[k], reason: k);
      }
    });
    test('le pied du papier à en-tête', () {
      final ap = '${b['apercu']}';
      // L'heure est celle du tirage du vecteur (l'horloge de la page) : on la relit sur l'aperçu.
      final h = RegExp(r'le (\d\d)/(\d\d)/(\d{4}) à (\d\d)h(\d\d)').firstMatch(ap)!;
      final quand = DateTime(int.parse(h.group(3)!), int.parse(h.group(2)!), int.parse(h.group(1)!), int.parse(h.group(4)!), int.parse(h.group(5)!));
      final pied = cfaPiedApercu('BASSONGUI Chabi Séko', quand);
      expect(s(ap).contains(s(pied)), isTrue, reason: pied);
    });
    test('ressources attendues = celles de l’écran', () {
      final lus = (b['ressources'] as List).map(s).toList();
      expect([for (final r in cfaRessourcesAttendues) s('${r.$2}${r.$3}À fournir')], lus);
      expect(cfaPoids(2048), '2 ko');
      expect(cfaPoids(3 * 1024 * 1024), '3.0 Mo');
      expect(cfaFichierTropLourd(1024 * 1024 + 1), isTrue);
    });
  });

  group('cfg-natures-facture', () {
    final n = obj(v['natures']);
    test('indicateurs', () {
      final rows = actives('naturesFacture');
      final secteurs = {for (final r in rows) '${r['secteur']}'};
      kpis(cfaKpisNatures(natures: rows.length, secteurs: secteurs.length, archivees: jeu('naturesFacture').length - rows.length), n['kpis']);
    });
    test('création : code = quatre lettres du libellé en majuscules, rang = fiches + 1', () {
      final c = obj(v['naturesCreations']);
      for (final cas in ['sansCode', 'avecCode']) {
        final e = obj(liste(obj(c[cas])['creees']).single);
        final saisie = {...e}..remove('ordre');
        if (obj(obj(c[cas])['saisie'])['code'] == null) saisie.remove('code');
        fiche(cfaFicheNature(saisie, obj(c[cas])['nbAvant'] as int), e, cas);
      }
    });
  });

  group('cfg-imagerie-catalogue', () {
    final im = obj(v['imagerie']);
    test('indicateurs : examens, variables, fermées, listes de choix (liste ou binaire)', () {
      final vars = actives('variablesImagerie');
      kpis(
          cfaKpisImagerie(
              examens: actives('examensImagerie').length,
              variables: vars.length,
              fermees: vars.where((x) => x['actif'] == false).length,
              listes: vars.where((x) => x['type'] == 'liste' || x['type'] == 'binaire').length),
          im['kpis']);
    });
    test('les choix saisis « a | b || » deviennent une liste sans vides ; sans choix, aucune liste', () {
      final c = obj(v['imagerieCreations']);
      final e = obj(liste(obj(c['variable'])['creees']).single);
      fiche(cfaTransformVariableImagerie({...e}..remove('options')..['optionsTexte'] = ' homogène | hétérogène ||  ' ..['ordre'] = '7'), e, 'variable');
      final e2 = obj(liste(obj(c['sans'])['creees']).single);
      fiche(cfaTransformVariableImagerie({...e2}..remove('options')..['optionsTexte'] = '' ..['ordre'] = '8'), {...e2, 'options': null}, 'sans');
      expect(cfaOptionsTexte(e), 'homogène|hétérogène');
    });
    test('fermer une variable le dit — le message se décide AVANT l’écriture (E845)', () {
      final b = obj(obj(v['imagerieCreations'])['apresFermeture']);
      final m = cfaMessageBascule(etaitFermee: false);
      expect(m.message, obj(liste(b['toasts']).single)['message']);
      expect(m.detail, obj(liste(b['toasts']).single)['detail']);
      expect(cfaMessageBascule(etaitFermee: true).message, 'Variable rouverte.');
    });
  });
}
