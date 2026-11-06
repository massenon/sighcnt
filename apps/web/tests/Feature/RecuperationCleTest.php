<?php

namespace Tests\Feature;

use App\Mail\CoffreCleMail;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Mail;
use Illuminate\Support\Facades\RateLimiter;
use Tests\TestCase;

/** Envoi du coffre de la clé par courriel, à la demande d'un poste appairé : le relais ne manipule qu'un COFFRE. */
class RecuperationCleTest extends TestCase
{
    use RefreshDatabase;

    private const SECRET = 'secret-mere-test';

    protected function setUp(): void
    {
        parent::setUp();
        config(['relais.secret_mere' => self::SECRET, 'relais.banc' => false]);
        RateLimiter::clear('coffre:poste-1');
    }

    private function appareil(string $uuid = 'poste-1'): array
    {
        $code = 'CODE-'.$uuid;
        $this->postJson('/mere/code', ['hash' => hash('sha256', $code)], ['x-mere' => self::SECRET])->assertOk();

        return ['Authorization' => 'Bearer '.$this->postJson('/appairage', ['code' => $code, 'uuid' => $uuid])->assertOk()->json('jeton')];
    }

    /** Un coffre réel, au format du poste et du navigateur (PBKDF2-SHA256 200 000 tours, AES-GCM, AAD « cle-clinique-v1 »). */
    private function coffre(string $phrase = 'une phrase assez longue'): array
    {
        $sel = random_bytes(16);
        $nonce = random_bytes(12);
        $k = hash_pbkdf2('sha256', $phrase, $sel, 200000, 32, true);
        $ct = openssl_encrypt(random_bytes(32), 'aes-256-gcm', $k, OPENSSL_RAW_DATA, $nonce, $tag, 'cle-clinique-v1', 16);

        return ['v' => 1, 'kdf' => 'PBKDF2-SHA256', 'iter' => 200000, 'sel' => base64_encode($sel), 'nonce' => base64_encode($nonce), 'ct' => base64_encode($ct.$tag)];
    }

    private function activer(): void
    {
        DB::table('relais_meta')->updateOrInsert(['k' => 'cle_recup_actif'], ['v' => '1']);
    }

    public function test_reglage_desactive_refus_nomme_et_rien_n_est_envoye(): void
    {
        Mail::fake();
        $h = $this->appareil();
        $this->postJson('/recuperation/envoyer', ['courriel' => 'a@b.bj', 'coffre' => $this->coffre()], $h)
            ->assertStatus(409)->assertJsonPath('code', 'recuperation_desactivee');
        Mail::assertNothingQueued();
    }

    public function test_appareil_inconnu_refuse(): void
    {
        $this->activer();
        $this->postJson('/recuperation/envoyer', ['courriel' => 'a@b.bj', 'coffre' => $this->coffre()])->assertStatus(401);
        $this->postJson('/recuperation/envoyer', ['courriel' => 'a@b.bj', 'coffre' => $this->coffre()], ['Authorization' => 'Bearer x.y'])->assertStatus(401);
    }

    public function test_cle_nue_refusee_comme_coffre(): void
    {
        Mail::fake();
        $this->activer();
        $h = $this->appareil();
        $cle = bin2hex(random_bytes(32));
        $this->postJson('/recuperation/envoyer', ['courriel' => 'a@b.bj', 'coffre' => $cle], $h)->assertStatus(422)->assertJsonPath('code', 'coffre_invalide');
        $this->postJson('/recuperation/envoyer', ['courriel' => 'a@b.bj', 'coffre' => ['v' => 1, 'cle' => $cle]], $h)->assertStatus(422)->assertJsonPath('code', 'coffre_invalide');
        Mail::assertNothingQueued();
    }

    public function test_cle_ou_phrase_jointes_a_un_coffre_valide_sont_refusees(): void
    {
        Mail::fake();
        $this->activer();
        $h = $this->appareil();
        $this->postJson('/recuperation/envoyer', ['courriel' => 'a@b.bj', 'coffre' => $this->coffre(), 'phrase' => 'une phrase assez longue'], $h)->assertStatus(422)->assertJsonPath('code', 'secret_en_clair');
        $this->postJson('/recuperation/envoyer', ['courriel' => 'a@b.bj', 'coffre' => $this->coffre(), 'cle' => bin2hex(random_bytes(32))], $h)->assertStatus(422)->assertJsonPath('code', 'secret_en_clair');
        Mail::assertNothingQueued();
    }

    public function test_courriel_invalide_refuse(): void
    {
        Mail::fake();
        $this->activer();
        $this->postJson('/recuperation/envoyer', ['courriel' => 'pas-un-courriel', 'coffre' => $this->coffre()], $this->appareil())->assertStatus(422)->assertJsonPath('code', 'courriel_invalide');
        Mail::assertNothingQueued();
    }

    public function test_le_courriel_ne_contient_que_le_coffre(): void
    {
        $this->activer();
        $h = $this->appareil();
        $coffre = $this->coffre('phrase-tres-secrete-123');
        $this->postJson('/recuperation/envoyer', ['courriel' => 'Aide@Clinique.bj', 'coffre' => $coffre], $h)->assertOk()->assertJsonPath('envoye', true);
        $messages = app('mailer')->getSymfonyTransport()->messages();
        $this->assertCount(1, $messages);
        $texte = $messages[0]->getOriginalMessage()->toString();
        $this->assertStringContainsString('aide@clinique.bj', strtolower($texte));
        $this->assertStringContainsString($coffre['ct'], str_replace(["=\r\n", "\r\n "], '', $texte));
        $this->assertStringNotContainsString('phrase-tres-secrete-123', $texte);
    }

    public function test_audit_sans_le_contenu_ni_l_adresse_en_clair(): void
    {
        $this->activer();
        $h = $this->appareil();
        $coffre = $this->coffre();
        $this->postJson('/recuperation/envoyer', ['courriel' => 'aide@clinique.bj', 'coffre' => $coffre], $h)->assertOk();
        $ligne = DB::table('relais_audit')->where('action', 'cle_coffre_envoye_par_poste')->first();
        $this->assertNotNull($ligne);
        $this->assertSame('a***@clinique.bj', $ligne->detail);
        $this->assertStringNotContainsString($coffre['ct'], json_encode($ligne));
        $this->assertStringNotContainsString('aide@', json_encode($ligne));
    }

    public function test_limitation_de_debit_trois_par_heure_et_par_appareil(): void
    {
        Mail::fake();
        $this->activer();
        $h = $this->appareil();
        for ($i = 0; $i < 3; $i++) {
            $this->postJson('/recuperation/envoyer', ['courriel' => 'a@b.bj', 'coffre' => $this->coffre()], $h)->assertOk();
        }
        $this->postJson('/recuperation/envoyer', ['courriel' => 'a@b.bj', 'coffre' => $this->coffre()], $h)->assertStatus(429)->assertJsonPath('code', 'trop_de_demandes');
        Mail::assertQueued(CoffreCleMail::class, 3);
    }
}
