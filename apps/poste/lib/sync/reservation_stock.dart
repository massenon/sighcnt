import '../donnees/magasin.dart';
import 'fusion_activite.dart';

/// LA PART DE STOCK DE CHAQUE POSTE QUAND IL N'EST PLUS JOINT (RG-03 ; limite levée le 03/11/2026).
///
/// Les sorties de stock de deux postes se retranchent toutes les deux (variations additionnées), mais deux postes qui sortent le DERNIER exemplaire sans se voir
/// donnent un stock négatif. Tant qu'un poste est en LIAISON (dernier tour de synchronisation réussi il y a moins de [fraicheur]), il voit les sorties des autres
/// et la règle ordinaire (jamais de stock négatif) suffit. Dès qu'il est HORS LIGNE (mère arrêtée, câble débranché, coupure), il ne peut plus sortir que SA
/// PART : le stock connu à la dernière synchronisation, divisé par le nombre de postes de la clinique. La somme des parts ne dépasse jamais le stock : même si
/// tous les postes sortent hors ligne en même temps, aucun stock ne devient négatif.
///
/// Ce que cette règle ne couvre pas, et qui reste dit : la fenêtre de quelques secondes entre deux tours de synchronisation de deux postes EN LIAISON (la
/// détection `stockNegatifDetecte` du pont la voit), et le cas d'un poste qui sort plus que sa part parce que le refus le gêne : il demande alors un transfert
/// ou attend la reconnexion, le refus le dit.
///
/// Le refus est posé comme une GARDE sur les collections de compteurs : il vaut pour tous les gestes qui sortent du stock (dispensation, transfert, perte,
/// inventaire), présents et futurs, sans qu'aucun écran ne le recopie.
class ReservationStock {
  ReservationStock._();
  static final Expando<ReservationStock> _par = Expando<ReservationStock>();
  static ReservationStock de(Magasin m) => _par[m] ??= ReservationStock._();

  /// Posé par `main` quand le poste est rattaché ou mère. Faux : aucune restriction (poste autonome).
  bool actif = false;

  /// L'horloge (injectable pour les tests).
  DateTime Function() maintenant = DateTime.now;

  /// Au-delà de ce délai sans tour réussi, le poste est considéré hors ligne.
  Duration fraicheur = const Duration(seconds: 12);

  /// Le nombre de postes de la clinique (celui-ci compris), déduit des battements publiés au journal. Un seul poste : aucune part à partager.
  int nbPostes = 1;

  DateTime? derniereSynchro;
  final Map<String, num> _instantane = {};
  bool _installe = false;

  bool get horsLigne => actif && (derniereSynchro == null || maintenant().difference(derniereSynchro!) > fraicheur);

  /// Appelé par le pont après un tour RÉUSSI : le stock que le poste connaît à cet instant sert de base aux sorties hors ligne qui suivront.
  void synchronise(Magasin m, Iterable<String> collections, {int? postes}) {
    derniereSynchro = maintenant();
    if (postes != null && postes > 0) nbPostes = postes;
    _instantane.clear();
    for (final e in champsCompteurs.entries) {
      if (!collections.contains(e.key)) continue;
      for (final f in m.collection(e.key).toutes) {
        for (final k in e.value) {
          if (f[k] is num) _instantane['${e.key}/${f['id']}/$k'] = f[k] as num;
        }
      }
    }
  }

  /// Pose la garde sur les collections de compteurs (une seule fois par magasin).
  void installer(Magasin m) {
    if (_installe) return;
    _installe = true;
    for (final e in champsCompteurs.entries) {
      if (e.key == 'factures') continue; // un règlement n'est pas une sortie de stock
      final col = m.collection(e.key);
      col.garder((op, f) => op == 'modifier' ? _controler(e.key, col, f, e.value) : null);
    }
  }

  static num _n(Object? v) => v is num ? v : (num.tryParse('${v ?? ''}') ?? 0);

  String? _controler(String collection, CollectionMagasin col, Fiche apres, Set<String> champs) {
    if (!horsLigne) return null;
    final avant = col.parId(apres['id']);
    if (avant == null) return null;
    for (final k in champs) {
      if (!apres.containsKey(k)) continue;
      final d = _n(avant[k]) - _n(apres[k]);
      if (d <= 0) continue;
      final cle = '$collection/${apres['id']}/$k';
      final base = _instantane[cle] ?? _n(avant[k]);
      final deja = base - _n(avant[k]);
      final part = (base / (nbPostes < 1 ? 1 : nbPostes)).floor();
      if ((deja > 0 ? deja : 0) + d > part) {
        final nom = '${apres['designation'] ?? apres['produit'] ?? apres['id']}';
        final heure = derniereSynchro == null
            ? 'jamais'
            : '${derniereSynchro!.hour.toString().padLeft(2, '0')}:${derniereSynchro!.minute.toString().padLeft(2, '0')}';
        return 'Poste hors ligne (dernière synchronisation : $heure) : la part de ce poste sur « $nom » est de $part unité(s) '
            '(stock connu ${base.toInt()}, $nbPostes postes), ${deja > 0 ? deja.toInt() : 0} déjà sortie(s) : une sortie de $d risquerait de rendre le stock négatif '
            'quand les autres postes se reconnectent (RG-03). Reconnectez le poste, ou demandez un transfert à un poste en liaison.';
      }
    }
    return null;
  }
}
