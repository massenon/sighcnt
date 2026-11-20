<?php

namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/** Une seule mère par clinique : la seconde déclaration est refusée en nommant la première, sauf reprise après sinistre. */
class MereUniqueTest extends TestCase
{
    use RefreshDatabase;

    private const SECRET = 'secret-mere-test';

    protected function setUp(): void
    {
        parent::setUp();
        config(['relais.secret_mere' => self::SECRET, 'relais.seuil_battement_ms' => 60000, 'relais.banc' => false]);
    }

    private function h(): array
    {
        return ['x-mere' => self::SECRET];
    }

    public function test_la_premiere_mere_s_active_et_peut_se_redeclarer(): void
    {
        $this->postJson('/mere/activer', ['uuid' => 'M1', 'etiquette' => 'Serveur DAF'], $this->h())->assertOk();
        $this->postJson('/mere/activer', ['uuid' => 'M1', 'etiquette' => 'Serveur DAF'], $this->h())->assertOk();
        $this->assertSame(1, DB::table('relais_audit')->where('action', 'mere_activee')->count(), 'une seule entrée d\'audit');
    }

    public function test_une_seconde_mere_est_refusee_en_nommant_la_premiere(): void
    {
        $this->postJson('/mere/activer', ['uuid' => 'M1', 'etiquette' => 'Serveur DAF'], $this->h())->assertOk();
        $r = $this->postJson('/mere/activer', ['uuid' => 'M2', 'etiquette' => 'Poste caisse'], $this->h());
        $r->assertStatus(409)->assertJsonPath('code', 'mere_deja_active');
        $this->assertStringContainsString('Serveur DAF', $r->json('motif'));
    }

    public function test_une_mere_vivante_ne_peut_pas_etre_remplacee_meme_explicitement(): void
    {
        $this->postJson('/mere/activer', ['uuid' => 'M1', 'etiquette' => 'Serveur DAF'], $this->h())->assertOk();
        $this->postJson('/mere/battement', [], $this->h())->assertOk();
        $this->postJson('/mere/activer', ['uuid' => 'M2', 'etiquette' => 'Nouveau', 'remplacer' => true], $this->h())->assertStatus(409)->assertJsonPath('code', 'mere_vivante');
    }

    public function test_une_mere_silencieuse_peut_etre_remplacee_explicitement_et_c_est_journalise(): void
    {
        $this->postJson('/mere/activer', ['uuid' => 'M1', 'etiquette' => 'Serveur DAF'], $this->h())->assertOk();
        DB::table('relais_meta')->updateOrInsert(['k' => 'battement'], ['v' => (string) ((int) (microtime(true) * 1000) - 600000)]);
        $this->postJson('/mere/activer', ['uuid' => 'M2', 'etiquette' => 'Nouveau serveur'], $this->h())->assertStatus(409)->assertJsonPath('code', 'mere_deja_active');
        $this->postJson('/mere/activer', ['uuid' => 'M2', 'etiquette' => 'Nouveau serveur', 'remplacer' => true], $this->h())->assertOk();
        $this->assertSame(1, DB::table('relais_audit')->where('action', 'mere_remplacee')->count());
        $this->postJson('/mere/activer', ['uuid' => 'M1', 'etiquette' => 'Serveur DAF'], $this->h())->assertStatus(409);
    }

    public function test_la_desactivation_libere_la_place_seulement_pour_la_mere_active(): void
    {
        $this->postJson('/mere/activer', ['uuid' => 'M1', 'etiquette' => 'A'], $this->h())->assertOk();
        $this->postJson('/mere/desactiver', ['uuid' => 'M2'], $this->h())->assertOk();
        $this->postJson('/mere/activer', ['uuid' => 'M3', 'etiquette' => 'C'], $this->h())->assertStatus(409);
        $this->postJson('/mere/desactiver', ['uuid' => 'M1'], $this->h())->assertOk();
        $this->postJson('/mere/activer', ['uuid' => 'M3', 'etiquette' => 'C'], $this->h())->assertOk();
    }

    public function test_sans_le_secret_de_la_mere_rien_ne_s_active(): void
    {
        $this->postJson('/mere/activer', ['uuid' => 'M1'], ['x-mere' => 'mauvais'])->assertStatus(403);
        $this->postJson('/mere/activer', ['uuid' => ''], $this->h())->assertStatus(422);
    }
}
