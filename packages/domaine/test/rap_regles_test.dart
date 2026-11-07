// Rejoue les vecteurs de RAP (prototype_html/build/vecteurs-rapports.js) : les QUATRE écrans réels de `rapports.js` pilotés dans Chrome à l'horloge du
// 30/10/2026 10 h, sur le jeu du poste. Ici, les RÈGLES : catalogue et écrans producteurs, point de la Direction (période × axe × cumul détaillé × date
// d'arrêt, 288 + 62 réglages), indicateurs du générateur, éditions (graine 3221) et leurs indicateurs.
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

typedef M = Map<String, Object?>;
M obj(Object? o) => (o as Map).cast<String, Object?>();
List<M> liste(Object? o) => [for (final x in (o as List)) obj(x)];
M lire(String nom) => obj(jsonDecode(File('test/vecteurs/$nom.json').readAsStringSync()));
List<M> jeuDossier(String nom) => liste(jsonDecode(File('../../apps/poste/assets/donnees/jeu/$nom.json').readAsStringSync()));

/// Les espaces (ordinaires, insécables, fines) ne comptent pas dans les comparaisons de libellés.
String s(Object? v) => '$v'.replaceAll(RegExp(r'[\s  ]'), '');

List<M> actives(Iterable<M> l) => [for (final f in l) if (f['statut'] != 'archive') f];

final maintenant = DateTime(2026, 10, 30, 10);

void main() {
  final v = lire('rap');
  final factures = actives(jeuDossier('factures'));
  final produits = actives(jeuDossier('produits'));

  group('constantes extraites de la maquette', () {
    test('catalogue : treize domaines, 76 états, tous rattachés à un écran', () {
      final c = obj(v['constantes']);
      expect(rapCatalogueEtats.length, (c['catalogue'] as List).length);
      for (final (i, d) in liste(c['catalogue']).indexed) {
        expect(rapCatalogueEtats[i].$1, d['domaine']);
        expect(rapCatalogueEtats[i].$2, d['etats']);
      }
      expect([for (final (k, e) in rapEcransProducteurs) [k, e]], c['ecrans']);
      final st = rapStatsBibliotheque();
      expect((st.etats, st.domaines, st.editables), (76, 13, 76));
    });
  });

  group('rapports-bibliotheque', () {
    test('chaque carte de domaine : états, action « Éditer » et écran cible comme la maquette', () {
      final b = obj(v['bibliotheque']);
      final cartes = liste(b['cartes']).where((c) => '${c['titre']}'.contains(' — ') && '${c['titre']}'.endsWith('état(s)')).toList();
      expect(cartes.length, 13);
      final cat = rapCatalogue();
      var i = 0;
      for (final c in cartes) {
        final lignes = liste(c['lignes']);
        for (final l in lignes) {
          final e = cat[i++];
          expect(l['etat'], e.etat);
          expect(l['action'], e.disponible ? 'Éditer' : 'À venir');
          expect(l['href'], e.disponible ? 'pages/${e.ecran}.php' : null, reason: e.etat);
        }
        final dom = cat[i - 1].domaine;
        expect(c['titre'], '$dom — ${lignes.length} état(s)');
      }
      expect(i, cat.length);
    });

    test('indicateurs', () {
      final b = obj(v['bibliotheque']);
      final k = liste(b['kpis']);
      final st = rapStatsBibliotheque();
      expect([k[0]['valeur'], k[1]['valeur'], k[2]['valeur']], ['${st.etats}', '${st.domaines}', '${st.editables}']);
    });

    test('un état sans écran producteur est « À venir » (aucun lien)', () {
      expect(rapCatalogue().every((e) => e.disponible), isTrue, reason: 'le catalogue de la maquette est entièrement rattaché');
      const e = RapEtat('X', 'Y', null);
      expect(e.disponible, isFalse);
    });
  });

  group('rapports-direction', () {
    void rejouer(String cle, List<M> facts) {
      final blocs = obj(v[cle]);
      for (final r in liste(blocs['sorties'])) {
        final reg = obj(r['reglage']);
        final nom = '$cle ${reg['periode']}/${reg['axe']}/${reg['fin']}/${reg['detaille']}';
        final b = rapBornes('${reg['periode']}', reg['fin']);
        final fac = rapFacturesPeriode(facts, b);
        final axe = rapAxe('${reg['axe']}');
        final rows = rapAgreger(fac, produits, axe.id);
        final cum = rapCumul(rows);
        final k = liste(r['kpis']);
        expect(k[0]['libelle'], 'Point ${b.libelle.toLowerCase()}', reason: nom);
        expect(s(k[0]['valeur']), s(money(fac.fold<double>(0, (t, f) => t + nombreOuZero(f['montantTTC'])))), reason: nom);
        expect(k[0]['indice'], '${b.debutFR} → ${b.finFR}', reason: nom);
        expect(s(k[1]['valeur']), s(money(fac.fold<double>(0, (t, f) => t + nombreOuZero(f['montantPaye'])))), reason: nom);
        expect(k[2]['valeur'], nombre(fac.length), reason: nom);
        expect(k[3]['libelle'], axe.libellePostes, reason: nom);
        expect(k[3]['valeur'], nombre(rows.length), reason: nom);
        expect(k[3]['indice'], axe.detail, reason: nom);
        // le tableau de l'écran : lignes dans l'ordre, colonnes, valeurs
        final att = liste(r['lignes']);
        expect(rows.length, att.length, reason: nom);
        for (var i = 0; i < att.length; i++) {
          expect(rows[i].libelle, att[i]['libelle'], reason: '$nom #$i');
          expect(rows[i].pieces, att[i]['pieces'], reason: '$nom #$i');
          expect(rows[i].quantite, (att[i]['quantite'] as num).toDouble(), reason: '$nom #$i');
          expect(rows[i].montant, (att[i]['montant'] as num).toDouble(), reason: '$nom #$i');
          expect(rows[i].assureur, (att[i]['assureur'] as num).toDouble(), reason: '$nom #$i');
          expect(rows[i].patient, (att[i]['patient'] as num).toDouble(), reason: '$nom #$i');
        }
        expect(r['titreTableau'], 'Point ${b.libelle.toLowerCase()} — ${axe.libelle.toLowerCase()}', reason: nom);
        final cols = ['${axe.colonne}', 'Pièces', 'Quantité vendue', 'Montant', if (reg['detaille'] == true && axe.niveauPiece) ...['Part assureur', 'Part patient']];
        expect(r['colonnes'], cols, reason: nom);
        // le cumul global
        final note = (r['notes'] as List).last;
        expect(s(note), s('Cumul global : ${money(cum.montant)} sur ${nombre(cum.quantite)} unité(s) vendue(s), ${nombre(cum.postes)} poste(s) d’analyse.'), reason: nom);
        expect((r['notes'] as List).length, axe.id == 'groupe' ? 2 : 1, reason: '$nom : la note de proposition n’accompagne que l’axe « groupe »');
        // la pièce imprimée : cartouche, tableau, pied
        final et = obj((r['etat'] as List).single);
        expect(et['titre'], 'Point ${b.libelle.toLowerCase()} — ${axe.libelle.toLowerCase()}', reason: nom);
        expect(et['sousTitre'], '${b.debutFR} au ${b.finFR}', reason: nom);
        final cart = rapCartoucheDirection(b, axe, pieces: fac.length, cumul: cum.montant);
        expect((et['cartouche'] as List).map((c) => [(c as List)[0], s(c[1])]).toList(), [for (final (a, z) in cart) [a, s(z)]], reason: nom);
        final t = rapTableauDirection(rows, axe);
        final tab = obj((et['tableaux'] as List).single);
        expect(tab['entetes'], [for (final c in t.colonnes) c.libelle], reason: nom);
        final att2 = tab['lignes'] as List;
        expect(t.cellules.length, att2.length, reason: nom);
        for (var i = 0; i < att2.length; i++) {
          expect([for (final c in t.cellules[i]) s(c)], [for (final c in att2[i] as List) s(c)], reason: '$nom impression #$i');
        }
        expect([for (final c in t.pied!) s(c)], [for (final c in (tab['pied'] as List).single as List) s(c)], reason: '$nom pied');
        final sig = liste(et['signatures']);
        expect([sig[0]['role'], sig[1]['role']], ['La Directrice Administrative', 'Le Comptable']);
      }
    }

    test('288 réglages (6 périodes × 6 axes × cumul détaillé × 4 dates d’arrêt) rejoués sur le jeu', () => rejouer('direction', factures));

    test('cas limites : avoir exclu, lignes sans montant ni nom, produit inconnu, client absent (62 réglages)', () {
      final lim = obj(v['directionLimites']);
      final ajout = liste(obj(lim['injection'])['factures']);
      rejouer('directionLimites', [...factures, ...ajout]);
    });

    test('réglage initial : mensuel, par client, arrêté au jour ; six périodes et six axes dans l’ordre', () {
      final p = obj(obj(v['direction'])['premier']);
      final i = obj(p['reglageInitial']);
      expect([i['periode'], i['axe'], i['fin']], ['mois', 'client', '2026-10-30']);
      expect(i['periodes'], [for (final p in rapPeriodesDirection) [p.id, p.libelle]]);
      expect(i['axes'], [for (final a in rapAxesDirection) [a.id, a.libelle]]);
    });

    test('une date d’arrêt invalide ne retient aucune pièce (jamais de repli silencieux sur « tout »)', () {
      final b = rapBornes('mois', '');
      expect(rapFacturesPeriode(factures, b), isEmpty);
      expect(b.debutFR, '—');
    });

    test('les bornes sont inclusives et la fenêtre remonte de jours − 1', () {
      final b = rapBornes('semaine', '2026-08-16');
      expect((b.debutFR, b.finFR), ('10/08/2026', '16/08/2026'));
      final f = [
        {'date': '2026-08-09', 'montantTTC': 1}, // veille de la fenêtre
        {'date': '2026-08-10', 'montantTTC': 2},
        {'date': '2026-08-16', 'montantTTC': 4},
        {'date': '2026-08-17', 'montantTTC': 8}, // lendemain
        {'date': '2026-08-12', 'montantTTC': -5}, // avoir : écarté
      ];
      expect(rapFacturesPeriode(f, b).map((x) => x['montantTTC']), [2, 4]);
    });
  });

  group('rapports-generateur', () {
    final personnel = actives(jeuDossier('personnel'));
    RapSources sources({List<M> ecritures = const []}) => RapSources(
          patients: actives(jeuDossier('patients')),
          consultations: actives(jeuDossier('consultations')),
          admissions: actives(jeuDossier('admissions')),
          factures: factures,
          produits: produits,
          lots: actives(jeuDossier('lots')),
          personnel: personnel,
          ecritures: [...actives(jeuDossier('ecritures')), ...ecritures],
          demandesAnalyses: actives(jeuDossier('demandesAnalyses')),
          nbAnalyses: obj(v['constantes'])['nbAnalyses'] as int,
          nbAssureurs: obj(v['constantes'])['nbAssureurs'] as int,
        );

    void comparer(RapRapport r, M att, String nom) {
      final e = obj((att['etat'] as List).single);
      expect(r.titre, e['titre'], reason: nom);
      expect(r.sousTitre, e['sousTitre'], reason: nom);
      expect(r.filigrane, e['filigrane'], reason: nom);
      expect([for (final (a, z) in r.cartouche) [a, z]], e['cartouche'], reason: nom);
      final tabs = liste(e['tableaux']);
      expect(r.sections.length, tabs.length, reason: nom);
      for (final (i, (_, lignes)) in r.sections.indexed) {
        expect([for (final (a, z) in lignes) [a, s(z)]], [for (final l in tabs[i]['lignes'] as List) [(l as List)[0], s(l[1])]], reason: '$nom section $i');
      }
    }

    test('rapport par défaut : activité + financier', () {
      final g = obj(v['generateur']);
      final r = rapComposerRapport(
          titre: 'Rapport d’activité',
          sousTitre: 'Période : ${moisAnnee(maintenant)}',
          periode: 'Mensuelle',
          dateDebut: '2026-08-01',
          dateFin: '2026-10-30',
          sectionsCochees: ['activite', 'financier'],
          utilisateur: '${obj(v['constantes'])['utilisateur']}',
          sources: sources());
      comparer(r, obj(g['defaut']), 'défaut');
    });

    test('les quatre modèles enregistrés chargent titre, destinataire et sections, puis génèrent', () {
      final g = obj(g0(v));
      for (final m in rapModeles) {
        final att = obj(obj(g['modeles'])[m.nom]);
        expect([for (final c in att['cases'] as List) if ((c as List)[1] == true) c[0]], [for (final x in rapSections) if (m.sections.contains(x.id)) x.libelle], reason: m.nom);
        expect(obj(obj(att['champs'])['f_destinataire'])['valeur'], rapChargerModele(m).destinataire, reason: m.nom);
        expect(att['toasts'], [['Modèle « ${m.nom} » chargé.']], reason: m.nom);
        final r = rapComposerRapport(
            titre: m.nom,
            sousTitre: 'Période : ${moisAnnee(maintenant)}',
            destinataire: rapChargerModele(m).destinataire,
            periode: 'Mensuelle',
            dateDebut: '2026-08-01',
            dateFin: '2026-10-30',
            sectionsCochees: m.sections,
            utilisateur: '${obj(v['constantes'])['utilisateur']}',
            sources: sources());
        comparer(r, obj(att['gen']), m.nom);
      }
    });

    test('toutes les sections, période annuelle, filigrane, sans sous-titre', () {
      final g = obj(g0(v));
      final r = rapComposerRapport(
          titre: 'Rapport complet',
          sousTitre: '',
          destinataire: 'Partenaire technique',
          periode: 'Annuelle',
          dateDebut: '2026-01-01',
          dateFin: '2026-06-30',
          filigrane: 'Confidentiel',
          sectionsCochees: [for (final x in rapSections) x.id],
          utilisateur: '${obj(v['constantes'])['utilisateur']}',
          sources: sources());
      comparer(r, obj(g['toutes']), 'toutes');
      expect(r.sections.length, 7);
    });

    test('une écriture déséquilibrée fait nommer l’écart', () {
      final inj = obj(obj(v['generateurEcart'])['injection']);
      final r = rapComposerRapport(
          titre: 'Rapport d’activité',
          sousTitre: 'Période : ${moisAnnee(maintenant)}',
          periode: 'Mensuelle',
          dateDebut: '2026-08-01',
          dateFin: '2026-10-30',
          sectionsCochees: ['comptable'],
          utilisateur: '${obj(v['constantes'])['utilisateur']}',
          sources: sources(ecritures: [inj]));
      comparer(r, obj(v['generateurEcart']), 'écart');
      expect(r.sections.single.$2.last.$2, startsWith('Écart de '));
    });

    test('refus nommés : aucune section ; titre vide', () {
      final g = obj(g0(v));
      expect(rapRefusGeneration(titre: 'X', sectionsCochees: []), 'Sélectionner au moins une section.');
      expect(obj(g['refusSections'])['toasts'], [['Sélectionner au moins une section.']]);
      expect(rapRefusGeneration(titre: '', sectionsCochees: ['rh']), 'Le formulaire comporte des erreurs.');
      expect(obj(g['refusTitre'])['toasts'], [['Le formulaire comporte des erreurs.']]);
      expect(rapRefusGeneration(titre: 'X', sectionsCochees: ['rh']), isNull);
    });

    test('sections rangées dans l’ordre de la maquette, pas dans l’ordre des clics ; date absente = tiret, jamais « NaN »', () {
      final r = rapComposerRapport(
          titre: 'T',
          periode: 'Mensuelle',
          sectionsCochees: ['assurances', 'activite'],
          utilisateur: 'U',
          sources: sources());
      expect(r.sections.map((x) => x.$1), ['Activité', 'Assurances']);
      expect(r.cartouche[1], ('Du', '—'));
      expect(r.cartouche[3], ('Destinataire', 'Usage interne'));
    });
  });

  group('rapports-historique', () {
    final noms = [for (final p in actives(jeuDossier('personnel'))) '${p['nomComplet']}'];

    void comparer(List<M> rows, M att, String nom) {
      final l = liste(att['lignes']);
      expect(rows.length, l.length, reason: nom);
      for (var i = 0; i < l.length; i++) {
        for (final k in ['id', 'reference', 'dateHeure', 'utilisateur', 'etat', 'module', 'format', 'poste']) {
          expect(rows[i][k], l[i][k], reason: '$nom #$i $k');
        }
      }
      final st = rapStatsHistorique(rows, maintenant);
      final k = liste(att['kpis']);
      expect([k[0]['valeur'], k[1]['valeur'], k[2]['valeur'], k[3]['valeur']],
          ['${st.editions}', '${st.ceMois}', '${st.pdf}', '${st.utilisateurs}'], reason: nom);
      final g = rapGrouper(rows, 'module');
      final barres = liste(att['barres']).single;
      expect(barres['etiquettes'], g.keys.toList(), reason: nom);
      expect(((barres['series'] as List).single as Map)['data'], [for (final x in g.values) x.length], reason: nom);
      final rk = (att['rankings'] as List).single as List;
      expect([for (final (a, z) in rapEtatsLesPlusEdites(rows)) {'label': a, 'value': z}], rk, reason: nom);
      final modules = {for (final r in rows) '${r['module']}'}.toList()..sort();
      expect([for (final f in att['filtres'] as List) f], [
        ['format', 'Format', rapFormats],
        ['module', 'Module', modules]
      ], reason: nom);
    }

    test('le jeu n’ayant aucune édition archivée : soixante éditions de démonstration (graine 3221)', () {
      final rows = rapEditions(actives(jeuDossier('audit')), noms, maintenant);
      expect(rows.length, 60);
      comparer(rows, obj(v['historiqueJeu']), 'jeu');
    });

    test('les éditions archivées passent d’abord, la référence manquante est numérotée par rang, le reste est complété', () {
      final inj = liste(obj(v['historiqueEditions'])['injection']);
      final rows = rapEditions([...inj, ...actives(jeuDossier('audit'))], noms, maintenant);
      comparer(rows, obj(v['historiqueEditions']), 'éditions');
      expect(rows.where((r) => r['reference'] == 'CNT-00001'), hasLength(1));
      expect(rows.where((r) => r['module'] == 'RAP' && r['poste'] == 'POSTE-LOCAL'), hasLength(3));
    });

    test('seules les entrées « Impression » du journal sont retenues', () {
      final rows = rapEditions([
        {'action': 'Création', 'module': 'M1', 'id': 'X', 'dateHeure': '2026-10-30T09:00:00.000Z', 'utilisateur': 'U', 'poste': 'P'}
      ], noms, maintenant);
      expect(rows.where((r) => r['id'] == 'X'), isEmpty);
      expect(rows.length, 60);
    });
  });
}

Object? g0(M v) => v['generateur'];
