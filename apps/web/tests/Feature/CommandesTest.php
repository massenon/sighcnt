<?php

namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/** Commandes d'exploitation du relais : purge de l'audit (jamais des enveloppes) et statut sans contenu. */
class CommandesTest extends TestCase
{
    use RefreshDatabase;

    private function audit(string $action, int $joursAvant): void
    {
        DB::table('relais_audit')->insert(['quand' => (int) (microtime(true) * 1000) - $joursAvant * 86400 * 1000, 'acteur' => 'test', 'action' => $action, 'detail' => null]);
    }

    private function enveloppe(string $id, int $n): void
    {
        DB::table('relais_enveloppes')->insert(['id' => $id, 'appareil' => 'm1', 'dir' => 'vers_mobile', 'n' => $n, 'nonce' => 'x', 'ct' => 'y', 'taille' => 1000, 'recu' => 1]);
    }

    public function test_la_simulation_ne_supprime_rien(): void
    {
        $this->audit('ancien', 400);
        $this->artisan('relais:purger')->expectsOutputToContain('1 ligne(s)')->assertSuccessful();
        $this->assertSame(1, DB::table('relais_audit')->count());
    }

    public function test_la_purge_retire_l_ancien_garde_le_recent_et_se_journalise(): void
    {
        $this->audit('ancien', 400);
        $this->audit('recent', 10);
        $this->artisan('relais:purger --oui')->assertSuccessful();
        $actions = DB::table('relais_audit')->pluck('action')->all();
        $this->assertNotContains('ancien', $actions);
        $this->assertContains('recent', $actions);
        $this->assertContains('audit_purge', $actions);
    }

    public function test_la_purge_ne_touche_jamais_une_enveloppe(): void
    {
        $this->enveloppe('e1', 1);
        $this->enveloppe('e2', 2);
        $this->audit('ancien', 4000);
        $this->artisan('relais:purger --oui --jours=30')->assertSuccessful();
        $this->assertSame(2, DB::table('relais_enveloppes')->count());
    }

    public function test_une_conservation_trop_courte_est_refusee(): void
    {
        $this->audit('ancien', 400);
        $this->artisan('relais:purger --oui --jours=5')->assertFailed();
        $this->assertSame(1, DB::table('relais_audit')->count());
    }

    public function test_le_statut_donne_les_volumes_sans_contenu(): void
    {
        $this->enveloppe('e1', 1);
        DB::table('relais_appareils')->insert(['uuid' => 'm1', 'jeton_hash' => 'h', 'etat' => 'actif']);
        $this->artisan('relais:statut')
            ->expectsOutputToContain('actif=1')
            ->expectsOutputToContain('vers_mobile')
            ->expectsOutputToContain('jamais')
            ->assertSuccessful();
    }
}
