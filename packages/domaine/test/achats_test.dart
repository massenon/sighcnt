// Rejoue les vecteurs des ACHATS (M7) — écrans réels de la maquette pilotés dans Chrome (prototype_html/build/vecteurs-achats.js) :
// achats-besoins.json (vues, arbitrage, saisie, modifications), achats-commandes.json (RG-04), achats-reception.json (réception, livraisons, écarts).
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

typedef M = Map<String, Object?>;

M lire(String nom) {
  final f = File('test/vecteurs/$nom.json');
  if (!f.existsSync()) {
    fail('vecteurs absents : lancer `node prototype_html/build/vecteurs-achats.js`');
  }
  return (jsonDecode(f.readAsStringSync()) as Map).cast<String, Object?>();
}

List<M> liste(Object? v) =>
    [for (final x in (v as List? ?? const [])) (x as Map).cast<String, Object?>()];

/// Le magasin ne garde pas les champs nuls : absent et nul se valent.
void memes(Object? obtenu, Object? attendu, String chemin) {
  if (attendu is Map || obtenu is Map) {
    final a = (attendu as Map?) ?? const {};
    final o = (obtenu as Map?) ?? const {};
    for (final k in {...a.keys, ...o.keys}) {
      memes(o[k], a[k], '$chemin.$k');
    }
  } else if (attendu is List) {
    final o = obtenu as List;
    expect(o.length, attendu.length, reason: '$chemin : longueur');
    for (var i = 0; i < attendu.length; i++) {
      memes(o[i], attendu[i], '$chemin[$i]');
    }
  } else if (attendu is num && obtenu is num) {
    expect(obtenu.toDouble(), attendu.toDouble(), reason: chemin);
  } else {
    expect(obtenu, attendu, reason: chemin);
  }
}

/// Une fiche sans ses champs techniques (identifiant, statut) : ce que les vecteurs comparent.
M nette(M f) => {...f}..remove('id')..remove('statut');

M produitInitial(M base, List<M> produits, Object? id) =>
    produits.where((p) => p['id'] == id).firstOrNull ?? base;

void main() {
  final besoins = lire('achats-besoins');
  final cmd = lire('achats-commandes');
  final rec = lire('achats-reception');

  group('besoins : les quatre vues d\'une collection', () {
    final vues = (besoins['vues']! as Map).cast<String, Object?>();
    final bons = liste(vues['bons']);
    const libelles = {
      'miennes': 'Mes demandes',
      'arbitrage': 'Arbitrage & validation DAF',
      'achats': 'Besoins validés — achats & logistique',
      'tous': 'Tous les bons',
    };
    for (final c in liste(vues['cas'])) {
      final role = '${c['role']}', moi = '${c['nom']}';
      test('$role (agent $moi)', () {
        final offertes = vuesOffertes(role: role, droitVoir: true);
        final onglets = liste(c['onglets']);
        expect([for (final o in onglets) o['libelle']],
            [for (final v in offertes) libelles[v]]);
        final compte = {
          'miennes': bonsMiens(bons, moi),
          'arbitrage': bonsAArbitrer(bons),
          'achats': bonsPourAchat(bons),
          'tous': bons,
        };
        for (final (i, v) in offertes.indexed) {
          expect(onglets[i]['badge'], compte[v]!.length, reason: '$role/$v : badge');
          final page = trierPar(compte[v]!, (b) => b['date'], descendant: true)
              .take(12)
              .map((b) => b['reference'])
              .toList();
          final lues = ((c['vues']! as Map)[libelles[v]] as Map)['refs'];
          expect(page, lues, reason: '$role/$v : première page');
        }
        // Indicateurs : mes demandes, à arbitrer, livrés, montant estimé cumulé.
        final k = [for (final x in (c['kpis'] as List)) (x as List)[1]];
        expect(k, [
          nombre(bonsMiens(bons, moi).length),
          nombre(bonsAArbitrer(bons).length),
          nombre(bonsLivres(bons)),
          money(bons.fold<num>(0, (a, b) => a + (b['montantEstime'] as num))),
        ]);
        // Le ruban du circuit.
        final circuit = compteCircuit(bons);
        expect([for (final (e, n) in circuit) [e.libelle, n]],
            [for (final x in (c['circuit'] as List)) x]);
      });
    }
    test('un profil qui n\'achète ni n\'arbitre ne voit que ses demandes', () {
      expect(vuesOffertes(role: 'medecin', droitVoir: true), ['miennes']);
      expect(vuesOffertes(role: 'comptable', droitVoir: true),
          ['miennes', 'achats', 'tous']);
      expect(vuesOffertes(role: 'da', droitVoir: true),
          ['miennes', 'arbitrage', 'achats', 'tous']);
      expect(vuesOffertes(role: 'comptable', droitVoir: false),
          ['miennes', 'achats']);
    });
  });

  group('besoins : l\'arbitrage de la DAF', () {
    final arb = (besoins['arbitrage']! as Map).cast<String, Object?>();
    for (final a in liste(arb['arbitrages'])) {
      test('${a['nom']}', () {
        final quoi = Arbitrage.values.byName('${a['quoi']}');
        final avant = (a['avant']! as Map).cast<String, Object?>();
        final apres = (a['apres']! as Map).cast<String, Object?>();
        final toast = liste(a['toasts']).first;
        final exige = quoi != Arbitrage.valider;
        if (exige && '${a['motif']}'.isEmpty) {
          expect(
              () => arbitrerBon(
                  bon: avant, quoi: quoi, utilisateur: 'TAKI Alimatou', maintenant: 'X'),
              throwsA(isA<RefusAchat>().having((e) => e.motif, 'motif', toast['message'])));
          // rien n'est écrit : le bon d'avant est le bon d'après
          memes(apres, avant, 'refus');
          expect(a['notifications'], isEmpty);
          return;
        }
        final r = arbitrerBon(
            bon: avant,
            quoi: quoi,
            motif: '${a['motif']}',
            utilisateur: 'TAKI Alimatou',
            maintenant: '2026-10-30T10:00:00.000Z');
        final obtenu = {...avant, ...r.patch}..remove('arbitreLe');
        memes(obtenu, apres, 'bon');
        expect(r.message, toast['message']);
        expect(r.type, toast['type'] == 'success' ? 'success' : 'warning');
        final notifs = liste(a['notifications']);
        expect(r.notifications.length, notifs.length);
        for (final n in notifs) {
          final mienne = r.notifications.firstWhere((x) => x['poste'] == n['poste']);
          memes(mienne, n, 'notification ${n['poste']}');
        }
        if (quoi == Arbitrage.valider) {
          // La validation informe DEUX postes — le comptable ET le gestionnaire de stock.
          expect({for (final n in r.notifications) n['poste']}, {'comptable', 'stock'});
        } else {
          expect(r.notifications, isEmpty);
        }
      });
    }
    test('rejeter et demander un complément exigent un motif non vide', () {
      for (final q in [Arbitrage.rejeter, Arbitrage.complement]) {
        for (final motif in ['', '   ']) {
          expect(
              () => arbitrerBon(
                  bon: {'reference': 'B'}, quoi: q, motif: motif, utilisateur: 'U', maintenant: 'X'),
              throwsA(isA<RefusAchat>()));
        }
      }
      // valider n'en exige pas
      expect(
          arbitrerBon(bon: {'reference': 'B', 'lignes': []}, quoi: Arbitrage.valider, utilisateur: 'U', maintenant: 'X')
              .patch['etape'],
          'accorde');
    });
    test('rejete et complement sont des ISSUES, pas des étapes du circuit', () {
      final etapes = [for (final e in etapesBesoin) e.id];
      expect(etapes, isNot(contains('rejete')));
      expect(etapes, isNot(contains('complement')));
      expect(etapes, isNot(contains('distribue')));
      expect([for (final e in issuesBesoin) e.id], ['rejete', 'complement', 'distribue']);
    });
    for (final a in liste(arb['achats'])) {
      test('geste de l\'achat : ${a['quoi']}', () {
        final avant = (a['avant']! as Map).cast<String, Object?>();
        final apres = (a['apres']! as Map).cast<String, Object?>();
        final patch = a['quoi'] == 'versCommande'
            ? versCommandeBesoin(utilisateur: 'MAMAN Zoukanéri', maintenant: 'X')
            : distribuerBesoin(utilisateur: 'MAMAN Zoukanéri', maintenant: 'X');
        final obtenu = {...avant, ...patch}
          ..remove('prepareLe')
          ..remove('distribueLe');
        memes(obtenu, apres, 'bon');
        if (a['quoi'] == 'distribuer') {
          expect(messageDistribution(avant), liste(a['toasts']).first['message']);
        } else {
          expect(a['allers'], ['m7-commandes']);
        }
      });
    }
  });

  group('besoins : la saisie', () {
    final produits = liste(besoins['produits']);
    final saisie = (besoins['saisie']! as Map).cast<String, Object?>();
    final vues = (besoins['vues']! as Map).cast<String, Object?>();
    final serie = <M>[
      for (final b in liste(vues['bons']))
        if ('${b['reference']}'.startsWith('BEB-2026-')) b
    ];
    for (final s in liste(saisie['saisies'])) {
      test('${s['nom']}', () {
        final cfg = (s['cfg']! as Map).cast<String, Object?>();
        final role = '${s['role']}';
        final pilote = pilotageCircuit(role: role, droitEditer: true);
        // Le formulaire offre « étape » à qui pilote le circuit — et à lui seul.
        expect((s['champs'] as List).contains('etape'), pilote);
        expect((s['defauts'] as Map)['etape'], pilote ? etapeParDefaut(pilote: true) : null);
        final form = {
          ...(s['defauts']! as Map).cast<String, Object?>(),
          ...(cfg['champs']! as Map).cast<String, Object?>(),
        };
        final lignes = <M>[];
        final refus = <String>[];
        for (final l in liste(cfg['lignes'])) {
          try {
            lignes.add(nouvelleLigneBesoin(
                produit: produits.where((p) => p['id'] == l['produitId']).firstOrNull,
                demandee: l['dem'],
                accordee: l['acc']));
          } on RefusAchat catch (e) {
            refus.add(e.motif);
          }
        }
        M? bon;
        try {
          bon = bonEnregistre(saisie: form, lignes: lignes, bons: serie);
        } on RefusAchat catch (e) {
          refus.add(e.motif);
        }
        final dits = [for (final t in liste(s['toasts'])) t['message']];
        if (s['bon'] == null) {
          expect(bon, isNull);
          expect(refus, dits);
        } else {
          expect(refus, isEmpty);
          memes(bon, nette((s['bon']! as Map).cast<String, Object?>()), 'bon');
          serie.add(bon!);
        }
      });
    }
    test('« part SOUMIS » : un agent qui ne pilote pas le circuit n\'obtient jamais un bon sans étape (E71)', () {
      final b = bonEnregistre(
          saisie: {'date': '2026-10-30', 'service': 'Accueil'},
          lignes: [
            {'quantiteDemandee': 2, 'prixAchat': 100}
          ],
          bons: const []);
      expect(b['etape'], 'soumis');
      expect(b['reference'], 'BEB-2026-0001');
      expect(b['montantEstime'], 200);
    });
    for (final m in liste(besoins['modifications'])) {
      test('modification — ${m['nom']}', () {
        final avant = (m['avant']! as Map).cast<String, Object?>();
        final form = {
          ...(m['defauts']! as Map).cast<String, Object?>(),
          ...(m['champs']! as Map).cast<String, Object?>(),
        };
        final patch = bonEnregistre(
            saisie: form, lignes: liste(avant['lignes']), existant: avant, bons: serie);
        memes({...avant, ...patch}, (m['apres']! as Map).cast<String, Object?>(), 'bon');
        expect(patch['reference'], isNull, reason: 'E75 : modifier ne renumérote pas');
      });
    }
    test('la référence se lit sur la série existante, archivés compris (E70)', () {
      expect(
          referenceAchatSuivante('BEB-2026-', 4, [
            {'reference': 'BEB-2026-0007'},
            {'reference': 'BEB-2025-0099'},
            {'reference': 'autre'}
          ]),
          'BEB-2026-0008');
    });
  });

  group('commandes (RG-04)', () {
    final produits = liste(cmd['produits']);
    final fournisseurs = liste(rec['fournisseurs']);
    final jour = '${cmd['jour']}';
    for (final v in liste(cmd['validations'])) {
      test('validation par ${v['role']}', () {
        if (v['apres'] == null) return; // le geste n'est pas offert à ce profil : il n'y a rien à rejouer
        final avant = (v['avant']! as Map).cast<String, Object?>();
        memes({...avant, ...validationCommande(jour: jour)}, v['apres'], 'commande');
        expect(avant['statutCommande'], 'attente_validation');
        expect(liste(v['toasts']).first['message'], 'Commande validée par la Directrice Administrative.');
      });
    }
    final serie = <M>[
      for (final r in (cmd['serieBC'] as List).take(15)) {'reference': r}
    ];
    for (final c in liste(cmd['creations'])) {
      test('${c['nom']}', () {
        final lignes = <M>[];
        final refus = <String>[];
        for (final l in liste(c['lignes'])) {
          try {
            lignes.add(nouvelleLigneCommande(
                produit: produits.where((p) => p['id'] == l['produitId']).firstOrNull,
                quantite: l['q'],
                prixUnitaire: l['pu'] ?? l['puDefaut']));
          } on RefusAchat catch (e) {
            refus.add(e.motif);
          }
        }
        final form = {
          ...(c['defauts']! as Map).cast<String, Object?>(),
          ...(c['champs']! as Map).cast<String, Object?>(),
        };
        M? obtenue;
        try {
          obtenue = commandeEnregistree(
              saisie: form, lignes: lignes, fournisseurs: fournisseurs, commandes: serie, jour: jour);
        } on RefusAchat catch (e) {
          refus.add(e.motif);
        }
        if (c['commande'] == null) {
          expect(obtenue, isNull);
          expect(refus, [for (final t in liste(c['toasts'])) t['message']]);
        } else {
          expect(refus, isEmpty);
          memes(obtenue, nette((c['commande']! as Map).cast<String, Object?>()), 'commande');
          serie.add(obtenue!);
        }
      });
    }
    for (final m in liste(cmd['modifications'])) {
      test('modification — ${m['nom']}', () {
        final avant = (m['avant']! as Map).cast<String, Object?>();
        final form = {
          ...(m['defauts']! as Map).cast<String, Object?>(),
          'statutCommande': m['statut'],
        };
        final patch = commandeEnregistree(
            saisie: form,
            lignes: liste(avant['lignes']),
            existante: avant,
            fournisseurs: fournisseurs,
            commandes: serie,
            jour: jour);
        memes({...avant, ...patch}, (m['apres']! as Map).cast<String, Object?>(), 'commande');
        expect(patch['reference'], isNull);
      });
    }
    test('indicateurs et file de réception sur les commandes de la maquette', () {
      final lec = (rec['lecture']! as Map).cast<String, Object?>();
      final commandes = liste(lec['commandes']);
      for (final g in liste(lec['gardes'])) {
        final r = (g['receptions']! as Map).cast<String, Object?>();
        final k = indicateursReceptions(commandes);
        expect([for (final x in (r['kpis'] as List)) (x as List)[1]], [
          nombre(k.aReceptionner),
          nombre(k.realisees),
          money(k.valeurAttendue),
          nombre(k.fournisseurs),
        ]);
        final refs = [
          for (final x in (r['refs'] as List))
            if ('$x'.startsWith('BC-')) x
        ];
        expect(commandesAReceptionner(commandes).take(refs.length).map((c) => c['reference']), refs);
      }
      // Tant que la DAF n'a rien validé, rien ne se réceptionne.
      expect(
          commandesAReceptionner([
            {'statutCommande': 'attente_validation'},
            {'statutCommande': 'brouillon'}
          ]),
          isEmpty);
    });
    test('indicateurs des commandes sur le dernier état', () {
      final k = indicateursCommandes(liste(cmd['commandes']));
      final g = liste(cmd['gardes']).first;
      expect([for (final x in (g['kpis'] as List)) (x as List)[1]],
          [nombre(k.enregistrees), nombre(k.enAttente), money(k.montant), nombre(k.livrees)]);
    });
  });

  group('réception d\'une commande', () {
    final produits = liste(rec['produits']);
    for (final r in liste(rec['reception'] == null ? null : (rec['reception']! as Map)['receptions'])) {
      test('${r['nom']}', () {
        if (r['bl'] == null) {
          // refusée par le formulaire (bordereau obligatoire) : rien n'est écrit
          expect((r['champs'] as Map)['referenceBL'], '');
          memes(r['apresProduits'], r['avantProduits'], 'produits');
          return;
        }
        final commande = (r['commande']! as Map).cast<String, Object?>();
        final lignes = liste(commande['lignes']);
        final recus = <String, num>{};
        final saisis = r['saisieRecus'] as List?;
        for (final (i, l) in lignes.indexed) {
          if (saisis != null && i < saisis.length && saisis[i] != null) {
            recus['${l['produitId']}'] = saisis[i] as num;
          }
        }
        final avant = liste(r['avantProduits']);
        final catalogue = [
          for (final a in avant) {...produitInitial({}, produits, a['id']), ...a}
        ];
        final calc = calculerReception(
            commande: commande,
            recus: recus,
            entete: (r['champs']! as Map).cast<String, Object?>(),
            produits: catalogue,
            mouvements: [
              {'reference': 'M000400'}
            ]);
        memes(calc.livraison, nette((r['bl']! as Map).cast<String, Object?>()), 'bordereau');
        // Les mouvements : la maquette insère en tête, l'ordre lu est l'inverse de l'ordre d'écriture.
        final vm = liste(r['mouvements']);
        expect(calc.mouvements.length, vm.length);
        for (final (i, mv) in calc.mouvements.reversed.indexed) {
          memes(mv, nette(vm[i]), 'mouvement $i');
        }
        // Les stocks : seuls les articles connus bougent.
        final apres = liste(r['apresProduits']);
        expect(calc.majProduits.length, apres.where((p) => calc.majProduits.any((m) => m.id == p['id']) ).length);
        for (final p in apres) {
          final maj = calc.majProduits.where((m) => m.id == p['id']).firstOrNull;
          final base = avant.firstWhere((a) => a['id'] == p['id']);
          memes(maj == null ? base : {'id': p['id'], ...maj.patch}, p, 'produit ${p['id']}');
        }
        memes(calc.patchCommande, {'statutCommande': 'livree'}, 'commande');
        final t = liste(r['toasts']).first;
        expect(calc.message, t['message']);
        expect(calc.type, t['type']);
        // Stock gros jamais négatif, CUMP entier (Math.round).
        for (final m in calc.majProduits) {
          expect(m.patch['stockGros'] as num, greaterThanOrEqualTo(0));
          expect((m.patch['cump'] as num) % 1, 0);
        }
      });
    }
    test('CUMP : (valeur du stock + valeur de l\'entrée) / quantité totale, arrondi comme Math.round', () {
      final c = calculerReception(
          commande: {
            'reference': 'BC',
            'fournisseur': 'F',
            'lignes': [
              {'produitId': 'P', 'produit': 'X', 'quantite': 10, 'prixUnitaire': 200}
            ]
          },
          recus: {'P': 10},
          entete: {'referenceBL': 'BL1', 'date': '2026-10-30', 'controleur1': 'A', 'controleur2': 'B'},
          produits: [
            {'id': 'P', 'designation': 'X', 'stock': 10, 'stockGros': 10, 'cump': 101}
          ],
          mouvements: const []);
      // (10×101 + 10×200) / 20 = 150,5 → 151 (la moitié s'arrondit vers le haut)
      expect(c.majProduits.single.patch['cump'], 151);
      expect(c.majProduits.single.patch['stock'], 20);
      expect(c.mouvements.single['reference'], 'M000001');
      expect(c.livraison['statutReception'], 'conforme');
    });
  });

  group('bons de livraison et écarts', () {
    final lec = (rec['lecture']! as Map).cast<String, Object?>();
    test('indicateurs des bons de livraison', () {
      final livs = liste(lec['livraisons']);
      final k = indicateursLivraisons(livs);
      for (final g in liste(lec['gardes'])) {
        final kp = [for (final x in ((g['livraisons']! as Map)['kpis'] as List)) (x as List)[1]];
        expect(kp, [nombre(k.total), nombre(k.conformes), nombre(k.avecEcart), money(k.valeur)]);
      }
      final extra = (lec['livraisonsExtra']! as Map)['kpis'] as List;
      final ke = indicateursLivraisons(liste((lec['ecartsExtra']! as Map)['livraisons']));
      expect([for (final x in extra) (x as List)[1]],
          [nombre(ke.total), nombre(ke.conformes), nombre(ke.avecEcart), money(ke.valeur)]);
    });
    test('registre des écarts — état de la maquette puis jeu d\'essai (manquant, surplus, ligne sans écart, bon conforme ignoré)', () {
      for (final (livs, lu) in [
        (liste(lec['livraisons']), (lec['ecartsLignes'] as List)),
        (liste((lec['ecartsExtra']! as Map)['livraisons']), ((lec['ecartsExtra']! as Map)['lignes'] as List)),
      ]) {
        final r = registreEcarts(livs);
        final obtenu = [
          for (final l in r.lignes)
            [
              l.bl,
              l.commande,
              dateFR(DateTime.parse('${l.date}')),
              l.fournisseur,
              l.produit,
              '${l.commandee}',
              '${l.livree}',
              '${l.ecart % 1 == 0 ? l.ecart.toInt() : l.ecart}',
              money(l.valeur, avecDevise: false),
            ]
        ];
        expect(obtenu, [for (final x in lu) (x as List).cast<Object?>()]);
      }
      final extra = (lec['ecartsExtra']! as Map);
      final k = indicateursEcarts(registreEcarts(liste(extra['livraisons'])));
      expect([for (final x in (extra['kpis'] as List)) (x as List)[1]],
          [nombre(k.ecarts), nombre(k.livraisons), money(k.valeur), nombre(k.fournisseurs)]);
    });
    for (final m in liste(lec['modifsBL'])) {
      test('modification d\'un bon de livraison — ${m['nom']}', () {
        final avant = (m['avant']! as Map).cast<String, Object?>();
        final form = {
          ...(m['defauts']! as Map).cast<String, Object?>(),
          ...(m['champs']! as Map).cast<String, Object?>(),
        };
        memes({...avant, ...livraisonModifiee(form)}, m['apres'], 'bon de livraison');
        expect(livraisonModifiee(form)['controlePar'], isA<List>());
      });
    }
    test('création manuelle d\'un bon de livraison', () {
      final fournisseurs = liste(rec['fournisseurs']);
      final serie = <M>[
        for (final l in liste(lec['livraisons'])) l
      ];
      for (final c in liste(lec['creationsBL'])) {
        if (c['bl'] == null) continue; // refusé par le formulaire (commande rattachée obligatoire)
        final form = {
          ...(c['defauts']! as Map).cast<String, Object?>(),
          ...(c['champs']! as Map).cast<String, Object?>(),
        };
        final bl = livraisonCreee(saisie: form, fournisseurs: fournisseurs, livraisons: serie);
        memes(bl, nette((c['bl']! as Map).cast<String, Object?>()), c['nom'] as String);
        serie.add(bl);
      }
    });
  });
}
