<?php

namespace Tests\Feature;

use App\Livewire\Panneau\Opacite as EcranOpacite;
use App\Livewire\Panneau\Sauvegarde;
use App\Models\User;
use App\Relais\Exporteur;
use App\Relais\Opacite;
use App\Relais\Sauvegarde\Entrepot;
use App\Relais\Sauvegarde\Regles;
use App\Relais\Sauvegarde\Reglages;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * LOT 5 (ADR-0007) : la sauvegarde hors site par blocs opaques, sur le VRAI code du relais Laravel. Le contrat est celui du banc (`packages/sync/banc/relais-sauvegarde.js`,
 * scénarios SAUVHS1 à SAUVHS4, rejoués contre ce code par `SIGH_RELAIS=laravel`) ; ici, les garde-fous propres au code PHP.
 */
class SauvegardeHorsSiteTest extends TestCase
{
    use RefreshDatabase;

    private const SECRET = 'secret-mere-test';

    private string $dossier;

    protected function setUp(): void
    {
        parent::setUp();
        $this->dossier = sys_get_temp_dir().'/sigh-sauv-test-'.bin2hex(random_bytes(4));
        config(['relais.secret_mere' => self::SECRET, 'relais.banc' => false, 'relais.sauvegardes_dir' => $this->dossier]);
    }

    protected function tearDown(): void
    {
        if (is_dir($this->dossier)) {
            $it = new \RecursiveIteratorIterator(new \RecursiveDirectoryIterator($this->dossier, \FilesystemIterator::SKIP_DOTS), \RecursiveIteratorIterator::CHILD_FIRST);
            foreach ($it as $f) {
                $f->isDir() ? rmdir($f->getPathname()) : unlink($f->getPathname());
            }
            rmdir($this->dossier);
        }
        parent::tearDown();
    }

    private function mere(): array
    {
        return ['x-mere' => self::SECRET];
    }

    private function poser(string $octets): string
    {
        $id = hash('sha256', $octets);
        $this->call('PUT', '/sauvegarde/bloc/'.$id, [], [], [], ['HTTP_X_MERE' => self::SECRET, 'CONTENT_TYPE' => 'application/octet-stream'], $octets)->assertOk();

        return $id;
    }

    private function alea(string $graine, int $n): string
    {
        $o = '';
        for ($i = 0; strlen($o) < $n; $i++) {
            $o .= hash('sha256', $graine.':'.$i, true);
        }

        return substr($o, 0, $n);
    }

    private function copie(string $graine, int $garder = 2, ?int $date = null, int $taille = 4096): string
    {
        $bloc = $this->poser($this->alea($graine, $taille));
        $manifeste = $this->poser($this->alea('manifeste'.$graine, 600));
        $id = hash('sha256', 'copie'.$graine);
        $this->postJson('/sauvegarde/copie', ['id' => $id, 'type' => 'magasin', 'date' => $date ?? (int) (microtime(true) * 1000), 'garder' => $garder], $this->mere())->assertOk();
        $this->postJson("/sauvegarde/copie/$id/blocs", ['ids' => [$bloc, $manifeste]], $this->mere())->assertOk();
        $this->postJson("/sauvegarde/copie/$id/valider", ['racine' => [$manifeste]], $this->mere())->assertOk();

        return $id;
    }

    public function test_un_appareil_appaire_est_refuse_en_le_nommant_et_rien_n_est_lu_ni_ecrit(): void
    {
        $this->postJson('/mere/code', ['hash' => hash('sha256', 'CODE-T')], $this->mere())->assertOk();
        $jeton = $this->postJson('/appairage', ['code' => 'CODE-T', 'uuid' => 'tel-1'])->assertOk()->json('jeton');
        $h = ['Authorization' => 'Bearer '.$jeton];
        $this->getJson('/sauvegarde/etat', $h)->assertStatus(403)->assertJson(['code' => 'sauvegarde_reservee_mere']);
        $this->getJson('/sauvegarde/copies', $h)->assertStatus(403)->assertJson(['code' => 'sauvegarde_reservee_mere']);
        $this->postJson('/sauvegarde/copie', ['id' => str_repeat('a', 64), 'type' => 'magasin', 'garder' => 7], $h)->assertStatus(403)->assertJson(['code' => 'sauvegarde_reservee_mere']);
        $id = hash('sha256', 'x');
        $this->call('PUT', '/sauvegarde/bloc/'.$id, [], [], [], ['HTTP_AUTHORIZATION' => 'Bearer '.$jeton, 'CONTENT_TYPE' => 'application/octet-stream'], 'x')->assertStatus(403)->assertJson(['code' => 'sauvegarde_reservee_mere']);
        $this->getJson('/sauvegarde/etat')->assertStatus(403)->assertJson(['code' => 'mere_requise']);
        $this->assertSame(0, DB::table('relais_sauv_blocs')->count());
        $this->assertSame(0, DB::table('relais_sauv_copies')->count());
    }

    public function test_un_bloc_est_sur_disque_jamais_en_base_et_son_empreinte_est_revérifiee(): void
    {
        $octets = $this->alea('bloc', 5000);
        $id = $this->poser($octets);
        $this->assertSame($octets, file_get_contents(Entrepot::chemin($id)));
        $this->assertSame(['id', 'taille', 'recu'], Schema::getColumnListing('relais_sauv_blocs'));
        $this->assertStringNotContainsString(substr(bin2hex($octets), 0, 40), json_encode(DB::table('relais_sauv_blocs')->get()));
        $this->call('PUT', '/sauvegarde/bloc/'.$id, [], [], [], ['HTTP_X_MERE' => self::SECRET], $octets)->assertOk()->assertJson(['rejeu' => true]);
        $this->assertSame(1, DB::table('relais_sauv_blocs')->count());
        $this->call('PUT', '/sauvegarde/bloc/'.hash('sha256', 'autre'), [], [], [], ['HTTP_X_MERE' => self::SECRET], $octets)->assertStatus(422)->assertJson(['code' => 'BLOC_ALTERE_EN_ROUTE']);
        // le disque du relais s'altère : la lecture le dit, elle ne rend jamais un octet faux
        file_put_contents(Entrepot::chemin($id), 'corrompu');
        $this->getJson('/sauvegarde/bloc/'.$id, $this->mere())->assertStatus(409)->assertJson(['code' => 'BLOC_ALTERE_AU_RELAIS']);
    }

    public function test_les_limites_sont_en_base_avec_un_defaut_seme_et_les_refus_sont_nommes_avec_le_geste(): void
    {
        foreach (Reglages::DEFAUTS as $nom => $d) {
            $this->assertDatabaseHas('relais_meta', ['k' => Reglages::cle($nom), 'v' => (string) $d['defaut']]);
        }
        $this->getJson('/sauvegarde/etat', $this->mere())->assertOk()->assertJsonPath('limites.rotationPlancher', 2)->assertJsonPath('limites.tailleBlocMax', 2097152);
        DB::table('relais_meta')->where('k', Reglages::cle('taille_bloc_max'))->update(['v' => '4096']);
        $gros = $this->alea('gros', 5000);
        $this->call('PUT', '/sauvegarde/bloc/'.hash('sha256', $gros), [], [], [], ['HTTP_X_MERE' => self::SECRET], $gros)->assertStatus(413)->assertJson(['code' => 'BLOC_TROP_GROS', 'limite' => 4096]);
        DB::table('relais_meta')->where('k', Reglages::cle('taille_bloc_max'))->update(['v' => '2097152']);
        $this->postJson('/sauvegarde/copie', ['id' => str_repeat('a', 64), 'type' => 'magasin', 'garder' => 1], $this->mere())->assertStatus(422)->assertJson(['code' => 'ROTATION_HORS_BORNES', 'plancher' => 2, 'plafond' => 60]);
        $this->postJson('/sauvegarde/copie', ['id' => str_repeat('a', 64), 'type' => 'magasin', 'garder' => 99], $this->mere())->assertStatus(422)->assertJson(['code' => 'ROTATION_HORS_BORNES']);
        $r = $this->getJson('/sauvegarde/copie/'.str_repeat('f', 64), $this->mere())->assertStatus(404)->assertJson(['code' => 'COPIE_INCONNUE']);
        $this->assertNotSame('', (string) $r->json('geste'));
    }

    public function test_la_rotation_archive_puis_l_espace_purge_sans_jamais_toucher_les_copies_courantes(): void
    {
        $t = (int) (microtime(true) * 1000);
        $ids = [];
        foreach (['a', 'b', 'c', 'd'] as $i => $g) {
            $ids[] = $this->copie($g, 2, $t + $i);
        }
        $etats = DB::table('relais_sauv_copies')->orderBy('date')->pluck('etat')->all();
        $this->assertSame(['archivee', 'archivee', 'complete', 'complete'], $etats);
        // le quota est atteint : une copie de plus fait PURGER l'archive, la plus ancienne d'abord
        DB::table('relais_meta')->where('k', Reglages::cle('quota_octets'))->update(['v' => (string) (Entrepot::utilise() + 100)]);
        $nouveau = $this->copie('e', 2, $t + 10);
        $parEtat = DB::table('relais_sauv_copies')->orderBy('date')->pluck('etat', 'id')->all();
        $this->assertSame('purgee', $parEtat[$ids[0]]);
        $this->assertSame('complete', $parEtat[$nouveau]);
        $this->assertSame('complete', $parEtat[$ids[3]]);
        $this->assertSame(5, DB::table('relais_sauv_copies')->count(), 'la copie purgée garde sa ligne (RG-14)');
        $this->getJson('/sauvegarde/copie/'.$ids[0], $this->mere())->assertStatus(410)->assertJson(['code' => 'COPIE_PURGEE']);
        $this->getJson('/sauvegarde/copie/'.$ids[3], $this->mere())->assertOk()->assertJsonPath('etat', 'complete');
        // même sous une pression extrême, les copies courantes restent
        DB::table('relais_meta')->where('k', Reglages::cle('quota_octets'))->update(['v' => '1000']);
        $autre = $this->alea('encore', 4096);
        $this->call('PUT', '/sauvegarde/bloc/'.hash('sha256', $autre), [], [], [], ['HTTP_X_MERE' => self::SECRET], $autre)->assertStatus(507)->assertJson(['code' => 'ESPACE_RELAIS_INSUFFISANT']);
        $this->assertSame(2, DB::table('relais_sauv_copies')->where('etat', 'complete')->count());
    }

    public function test_la_limite_par_copie_refuse_le_rattachement(): void
    {
        DB::table('relais_meta')->where('k', Reglages::cle('taille_max_copie'))->update(['v' => '1000']);
        $bloc = $this->poser($this->alea('lim', 4096));
        $id = hash('sha256', 'copie-lim');
        $this->postJson('/sauvegarde/copie', ['id' => $id, 'type' => 'magasin', 'date' => 1, 'garder' => 7], $this->mere())->assertOk();
        $this->postJson("/sauvegarde/copie/$id/blocs", ['ids' => [$bloc]], $this->mere())->assertStatus(413)->assertJson(['code' => 'SAUVEGARDE_TROP_GROSSE']);
        $this->postJson("/sauvegarde/copie/$id/valider", ['racine' => [$bloc]], $this->mere())->assertStatus(409)->assertJson(['code' => 'BLOC_MANQUANT']);
        $this->assertSame('ouverte', DB::table('relais_sauv_copies')->where('id', $id)->value('etat'));
    }

    public function test_l_export_du_panneau_n_embarque_pas_les_blocs_ni_leurs_tables(): void
    {
        $this->copie('export');
        $e = Exporteur::exporter(false, 'test@clinique');
        $contenu = '';
        $h = gzopen(Exporteur::dossier().'/'.$e->fichier, 'rb');
        while (! gzeof($h)) {
            $contenu .= gzread($h, 65536);
        }
        gzclose($h);
        $this->assertStringNotContainsString('relais_sauv_', $contenu);
        $this->assertStringNotContainsString(substr(bin2hex($this->alea('export', 4096)), 0, 40), $contenu);
        $this->assertSame(1, DB::table('relais_sauv_copies')->count());
        @unlink(Exporteur::dossier().'/'.$e->fichier);
    }

    public function test_l_ecran_opacite_signale_un_bloc_non_chiffre_et_accepte_un_chiffre(): void
    {
        $this->poser($this->alea('chiffre', 20000));
        $m = Opacite::mesurerBlocs();
        $this->assertSame(0, $m['signatures']);
        $this->assertSame(0, $m['lisibles']);
        $this->assertGreaterThan(7.9, $m['entropie']);
        $this->poser("SQLite format 3\0".str_repeat('Hyperglycemie du patient AKPO ', 400));
        $m2 = Opacite::mesurerBlocs();
        $this->assertSame(1, $m2['signatures']);
        $this->assertSame(1, $m2['lisibles']);
        $this->assertLessThan($m['entropie'], $m2['entropie']);
        Livewire::actingAs(User::factory()->create())->test(EcranOpacite::class)->assertSee('Blocs de sauvegarde hors site')->assertSee('ALERTE');
    }

    public function test_la_carte_du_panneau_montre_des_compteurs_jamais_un_contenu_et_regle_les_limites_bornees(): void
    {
        $this->copie('panneau');
        $u = User::factory()->create(['email' => 'dg@clinique.test']);
        $c = Livewire::actingAs($u)->test(Sauvegarde::class)->assertSee('Sauvegardes hors site')->assertSee('Espace utilisé')->assertSee('n’embarque PAS les blocs');
        $c->set('limites.quota_octets', 1)->call('enregistrerLimites')->assertSee('Espace total des copies hors site');
        $this->assertSame(Reglages::DEFAUTS['quota_octets']['defaut'], Reglages::toutes()['quota_octets']);
        $c->set('limites.quota_octets', 128 * 1048576)->set('limites.rotation_plancher', 3)->call('enregistrerLimites');
        $this->assertSame(128 * 1048576, Reglages::toutes()['quota_octets']);
        $this->assertSame(3, Reglages::toutes()['rotation_plancher']);
        $this->assertDatabaseHas('relais_audit', ['action' => 'reglage_sauvegarde', 'acteur' => 'dg@clinique.test']);
        // le plancher ne dépasse pas le plafond
        $this->assertNotNull(Reglages::poser('rotation_plancher', 10, 'dg@clinique.test') === null ? 'ok' : null);
        $this->assertSame('Le plafond ne peut pas être sous le plancher de rotation.', Reglages::poser('rotation_plafond', 2, 'dg@clinique.test'));
    }

    /** Les règles pures rejouées sur les vecteurs tirés du banc (mêmes cas que le domaine Dart). */
    public function test_les_regles_pures_rejouent_les_vecteurs_du_banc(): void
    {
        $f = json_decode((string) file_get_contents(base_path('../../packages/domaine/test/vecteurs/sauvegarde_horssite.json')), true);
        $n = 0;
        foreach ($f['cas'] as $c) {
            $e = $c['entree'];
            if ($c['op'] === 'rotation') {
                $r = Regles::rotation($e['copies'], $e['garder'], $e['plancher'], $e['plafond']);
                $a = $c['attendu'];
                if (($a['ok'] ?? null) === false) {
                    $this->assertFalse($r['ok'], $c['nom']);
                    $this->assertSame($a['code'], $r['code'], $c['nom']);
                } else {
                    $this->assertSame($a['gardees'], $r['gardees'], $c['nom']);
                    $this->assertSame($a['archiver'], $r['archiver'], $c['nom']);
                }
                $n++;
            } elseif ($c['op'] === 'ordrePurge') {
                $this->assertSame($c['attendu'], Regles::ordrePurge($e['copies'], $e['plancher']), $c['nom']);
                $n++;
            } elseif ($c['op'] === 'verifierPlan') {
                $r = Regles::verifierPlan($e['octetsCopie'], $e['etat']);
                $this->assertSame($c['attendu']['code'] ?? null, $r['code'] ?? null, $c['nom']);
                $n++;
            }
        }
        $this->assertGreaterThan(25, $n);
    }
}
