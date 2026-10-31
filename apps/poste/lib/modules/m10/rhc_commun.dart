import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'rha_commun.dart';
import 'rhb_commun.dart';

/// Briques communes aux huit écrans de M10 (C) : badges du personnel, événements et participations, assurance du personnel, rotation sécurité & entretien.
/// Les règles sont dans `packages/domaine/lib/src/rh/rhc_regles.dart` ; ce fichier ne porte que de la mise en page et la lecture du magasin du poste.

/// `K.source(texte)` : « Source : … » sous le tableau, avec l'icône de pièce vérifiée.
Widget rhcSource(String texte) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Row(children: [
      const Icon(LucideIcons.fileCheck2, size: 14, color: JetonsShell.slate400),
      const SizedBox(width: 6),
      Expanded(child: Text('Source : $texte', style: rhbPetit)),
    ]));

/// Les agents ACTIFS du personnel, dans l'ordre de la collection (`personnel()`).
List<Fiche> rhcPersonnel(ContexteEcran c) => rhbActives(c, 'personnel');

/// Un montant en FCFA sans la devise (colonnes de tableau).
String rhcMontant(Object? v) => money(v, avecDevise: false);

/// « août 2026 » depuis « 2026-08 » ; « — » si la période est vide.
String rhcMois(Object? periode) {
  final p = '${periode ?? ''}';
  if (p.isEmpty) return '—';
  final d = DateTime.tryParse('$p-01');
  return d == null ? p : moisAnnee(d);
}

/// `C.dateFR` d'une date « AAAA-MM-JJ » (ou d'un instant ISO) ; texte inchangé si illisible.
String rhcDate(Object? v) {
  final s = '${v ?? ''}';
  if (s.length < 10) return s;
  final d = DateTime.tryParse(s.substring(0, 10));
  return d == null ? s : dateFR(d);
}

/// `RG-12` : une vérification, une consultation, un accès se journalisent SANS passer par l'insertion d'une fiche (qui journaliserait à son tour et
/// doublerait l'entrée). Même forme que `S.journaliserAcces` de la maquette ; le journal est plafonné à 400 entrées.
void rhcJournaliserAcces(ContexteEcran c, {required String action, required String entite, String? reference, String? cible, required String ecran, String? motif, bool trouve = true}) {
  final a = c.magasin.collection('audit');
  a.inserer({
    'id': 'LOG${(a.toutes.length + 1).toString().padLeft(5, '0')}',
    'dateHeure': c.aujourdhui.toIso8601String(),
    'utilisateur': c.utilisateur,
    'action': action,
    'module': 'M10',
    'entite': entite,
    if (reference != null) 'reference': reference,
    if (cible != null) 'cible': cible,
    'ecran': ecran,
    if (motif != null) 'motif': motif,
    'trouve': trouve,
    'poste': c.magasin.poste,
    'succes': true,
  });
  a.plafonner(400);
}

/// Un motif d'archivage se journalise (RG-12) : `archiver` ne le porte pas, comme pour les registres de M14.
void rhcMotifArchivage(ContexteEcran c, String entite, String reference, String motif) =>
    c.magasin.journaliser('Motif d’archivage', 'M10', entite, reference, null, {'motif': motif});

/// `<strong>…</strong>` des messages de confirmation de la maquette → texte brut.
String rhcTexte(String s) => sansBalises(s.replaceAll('<br><br>', ' '));

/// Le contenu d'une cellule « intitulé + détail » (nom 14/20 en 500, détail 12/16).
Widget rhcDeuxLignes(String haut, String bas, {bool monoHaut = false}) =>
    Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(haut,
          overflow: TextOverflow.ellipsis,
          style: monoHaut ? const TextStyle(fontFamily: 'LiberationMono', color: JetonsShell.slate800, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w500) : rhbCorps),
      Text(bas, overflow: TextOverflow.ellipsis, style: rhbPetit),
    ]);

/// Le badge d'un ton de la maquette (`success`, `warning`…).
Widget rhcBadge(String libelle, String ton) => BadgeSigh(libelle, ton: rhbTon(ton));

/// Les valeurs du formulaire d'une fiche existante, nombres en texte (le formulaire saisit du texte).
Map<String, Object?> rhcEnTexte(Fiche f) => {for (final e in f.entries) e.key: e.value is num ? '${e.value}' : e.value};

List<OptionChamp> rhcOptions(Iterable<(String, String)> l) => [for (final o in l) OptionChamp(o.$1, o.$2)];

/// Les agents de la maquette (`optionsEmployes`) — réexport pour les écrans de ce lot.
List<OptionChamp> rhcOptionsAgents(Magasin m) => rhaOptionsEmployes(m);
