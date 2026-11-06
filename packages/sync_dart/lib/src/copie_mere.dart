/// LA COPIE CONSOLIDÉE DE LA MÈRE (PRD relais consultable, option B) : l'état fusionné des collections de famille A, déposé chiffré dans le sens `copie` du relais
/// (appareil `mere`). UNE enveloppe par tour qui a des changements, portant un lot `{lot: [{collection, fiche, data, archive}, …]}` : le panneau du relais la
/// déchiffre dans le navigateur. Seule la différence part (empreinte par fiche), rang contigu, charge persistée avant dépôt (un SIGKILL ne perd ni ne duplique
/// rien : le dépôt rejoué est idempotent par id). Rien n'est supprimé (RG-14) : un archivage est un champ.
library;

import 'dart:convert';

import 'package:sigh_domaine/sigh_domaine.dart';

import 'commun.dart';
import 'mere.dart';
import 'ordre_copie.dart';

class CopieMere {
  CopieMere(this.mere);
  final Mere mere;
  bool _prete = false;

  static const int fichesParEnveloppe = 500;

  static Set<String> get collections => {for (final e in famillesPair.entries) if (e.value == 'A') e.key};

  Future<void> _preparer() async {
    if (_prete) return;
    await mere.verrou.executer(() async {
      await mere.base.exec('CREATE TABLE IF NOT EXISTS copie_mere_sortie (n BIGINT PRIMARY KEY, enveloppe TEXT, depose INTEGER DEFAULT 0)');
      await mere.base.exec('CREATE TABLE IF NOT EXISTS copie_mere_etat (cle TEXT PRIMARY KEY, empreinte TEXT)');
      await mere.base.exec('CREATE TABLE IF NOT EXISTS copie_mere_ops (id TEXT PRIMARY KEY, cle TEXT)');
      await mere.base.exec('CREATE INDEX IF NOT EXISTS copie_mere_ops_cle ON copie_mere_ops(cle)');
      await mere.base.exec('CREATE TABLE IF NOT EXISTS copie_mere_a_faire (cle TEXT PRIMARY KEY)');
    });
    _prete = true;
  }

  /// Bornes d'UN tour : le verrou de la mère est tenu pendant le calcul, un premier tour sur 200 000 opérations ne doit pas bloquer les autres gestes. Le travail se
  /// répartit sur plusieurs tours : indexation de [opsParTour] opérations au plus, puis recalcul de [fichesParTour] fiches au plus.
  static const int opsParTour = 20000, fichesParTour = 1500;

  /// Vrai tant qu'il reste des opérations à indexer ou des fiches à recalculer.
  Future<bool> enRetard() async =>
      (await mere.base.select('SELECT 1 AS x FROM copie_mere_a_faire LIMIT 1')).isNotEmpty ||
      (await mere.base.select('SELECT 1 AS x FROM pair_ops p LEFT JOIN copie_mere_ops c ON c.id=p.id WHERE c.id IS NULL LIMIT 1')).isNotEmpty;

  /// Prépare l'enveloppe des fiches nouvelles ou changées. INCRÉMENTAL : seules les opérations nouvelles (anti-jointure sur l'index `copie_mere_ops`, tenu ici sans
  /// toucher au pont pair) désignent les fiches à recalculer, chacune depuis SES opérations seules (famille A), et seulement une fois TOUTES les opérations connues
  /// indexées (aucune version intermédiaire déposée). Chaque version porte son `ordre` : la page retient la plus informée, quel que soit l'ordre de lecture.
  Future<void> preparer() async {
    final base = mere.base;
    await mere.verrou.executer(() async {
      final neuves = await base.select('SELECT p.id AS id, p.json AS json FROM pair_ops p LEFT JOIN copie_mere_ops c ON c.id=p.id WHERE c.id IS NULL LIMIT $opsParTour');
      if (neuves.isNotEmpty) {
        await base.tx(() async {
          for (final r in neuves) {
            final j = (jsonDecode(r['json'] as String) as Map).cast<String, Object?>();
            final cle = '${j['collection']}/${j['fiche']}';
            await base.exec('INSERT INTO copie_mere_ops(id,cle) VALUES(?,?)', [r['id'], cle]);
            if (collections.contains('${j['collection']}')) await base.exec('INSERT INTO copie_mere_a_faire(cle) VALUES(?) ON CONFLICT(cle) DO NOTHING', [cle]);
          }
        });
        if (neuves.length >= opsParTour) return; // il en reste : le tour suivant continue l'indexation
      }
      final aFaire = [for (final r in await base.select('SELECT cle FROM copie_mere_a_faire LIMIT $fichesParTour')) r['cle'] as String];
      if (aFaire.isEmpty) return;
      final lot = <Map<String, Object?>>[];
      final empreintes = <String, String>{};
      await base.tx(() async {
        for (final cle in aFaire) {
          await base.exec('DELETE FROM copie_mere_a_faire WHERE cle=?', [cle]);
          final i = cle.indexOf('/');
          final ops = [
            for (final r in await base.select('SELECT p.json AS json, p.seq AS seq FROM pair_ops p JOIN copie_mere_ops c ON c.id=p.id WHERE c.cle=?', [cle]))
              OperationPair.depuisJson({
                ...(jsonDecode(r['json'] as String) as Map).cast<String, Object?>(),
                if (r['seq'] != null) 'seq': (r['seq'] as num).toInt(),
              })
          ];
          final charge = chargeCopieDeFiche(cle.substring(0, i), cle.substring(i + 1), ops, droits: mere.pair.droits);
          if (charge == null) continue;
          final texte = enJson(contenuCopie(charge));
          final connue = await base.select('SELECT empreinte FROM copie_mere_etat WHERE cle=?', [cle]);
          if (connue.isNotEmpty && connue.first['empreinte'] == texte) continue;
          lot.add(charge);
          empreintes[cle] = texte;
        }
        if (lot.isEmpty) return;
        // des lots de FICHES_PAR_ENVELOPPE au plus : une enveloppe de 18 000 fiches serait déchiffrée d'un bloc par la page (mémoire, gel de l'interface)
        for (var d = 0; d < lot.length; d += fichesParEnveloppe) {
          final tranche = lot.sublist(d, d + fichesParEnveloppe > lot.length ? lot.length : d + fichesParEnveloppe);
          final n = await base.metaInt('copie_n') + 1;
          await base.poserMeta('copie_n', n);
          final env = await mere.pont.env.chiffrer({'lot': tranche}, id: 'copie-mere-$n', appareil: 'mere', dir: 'copie', n: n);
          await base.exec('INSERT INTO copie_mere_sortie(n,enveloppe,depose) VALUES(?,?,0)', [n, enJson(env)]);
        }
        for (final e in empreintes.entries) {
          await base.exec('INSERT INTO copie_mere_etat(cle,empreinte) VALUES(?,?) ON CONFLICT(cle) DO UPDATE SET empreinte=excluded.empreinte', [e.key, e.value]);
        }
      });
    });
  }

  Future<void> expedier() async {
    final base = mere.base;
    final lignes = await mere.verrou.executer(() => base.select('SELECT n,enveloppe FROM copie_mere_sortie WHERE depose=0 ORDER BY n'));
    for (final r in lignes) {
      await mere.pont.rel('POST', '/depot', {'enveloppe': jsonDecode(r['enveloppe'] as String)});
      await mere.verrou.executer(() => base.exec('UPDATE copie_mere_sortie SET depose=1 WHERE n=?', [r['n']]));
    }
  }

  /// Pour les tests : crée les tables sans lancer un tour complet.
  Future<void> tourPreparer() => _preparer();

  Future<void> tour() async {
    await _preparer();
    await preparer();
    await expedier();
  }
}
