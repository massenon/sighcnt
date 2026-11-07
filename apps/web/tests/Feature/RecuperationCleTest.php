<?php

namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\RateLimiter;
use Tests\Concerns\AvecPuitsSmtp;
use Tests\TestCase;

/** Envoi du coffre de la clé par courriel, à la demande d'un poste appairé : le relais ne manipule qu'un COFFRE. */
class RecuperationCleTest extends TestCase
{
    use AvecPuitsSmtp, RefreshDatabase;

    private const SECRET = 'secret-mere-test';

    protected function setUp(): void
    {
        parent::setUp();
        config(['relais.secret_mere' => self::SECRET, 'relais.banc' => false]);
        RateLimiter::clear('coffre:poste-1');
        // les courriels traversent le VRAI transport SMTP, vers un puits local
        $this->demarrerPuits();
        $this->reglerSmtp();
    }

    protected function tearDown(): void
    {
        $this->arreterPuits();
        parent::tearDown();
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

    private function activer(string $adresse = 'aide@clinique.bj'): void
    {
        DB::table('relais_meta')->updateOrInsert(['k' => 'cle_recup_actif'], ['v' => '1']);
        if ($adresse !== '') {
            DB::table('relais_meta')->updateOrInsert(['k' => 'cle_recup_courriel'], ['v' => $adresse]);
        }
    }

    public function test_reglage_desactive_refus_nomme_et_rien_n_est_envoye(): void
    {
        $h = $this->appareil();
        $this->postJson('/recuperation/envoyer', ['courriel' => 'aide@clinique.bj', 'coffre' => $this->coffre()], $h)
            ->assertStatus(409)->assertJsonPath('code', 'recuperation_desactivee');
        $this->assertCount(0, $this->messagesRecus(), 'rien ne doit partir');
    }

    public function test_appareil_inconnu_refuse(): void
    {
        $this->activer();
        $this->postJson('/recuperation/envoyer', ['courriel' => 'aide@clinique.bj', 'coffre' => $this->coffre()])->assertStatus(401);
        $this->postJson('/recuperation/envoyer', ['courriel' => 'aide@clinique.bj', 'coffre' => $this->coffre()], ['Authorization' => 'Bearer x.y'])->assertStatus(401);
    }

    public function test_cle_nue_refusee_comme_coffre(): void
    {
        $this->activer();
        $h = $this->appareil();
        $cle = bin2hex(random_bytes(32));
        $this->postJson('/recuperation/envoyer', ['courriel' => 'aide@clinique.bj', 'coffre' => $cle], $h)->assertStatus(422)->assertJsonPath('code', 'coffre_invalide');
        $this->postJson('/recuperation/envoyer', ['courriel' => 'aide@clinique.bj', 'coffre' => ['v' => 1, 'cle' => $cle]], $h)->assertStatus(422)->assertJsonPath('code', 'coffre_invalide');
        $this->assertCount(0, $this->messagesRecus(), 'rien ne doit partir');
    }

    public function test_cle_ou_phrase_jointes_a_un_coffre_valide_sont_refusees(): void
    {
        $this->activer();
        $h = $this->appareil();
        $this->postJson('/recuperation/envoyer', ['courriel' => 'aide@clinique.bj', 'coffre' => $this->coffre(), 'phrase' => 'une phrase assez longue'], $h)->assertStatus(422)->assertJsonPath('code', 'secret_en_clair');
        $this->postJson('/recuperation/envoyer', ['courriel' => 'aide@clinique.bj', 'coffre' => $this->coffre(), 'cle' => bin2hex(random_bytes(32))], $h)->assertStatus(422)->assertJsonPath('code', 'secret_en_clair');
        $this->assertCount(0, $this->messagesRecus(), 'rien ne doit partir');
    }

    public function test_un_destinataire_choisi_par_l_appareil_est_refuse_et_rien_ne_part(): void
    {
        $this->activer('aide@clinique.bj');
        $h = $this->appareil();
        foreach (['pirate@exemple.org', 'pas-un-courriel'] as $autre) {
            $this->postJson('/recuperation/envoyer', ['courriel' => $autre, 'coffre' => $this->coffre()], $h)
                ->assertStatus(422)->assertJsonPath('code', 'destinataire_non_autorise');
        }
        $this->assertCount(0, $this->messagesRecus(), 'rien ne doit partir vers une adresse non enregistrée');
    }

    public function test_sans_adresse_enregistree_refus_nomme_409_et_rien_ne_part(): void
    {
        $this->activer('');
        $h = $this->appareil();
        $this->postJson('/recuperation/envoyer', ['coffre' => $this->coffre()], $h)
            ->assertStatus(409)->assertJsonPath('code', 'adresse_non_enregistree');
        $this->postJson('/recuperation/envoyer', ['courriel' => 'pirate@exemple.org', 'coffre' => $this->coffre()], $h)
            ->assertStatus(409)->assertJsonPath('code', 'adresse_non_enregistree');
        $this->assertCount(0, $this->messagesRecus());
    }

    public function test_le_destinataire_est_l_adresse_enregistree_meme_sans_courriel_dans_la_demande(): void
    {
        $this->activer('aide@clinique.bj');
        $this->postJson('/recuperation/envoyer', ['coffre' => $this->coffre()], $this->appareil())->assertOk()->assertJsonPath('envoye', true);
        $messages = $this->messagesRecus();
        $this->assertCount(1, $messages);
        $this->assertSame(['RCPT TO:<aide@clinique.bj>'], $messages[0]['a']);
    }

    public function test_le_courriel_ne_contient_que_le_coffre(): void
    {
        $this->activer();
        $h = $this->appareil();
        $coffre = $this->coffre('phrase-tres-secrete-123');
        $this->postJson('/recuperation/envoyer', ['courriel' => 'Aide@Clinique.bj', 'coffre' => $coffre], $h)->assertOk()->assertJsonPath('envoye', true);
        $messages = $this->messagesRecus();
        $this->assertCount(1, $messages);
        $this->assertSame(['RCPT TO:<aide@clinique.bj>'], $messages[0]['a']);
        $texte = $messages[0]['data'];
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
        $this->activer();
        $h = $this->appareil();
        for ($i = 0; $i < 3; $i++) {
            $this->postJson('/recuperation/envoyer', ['courriel' => 'aide@clinique.bj', 'coffre' => $this->coffre()], $h)->assertOk();
        }
        $this->postJson('/recuperation/envoyer', ['courriel' => 'aide@clinique.bj', 'coffre' => $this->coffre()], $h)->assertStatus(429)->assertJsonPath('code', 'trop_de_demandes');
        $this->assertCount(3, $this->messagesRecus());
    }

    public function test_sans_smtp_regle_refus_nomme_et_rien_n_est_envoye(): void
    {
        DB::table('relais_meta')->where('k', 'like', 'smtp_%')->delete();
        $this->activer();
        $h = $this->appareil();
        $this->postJson('/recuperation/envoyer', ['courriel' => 'aide@clinique.bj', 'coffre' => $this->coffre()], $h)
            ->assertStatus(409)->assertJsonPath('code', 'smtp_non_configure');
        $this->assertCount(0, $this->messagesRecus());
        $this->assertSame(0, DB::table('relais_audit')->where('action', 'cle_coffre_envoye_par_poste')->count(), 'aucun « envoyé » ne doit être journalisé');
    }

    public function test_serveur_injoignable_refus_nomme_a_l_etape_connexion_et_aucun_envoye_au_journal(): void
    {
        $this->arreterPuits();
        $this->activer();
        $h = $this->appareil();
        $this->postJson('/recuperation/envoyer', ['courriel' => 'aide@clinique.bj', 'coffre' => $this->coffre()], $h)
            ->assertStatus(502)->assertJsonPath('code', 'envoi_echoue')->assertJsonPath('etape', 'connexion');
        $this->assertSame(0, DB::table('relais_audit')->where('action', 'cle_coffre_envoye_par_poste')->count());
        $this->assertSame(1, DB::table('relais_audit')->where('action', 'cle_coffre_envoi_echoue')->count());
    }
}
