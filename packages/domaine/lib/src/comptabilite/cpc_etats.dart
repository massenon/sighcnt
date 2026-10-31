/// ÉTATS FINANCIERS DE SYNTHÈSE AU FORMAT DE LA LIASSE DÉPOSÉE (M12, `m12-etats-financiers`) — port de `m12-comptabilite.js` (vagues 57-59), rejoué sur
/// `test/vecteurs/etats.json` tiré de l'écran réel.
///
/// L'écran reproduit les CINQ feuillets de la liasse remise à la DGI le 15/05/2026 (code BK505416) : bilan, compte de résultat, flux de trésorerie, note 11
/// « Disponibilités », note 34 « Fiche de synthèse ». Mêmes références (AD, AI, XB, ZA…), mêmes libellés, même ordre, mêmes sous-totaux : un comptable doit
/// retrouver SES lignes, à LEUR place, pour rapprocher l'écran du dépôt. DEUX COLONNES DE NATURES DIFFÉRENTES, QUI NE SE MÉLANGENT JAMAIS :
///  * « déposé » (N et N-1) CITE le document — des faits, qui ne se recalculent pas ; la liasse est ENGENDRÉE (`cpc_liasse.dart`), jamais recopiée ;
///  * « exercice en cours » est CALCULÉE depuis les écritures VALIDÉES du journal, par les préfixes de comptes SYSCOHADA que chaque ligne déclare — et reste
///    VIDE là où le journal ne porte rien : un zéro y ferait croire à un solde nul.
/// UN COMPTE DE TIERS CHANGE DE CÔTÉ SELON SON SENS : le plan SYSCOHADA emploie les mêmes comptes de classe 4 pour les créances et pour les dettes ; solde
/// débiteur → actif, créditeur → passif. Les SIX ÉCARTS INTERNES du document déposé sont CONSERVÉS et signalés, jamais arbitrés.
library;

import 'dart:convert';

import '../format/js.dart';
import 'cpa_referentiels.dart' show CpaFiche;
import 'cpc_exercice.dart';
import 'cpc_liasse.dart';

double _n(Object? v) => nombreOuZero(v);

/// La liasse déposée, typée.
class CpcLiasseDonnees {
  CpcLiasseDonnees(Map<String, Object?> j)
      : depot = (j['DEPOT'] as Map).cast<String, Object?>(),
        bilanActif = _l(j['BILAN_ACTIF']),
        bilanPassif = _l(j['BILAN_PASSIF']),
        resultat = _l(j['RESULTAT']),
        flux = _l(j['FLUX']),
        dispoNote = '${(j['DISPONIBILITES'] as Map)['note']}',
        dispoNb = '${(j['DISPONIBILITES'] as Map)['nb']}',
        dispoLignes = _l((j['DISPONIBILITES'] as Map)['lignes']),
        dispoCommentaires = [for (final x in ((j['DISPONIBILITES'] as Map)['commentaires'] as List)) '$x'],
        synthese = _l(j['SYNTHESE']),
        notesSynthese = [for (final x in (j['NOTES_SYNTHESE'] as List)) '$x'],
        ecarts = _l(j['ECARTS']);
  static List<CpaFiche> _l(Object? v) => [for (final x in (v as List)) (x as Map).cast<String, Object?>()];

  final Map<String, Object?> depot;
  final List<CpaFiche> bilanActif, bilanPassif, resultat, flux, dispoLignes, synthese, ecarts;
  final String dispoNote, dispoNb;
  final List<String> dispoCommentaires, notesSynthese;

  int get exerciceN => depot['exerciceN'] as int;
  int get exerciceN1 => depot['exerciceN1'] as int;

  CpaFiche? ligne(List<CpaFiche> l, String ref) {
    for (final x in l) {
      if (x['ref'] == ref) return x;
    }
    return null;
  }

  /// `L.ecart(cle)` : l'écart interne du document, ou `null`.
  CpaFiche? ecart(Object? cle) {
    for (final x in ecarts) {
      if (x['cle'] == cle) return x;
    }
    return null;
  }

  /// Les écarts nommés par [cles], dans l'ordre du document.
  List<CpaFiche> ecartsDe(List<String> cles) => [for (final x in ecarts) if (cles.contains(x['cle'])) x];
}

CpcLiasseDonnees? _d;
CpcLiasseDonnees get cpcLiasseDonnees => _d ??= CpcLiasseDonnees((jsonDecode(cpcLiasseJson) as Map).cast<String, Object?>());

/// `soldeDesComptes(prefixes, sens, source)` : le solde des écritures dont le compte commence par l'un des préfixes — `null` si la ligne ne déclare aucun
/// préfixe ou si le journal ne porte rien (jamais un zéro). `sens: 'credit'` lit le passif et les produits, sinon l'actif et les charges.
double? cpcSoldeDesComptes(List<Object?>? prefixes, String sens, Iterable<CpaFiche> source) {
  if (prefixes == null || prefixes.isEmpty) return null;
  final sel = [
    for (final x in source)
      if (prefixes.any((p) => '${x['compte'] ?? ''}'.startsWith('$p'))) x
  ];
  if (sel.isEmpty) return null;
  final d = sel.fold(0.0, (a, x) => a + _n(x['debit'])), c = sel.fold(0.0, (a, x) => a + _n(x['credit']));
  return sens == 'credit' ? c - d : d - c;
}

List<Object?>? _comptes(CpaFiche l) => l['comptes'] as List?;

/// Un compte de TIERS change de côté : à l'actif, seul un solde débiteur compte ; un solde négatif y serait un contresens.
double? cpcCalculActif(CpaFiche l, Iterable<CpaFiche> source) {
  final v = cpcSoldeDesComptes(_comptes(l), 'debit', source);
  return v == null || v < 0 ? null : v;
}

/// Au passif, seul un solde créditeur compte.
double? cpcCalculPassif(CpaFiche l, Iterable<CpaFiche> source) {
  final v = cpcSoldeDesComptes(_comptes(l), 'credit', source);
  return v == null || v < 0 ? null : v;
}

/// Au compte de résultat, le formulaire porte les charges en NÉGATIF : on suit sa convention, sans quoi la colonne calculée ne se compare pas à la déposée.
double? cpcCalculResultat(CpaFiche l, Iterable<CpaFiche> source) {
  final v = cpcSoldeDesComptes(_comptes(l), l['signe'] == '-' ? 'debit' : 'credit', source);
  if (v == null) return null;
  return l['signe'] == '-' ? -v : v;
}

/// Note 11 « Disponibilités » : le solde se lit au débit, négatif compris (« en négatif si le compte principal attaché est débiteur »).
double? cpcCalculDisponibilite(CpaFiche l, Iterable<CpaFiche> source) => cpcSoldeDesComptes(_comptes(l), 'debit', source);

/// Les écritures VALIDÉES de l'exercice [annee] (un brouillon n'est pas un fait comptable), plus ses à-nouveaux PROVISOIRES s'il n'est pas encore ouvert sur
/// un exercice clos.
List<CpaFiche> cpcSourceExercice(Iterable<CpaFiche> exercices, Iterable<CpaFiche> actives, int annee) => [
      ...cpcEcrituresDe(actives, annee),
      ...cpcANouveauxProvisoires(exercices, actives, annee).where((x) => x['statut'] == 'validee'),
    ];

/// La variation en % de la note 11 : `(N − N-1) / |N-1| × 100`, absente quand l'une des deux années l'est (ou que N-1 vaut zéro).
double? cpcVariationDisponibilite(CpaFiche l) {
  final n = l['n'], n1 = l['n1'];
  if (n == null || n1 == null || n1 == 0) return null;
  return (_n(n) - _n(n1)) / _n(n1).abs() * 100;
}
