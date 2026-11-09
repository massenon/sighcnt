// LE SERVICE DES PARAMÈTRES (lot L0) : ce que le poste appelle pour LIRE la valeur en vigueur, la RÉGLER (nouvelle version datée) et NOTER qu'une pièce l'a utilisée.
//
// Dart pur : le magasin du poste lui est branché par quatre fonctions (lire les versions, lire les usages, écrire une version, écrire un usage). Ainsi la règle se
// teste sans Flutter, et la même sert la mère (qui écrit) et le fileul (qui ne fait que lire : sa collection de paramètres est protégée « réglé sur la mère »).
//
// Aucune valeur n'est codée ici : le DÉFAUT vient de la définition (donnée du registre), la valeur en vigueur de la base. Un paramètre inconnu se REFUSE en le nommant.

import 'parametres.dart';

typedef LireFichesParametres = List<Map<String, Object?>> Function();
typedef EcrireFicheParametre = void Function(String id, Map<String, Object?> champs);

/// AAAA-MM-JJ d'une date locale : la date d'une pièce ou d'un effet, jamais une heure.
String parametreDateIso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Ce que l'écran des paramètres montre d'une définition : la valeur d'aujourd'hui, d'où elle vient, et la prochaine version à venir s'il y en a une.
class ParametreAffiche {
  const ParametreAffiche({required this.definition, required this.valeur, required this.origine, required this.version, required this.dateEffet, required this.prochaine, required this.nbVersions});
  final DefinitionParametre definition;
  final Object? valeur;

  /// `defaut` (aucune version ne s'applique) ou `version`.
  final String origine;
  final int version;
  final String? dateEffet;

  /// La première version dont la date d'effet est postérieure à aujourd'hui (`null` : aucune).
  final Parametre? prochaine;
  final int nbVersions;
}

class ServiceParametres {
  ServiceParametres({
    required this.definitions,
    required this.lireVersions,
    required this.lireUsages,
    required this.ecrireVersion,
    required this.ecrireUsage,
    required this.auteur,
    required this.maintenant,
  });

  final List<DefinitionParametre> definitions;
  final LireFichesParametres lireVersions;
  final LireFichesParametres lireUsages;
  final EcrireFicheParametre ecrireVersion;
  final EcrireFicheParametre ecrireUsage;

  /// Qui règle (RG-12 : aucune action anonyme). Lu à chaque geste : la session peut changer.
  final String Function() auteur;

  /// Le moment du geste (horloge du poste).
  final DateTime Function() maintenant;

  DefinitionParametre? definition(String cle) {
    for (final d in definitions) {
      if (d.cle == cle) return d;
    }
    return null;
  }

  /// Les versions connues (les fiches archivées ou illisibles sont ignorées).
  List<Parametre> versions([String? cle]) => [
        for (final f in lireVersions())
          if (f['statut'] != 'archive' && (cle == null || f['cle'] == cle)) Parametre.fromJson(f)
      ];

  /// Sème la version 0 (le défaut) de chaque définition qui n'a pas encore sa fiche. À appeler sur la MÈRE seulement : un fileul reçoit les mêmes fiches par le
  /// journal, et en attendant la valeur en vigueur retombe sur le défaut de la définition, identique. Rend le nombre de fiches semées.
  int semerDefauts() {
    final connues = {for (final f in lireVersions()) '${f['id']}'};
    var n = 0;
    for (final d in definitions) {
      final p = Parametres.semer(d);
      if (connues.contains(p.id)) continue;
      ecrireVersion(p.id, p.toJson());
      n++;
    }
    return n;
  }

  /// La valeur en vigueur de [cle] à [date] (AAAA-MM-JJ : la date de la PIÈCE, pas celle du jour, quand une pièce est en jeu).
  ResultatParametre<ResolutionParametre> valeurA(String cle, String date) => Parametres.resoudre(cle, versions(cle), date, definition: definition(cle));

  /// Comme [valeurA], mais ne refuse jamais : un paramètre inconnu rend `null`, un défaut manquant aussi. Pour les écrans qui ont besoin d'une valeur pour
  /// s'afficher ; une règle qui DÉCIDE passe par [valeurA] et traite le refus.
  Object? valeur(String cle, String date) {
    final r = valeurA(cle, date);
    return r.ok ? r.valeur!.valeur : definition(cle)?.defaut;
  }

  /// Règle [cle] : une NOUVELLE VERSION à partir de [dateEffet] (AAAA-MM-JJ). Jamais une réécriture : une valeur déjà utilisée par une pièce se refuse en nommant la
  /// date de la dernière pièce (`parametre_deja_utilise`). Écrit la version si elle est recevable.
  ResultatParametre<Parametre> regler(String cle, Object? valeur, String dateEffet, {String? motif}) {
    final r = Parametres.proposer(
      definition: definition(cle),
      versions: versions(cle),
      usages: lireUsages().where((u) => u['cle'] == cle).toList(),
      valeur: valeur,
      dateEffet: dateEffet,
      auteur: auteur(),
      creeLe: maintenant().toUtc().toIso8601String(),
      motif: (motif == null || motif.trim().isEmpty) ? null : motif.trim(),
    );
    if (r.ok) ecrireVersion(r.valeur!.id, r.valeur!.toJson());
    return r;
  }

  /// Note qu'une PIÈCE émise à [date] a utilisé la valeur de [cle] : c'est ce qui interdit ensuite de réécrire cette valeur. Idempotent (une pièce, une clé, une ligne).
  /// Une clé inconnue est refusée en la nommant : noter l'usage d'un paramètre qui n'existe pas masquerait une faute de frappe.
  RefusParametre? enregistrerUsage(String cle, String date, String piece) {
    if (definition(cle) == null && versions(cle).isEmpty) {
      return const RefusParametre('parametre_inconnu', 'Paramètre inconnu : l\'usage ne peut pas être noté.', 'Vérifier la clé du paramètre dans le registre');
    }
    if (!Parametres.dateValide(date)) return RefusParametre('date_invalide', 'Date « $date » illisible : attendu AAAA-MM-JJ.', 'Fournir la date de la pièce au format AAAA-MM-JJ');
    final id = '$cle@$piece';
    if (lireUsages().any((u) => u['id'] == id)) return null;
    ecrireUsage(id, {'cle': cle, 'date': date, 'piece': piece});
    return null;
  }

  /// L'historique d'une clé, de la version la plus récente à la plus ancienne (date d'effet puis numéro).
  List<Parametre> historique(String cle) => versions(cle)
    ..sort((a, b) {
      final c = (b.dateEffet ?? '').compareTo(a.dateEffet ?? '');
      return c != 0 ? c : b.version.compareTo(a.version);
    });

  /// Les définitions avec leur valeur d'aujourd'hui, groupées par famille (l'ordre des familles est celui du registre).
  Map<String, List<ParametreAffiche>> parFamille(String aujourdhui) {
    final out = <String, List<ParametreAffiche>>{};
    for (final d in definitions) {
      final vs = versions(d.cle);
      final r = valeurA(d.cle, aujourdhui);
      final futures = vs.where((v) => v.dateEffet != null && v.dateEffet!.compareTo(aujourdhui) > 0).toList()..sort((a, b) => a.dateEffet!.compareTo(b.dateEffet!));
      (out[d.famille] ??= []).add(ParametreAffiche(
        definition: d,
        valeur: r.ok ? r.valeur!.valeur : d.defaut,
        origine: r.ok ? r.valeur!.origine : 'defaut',
        version: r.ok ? r.valeur!.version : 0,
        dateEffet: r.ok ? r.valeur!.dateEffet : null,
        prochaine: futures.isEmpty ? null : futures.first,
        nbVersions: vs.length,
      ));
    }
    return out;
  }
}

