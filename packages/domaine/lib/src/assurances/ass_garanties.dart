/// LES GARANTIES SONT DATÉES : `PR.poserGarantie` de la maquette (prototype_html/assets/js/parcours.js, lot IMP-B2), porté au lot 8b. Une VERSION de garantie, jamais un écrasement : un refus
/// se NOMME (code, motif, geste) ; l'essai contrôle sans rien écrire. La version remplacée reste écrite : une facture émise garde son taux, et une date d'effet qu'une facture a déjà
/// dépassée est refusée. Les fiches sont passées en ARGUMENT (souscripteurs, garanties, factures, patients, couvertures) : aucune lecture d'une base, aucune date lue sur l'horloge.
library;

import '../caisse/prise_en_charge.dart' show cleSerieGarantie, garantiesEnVigueur, souscripteurDe;
import '../format/format_fr.dart' show dateFR;
import 'ass_regles.dart' show assCategoriesGarantie, assDate, assUnitesPlafond;

typedef _Fiche = Map<String, Object?>;

/// Les versions d'une série (souscripteur, catégorie, libellé), de la plus ancienne à la plus récente (`versionsGarantie`). [garanties] : les fiches actives.
List<_Fiche> assVersionsGarantie(Iterable<_Fiche> garanties, Object? souscripteurId, Object? categorie, Object? libelle) {
  final cle = cleSerieGarantie({'souscripteurId': souscripteurId, 'categorie': categorie, 'libelle': libelle});
  return [for (final g in garanties) if (cleSerieGarantie(g) == cle) g]..sort((a, b) => '${a['dateEffet'] ?? ''}'.compareTo('${b['dateEffet'] ?? ''}'));
}

/// La première facture non archivée d'un assuré de ce souscripteur datée du jour dit ou après : ce qu'une version ne peut pas rattraper (la pièce émise garde son taux).
_Fiche? assFactureSousGrille(_Fiche sous, String jour,
    {required Iterable<_Fiche> factures, required Iterable<_Fiche> patients, required List<_Fiche> couvertures, required List<_Fiche> souscripteurs}) {
  final parId = {for (final p in patients) p['id']: p};
  final trouvees = <_Fiche>[];
  for (final f in factures) {
    if (f['statut'] == 'archive') continue;
    final date = '${f['date'] ?? ''}';
    if (f['assureur'] == null || f['assureur'] == '' || f['assureur'] != sous['assureur'] || date.isEmpty || (date.length >= 10 ? date.substring(0, 10) : date).compareTo(jour) < 0) continue;
    final p = parId[f['patientId']];
    final sd = p == null ? null : souscripteurDe(p, couvertures, souscripteurs, date);
    if (sd != null && sd['id'] == sous['id']) trouvees.add(f);
  }
  trouvees.sort((a, b) => '${a['date']}'.compareTo('${b['date']}'));
  return trouvees.firstOrNull;
}

/// Ce que `assPoserGarantie` rend : un refus nommé, ou la version à ÉCRIRE (`fiche`, nulle en essai), avec la version remplacée (`ancienne`) et le rang de la nouvelle.
class AssPoseGarantie {
  const AssPoseGarantie.refus(String this.code, String this.motif, String this.geste)
      : ok = false,
        ancienne = null,
        version = null,
        fiche = null;
  const AssPoseGarantie.ok({this.ancienne, required int this.version, this.fiche}) : ok = true, code = null, motif = null, geste = null;
  final bool ok;
  final String? code, motif, geste;
  final _Fiche? ancienne, fiche;
  final int? version;
}

/// `PR.poserGarantie(spec)`. [spec] : `{souscripteurId, categorie, libelle, taux, plafond, unitePlafond, dateEffet, sansDate?, source?, motif?, code?}`. `sansDate` n'est admis que pour la
/// PREMIÈRE ligne d'une série (la grille d'une convention saisie d'un bloc : « depuis l'origine », aucune date n'est inventée). [champs] : traces posées sur la fiche (lot d'import).
AssPoseGarantie assPoserGarantie(
  Map<String, Object?> spec, {
  required List<_Fiche> souscripteurs,
  required List<_Fiche> garanties,
  required Iterable<_Fiche> factures,
  required Iterable<_Fiche> patients,
  required List<_Fiche> couvertures,
  bool essai = false,
  Map<String, Object?> champs = const {},
}) {
  AssPoseGarantie refus(String code, String motif, String geste) => AssPoseGarantie.refus(code, motif, geste);
  final sous = souscripteurs.where((s) => s['id'] == spec['souscripteurId']).firstOrNull;
  if (sous == null || sous['statut'] == 'archive') {
    return refus('SOUSCRIPTEUR_INCONNU', 'aucun souscripteur actif ne porte cette identité', 'Choisissez un souscripteur connu (écran « Souscripteurs ») ou importez-le d’abord.');
  }
  if (!assCategoriesGarantie.any((c) => c.$1 == spec['categorie'])) {
    return refus('CATEGORIE_INCONNUE', 'la catégorie « ${spec['categorie']} » n’est pas une catégorie de garantie', 'Choisissez une catégorie de la liste.');
  }
  final libelle = '${spec['libelle'] ?? ''}'.trim();
  if (libelle.isEmpty) {
    return refus('GARANTIE_SANS_LIBELLE', 'la garantie n’a pas de libellé : la série ne se distinguerait pas des autres garanties de la catégorie', 'Saisissez le libellé de la garantie.');
  }
  final t = spec['taux'];
  final taux = t == null || t == '' ? double.nan : (t is num ? t.toDouble() : (double.tryParse('$t') ?? double.nan));
  if (!taux.isFinite || taux < 0 || taux > 100) {
    return refus('TAUX_INVALIDE', 'le taux doit être un nombre de 0 à 100', 'Saisissez un pourcentage entre 0 et 100.');
  }
  final pl = spec['plafond'];
  final double? plafond = pl == null || pl == '' ? null : (pl is num ? pl.toDouble() : (double.tryParse('$pl') ?? double.nan));
  if (plafond != null && (!plafond.isFinite || plafond < 0 || plafond.floorToDouble() != plafond)) {
    return refus('PLAFOND_INVALIDE', 'le plafond doit être un montant entier de francs, zéro ou plus', 'Saisissez un montant entier, ou laissez vide pour « sans plafond ».');
  }
  final unite = plafond == null ? null : (spec['unitePlafond'] == null || spec['unitePlafond'] == '' ? null : '${spec['unitePlafond']}');
  if (plafond != null && !assUnitesPlafond.containsKey(unite)) {
    return refus('UNITE_PLAFOND_REQUISE', 'un plafond se dit toujours « par quoi » (acte, jour, an…)', 'Choisissez l’unité du plafond.');
  }
  final sansDate = spec['sansDate'] == true;
  final de = '${spec['dateEffet'] ?? ''}';
  final jour = sansDate ? null : (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(de) ? de : '');
  if (!sansDate && (jour == null || jour.isEmpty)) {
    return refus('DATE_EFFET_REQUISE', 'la date d’effet est obligatoire : sans elle, la nouvelle version ne se distinguerait pas de l’ancienne sur les pièces déjà émises', 'Saisissez la date à laquelle la garantie change.');
  }
  final rows = assVersionsGarantie([for (final g in garanties) if (g['statut'] != 'archive') g], sous['id'], spec['categorie'], libelle);
  if (sansDate) {
    if (rows.isNotEmpty) {
      return refus('SERIE_EXISTANTE', 'la garantie « $libelle » existe déjà pour ce souscripteur : elle ne se redéfinit pas « depuis l’origine »', 'Posez une nouvelle version avec sa date d’effet.');
    }
  } else {
    final j = jour!;
    final meme = rows.where((g) => '${g['dateEffet'] ?? ''}' == j).firstOrNull;
    final enForce = garantiesEnVigueur(rows, j).firstOrNull;
    final identique = enForce != null &&
        (enForce['taux'] as num?)?.toDouble() == taux &&
        (enForce['plafond'] == null ? null : (enForce['plafond'] as num).toDouble()) == plafond &&
        (plafond == null || enForce['unitePlafond'] == unite);
    if (identique) {
      return refus('GARANTIE_INCHANGEE', 'la garantie « $libelle » porte déjà ce taux et ce plafond à cette date', 'Rien à faire : aucune version n’est créée.');
    }
    if (meme != null) {
      return refus('VERSION_MEME_DATE', 'une version de « $libelle » prend déjà effet le ${dateFR(assDate(j))} avec d’autres valeurs : une version ne se réécrit pas', 'Choisissez une autre date d’effet.');
    }
    final plusRecente = rows.where((g) => '${g['dateEffet'] ?? ''}'.compareTo(j) > 0).firstOrNull;
    if (plusRecente != null) {
      return refus('VERSION_ANTERIEURE',
          'une version plus récente de « $libelle » prend effet le ${dateFR(assDate(plusRecente['dateEffet']))} : on ne glisse pas une version dans le passé d’une série', 'Choisissez une date d’effet postérieure à la dernière version.');
    }
    final fac = assFactureSousGrille(sous, j, factures: factures, patients: patients, couvertures: couvertures, souscripteurs: souscripteurs);
    if (fac != null) {
      return refus('FACTURE_DEJA_EMISE', 'la facture ${fac['numero']} du ${dateFR(assDate(fac['date']))} a été émise sous la grille de ce souscripteur : une pièce émise garde son taux',
          'Choisissez une date d’effet postérieure à la dernière facture émise (${dateFR(assDate(fac['date']))}).');
    }
  }
  final ancienne = rows.isEmpty ? null : (garantiesEnVigueur(rows, jour ?? '9999-12-31').firstOrNull ?? rows.last);
  if (essai) return AssPoseGarantie.ok(ancienne: ancienne, version: rows.length + 1);
  final fiche = <String, Object?>{
    'souscripteurId': sous['id'],
    'assureur': sous['assureur'],
    'code': spec['code'] ?? (rows.isNotEmpty ? rows.first['code'] : null),
    'libelle': libelle,
    'categorie': spec['categorie'],
    'taux': _nombre(taux),
    'plafond': plafond == null ? null : _nombre(plafond),
    'unitePlafond': unite,
    'zone': (rows.isNotEmpty ? rows.first['zone'] : null) ?? 'Bénin',
    'dateEffet': sansDate ? null : jour,
    'version': rows.length + 1,
    'motif': spec['motif'],
    'source': spec['source'],
    ...champs,
  };
  return AssPoseGarantie.ok(ancienne: ancienne, version: rows.length + 1, fiche: fiche);
}

num _nombre(double x) => x == x.truncateToDouble() ? x.toInt() : x;
