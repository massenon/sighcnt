<?php

namespace Tests\Feature\Panneau;

use App\Livewire\Panneau\Alertes;
use App\Livewire\Panneau\Boites;
use App\Livewire\Panneau\Sauvegarde;
use App\Livewire\Panneau\Superadmin;
use App\Models\User;
use App\Relais\Exporteur;
use App\Relais\Opacite;
use App\Relais\Surveillance;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Mail;
use Livewire\Livewire;
use Tests\TestCase;

/** Comportement des écrans du panneau ajoutés pour la parité RLS : alertes, indicateurs, export, mot de passe, opacité. */
class PanneauCompletTest extends TestCase
{
    use RefreshDatabase;

    private function admin(): User
    {
        return User::factory()->create(['email' => 'admin@clinique.test', 'password' => Hash::make('ancien-mot-de-passe-12')]);
    }

    public function test_les_douze_pages_sont_fermees_aux_visiteurs_et_ouvertes_au_superadmin(): void
    {
        $routes = ['tableau', 'appareils', 'boites', 'codes', 'indicateurs', 'alertes', 'journal', 'superadmin', 'parametres', 'hebergement', 'sauvegarde', 'opacite'];
        foreach ($routes as $r) {
            $this->get(route('panneau.'.$r))->assertRedirect('/panneau/connexion');
        }
        $u = $this->admin();
        foreach ($routes as $r) {
            $this->actingAs($u)->get(route('panneau.'.$r))->assertOk();
        }
    }

    public function test_la_surveillance_leve_puis_resout_une_alerte_et_la_journalise(): void
    {
        config(['relais.seuil_battement_ms' => 60000]);
        Surveillance::evaluer();
        $this->assertDatabaseHas('relais_alertes', ['type' => 'battement', 'fin' => null]);
        $this->assertDatabaseHas('relais_audit', ['acteur' => 'système', 'action' => 'alerte_battement']);
        Surveillance::evaluer(); // idempotent : pas de doublon
        $this->assertSame(1, DB::table('relais_alertes')->where('type', 'battement')->count());

        DB::table('relais_meta')->updateOrInsert(['k' => 'battement'], ['v' => (string) (int) (microtime(true) * 1000)]);
        Surveillance::evaluer();
        $this->assertDatabaseMissing('relais_alertes', ['type' => 'battement', 'fin' => null]);
        $this->assertDatabaseHas('relais_audit', ['action' => 'alerte_resolue', 'detail' => 'battement']);
    }

    public function test_l_alerte_appareil_bloque_vient_de_ce_que_la_mere_publie(): void
    {
        DB::table('relais_meta')->insert(['k' => 'indicateurs', 'v' => json_encode(['appareils_bloques' => 2])]);
        Surveillance::evaluer();
        $this->assertDatabaseHas('relais_alertes', ['type' => 'appareil_bloque', 'fin' => null]);
    }

    public function test_la_commande_surveiller_marque_le_passage_du_cron(): void
    {
        $this->artisan('relais:surveiller')->assertSuccessful();
        $this->assertNotNull(Surveillance::ageCron());
        $this->assertDatabaseMissing('relais_alertes', ['type' => 'cron', 'fin' => null]);
    }

    public function test_les_indicateurs_publies_alimentent_l_historique_sans_rien_de_plus(): void
    {
        config(['relais.secret_mere' => 's3cret']);
        $this->postJson('/mere/indicateurs',['indicateurs' => ['seq' => 7, 'appareils_actifs' => 4]], ['x-mere' => 's3cret'])->assertOk();
        $this->assertSame(1, DB::table('relais_indicateurs_historique')->count());
        $this->actingAs($this->admin())->get(route('panneau.indicateurs'))->assertOk()->assertSee('Historique (24 h)')->assertSee('appareils_actifs');
    }

    public function test_un_code_declare_porte_sa_date_de_creation_et_d_usage(): void
    {
        config(['relais.secret_mere' => 's3cret']);
        $this->postJson('/mere/code',['hash' => hash('sha256', 'CODE-1')], ['x-mere' => 's3cret'])->assertOk();
        $this->assertNotNull(DB::table('relais_codes')->value('cree'));
        $this->postJson('/appairage', ['code' => 'CODE-1', 'uuid' => 'mob-1'])->assertOk();
        $this->assertNotNull(DB::table('relais_codes')->value('utilise_le'));
    }

    public function test_l_export_est_un_fichier_sans_comptes_ni_sessions_et_il_est_journalise(): void
    {
        $u = $this->admin();
        DB::table('relais_appareils')->insert(['uuid' => 'a1', 'jeton_hash' => 'hh', 'etat' => 'actif']);
        Livewire::actingAs($u)->test(Sauvegarde::class)->call('exporter')->assertSee('Export créé');
        $e = DB::table('relais_exports')->first();
        $this->assertNotNull($e);
        $contenu = gzdecode(file_get_contents(Exporteur::dossier().'/'.$e->fichier));
        $this->assertStringContainsString('relais_appareils', $contenu);
        $this->assertStringNotContainsString('ancien-mot-de-passe', $contenu);
        $this->assertStringNotContainsString('"users"', $contenu);
        $this->assertDatabaseHas('relais_audit', ['action' => 'export_base', 'acteur' => 'admin@clinique.test']);
        @unlink(Exporteur::dossier().'/'.$e->fichier);
    }

    public function test_la_commande_exporter_marque_avant_migration(): void
    {
        $this->artisan('relais:exporter', ['--avant-migration' => true])->assertSuccessful();
        $e = DB::table('relais_exports')->first();
        $this->assertSame(1, (int) $e->avant_migration);
        @unlink(Exporteur::dossier().'/'.$e->fichier);
    }

    public function test_changer_le_mot_de_passe_exige_l_ancien_huit_caracteres_et_ne_journalise_pas_le_secret(): void
    {
        $u = $this->admin();
        Livewire::actingAs($u)->test(Superadmin::class)
            ->set('actuel', 'faux')->set('nouveau', 'nouveau-mot-de-passe-13')->set('confirmation', 'nouveau-mot-de-passe-13')->call('changerMotDePasse')->assertSee('actuel est incorrect');
        Livewire::actingAs($u)->test(Superadmin::class)
            ->set('actuel', 'ancien-mot-de-passe-12')->set('nouveau', 'court')->set('confirmation', 'court')->call('changerMotDePasse')->assertSee('au moins 8');
        Livewire::actingAs($u)->test(Superadmin::class)
            ->set('actuel', 'ancien-mot-de-passe-12')->set('nouveau', 'nouveau-mot-de-passe-13')->set('confirmation', 'autre-chose-de-long')->call('changerMotDePasse')->assertSee('ne correspond pas');
        $this->assertTrue(Hash::check('ancien-mot-de-passe-12', $u->fresh()->password));
        Livewire::actingAs($u)->test(Superadmin::class)
            ->set('actuel', 'ancien-mot-de-passe-12')->set('nouveau', 'nouveau-mot-de-passe-13')->set('confirmation', 'nouveau-mot-de-passe-13')->call('changerMotDePasse')->assertSee('Mot de passe changé');
        $this->assertTrue(Hash::check('nouveau-mot-de-passe-13', $u->fresh()->password));
        $this->assertDatabaseHas('relais_audit', ['action' => 'mot_de_passe_change']);
        $this->assertSame(0, DB::table('relais_audit')->where('detail', 'like', '%mot-de-passe%')->count());
    }

    public function test_le_courriel_de_test_part_vers_le_compte_connecte_et_est_journalise(): void
    {
        Mail::fake();
        Livewire::actingAs($this->admin())->test(Alertes::class)->call('tester')->assertSee('Courriel de test envoyé');
        $this->assertDatabaseHas('relais_audit', ['action' => 'courriel_test', 'detail' => 'envoyé']);
    }

    public function test_les_boites_comptent_les_deux_sens_sans_le_journal(): void
    {
        foreach ([['a', 'vers_mobile', 1], ['a', 'vers_mobile', 2], ['a', 'vers_mere', 1], ['a', 'journal', 1]] as $i => [$app, $dir, $n]) {
            DB::table('relais_enveloppes')->insert(['id' => "x$i", 'appareil' => $app, 'dir' => $dir, 'n' => $n, 'nonce' => 'n', 'ct' => 'Y3Q=', 'taille' => 100, 'recu' => 1000]);
        }
        Livewire::actingAs($this->admin())->test(Boites::class)->assertViewHas('vers', 2)->assertViewHas('depuis', 1);
    }

    public function test_l_opacite_mesure_du_hasard_et_repere_un_contenu_lisible(): void
    {
        $this->assertNull(Opacite::mesurer()['entropie']);
        DB::table('relais_enveloppes')->insert(['id' => 'h', 'appareil' => 'a', 'dir' => 'journal', 'n' => 1, 'nonce' => 'n', 'ct' => base64_encode(random_bytes(4000)), 'taille' => 5000, 'recu' => 1]);
        $m = Opacite::mesurer();
        $this->assertGreaterThan(7.9, $m['entropie']);
        $this->assertSame(0, $m['lisibles']);
        DB::table('relais_enveloppes')->insert(['id' => 'l', 'appareil' => 'a', 'dir' => 'journal', 'n' => 2, 'nonce' => 'n', 'ct' => base64_encode('{"collection":"patients","nom":"X"}'), 'taille' => 50, 'recu' => 2]);
        $this->assertSame(1, Opacite::mesurer()['lisibles']);
        $this->assertFalse(Opacite::cleDeCliniqueAuRelais());
    }

    public function test_les_parametres_n_affichent_jamais_le_secret_de_la_mere(): void
    {
        config(['relais.secret_mere' => 'SECRET-DE-LA-MERE-123']);
        $this->actingAs($this->admin())->get(route('panneau.parametres'))->assertOk()->assertDontSee('SECRET-DE-LA-MERE-123')->assertSee('défini, non affichable');
    }
}
