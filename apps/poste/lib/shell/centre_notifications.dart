import 'package:flutter/foundation.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../core/donnees_navigation.dart';
import '../donnees/magasin.dart';
import 'recherche_globale.dart' show ecranOuvertAuRole;

/// Le MOTEUR DE NOTIFICATIONS du poste (`SIGH.notifications` de la maquette, `notifications.js`). Il AFFICHE, il ne DÉCIDE pas : chaque source lit ce que
/// les modules ont déjà déterminé (un article sous son seuil, un lot périmé, une échéance dépassée, une facture rejetée, un bon à valider), le moteur
/// ROUTE par poste et par droits, REGROUPE au-delà de trois alertes de même nature et PRIORISE. Le jour où un seuil change dans le module, ce fichier
/// n'a rien à changer.
///
/// Trois règles tenues ici :
///  - une alerte ne mène jamais à un écran interdit au profil (RG-13) : la matrice en force (droits à chaud et activités fermées comprises) filtre ;
///  - ENTENDRE N'EST PAS TRAITER : une alerte acquittée sort du badge mais RESTE au centre tant que sa cause dure ;
///  - JAMAIS de donnée médicale dans le message d'une alerte : le détail vit derrière les permissions de l'écran visé.
class AlerteNotif {
  const AlerteNotif({
    required this.cle,
    required this.source,
    required this.categorie,
    required this.domaine,
    required this.priorite,
    required this.titre,
    required this.detail,
    this.lien,
    this.postes,
    this.acquitteeLe,
    this.groupe = false,
    this.membres = const [],
    this.nombre = 1,
  });
  final String cle, source, categorie, domaine, priorite, titre, detail;
  final String? lien;
  final List<String>? postes;
  final String? acquitteeLe;
  final bool groupe;
  final List<String> membres;
  final int nombre;
  bool get acquittee => acquitteeLe != null;

  AlerteNotif avecAcquittement(String? quand) => AlerteNotif(
      cle: cle,
      source: source,
      categorie: categorie,
      domaine: domaine,
      priorite: priorite,
      titre: titre,
      detail: detail,
      lien: lien,
      postes: postes,
      acquitteeLe: quand,
      groupe: groupe,
      membres: membres,
      nombre: nombre);
}

/// Rang d'une priorité : le plus grave d'abord, c'est l'ordre dans lequel on veut les lire.
int rangPriorite(String p) => switch (p) { 'critique' => 0, 'important' => 1, _ => 2 };

/// Libellé d'une priorité (`PRIORITES[x].label`).
String libellePriorite(String p) => switch (p) { 'critique' => 'Critique', 'important' => 'Important', _ => 'Information' };

/// Au-delà de trois alertes de même nature et de même priorité, c'est le NOMBRE qui informe : en dessous, nommer l'article rend service.
const seuilRegroupement = 3;

/// Quels rôles tiennent un POSTE de notification (`POSTES_NOTIF`). `null` = tout le monde (« tous » ou poste non précisé) ; un poste inconnu est lu comme un rôle.
const _postesNotif = <String, List<String>?>{
  'tous': null,
  'caisse': ['caissier'],
  'comptable': ['comptable', 'assistant_comptable', 'aide_comptable', 'da'],
  'direction': ['direction', 'da', 'dm'],
  'imagerie': ['echographiste'],
  'laboratoire': ['laborantin'],
  'prescripteur': ['medecin', 'chirurgien', 'anesthesiste', 'dm'],
  'stock': ['stock', 'pharmacien', 'da'],
  'salle_soins': ['infirmier', 'aide_soignant', 'surveillant'],
  'hospitalisation': ['infirmier', 'aide_soignant', 'surveillant', 'medecin'],
};

List<String>? _rolesDuPoste(Object? poste) {
  if (!_v(poste) || poste == 'tous') return null;
  final p = '$poste';
  return _postesNotif.containsKey(p) ? _postesNotif[p] : [p];
}

/// L'écran où se traite chaque type de notification de poste (`LIENS_NOTIF`).
const _liensNotif = <String, String>{
  'demande_imagerie': 'm2-imagerie-demandes',
  'prescription_soins': 'm2-salle-soins',
  'resultat_disponible': 'm5-resultats',
  'resultat_rectifie': 'm5-resultats',
  'cloture': 'm12-cloture',
};

/// `PR.notifier` écrit « haute » ou « normale » ; le moteur raisonne en critique, important, information.
String _prioriteDePoste(Fiche n) {
  final p = n['priorite'];
  if (p == 'critique' || p == 'important' || p == 'information') return '$p';
  if (p == 'haute' || n['ton'] == 'danger') return 'critique';
  return 'information';
}

/// Libellés des lignes groupées : [intitulé après le nombre, détail].
const _libellesGroupe = <String, (String, String)>{
  'stock_seuil': ('article(s) sous leur seuil d’alerte', 'Établir un bon de commande, validation de la Direction requise (RG-04).'),
  'lots_peremption': ('lot(s) périmés ou proches de la péremption', 'Appliquer le principe FEFO (RG-05) et déclarer les pertes constatées.'),
  'mecef_rejet': ('facture(s) rejetée(s) par la MECeF', 'Corriger puis réémettre auprès de l’administration fiscale.'),
  'echeance_fiscale': ('échéance(s) fiscale(s) dépassée(s)', 'Une pénalité court sur chacune. Déclarer et payer.'),
  'creance_agee': ('créance(s) assureur en souffrance', 'Relancer chaque compagnie : ces créances pèsent sur le besoin en fonds de roulement.'),
  'labo_a_traiter': ('analyse(s) réglée(s), prélèvement à faire', 'Les patients ont payé : ils peuvent être appelés en salle de prélèvement.'),
  'labo_a_saisir': ('échantillon(s) reçu(s), résultat à saisir', 'Le prescripteur ne verra rien tant que le résultat n’est pas validé.'),
  'a_valider_besoins': ('bon(s) de besoins à valider', 'Arbitrer chaque bon : validé, complément demandé ou rejeté avec son motif.'),
  'a_valider_ecritures': ('pièce(s) comptable(s) en brouillon', 'Contrôler l’équilibre (RG-10) puis valider.'),
  'pair_conflits': ('champ(s) modifié(s) en même temps sur deux postes', 'Deux valeurs coexistent, la plus récente est retenue provisoirement : la personne habilitée tranche.'),
  'poste': ('notification(s) de poste', 'À consulter dans les écrans concernés.'),
};

bool _v(Object? x) => !(x == null || x == false || x == '' || (x is num && x == 0));
String _ou(Object? a, Object? b) => _v(a) ? '$a' : '$b';
num? _num(Object? x) => x is num ? x : (x is String ? num.tryParse(x) : null);
String _entier(num x) => x == x.roundToDouble() ? '${x.toInt()}' : '$x';

class _Ligne {
  const _Ligne(this.cle, this.priorite, this.titre, this.detail, this.lien, this.postes);
  final String cle, priorite, titre, detail;
  final String? lien;
  final List<String>? postes;
}

class _Source {
  const _Source(this.code, this.categorie, this.domaine, this.lire);
  final String code, categorie, domaine;
  final List<_Ligne> Function(Magasin m, DateTime auj) lire;
}

final List<_Source> _sources = [
  _Source('stock_seuil', 'metier', 'Stock', (m, auj) => [
        for (final p in m.collection('produits').actives)
          if (p['seuilAlerte'] != null && (_num(p['stock']) ?? 0) <= (_num(p['seuilAlerte']) ?? 0))
            _Ligne(
                'stock:${p['id']}',
                (_num(p['stock']) ?? 0) <= 0 ? 'critique' : 'important',
                '${p['designation']} : ${nombre(p['stock'])} en stock',
                'Seuil d’alerte fixé à ${nombre(p['seuilAlerte'])}. Établir un bon de commande, validation de la Direction requise (RG-04).',
                'm6-alertes',
                const ['stock', 'pharmacien', 'caissier', 'da']),
      ]),
  _Source('lots_peremption', 'metier', 'Pharmacie', (m, auj) => [
        for (final l in m.collection('lots').actives)
          if (l['statut'] == 'perime' || l['statut'] == 'alerte')
            _Ligne(
                'lot:${l['id']}',
                l['statut'] == 'perime' ? 'critique' : 'important',
                l['statut'] == 'perime' ? 'Lot périmé : ${_ou(l['produit'], l['numero'])}' : 'Péremption proche : ${_ou(l['produit'], l['numero'])}',
                l['statut'] == 'perime' ? 'À sortir du rayon et à déclarer en perte.' : 'Appliquer le principe FEFO (RG-05).',
                'm6-lots',
                const ['stock', 'pharmacien', 'caissier', 'laborantin']),
      ]),
  _Source('mecef_rejet', 'metier', 'Facturation', (m, auj) => [
        for (final f in m.collection('factures').actives)
          if (f['statutMecef'] == 'rejete')
            _Ligne('mecef:${f['id']}', 'important', 'Facture ${_ou(f['numero'], f['id'])} rejetée par la MECeF',
                'Corriger puis réémettre auprès de l’administration fiscale.', 'mecef-transmission', const ['caissier', 'comptable', 'da', 'assistant_comptable']),
      ]),
  _Source('echeance_fiscale', 'metier', 'Comptabilité', (m, auj) {
    // Le calendrier fiscal est un référentiel : le moteur ne recalcule aucune date, il lit ce qui est déjà dépassé.
    final j = iso(auj);
    return [
      for (final e in m.collection('echeancesFiscales').actives)
        if (!_v(e['paye']) && '${e['echeance']}'.compareTo(j) < 0)
          _Ligne('fisc:${e['id']}', 'critique', '${_ou(e['libelle'], e['obligation'])} : échéance dépassée',
              'Échéance au ${_dateFr(e['echeance'])}. Une pénalité court.', 'm12-echeances', const ['comptable', 'da', 'assistant_comptable', 'direction']),
    ];
  }),
  _Source('creance_agee', 'metier', 'Recouvrement', (m, auj) {
    // La source ROUTE, elle ne décide pas du seuil : il vit dans `objectifsPilotage`, où la Direction le règle.
    final alertes = cpcAlertesRecouvrement(factures: m.collection('factures').actives, objectifs: m.collection('objectifsPilotage').actives, auj: auj);
    return [
      for (final a in alertes)
        _Ligne(
            'creance:${a.assureur}',
            a.jours > a.seuil * 1.5 ? 'critique' : 'important',
            '${_nomAssureur(a.assureur)} : ${money(a.montant, avecDevise: false)} en souffrance',
            '${nombre(a.nb)} facture(s), jusqu’à ${a.jours} jours d’ancienneté (seuil retenu : ${_entier(a.seuil)} jours). Cette créance pèse sur le besoin en fonds de roulement.',
            'm9-relances',
            const ['da', 'comptable', 'direction', 'assistant_comptable', 'aide_comptable']),
    ];
  }),
  _Source('labo_a_traiter', 'metier', 'Laboratoire', (m, auj) => [
        for (final d in m.collection('demandesAnalyses').actives)
          if (d['etatAnalyse'] == 'attente_prelevement')
            _Ligne('labo-prel:${d['id']}', 'important', 'Analyse réglée, prélèvement à faire',
                '${_ou(d['analyse'], 'Analyse')} : le patient a payé, il peut être appelé.', 'm5-prelevement', const ['laborantin']),
      ]),
  _Source('labo_a_saisir', 'metier', 'Laboratoire', (m, auj) => [
        for (final d in m.collection('demandesAnalyses').actives)
          if (_v(d['recuLaboLe']) && d['etatAnalyse'] == 'en_cours')
            _Ligne('labo-saisie:${d['id']}', 'information', 'Échantillon reçu, résultat à saisir',
                '${_ou(d['analyse'], 'Analyse')} : reçu le ${_dateFr(d['recuLaboLe'])}.', 'm5-resultats', const ['laborantin']),
      ]),
  _Source('a_valider_besoins', 'metier', 'À valider', (m, auj) => [
        for (final b in m.collection('besoins').actives)
          if (b['etape'] == 'soumis' || b['etape'] == 'validation_da')
            _Ligne(
                'besoin:${b['id']}',
                'important',
                'Bon de besoins à valider${_v(b['reference']) ? ' : ${b['reference']}' : ''}',
                '${_ou(b['service'], 'Service')}${_v(b['motif']) ? ' : ${b['motif']}' : ''}. La validation est un geste de la DAF.',
                'm7-besoins',
                const ['da', 'direction']),
      ]),
  _Source('a_valider_ecritures', 'metier', 'À valider', (m, auj) {
    // Une PIÈCE comptable en brouillon (deux lignes de même numéro) compte pour une : le comptable valide des pièces, pas des lignes (RG-10).
    final vues = <String>{};
    final out = <_Ligne>[];
    for (final e in m.collection('ecritures').actives) {
      if (e['statut'] != 'brouillon') continue;
      final k = _ou(e['numero'], _ou(e['pieceNumero'], e['id']));
      if (!vues.add(k)) continue;
      out.add(_Ligne('ecr:$k', 'information', 'Pièce comptable en brouillon : $k', '${_ou(e['libelle'], 'Écriture')}. La validation comptable reste un geste humain.',
          'm12-ecritures', const ['comptable', 'da', 'aide_comptable']));
    }
    return out;
  }),
  // E2143 (arbitrage du 04/11/2026) : un doublon détecté par la synchronisation n'est JAMAIS corrigé en silence (RG-01, pièce émise intouchable) ; il est
  // signalé à ceux qui tranchent, avec le nom de l'objet et l'écran où il se traite.
  _Source('sync_a_arbitrer', 'metier', 'Synchronisation', (m, auj) {
    const postes = ['direction', 'da', 'comptable', 'admin'];
    List<_Ligne> par(String col, String marqueur, String prefixe, String titre, String detail, String lien, String Function(Map<String, Object?>) nom, [String priorite = 'important']) => [
          for (final f in m.collection(col).actives)
            if (f[marqueur] == true) _Ligne('$prefixe:${f['id']}', priorite, '$titre : ${nom(f)}', detail, lien, postes),
        ];
    String ou(Object? a, Object? b) => '${a ?? b ?? ''}';
    return [
      ...par('patients', 'codeEnDoublon', 'dbl-pat', 'Dossier en doublon', 'Deux dossiers portent le même code CNT. Le code n’est jamais renuméroté (RG-01) : la Direction décide du dossier à conserver ou à fusionner.', 'm1-patients', (f) => ou(f['code'], f['id'])),
      ...par('factures', 'numeroEnDoublon', 'dbl-fac', 'Facture au numéro en double', 'Une pièce émise ne se réécrit pas : régler par avoir et réémission, ou justifier par écrit.', 'm8-factures', (f) => ou(f['numero'], f['id'])),
      ...par('factures', 'encaissementEnDoublon', 'dbl-enc', 'Encaissement en double', 'La même ligne a été encaissée par deux guichets : vérifier la caisse et rembourser par avoir si besoin.', 'm8-factures', (f) => ou(f['numero'], f['id']), 'critique'),
      ...par('avoirs', 'numeroEnDoublon', 'dbl-avo', 'Avoir au numéro en double', 'Une pièce émise ne se réécrit pas : la Direction tranche.', 'm8-facture-avoir', (f) => ou(f['numero'], f['id'])),
      ...par('ecritures', 'numeroEnDoublon', 'dbl-ecr', 'Écriture au numéro en double', 'Une pièce comptable ne se renumérote pas : le comptable tranche.', 'm12-ecritures', (f) => ou(f['numero'], f['id'])),
      ...par('admissions', 'litEnConflit', 'dbl-lit', 'Lit en conflit', 'Deux admissions actives sur le même lit : transférer l’un des patients.', 'm3-admissions', (f) => ou(f['lit'], f['id']), 'critique'),
      ...par('produits', 'stockNegatifDetecte', 'dbl-stk', 'Stock négatif détecté', 'Deux postes ont sorti le dernier exemplaire hors ligne (RG-03) : régulariser par un inventaire.', 'm6-stock-detail', (f) => ou(f['designation'], f['id']), 'critique'),
    ];
  }),
  // ADR-0006 (D2) : un champ écrit en même temps par deux postes reste MARQUÉ jusqu'à ce que la personne habilitée tranche ; le moteur pair recopie ces
  // conflits dans la collection locale `conflitsPair` (jamais synchronisée) et ils s'annoncent à l'ouverture, avec le son, comme toute alerte importante.
  _Source('pair_conflits', 'metier', 'Échanges entre postes', (m, auj) => [
        for (final c in m.collection('conflitsPair').actives)
          _Ligne('pair:${c['collection']}:${c['fiche']}:${c['champ']}', 'important',
              'Conflit à trancher : ${_ou(c['libelle'], '${c['collection']} / ${c['champ']}')}',
              'Valeurs en présence : ${_ou(c['valeurs'], '')}. Le conflit reste marqué tant que la Direction ou la DAF ne tranche pas.',
              _v(c['ecran']) ? '${c['ecran']}' : 'pair-trancher', const ['direction', 'da', 'admin']),
      ]),
  _Source('poste', 'metier', 'Poste', (m, auj) => [
        // Notifications de POSTE, écrites par le moteur transactionnel : elles s'adressent à un poste, pas à une personne.
        for (final n in m.collection('notifications').actives)
          if (!_v(n['lue']))
            _Ligne(
                'notif:${n['id']}',
                _prioriteDePoste(n),
                _ou(n['titre'], _ou(n['libelle'], _ou(n['message'], 'Notification'))),
                _ou(n['detail'], _v(n['message']) ? n['message'] : ''),
                _v(n['ecran']) ? '${n['ecran']}' : _liensNotif['${n['type']}'],
                _rolesDuPoste(n['poste'])),
      ]),
];

String _dateFr(Object? v) {
  final d = DateTime.tryParse('$v');
  return d == null ? '$v' : dateFR(d);
}

String _nomAssureur(String code) {
  for (final a in patAssureurs) {
    if (a.$1 == code) return a.$2;
  }
  return code;
}

/// Le centre de notifications d'un POSTE : collecte, routage, regroupement, acquittement. Il se tient à jour tout seul : toute écriture dans une
/// collection qu'il lit le notifie, et la cloche suit.
class CentreNotifications extends ChangeNotifier {
  CentreNotifications({
    required this.magasin,
    required this.donnees,
    required this.role,
    DateTime Function()? horloge,
    this.audioDisponible,
  }) : _horloge = horloge ?? DateTime.now {
    _ecoute = Listenable.merge([for (final n in collectionsLues) magasin.collection(n)])..addListener(notifyListeners);
  }

  /// Les collections que les sources lisent : leur écriture fait repeindre la cloche.
  static const collectionsLues = [
    'produits',
    'lots',
    'factures',
    'echeancesFiscales',
    'objectifsPilotage',
    'demandesAnalyses',
    'besoins',
    'ecritures',
    'patients',
    'avoirs',
    'admissions',
    'notifications',
    'reglages',
  ];

  final Magasin magasin;

  /// Données de navigation EN FORCE (droits à chaud, activités fermées) : relues à chaque collecte.
  final DonneesNavigation Function() donnees;

  /// Le rôle connecté.
  final String Function() role;
  final DateTime Function() _horloge;

  /// Le canal sonore est-il disponible sur ce poste ? `null` : non vérifié, aucune notification système.
  final bool Function()? audioDisponible;
  late final Listenable _ecoute;

  static const _idAcquittees = 'notificationsAcquittees';

  Map<String, String> acquittees() {
    final f = magasin.collection('reglages').actives.where((x) => x['id'] == _idAcquittees).firstOrNull;
    final v = f?['valeur'];
    return v is Map ? {for (final e in v.entries) '${e.key}': '${e.value}'} : {};
  }

  void _ecrireAcquittees(Map<String, String> a) {
    final col = magasin.collection('reglages');
    final f = col.actives.where((x) => x['id'] == _idAcquittees).firstOrNull;
    if (f == null) {
      col.inserer({'id': _idAcquittees, 'statut': 'actif', 'valeur': a});
    } else {
      col.mettreAJour(_idAcquittees, {'valeur': a});
    }
  }

  /// Acquitter une ligne GROUPÉE acquitte ses membres : sinon le badge ne bougerait pas, et l'agent cliquerait sans effet visible.
  void acquitter(AlerteNotif n) {
    final a = acquittees();
    final quand = _horloge().toIso8601String();
    a[n.cle] = quand;
    for (final m in n.membres) {
      a[m] = quand;
    }
    _ecrireAcquittees(a);
  }

  void reprendre(AlerteNotif n) {
    final a = acquittees();
    a.remove(n.cle);
    for (final m in n.membres) {
      a.remove(m);
    }
    _ecrireAcquittees(a);
  }

  bool _pourMoi(_Ligne n, String r, DonneesNavigation nav) {
    if (n.postes != null && !n.postes!.contains(r)) return false;
    if (n.lien != null) {
      final e = nav.manifeste.ecran(n.lien!);
      if (e != null && !ecranOuvertAuRole(nav, r, e.id)) return false;
    }
    return true;
  }

  /// Ce que la cloche et le centre affichent : routé par poste et par droits, regroupé au-delà de trois, le plus grave d'abord.
  List<AlerteNotif> collecter({String? poste, bool detaille = false}) {
    final r = poste ?? role();
    final nav = donnees();
    final auj = _horloge();
    final acq = acquittees();
    final out = <AlerteNotif>[];
    for (final src in _sources) {
      List<_Ligne> lues;
      try {
        lues = src.lire(magasin, auj);
      } catch (_) {
        lues = const [];
      }
      for (final n in lues) {
        if (!_pourMoi(n, r, nav)) continue;
        // Le serveur et le poste calculent parfois la MÊME alerte (même clé) : celle du poste l'emporte, l'autre ne double pas la cloche.
        if (out.any((x) => x.cle == n.cle)) continue;
        out.add(AlerteNotif(
            cle: n.cle,
            source: src.code,
            categorie: src.categorie,
            domaine: src.domaine,
            priorite: n.priorite,
            titre: n.titre,
            detail: n.detail,
            lien: n.lien,
            postes: n.postes,
            acquitteeLe: acq[n.cle]));
      }
    }
    // Le canal sonore : une notification SYSTÈME, distincte du métier.
    if (audioDisponible != null && audioDisponible!() == false) {
      out.add(AlerteNotif(
          cle: 'sys:audio',
          source: 'audio',
          categorie: 'systeme',
          domaine: 'Périphérique audio',
          priorite: 'information',
          titre: 'Sonorisation indisponible sur ce poste',
          detail: 'Le périphérique audio n’a pas répondu. Les alertes restent visibles : cloche, badge et messages fonctionnent normalement.',
          lien: 'cfg-notifications',
          acquitteeLe: acq['sys:audio']));
    }
    final res = detaille ? out : _regrouper(out, acq);
    // Le plus grave d'abord, puis l'ordre alphabétique des titres ; l'ordre d'arrivée départage les égalités (tri STABLE, comme `Array.sort`).
    final lignes = [for (final (i, x) in res.indexed) (i, x)]..sort((x, y) {
        final c = rangPriorite(x.$2.priorite).compareTo(rangPriorite(y.$2.priorite));
        if (c != 0) return c;
        final t = comparerNaturel(x.$2.titre, y.$2.titre);
        return t != 0 ? t : x.$1.compareTo(y.$1);
      });
    return [for (final l in lignes) l.$2];
  }

  List<AlerteNotif> _regrouper(List<AlerteNotif> liste, Map<String, String> acq) {
    final paquets = <String, List<AlerteNotif>>{};
    for (final x in liste) {
      (paquets['${x.source}|${x.priorite}'] ??= []).add(x);
    }
    final out = <AlerteNotif>[];
    for (final e in paquets.entries) {
      final g = e.value;
      if (g.length < seuilRegroupement) {
        out.addAll(g);
        continue;
      }
      final lib = _libellesGroupe[g.first.source] ?? ('${g.first.domaine.toLowerCase()} : alertes', '');
      // Une alerte groupée est acquittée si TOUS ses membres le sont, OU si la ligne elle-même l'a été (geste délibéré sur ce que l'on voit).
      final cleGroupe = 'groupe:${e.key}';
      final toutes = g.every((x) => x.acquittee);
      final quand = acq[cleGroupe] ?? (toutes ? g.first.acquitteeLe : null);
      out.add(AlerteNotif(
          cle: cleGroupe,
          source: g.first.source,
          categorie: g.first.categorie,
          domaine: g.first.domaine,
          priorite: g.first.priorite,
          titre: '${nombre(g.length)} ${lib.$1}',
          detail: lib.$2,
          lien: g.first.lien,
          postes: g.first.postes,
          acquitteeLe: quand,
          groupe: true,
          membres: [for (final x in g) x.cle],
          nombre: g.length));
    }
    return out;
  }

  /// Ce qui pèse sur le badge : les non acquittées.
  List<AlerteNotif> enAttente([String? poste]) => [
        for (final n in collecter(poste: poste))
          if (!n.acquittee) n
      ];

  @override
  void dispose() {
    _ecoute.removeListener(notifyListeners);
    super.dispose();
  }
}
