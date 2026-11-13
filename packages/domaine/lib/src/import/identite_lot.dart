/// L'IDENTITÉ D'UN LOT D'IMPORT, tirée de son CONTENU (lot IDEM, décisions de la Direction du 13/11/2026, section V).
///
/// Le même inventaire importé par deux fileuls, ou deux fois par le même, est le MÊME lot : la mère le confirme UNE fois, le second fileul l'adopte, aucune fiche n'est écrite ni
/// comptée deux fois. Pour cela, l'identité ne dépend ni du fileul, ni du moment, ni du nom du fichier, ni de son format (un classeur et un CSV du même inventaire donnent la même
/// identité) : c'est l'empreinte SHA-256 du jeu et de ses lignes NORMALISÉES (cellules rognées, espaces insécables ramenés à l'espace, nombres entiers sans décimale, lignes finales
/// vides retirées, en-têtes sans accent ni casse). Une seule cellule qui change, et c'est un AUTRE lot. L'empreinte CRC-32 du fichier (consignée au lot, parité avec la maquette) ne sert
/// pas : 32 bits ne suffisent pas à dire « le même fichier » sans risque de collision.
///
/// La SÉRIE d'un lot dérive de son identité : c'est elle qui donne aux fiches d'un lot des identifiants identiques chez tous les postes (`<COL>-<série>-<rang>`). Une nouvelle TENTATIVE
/// (le même fichier réimporté après une annulation ou un refus, quand des fiches archivées portent déjà la série précédente) prend un suffixe `T<n>` : une fiche archivée n'est jamais
/// réutilisée, un identifiant n'est jamais attribué deux fois.
library;

import 'dart:convert';

import '../fichiers/sha256.dart';

/// La demande dont une fiche est née (série des identifiants, la même chez le fileul et chez la mère).
const String champSerieDemande = 'serieDemande';

/// LOT IDEM : l'identité de CONTENU du lot dont une fiche est née (posée sur chaque fiche d'un lot écrit par une demande, lot d'import compris).
const String champIdentiteLot = 'identiteLot';

/// LOT IDEM : la demande que la mère a traitée pour écrire ce lot (ou consigner ce refus). Elle distingue une CONFIRMATION (la demande qui a écrit) d'une ADOPTION (une autre demande,
/// même lot) et empêche de consigner deux fois le refus d'une même demande rejouée.
const String champDemandeOrigine = 'demandeOrigine';

String _cellule(Object? v) {
  if (v == null) return '';
  if (v is double && v.isFinite && v == v.truncateToDouble()) return v.toInt().toString();
  if (v is DateTime) return v.toIso8601String().substring(0, 10);
  return '$v'.replaceAll(RegExp('[  ]'), ' ').trim();
}

String _entete(Object? v) {
  var t = _cellule(v).toLowerCase();
  const de = 'àâäáãåçéèêëíìîïñóòôöõúùûüýÿ', vers = 'aaaaaaceeeeiiiinooooouuuuyy';
  for (var i = 0; i < de.length; i++) {
    t = t.replaceAll(de[i], vers[i]);
  }
  return t.replaceAll(RegExp(r'\s+'), ' ');
}

/// L'identité de contenu du fichier [lignes] (la première ligne est l'en-tête) pour le jeu [jeuId] : 64 caractères hexadécimaux.
String identiteLotImport(String jeuId, List<List<Object?>> lignes) {
  final tampon = StringBuffer('$jeuId\n');
  for (var r = 0; r < lignes.length; r++) {
    final cellules = [for (final c in lignes[r]) r == 0 ? _entete(c) : _cellule(c)];
    while (cellules.isNotEmpty && cellules.last.isEmpty) {
      cellules.removeLast();
    }
    // Une ligne entièrement vide n'est pas une ligne du fichier (le moteur l'ignore aussi) : elle ne change pas le lot.
    if (cellules.isEmpty) continue;
    tampon
      ..write(cellules.join('\u001f'))
      ..write('\n');
  }
  return sha256Octets(utf8.encode(tampon.toString()));
}

/// La série des identifiants d'un lot : `IMP` et les 20 premiers caractères de l'identité ; `T<n>` à partir de la deuxième tentative.
String serieDuLotImport(String identite, [int tentative = 1]) => 'IMP${identite.substring(0, 20)}${tentative > 1 ? 'T$tentative' : ''}';

/// Cette série est-elle bien celle de cette identité (quelle que soit la tentative) ?
bool serieEstDeLIdentite(String serie, String identite) {
  final base = serieDuLotImport(identite);
  if (serie == base) return true;
  return RegExp('^${RegExp.escape(base)}T[0-9]+\$').hasMatch(serie);
}
