import 'package:sigh_sync/src/commun.dart';
import 'package:sigh_sync/src/mere.dart';
import 'package:sigh_sync/src/supervision.dart';
import 'package:test/test.dart';

Map<String, Object?> controle(List<Map<String, Object?>> l, String nom) => l.firstWhere((c) => '${c['nom']}'.startsWith(nom));

void main() {
  late Mere m;
  setUp(() async => m = await Mere.creer(ConfigMere(port: 0, dbChemin: ':memory:')));

  test('mère neuve : aucune sauvegarde = ALERTE, jamais un « ok » par défaut ; relais absent = « inconnu »', () async {
    final c = await controlesMere(m, disqueLibre: 100 << 30);
    expect(controle(c, 'Sauvegarde')['etat'], 'alerte');
    expect(controle(c, 'Relais en ligne')['etat'], 'inconnu');
    expect(controle(c, 'Base de données')['etat'], 'ok');
    expect(controle(c, 'Espace disque')['etat'], 'ok');
    expect(etatGlobal(c), 'alerte');
  });

  test('l\'état global est le PIRE des contrôles — un « inconnu » ne rassure pas', () {
    Map<String, Object?> c(String e) => {'nom': 'x', 'etat': e};
    expect(etatGlobal([c('ok'), c('ok')]), 'ok');
    expect(etatGlobal([c('ok'), c('inconnu')]), 'inconnu');
    expect(etatGlobal([c('inconnu'), c('attention'), c('ok')]), 'attention');
    expect(etatGlobal([c('ok'), c('attention'), c('alerte')]), 'alerte');
  });

  test('sauvegarde : récente = ok ; 30 h = attention ; 60 h = alerte', () async {
    Future<String> etat(int heures) async {
      await m.base.poserMeta('derniere_sauvegarde', maintenantMs() - heures * 3600 * 1000);
      return '${controle(await controlesMere(m, disqueLibre: 100 << 30), 'Sauvegarde')['etat']}';
    }

    expect(await etat(3), 'ok');
    expect(await etat(30), 'attention');
    expect(await etat(60), 'alerte');
  });

  test('disque : seuils d\'attention (10 Go) et d\'alerte (2 Go) ; non mesurable = inconnu', () async {
    Future<String> etat(int octets) async => '${controle(await controlesMere(m, disqueLibre: octets), 'Espace disque')['etat']}';
    expect(await etat(50 << 30), 'ok');
    expect(await etat(5 << 30), 'attention');
    expect(await etat(1 << 30), 'alerte');
  });

  test('postes : silencieux depuis des heures = alerte nommée ; horloge dérivée = attention', () async {
    await m.base.exec("INSERT INTO appareils(uuid,etiquette,role,etat,dernier_contact,dernier_seq,derive_ms) VALUES('p1','Caisse','fileul','actif',?,0,0)", [maintenantMs() - 5 * 3600 * 1000]);
    await m.base.exec("INSERT INTO appareils(uuid,etiquette,role,etat,dernier_contact,dernier_seq,derive_ms) VALUES('p2','Accueil','fileul','actif',?,0,600000)", [maintenantMs() - 60 * 1000]);
    await m.base.exec("INSERT INTO appareils(uuid,etiquette,role,etat) VALUES('p3','Neuf','fileul','actif')");
    await m.base.exec("INSERT INTO appareils(uuid,etiquette,role,etat,dernier_contact) VALUES('m1','Mobile','mobile','actif',1)");
    final c = await controlesMere(m, disqueLibre: 100 << 30);
    expect(controle(c, 'Poste « Caisse »')['etat'], 'alerte');
    expect('${controle(c, 'Poste « Caisse »')['detail']}', contains('Silencieux'));
    expect(controle(c, 'Poste « Accueil »')['etat'], 'attention');
    expect('${controle(c, 'Poste « Accueil »')['detail']}', contains('Horloge'));
    expect(controle(c, 'Poste « Neuf »')['etat'], 'attention');
    expect(c.where((x) => '${x['nom']}'.contains('Mobile')), isEmpty, reason: 'les mobiles se supervisent par le relais, pas par silence');
  });

  test('appareils bloqués, conflits et erreurs internes remontent', () async {
    await m.base.poserMeta('bloque:u9', 'auth');
    await m.base.exec("INSERT INTO conflits(collection,fiche,champ,a,b,appareil) VALUES('patients','p','tel','1','2','u')");
    await m.evenement('erreur', 'test', 'panne simulée');
    final c = await controlesMere(m, disqueLibre: 100 << 30);
    expect(controle(c, 'Intégrité')['etat'], 'alerte');
    expect(controle(c, 'Conflits')['etat'], 'attention');
    expect(controle(c, 'Erreurs internes')['etat'], 'attention');
  });
}
