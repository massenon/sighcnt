/// POSTE D'IMAGERIE — les chiffres que lisent le registre des demandes, le tableau de bord du poste et la galerie des clichés.
///
/// Rien n'est fourni : tout est CALCULÉ depuis les registres (demandes, comptes rendus, clichés). Port des `afficher()` de
/// `m2-imagerie-demandes`, `m2-dashboard-imagerie` et `m2-echographie-galerie`, rejoué sur les vecteurs de ces écrans réels
/// (`test/vecteurs/img_demandes.json`).
library;

import '../format/recherche.dart';
import 'img_demandes_etats.dart';

typedef FicheImg = Map<String, Object?>;

bool _vrai(Object? v) => v != null && v != '' && v != 0 && v != false;
bool _actif(FicheImg f) => f['statut'] != 'archive';

/// Registre : le nombre de demandes de chaque état (les quatre indicateurs du registre). Les fiches archivées (RG-14) ne comptent pas.
Map<String, int> comptesParEtat(Iterable<FicheImg> demandes) => {
      for (final e in etatsImagerie)
        e.id: demandes.where((d) => _actif(d) && d['statut'] == e.id).length
    };

/// Une ligne de « Activité par modalité ».
class LigneModalite {
  const LigneModalite(this.modalite,
      {required this.attente,
      required this.payees,
      required this.redaction,
      required this.rendus});
  final ModaliteDemandeImagerie modalite;
  final int attente, payees, redaction, rendus;
}

/// Ce que le tableau de bord du poste montre : les examens PAYÉS (la file à exécuter), l'attente de caisse, les CR en rédaction, les CR rendus
/// ce mois-ci, et la charge par modalité.
class PosteImagerie {
  PosteImagerie(
      {required this.payees,
      required this.attente,
      required this.redaction,
      required this.rendusMois,
      required this.parModalite});

  /// Triées par date croissante (les plus anciennes d'abord : le premier regard du poste).
  final List<FicheImg> payees;
  final List<FicheImg> attente;
  final List<FicheImg> redaction;
  final List<FicheImg> rendusMois;
  final List<LigneModalite> parModalite;
}

/// `afficher()` de `m2-dashboard-imagerie`. [moisCourant] : `AAAA-MM` de l'horloge du poste. Un CR est « rendu ce mois-ci » d'après sa date de
/// rendu (`renduLe`), à défaut sa date de rédaction.
PosteImagerie posteImagerie({
  required Iterable<FicheImg> demandes,
  required Iterable<FicheImg> comptesRendus,
  required Iterable<FicheImg> catalogue,
  required String moisCourant,
}) {
  final dems = demandes.where(_actif).toList();
  final payees = dems.where((r) => r['statut'] == 'payee').toList();
  final attente = dems.where((r) => r['statut'] == 'demandee').toList();
  final crs = comptesRendus.where(_actif).toList();
  final redaction = crs.where((r) => r['statut'] != 'rendu').toList();
  final rendusMois = crs.where((r) {
    if (r['statut'] != 'rendu') return false;
    final t = _vrai(r['renduLe'])
        ? '${r['renduLe']}'
        : (_vrai(r['date']) ? '${r['date']}' : '');
    return (t.length > 7 ? t.substring(0, 7) : t) == moisCourant;
  }).toList();
  bool de(FicheImg x, ModaliteDemandeImagerie m) =>
      modaliteDemandeDeExamen(catalogue, x['examenCode']) == m.code;
  return PosteImagerie(
    payees: trierPar(payees, (r) => r['dateHeure']),
    attente: attente,
    redaction: redaction,
    rendusMois: rendusMois,
    parModalite: [
      for (final m in modalitesDemandeImagerie)
        LigneModalite(m,
            attente: attente.where((x) => de(x, m)).length,
            payees: payees.where((x) => de(x, m)).length,
            redaction: redaction.where((x) => de(x, m)).length,
            rendus: rendusMois.where((x) => de(x, m)).length)
    ],
  );
}

/// Les quatre indicateurs de la galerie.
class StatsGalerie {
  const StatsGalerie(this.conserves, this.patients, this.lies, this.sansLien);
  final int conserves, patients, lies, sansLien;
}

/// `afficher()` de `m2-echographie-galerie` : un patient se reconnaît à son identifiant, à défaut à son nom (un cliché d'un patient sans dossier
/// ne s'additionne pas à un autre).
StatsGalerie statsGalerie(Iterable<FicheImg> cliches) {
  final rows = cliches.where(_actif).toList();
  final patients = <String>{
    for (final r in rows)
      _vrai(r['patientId']) ? '${r['patientId']}' : '${r['patient']}'
  };
  final lies = rows.where((r) => _vrai(r['crReference'])).length;
  return StatsGalerie(rows.length, patients.length, lies, rows.length - lies);
}

/// Les clichés du plus récent au plus ancien (`C.sortBy(rows, 'date').reverse()`).
List<FicheImg> clichesRecentsDabord(Iterable<FicheImg> cliches) =>
    trierPar(cliches.where(_actif).toList(), (r) => r['date'])
        .reversed
        .toList();
