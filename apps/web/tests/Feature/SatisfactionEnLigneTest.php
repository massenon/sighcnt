<?php

namespace Tests\Feature;

use App\Relais\Satisfaction\Entrepot;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/**
 * LOT SAT (ADR-0009) : la satisfaction en ligne, sur le VRAI code du relais Laravel. L'enveloppe est scellée ICI comme le fait le navigateur (X25519 éphémère, HKDF-SHA-256, AES-256-GCM,
 * rembourrage), et ouverte ICI comme le fait la mère : le relais, lui, ne fait ni l'un ni l'autre.
 */
class SatisfactionEnLigneTest extends TestCase
{
    use RefreshDatabase;

    private const SECRET = 'secret-mere-test';

    private string $privee;

    private string $publique;

    protected function setUp(): void
    {
        parent::setUp();
        config(['relais.secret_mere' => self::SECRET, 'relais.banc' => false]);
        $paire = sodium_crypto_box_keypair();
        $this->privee = sodium_crypto_box_secretkey($paire);
        $this->publique = sodium_crypto_box_publickey($paire);
    }

    private function charge(string $point = 'accueil'): array
    {
        return ['enquete' => 'ENQ-SAT', 'version' => 'V1', 'point' => ['code' => $point, 'libelle' => 'Accueil'], 'titre' => 'Votre avis', 'intro' => 'Merci',
            'questions' => [['code' => 'Q1', 'type' => 'note', 'libelle' => 'Accueil ?', 'obligatoire' => true], ['code' => 'Q2', 'type' => 'texte', 'libelle' => 'Commentaire ?', 'obligatoire' => false]]];
    }

    private function publier(array $liens, ?string $cle = null): \Illuminate\Testing\TestResponse
    {
        return $this->postJson('/satisfaction/publier', ['cle' => base64_encode($cle ?? $this->publique), 'liens' => $liens], ['x-mere' => self::SECRET]);
    }

    private function lien(string $jeton, array $plus = []): array
    {
        return ['empreinte' => hash('sha256', $jeton), 'charge' => $this->charge()] + $plus;
    }

    /** Scelle comme le navigateur. */
    private function sceller(array $donnees, string $id, int $taille = 1024): array
    {
        $eph = sodium_crypto_box_keypair();
        $epk = sodium_crypto_box_publickey($eph);
        $secret = sodium_crypto_scalarmult(sodium_crypto_box_secretkey($eph), $this->publique);
        $cle = hash_hkdf('sha256', $secret, 32, 'sigh-satisfaction-v1', $epk.$this->publique);
        $clair = json_encode($donnees, JSON_UNESCAPED_UNICODE);
        $rembourre = pack('n', strlen($clair)).$clair;
        $rembourre = str_pad($rembourre, $taille, "\0");
        $iv = random_bytes(12);
        $etiquette = '';
        $ct = openssl_encrypt($rembourre, 'aes-256-gcm', $cle, OPENSSL_RAW_DATA, $iv, $etiquette, $id, 16);

        return ['v' => 1, 'id' => $id, 'epk' => base64_encode($epk), 'iv' => base64_encode($iv), 'ct' => base64_encode($ct.$etiquette)];
    }

    /** Ouvre comme la mère. */
    private function ouvrir(array $ligne): array
    {
        $b = $ligne['bloc'];
        $epk = base64_decode($b['epk']);
        $secret = sodium_crypto_scalarmult($this->privee, $epk);
        $cle = hash_hkdf('sha256', $secret, 32, 'sigh-satisfaction-v1', $epk.$this->publique);
        $ct = base64_decode($b['ct']);
        $clair = openssl_decrypt(substr($ct, 0, -16), 'aes-256-gcm', $cle, OPENSSL_RAW_DATA, base64_decode($b['iv']), substr($ct, -16), $ligne['id']);
        $this->assertNotFalse($clair, 'la mère doit ouvrir l\'enveloppe');
        $n = unpack('n', substr($clair, 0, 2))[1];

        return json_decode(substr($clair, 2, $n), true);
    }

    private function id(): string
    {
        return bin2hex(random_bytes(16));
    }

    private function releve(): array
    {
        return $this->getJson('/satisfaction/releve?apres=0', ['x-mere' => self::SECRET])->assertOk()->json();
    }

    public function test_le_cycle_complet_la_mere_ouvre_ce_que_le_relais_ne_lit_pas(): void
    {
        $this->publier([$this->lien('jetonaccueil1')])->assertOk()->assertJson(['liens' => 1]);
        $id = $this->id();
        $this->postJson('/s/jetonaccueil1', $this->sceller(['id' => $id, 'point' => 'accueil', 'reponses' => ['Q1' => 5, 'Q2' => 'Très bon accueil']], $id))->assertOk()->assertJson(['ok' => true]);
        $r = $this->releve();
        $this->assertCount(1, $r['reponses']);
        $this->assertSame(hash('sha256', 'jetonaccueil1'), $r['reponses'][0]['lien']);
        $clair = $this->ouvrir($r['reponses'][0]);
        $this->assertSame(5, $clair['reponses']['Q1']);
        $this->assertSame('Très bon accueil', $clair['reponses']['Q2']);
    }

    public function test_opacite_la_base_du_relais_ne_laisse_rien_lire_et_ressemble_a_du_hasard(): void
    {
        $this->publier([$this->lien('jetonopacite1')])->assertOk();
        for ($i = 0; $i < 12; $i++) {
            $id = $this->id();
            $this->withServerVariables(['REMOTE_ADDR' => '198.51.100.'.($i + 1)])->postJson('/s/jetonopacite1', $this->sceller(['id' => $id, 'point' => 'accueil', 'reponses' => ['Q1' => 1 + $i % 5, 'Q2' => str_repeat('Le personnel était très aimable. ', 5)]], $id))->assertOk();
        }
        $tout = json_encode(DB::table('relais_sat_reponses')->get());
        foreach (['aimable', 'personnel', 'accueil', 'reponses', 'Très bon'] as $mot) {
            $this->assertStringNotContainsString($mot, $tout, "le mot « $mot » ne doit pas se lire en base");
        }
        $m = Entrepot::mesurerOpacite();
        $this->assertSame(12, $m['echantillon']);
        $this->assertSame(0, $m['lisibles']);
        $this->assertGreaterThan(7.6, $m['entropie'], 'entropie d\'un texte chiffré de 1 Kio (hasard : environ 7,8 bits par octet)');
        // Le jeton ne s'écrit jamais en base : seule son empreinte.
        $this->assertStringNotContainsString('jetonopacite1', json_encode(DB::table('relais_sat_liens')->get()).$tout);
    }

    public function test_jeton_inconnu_expire_ou_revoque_une_seule_reponse_et_aucune_enquete_nommee(): void
    {
        $this->publier([$this->lien('jetonouvert01'), $this->lien('jetonexpire01', ['expire' => Entrepot::maintenant() - 1000]), $this->lien('jetonrevoque1', ['revoque' => Entrepot::maintenant() - 1000])])->assertOk();
        $corps = [];
        foreach (['jetoninconnu1', 'jetonexpire01', 'jetonrevoque1'] as $j) {
            $g = $this->get('/s/'.$j);
            $g->assertStatus(404);
            $this->assertStringNotContainsString('Votre avis', $g->getContent());
            $corps[] = $g->getContent();
            $p = $this->postJson('/s/'.$j, $this->sceller(['id' => 'x'], $this->id()));
            $p->assertStatus(404)->assertJson(['code' => 'lien_indisponible']);
            $corps[] = $p->getContent();
        }
        $this->assertSame($corps[0], $corps[2]);
        $this->assertSame($corps[0], $corps[4]);
        $this->assertSame($corps[1], $corps[3]);
        $this->assertSame($corps[1], $corps[5]);
        $this->get('/s/jetonouvert01')->assertOk()->assertSee('Votre avis');
        $this->assertSame(0, DB::table('relais_sat_reponses')->count());
    }

    public function test_la_page_publique_n_pose_aucun_cookie_et_ne_se_met_pas_en_cache(): void
    {
        $this->publier([$this->lien('jetonsanscookie')])->assertOk();
        $g = $this->get('/s/jetonsanscookie')->assertOk();
        $this->assertSame([], $g->headers->getCookies());
        $this->assertStringContainsString('no-store', (string) $g->headers->get('Cache-Control'));
        $this->assertStringContainsString('noindex', (string) $g->headers->get('X-Robots-Tag'));
        $this->assertSame([], $this->postJson('/s/jetonsanscookie', $this->sceller(['id' => 'x'], $this->id()))->headers->getCookies());
    }

    public function test_la_meme_reponse_envoyee_deux_fois_n_est_comptee_qu_une_fois(): void
    {
        $this->publier([$this->lien('jetondoublon1')])->assertOk();
        $id = $this->id();
        $env = $this->sceller(['id' => $id, 'reponses' => ['Q1' => 4]], $id);
        $this->postJson('/s/jetondoublon1', $env)->assertOk()->assertJsonMissing(['rejeu' => true]);
        $this->postJson('/s/jetondoublon1', $env)->assertOk()->assertJson(['rejeu' => true]);
        $this->assertSame(1, DB::table('relais_sat_reponses')->count());
    }

    public function test_limite_de_debit_dix_reponses_par_empreinte_d_adresse_par_dix_minutes(): void
    {
        $this->publier([$this->lien('jetondebit001')])->assertOk();
        for ($i = 0; $i < 10; $i++) {
            $id = $this->id();
            $this->postJson('/s/jetondebit001', $this->sceller(['id' => $id], $id))->assertOk();
        }
        $id = $this->id();
        $r = $this->postJson('/s/jetondebit001', $this->sceller(['id' => $id], $id));
        $r->assertStatus(429)->assertJson(['code' => 'debit_depasse']);
        $this->assertSame('600', $r->headers->get('Retry-After'));
        // Une autre adresse n'est pas limitée ; la base ne garde qu'une EMPREINTE d'adresse, jamais l'adresse.
        $id = $this->id();
        $this->withServerVariables(['REMOTE_ADDR' => '203.0.113.9'])->postJson('/s/jetondebit001', $this->sceller(['id' => $id], $id))->assertOk();
        $this->assertStringNotContainsString('127.0.0.1', json_encode(DB::table('relais_sat_debit')->get()));
        // Après la fenêtre, l'empreinte s'efface et la limite retombe.
        DB::table('relais_sat_debit')->update(['t' => Entrepot::maintenant() - Entrepot::DEBIT_FENETRE_MS - 5]);
        $id = $this->id();
        $this->postJson('/s/jetondebit001', $this->sceller(['id' => $id], $id))->assertOk();
        $this->assertSame(1, DB::table('relais_sat_debit')->count());
    }

    public function test_enveloppe_de_plus_de_16_kio_refusee_et_forme_invalide_nommee(): void
    {
        $this->publier([$this->lien('jetontaille001')])->assertOk();
        $gros = str_repeat('a', Entrepot::ENVELOPPE_MAX + 1);
        $this->call('POST', '/s/jetontaille001', [], [], [], ['CONTENT_TYPE' => 'application/json'], $gros)->assertStatus(413)->assertJson(['code' => 'enveloppe_trop_grande']);
        $id = $this->id();
        $env = $this->sceller(['id' => $id], $id);
        $this->postJson('/s/jetontaille001', ['ct' => 'AAAA'] + $env)->assertStatus(422)->assertJson(['code' => 'enveloppe_invalide']);
        $court = $env;
        $court['ct'] = base64_encode(random_bytes(100));
        $this->postJson('/s/jetontaille001', $court)->assertStatus(422)->assertJson(['code' => 'enveloppe_invalide']);
        $this->postJson('/s/jetontaille001', ['v' => 2] + $env)->assertStatus(422);
        $this->postJson('/s/jetontaille001', ['id' => 'pas-un-id'] + $env)->assertStatus(422);
        $this->assertSame(0, DB::table('relais_sat_reponses')->count());
    }

    public function test_le_champ_piege_rempli_ne_stocke_rien_et_repond_comme_un_succes(): void
    {
        $this->publier([$this->lien('jetonpiege001')])->assertOk();
        $id = $this->id();
        $this->postJson('/s/jetonpiege001', $this->sceller(['id' => $id], $id) + ['piege' => 'http://spam.example'])->assertOk()->assertExactJson(['ok' => true]);
        $this->assertSame(0, DB::table('relais_sat_reponses')->count());
        $this->assertSame(0, DB::table('relais_sat_debit')->count());
    }

    public function test_deux_cents_liens_au_plus_et_clef_invalide_nommee(): void
    {
        $liens = [];
        for ($i = 0; $i < 201; $i++) {
            $liens[] = $this->lien('jeton'.str_pad((string) $i, 8, '0', STR_PAD_LEFT));
        }
        $this->publier($liens)->assertStatus(422)->assertJson(['code' => 'liens_trop_nombreux']);
        $this->publier(array_slice($liens, 0, 200))->assertOk()->assertJson(['liens' => 200]);
        $this->postJson('/satisfaction/publier', ['cle' => 'pas-une-cle', 'liens' => []], ['x-mere' => self::SECRET])->assertStatus(422)->assertJson(['code' => 'cle_invalide']);
    }

    public function test_un_appareil_appaire_est_refuse_en_le_nommant_et_sans_identite_403(): void
    {
        $this->postJson('/satisfaction/publier', ['cle' => base64_encode($this->publique), 'liens' => []], ['Authorization' => 'Bearer abc.def'])->assertStatus(403)->assertJson(['code' => 'satisfaction_reservee_mere']);
        $this->getJson('/satisfaction/releve', ['Authorization' => 'Bearer abc.def'])->assertStatus(403)->assertJson(['code' => 'satisfaction_reservee_mere']);
        $this->getJson('/satisfaction/releve')->assertStatus(403)->assertJson(['code' => 'mere_requise']);
        $this->getJson('/satisfaction/releve', ['x-mere' => 'mauvais'])->assertStatus(403);
    }

    public function test_publier_remplace_l_ensemble_des_liens_et_la_revocation_ferme_le_lien(): void
    {
        $this->publier([$this->lien('jetonrevoc0001')])->assertOk();
        $this->get('/s/jetonrevoc0001')->assertOk();
        $this->publier([$this->lien('jetonrevoc0001', ['revoque' => Entrepot::maintenant() - 1])])->assertOk();
        $this->get('/s/jetonrevoc0001')->assertStatus(404);
        $this->publier([])->assertOk();
        $this->assertSame(0, DB::table('relais_sat_liens')->count());
    }

    public function test_le_releve_avance_par_curseur_et_ne_depasse_pas_la_limite(): void
    {
        $this->publier([$this->lien('jetoncurseur01')])->assertOk();
        for ($i = 0; $i < 3; $i++) {
            $id = $this->id();
            $this->postJson('/s/jetoncurseur01', $this->sceller(['id' => $id], $id))->assertOk();
        }
        $p = $this->getJson('/satisfaction/releve?apres=0&limite=2', ['x-mere' => self::SECRET])->assertOk()->json();
        $this->assertCount(2, $p['reponses']);
        $this->assertSame(1, $p['reste']);
        $s = $this->getJson('/satisfaction/releve?apres='.$p['reponses'][1]['seq'], ['x-mere' => self::SECRET])->json();
        $this->assertCount(1, $s['reponses']);
        $this->assertSame(0, $s['reste']);
    }

    public function test_le_relais_n_importe_aucune_fonction_de_chiffrement(): void
    {
        $code = file_get_contents(__DIR__.'/../../app/Relais/Satisfaction/Entrepot.php').file_get_contents(__DIR__.'/../../app/Http/Controllers/SatisfactionController.php');
        $code = preg_replace('#/\*\*.*?\*/#s', '', $code);
        foreach (['openssl_decrypt', 'sodium_crypto', 'sodium_crypto_scalarmult', 'Crypt::decrypt', 'decrypt('] as $f) {
            $this->assertStringNotContainsString($f, $code, "le relais ne déchiffre pas ($f)");
        }
    }
}
