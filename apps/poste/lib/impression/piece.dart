import 'package:sigh_domaine/sigh_domaine.dart';

class Signature {
  const Signature(this.role, {this.nom, this.mention = 'Signature'});
  final String role;
  final String? nom;
  final String mention;
}

/// Pièce A4 (`P.etat`) : en-tête légal UNIQUE (jamais passé par l'appelant), titre, filtres en force, contenu tabulaire dont le total est
/// calculé, lieu et date, signatures, pied normalisé (utilisateur, date/heure, identifiant). Une seule description pour l'aperçu ET le PDF.
/// Un bloc de contenu d'une pièce, dans l'ordre d'impression : le même ordre sert l'aperçu et le PDF.
sealed class BlocPiece {
  const BlocPiece();
}

class BlocTableau extends BlocPiece {
  const BlocTableau(this.tableau, {this.titre, this.alerte = false});
  final TableauEtat tableau;

  /// Intertitre (« Prestations réglées », « Reste à régler ») ; `alerte` le met en rouge.
  final String? titre;
  final bool alerte;
}

class BlocTexte extends BlocPiece {
  const BlocTexte(this.texte, {this.gras = false, this.italique = false});
  final String texte;
  final bool gras;
  final bool italique;
}

class PieceA4 {
  PieceA4({
    required this.titre,
    required this.reference,
    required this.utilisateur,
    required this.edite,
    this.sousTitre,
    List<TableauEtat> tableaux = const [],
    List<BlocPiece> blocs = const [],
    this.cartouche = const [],
    this.filtres = const [],
    this.signatures = const [],
    this.lieuDate = true,
    this.filigrane,
  }) : blocs = [...blocs, for (final t in tableaux) BlocTableau(t)];

  final String titre;
  final String? sousTitre;
  final List<BlocPiece> blocs;

  /// Cartouche d'en-tête de pièce : (libellé, valeur), sur deux colonnes.
  final List<(String, String)> cartouche;

  /// Filtres appliqués à l'état, (libellé, valeur) : un état tiré d'un écran filtré ne montre qu'une PARTIE des données, et doit le dire.
  final List<(String, String)> filtres;
  final List<Signature> signatures;
  final bool lieuDate;
  final String? filigrane;
  final String reference;
  final String utilisateur;
  final DateTime edite;

  /// Référence `CNT-AAAAMMJJ-NNNN` (`compteur` s'incrémente à chaque édition, comme la maquette).
  static String reference_(DateTime d, int compteur) =>
      'CNT-${iso(d).replaceAll('-', '')}-${compteur.toString().padLeft(4, '0')}';
}
