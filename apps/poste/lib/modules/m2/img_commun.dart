import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../kit/kit.dart';

/// Poste d'imagerie médicale (M2) : ce que partagent le registre des demandes, le poste et la galerie des clichés.

/// `U.badge(label, tone)` : les tons de la maquette (`success`, `warning`, `info`, `navy`, `neutral`) → ceux du kit.
TonSigh tonImagerie(String ton) => switch (ton) {
      'success' => TonSigh.succes,
      'warning' => TonSigh.attention,
      'info' => TonSigh.info,
      'navy' => TonSigh.navy,
      'danger' => TonSigh.danger,
      _ => TonSigh.neutre,
    };

/// Le pictogramme Lucide d'une modalité (`icone` de `D.IMAGERIE.MODALITES`).
IconData iconeModalite(String nom) => switch (nom) {
      'bone' => LucideIcons.bone,
      'ribbon' => LucideIcons.ribbon,
      'radiation' => LucideIcons.radiation,
      'magnet' => LucideIcons.magnet,
      _ => LucideIcons.scanLine,
    };

const styleMono = TextStyle(
    fontFamily: 'LiberationMono', fontSize: 12, color: JetonsShell.slate700);

String texteDate(Object? v) {
  final d = DateTime.tryParse('${v ?? ''}');
  return d == null ? '' : dateFR(d.toLocal());
}

num nombreImg(Object? v) => v is num ? v : (num.tryParse('${v ?? ''}') ?? 0);

/// Le catalogue d'examens (`examensImagerie`), tel que le magasin le tient.
List<Fiche> catalogueExamens(Magasin m) =>
    m.collection('examensImagerie').actives;

/// `optionsPatients()` : `code — nom prénom`, triés par code (tri naturel de la maquette).
List<OptionChamp> optionsPatientsImagerie(Magasin m) => [
      for (final p in trierPar(m.collection('patients').actives, (p) => p['code']))
        OptionChamp('${p['code']}', '${p['code']} — ${p['nom']} ${p['prenom']}')
    ];

/// `D.tarifPrix(code, assure)` : le catalogue tarifaire est lu au magasin (`catalogueTarifs`), puis aux actes rapprochés d'une grille
/// (`actes` : `codeTarif` + prix non assuré / assuré). Aucun prix n'est inventé : sans entrée, le code est ABSENT et la demande est refusée en le nommant.
PrixImagerie Function(String code, bool assure) prixDepuisMagasin(Magasin m) {
  final tarifs = <String, Fiche>{};
  for (final a in m.collection('actes').actives) {
    final c = a['codeTarif'];
    if (c != null && a['prixNonAssure'] != null) tarifs.putIfAbsent('$c', () => a);
  }
  for (final t in m.collection('catalogueTarifs').actives) {
    tarifs['${t['code']}'] = t;
  }
  final examens = catalogueExamens(m);
  return (code, assure) {
    final ex = examens.where((x) => x['code'] == code).firstOrNull;
    final cle = '${(ex?['tarifCode'] ?? '') == '' ? code : ex!['tarifCode']}';
    return prixTarif(tarifs[cle], assure);
  };
}

int _serie = 0;

/// Un identifiant `<PREFIXE><horodatage><rang>` unique pour une fiche créée par la fabrique d'ouverture.
String nouvelIdImagerie(String prefixe) =>
    '$prefixe${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${(_serie++).toRadixString(36)}';
