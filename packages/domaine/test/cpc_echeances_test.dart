// Rejoue les vecteurs des échéances fiscales et de la baseline 2025 de M12, tirés des écrans réels de la maquette
// (prototype_html/build/vecteurs-m12-echeances.js). Le jeu est celui du poste, l'horloge celle du 30/10/2026 10 h.
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_domaine/src/comptabilite/cpc_donnees.dart' show cpcExercice2025Json;
import 'package:test/test.dart';

typedef F = Map<String, Object?>;

List<F> liste(Object? v) => ((v ?? const []) as List).map((x) => (x as Map).cast<String, Object?>()).toList();
F carte(Object? v) => (v as Map).cast<String, Object?>();
String nt(Object? s) => '$s'.replaceAll(RegExp(r'[\s  ]+'), ' ').trim();
List<F> jeu(String nom) => liste(jsonDecode(File('../../apps/poste/assets/donnees/jeu/$nom.json').readAsStringSync()));
List<String> cellules(Object? l) => [for (final c in (l as List)) nt(c)];

void main() {
  final f = File('test/vecteurs/echeances.json');
  if (!f.existsSync()) fail('vecteurs absents : lancer `node prototype_html/build/vecteurs-m12-echeances.js`');
  final v = carte(jsonDecode(f.readAsStringSync()));
  final e = carte(v['echeances']);
  final b = carte(v['baseline']);
  final auj = DateTime(2026, 10, 30, 10);
  final brut = jeu('echeancesFiscales');
  final lignes = cpcLignesEcheances(brut, auj);

  group('échéances : l\'état est CALCULÉ, jamais stocké', () {
    test('les quatre indicateurs de l\'ouverture', () {
      int nb(String s) => lignes.where((l) => l['etat'] == s).length;
      final k = liste(carte(e['ouverture'])['kpis']);
      expect([nb('en_retard'), nb('a_payer'), nb('declaration'), nb('payee')], [for (final x in k) int.parse(x['valeur'] as String)]);
      expect(lignes.length, 63);
    });

    test('chaque ligne du tableau (63, triées par échéance) : code, date, délai et état de la maquette', () {
      final tri = [for (final (i, l) in lignes.indexed) (i, l)]..sort((a, b) {
          final c = DateTime.parse('${a.$2['echeance']}').compareTo(DateTime.parse('${b.$2['echeance']}'));
          return c != 0 ? c : a.$1.compareTo(b.$1);
        });
      final attLignes = (e['lignes'] as List);
      expect(attLignes.length, tri.length);
      for (var i = 0; i < tri.length; i++) {
        final x = tri[i].$2;
        final c = cellules(attLignes[i]);
        final j = x['jours'] as int;
        final delai = x['paye'] == true ? '—' : (j < 0 ? '$j'.replaceFirst('-', '') + ' j de retard' : 'dans $j j');
        expect(c[0], x['code'], reason: 'ligne $i');
        expect(c[3], delai, reason: 'ligne $i ${x['code']}');
        expect(c[4], cpcEtat('${x['etat']}').$2, reason: 'ligne $i');
        expect(c[2], startsWith(nt(dateFR(DateTime.parse('${x['echeance']}')))), reason: 'ligne $i');
        expect(c[2].contains('reportée — jour ouvrable'), x['reportee'] == true, reason: 'ligne $i');
      }
    });

    test('un samedi ou un dimanche est reporté au jour ouvrable SUIVANT, jamais avancé', () {
      expect(cpcJourOuvrableSuivant(DateTime(2026, 1, 10)), DateTime(2026, 1, 12), reason: 'samedi → lundi');
      expect(cpcJourOuvrableSuivant(DateTime(2026, 1, 11)), DateTime(2026, 1, 12), reason: 'dimanche → lundi');
      expect(cpcJourOuvrableSuivant(DateTime(2026, 1, 9)), DateTime(2026, 1, 9), reason: 'vendredi : inchangé');
      // la maquette l'a fait pour toutes les échéances du jeu : une échéance « reportée » n'est jamais un week-end
      for (final x in brut) {
        final d = DateTime.parse('${x['echeance']}');
        expect(d.weekday <= 5, true, reason: '${x['code']} ${x['echeance']}');
      }
    });

    test('les compteurs des filtres sont ceux de la maquette', () {
      final pf = carte(e['parFiltre']);
      expect(lignes.where((l) => l['etat'] == 'en_retard').length, pf['État|en_retard']);
      expect(lignes.where((l) => l['etat'] == 'declaration').length, pf['État|declaration']);
      expect(lignes.where((l) => l['etat'] == 'a_venir').length, pf['État|a_venir']);
      expect(lignes.where((l) => l['periodicite'] == 'annuelle').length, pf['Périodicité|annuelle']);
      expect(lignes.where((l) => l['famille'] == 'ITS').length, pf['Obligation|ITS']);
    });
  });

  group('la barre de notification et l\'alerte sonore', () {
    test('à l\'ouverture : retards nommés, déclarations annoncées — comme la maquette', () {
      final notes = (carte(e['ouverture'])['notes'] as List).cast<String>();
      final barre = cpcBarreEcheances(lignes);
      expect(barre.map((a) => a.ton), ['danger', 'info']);
      expect(nt(notes[0]), contains(nt(barre[0].titre)));
      expect(nt(notes[0]), contains(nt(barre[0].detail)));
      expect(nt(notes[1]), contains(nt(barre[1].titre)));
      expect(nt(notes[1]), contains(nt(barre[1].detail)));
      expect(barre[0].cible!['code'], 'ITS');
      expect(barre[1].cible, isNull, reason: 'une déclaration précède le paiement : rien à valider encore');
    });

    test('l\'alerte sonore de l\'ouverture : le retard prime, avec le libellé et la date de la première échéance en retard', () {
      final a = cpcAlerteOuverture(lignes)!;
      final att = liste(e['alertesOuverture']).first;
      expect([a.message, a.son, a.type, a.detail], [att['message'], att['son'], att['type'], att['detail']]);
    });

    test('trois situations : tout payé, rien de payé, tout à venir', () {
      final cas = carte(e['cas']);
      List<F> sous(F Function(F) t) => cpcLignesEcheances([for (final x in brut) t({...x})], auj);
      final toutPaye = cpcBarreEcheances(sous((x) => x..['paye'] = true));
      expect(toutPaye.single.ton, 'success');
      expect(nt((carte(cas['toutPaye'])['notes'] as List).first), contains(nt(toutPaye.single.detail)));
      expect(cpcAlerteOuverture(sous((x) => x..['paye'] = true)), isNull);
      final rien = cpcBarreEcheances(sous((x) => x..['paye'] = false));
      expect(rien.map((a) => a.ton), ['danger', 'info']);
      expect(nt((carte(cas['rienPaye'])['notes'] as List).first), contains(nt(rien[0].titre)));
      expect(nt((carte(cas['rienPaye'])['notes'] as List).first), contains(nt(rien[0].detail)));
      final avenir = cpcBarreEcheances(sous((x) {
        final passee = '${x['echeance']}'.compareTo('2026-10-30') < 0;
        return x
          ..['paye'] = passee
          ..['echeance'] = passee ? x['echeance'] : '2027-${'${x['echeance']}'.substring(5)}';
      }));
      expect(avenir.single.ton, 'success');
      expect(nt((carte(cas['toutALAvenir'])['notes'] as List).first), contains(nt(avenir.single.detail)));
      expect(avenir.single.detail, 'La prochaine obligation tombe le 10/11/2027', reason: 'E804 : la date est formatée, plus d\'« undefined »');
      expect(cpcAlerteOuverture(sous((x) => x..['paye'] = false))!.message, '54 échéance(s) en retard');
    });

    test('le rappel d\'une échéance en retard', () {
      final r = cpcRappel(lignes.firstWhere((l) => l['etat'] == 'en_retard'));
      final att = liste(e['rappel']).first;
      expect([r.message, r.detail], [att['message'], att['detail']]);
    });
  });

  group('validation et annulation d\'un paiement', () {
    test('le patch d\'un paiement validé est celui que la maquette écrit', () {
      final att = carte(liste(carte(carte(carte(e['apres'])['ecart'])['modifs'])['echeancesFiscales']).first['patch']);
      expect(
          cpcPatchPaiement(
              datePaiement: '2026-10-30', montant: 125000, moyen: 'Virement bancaire', reference: 'QUIT-TEST-0001', valideePar: 'BASSONGUI Chabi Séko'),
          att);
    });
    test('l\'annulation remet l\'échéance DUE, garde le motif, et ne touche pas au moyen', () {
      final att = carte(liste(carte(carte(carte(e['annulation'])['ecart'])['modifs'])['echeancesFiscales']).first['patch']);
      expect(cpcPatchAnnulation('Paiement saisi sur la mauvaise échéance'), att);
      expect(att.containsKey('moyen'), false);
    });
    test('les quatre moyens de règlement de la maquette', () {
      final champs = (carte(e['modaleValider'])['texte'] as String);
      for (final m in cpcMoyensReglement) {
        expect(champs, contains(m));
      }
    });
  });

  group('baseline 2025 : le diagnostic est CALCULÉ', () {
    final x = cpcExercice2025;
    test('les huit indicateurs', () {
      final k = liste(b['kpis']);
      expect(nt(money(x.totalChiffreAffaires)), nt(k[0]['valeur']));
      expect(nt(money(x.totalCharges)), nt(k[1]['valeur']));
      expect(nt(money(x.resultat)), nt(k[2]['valeur']));
      expect(nt(pourcent(x.resultat / x.totalChiffreAffaires * 100)), nt('${k[2]['indice']}'.split(' du ').first));
      expect(nt(money(x.totalChiffreAffaires / 12)), nt(k[3]['valeur']));
      expect(x.mois[x.indiceMeilleurMois], k[4]['valeur']);
      expect(nt(money(x.chiffreAffaires[x.indiceMeilleurMois])), nt(k[4]['indice']));
      expect(x.mois[x.indiceMoisFaible], k[5]['valeur']);
      expect(x.postesCharges().length, int.parse('${k[6]['valeur']}'));
      expect(nt(money(x.totalHorsExploitation)), nt(k[7]['valeur']));
    });

    test('141 667 FCFA n\'est PAS un arrondi : c\'est l\'échéance mensuelle omise par la ligne TOTAL (calculé, jamais écrit en dur)', () {
      final d = cpcExpliquerEcart(x)!;
      expect(d.ecart, 141667);
      expect(d.incoherentes, isEmpty, reason: 'le détail somme exactement à ses propres totaux');
      expect(d.mensuelles.length, 1);
      expect(d.mensuelles.first.ligne.libelle, 'FONDS DE GARANTIE');
      expect(d.mensuelles.first.mois.map((i) => x.mois[i]), ['novembre', 'décembre']);
      final note = nt((b['notes'] as List)[1]);
      expect(note, contains(nt(money(d.ecart))));
      expect(note, contains('« ${d.mensuelles.first.ligne.libelle} »'));
      expect(note, contains('novembre et décembre'));
      expect(note, contains('${x.depenses.length} lignes du détail'));
      expect(note, contains(nt(money(x.controle.totalDetail))));
    });

    test('si le classeur est régénéré sans écart, plus de diagnostic ; si le détail est incohérent, l\'écart vient du détail', () {
      final sans = CpcExercice2025({
        ...jsonDecode(cpcExercice2025Json) as Map<String, dynamic>,
        'controle': {'totalDetail': 1, 'totalClasseur': 1, 'ecart': 0, 'postesSansCompte': 0, 'montantSansCompte': 0}
      });
      expect(cpcExpliquerEcart(sans), isNull);
      final j = jsonDecode(cpcExercice2025Json) as Map<String, dynamic>;
      (j['depenses'] as List).first['total'] = 1.0;
      expect(cpcExpliquerEcart(CpcExercice2025(j))!.incoherentes, isNotEmpty);
    });

    test('trois postes sans compte : un rattachement PROPOSÉ avec son motif, jamais appliqué', () {
      final sans = x.depenses.where((d) => d.num == null).toList();
      expect(sans.length, x.controle.postesSansCompte);
      expect(sans.fold(0.0, (a, d) => a + d.total), x.controle.montantSansCompte);
      expect((carte(liste(b['tablesControle']).first)['lignes'] as List).length, 3);
      for (final l in (carte(liste(b['tablesControle']).first)['lignes'] as List)) {
        final c = cellules(l);
        final p = cpcPropositionCompte(c[0])!;
        expect(c[2], '${p.compte} ${p.intitule}');
        expect(c[3], p.motif);
        expect(c[1], nt(money(sans.firstWhere((d) => d.libelle == c[0]).total, avecDevise: false)));
      }
      expect(cpcPropositionCompte('  fonds de garantie ')!.compte, '275000');
      expect(cpcPropositionCompte('AUTRE POSTE'), isNull);
    });

    test('détail mensuel : chiffre d\'affaires, charges d\'exploitation, résultat et marge', () {
      final att = (b['mensuel'] as List);
      expect(att.length, 12);
      for (var i = 0; i < 12; i++) {
        final c = cellules(att[i]);
        expect(c[1], nt(money(x.chiffreAffaires[i], avecDevise: false)), reason: 'CA ${x.mois[i]}');
        expect(c[2], nt(money(arrondiJs(x.chargesDuMois(i)), avecDevise: false)), reason: 'charges ${x.mois[i]}');
        expect(c[3], nt(money(arrondiJs(x.resultatDuMois(i)), avecDevise: false)), reason: 'résultat ${x.mois[i]}');
        expect(c[4], '${cpcMargeMois(x, i)} %');
      }
    });

    test('les postes de charges : poids décroissant, hors postes de bilan (emprunt, cautionnements, immobilisation)', () {
      final p = x.postesCharges();
      final att = carte(b['charges']);
      expect(p.length, 30);
      final prem = (att['premier'] as List);
      for (var i = 0; i < prem.length; i++) {
        final c = cellules(prem[i]);
        expect([c[0], c[1], c[2], c[4]], [p[i].num, p[i].libelle, nt(money(p[i].total, avecDevise: false)), nt(pourcent(p[i].total / x.totalCharges * 100))]);
      }
      expect(x.postesCharges().any((d) => x.horsExploitation.containsKey(d.num)), false);
      final classement = ((att['classement'] as List).first as List);
      for (var i = 0; i < classement.length; i++) {
        expect(nt(classement[i][0]), p[i].libelle);
      }
    });

    test('la comparaison 2025 / 2026 se lit sur les factures du jeu', () {
      final c = cpcComparaison(x, jeu('factures').where((e) => e['statut'] != 'archive'));
      final att = ((b['comparaison'] as Map)['lignes'] as List);
      for (var i = 0; i < 12; i++) {
        final l = cellules(att[i]);
        expect(l[0], c[i].mois);
        expect(l[1], nt(money(c[i].ca2025, avecDevise: false)));
        expect(l[2], nt(money(c[i].ca2026, avecDevise: false)), reason: c[i].mois);
        expect(l[3], nt(money(c[i].ecart, avecDevise: false)));
        expect(l[4], '${c[i].evolution} %');
      }
    });
  });
}
