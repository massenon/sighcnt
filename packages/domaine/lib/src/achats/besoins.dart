/// BONS D'EXPRESSION DE BESOINS (m7-besoins) — port des règles de `prototype_html/assets/js/modules/m7-achats.js`.
///
/// Quatre vues sur UNE collection (mes demandes, arbitrage de la DAF, besoins validés pour l'achat, tous les bons) ; une arbitrage à trois réponses dont
/// deux EXIGENT leur motif ; une validation qui informe DEUX postes (le comptable, le gestionnaire de stock) par une notification de poste ;
/// `rejete`, `complement` et `distribue` sont des ISSUES, pas des étapes ; la quantité accordée n'est pas la quantité demandée.
///
/// Rejoué sur `test/vecteurs/achats-besoins.json`, engendré en pilotant l'écran réel dans Chrome (`prototype_html/build/vecteurs-achats.js`).
///
/// Écarts de la maquette (voir `docs/architecture/ECARTS-MAQUETTE.md`, E70–E77) :
///   · E70 ✅ la référence venait d'un compteur de page : elle se lit désormais sur les bons existants ;
///   · E71 ✅ un bon saisi par un agent qui ne pilote pas le circuit était enregistré SANS étape (aucune vue ne le montrait) : il part SOUMIS ;
///   · E74 ✅ modifier un bon déjà validé écrasait le validateur ; E75 ✅ modifier un bon le RENUMÉROTAIT ;
///   · E73 porté fidèlement : qui pilote le circuit peut poser l'étape « Validation DA » ou « Quantité accordée » à la saisie, et la DAF est alors portée
///     validatrice sans avoir arbitré ;
///   · E77 porté fidèlement : « DAF » = 'TAKI Alimatou', écrit en dur (validateur, signatures) quel que soit l'agent connecté.
library;

import '../format/format_fr.dart';
import 'nombres.dart';

/// Un refus NOMMÉ : le motif est le texte affiché à l'agent, rien n'a été écrit.
class RefusAchat implements Exception {
  const RefusAchat(this.motif);
  final String motif;
  @override
  String toString() => motif;
}

/// L'agent qui valide pour la Directrice Administrative dans la maquette (E77 : écrit en dur).
const directriceAdministrative = 'TAKI Alimatou';

class EtatBesoin {
  const EtatBesoin(this.id, this.libelle, this.ton);
  final String id;
  final String libelle;

  /// Ton de la maquette (`neutral`, `info`, `warning`, `navy`, `success`, `danger`).
  final String ton;
}

/// Le chemin : brouillon → soumis → contrôle stock → validation DA → accordé → préparation → livré → clôturé.
const etapesBesoin = [
  EtatBesoin('brouillon', 'Brouillon', 'neutral'),
  EtatBesoin('soumis', 'Soumis', 'info'),
  EtatBesoin('controle_stock', 'Contrôle stock', 'info'),
  EtatBesoin('validation_da', 'Validation DA', 'warning'),
  EtatBesoin('accorde', 'Quantité accordée', 'navy'),
  EtatBesoin('prepare', 'Préparation', 'navy'),
  EtatBesoin('livre', 'Livré', 'success'),
  EtatBesoin('cloture', 'Clôturé', 'neutral'),
];

/// Les issues : elles sortent du circuit, le ruban ne les affiche pas. Un bon rejeté n'est PAS archivé (le service lit le motif).
const issuesBesoin = [
  EtatBesoin('rejete', 'Rejeté', 'danger'),
  EtatBesoin('complement', 'Complément demandé', 'warning'),
  EtatBesoin('distribue', 'Distribué au service', 'success'),
];

EtatBesoin etatBesoin(Object? id) => [...etapesBesoin, ...issuesBesoin]
    .firstWhere((e) => e.id == id,
        orElse: () => EtatBesoin('$id', '$id', 'neutral'));

const servicesDemandeurs = [
  'Pharmacie d’urgence',
  'Laboratoire',
  'Hospitalisation',
  'Maternité',
  'Bloc opératoire',
  'Accueil',
  'Administration',
  'Entretien',
];

/// Les familles nommées par la Direction ; un besoin qui n'entre dans aucune se dit « Autre » et se décrit.
const categoriesBesoin = [
  'Produits d’entretien (nettoyage, désinfection)',
  'Produits administratifs (stylos, cahiers, classeurs, cartouches, papier RAM)',
  'Matériel technique léger',
  'Consommables médicaux',
  'Autre — à préciser',
];

/// Qui arbitre (valider, rejeter, demander un complément).
const rolesArbitres = {'da', 'direction', 'admin'};

/// Qui voit les besoins validés et le registre complet (achat et logistique).
const rolesAchat = {
  'comptable',
  'stock',
  'da',
  'direction',
  'admin',
  'aide_comptable'
};

bool estArbitre(String role) => rolesArbitres.contains(role);
bool estAchat(String role) => rolesAchat.contains(role);

/// Le formulaire s'adapte à qui l'ouvre : seul celui qui tient le circuit (droit d'écrire ET poste d'achat) choisit l'étape. Un agent qui exprime un
/// besoin ne se place pas lui-même en « validation DA ».
bool pilotageCircuit({required String role, required bool droitEditer}) =>
    droitEditer && estAchat(role);

/// L'étape proposée à l'ouverture du formulaire de création.
String etapeParDefaut({required bool pilote}) => pilote ? 'brouillon' : 'soumis';

// ---------------------------------------------------------------------------------------------------------------------------------------
// LES QUATRE VUES D'UNE COLLECTION — des filtres, jamais des collections.
// ---------------------------------------------------------------------------------------------------------------------------------------

typedef _Bon = Map<String, Object?>;

/// « Mes demandes » : ce que CE poste a exprimé (le bon porte le demandeur par son nom).
List<_Bon> bonsMiens(Iterable<_Bon> actifs, String moi) =>
    [for (final b in actifs) if (b['demandeur'] == moi) b];

/// À arbitrer : soumis, au contrôle du stock, ou en validation DA.
List<_Bon> bonsAArbitrer(Iterable<_Bon> actifs) => [
      for (final b in actifs)
        if (const ['soumis', 'controle_stock', 'validation_da']
            .contains(b['etape']))
          b
    ];

/// Besoins validés pour l'achat : accordés, en préparation ou livrés.
List<_Bon> bonsPourAchat(Iterable<_Bon> actifs) => [
      for (final b in actifs)
        if (const ['accorde', 'prepare', 'livre'].contains(b['etape'])) b
    ];

int bonsLivres(Iterable<_Bon> actifs) =>
    actifs.where((b) => const ['livre', 'cloture'].contains(b['etape'])).length;

/// Les onglets offerts à un profil, dans l'ordre : chaque vue est gardée par CE QU'ELLE PERMET, non par un module.
/// `droitVoir` : le droit de lecture du profil sur l'écran.
List<String> vuesOffertes({required String role, required bool droitVoir}) => [
      'miennes',
      if (estArbitre(role)) 'arbitrage',
      if (estAchat(role)) 'achats',
      if (droitVoir && estAchat(role)) 'tous',
    ];

/// Étapes du ruban du circuit avec leur compte.
List<(EtatBesoin, int)> compteCircuit(Iterable<_Bon> actifs) => [
      for (final e in etapesBesoin)
        (e, actifs.where((b) => b['etape'] == e.id).length)
    ];

num _n(Object? v) => nombreEntier(v);

List<_Bon> _lignes(_Bon b) => [
      for (final l in (b['lignes'] as List? ?? const []))
        (l as Map).cast<String, Object?>()
    ];

/// Somme des quantités demandées.
num quantiteDemandeeTotale(_Bon b) =>
    _lignes(b).fold<num>(0, (a, l) => a + _n(l['quantiteDemandee']));

/// Somme des quantités ACCORDÉES, comptée sur les seules lignes déjà accordées (une ligne non arbitrée ne vaut pas zéro).
num quantiteAccordeeTotale(_Bon b) => _lignes(b)
    .where((l) => l['quantiteAccordee'] != null)
    .fold<num>(0, (a, l) => a + _n(l['quantiteAccordee']));

/// Total estimé d'un jeu de lignes : quantité demandée × prix d'achat.
num montantEstimeLignes(Iterable<_Bon> lignes) => lignes.fold<num>(
    0, (a, l) => a + _n(l['quantiteDemandee']) * _n(l['prixAchat']));

/// La ligne d'un bon : un article du référentiel, une quantité demandée, une quantité accordée facultative.
/// Refus nommés : article ou quantité manquants ; accordée supérieure à la demandée.
_Bon nouvelleLigneBesoin(
    {required _Bon? produit, required Object? demandee, Object? accordee}) {
  final d = _n(demandee);
  if (produit == null || d <= 0) {
    throw const RefusAchat('Sélectionner un article et une quantité.');
  }
  final vide = accordee == null || '$accordee'.isEmpty;
  final a = vide ? null : _n(accordee);
  if (a != null && a > d) {
    throw const RefusAchat(
        'La quantité accordée ne peut excéder la quantité demandée.');
  }
  return {
    'produitId': produit['id'],
    'produit': produit['designation'],
    'unite': produit['unite'],
    'quantiteDemandee': d,
    'quantiteAccordee': a,
    'quantiteLivree': null,
    'prixAchat': produit['prixAchat'],
  };
}

/// Le plus grand rang déjà écrit pour ce préfixe, plus un, lu sur les fiches EXISTANTES (archivées comprises : un numéro ne se réutilise pas).
/// Équivalent de `C.referenceSuivante` (E70/E8).
String referenceAchatSuivante(
    String prefixe, int largeur, Iterable<Map<String, Object?>> fiches) {
  var max = 0;
  for (final f in fiches) {
    final r = '${f['reference'] ?? ''}';
    if (r.startsWith(prefixe)) {
      final k = _entierJs(r.substring(prefixe.length));
      if (k > max) max = k;
    }
  }
  return '$prefixe${(max + 1).toString().padLeft(largeur, '0')}';
}

/// `parseInt(s, 10) || 0` : les chiffres de tête, sinon 0.
int _entierJs(String s) {
  final m = RegExp(r'^\s*[+-]?\d+').firstMatch(s);
  return m == null ? 0 : (int.tryParse(m.group(0)!.trim()) ?? 0);
}

/// Enregistre un bon (création ou modification) : ce que la modale de la maquette écrit.
/// [saisie] = valeurs du formulaire ; [existant] = le bon modifié (`null` en création) ; [bons] = TOUS les bons (archivés compris, pour la série).
/// Renvoie la fiche à insérer (création) ou le correctif à appliquer (modification).
_Bon bonEnregistre(
    {required _Bon saisie,
    required List<_Bon> lignes,
    _Bon? existant,
    required Iterable<_Bon> bons}) {
  if (lignes.isEmpty) throw const RefusAchat('Ajouter au moins un article.');
  final v = {...saisie};
  v['lignes'] = lignes;
  // E71 : le champ « étape » n'est pas offert à qui ne pilote pas le circuit — le bon part SOUMIS.
  if (existant == null && (v['etape'] == null || v['etape'] == '')) {
    v['etape'] = 'soumis';
  }
  v['montantEstime'] = montantEstimeLignes(lignes);
  // E75 : la référence est posée à la création, jamais à la modification.
  if (existant == null) {
    v['reference'] = referenceAchatSuivante('BEB-2026-', 4, bons);
  }
  // E74 : un validateur déjà connu n'est jamais écrasé. E73/E77 : sinon la DAF est portée validatrice.
  const validantes = ['validation_da', 'accorde', 'prepare', 'livre', 'cloture'];
  final validateur = v['valideePar'];
  if (validantes.contains(v['etape']) &&
      (validateur == null || validateur == '') &&
      !(existant != null && existant['valideePar'] != null && existant['valideePar'] != '')) {
    v['valideePar'] = directriceAdministrative;
  }
  return v;
}

// ---------------------------------------------------------------------------------------------------------------------------------------
// L'ARBITRAGE DE LA DAF
// ---------------------------------------------------------------------------------------------------------------------------------------

enum Arbitrage { valider, rejeter, complement }

class ArbitrageEnregistre {
  const ArbitrageEnregistre(
      {required this.patch,
      required this.notifications,
      required this.message,
      required this.type});

  /// Ce qu'il faut écrire sur le bon.
  final _Bon patch;

  /// Les notifications de poste à insérer (vide sauf validation) : le comptable ET le gestionnaire de stock.
  final List<_Bon> notifications;

  /// Le message affiché à l'agent, et son ton (`success` | `warning`).
  final String message;
  final String type;
}

/// Trois réponses ; rejeter et demander un complément EXIGENT leur motif (un refus sans motif se représente à l'identique).
/// [maintenant] : instant du geste (ISO 8601) ; [utilisateur] : l'agent qui arbitre.
ArbitrageEnregistre arbitrerBon(
    {required _Bon bon,
    required Arbitrage quoi,
    String motif = '',
    required String utilisateur,
    required String maintenant}) {
  final m = motif.trim();
  if (quoi != Arbitrage.valider && m.isEmpty) {
    throw const RefusAchat('Le motif est obligatoire.');
  }
  final etape = switch (quoi) {
    Arbitrage.valider => 'accorde',
    Arbitrage.rejeter => 'rejete',
    Arbitrage.complement => 'complement',
  };
  final patch = <String, Object?>{
    'etape': etape,
    'arbitreLe': maintenant,
    'arbitrePar': utilisateur,
    'motifArbitrage': m.isEmpty ? null : m,
    'valideePar': quoi == Arbitrage.valider ? utilisateur : null,
  };
  final ref = '${bon['reference']}';
  if (quoi != Arbitrage.valider) {
    return ArbitrageEnregistre(
        patch: patch,
        notifications: const [],
        message: 'Besoin $ref — ${etatBesoin(etape).libelle.toLowerCase()}.',
        type: 'warning');
  }
  final detail =
      '${bon['service']} — ${nombre(_lignes(bon).length)} article(s), ${money(bon['montantEstime'], avecDevise: false)}${m.isEmpty ? '' : ' · $m'}';
  return ArbitrageEnregistre(
      patch: patch,
      notifications: [
        for (final poste in const ['comptable', 'stock'])
          {
            'type': 'besoin_accorde',
            'poste': poste,
            'libelle': 'Besoin accordé — $ref',
            'detail':
                '$detail${poste == 'comptable' ? ' · engagement budgétaire et décaissement à préparer' : ' · achat à lancer ou distribution à planifier'}',
            'reference': ref,
            'priorite': 'important',
          }
      ],
      message:
          'Besoin $ref accordé — le comptable et le gestionnaire de stock sont informés.',
      type: 'success');
}

/// Le besoin accordé passe en PRÉPARATION (puis l'écran des commandes : RG-04 veut la validation de la DAF sur la commande elle-même).
_Bon versCommandeBesoin(
        {required String utilisateur, required String maintenant}) =>
    {'etape': 'prepare', 'prepareLe': maintenant, 'preparePar': utilisateur};

/// Le message affiché après une distribution.
String messageDistribution(Map<String, Object?> bon) =>
    'Besoin ${bon['reference']} distribué à ${bon['service']}.';

/// Le service a reçu les articles : le bon sort du circuit d'achat.
_Bon distribuerBesoin(
        {required String utilisateur, required String maintenant}) =>
    {'etape': 'distribue', 'distribueLe': maintenant, 'distribuePar': utilisateur};
