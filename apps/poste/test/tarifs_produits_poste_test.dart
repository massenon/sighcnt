import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/tarifs_poste.dart';

/// LES PRIX D'ACHAT DES PRODUITS AU POSTE (lot TFIN) sur le magasin du jeu livré (184 articles) : la reprise donne sa version 1 à chaque article sans toucher une fiche ; un changement du
/// prix d'achat AJOUTE une version datée (jamais un écrasement) et ne change rien avant le Oui ; RG-02 refuse en nommant ET au moteur du magasin ; le droit de décider est celui de la liste ;
/// la fiche suit la décision de SON article seulement ; un fileul dépose, la mère applique sous le rôle de l'auteur. Les règles elles-mêmes sont celles du domaine (vecteurs de la maquette).
final auj = DateTime(2026, 10, 30, 10);
String plus(int n) => tarIso(auj.add(Duration(days: n)));
Magasin jeu() => Magasin.depuisDossier(Magasin.collectionsDuJeu);

TarifsPoste poste(Magasin m, String role, {String nom = 'Agent', bool fileul = false, String etiquette = 'P'}) => TarifsPoste(m,
    role: role,
    auteur: () => nom,
    fileul: fileul,
    peutEditerEcran: true,
    peutEditerPour: (r) => const ['admin', 'da', 'direction'].contains(r),
    peutProposerPrixAchat: const ['admin', 'da', 'stock'].contains(role),
    peutProposerPrixAchatPour: (r) => const ['admin', 'da', 'stock'].contains(r),
    libelles: const {'da': 'Directrice de l’Administration et des Finances (DAF)', 'direction': 'Direction / Gérance'},
    horloge: () => auj,
    etiquette: etiquette);

Map<String, Object?> produit(Magasin m, {bool medicament = true}) =>
    m.collection('produits').actives.firstWhere((p) => (p['categorie'] == 'medicament') == medicament && (p['prixAchat'] as num? ?? 0) > 0);

DemandeProduit changer(Map<String, Object?> p, int delta, {int jours = 3, bool valider = false, num? vente}) => DemandeProduit(
    code: '${p['code']}', prixAchat: (p['prixAchat'] as num) + delta, prixVente: vente, dateEffet: plus(jours), motif: 'Nouveau tarif du fournisseur', valider: valider);

void main() {
  test('la reprise : chaque article reçoit sa version 1 (le prix qu\'il tient), aucune fiche ne bouge, rejouée elle ne pose rien', () {
    final m = jeu();
    final avant = [for (final p in m.collection('produits').actives) '${p['id']}:${p['prixAchat']}:${p['prixVente']}'];
    expect(TarifsPoste.lire(m).tarifs.where((t) => t['famille'] == 'PRODUIT'), isEmpty, reason: 'le jeu livré ne porte pas encore les prestations de prix des articles');
    expect(TarifsPoste.assurerProduits(m), 184);
    expect(TarifsPoste.assurerProduits(m), 0, reason: 'rejouée : aucune seconde version 1');
    expect([for (final p in m.collection('produits').actives) '${p['id']}:${p['prixAchat']}:${p['prixVente']}'], avant, reason: 'la reprise ne touche aucune fiche');
    final p = produit(m);
    final r = TarifsPoste.prixProduit(m, p, aujourdhui: auj);
    expect([r.absent, r.achat, r.vente, r.version], [false, p['prixAchat'], p['prixAchat'], 1], reason: 'médicament : vente = achat (RG-02)');
  });

  test('un changement AJOUTE une version datée : l\'ancien prix reste lisible, rien ne bouge avant le Oui ; le Oui prend effet à sa date et la fiche suit ; une autre fiche ne bouge pas', () {
    final m = jeu();
    TarifsPoste.assurerProduits(m);
    final p = produit(m), autre = m.collection('produits').actives.firstWhere((x) => x['id'] != p['id'] && x['categorie'] == 'medicament');
    final stock = poste(m, 'stock', nom: 'Gestionnaire de stock'), daf = poste(m, 'da', nom: 'DAF');
    final n0 = TarifsPoste.lire(m).versionsDe('${p['code']}').length;
    final r = stock.proposerPrixAchat(changer(p, 50));
    expect(r.ok, isTrue, reason: '${r.refus?.code} ${r.refus?.motif}');
    expect(TarifsPoste.lire(m).versionsDe('${p['code']}').length, n0 + 1, reason: 'une version AJOUTÉE, jamais un écrasement');
    expect(TarifsPoste.lire(m).versionsDe('${p['code']}').first['prixNonAssure'], p['prixAchat'], reason: 'la version 1 est intacte');
    expect(m.collection('produits').parId(p['id'])!['prixAchat'], p['prixAchat'], reason: 'une proposition ne change rien');
    final ver = r.version!;
    expect(ver['statut'], 'propose');
    expect(daf.decider('${ver['id']}', 'oui').ok, isTrue);
    expect(TarifsPoste.prixProduit(m, p, aujourdhui: auj, date: plus(2)).achat, p['prixAchat'], reason: 'la veille de la date d\'effet : l\'ancien prix');
    final nouveau = TarifsPoste.prixProduit(m, p, aujourdhui: auj, date: plus(3));
    expect([nouveau.achat, nouveau.vente, nouveau.version], [(p['prixAchat'] as num) + 50, (p['prixAchat'] as num) + 50, 2]);
    expect(m.collection('produits').parId(p['id'])!['prixAchat'], p['prixAchat'], reason: 'avant la date d\'effet la fiche garde son prix : la décision ne projette que ce qui est en vigueur aujourd\'hui');
    expect(m.collection('produits').parId(autre['id'])!['prixAchat'], autre['prixAchat'], reason: 'la fiche d\'un autre article ne bouge pas');
    // Effet immédiat : la fiche suit la décision de SON article.
    final q = m.collection('produits').actives.firstWhere((x) => x['categorie'] == 'medicament' && x['id'] != p['id'] && x['id'] != autre['id'] && (x['prixAchat'] as num? ?? 0) > 0);
    final prixQ = q['prixAchat'] as num;
    final v2 = daf.proposerPrixAchat(changer(q, 25, jours: 0, valider: true));
    expect(v2.ok && v2.valideeEnUnGeste, isTrue, reason: '${v2.refus?.code}');
    final f = m.collection('produits').parId(q['id'])!;
    expect([f['prixAchat'], f['prixVente']], [prixQ + 25, prixQ + 25], reason: 'valider en un geste a effet aujourd\'hui : la fiche suit, la vente suit l\'achat (RG-02)');
  });

  test('RG-02 : refusé en nommant (marge, dessous du prix d\'achat) ET au moteur du magasin (insertion ou modification d\'une fiche) ; l\'alignement sur l\'achat passe', () {
    final m = jeu();
    TarifsPoste.assurerProduits(m);
    final p = produit(m), stock = poste(m, 'stock');
    for (final delta in [40, -10]) {
      final r = stock.proposerPrixAchat(changer(p, 10, vente: (p['prixAchat'] as num).toInt() + 10 + delta));
      expect([r.ok, r.refus?.code], [false, 'RG02_MARGE'], reason: 'vente à ${delta > 0 ? 'plus' : 'moins'} de l\'achat');
    }
    expect(() => m.collection('produits').inserer({'id': 'PRD-RG02', 'code': 'RG02-X', 'designation': 'Marge', 'categorie': 'medicament', 'prixAchat': 100, 'prixVente': 140, 'statut': 'actif'}), throwsA(isA<EcritureRefusee>()));
    expect(() => m.collection('produits').mettreAJour(p['id'], {'prixVente': (p['prixAchat'] as num) + 5}), throwsA(isA<EcritureRefusee>()), reason: 'une fiche ne devient pas à marge par une modification');
    m.collection('produits').mettreAJour(p['id'], {'stockDetail': 7});
    expect(m.collection('produits').parId(p['id'])!['stockDetail'], 7, reason: 'un mouvement de stock (ni achat ni vente touchés) passe');
    m.collection('produits').inserer({'id': 'PRD-OK', 'code': 'RG02-OK', 'designation': 'Sans marge', 'categorie': 'medicament', 'prixAchat': 100, 'prixVente': 100, 'statut': 'actif'});
    m.collection('produits').inserer({'id': 'PRD-LIBRE', 'code': 'RG02-LIBRE', 'designation': 'Consommable', 'categorie': 'consommable', 'prixAchat': 100, 'prixVente': 160, 'statut': 'actif'});
    expect(m.collection('produits').parId('PRD-LIBRE')!['prixVente'], 160, reason: 'hors médicament le prix de vente propre est libre');
  });

  test('les droits : proposer = modifier « Référentiel produits » ; décider = la liste de rôles ; le gestionnaire de stock ne décide pas, le comptable ne propose pas', () {
    final m = jeu();
    TarifsPoste.assurerProduits(m);
    final p = produit(m);
    expect(poste(m, 'comptable').proposerPrixAchat(changer(p, 5)).refus?.code, 'PROPOSITION_RESERVEE');
    final stock = poste(m, 'stock');
    expect(stock.proposerPrixAchat(changer(p, 5, valider: true)).refus?.code, 'VALIDATION_RESERVEE', reason: 'valider n\'est pas modifier la fiche');
    final r = stock.proposerPrixAchat(changer(p, 5));
    expect(r.ok, isTrue);
    expect(stock.decider('${r.version!['id']}', 'oui').refus?.code, 'VALIDATION_RESERVEE', reason: 'le droit de décider est celui de la liste, jamais « modifier »');
    expect(poste(m, 'da').decider('${r.version!['id']}', 'non', motif: 'Prix hors grille').ok, isTrue);
    expect(TarifsPoste.prixProduit(m, p, aujourdhui: auj, date: plus(5)).achat, p['prixAchat'], reason: 'un Non ne change rien');
  });

  test('la création d\'une fiche pose la version 1 ; sans prix, « à valoriser » ; rejouée, aucune seconde version 1 ; un fileul ne l\'écrit pas', () {
    final m = jeu();
    TarifsPoste.assurerProduits(m);
    final daf = poste(m, 'da');
    final f1 = m.collection('produits').inserer({'id': 'PRD-N1', 'code': 'NEUF-1', 'designation': 'Neuf', 'categorie': 'consommable', 'prixAchat': 700, 'statut': 'actif'});
    expect(f1, isNotNull);
    final r = daf.creerPrixProduit(m.collection('produits').parId('PRD-N1')!);
    expect([r.ok, r.version!['statut'], r.version!['version'], r.version!.containsKey('dateEffet')], [true, 'valide', 1, false]);
    expect(daf.creerPrixProduit(m.collection('produits').parId('PRD-N1')!).reutilise, isTrue, reason: 'aucune seconde version 1');
    m.collection('produits').inserer({'id': 'PRD-N2', 'code': 'NEUF-2', 'designation': 'Sans prix', 'categorie': 'consommable', 'statut': 'actif'});
    expect(daf.creerPrixProduit(m.collection('produits').parId('PRD-N2')!).ok, isTrue);
    final av = TarifsPoste.produitsAValoriser(m, aujourdhui: auj);
    expect(av.map((x) => x.produit['code']), ['NEUF-2'], reason: 'un article sans prix d\'achat se crée à valoriser, il ne se facture pas');
    expect(TarifsPoste.prixProduit(m, m.collection('produits').parId('PRD-N2')!, aujourdhui: auj).absent, isTrue, reason: 'absent n\'est pas zéro');
    final fil = poste(jeu(), 'da', fileul: true);
    expect(fil.creerPrixProduit({'code': 'NEUF-3', 'prixAchat': 10, 'categorie': 'consommable'}).refus?.code, 'CONFIGURATION_DE_LA_MERE');
  });

  test('un fileul DÉPOSE la proposition ; la mère l\'applique sous le rôle de l\'auteur, une seule fois ; un rôle sans le droit est refusé en nommant', () {
    final mm = jeu(), mf = jeu();
    TarifsPoste.assurerProduits(mm);
    TarifsPoste.assurerProduits(mf);
    final p = produit(mm);
    final fil = poste(mf, 'stock', nom: 'Gestionnaire fileul', fileul: true, etiquette: 'F'), daf = poste(mm, 'da', nom: 'DAF', etiquette: 'M');
    final avantF = TarifsPoste.lire(mf).versions.length;
    final dem = fil.proposerPrixAchat(changer(p, 40));
    expect(dem.ok && dem.depose, isTrue, reason: '${dem.refus?.code}');
    expect(TarifsPoste.lire(mf).versions.length, avantF, reason: 'le fileul n\'écrit aucune version');
    // La demande voyage (la collection de demandes de la mère reçoit la fiche) ; elle est rejouée UNE fois.
    for (final d in mf.collection('propositionsTarif').toutes) {
      mm.collection('propositionsTarif').appliquerDistante(d);
    }
    expect(daf.appliquerDemandes(), 1);
    expect(daf.appliquerDemandes(), 0, reason: 'rejeu sans effet');
    final v = TarifsPoste.lire(mm).versionsDe('${p['code']}').last;
    expect([v['proposePar'], v['proposeRole'], v['statut'], v['prixNonAssure']], ['Gestionnaire fileul', 'stock', 'propose', (p['prixAchat'] as num) + 40]);
    // Un poste modifié dépose la demande d'un rôle SANS le droit : la mère refait le contrôle et refuse.
    mm.collection('propositionsTarif').inserer({
      'id': 'DTFORGEE',
      'statut': 'actif',
      'genre': 'propositionProduit',
      'etat': 'deposee',
      'code': '${produit(mm, medicament: false)['code']}',
      'prixAchat': 999,
      'dateEffet': plus(6),
      'motif': 'x',
      'demandePar': 'Comptable',
      'demandeRole': 'comptable',
      'demandeLe': tarIso(auj),
    });
    expect(daf.appliquerDemandes(), 1);
    final refus = mm.collection('propositionsTarif').parId('DTFORGEE')!;
    expect([refus['etat'], refus['resultatCode']], ['refusee', 'PROPOSITION_RESERVEE']);
    expect('${refus['resultatMotif']}'.isNotEmpty && '${refus['resultatGeste']}'.isNotEmpty, isTrue);
  });
}
