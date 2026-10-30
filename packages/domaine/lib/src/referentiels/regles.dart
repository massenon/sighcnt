/// Règles pures de référentiel reprises de la maquette (`core.js`, `data.js`).
library;

import '../format/js.dart';

/// RG-01 — `C.codePatient(ordre, annee)` : `CNT/[n° d'ordre]/[année sur 2 chiffres]`. Le code attribué ne se
/// modifie jamais : cette fonction est appelée à la création, jamais à l'affichage.
String codePatient(Object ordre, Object annee) {
  final a = annee.toString();
  final yy = a.length > 2 ? a.substring(a.length - 2) : a;
  return 'CNT/${_texte(ordre)}/$yy';
}

String _texte(Object v) => v is double && v == v.truncateToDouble() ? v.toInt().toString() : v.toString();

/// `D.resultatRendu(etat)` : seul un résultat validé ou rectifié est opposable au prescripteur.
bool resultatRendu(String? etat) => etat == 'valide' || etat == 'rectifie';

const _accents = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'ç': 'c', 'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
  'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ñ': 'n', 'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
  'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ý': 'y', 'ÿ': 'y',
};

String _sansAccents(String s) => s.split('').map((c) => _accents[c] ?? c).join();

/// `D.secteurNormalise(cle)` : toute clé — secteur d'acte, centre de coûts, origine de prescription — est ramenée
/// à l'un des SIX secteurs productifs, ou à `null` (direction, entretien, ambulance : un support n'est pas un secteur).
String? secteurNormalise(Object? cle) {
  final k = _sansAccents((cle == null ? '' : cle.toString()).toLowerCase());
  if (k.isEmpty) return null;
  if (RegExp('labo').hasMatch(k)) return 'Laboratoire';
  if (RegExp('pharma|dispensation|medicament').hasMatch(k)) return 'Pharmacie';
  if (RegExp(r'maternit|obstetr|gyneco|accouch|cpn|pf\b').hasMatch(k)) return 'Maternité';
  if (RegExp('imagerie|echograph|radio|ecg|scanner|irm|mammo').hasMatch(k)) return 'Imagerie médicale';
  if (RegExp('consultation|medecine|accueil').hasMatch(k)) return 'Consultation';
  if (RegExp('hospit|observation|soins|chirurgie|bloc|urgence').hasMatch(k)) return 'Hospitalisation et soins';
  return null;
}

/// Utilisé par les tests de bornes : `Math.round((b − a) / 86 400 000)`.
int joursEntre(DateTime a, DateTime b) => arrondiJs((b.difference(a).inMilliseconds) / 86400000).toInt();
