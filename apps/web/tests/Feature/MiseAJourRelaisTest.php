<?php

namespace Tests\Feature;

use App\Relais\Exporteur;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/** Lot MAJ, relais : relecture de l'export `.jsonl.gz`, restauration dans une base neuve, mise à jour qui exporte et relit AVANT de migrer. */
class MiseAJourRelaisTest extends TestCase
{
    use RefreshDatabase;

    private function semer(): void
    {
        DB::table('relais_enveloppes')->insert(['id' => 'e1', 'appareil' => 'm1', 'dir' => 'vers_mobile', 'n' => 1, 'nonce' => 'x', 'ct' => 'y', 'taille' => 10, 'recu' => 1]);
        DB::table('relais_enveloppes')->insert(['id' => 'e2', 'appareil' => 'm1', 'dir' => 'vers_mobile', 'n' => 2, 'nonce' => 'x', 'ct' => 'z', 'taille' => 10, 'recu' => 1]);
    }

    private function nettoyer(): void
    {
        foreach (glob(Exporteur::dossier().'/relais-*.jsonl.gz') ?: [] as $f) {
            @unlink($f);
        }
    }

    public function test_la_relecture_compte_par_table_et_ne_modifie_rien(): void
    {
        $this->semer();
        $e = Exporteur::exporter(false, 'test');
        $avant = DB::table('relais_enveloppes')->count();
        $this->artisan('relais:relire-export', ['fichier' => Exporteur::dossier().'/'.$e->fichier])->expectsOutputToContain('relais_enveloppes')->assertSuccessful();
        $this->assertSame($avant, DB::table('relais_enveloppes')->count());
        $this->nettoyer();
    }

    public function test_un_fichier_inexistant_ou_tronque_est_nomme(): void
    {
        $this->artisan('relais:relire-export', ['fichier' => '/tmp/inexistant-relais.jsonl.gz'])->expectsOutputToContain('EXPORT_INTROUVABLE')->assertFailed();
        $f = sys_get_temp_dir().'/mauvais-'.uniqid().'.jsonl.gz';
        file_put_contents($f, gzencode("pas du json\n".json_encode(['t' => 'table_inconnue', 'r' => ['a' => 1]])."\n"));
        $this->artisan('relais:relire-export', ['fichier' => $f])->expectsOutputToContain('enregistrement mal formé')->assertFailed();
        @unlink($f);
    }

    public function test_la_restauration_refuse_une_base_non_vide_et_n_ecrase_rien(): void
    {
        $this->semer();
        $e = Exporteur::exporter(false, 'test');
        $this->artisan('relais:relire-export', ['fichier' => Exporteur::dossier().'/'.$e->fichier, '--restaurer' => true])->expectsOutputToContain('RESTAURATION_BASE_NON_VIDE')->assertFailed();
        $this->assertSame(2, DB::table('relais_enveloppes')->count());
        $this->nettoyer();
    }

    public function test_la_restauration_remet_les_lignes_dans_une_base_neuve(): void
    {
        $this->semer();
        $e = Exporteur::exporter(false, 'test');
        DB::table('relais_enveloppes')->delete();
        DB::table('relais_audit')->delete();
        DB::table('relais_exports')->delete();
        $this->artisan('relais:relire-export', ['fichier' => Exporteur::dossier().'/'.$e->fichier, '--restaurer' => true])->assertSuccessful();
        $this->assertSame(['e1', 'e2'], DB::table('relais_enveloppes')->orderBy('id')->pluck('id')->all());
        $this->nettoyer();
    }

    public function test_la_mise_a_jour_exporte_et_relit_avant_de_migrer(): void
    {
        $this->semer();
        $this->artisan('relais:mise-a-jour')->expectsOutputToContain('Export relu')->assertSuccessful();
        $e = DB::table('relais_exports')->orderByDesc('id')->first();
        $this->assertSame(1, (int) $e->avant_migration);
        $this->nettoyer();
    }

    public function test_l_essai_a_blanc_n_exporte_ni_ne_migre(): void
    {
        $avant = DB::table('relais_exports')->count();
        $this->artisan('relais:mise-a-jour', ['--essai' => true])->expectsOutputToContain('Essai à blanc')->assertSuccessful();
        $this->assertSame($avant, DB::table('relais_exports')->count());
    }
}
