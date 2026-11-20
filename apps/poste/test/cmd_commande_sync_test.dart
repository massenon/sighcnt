import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/demandes_validation_poste.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/sync/service_demandes_validation.dart';

import 'aide_grand_stock.dart';

/// LOT CMD (Direction, section AQ point 1 : « ELLE VOYAGE A LA SYNCHRONISATION ») : la commande de stock gros voyage, contre la VRAIE mère Dart et DEUX VRAIS moteurs de fileul (la mère arrêtée pour de vrai) :
///  - une commande créée sur le fileul F1 (le gestionnaire de stock) porte une référence PROVISOIRE par poste ; la mère attribue le rang DÉFINITIF, qui revient à F1 et arrive à F2 ; jamais de doublon, aucune
///    référence définitive réécrite ;
///  - la Directrice Administrative, sur F2 (un AUTRE poste), SIGNE la décision de valider ; la mère l'applique (droit relu sous le rôle de l'AUTEUR, datée de la signature) ; la validation arrive partout ;
///  - un fileul sans le droit : refus nommé au dépôt ; une décision signée sans droit qui arrive quand même : refusée nommée par la mère ; une validation écrite DIRECTEMENT sur la fiche : refusée au rejeu ;
///  - mère coupée puis relancée : la décision attend (comptée), puis s'applique UNE fois ; rejeu sans doublon ;
///  - jamais vers un téléphone (RG-13).
/// Non éprouvé ici : le relais cPanel réel, deux machines distinctes, Windows, charge.
typedef M = Map<String, Object?>;

M commande(String date, String fournisseur, num q, {String ref = 'BC-2026-P1-0001'}) => {
      'reference': ref,
      'date': date,
      'fournisseur': fournisseur,
      'fournisseurNom': 'Fournisseur $fournisseur',
      'statutCommande': 'attente_validation',
      'statut': 'actif',
      'montant': q * 100,
      'lignes': [
        {'produitId': 'PRD1', 'produit': 'Gants', 'quantite': q, 'prixUnitaire': 100, 'montant': q * 100}
      ],
    };

Iterable<Fiche> parDate(Magasin m, String date) => m.collection('commandes').toutes.where((c) => c['date'] == date);
Fiche une(Magasin m, String date) => parDate(m, date).single;

void main() {
  test('CMD : créée sur F1, adoptée par la mère (rang définitif), validée par la DAF sur F2 par décision signée ; sans droit refusé ; validation directe refusée ; mère coupée puis relancée ; rien vers un mobile',
      () async {
    final c = Clinique(9760, '${Directory.systemTemp.createTempSync('sigh-cmd-').path}/mere.sqlite');
    await c.demarrer();
    final tMere = DateTime.utc(2026, 11, 16, 18);
    final sv = ServiceDemandesValidation(c.mm, donnees: () async => donnees, horloge: () => tMere);
    try {
      c.mm.collection('utilisateurs').inserer({'id': 'U-DAF', 'statut': 'actif', 'nom': 'Mme DAF', 'nomComplet': 'Mme DAF', 'role': 'da'});
      c.mm.collection('utilisateurs').inserer({'id': 'U-STK', 'statut': 'actif', 'nom': 'M. STOCK', 'nomComplet': 'M. STOCK', 'role': 'stock'});
      final f1 = await c.fileul('F1', 'stock', 'M. STOCK');
      final f2 = await c.fileul('F2', 'da', 'Mme DAF');
      Future<void> tour() async {
        await c.tour();
        await sv.traiter();
      }

      Future<void> converger(bool Function() fini, String quoi, {int apres = 3}) async {
        final fin = DateTime.now().add(const Duration(seconds: 60));
        while (!fini()) {
          await tour();
          if (DateTime.now().isAfter(fin)) fail('$quoi : pas de convergence (service ${sv.derniereErreur}, F1 ${f1.pont.erreur.value}, F2 ${f2.pont.erreur.value}, refus F1 ${f1.pont.motifsRefus})');
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
        for (var i = 0; i < apres; i++) {
          await tour();
          await Future<void>.delayed(const Duration(milliseconds: 150));
        }
      }

      final libelles = DemandesValidationPoste.libellesDesRoles(donnees.matrice);
      DemandesValidationPoste dem(Poste p, DateTime t) => DemandesValidationPoste(p.m, libelles: libelles, horloge: () => t, etiquette: p.nom, matrice: donnees.matrice);
      bool partout(bool Function(Magasin) p) => [c.mm, f1.m, f2.m].every(p);
      // Une commande ancienne de la mère : son rang compte dans la série définitive.
      c.mm.collection('commandes').inserer({...commande('2026-01-05', 'F0', 1, ref: 'BC-2026-0007'), 'statutCommande': 'livree', 'valideePar': 'Ancien', 'dateValidation': '2026-01-06'}, prefixe: 'COM');
      await converger(() => partout((m) => parDate(m, '2026-01-05').length == 1), 'la commande ancienne est partout');

      // 1. CRÉÉE SUR F1 : référence PROVISOIRE par poste, puis rang DÉFINITIF de la mère (7 + 1), revenu chez F1.
      final prov = referenceCommandeProvisoire(date: '2026-11-16', poste: f1.m.poste, commandes: f1.m.collection('commandes').toutes, maintenant: DateTime(2026, 11, 16));
      expect(estReferenceCommandeProvisoire(prov), isTrue, reason: prov);
      f1.m.collection('commandes').inserer(commande('2026-11-16', 'F1', 10, ref: prov), prefixe: 'COM');
      await converger(() => partout((m) => parDate(m, '2026-11-16').length == 1 && '${une(m, '2026-11-16')['reference']}' == 'BC-2026-0008'), 'la mère adopte la commande, le rang définitif revient à F1 et arrive à F2', apres: 4);
      for (final m in [c.mm, f1.m, f2.m]) {
        expect(parDate(m, '2026-11-16'), hasLength(1), reason: 'jamais de doublon');
        expect(une(m, '2026-11-16')['reference'], 'BC-2026-0008', reason: 'la même référence définitive partout, la plus haute de la série + 1');
        expect(une(m, '2026-11-16')['statutCommande'], 'attente_validation');
      }
      expect(parDate(c.mm, '2026-01-05').single['reference'], 'BC-2026-0007', reason: 'une référence définitive ne se réécrit jamais');

      // 2. LA DAF, SUR F2 (un AUTRE poste que celui de la création), SIGNE la décision : la mère l'applique datée de la signature, sous le rôle de l'AUTEUR.
      final c8 = une(f2.m, '2026-11-16');
      final signe = DateTime(2026, 11, 16, 9, 30);
      // Sans le droit (le gestionnaire de stock sur F1) : refus NOMMÉ au dépôt.
      final sans = dem(f1, signe).deposerCommande(une(f1.m, '2026-11-16'), role: 'stock', acteur: 'M. STOCK');
      expect(sans.ok, isFalse);
      expect(sans.refus!.code, 'VALIDATION_COMMANDE_RESERVEE');
      expect(f1.m.collection(valCollectionDemandes).toutes, isEmpty, reason: 'aucune demande écrite');
      final d = dem(f2, signe).deposerCommande(c8, role: 'da', acteur: 'Mme DAF');
      expect(d.ok, isTrue, reason: '${d.refus?.motif}');
      expect(dem(f2, signe).deposerCommande(c8, role: 'da', acteur: 'Mme DAF').refus!.code, 'DEMANDE_DEJA_DEPOSEE', reason: 'jamais doublée');
      expect(une(f2.m, '2026-11-16')['statutCommande'], 'attente_validation', reason: 'rien n\'est validé tant que la mère n\'a pas appliqué');
      await converger(() => partout((m) => une(m, '2026-11-16')['statutCommande'] == 'validee') && f2.m.collection(valCollectionDemandes).toutes.every((x) => x['etat'] == valEtatAppliquee), 'la mère applique la décision, la validation arrive partout', apres: 4);
      for (final m in [c.mm, f1.m, f2.m]) {
        final cm = une(m, '2026-11-16');
        expect(cm['valideePar'], 'Mme DAF', reason: 'le NOM de la personne qui a décidé, pas celui de la mère');
        expect(cm['dateValidation'], signe.toUtc().toLocal().toIso8601String().substring(0, 10), reason: 'la date de la SIGNATURE');
        expect(cm['reference'], 'BC-2026-0008');
      }
      expect(f2.m.collection(valCollectionDemandes).toutes, hasLength(1), reason: 'rejeu sans doublon : une seule décision');
      expect(c.mm.collection('audit').toutes.where((a) => a['action'] == 'Validation' && '${a['entite']}' == valLibelleCommandeStock), hasLength(1), reason: 'une seule ligne de journal à la mère (RG-12)');

      // 3. UNE DÉCISION SIGNÉE SANS DROIT qui arrive quand même (poste trafiqué) : la mère REFAIT le contrôle sous le rôle de l'auteur et la refuse en nommant.
      f1.m.collection('commandes').inserer(commande('2026-11-17', 'F1', 4, ref: referenceCommandeProvisoire(date: '2026-11-17', poste: f1.m.poste, commandes: f1.m.collection('commandes').toutes, maintenant: DateTime(2026, 11, 16))), prefixe: 'COM');
      await converger(() => partout((m) => parDate(m, '2026-11-17').length == 1 && '${une(m, '2026-11-17')['reference']}' == 'BC-2026-0009'), 'la seconde commande est adoptée (rang 9)', apres: 2);
      final cible = cibleCommande(une(f1.m, '2026-11-17'));
      f1.m.collection(valCollectionDemandes).inserer({
        'id': 'DVTRAFIQUE1',
        'statut': 'actif',
        'famille': valFamilleCommandeStock,
        'cible': cible,
        'libelle': valLibelleCommandeStock,
        'etat': valEtatDeposee,
        'demandePar': 'M. STOCK',
        'demandeRole': 'stock',
        'demandeLe': valInstant(signe),
      });
      await converger(() => f1.m.collection(valCollectionDemandes).parId('DVTRAFIQUE1')?['etat'] == valEtatRefusee, 'la mère refuse la décision sans droit', apres: 2);
      expect(f1.m.collection(valCollectionDemandes).parId('DVTRAFIQUE1')!['resultatCode'], 'VALIDATION_COMMANDE_RESERVEE');
      expect(une(c.mm, '2026-11-17')['statutCommande'], 'attente_validation', reason: 'la commande n\'a pas bougé');

      // 4. UNE VALIDATION ÉCRITE DIRECTEMENT sur la fiche par un autre poste : REFUSÉE au rejeu par la mère (refus nommé), le fileul n'est pas bloqué.
      f1.m.collection('commandes').mettreAJour(une(f1.m, '2026-11-17')['id'], {'statutCommande': 'validee', 'valideePar': 'M. STOCK', 'dateValidation': '2026-11-17'});
      var refusF1 = <Map<String, Object?>>[];
      final finRefus = DateTime.now().add(const Duration(seconds: 40));
      while (!refusF1.any((r) => r['code'] == 'COMMANDE_VALIDATION_DIRECTE')) {
        await tour();
        refusF1 = [for (final r in await f1.moteur.refusees()) (r as Map).cast<String, Object?>()];
        if (DateTime.now().isAfter(finRefus)) fail('la mère ne refuse pas la validation écrite directement : $refusF1');
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      final refusDirect = refusF1.firstWhere((r) => r['code'] == 'COMMANDE_VALIDATION_DIRECTE');
      expect('${refusDirect['motif']}', allOf(contains('REFUSÉE au rejeu'), contains('BC-2026-0009')));
      expect('${refusDirect['geste']}', contains('Valider une commande de stock gros'));
      expect(une(c.mm, '2026-11-17')['statutCommande'], 'attente_validation', reason: 'la mère garde la commande en attente');
      expect(une(c.mm, '2026-11-17')['valideePar'], isNull);
      expect(une(f2.m, '2026-11-17')['statutCommande'], 'attente_validation', reason: 'l\'autre fileul ne voit jamais cette validation');

      // 5. MÈRE COUPÉE : la DAF décide, la décision attend (comptée) ; F1 crée une commande ET F2 une autre (deux postes, même rang provisoire possible) ; au retour : UNE application, deux rangs DISTINCTS.
      await c.mere.arreter();
      final s2 = DateTime(2026, 11, 16, 11);
      final d2 = dem(f2, s2).deposerCommande(une(f2.m, '2026-11-17'), role: 'da', acteur: 'Mme DAF');
      expect(d2.ok, isTrue, reason: '${d2.refus?.motif}');
      f1.m.collection('commandes').inserer(commande('2026-11-18', 'F2', 3, ref: referenceCommandeProvisoire(date: '2026-11-18', poste: f1.m.poste, commandes: f1.m.collection('commandes').toutes, maintenant: DateTime(2026, 11, 16))), prefixe: 'COM');
      f2.m.collection('commandes').inserer(commande('2026-11-19', 'F3', 8, ref: referenceCommandeProvisoire(date: '2026-11-19', poste: f2.m.poste, commandes: f2.m.collection('commandes').toutes, maintenant: DateTime(2026, 11, 16))), prefixe: 'COM');
      // La MÊME commande (même fournisseur, même jour, mêmes lignes) saisie aux deux postes coupés : identité commune par le contenu, UNE fiche.
      for (final p in [f1, f2]) {
        p.m.collection('commandes').inserer(commande('2026-11-20', 'F4', 5, ref: referenceCommandeProvisoire(date: '2026-11-20', poste: p.m.poste, commandes: p.m.collection('commandes').toutes, maintenant: DateTime(2026, 11, 16))), prefixe: 'COM');
      }
      for (var i = 0; i < 3; i++) {
        await f1.tour();
        await f2.tour();
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
      expect(parDate(c.mm, '2026-11-18'), isEmpty, reason: 'la mère est coupée : rien n\'est arrivé');
      expect(dem(f2, s2).synthese().nombre, greaterThanOrEqualTo(1), reason: 'la décision est comptée « en attente de la mère »');
      await c.demarrerMere();
      await converger(
          () => partout((m) => parDate(m, '2026-11-18').length == 1 && parDate(m, '2026-11-19').length == 1 && parDate(m, '2026-11-20').length == 1 && une(m, '2026-11-17')['statutCommande'] == 'validee'),
          'la mère relancée adopte les deux commandes et applique la décision', apres: 5);
      final refs = [for (final m in [c.mm]) for (final x in m.collection('commandes').toutes) '${x['reference']}'];
      expect(refs.toSet().length, refs.length, reason: 'aucune référence en double à la mère : $refs');
      expect(refs.where(estReferenceCommandeProvisoire), isEmpty, reason: 'plus aucune provisoire après l\'adoption : $refs');
      for (final m in [f1.m, f2.m]) {
        expect([for (final x in m.collection('commandes').toutes) '${x['reference']}']..sort(), [...refs]..sort(), reason: 'les fileuls tiennent les mêmes références que la mère');
      }
      expect(une(c.mm, '2026-11-17')['valideePar'], 'Mme DAF');
      expect(dem(f2, s2).synthese().nombre, 0);
      expect(c.mm.collection('commandes').toutes, hasLength(6), reason: 'six commandes à la mère : la même commande saisie aux deux postes coupés n\'en fait qu\'UNE, aucun doublon');
      for (final m in [c.mm, f1.m, f2.m]) {
        expect(parDate(m, '2026-11-20'), hasLength(1), reason: 'identité commune par le contenu');
      }

      // 6. JAMAIS VERS UN TÉLÉPHONE (RG-13) : ni par le journal, ni par un lot de tournée.
      final mobile = await collectionsRecuesParUnMobile(c.port);
      expect(mobile, isNotEmpty);
      expect(mobile.where((o) => o.collection == 'commandes'), isEmpty, reason: 'la commande ne part jamais vers un téléphone');
      final h = HttpClient();
      try {
        final code = await (await (await h.postUrl(Uri.parse('http://127.0.0.1:${c.port}/admin/code'))
                  ..headers.contentType = ContentType.json
                  ..headers.set('x-admin', 'secret-test')
                  ..add(utf8.encode(jsonEncode({'etiquette': 'tel', 'role': 'mobile', 'profil': 'soignant', 'fonction': 'infirmier'}))))
                .close())
            .transform(utf8.decoder)
            .join();
        await (await (await h.postUrl(Uri.parse('http://127.0.0.1:${c.port}/appairage'))
                  ..headers.contentType = ContentType.json
                  ..add(utf8.encode(jsonEncode({'code': (jsonDecode(code) as Map)['code'], 'uuid': 'tel-cmd-1', 'plateforme': 'test'}))))
                .close())
            .drain<void>();
        final rep = await (await h.postUrl(Uri.parse('http://127.0.0.1:${c.port}/admin/lot'))
              ..headers.contentType = ContentType.json
              ..headers.set('x-admin', 'secret-test')
              ..add(utf8.encode(jsonEncode({
                'uuid': 'tel-cmd-1',
                'fiches': [
                  {'collection': 'commandes', 'id': 'X'}
                ],
                'ttl_ms': 60000
              }))))
            .close();
        final corps = await rep.transform(utf8.decoder).join();
        expect(rep.statusCode, 422, reason: corps);
        expect((jsonDecode(corps) as Map)['code'], codeAchatsInterditsAuMobile);
      } finally {
        h.close(force: true);
      }
    } finally {
      sv.arreter();
      await c.arreter();
    }
  }, timeout: const Timeout(Duration(minutes: 6)));
}
