import 'dart:async';

import 'package:sigh_domaine/sigh_domaine.dart';

import '../donnees/magasin.dart';

/// LES CODES DE DOSSIER NE SE CHEVAUCHENT JAMAIS ENTRE POSTES (RG-01 ; limite levée le 03/11/2026).
///
/// Chaque poste d'une clinique (la mère comme les fileuls) reçoit de la MÈRE des PLAGES de numéros : le poste ne tire un code que dans sa plage, hors ligne
/// comme en ligne, et deux postes ne peuvent donc plus attribuer le même numéro. La plage en cours vit au magasin (collection `plagesCodes`, locale au poste,
/// jamais synchronisée) : elle survit à un redémarrage. Quand il reste peu de numéros, le poste en redemande une, en tâche de fond.
///
/// Un poste SANS plage (autonome, mère pas encore activée) garde la règle historique (plus grand rang + 1) : rien ne change pour lui. Un poste rattaché dont la
/// plage est ÉPUISÉE hors ligne n'invente pas de numéro : il attribue un code PROVISOIRE (`PROV-…`), que la mère remplace à la première synchronisation.
class PlagesCodes {
  PlagesCodes._(this.magasin);
  final Magasin magasin;
  static final Expando<PlagesCodes> _par = Expando<PlagesCodes>();

  /// Le service du magasin donné (créé à la première demande).
  static PlagesCodes de(Magasin m) => _par[m] ??= PlagesCodes._(m);

  /// Demande une plage à la mère : `(taille, minimum) -> (début, fin)`. Posée par `main` quand le poste est rattaché ou mère ; absente sinon.
  Future<(int, int)> Function(int taille, int minimum)? obtenir;

  /// Combien de numéros il faut avoir devant soi avant d'en redemander.
  static const int seuilRecharge = 10;
  static const int taillePlage = 50;
  static const String collection = 'plagesCodes';

  bool _enCours = false;

  bool get actif => obtenir != null;

  /// Les plages détenues par ce poste, la plus ancienne d'abord.
  List<Fiche> get plages => [
        for (final f in magasin.collection(collection).toutes)
          if (f['statut'] != 'archive') f
      ]..sort((a, b) => (a['debut'] as num).compareTo(b['debut'] as num));

  /// Le numéro restant dans les plages détenues.
  int get restants => plages.fold(0, (n, f) => n + ((f['fin'] as num).toInt() - (f['prochain'] as num).toInt() + 1).clamp(0, 1 << 30));

  int _plusGrandRang(Iterable<Fiche> patients, int annee) {
    final suffixe = '$annee'.substring('$annee'.length - 2);
    final re = RegExp(r'^CNT/?(\d+)/(\d{2})$');
    var max = 0;
    for (final p in patients) {
      final m = re.firstMatch('${p['code'] ?? ''}');
      if (m != null && m.group(2) == suffixe) {
        final n = int.parse(m.group(1)!);
        if (n > max) max = n;
      }
    }
    return max;
  }

  /// Demande une plage si le stock de numéros est bas. Sans effet hors ligne : l'échec est silencieux ICI (la plage restante sert) et se redit au tirage
  /// suivant ; le seul cas qui se voit est l'épuisement, qui donne un code provisoire.
  Future<void> recharger({DateTime? maintenant}) async {
    final demander = obtenir;
    if (demander == null || _enCours || restants > seuilRecharge) return;
    _enCours = true;
    try {
      final annee = (maintenant ?? DateTime.now()).year;
      final minimum = _plusGrandRang(magasin.collection('patients').toutes, annee) + 1;
      final (debut, fin) = await demander(taillePlage, minimum);
      magasin.collection(collection).ajouterSansJournal({'id': 'PLG$debut', 'debut': debut, 'fin': fin, 'prochain': debut, 'annee': annee});
    } catch (_) {
      // Hors ligne ou mère arrêtée : on garde ce qu'on a.
    } finally {
      _enCours = false;
    }
  }

  /// Le prochain code de dossier. Plage détenue : le numéro suivant de la plage. Plage épuisée : un code PROVISOIRE. Aucun service de plage : la règle historique.
  String prochainCode(Iterable<Fiche> patients, DateTime maintenant) {
    if (!actif) return patProchainCode(patients, maintenant);
    final col = magasin.collection(collection);
    for (final p in plages) {
      final n = (p['prochain'] as num).toInt();
      if (n <= (p['fin'] as num).toInt()) {
        // La plage avance DÈS la réservation : l'écran de saisie peut rester ouvert, et un second guichet ne reçoit pas le même numéro.
        col.appliquerDistante({...p, 'prochain': n + 1});
        unawaited(recharger(maintenant: maintenant));
        return codePatient(n, maintenant.year);
      }
    }
    unawaited(recharger(maintenant: maintenant));
    return 'PROV-${maintenant.millisecondsSinceEpoch.toRadixString(36).toUpperCase()}';
  }
}
