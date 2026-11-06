/// LA COPIE CONSOLIDÉE DE LA MÈRE (PRD relais consultable, option B) : l'état fusionné des collections de famille A, déposé chiffré dans le sens `copie` du relais
/// (appareil `mere`). UNE enveloppe par tour qui a des changements, portant un lot `{lot: [{collection, fiche, data, archive}, …]}` : le panneau du relais la
/// déchiffre dans le navigateur. Seule la différence part (empreinte par fiche), rang contigu, charge persistée avant dépôt (un SIGKILL ne perd ni ne duplique
/// rien : le dépôt rejoué est idempotent par id). Rien n'est supprimé (RG-14) : un archivage est un champ.
library;

import 'dart:convert';

import 'package:sigh_domaine/sigh_domaine.dart';

import 'commun.dart';
import 'mere.dart';

class CopieMere {
  CopieMere(this.mere);
  final Mere mere;
  bool _prete = false;

  static Set<String> get collections => {for (final e in famillesPair.entries) if (e.value == 'A') e.key};

  Future<void> _preparer() async {
    if (_prete) return;
    await mere.verrou.executer(() async {
      await mere.base.exec('CREATE TABLE IF NOT EXISTS copie_mere_sortie (n BIGINT PRIMARY KEY, enveloppe TEXT, depose INTEGER DEFAULT 0)');
      await mere.base.exec('CREATE TABLE IF NOT EXISTS copie_mere_etat (cle TEXT PRIMARY KEY, empreinte TEXT)');
    });
    _prete = true;
  }

  /// Prépare l'enveloppe des fiches nouvelles ou changées depuis le dernier tour.
  Future<void> preparer() async {
    final base = mere.base;
    final etat = etatPair(await mere.pair.ops(), droits: mere.pair.droits);
    final lot = <Map<String, Object?>>[];
    final empreintes = <String, String>{};
    final connues = {for (final r in await mere.verrou.executer(() => base.select('SELECT cle,empreinte FROM copie_mere_etat'))) r['cle'] as String: r['empreinte'] as String};
    for (final e in etat.fiches.entries) {
      final i = e.key.indexOf('/');
      if (i < 0 || !collections.contains(e.key.substring(0, i))) continue;
      final charge = {'collection': e.key.substring(0, i), 'fiche': e.key.substring(i + 1), 'data': e.value['data'], 'archive': e.value['archive'] == true};
      final texte = enJson(charge);
      if (connues[e.key] == texte) continue;
      lot.add(charge);
      empreintes[e.key] = texte;
    }
    if (lot.isEmpty) return;
    await mere.verrou.executer(() => base.tx(() async {
          final n = await base.metaInt('copie_n') + 1;
          await base.poserMeta('copie_n', n);
          final env = await mere.pont.env.chiffrer({'lot': lot}, id: 'copie-mere-$n', appareil: 'mere', dir: 'copie', n: n);
          await base.exec('INSERT INTO copie_mere_sortie(n,enveloppe,depose) VALUES(?,?,0)', [n, enJson(env)]);
          for (final e in empreintes.entries) {
            await base.exec('INSERT INTO copie_mere_etat(cle,empreinte) VALUES(?,?) ON CONFLICT(cle) DO UPDATE SET empreinte=excluded.empreinte', [e.key, e.value]);
          }
        }));
  }

  Future<void> expedier() async {
    final base = mere.base;
    final lignes = await mere.verrou.executer(() => base.select('SELECT n,enveloppe FROM copie_mere_sortie WHERE depose=0 ORDER BY n'));
    for (final r in lignes) {
      await mere.pont.rel('POST', '/depot', {'enveloppe': jsonDecode(r['enveloppe'] as String)});
      await mere.verrou.executer(() => base.exec('UPDATE copie_mere_sortie SET depose=1 WHERE n=?', [r['n']]));
    }
  }

  Future<void> tour() async {
    await _preparer();
    await preparer();
    await expedier();
  }
}
