<?php

namespace Tests\Feature;

use App\Livewire\Panneau\Appareils;
use App\Livewire\Panneau\Tableau;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Livewire\Livewire;
use Tests\TestCase;

/** Panneau superadmin minimal du relais : accès fermé, lecture sans contenu de santé, révocation journalisée. */
class PanneauTest extends TestCase
{
    use RefreshDatabase;

    private function superadmin(): User
    {
        return User::factory()->create(['email' => 'admin@clinique.test']);
    }

    public function test_le_panneau_est_ferme_aux_visiteurs(): void
    {
        foreach (['/panneau', '/panneau/appareils', '/panneau/codes', '/panneau/journal'] as $route) {
            $this->get($route)->assertRedirect('/panneau/connexion');
        }
        $this->get('/')->assertRedirect('/panneau');
    }

    public function test_connexion_refusee_et_journalisee(): void
    {
        $this->superadmin();
        $this->post('/panneau/connexion', ['courriel' => 'admin@clinique.test', 'mot_de_passe' => 'mauvais'])->assertSessionHasErrors('courriel');
        $this->assertDatabaseHas('relais_audit', ['action' => 'connexion_refusee', 'acteur' => 'admin@clinique.test']);
        $this->assertGuest();
    }

    public function test_connexion_reussie_puis_deconnexion(): void
    {
        $this->superadmin();
        $this->post('/panneau/connexion', ['courriel' => 'admin@clinique.test', 'mot_de_passe' => 'password'])->assertRedirect(route('panneau.tableau'));
        $this->assertAuthenticated();
        $this->assertDatabaseHas('relais_audit', ['action' => 'connexion']);
        $this->post('/panneau/deconnexion')->assertRedirect(route('panneau.connexion'));
        $this->assertGuest();
        $this->assertDatabaseHas('relais_audit', ['action' => 'deconnexion']);
    }

    public function test_le_tableau_de_bord_montre_l_alerte_battement_et_les_indicateurs_sans_aucun_contenu(): void
    {
        config(['relais.seuil_battement_ms' => 1000]);
        DB::table('relais_meta')->insert([
            ['k' => 'battement', 'v' => (string) ((int) (microtime(true) * 1000) - 600000)],
            ['k' => 'indicateurs', 'v' => json_encode(['patients_actifs' => 42, 'retard_replication' => 3])],
        ]);
        DB::table('relais_enveloppes')->insert(['id' => 'e1', 'appareil' => 'a', 'dir' => 'journal', 'n' => 1, 'nonce' => 'SECRET-NONCE', 'ct' => 'SECRET-CHIFFRE', 'taille' => 14, 'recu' => (int) (microtime(true) * 1000)]);
        Livewire::actingAs($this->superadmin())->test(Tableau::class)
            ->assertSee('Silencieuse')
            ->assertSee('patients actifs')->assertSee('42')
            ->assertDontSee('SECRET-CHIFFRE')->assertDontSee('SECRET-NONCE');
    }

    public function test_la_mere_vivante_est_en_ligne(): void
    {
        config(['relais.seuil_battement_ms' => 60000]);
        DB::table('relais_meta')->insert(['k' => 'battement', 'v' => (string) (int) (microtime(true) * 1000)]);
        Livewire::actingAs($this->superadmin())->test(Tableau::class)->assertSee('En ligne');
    }

    public function test_revoquer_un_appareil_est_journalise_et_refuse_ensuite_ses_appels(): void
    {
        DB::table('relais_appareils')->insert(['uuid' => 'mobile-1', 'jeton_hash' => hash('sha256', 'secret'), 'etat' => 'actif']);
        Livewire::actingAs($this->superadmin())->test(Appareils::class)->assertSee('Actif')
            ->call('revoquer', 'mobile-1')->assertSee('Appareil révoqué')->assertSee('Révoqué');
        $this->assertDatabaseHas('relais_appareils', ['uuid' => 'mobile-1', 'etat' => 'revoque']);
        $this->assertDatabaseHas('relais_audit', ['action' => 'appareil_revoque', 'detail' => 'mobile-1', 'acteur' => 'admin@clinique.test']);
        $this->getJson('/compteur', ['Authorization' => 'Bearer mobile-1.secret'])->assertStatus(401)->assertJson(['code' => 'appareil_revoque']);
    }

    public function test_revoquer_deux_fois_ne_fait_rien_de_plus(): void
    {
        DB::table('relais_appareils')->insert(['uuid' => 'm', 'jeton_hash' => 'h', 'etat' => 'revoque']);
        Livewire::actingAs($this->superadmin())->test(Appareils::class)->call('revoquer', 'm')->assertSee('déjà révoqué');
        $this->assertDatabaseCount('relais_audit', 0);
    }

    public function test_la_commande_superadmin_exige_un_mot_de_passe_solide_et_ne_le_journalise_pas(): void
    {
        $this->artisan('relais:superadmin', ['courriel' => 'a@b.test', '--mot-de-passe' => 'court'])->assertFailed();
        $this->artisan('relais:superadmin', ['courriel' => 'a@b.test', '--mot-de-passe' => 'un-mot-de-passe-solide'])->assertSuccessful();
        $this->assertDatabaseHas('users', ['email' => 'a@b.test']);
        $this->assertDatabaseMissing('relais_audit', ['detail' => 'un-mot-de-passe-solide']);
        $this->assertNotSame('un-mot-de-passe-solide', User::where('email', 'a@b.test')->value('password'));
    }
}
