import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'commun.dart';
import 'impression.dart';

const _naturesLigne = [
  OptionChamp('acte', 'Acte / consultation'),
  OptionChamp('analyse', 'Analyse de laboratoire'),
  OptionChamp('medicament', 'Médicament'),
  OptionChamp('hospitalisation', 'Journée d’hospitalisation'),
  OptionChamp('libre', 'Ligne libre'),
];

const _libellesNature = {
  'acte': 'Acte',
  'analyse': 'Analyse',
  'medicament': 'Médicament',
  'hospitalisation': 'Hospitalisation',
  'libre': 'Divers',
};

/// Un article proposé au catalogue : libellé, prix, et ce qui décide de sa catégorie de garantie (secteur) ou de son stock (produit).
typedef _Article = ({
  String libelle,
  num prix,
  String? produitId,
  String? secteur
});

/// `m8-facturation` — « Nouvelle facture » : patient, prestations, prise en charge (RG-09) par ligne, encaissement.
/// Un patient non assuré reçoit UNE pièce ; un assuré dont les lignes se partagent en reçoit DEUX (`-A` couvert, `-B` non couvert) —
/// la décision vit dans `packages/domaine` (`emettreFacture`), rejouée sur les vecteurs de l'écran réel de la maquette.
class EcranFacturation extends StatefulWidget with EcranMaquette {
  const EcranFacturation({super.key});

  @override
  String get titre => 'Nouvelle facture';

  @override
  String get description =>
      'Établissement d’une facture : sélection du patient, ajout des prestations et médicaments, calcul de la prise en charge et encaissement.';

  @override
  String get regle =>
      'RG-02 — les médicaments sont ajoutés au prix d’achat, sans marge. RG-09 — la prise en charge assurance n’est appliquée que si la carte est valide à la date de facturation.';

  @override
  State<EcranFacturation> createState() => _EtatFacturation();
}

class _EtatFacturation extends State<EcranFacturation> {
  final List<Fiche> _lignes = [];
  ContexteEcran? _c;

  late ControleurFormulaire _patient;
  late ControleurFormulaire _nature;
  late ControleurFormulaire _ajout;
  late ControleurFormulaire _reglement;
  List<Fiche> _patients = const [];
  List<_Article> _articles = const [];
  String _natureVue = '';
  int? _articleVu;

  // Les contrôleurs dépendent du magasin (patients, natures) : ils naissent au premier `build`, quand le contexte existe.
  bool _pret = false;
  void _preparer(ContexteEcran c) {
    _pret = true;
    final m = c.magasin;
    _patients = trierPar(m.collection('patients').actives, (p) => p['code']);
    final natures = trierPar(
        m.collection('naturesFacture').actives, (x) => x['ordre']);
    _patient = ControleurFormulaire([
      ChampDef(
          nom: 'patient',
          libelle: 'Patient',
          type: TypeChamp.select,
          col: ColChamp.plein,
          recherche: true,
          indicatif: 'Choisir un patient',
          options: [
            for (final p in _patients)
              OptionChamp('${p['id']}', '${p['nom']} ${p['prenom']}')
          ])
    ], {
      'patient': _patients.isEmpty ? '' : '${_patients.first['id']}'
    });
    _nature = ControleurFormulaire([
      ChampDef(
          nom: 'nature',
          libelle: 'Nature de la facture',
          type: TypeChamp.select,
          col: ColChamp.plein,
          requis: true,
          indicatif: '— Nature de la facture —',
          options: [
            for (final x in natures)
              OptionChamp('${x['libelle']}', '${x['libelle']}')
          ])
    ]);
    _ajout = ControleurFormulaire([
      const ChampDef(
          nom: 'nature',
          libelle: 'Nature',
          type: TypeChamp.select,
          requis: true,
          col: ColChamp.tiers,
          options: _naturesLigne),
      const ChampDef(
          nom: 'prestation',
          libelle: 'Prestation',
          type: TypeChamp.select,
          col: ColChamp.demi,
          indicatif: 'Choisir une prestation',
          recherche: true,
          condition: (
            controle: 'nature',
            quand: ['acte', 'analyse', 'medicament', 'hospitalisation']
          )),
      const ChampDef(
          nom: 'designation',
          libelle: 'Désignation',
          col: ColChamp.demi,
          indicatif: 'Désignation de la prestation',
          condition: (controle: 'nature', quand: ['libre'])),
      const ChampDef(
          nom: 'quantite', libelle: 'Qté', type: TypeChamp.nombre, col: ColChamp.tiers),
      const ChampDef(
          nom: 'prix',
          libelle: 'Prix unitaire',
          type: TypeChamp.nombre,
          col: ColChamp.tiers),
      const ChampDef(
          nom: 'remise',
          libelle: 'Remise',
          type: TypeChamp.nombre,
          col: ColChamp.tiers),
      const ChampDef(
          nom: 'typeRemise',
          libelle: 'Type de remise',
          type: TypeChamp.select,
          requis: true,
          col: ColChamp.tiers,
          options: [OptionChamp('pct', '%'), OptionChamp('montant', 'FCFA')]),
      const ChampDef(
          nom: 'motif',
          libelle: 'Motif de remise',
          type: TypeChamp.select,
          col: ColChamp.tiers,
          indicatif: 'Sans remise',
          options: [
            OptionChamp('personnel', 'Remise personnel'),
            OptionChamp('client', 'Remise client'),
            OptionChamp('direction', 'Geste commercial'),
          ]),
    ], {
      'nature': 'acte',
      'quantite': '1',
      'prix': '0',
      'remise': '0',
      'typeRemise': 'pct',
    });
    _reglement = ControleurFormulaire([
      ChampDef(
          nom: 'mode',
          libelle: 'Mode de règlement',
          type: TypeChamp.select,
          requis: true,
          col: ColChamp.plein,
          options: [
            for (final x in modesPaiement.take(4)) OptionChamp(x.$1, x.$2)
          ]),
      const ChampDef(
          nom: 'regle',
          libelle: 'Montant réglé (FCFA)',
          type: TypeChamp.nombre,
          col: ColChamp.plein),
      const ChampDef(
          nom: 'dissocier',
          libelle:
              'Opération de caisse détachée du dossier patient (vente au comptoir)',
          type: TypeChamp.case_,
          col: ColChamp.plein),
    ], {
      'regle': '0'
    });
    _patient.addListener(_majPatient);
    _ajout.addListener(_majAjout);
    _remplirArticles(m);
  }

  @override
  void dispose() {
    if (_pret) {
      _patient.dispose();
      _nature.dispose();
      _ajout.dispose();
      _reglement.dispose();
    }
    super.dispose();
  }

  Fiche? get _patientCourant => _patients
      .where((p) => '${p['id']}' == '${_patient['patient']}')
      .firstOrNull;

  void _majPatient() => setState(() => _proposerReglement());

  // --- catalogue ---------------------------------------------------------------------------------------------------
  void _remplirArticles(Magasin m) {
    final nature = '${_ajout['nature']}';
    final liste = <_Article>[];
    switch (nature) {
      case 'acte':
        for (final a in m.collection('actes').actives) {
          if (a['prix'] == null) continue;
          liste.add((
            libelle: '${a['libelle']}',
            prix: n(a['prix']),
            produitId: null,
            secteur: a['secteur'] as String?
          ));
        }
        if (liste.isEmpty) {
          liste.add((
            libelle: 'Aucun acte tarifé — voir le référentiel tarifaire',
            prix: 0,
            produitId: null,
            secteur: null
          ));
        }
      case 'analyse':
        for (final a in m.referentiel('analyses')) {
          liste.add((
            libelle: '${a['designation']}',
            prix: n(a['prix']),
            produitId: null,
            secteur: null
          ));
        }
      case 'medicament':
        for (final p in m.collection('produits').actives) {
          if (n(p['stockDetail']) <= 0) continue;
          liste.add((
            libelle:
                '${p['designation']} (${nombre(p['stockDetail'])} ${p['unite']})',
            prix: n(p['prixVente']),
            produitId: '${p['id']}',
            secteur: null
          ));
        }
      case 'hospitalisation':
        for (final t in m.referentiel('typesChambre')) {
          liste.add((
            libelle: 'Journée — chambre ${t['label']}',
            prix: n(t['tarif']),
            produitId: null,
            secteur: null
          ));
        }
    }
    _articles = liste;
    _natureVue = nature;
    _articleVu = null;
    final champ = _ajout.champs.firstWhere((c) => c.nom == 'prestation');
    _ajout.champs[_ajout.champs.indexOf(champ)] = ChampDef(
        nom: champ.nom,
        libelle: champ.libelle,
        type: TypeChamp.select,
        col: champ.col,
        indicatif: champ.indicatif,
        recherche: true,
        condition: champ.condition,
        options: [
          for (final (i, x) in liste.indexed)
            OptionChamp('$i', x.libelle)
        ]);
    if (liste.isNotEmpty && nature != 'libre') {
      _articleVu = 0;
      _ajout.poser('prestation', '0');
      _ajout.poser('prix', '${liste.first.prix}');
    } else {
      _ajout.poser('prestation', '');
    }
  }

  void _majAjout() {
    final m = _c!.magasin;
    if ('${_ajout['nature']}' != _natureVue) {
      _remplirArticles(m);
      return;
    }
    final i = int.tryParse('${_ajout['prestation']}');
    if (i != null && i != _articleVu && i < _articles.length) {
      _articleVu = i;
      _ajout.poser('prix', '${_articles[i].prix}');
    }
  }

  // --- calcul ------------------------------------------------------------------------------------------------------
  List<Fiche> _liste(String collection) =>
      _c!.magasin.collection(collection).actives;

  TotauxEmission _totaux() => totauxEmission(
        patient: _patientCourant,
        lignes: _lignes,
        date: iso(_c!.aujourdhui),
        couvertures: _liste('couverturesAssurance'),
        souscripteurs: _liste('souscripteurs'),
        garanties: _liste('garanties'),
      );

  void _proposerReglement() {
    if (_c == null) return;
    _reglement.poser('regle', '${_totaux().partPatient}');
  }

  // --- gestes ------------------------------------------------------------------------------------------------------
  void _ajouter() {
    final v = _ajout;
    final nature = '${v['nature']}';
    _Article? art;
    String designation;
    if (nature == 'libre') {
      designation = '${v['designation'] ?? ''}'.trim();
      if (designation.isEmpty) {
        ToastsSigh.afficher(context, 'Saisir une désignation.',
            type: TypeToast.erreur);
        return;
      }
    } else {
      final i = int.tryParse('${v['prestation']}');
      art = i == null || i >= _articles.length ? null : _articles[i];
      if (art == null) {
        ToastsSigh.afficher(context, 'Sélectionner une prestation.',
            type: TypeToast.erreur);
        return;
      }
      designation = art.libelle;
    }
    final produit = art?.produitId == null
        ? null
        : _c!.magasin.collection('produits').parId(art!.produitId);
    final deja = _lignes
        .where((l) => art?.produitId != null && l['produitId'] == art!.produitId)
        .fold<num>(0, (a, l) => a + n(l['quantite']));
    try {
      _lignes.add(ligneSaisie(
        nature: nature,
        designation: designation,
        quantite: nombreOuZero(v['quantite']),
        prixUnitaire: nombreOuZero(v['prix']),
        produitId: art?.produitId,
        secteur: art?.secteur,
        remise: nombreOuZero(v['remise']),
        typeRemise: '${v['typeRemise']}',
        motifRemise: '${v['motif'] ?? ''}',
        stockDetail: produit == null ? null : n(produit['stockDetail']),
        dejaSurLaFacture: deja,
      ));
    } on RefusEmission catch (r) {
      ToastsSigh.afficher(context, r.motif, type: TypeToast.erreur);
      return;
    }
    _ajout.poser('quantite', '1');
    _ajout.poser('remise', '0');
    if (nature == 'libre') _ajout.poser('designation', '');
    setState(_proposerReglement);
  }

  ResultatEmission _emettre(bool proforma) {
    final c = _c!;
    return emettreFacture(
      patient: _patientCourant!,
      lignes: _lignes,
      dateRepartition: iso(c.aujourdhui),
      dateFacture: iso(c.aujourdhui),
      type: '${_nature['nature']}',
      mode: '${_reglement['mode']}',
      rangDebut: _liste('factures').length,
      reglement: nombreOuZero(_reglement['regle']),
      proforma: proforma,
      dissocier: _reglement['dissocier'] == true,
      couvertures: _liste('couverturesAssurance'),
      souscripteurs: _liste('souscripteurs'),
      garanties: _liste('garanties'),
      produits: [
        for (final p in _liste('produits'))
          {'id': p['id'], 'stockDetail': p['stockDetail'], 'stock': p['stock']}
      ],
    );
  }

  void _enregistrer(bool proforma) {
    if (_lignes.isEmpty || _patientCourant == null) {
      ToastsSigh.afficher(context, 'Ajouter au moins une prestation.',
          type: TypeToast.erreur);
      return;
    }
    final c = _c!;
    final m = c.magasin;
    final r = _emettre(proforma);
    final annulations = <VoidCallback>[];
    final creees = <Fiche>[];
    final factures = m.collection('factures');
    for (final p in r.pieces) {
      final fiche = {...p}..remove('mecef');
      if (p['mecef'] == true) {
        // Identifiant simulé, tiré de l'horloge comme la maquette (`Date.now() % 100000 + rang`) : le boîtier physique n'est pas branché.
        fiche['numeroMecef'] = numeroMecefSimule(
            c.aujourdhui.millisecondsSinceEpoch % 100000 + creees.length);
      }
      fiche['statut'] = 'actif';
      final ins = factures.inserer(fiche, prefixe: 'FAC');
      creees.add(ins.fiche);
      annulations.add(ins.annuler);
    }
    // Sortie automatique du stock pour les médicaments facturés (CDCT §10.7) : RG-03, justificatif = numéro de la pièce.
    final produits = m.collection('produits');
    final mouvements = m.collection('mouvements');
    for (final s in r.sorties) {
      annulations.add(produits.mettreAJour(s.produitId, {
        'stockDetail': s.apres.stockDetail,
        'stock': s.apres.stock,
      }));
      final prod = produits.parId(s.produitId);
      final ins = mouvements.inserer({
        'reference': 'M${(mouvements.toutes.length + 1).toString().padLeft(6, '0')}',
        'date': iso(c.aujourdhui),
        'produitId': s.produitId,
        'produit': prod?['designation'],
        'type': 'sortie',
        'typeLabel': 'Sortie',
        'quantite': s.quantite,
        'stockType': 'detail',
        'justificatif': s.justificatif,
        'utilisateur': c.utilisateur,
        'statut': 'actif',
      }, prefixe: 'MVT');
      annulations.add(ins.annuler);
    }
    final encaisse =
        creees.fold<num>(0, (a, f) => a + n(f['montantPaye']));
    ToastsSigh.afficher(
        context,
        proforma
            ? 'Facture pro-forma établie.'
            : 'Facture enregistrée — ${money(encaisse)} encaissé.',
        type: TypeToast.succes,
        detail: creees.length > 1
            ? 'Deux pièces : ${creees[0]['numero']} (couvert) et ${creees[1]['numero']} (non couvert).'
            : (n(creees[0]['reliquat']) > 0
                ? 'Reliquat de ${money(creees[0]['reliquat'])} à régler.'
                : null),
        duree: const Duration(seconds: 7),
        annuler: () {
          for (final u in annulations.reversed) {
            u();
          }
          setState(() {});
        });
    imprimerFacture(context, creees[0],
        proforma: proforma, jumelle: creees.length > 1 ? creees[1] : null);
    setState(() {
      _lignes.clear();
      _proposerReglement();
    });
  }

  void _apercuTicket() {
    if (_lignes.isEmpty || _patientCourant == null) {
      ToastsSigh.afficher(context, 'Ajouter au moins une prestation.',
          type: TypeToast.erreur);
      return;
    }
    final c = _c!;
    final t = _totaux();
    final p = _patientCourant!;
    final nbFactures = _liste('factures').length;
    final assure = t.partAssureur > 0;
    final detail = t.repartition.lignes;
    final nonAssuree = detail.fold<num>(
        0,
        (a, l) =>
            a + (n(l['partAssureur']) > 0 ? 0 : n(l['montant'])));
    afficherApercuTicket(
        context,
        EntreeTicket(
          operateur: c.utilisateur,
          numero: 'T-${(nbFactures + 1).toString().padLeft(5, '0')}',
          typeVente: assure ? 'ASSURANCE' : 'COMPTANT',
          assureur: assure ? '${p['assureurNom']}' : null,
          assure: assure ? '${p['nom']} ${p['prenom']}' : null,
          dossier: _reglement['dissocier'] == true ? null : '${p['code']}',
          date: c.aujourdhui,
          mecef: BlocMecef(
              nim: 'NIM${IdentiteClinique.ifu.substring(IdentiteClinique.ifu.length - 8)}',
              code: 'CODE-DGI-EN-ATTENTE',
              compteurs: '${nbFactures + 1}/$nbFactures FN'),
          lignes: [
            for (final l in _lignes)
              LigneArticle(
                  designation: '${l['designation']}'.toUpperCase(),
                  quantite: n(l['quantite']),
                  prixUnitaire: n(l['prixNet'] ?? l['prixUnitaire']),
                  montant: n(l['quantite']) * n(l['prixNet'] ?? l['prixUnitaire']))
          ],
          total: t.total,
          remise: t.remises,
          partAssureur: t.partAssureur,
          partPatient: t.partPatient,
          partNonAssuree: nonAssuree,
          regle: nombreOuZero(_reglement['regle']),
          baseMecef: t.partPatient,
        ),
        'T-${(nbFactures + 1).toString().padLeft(5, '0')}');
  }

  Future<void> _nouvelleNature() async {
    final c = _c!;
    final f = ControleurFormulaire([
      const ChampDef(
          nom: 'libelle',
          libelle: 'Nature de la facture',
          requis: true,
          col: ColChamp.plein),
      ChampDef(
          nom: 'secteur',
          libelle: 'Secteur émetteur',
          type: TypeChamp.select,
          requis: true,
          options: [
            for (final s in c.magasin.referentiel('secteursActivite'))
              OptionChamp('${s['id'] ?? s['label'] ?? s}',
                  '${s['label'] ?? s['libelle'] ?? s}')
          ]),
    ]);
    await afficherModale<void>(context,
        titre: 'Nouvelle nature de facture',
        taille: TailleModale.md,
        corps: FormulaireSigh(controleur: f),
        pied: (fermer) => [
              BoutonSigh(
                  libelle: 'Annuler',
                  variante: VarianteBouton.secondaire,
                  onPressed: fermer),
              BoutonSigh(
                  libelle: 'Créer',
                  icone: LucideIcons.plus,
                  onPressed: () {
                    final v = f.valider();
                    if (v == null) return;
                    final col = c.magasin.collection('naturesFacture');
                    final libelle = '${v['libelle']}';
                    final ins = col.inserer({
                      ...v,
                      'code': libelle
                          .substring(0, libelle.length < 4 ? libelle.length : 4)
                          .toUpperCase(),
                      'ordre': col.toutes.length + 1,
                      'source': 'Créée depuis l’émission de facture',
                      'statut': 'actif',
                    }, prefixe: 'NAT');
                    fermer();
                    setState(() {
                      final natures = trierPar(col.actives, (x) => x['ordre']);
                      _nature.champs
                        ..clear()
                        ..add(ChampDef(
                            nom: 'nature',
                            libelle: 'Nature de la facture',
                            type: TypeChamp.select,
                            requis: true,
                            col: ColChamp.plein,
                            options: [
                              for (final x in natures)
                                OptionChamp('${x['libelle']}', '${x['libelle']}')
                            ]));
                      _nature.poser('nature', '${ins.fiche['libelle']}');
                    });
                    ToastsSigh.afficher(context,
                        'Nature « ${ins.fiche['libelle']} » créée et sélectionnée.',
                        type: TypeToast.succes,
                        detail: 'Elle est désormais proposée à toute la caisse.');
                  }),
            ]);
  }

  // --- rendu -------------------------------------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    _c = c;
    if (!_pret) _preparer(c);
    return LayoutBuilder(builder: (context, k) {
      final principal = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _cartePatient(c),
            const SizedBox(height: 16),
            _cartePrestations(c),
          ]);
      final lateral = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _carteRecap(),
            const SizedBox(height: 16),
            _carteActions(c),
            const SizedBox(height: 16),
            _carteRappels(),
          ]);
      if (k.maxWidth < 1024) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          principal,
          const SizedBox(height: 16),
          lateral,
        ]);
      }
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(flex: 2, child: principal),
        const SizedBox(width: 16),
        Expanded(child: lateral),
      ]);
    });
  }

  Widget _cartePatient(ContexteEcran c) => CarteSigh(
        titre: 'Patient et nature de la facture',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          LayoutBuilder(builder: (_, k) {
            final patient = FormulaireSigh(controleur: _patient);
            final nature = Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(child: FormulaireSigh(controleur: _nature)),
                  const SizedBox(width: 8),
                  if (c.droit.editer)
                    BoutonSigh(
                        libelle: 'Nouvelle nature',
                        icone: LucideIcons.plus,
                        taille: TailleBouton.sm,
                        variante: VarianteBouton.secondaire,
                        onPressed: _nouvelleNature),
                ]);
            return k.maxWidth < 640
                ? Column(children: [patient, const SizedBox(height: 12), nature])
                : Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Expanded(child: patient),
                    const SizedBox(width: 12),
                    Expanded(child: nature),
                  ]);
          }),
          const SizedBox(height: 12),
          _infoAssurance(c),
        ]),
      );

  Widget _infoAssurance(ContexteEcran c) {
    final p = _patientCourant;
    if (p == null) return const SizedBox.shrink();
    if (!(p['assureur'] != null && p['assureur'] != '')) {
      return const NoteSigh(
          'Patient non assuré : la facturation est intégrale à sa charge.');
    }
    final valide = carteValide(p, _liste('couverturesAssurance'),
        iso(c.aujourdhui));
    final expiration = DateTime.tryParse('${p['carteExpiration'] ?? ''}');
    if (valide) {
      return NoteSigh(
          'Couverture ${p['assureurNom']} — prise en charge ${p['tauxPriseEnCharge']} %. Carte valide jusqu’au ${expiration == null ? '—' : dateFR(expiration)}.',
          ton: TonSigh.succes,
          icone: LucideIcons.shieldCheck);
    }
    return NoteSigh(
        'RG-09 — carte expirée le ${expiration == null ? '—' : dateFR(expiration)}. La prise en charge ne peut pas être appliquée : la facturation est intégrale au patient.',
        ton: TonSigh.danger,
        icone: LucideIcons.shieldAlert);
  }

  Widget _cartePrestations(ContexteEcran c) => CarteSigh(
        titre: 'Prestations facturées',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          FormulaireSigh(controleur: _ajout),
          const SizedBox(height: 12),
          Align(
              alignment: Alignment.centerLeft,
              child: BoutonSigh(
                  libelle: 'Ajouter',
                  icone: LucideIcons.plus,
                  onPressed: _ajouter)),
          const SizedBox(height: 12),
          _tableauLignes(),
        ]),
      );

  Widget _tableauLignes() {
    if (_lignes.isEmpty) {
      return const VideSigh('Aucune prestation ajoutée.',
          icone: LucideIcons.receipt);
    }
    final t = _totaux();
    TextStyle style([Color? couleur, bool gras = false]) => TextStyle(
        color: couleur ?? JetonsShell.slate700,
        fontSize: 13,
        fontWeight: gras ? FontWeight.w600 : FontWeight.w400);
    Widget cellule(String texte,
            {bool droite = false, Color? couleur, bool gras = false}) =>
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Text(texte,
                textAlign: droite ? TextAlign.right : TextAlign.left,
                style: style(couleur, gras)));
    Widget entete(String texte, {bool droite = false}) => Container(
        color: JetonsShell.slate50,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Text(texte,
            textAlign: droite ? TextAlign.right : TextAlign.left,
            style: const TextStyle(
                color: JetonsShell.slate500,
                fontSize: 12,
                fontWeight: FontWeight.w600)));
    return Container(
      decoration: BoxDecoration(
          border: Border.all(color: JetonsShell.slate200),
          borderRadius: BorderRadius.circular(8)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 760),
            child: Table(
              defaultColumnWidth: const IntrinsicColumnWidth(),
              border: const TableBorder(
                  horizontalInside: BorderSide(color: JetonsShell.slate200)),
              children: [
                TableRow(children: [
                  entete('Désignation'),
                  entete('Qté', droite: true),
                  entete('P.U.', droite: true),
                  entete('Remise', droite: true),
                  entete('P.U net', droite: true),
                  entete('Montant', droite: true),
                  entete('Part ass.', droite: true),
                  entete('Part pat.', droite: true),
                  entete(''),
                ]),
                for (final (i, l) in _lignes.indexed)
                  () {
                    final d = i < t.repartition.lignes.length
                        ? t.repartition.lignes[i]
                        : const <String, Object?>{};
                    final net = n(l['prixNet'] ?? l['prixUnitaire']);
                    final remise = n(l['remiseUnitaire']);
                    return TableRow(children: [
                      Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${l['designation']}',
                                    style: const TextStyle(
                                        color: JetonsShell.slate800,
                                        fontSize: 14)),
                                Text(
                                    '${_libellesNature['${l['nature']}'] ?? l['nature']}${l['motifRemise'] != null ? ' · remise ${l['motifRemise']}' : ''}${d['motif'] != null ? ' · ${d['motif']}' : ''}',
                                    style: const TextStyle(
                                        color: JetonsShell.slate400,
                                        fontSize: 12)),
                              ])),
                      cellule(nombre(l['quantite']), droite: true),
                      cellule(m(l['prixUnitaire']), droite: true),
                      cellule(
                          remise > 0
                              ? '- ${m(remise)}${l['remisePct'] != null && n(l['remisePct']) > 0 ? ' (${nombre(l['remisePct'])} %)' : ''}'
                              : '—',
                          droite: true,
                          couleur: remise > 0
                              ? JetonsShell.warning700
                              : JetonsShell.slate300),
                      cellule(m(net), droite: true),
                      cellule(m(n(l['quantite']) * net),
                          droite: true, gras: true),
                      cellule(
                          n(d['partAssureur']) > 0 ? m(d['partAssureur']) : '—',
                          droite: true,
                          couleur: n(d['partAssureur']) > 0
                              ? JetonsShell.info600
                              : JetonsShell.slate300),
                      cellule(
                          m(d['partPatient'] != null
                              ? d['partPatient']
                              : n(l['quantite']) * net),
                          droite: true,
                          gras: true),
                      Padding(
                          padding: const EdgeInsets.all(4),
                          child: BoutonIcone(
                              icone: LucideIcons.x,
                              libelle: 'Retirer',
                              onPressed: () => setState(() {
                                    _lignes.removeAt(i);
                                    _proposerReglement();
                                  }))),
                    ]);
                  }(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _carteRecap() {
    final t = _lignes.isEmpty && _patientCourant == null ? null : _totaux();
    final brut = t?.brut ?? 0, remises = t?.remises ?? 0;
    final lignes = <(String, String)>[
      ('Total brut des prestations', money(brut)),
      if (remises > 0) ('Remises accordées', '− ${money(remises)}'),
      ('Total facturé', money(t?.total ?? 0)),
      if ((t?.partAssureur ?? 0) > 0)
        ('Part assureur', '− ${money(t!.partAssureur)}'),
      ('Part à la charge du patient', money(t?.partPatient ?? 0)),
    ];
    final partPatient = t?.partPatient ?? 0;
    final ass = t?.partAssureur ?? 0;
    return CarteSigh(
      titre: 'Récapitulatif',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final (i, x) in lignes.indexed)
          Container(
            margin: EdgeInsets.only(top: i == lignes.length - 1 ? 4 : 0),
            padding: EdgeInsets.only(
                top: i == lignes.length - 1 ? 10 : 6, bottom: 6),
            decoration: i == lignes.length - 1
                ? const BoxDecoration(
                    border: Border(top: BorderSide(color: JetonsShell.slate200)))
                : null,
            child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(x.$1,
                      style: TextStyle(
                          color: i == lignes.length - 1
                              ? JetonsShell.slate800
                              : JetonsShell.slate500,
                          fontSize: i == lignes.length - 1 ? 14 : 12,
                          fontWeight: i == lignes.length - 1
                              ? FontWeight.w600
                              : FontWeight.w400)),
                  Text(x.$2,
                      style: TextStyle(
                          color: i == lignes.length - 1
                              ? JetonsShell.navy900
                              : JetonsShell.slate700,
                          fontSize: i == lignes.length - 1 ? 16 : 14,
                          fontWeight: i == lignes.length - 1
                              ? FontWeight.w700
                              : FontWeight.w400)),
                ]),
          ),
        const SizedBox(height: 12),
        // Point fiscal du dossier : la MECeF ne porte que la part réglée par le patient. Ni la part assureur ni les remises n'y entrent.
        NoteSigh(
            'Base MECeF : ${money(partPatient)} — seule la part réglée par le patient est normalisée.${ass > 0 ? ' La part assureur (${money(ass)}) ' : ''}${ass > 0 && remises > 0 ? 'et les remises (${money(remises)}) en sont exclues.' : (remises > 0 ? ' Les remises (${money(remises)}) en sont exclues.' : (ass > 0 ? 'en est exclue.' : ''))}',
            icone: LucideIcons.landmark),
        const SizedBox(height: 12),
        FormulaireSigh(controleur: _reglement),
      ]),
    );
  }

  Widget _carteActions(ContexteEcran c) => CarteSigh(
        titre: 'Actions',
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          // Émettre une facture est une ÉCRITURE : le profil qui ne fait que lire la caisse voit l'écran sans se voir offrir de l'alimenter.
          if (c.droit.editer) ...[
            BoutonSigh(
                libelle: 'Enregistrer et encaisser',
                icone: LucideIcons.check,
                onPressed: () => _enregistrer(false)),
            BoutonSigh(
                libelle: 'Facture pro-forma',
                icone: LucideIcons.fileText,
                variante: VarianteBouton.secondaire,
                onPressed: () => _enregistrer(true)),
          ],
          BoutonSigh(
              libelle: 'Ticket de caisse',
              icone: LucideIcons.receipt,
              variante: VarianteBouton.secondaire,
              onPressed: _apercuTicket),
        ]),
      );

  Widget _carteRappels() => const CarteSigh(
        titre: 'Rappels',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          NoteSigh('RG-02 — médicaments au prix d’achat, sans marge.'),
          SizedBox(height: 8),
          NoteSigh('RG-09 — prise en charge uniquement si la carte est valide.',
              ton: TonSigh.attention, icone: LucideIcons.shieldAlert),
          SizedBox(height: 8),
          NoteSigh(
              'La sortie de stock des médicaments facturés est automatique (module M6).',
              icone: LucideIcons.package),
        ]),
      );
}
