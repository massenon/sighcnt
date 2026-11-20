/// LE TRANSFERT D'UN FICHIER PAR MORCEAUX, AVEC REPRISE (EF-SYNC-18, lot D5) : les règles PURES, sans disque ni réseau. Un fichier voyage À PART du journal, par son empreinte
/// SHA-256 : les métadonnées d'abord (la fiche), le binaire ensuite, en morceaux dont chacun porte SA propre empreinte. Un morceau altéré est refusé et renvoyé ; un transfert
/// coupé repart du dernier morceau VÉRIFIÉ ; le fichier entier n'est rangé qu'après la vérification de l'empreinte de l'ensemble.
///
/// La taille de morceau (256 Kio) est une PROPOSITION à valider : assez petite pour qu'une coupure ne fasse pas recommencer un gros scan, assez grande pour qu'un fichier de
/// 10 Mo tienne en quarante requêtes.
library;

import 'dart:typed_data';

import 'fichiers_regles.dart';
import 'sha256.dart';

const int fichierTailleMorceau = 256 * 1024;

/// Le découpage d'un fichier de [taille] octets en morceaux de [tailleMorceau] octets.
class PlanMorceaux {
  const PlanMorceaux(this.taille, [this.tailleMorceau = fichierTailleMorceau]);
  final int taille;
  final int tailleMorceau;

  int get nombre => taille <= 0 ? 0 : (taille + tailleMorceau - 1) ~/ tailleMorceau;
  int debut(int i) => i * tailleMorceau;
  int fin(int i) => (i + 1) * tailleMorceau > taille ? taille : (i + 1) * tailleMorceau;
  int longueur(int i) => fin(i) - debut(i);
}

/// Ce que l'émetteur annonce avant le premier morceau : l'empreinte de l'ensemble, la taille, la taille de morceau et l'empreinte de CHAQUE morceau.
class DescriptionFichier {
  const DescriptionFichier({required this.sha256, required this.taille, required this.tailleMorceau, required this.morceaux});
  final String sha256;
  final int taille;
  final int tailleMorceau;
  final List<String> morceaux;

  PlanMorceaux get plan => PlanMorceaux(taille, tailleMorceau);

  Map<String, Object?> toJson() => {'sha256': sha256, 'taille': taille, 'tailleMorceau': tailleMorceau, 'morceaux': morceaux};

  factory DescriptionFichier.depuisJson(Map<String, Object?> j) => DescriptionFichier(
        sha256: '${j['sha256']}',
        taille: (j['taille'] as num).toInt(),
        tailleMorceau: (j['tailleMorceau'] as num).toInt(),
        morceaux: [for (final m in (j['morceaux'] as List)) '$m'],
      );

  /// La description d'octets que l'on possède.
  factory DescriptionFichier.deOctets(Uint8List octets, [int tailleMorceau = fichierTailleMorceau]) => DescriptionFichier(
        sha256: sha256Octets(octets),
        taille: octets.length,
        tailleMorceau: tailleMorceau,
        morceaux: fichierHachesMorceaux(octets, tailleMorceau),
      );

  /// La cohérence de la description elle-même (empreinte valide, nombre de morceaux conforme au plan, chaque empreinte valide) ; `null` si elle tient.
  RefusFichier? incoherence({int tailleMax = 64 * 1024 * 1024}) {
    if (!empreinteValide(sha256)) {
      return const RefusFichier('EMPREINTE_INVALIDE', 'l’empreinte annoncée n’est pas un SHA-256 (64 caractères hexadécimaux)', 'Ouvrir la pièce depuis sa fiche.');
    }
    if (taille <= 0) return const RefusFichier('FICHIER_VIDE', 'le fichier annoncé ne contient aucun octet', 'Choisir un fichier numérisé non vide.');
    if (taille > tailleMax) {
      return RefusFichier('TAILLE_DEPASSEE', 'le fichier annoncé pèse ${fichierPoids(taille)}, le maximum est ${fichierPoids(tailleMax)}',
          'Numériser en résolution plus basse, ou demander à l’administrateur de relever la taille maximale.');
    }
    if (tailleMorceau < 1024 || tailleMorceau > 4 * 1024 * 1024) {
      return const RefusFichier('PLAN_INVALIDE', 'la taille de morceau annoncée est hors de 1 Kio à 4 Mio', 'Rejouer le transfert avec la taille de morceau du poste.');
    }
    if (morceaux.length != plan.nombre || morceaux.any((m) => !empreinteValide(m))) {
      return const RefusFichier('PLAN_INVALIDE', 'le plan des morceaux ne correspond pas à la taille annoncée', 'Rejouer le transfert depuis le fichier d’origine.');
    }
    return null;
  }
}

/// Les empreintes de chaque morceau d'un fichier.
List<String> fichierHachesMorceaux(Uint8List octets, [int tailleMorceau = fichierTailleMorceau]) {
  final plan = PlanMorceaux(octets.length, tailleMorceau);
  return [for (var i = 0; i < plan.nombre; i++) sha256Octets(Uint8List.sublistView(octets, plan.debut(i), plan.fin(i)))];
}

/// L'état de RÉCEPTION d'un fichier : quels morceaux ont été reçus ET vérifiés. Il ne tient aucun octet (le stockage des morceaux est l'affaire du disque) : c'est ce qui
/// permet de reprendre après un redémarrage avec la seule liste des morceaux déjà rangés.
class ReceptionFichier {
  ReceptionFichier(this.description, {Iterable<int> deja = const []}) : _verifies = {...deja};
  final DescriptionFichier description;
  final Set<int> _verifies;

  Set<int> get verifies => Set.unmodifiable(_verifies);

  /// Les morceaux encore à recevoir, dans l'ordre : la REPRISE repart du premier manquant.
  List<int> get manquants => [for (var i = 0; i < description.plan.nombre; i++) if (!_verifies.contains(i)) i];

  bool get complet => _verifies.length == description.plan.nombre;

  /// Contrôle UN morceau reçu : rang, longueur, empreinte. Rend le refus nommé (`MORCEAU_HORS_PLAN`, `MORCEAU_ALTERE`), ou `null` et le marque VÉRIFIÉ. Un morceau déjà vérifié
  /// et reçu une seconde fois est accepté sans rien changer (idempotence : jamais un compteur doublé).
  RefusFichier? accepter(int i, List<int> octets) {
    final plan = description.plan;
    if (i < 0 || i >= plan.nombre) {
      return RefusFichier('MORCEAU_HORS_PLAN', 'le morceau $i n’existe pas dans ce fichier (${plan.nombre} morceaux)', 'Reprendre le transfert avec la liste des morceaux manquants.');
    }
    if (octets.length != plan.longueur(i)) {
      return RefusFichier('MORCEAU_ALTERE', 'le morceau $i a ${octets.length} octets au lieu de ${plan.longueur(i)}', 'Renvoyer ce morceau.', {'morceau': i});
    }
    final h = sha256Octets(octets);
    if (h != description.morceaux[i]) {
      return RefusFichier('MORCEAU_ALTERE', 'le morceau $i n’a pas l’empreinte annoncée (transport altéré)', 'Renvoyer ce morceau.', {'morceau': i, 'recu': h, 'annonce': description.morceaux[i]});
    }
    _verifies.add(i);
    return null;
  }

  /// La vérification de l'ENSEMBLE, avant de ranger : l'empreinte des octets assemblés est celle de la description. Une divergence jette tout (les morceaux vérifiés un à un
  /// ne prouvent pas un assemblage faux).
  RefusFichier? verifierEnsemble(Uint8List assemble) {
    if (assemble.length != description.taille) {
      return RefusFichier('EMPREINTE_DIVERGENTE', 'le fichier assemblé a ${assemble.length} octets au lieu de ${description.taille}', 'Redemander le fichier.');
    }
    final h = sha256Octets(assemble);
    if (h != description.sha256) {
      return RefusFichier('EMPREINTE_DIVERGENTE', 'le fichier assemblé n’a pas l’empreinte annoncée', 'Redemander le fichier.', {'recu': h, 'annonce': description.sha256});
    }
    return null;
  }
}
