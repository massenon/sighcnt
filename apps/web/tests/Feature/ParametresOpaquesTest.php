<?php

namespace Tests\Feature;

use App\Models\User;
use App\Relais\Opacite;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Route;
use Tests\TestCase;

/**
 * Lot L0 (décision de la Direction, 09/11/2026) : les paramètres se règlent au POSTE, voyagent chiffrés par le journal (famille R) et le relais les stocke sans
 * jamais les lire ; son panneau ne montre que ses propres réglages. Le banc de synchronisation (`packages/sync/banc`, scénario L0) prouve l'aller-retour poste,
 * relais, second poste ; ici, ce que le VRAI relais Laravel garantit de son côté.
 */
class ParametresOpaquesTest extends TestCase
{
    use RefreshDatabase;

    private const SECRET = 'secret-mere-test';

    protected function setUp(): void
    {
        parent::setUp();
        config(['relais.secret_mere' => self::SECRET, 'relais.banc' => false]);
    }

    /** Une enveloppe AES-256-GCM comme celle de la mère : métadonnées authentifiées (id|appareil|dir|n), clé de clinique que le relais n'a pas. */
    private function enveloppe(string $cle, array $charge, int $n): array
    {
        $id = "journal-$n";
        $nonce = random_bytes(12);
        $tag = '';
        $ct = openssl_encrypt(json_encode($charge, JSON_UNESCAPED_UNICODE), 'aes-256-gcm', $cle, OPENSSL_RAW_DATA, $nonce, $tag, "$id|mere|journal|$n");

        return ['id' => $id, 'appareil' => 'mere', 'dir' => 'journal', 'n' => $n, 'nonce' => base64_encode($nonce), 'ct' => base64_encode($ct.$tag)];
    }

    private function charge(string $valeur): array
    {
        return ['type' => 'journal', 'ops' => [[
            'seq' => 1, 'id' => 'ref-1', 'appareil' => 'mere', 'collection' => 'parametres', 'fiche' => 'accueil.note@2026-12-01@1', 'type' => 'creer',
            'champs' => ['cle' => 'accueil.note', 'famille' => 'accueil', 'type' => 'texte', 'valeur' => $valeur, 'defaut' => 'rien', 'dateEffet' => '2026-12-01', 'version' => 1,
                'auteur' => 'ADJOVI Koffi', 'motif' => str_repeat('Décision de la Direction ', 60)],
        ]]];
    }

    public function test_un_parametre_depose_par_la_mere_est_stocke_chiffre_et_illisible(): void
    {
        $cle = random_bytes(32);
        $secret = 'VALEUR-SECRETE-Zébulon';
        $this->postJson('/depot', ['enveloppe' => $this->enveloppe($cle, $this->charge($secret), 1)], ['x-mere' => self::SECRET])->assertOk();

        $ligne = DB::table('relais_enveloppes')->where('dir', 'journal')->first();
        $this->assertNotNull($ligne);
        $octets = base64_decode($ligne->ct, true);
        foreach ([$secret, 'accueil.note', 'parametres', 'dateEffet', 'ADJOVI'] as $clair) {
            $this->assertStringNotContainsString($clair, $octets, "« $clair » ne doit pas se lire dans les octets stockés");
            $this->assertStringNotContainsString($clair, (string) $ligne->ct);
        }
        $this->assertGreaterThan(7.5, Opacite::entropie($octets), 'un chiffrement authentifié ressemble à du hasard : on mesure, on ne cherche pas du texte');
        $m = Opacite::mesurer();
        $this->assertSame(0, $m['lisibles']);
        $this->assertFalse(Opacite::cleDeCliniqueAuRelais());

        // Contre-épreuve : avec la clé de clinique (que le relais n'a pas), le contenu est bien là. L'opacité ne vient donc pas d'une enveloppe vide.
        $brut = base64_decode($ligne->ct, true);
        $clair = openssl_decrypt(substr($brut, 0, -16), 'aes-256-gcm', $cle, OPENSSL_RAW_DATA, base64_decode($ligne->nonce, true), substr($brut, -16), "{$ligne->id}|mere|journal|1");
        $this->assertStringContainsString($secret, (string) $clair);
    }

    public function test_le_relais_ne_detient_aucune_cle_et_ne_peut_donc_ni_lire_ni_valider_un_contenu(): void
    {
        // Le relais n'a aucune clé : il ne sait pas déchiffrer, donc il ne peut ni lire ni valider un contenu. Il stocke et transmet des octets.
        $this->assertSame([], array_filter(array_keys((array) config('relais')), fn ($k) => (bool) preg_match('/^(cle|key|secret_clinique|cle_clinique)/i', (string) $k)));
    }

    public function test_le_relais_n_offre_aucune_route_pour_lire_ou_ecrire_un_parametre_metier(): void
    {
        $uris = collect(Route::getRoutes()->getRoutes())->map(fn ($r) => $r->uri())->values();
        $parametres = $uris->filter(fn ($u) => (bool) preg_match('/param/i', $u))->values()->all();
        $this->assertSame(['panneau/parametres'], $parametres, 'seule la page des réglages PROPRES au relais existe');
    }

    public function test_le_panneau_ne_montre_que_les_reglages_du_relais(): void
    {
        $admin = User::factory()->create(['email' => 'admin@clinique.test', 'password' => Hash::make('ancien-mot-de-passe-12')]);
        $this->postJson('/depot', ['enveloppe' => $this->enveloppe(random_bytes(32), $this->charge('rien'), 1)], ['x-mere' => self::SECRET])->assertOk();
        $page = $this->actingAs($admin)->get(route('panneau.parametres'))->assertOk();
        $page->assertSee('Paramètres du relais');
        $page->assertSee('ne se règlent pas ici');
        foreach (['planning.circuitPresences', 'mecef.mode', 'bareme_aib', 'paie.copieFichePaieTelephone', 'accueil.note'] as $metier) {
            $page->assertDontSee($metier);
        }
    }
}
