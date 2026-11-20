import 'package:sigh_domaine/sigh_domaine.dart';

import '../core/service_parametres.dart';
import 'magasin.dart';

/// L'AIB au poste (Direction, 09/11/2026, lot L2) : la colle entre les fonctions pures de `packages/domaine/lib/src/comptabilite/aib.dart` (rejouées sur les
/// vecteurs de la maquette) et le magasin du poste. Aucune règle ici : le taux se lit à la version datée du barème, la charge des 5 %, le branchement sur les
/// achats et les deux comptes à la version datée du REGISTRE DES PARAMÈTRES (`bareme_aib.*`, famille R : la mère écrit, les fileuls reçoivent), l'écriture à la
/// liste que le domaine calcule. Ce fichier ne fait qu'assembler les fiches, écrire ce que le domaine rend, et journaliser (RG-12).
class AibPoste {
  AibPoste(this.m, {required this.auteur, required this.role, required this.libelleRole, required this.fileul, DateTime Function()? horloge})
      : _horloge = horloge ?? DateTime.now;
  final Magasin m;
  final String Function() auteur;
  final String role;
  final String libelleRole;

  /// Un fileul lit, la mère écrit (refus nommé AIB_POSTE_FILEUL).
  final bool fileul;
  final DateTime Function() _horloge;

  String get aujourdhui => parametreDateIso(_horloge());

  ServiceParametres get service => serviceParametres(m, auteur: auteur, horloge: _horloge);

  /// Sème, EN MÉMOIRE et sans journal, les situations de l'acheteur et les versions du barème (constantes du domaine engendrées par la maquette) quand elles
  /// manquent : le barème est « à valider » tant qu'aucun texte réglementaire n'est au dépôt. Idempotent.
  static void amorcer(Magasin m) {
    final s = m.collection('situationsAib');
    final codes = {for (final f in s.toutes) f['code']};
    // Lot FISC-2 : le SECOND barème (retenue sur la facture d'un tiers) s'ajoute à un poste qui n'a que les trois situations de l'acheteur : par code, jamais en doublon.
    for (final f in aibSituationsSemees) {
      if (!codes.contains(f['code'])) {
        s.ajouterSansJournal({...f, 'statut': 'actif', 'creeLe': '2026-11-09', 'creePar': 'Semence du socle'});
      }
    }
    final b = m.collection('baremeAib');
    final avecVersion = {for (final f in b.toutes) f['situation']};
    for (final f in aibBaremeSeme) {
      if (!avecVersion.contains(f['situation'])) {
        b.ajouterSansJournal({...f, 'statut': 'actif', 'aValider': true, 'creeLe': '2026-11-09', 'creePar': 'Semence du socle'});
      }
    }
  }

  /// Les fiches que les fonctions du domaine lisent, relues À CHAQUE appel (le magasin est la seule source).
  AibDonnees donnees() {
    amorcer(m);
    return AibDonnees(
      situations: m.collection('situationsAib').toutes,
      bareme: m.collection('baremeAib').toutes,
      reglages: aibReglagesDepuisParametres(service.versions()),
      comptes: m.collection('comptes').toutes,
      fournisseurs: m.collection('fournisseurs').toutes,
      facturesFournisseurs: m.collection('facturesFournisseurs').toutes,
      ecritures: m.collection('ecritures').toutes,
    );
  }

  /// Le réglage [cleRegistre] (`bareme_aib.…`) est-il recevable ? Rend le refus nommé du moteur (AIB_*), ou `null`. Même contrôle que `definir` de la maquette :
  /// rôle d'écriture, mère, valeur admise, compte au plan, date et motif, date d'effet postérieure, activation du branchement complète. La version est
  /// arrêtée à l'enregistrement : c'est un profil de la famille qui règle.
  Map<String, Object?>? controlerReglage(String cleRegistre, Object? valeur, String dateEffet, String? motif) {
    if (!cleRegistre.startsWith(aibPrefixeParametre)) return null;
    final r = aibDefinirReglage(donnees(), {'cle': cleRegistre.substring(aibPrefixeParametre.length), 'valeur': valeur, 'dateEffet': dateEffet, 'motif': motif},
        role: role, libelleRole: libelleRole, fileul: fileul, id: 'controle', creeLe: aujourdhui, auteur: auteur(), marquage: const {'aValider': false});
    return r['ok'] == true ? null : r;
  }

  /// Ce que le branchement écrirait (aperçu, sans rien écrire) sur la période ; sans bornes : du 1er janvier à aujourd'hui.
  Map<String, Object?> apercu({String? du, String? au}) => aibAchatsAEcrire(donnees(), du: du, au: au, aujourdhui: aujourdhui);

  /// Écrit EXACTEMENT ce que l'aperçu liste, quand le branchement est actif : une pièce de deux lignes en brouillon par facture. Désactivé : refus nommé, rien n'est
  /// écrit. Une écriture refusée par une garde de la collection (exercice clos) est rendue en refus nommé, sans interrompre le reste.
  Map<String, Object?> ecrire({String? du, String? au}) {
    final r = aibEcrireAchats(donnees(), du: du, au: au, aujourdhui: aujourdhui, role: role, libelleRole: libelleRole, fileul: fileul);
    if (r['ok'] != true) return r;
    final col = m.collection('ecritures');
    final posees = <String>{};
    final refusees = <Object?>[];
    final lignes = (r['lignesEcritures'] as List).cast<Map<String, Object?>>();
    for (var i = 0; i + 1 < lignes.length; i += 2) {
      final facture = lignes[i]['aibFactureId'];
      try {
        col.inserer({...lignes[i]}, prefixe: 'ECR');
        col.inserer({...lignes[i + 1]}, prefixe: 'ECR');
        posees.add('${lignes[i]['numero']}');
      } on EcritureRefusee catch (e) {
        refusees.add({'factureId': facture, 'motif': e.motif});
      }
    }
    m.journaliser('AIB sur achats écrit', 'M12', 'Ecriture', 'AIB-achats', null,
        {'pieces': posees.length, 'du': r['du'], 'au': r['au'], 'compteAcompte': (lignes.isEmpty ? null : lignes.first['compte'])});
    return {'ok': true, 'pieces': (r['pieces'] as List).where((p) => posees.contains('${(p as Map)['numero']}')).toList(), 'refusees': refusees, 'du': r['du'], 'au': r['au']};
  }

  // --- Une version nouvelle du barème (lot FISC-2 : portée au poste) -----------------------------------------------------------------------------

  /// Écrit une version NOUVELLE du barème : le domaine décide du refus nommé ou rend la fiche et la fermeture de la précédente (à la veille) ; ICI on écrit et on journalise
  /// (RG-12). Un profil de la famille de validation l'arrête à l'enregistrement (signée), tout autre la laisse « à valider ». Une version ne se réécrit pas.
  Map<String, Object?> nouvelleVersion(Map<String, Object?> saisie) {
    final maintenant = _horloge();
    final col = m.collection('baremeAib');
    final marq = valMarquageEnregistrement('bareme_aib',
        role: role, acteur: auteur(), maintenant: maintenant, libelles: {role: libelleRole}, avant: null, valeurs: {'taux': saisie['taux'], 'situation': saisie['situation']});
    final id = 'BAI${(col.toutes.length + 1).toString().padLeft(3, '0')}';
    final r = aibNouvelleVersion(donnees(), saisie, role: role, libelleRole: libelleRole, fileul: fileul, id: id, creeLe: aujourdhui, auteur: auteur(), marquage: marq.patch);
    if (r['ok'] != true) return r;
    final ferm = r['fermeture'] as Map?;
    if (ferm != null) col.mettreAJour(ferm['id'], {'dateFin': ferm['dateFin'], 'modifieLe': aujourdhui, 'modifiePar': auteur()}, journaliser: false);
    final fiche = (r['fiche'] as Map).cast<String, Object?>();
    col.inserer(fiche, prefixe: 'BAI');
    m.journaliser('Barème AIB : nouvelle version', 'CFG', 'baremeAib', id, {'precedente': r['precedente']},
        {'etat': r['enAttenteDeValidation'] == true ? 'à valider' : 'validé', 'situation': fiche['situation'], 'taux': fiche['taux'], 'dateEffet': fiche['dateEffet'], 'precedenteFermeeLe': r['precedenteFermeeLe']});
    return r;
  }

  // --- L'imputation de l'AIB, opération par opération (lot FISC-2, Direction, 16/11/2026) -------------------------------------------------------

  CollectionMagasin get imputations => m.collection('imputationsAib');

  /// La proposition du barème à la date de l'opération (n'écrit rien, ne décide rien).
  Map<String, Object?> proposer(Object? situation, String date) => aibProposerImputation(donnees(), situation: situation, date: date);

  /// Imputer : le domaine décide du refus nommé ou rend la fiche signée ; ICI on l'écrit et on journalise (RG-12). [droit] : le geste réservé `imputer_aib` de la fiche RBAC.
  Map<String, Object?> imputer(Map<String, Object?> saisie, {required bool droit}) {
    final maintenant = _horloge();
    final r = aibImputer(donnees(), imputations.actives,
        droit: droit,
        saisie: saisie,
        acteur: auteur(),
        libelleRole: libelleRole,
        maintenant: maintenant,
        aujourdhui: maintenant,
        exercices: m.collection('exercices').toutes);
    if (r['ok'] != true) return r;
    final fiche = (r['fiche'] as Map).cast<String, Object?>();
    final ins = imputations.inserer({...fiche, 'statut': 'actif'}, prefixe: 'IAI');
    m.journaliser('AIB : imputation', 'M12', 'imputationsAib', '${ins.fiche['id']}', null, {
      'operation': fiche['operation'],
      'reference': fiche['reference'],
      'appliquer': fiche['appliquer'],
      'taux': fiche['taux'],
      'montant': fiche['montant'],
      'compte': fiche['compte'],
      'horsProposition': fiche['horsProposition'] == true,
      'motif': fiche['motif'],
    });
    return {'ok': true, 'id': ins.fiche['id'], 'fiche': ins.fiche};
  }

  /// Annuler une imputation : un motif, l'archive (RG-14, jamais une suppression), l'opération redevient imputable.
  Map<String, Object?> annuler(String id, String? motif, {required bool droit}) {
    if (!droit) {
      return aibRefus('IMPUTATION_AIB_RESERVEE', 'Imputer l’AIB est un droit réservé de la fiche du rôle : « $libelleRole » ne l’a pas.', 'Demander à un rôle qui détient le droit « Imputer l’AIB » (matrice des droits).');
    }
    final x = imputations.parId(id);
    if (x == null || x['statut'] == 'archive') return aibRefus('AIB_IMPUTATION_INTROUVABLE', 'L’imputation « $id » n’existe pas ou est déjà annulée.', 'Choisir une imputation de la liste.');
    if ((motif ?? '').trim().isEmpty) return aibRefus('AIB_MOTIF_ABSENT', 'Le motif de l’annulation est obligatoire.', 'Dire pourquoi l’imputation est annulée.');
    imputations.archiver(id, journaliser: false);
    m.journaliser('AIB : imputation annulée', 'M12', 'imputationsAib', id, {'appliquer': x['appliquer'], 'taux': x['taux']}, {'statut': 'archive', 'motif': motif!.trim()});
    return {'ok': true, 'id': id};
  }
}
