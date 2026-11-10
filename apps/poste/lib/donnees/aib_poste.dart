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
    if (s.toutes.isEmpty) {
      for (final f in aibSituationsSemees) {
        s.ajouterSansJournal({...f, 'statut': 'actif', 'creeLe': '2026-11-09', 'creePar': 'Semence du socle'});
      }
    }
    final b = m.collection('baremeAib');
    if (b.toutes.isEmpty) {
      for (final f in aibBaremeSeme) {
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
}
