<?php

namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Garde-fous du relais OPAQUE. Chaque test reprend un scénario du banc (packages/sync/banc) :
 * le contrat est le même, ici éprouvé sur le vrai code Laravel.
 */
class RelaisTest extends TestCase
{
    use RefreshDatabase;

    private const SECRET = 'secret-mere-test';

    protected function setUp(): void
    {
        parent::setUp();
        config(['relais.secret_mere' => self::SECRET, 'relais.seuil_battement_ms' => 1000, 'relais.banc' => false]);
    }

    private function mere(): array
    {
        return ['x-mere' => self::SECRET];
    }

    private function appairer(string $uuid): array
    {
        $code = 'CODE-'.$uuid;
        $this->postJson('/mere/code', ['hash' => hash('sha256', $code)], $this->mere())->assertOk();
        $r = $this->postJson('/appairage', ['code' => $code, 'uuid' => $uuid])->assertOk();

        return ['Authorization' => 'Bearer '.$r->json('jeton'), 'code' => $code];
    }

    private function enveloppe(string $id, string $appareil, string $dir, int $n, string $ct = 'AAAA'): array
    {
        return ['enveloppe' => ['id' => $id, 'appareil' => $appareil, 'dir' => $dir, 'n' => $n, 'nonce' => 'bm9uY2U=', 'ct' => $ct]];
    }

    public function test_un_code_ne_sert_qu_une_fois_et_n_est_jamais_conserve_en_clair(): void
    {
        $a = $this->appairer('m-1');
        $this->postJson('/appairage', ['code' => $a['code'], 'uuid' => 'm-2'])->assertStatus(403)->assertJson(['code' => 'code_utilise']);
        $this->assertDatabaseMissing('relais_codes', ['hash' => $a['code']]);
        $this->assertDatabaseHas('relais_codes', ['hash' => hash('sha256', $a['code']), 'utilise' => true]);
    }

    public function test_le_jeton_n_est_jamais_conserve_en_clair(): void
    {
        $a = $this->appairer('m-1');
        $jeton = substr($a['Authorization'], strlen('Bearer '));
        $this->assertDatabaseMissing('relais_appareils', ['jeton_hash' => $jeton]);
        $this->assertDatabaseMissing('relais_appareils', ['jeton_hash' => explode('.', $jeton)[1]]);
    }

    public function test_un_depot_rejoue_ne_cree_aucun_doublon(): void
    {
        $a = $this->appairer('m-1');
        $e = $this->enveloppe('m-1-2', 'm-1', 'vers_mere', 2);
        $this->postJson('/depot', $e, $a)->assertOk()->assertJsonMissing(['rejeu' => true]);
        $this->postJson('/depot', $e, $a)->assertOk()->assertJson(['rejeu' => true]);
        $this->assertDatabaseCount('relais_enveloppes', 1);
    }

    public function test_un_rang_deja_pris_est_refuse(): void
    {
        $a = $this->appairer('m-1');
        $this->postJson('/depot', $this->enveloppe('x1', 'm-1', 'vers_mere', 1), $a)->assertOk();
        $this->postJson('/depot', $this->enveloppe('x2', 'm-1', 'vers_mere', 1), $a)->assertStatus(409)->assertJson(['code' => 'rang_deja_pris']);
    }

    public function test_cloisonnement_un_appareil_ne_lit_ni_ne_depose_chez_un_autre(): void
    {
        $a = $this->appairer('m-a');
        $this->appairer('m-b');
        $this->getJson('/releve?dir=vers_mobile&appareil=m-b&depuis_n=0', $a)->assertStatus(403)->assertJson(['code' => 'lecture_interdite']);
        $this->postJson('/depot', $this->enveloppe('y', 'm-b', 'vers_mere', 9), $a)->assertStatus(403)->assertJson(['code' => 'depot_interdit']);
        $this->postJson('/depot', $this->enveloppe('z', 'm-a', 'vers_mobile', 9), $a)->assertStatus(403)->assertJson(['code' => 'depot_interdit']);
    }

    public function test_les_routes_de_la_mere_sont_fermees_sans_son_secret(): void
    {
        foreach (['/mere/appareils', '/admin/etat'] as $route) {
            $this->getJson($route)->assertStatus(403)->assertJson(['code' => 'mere_requise']);
            $this->getJson($route, ['x-mere' => 'mauvais'])->assertStatus(403);
        }
        $this->postJson('/mere/battement', [], ['x-mere' => 'mauvais'])->assertStatus(403);
    }

    public function test_sans_secret_configure_aucune_mere_n_est_reconnue(): void
    {
        config(['relais.secret_mere' => '']);
        $this->getJson('/admin/etat', ['x-mere' => ''])->assertStatus(403);
    }

    public function test_la_mere_depose_dans_une_boite_mobile_et_le_mobile_la_relit(): void
    {
        $a = $this->appairer('m-1');
        $this->postJson('/depot', $this->enveloppe('m-m-1-1', 'm-1', 'vers_mobile', 1), $this->mere())->assertOk();
        $this->getJson('/compteur', $a)->assertOk()->assertJson(['max_n' => 1]);
        $r = $this->getJson('/releve?dir=vers_mobile&appareil=m-1&depuis_n=0', $a)->assertOk();
        $this->assertCount(1, $r->json('env'));
        $this->assertTrue($r->json('fin'));
    }

    public function test_la_mere_ne_depose_pas_dans_le_sens_mobile_vers_mere(): void
    {
        $this->postJson('/depot', $this->enveloppe('q', 'm-1', 'vers_mere', 1), $this->mere())->assertStatus(403);
    }

    public function test_revocation_l_appareil_perd_tout_acces(): void
    {
        $a = $this->appairer('m-1');
        $this->postJson('/mere/revoquer', ['uuid' => 'm-1'], $this->mere())->assertOk();
        $this->getJson('/compteur', $a)->assertStatus(401)->assertJson(['code' => 'appareil_revoque']);
    }

    public function test_battement_alerte_si_la_mere_se_tait_puis_retombe(): void
    {
        $this->getJson('/admin/etat', $this->mere())->assertOk()->assertJson(['alerte_battement' => true]); // jamais vue
        $this->postJson('/mere/battement', [], $this->mere())->assertOk();
        $this->getJson('/admin/etat', $this->mere())->assertJson(['alerte_battement' => false]);
        usleep(1300 * 1000); // seuil de 1000 ms
        $this->getJson('/admin/etat', $this->mere())->assertJson(['alerte_battement' => true]);
    }

    public function test_les_indicateurs_sont_le_seul_contenu_en_clair_et_se_relisent(): void
    {
        $this->postJson('/mere/indicateurs', ['indicateurs' => ['patients_actifs' => 12, 'retard_replication' => 0]], $this->mere())->assertOk();
        $this->getJson('/admin/etat', $this->mere())->assertJsonPath('indicateurs.patients_actifs', 12);
    }

    public function test_les_crochets_du_banc_sont_fermes_par_defaut(): void
    {
        foreach (['/banc/tout', '/banc/ids?dir=vers_mere'] as $route) {
            $this->getJson($route)->assertStatus(404);
        }
        $this->postJson('/banc/alterer', ['id' => 'x'])->assertStatus(404);
    }

    public function test_le_relais_ne_contient_aucun_chiffrement_ni_cle(): void
    {
        $src = file_get_contents(app_path('Http/Controllers/RelaisController.php'));
        $this->assertDoesNotMatchRegularExpression('/openssl_|sodium_|Crypt::|Crypto|encrypt\(|decrypt\(|AES|GCM/i', $src);
    }

    public function test_l_autorisation_precede_la_validation_meme_refus_quelle_que_soit_la_forme(): void
    {
        $a = $this->appairer('m-a');
        $this->appairer('m-b');
        // Enveloppe vide ET interdite : c'est l'interdiction qui répond, pas le défaut de forme.
        $this->postJson('/depot', ['enveloppe' => ['id' => 'x', 'appareil' => 'm-b', 'dir' => 'vers_mere', 'n' => 1, 'nonce' => '', 'ct' => '']], $a)
            ->assertStatus(403)->assertJson(['code' => 'depot_interdit']);
        // Enveloppe permise mais mal formée : validation.
        $this->postJson('/depot', ['enveloppe' => ['id' => 'x', 'appareil' => 'm-a', 'dir' => 'vers_mere', 'n' => 1, 'nonce' => '', 'ct' => '']], $a)
            ->assertStatus(422)->assertJson(['code' => 'enveloppe_invalide']);
    }
}
