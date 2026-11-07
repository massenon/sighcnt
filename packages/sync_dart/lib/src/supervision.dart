/// SUPERVISION DU POSTE MÈRE (spec §13) : ce que le « PC du serveur local » doit surveiller seul — base, disque,
/// sauvegarde, retard des postes, liaison au relais, horloges, conflits. Chaque contrôle rend un état NOMMÉ
/// (`ok` · `attention` · `alerte` · `inconnu`) et une phrase lisible : jamais un voyant muet, jamais un « inconnu » qui se
/// fait passer pour « ok ». Les seuils sont des PROPOSITIONS (à valider sur le matériel réel de la clinique).
library;

import 'dart:io';

import 'commun.dart';
import 'mere.dart';

class Seuils {
  const Seuils({
    this.disqueAttentionOctets = 10 * 1024 * 1024 * 1024,
    this.disqueAlerteOctets = 2 * 1024 * 1024 * 1024,
    this.sauvegardeAttentionHeures = 26,
    this.sauvegardeAlerteHeures = 50,
    this.posteSilenceAttentionMin = 30,
    this.posteSilenceAlerteMin = 240,
    this.posteRetardOperations = 500,
    this.relaisRetardAttention = 50,
    this.relaisRetardAlerte = 2000,
  });
  final int disqueAttentionOctets;
  final int disqueAlerteOctets;
  final int sauvegardeAttentionHeures;
  final int sauvegardeAlerteHeures;
  final int posteSilenceAttentionMin;
  final int posteSilenceAlerteMin;
  final int posteRetardOperations;
  final int relaisRetardAttention;
  final int relaisRetardAlerte;
}

Map<String, Object?> _controle(String nom, String etat, String detail, [Object? valeur]) =>
    {'nom': nom, 'etat': etat, 'detail': detail, 'valeur': ?valeur};

/// Octets libres du disque qui porte le dossier courant, ou `null` si la plateforme ne le dit pas.
Future<int?> octetsLibres() async {
  try {
    if (Platform.isWindows) {
      final r = await Process.run('powershell', ['-NoProfile', '-Command', '[IO.DriveInfo]::new((Get-Location).Drive.Name).AvailableFreeSpace']);
      return int.tryParse('${r.stdout}'.trim());
    }
    final r = await Process.run('df', ['-Pk', '.']);
    final lignes = '${r.stdout}'.trim().split('\n');
    if (lignes.length < 2) return null;
    final disponible = int.tryParse(lignes.last.trim().split(RegExp(r'\s+'))[3]);
    return disponible == null ? null : disponible * 1024;
  } catch (_) {
    return null;
  }
}

String _taille(int o) => o >= 1 << 30 ? '${(o / (1 << 30)).toStringAsFixed(1)} Go' : '${(o / (1 << 20)).toStringAsFixed(0)} Mo';

Future<List<Map<String, Object?>>> controlesMere(Mere m, {Seuils seuils = const Seuils(), int? disqueLibre}) async {
  final out = <Map<String, Object?>>[];
  final base = m.base;
  final maintenant = maintenantMs();

  // 1. base de données
  final t0 = DateTime.now();
  try {
    await base.select('SELECT 1 AS un');
    final ms = DateTime.now().difference(t0).inMilliseconds;
    out.add(_controle('Base de données', ms > 1000 ? 'attention' : 'ok', '${base.dialecte == 'pg' ? 'PostgreSQL' : 'SQLite'} répond en $ms ms.', ms));
  } catch (e) {
    out.add(_controle('Base de données', 'alerte', 'La base ne répond pas : $e'));
  }

  // 2. espace disque
  final libre = disqueLibre ?? await octetsLibres();
  if (libre == null) {
    out.add(_controle('Espace disque', 'inconnu', 'Non mesurable sur cette plateforme.'));
  } else {
    final etat = libre < seuils.disqueAlerteOctets ? 'alerte' : (libre < seuils.disqueAttentionOctets ? 'attention' : 'ok');
    out.add(_controle('Espace disque', etat, '${_taille(libre)} libres.', libre));
  }

  // 3. sauvegarde quotidienne
  final derniere = await base.metaInt('derniere_sauvegarde');
  if (derniere == 0) {
    out.add(_controle('Sauvegarde', 'alerte', 'Aucune sauvegarde n\'a jamais été faite.'));
  } else {
    final h = (maintenant - derniere) / 3600000;
    final etat = h > seuils.sauvegardeAlerteHeures ? 'alerte' : (h > seuils.sauvegardeAttentionHeures ? 'attention' : 'ok');
    out.add(_controle('Sauvegarde', etat, 'Dernière sauvegarde il y a ${h.toStringAsFixed(1)} h.', derniere));
  }

  // 4. postes : silence et retard de synchronisation
  final seq = await m.seqMax();
  for (final a in await base.select("SELECT uuid,etiquette,role,dernier_contact,dernier_seq,derive_ms FROM appareils WHERE etat='actif' AND role<>'mobile' ORDER BY etiquette")) {
    final nom = '${a['etiquette'] ?? ''}'.isEmpty ? '${a['uuid']}' : '${a['etiquette']}';
    final contact = a['dernier_contact'] as int?;
    final retard = seq - (a['dernier_seq'] as int);
    if (contact == null) {
      out.add(_controle('Poste « $nom »', 'attention', 'Jamais vu depuis son appairage.'));
      continue;
    }
    final silence = (maintenant - contact) / 60000;
    var etat = 'ok';
    var detail = 'Vu il y a ${silence.toStringAsFixed(0)} min, retard ${retard.clamp(0, 1 << 30)} opération(s).';
    if (silence > seuils.posteSilenceAlerteMin) {
      etat = 'alerte';
      detail = 'Silencieux depuis ${(silence / 60).toStringAsFixed(1)} h — poste éteint, hors réseau ou en panne ?';
    } else if (silence > seuils.posteSilenceAttentionMin || retard > seuils.posteRetardOperations) {
      etat = 'attention';
    }
    if ((a['derive_ms'] as int) > 2 * 60 * 1000) {
      etat = etat == 'alerte' ? 'alerte' : 'attention';
      detail += ' Horloge à vérifier (dérive ${((a['derive_ms'] as int) / 60000).toStringAsFixed(0)} min).';
    }
    out.add(_controle('Poste « $nom »', etat, detail));
  }

  // 5. liaison au relais en ligne
  if (!m.pont.actif) {
    out.add(_controle('Relais en ligne', 'inconnu', 'Aucun relais configuré : pas de copie hors site ni de mobiles.'));
  } else {
    final retard = seq - await base.metaInt('rep_seq');
    final dernierOk = await base.metaInt('relais_dernier_ok');
    final silence = dernierOk == 0 ? null : (maintenant - dernierOk) / 60000;
    var etat = retard > seuils.relaisRetardAlerte ? 'alerte' : (retard > seuils.relaisRetardAttention ? 'attention' : 'ok');
    var detail = '$retard opération(s) pas encore répliquées (chiffrées) vers le relais.';
    if (silence != null && silence > 5) {
      etat = 'alerte';
      detail += ' Aucun échange réussi depuis ${silence.toStringAsFixed(0)} min : Internet ou relais hors service.';
    }
    out.add(_controle('Relais en ligne', etat, detail, retard));
  }

  // 6. enveloppes altérées ou manquantes, appareils bloqués
  final bloques = await base.select("SELECT k FROM meta WHERE k LIKE 'bloque:%' AND v<>''");
  out.add(bloques.isEmpty
      ? _controle('Intégrité des enveloppes', 'ok', 'Aucune enveloppe altérée ni manquante.')
      : _controle('Intégrité des enveloppes', 'alerte', '${bloques.length} appareil(s) bloqué(s) : enveloppe altérée ou rang manquant — à examiner à la console.', bloques.length));

  // 7. conflits à arbitrer
  final conflits = (await base.select("SELECT COUNT(*) AS n FROM conflits WHERE etat='ouvert'")).first['n'] as int;
  out.add(_controle('Conflits à régulariser', conflits == 0 ? 'ok' : (conflits > 20 ? 'alerte' : 'attention'), conflits == 0 ? 'Aucun conflit ouvert.' : '$conflits conflit(s) attendent un arbitrage.', conflits));

  // 8. erreurs internes récentes (24 h)
  final erreurs = (await base.select("SELECT COUNT(*) AS n FROM evenements WHERE niveau='erreur' AND quand>?", [maintenant - 24 * 3600 * 1000])).first['n'] as int;
  out.add(_controle('Erreurs internes (24 h)', erreurs == 0 ? 'ok' : (erreurs > 10 ? 'alerte' : 'attention'), erreurs == 0 ? 'Aucune erreur interne.' : '$erreurs erreur(s) interne(s) — voir le journal.', erreurs));
  return out;
}

/// Le pire état rencontré : `alerte` > `attention` > `inconnu` > `ok`. Un « inconnu » ne rassure jamais.
String etatGlobal(List<Map<String, Object?>> controles) {
  const ordre = ['ok', 'inconnu', 'attention', 'alerte'];
  var pire = 0;
  for (final c in controles) {
    final i = ordre.indexOf('${c['etat']}');
    if (i > pire) pire = i;
  }
  return ordre[pire];
}
