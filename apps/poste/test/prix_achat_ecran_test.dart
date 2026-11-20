import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/parametres_poste.dart';
import 'package:sigh_poste/core/service_installation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/tarifs_poste.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';
import 'm14_aide.dart';

/// L'ÉCRAN « Référentiel produits » PORTE LE CIRCUIT DU PRIX D'ACHAT (lot TFIN-2, PRD-TARIFS T5). Avant ce lot l'écran écrivait `prixAchat` sur la fiche : le circuit versionné (moteur, `TarifsPoste`)
/// n'était vivant qu'au niveau de l'API. Les règles elles-mêmes (RG-02, refus nommés, date d'effet, usage) sont celles du domaine, rejouées sur les vecteurs de la maquette ; ici, le GESTE D'ÉCRAN :
/// « Changer le prix d'achat » AJOUTE une version datée (jamais une réécriture de la fiche), le droit est celui de modifier l'écran (commande ABSENTE sinon), « Valider » est celui de la liste de rôles
/// de la famille, la colonne lit la version en vigueur, un fileul DÉPOSE une demande et n'écrit rien.
Magasin _jeu() {
  final m = magasinM14();
  TarifsPoste.assurerProduits(m);
  return m;
}

Map<String, Object?> _article(Magasin m, {bool medicament = true}) =>
    m.collection('produits').actives.firstWhere((p) => (p['categorie'] == 'medicament') == medicament && (p['prixAchat'] as num? ?? 0) > 0);

Future<void> _chercher(WidgetTester t, String texte) async {
  await t.enterText(find.byKey(const Key('kit:tableau-recherche')).first, texte);
  await t.pump(const Duration(milliseconds: 500));
}

void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  casM14('« Changer le prix d\'achat » AJOUTE une version datée : la version 1 reste, la fiche ne bouge pas, rien ne change avant le Oui', (t) async {
    final m = _jeu();
    final p = _article(m);
    final code = '${p['code']}', ancien = p['prixAchat'] as num;
    await ouvrirM14(t, m, 'm6-produits', role: 'stock');
    await _chercher(t, code);
    final n0 = TarifsPoste.lire(m).versionsDe(code).length;
    await toucherM14(t, find.byTooltip('Changer le prix d’achat').first);
    await saisir(t, 'prixAchat', '${ancien + 75}');
    await saisir(t, 'motif', 'Nouveau tarif du fournisseur');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
    final vs = TarifsPoste.lire(m).versionsDe(code);
    expect(vs.length, n0 + 1, reason: 'une version AJOUTÉE, jamais un écrasement');
    expect(vs.first['prixNonAssure'], ancien, reason: 'la version 1 est intacte');
    expect([vs.last['statut'], vs.last['prixNonAssure'], vs.last['proposeRole'], vs.last['origine']], ['propose', ancien + 75, 'stock', 'ecran']);
    expect(m.collection('produits').parId(p['id'])!['prixAchat'], ancien, reason: 'la fiche ne reçoit rien : une proposition ne change RIEN avant le Oui');
    expect(TarifsPoste.prixProduit(m, p, aujourdhui: aujourdhui).achat, ancien);
    expect(find.text('Proposition enregistrée : elle attend la décision (Oui ou Non).'), findsOneWidget);
    expect(m.collection('audit').toutes.where((a) => a['action'] == 'Changement de prix : proposition').length, 1, reason: 'RG-12 : une ligne de journal');
  });

  casM14('« Valider » est ABSENT pour le gestionnaire de stock (qui propose) et PRÉSENT pour la Directrice Administrative : validé en un geste, il prend effet et la fiche suit sa propre décision', (t) async {
    final m = _jeu();
    final p = _article(m), autre = m.collection('produits').actives.firstWhere((x) => x['id'] != p['id'] && x['categorie'] == 'medicament');
    final code = '${p['code']}', ancien = p['prixAchat'] as num, autreAvant = autre['prixAchat'];
    await ouvrirM14(t, m, 'm6-produits', role: 'stock');
    await _chercher(t, code);
    await toucherM14(t, find.byTooltip('Changer le prix d’achat').first);
    expect(find.widgetWithText(BoutonSigh, 'Valider'), findsNothing, reason: 'la commande est ABSENTE hors de la liste de rôles de la famille, jamais grisée');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Annuler'));

    await ouvrirM14(t, m, 'm6-produits', role: 'da');
    await _chercher(t, code);
    await toucherM14(t, find.byTooltip('Changer le prix d’achat').first);
    expect(find.widgetWithText(BoutonSigh, 'Valider'), findsOneWidget);
    await saisir(t, 'prixAchat', '${ancien + 40}');
    await saisir(t, 'motif', 'Validation d’emblée');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Valider'));
    final v = TarifsPoste.lire(m).versionsDe(code).last;
    expect([v['statut'], v['roleDecision']], ['valide', 'da']);
    expect(m.collection('produits').parId(p['id'])!['prixAchat'], ancien + 40, reason: 'la fiche suit la décision de SON article');
    expect(m.collection('produits').parId(autre['id'])!['prixAchat'], autreAvant, reason: 'une autre fiche ne bouge pas');
    expect(find.textContaining('Prix d’achat validé'), findsOneWidget);
  });

  casM14('ABSENT, jamais grisé, sans le droit de modifier l\'écran ; l\'historique reste offert à qui voit la ligne', (t) async {
    final m = _jeu();
    final code = '${_article(m)['code']}';
    await ouvrirM14(t, m, 'm6-produits', role: 'direction');
    await _chercher(t, code);
    expect(find.byTooltip('Historique de prix'), findsWidgets, reason: 'une lecture');
    expect(find.byTooltip('Changer le prix d’achat'), findsNothing, reason: 'une écriture : absente sans le droit');
    await toucherM14(t, find.byTooltip('Historique de prix').first);
    expect(find.byKey(const Key('prix-achat:historique')), findsOneWidget);
    expect(find.textContaining('Version 1'), findsOneWidget);
  });

  casM14('la MODIFICATION d\'un article ne porte ni prix d\'achat ni prix de vente et ne les écrit pas (le seuil change, le prix reste)', (t) async {
    final m = _jeu();
    final p = _article(m);
    final code = '${p['code']}', achat = p['prixAchat'], vente = p['prixVente'];
    await ouvrirM14(t, m, 'm6-produits', role: 'stock');
    await _chercher(t, code);
    await toucherM14(t, find.byTooltip('Modifier').first);
    expect(find.byKey(const Key('kit:champ:prixAchat')), findsNothing, reason: 'le prix se change par « Changer le prix d’achat »');
    expect(find.byKey(const Key('kit:champ:prixVente')), findsNothing);
    await saisir(t, 'seuilAlerte', '77');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
    final apres = m.collection('produits').parId(p['id'])!;
    expect([apres['seuilAlerte'], apres['prixAchat'], apres['prixVente']], [77, achat, vente]);
    expect(TarifsPoste.lire(m).versionsDe(code).length, 1, reason: 'aucune version ne naît d\'une modification de fiche');
  });

  casM14('la colonne « Prix d\'achat » lit la VERSION en vigueur (pas la fiche) ; un article sans prix est « à valoriser », jamais zéro', (t) async {
    final m = _jeu();
    final p = _article(m);
    final code = '${p['code']}';
    // La fiche est rendue FAUSSE sur le disque : seule la version fait foi.
    m.collection('produits').appliquerDistante({...m.collection('produits').parId(p['id'])!, 'prixAchat': 1});
    final version = TarifsPoste.prixProduit(m, p, aujourdhui: aujourdhui).achat!;
    await ouvrirM14(t, m, 'm6-produits', role: 'stock');
    await _chercher(t, code);
    expect(find.textContaining(money(version, avecDevise: false)), findsWidgets, reason: 'la colonne montre la version, non la fiche à 1');
    // Un article repris SANS prix : « à valoriser ».
    final sans = m.collection('produits').inserer({'code': 'SANS-PRIX', 'designation': 'ARTICLE SANS PRIX', 'categorie': 'consommable', 'unite': 'Unité', 'statut': 'actif', 'stock': 0, 'stockGros': 0, 'stockDetail': 0}).fiche;
    TarifsPoste.assurerProduits(m);
    expect(TarifsPoste.produitsAValoriser(m, aujourdhui: aujourdhui).map((x) => x.produit['id']), contains(sans['id']));
    await t.pump();
    await _chercher(t, 'SANS-PRIX');
    expect(find.text('à valoriser'), findsWidgets);
  });

  casM14('la CRÉATION pose la version 1 du prix d\'achat ; sans prix d\'achat (zéro) elle est REFUSÉE en nommant l\'article, rien n\'est écrit ; RG-02 à l\'écriture', (t) async {
    final m = _jeu();
    await ouvrirM14(t, m, 'm6-produits', role: 'stock');
    final avant = m.collection('produits').actives.length;
    await toucherM14(t, find.text('Nouveau'));
    await saisir(t, 'code', 'NEUF-1');
    await saisir(t, 'designation', 'ARTICLE NEUF');
    await saisir(t, 'prixAchat', '0');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Créer'));
    expect(m.collection('produits').actives.length, avant, reason: 'refusé : rien n\'est écrit');
    expect(find.textContaining('PRIX_ACHAT_ABSENT'), findsWidgets);
    expect(find.textContaining('ARTICLE NEUF'), findsWidgets, reason: 'le refus nomme l\'article');
    await saisir(t, 'prixAchat', '640');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Créer'));
    expect(m.collection('produits').actives.length, avant + 1);
    final vs = TarifsPoste.lire(m).versionsDe('NEUF-1');
    expect(vs.length, 1, reason: 'la version 1 naît AVEC la fiche, par la même voie');
    expect([vs.first['version'], vs.first['statut'], vs.first['prixNonAssure'], vs.first['origine']], [1, 'valide', 640, 'creation']);
  });

  casM14('sur un FILEUL rattaché, « Changer le prix d\'achat » DÉPOSE une demande : aucune version n\'est écrite chez lui', (t) async {
    final m = _jeu();
    await t.runAsync(() => ServiceInstallation.de(m).attacher(StockageMemoire(), const ParametresPoste(uuidPoste: 'u', rejoint: true)));
    final p = _article(m);
    final code = '${p['code']}', ancien = p['prixAchat'] as num;
    // Un fileul reçoit les versions de la mère : on les lui donne (la reprise est faite à la mère seule).
    await ouvrirM14(t, m, 'm6-produits', role: 'stock');
    await _chercher(t, code);
    final n0 = TarifsPoste.lire(m).versionsDe(code).length;
    await toucherM14(t, find.byTooltip('Changer le prix d’achat').first);
    await saisir(t, 'prixAchat', '${ancien + 20}');
    await saisir(t, 'motif', 'Demande du gestionnaire');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
    expect(TarifsPoste.lire(m).versionsDe(code).length, n0, reason: 'rien n\'est écrit chez un fileul hors demande (famille R)');
    final d = m.collection('propositionsTarif').toutes.where((x) => x['genre'] == 'propositionProduit');
    expect(d.length, 1);
    expect([d.first['code'], '${d.first['prixAchat']}', d.first['etat'], d.first['demandeRole']], [code, '${ancien + 20}', 'deposee', 'stock']);
    expect(find.textContaining('Demande déposée à la mère'), findsOneWidget);
  });

  TarifsPoste posteReception(Magasin m, String role, {bool fileul = false, bool m6 = false, bool m7 = true, String nom = 'Agent'}) => TarifsPoste(m,
      role: role,
      auteur: () => nom,
      fileul: fileul,
      peutProposerPrixAchat: m6,
      peutProposerPrixAchatPour: (r) => r == 'compta6',
      peutProposerReception: m7,
      peutProposerReceptionPour: (r) => r == 'recep7',
      libelles: const {'da': 'Directrice de l’Administration et des Finances (DAF)', 'direction': 'Direction / Gérance'},
      horloge: () => aujourdhui,
      etiquette: 'R');

  test('la proposition née d\'une RÉCEPTION a l\'autorité de MODIFIER les réceptions, non celle de modifier « Référentiel produits » ; une seule par produit ; identique, rien', () {
    final m = _jeu();
    final p = _article(m), prix = p['prixAchat'] as num;
    final sansM6 = posteReception(m, 'stock', m6: false, m7: true), sansM7 = posteReception(m, 'stock', m6: true, m7: false);
    var r = sansM7.proposerPrixReception(produit: p, prixRecu: prix + 30, date: tarIso(aujourdhui), reference: 'BL-1');
    expect([r.issue.etat, r.issue.refus?.code], ['refusee', 'PROPOSITION_RESERVEE'], reason: 'modifier « Référentiel produits » ne donne pas le droit de proposer depuis une réception');
    expect(TarifsPoste.lire(m).versionsDe('${p['code']}').length, 1);
    r = sansM6.proposerPrixReception(produit: p, prixRecu: prix, date: tarIso(aujourdhui), reference: 'BL-1');
    expect(r.issue.etat, 'identique', reason: 'un prix identique ne propose rien');
    r = sansM6.proposerPrixReception(produit: p, prixRecu: prix + 30, date: tarIso(aujourdhui), reference: 'BL-1');
    expect([r.issue.etat, r.issue.ancien, r.issue.prix], ['ouverte', prix, prix + 30]);
    final v = TarifsPoste.lire(m).versionsDe('${p['code']}').last;
    expect([v['statut'], v['source'], v['motif'], v['dateEffet']], ['propose', 'Réception BL-1', 'prix constaté à la réception n° BL-1', tarIso(aujourdhui)]);
    expect(m.collection('produits').parId(p['id'])!['prixAchat'], prix, reason: 'aucun prix ne change avant le Oui');
    r = sansM6.proposerPrixReception(produit: p, prixRecu: prix + 60, date: tarIso(aujourdhui), reference: 'BL-2');
    expect(r.issue.etat, 'deja_ouverte', reason: 'une seule proposition ouverte par produit');
    expect(TarifsPoste.lire(m).versionsDe('${p['code']}').length, 2);
  });

  test('un FILEUL dépose la proposition d\'une réception (reception: true) ; la MÈRE l\'applique sous l\'autorité de MODIFIER les réceptions, et la refuse pour un rôle qui ne l\'a pas', () {
    final m = _jeu();
    final p = _article(m), prix = p['prixAchat'] as num;
    final fileul = posteReception(m, 'recep7', fileul: true, m7: true);
    final r = fileul.proposerPrixReception(produit: p, prixRecu: prix + 10, date: tarIso(aujourdhui), reference: 'BL-F');
    expect(r.issue.etat, 'ouverte');
    expect(r.demande!['reception'], true);
    expect(TarifsPoste.lire(m).versionsDe('${p['code']}').length, 1, reason: 'rien n\'est écrit chez un fileul');
    final mere = posteReception(m, 'admin');
    expect(mere.appliquerDemandes(), 1);
    final d = m.collection('propositionsTarif').toutes.single;
    expect(d['etat'], 'appliquee', reason: '${d['resultatCode']} ${d['resultatMotif']}');
    expect(TarifsPoste.lire(m).versionsDe('${p['code']}').last['statut'], 'propose');
    // Une demande de réception forgée sous un rôle qui n'a pas ce droit : refusée en nommant.
    final q = m.collection('produits').actives.firstWhere((x) => x['id'] != p['id'] && x['categorie'] == 'medicament');
    final forge = posteReception(m, 'sans-droit', fileul: true, m7: true).proposerPrixReception(produit: q, prixRecu: (q['prixAchat'] as num) + 10, date: tarIso(aujourdhui), reference: 'BL-X');
    expect(forge.issue.etat, 'ouverte');
    m.collection('propositionsTarif').mettreAJour(forge.demande!['id'], {'demandeRole': 'sans-droit'}, journaliser: false);
    mere.appliquerDemandes();
    final refusee = m.collection('propositionsTarif').toutes.firstWhere((x) => x['id'] == forge.demande!['id']);
    expect([refusee['etat'], refusee['resultatCode']], ['refusee', 'PROPOSITION_RESERVEE']);
  });

  casM14('à l\'ÉCRAN des réceptions, recevoir à un autre prix OUVRE une proposition (sans bloquer la réception) ; l\'annulation du geste la retire', (t) async {
    final m = _jeu();
    final p = _article(m), prix = p['prixAchat'] as num, code = '${p['code']}';
    m.collection('commandes').inserer({
      'reference': 'BC-TFIN2',
      'date': '2099-01-01',
      'fournisseur': 'CAME',
      'fournisseurNom': 'CAME',
      'delaiLivraison': 7,
      'statutCommande': 'validee',
      'valideePar': 'TAKI Alimatou',
      'statut': 'actif',
      'lignes': [
        {'produitId': p['id'], 'produit': p['designation'], 'unite': 'Unité', 'quantite': 4, 'prixUnitaire': prix + 25, 'montant': (prix + 25) * 4}
      ],
      'montant': (prix + 25) * 4,
    }, prefixe: 'COM');
    final blAvant = m.collection('livraisons').actives.length;
    await ouvrirM14(t, m, 'm7-receptions', role: 'stock');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Réceptionner').first);
    await saisir(t, 'referenceBL', 'BL-TFIN2');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Valider la réception'));
    expect(m.collection('livraisons').actives.length, blAvant + 1, reason: 'la réception est écrite : la proposition ne la bloque jamais');
    final v = TarifsPoste.lire(m).versionsDe(code).last;
    expect([v['statut'], v['prixNonAssure'], v['source']], ['propose', prix + 25, 'Réception BL-TFIN2']);
    expect(m.collection('produits').parId(p['id'])!['prixAchat'], prix, reason: 'le prix en vigueur ne change qu\'au Oui');
    expect(find.textContaining('proposition(s) de changement du prix d’achat ouverte(s)'), findsOneWidget);
    await t.pump(const Duration(milliseconds: 400));
    await toucherM14(t, find.text('Annuler').last);
    expect(TarifsPoste.lire(m).versionsDe(code).last['statut'], 'retire', reason: 'annuler la réception retire la proposition qu\'elle a ouverte (jamais supprimée, RG-14)');
  });

  test('une version à DATE FUTURE prend effet le jour venu : la projection du jour met la fiche au pas de la version en vigueur, sans qu\'aucune décision ne passe', () {
    final m = _jeu();
    final p = _article(m), prix = p['prixAchat'] as num;
    final daf = posteReception(m, 'da', m6: true);
    final r = TarifsPoste(m,
            role: 'da', auteur: () => 'DAF', peutProposerPrixAchat: true, libelles: const {}, horloge: () => aujourdhui, etiquette: 'D')
        .proposerPrixAchat(DemandeProduit(code: '${p['code']}', prixAchat: prix + 90, dateEffet: tarIso(aujourdhui.add(const Duration(days: 3))), motif: 'Tarif futur', valider: true));
    expect(r.ok, isTrue, reason: '${r.refus?.code} ${r.refus?.motif}');
    expect(daf.role, 'da');
    expect(m.collection('produits').parId(p['id'])!['prixAchat'], prix, reason: 'avant la date d\'effet la fiche garde l\'ancien prix');
    TarifsPoste.projeter(m, aujourdhui.add(const Duration(days: 2)));
    expect(m.collection('produits').parId(p['id'])!['prixAchat'], prix, reason: 'la veille : toujours l\'ancien');
    TarifsPoste.projeter(m, aujourdhui.add(const Duration(days: 3)));
    expect(m.collection('produits').parId(p['id'])!['prixAchat'], prix + 90, reason: 'le jour venu la fiche suit la version');
    expect(m.collection('produits').parId(p['id'])!['prixVente'], prix + 90, reason: 'RG-02 : médicament, vente = achat');
  });

  casM14('l\'onglet Produits de « Tarifs et prix » lit la VERSION en vigueur, pas la fiche', (t) async {
    final m = _jeu();
    final p = _article(m);
    final version = TarifsPoste.prixProduit(m, p, aujourdhui: aujourdhui).achat!;
    m.collection('produits').appliquerDistante({...m.collection('produits').parId(p['id'])!, 'prixAchat': 3, 'prixVente': 3});
    await ouvrirM14(t, m, 'cfg-tarifs', role: 'da');
    await toucherM14(t, find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('kit:onglet:produits')).first);
    await t.enterText(find.byKey(const Key('kit:tableau-recherche')).first, '${p['code']}');
    await t.pump(const Duration(milliseconds: 500));
    expect(find.textContaining(money(version, avecDevise: false)), findsWidgets, reason: 'la version en vigueur');
    expect(find.text(money(3, avecDevise: false)), findsNothing, reason: 'la fiche altérée n\'est pas lue');
  });

  test('la REPRISE au démarrage de la mère : chaque article reçoit sa version 1, rejouée elle ne pose rien, un fileul ne la fait pas', () {
    final m = magasinM14();
    expect(TarifsPoste.lire(m).tarifs.where((x) => x['famille'] == 'PRODUIT'), isEmpty);
    TarifsPoste.reprendre(m, fileul: true);
    expect(TarifsPoste.lire(m).tarifs.where((x) => x['famille'] == 'PRODUIT'), isEmpty, reason: 'un fileul reçoit les versions avec la configuration, il ne les crée pas');
    TarifsPoste.reprendre(m);
    expect(TarifsPoste.lire(m).tarifs.where((x) => x['famille'] == 'PRODUIT').length, m.collection('produits').actives.length);
    final n = m.collection('versionsTarif').toutes.length;
    TarifsPoste.reprendre(m);
    expect(m.collection('versionsTarif').toutes.length, n, reason: 'idempotent');
  });
}
