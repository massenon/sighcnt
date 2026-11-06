<?php

namespace Tests\Feature;

use App\Models\User;
use App\Relais\ReglagesSmtp;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Crypt;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\RateLimiter;
use Tests\Concerns\AvecPuitsSmtp;
use Tests\TestCase;

/**
 * Messagerie SMTP du relais : réglage dans le panneau, mot de passe chiffré jamais relu, message de test et envoi du coffre par un VRAI transport SMTP vers un
 * puits local (tests/outils/puits_smtp.php), étape en échec nommée. Aucun fournisseur réel n'est joignable depuis l'environnement de test.
 */
class SmtpTest extends TestCase
{
    use AvecPuitsSmtp, RefreshDatabase;

    private const MDP = 'Mdp-Tres-Secret-9137';

    protected function setUp(): void
    {
        parent::setUp();
        RateLimiter::clear('coffre:poste-1');
        $this->actingAs(User::factory()->create());
    }

    protected function tearDown(): void
    {
        $this->arreterPuits();
        parent::tearDown();
    }

    private function formulaire(array $plus = []): array
    {
        return $plus + [
            'hote' => '127.0.0.1', 'port' => $this->puitsPort, 'chiffrement' => 'aucun', 'utilisateur' => '', 'mdp' => '',
            'expediteur' => 'relais@clinique.bj', 'expediteur_nom' => 'Relais SIGH-CNT', 'verifier_certificat' => false,
        ];
    }

    public function test_le_message_de_test_arrive_avec_sujet_corps_expediteur_destinataire_et_accents(): void
    {
        $this->demarrerPuits();
        $this->postJson('/panneau/smtp', $this->formulaire())->assertOk()->assertJsonPath('configure', true);
        $this->postJson('/panneau/smtp/test', ['destinataire' => 'direction@clinique.bj'])->assertOk()->assertJson(['envoye' => true]);
        $messages = $this->messagesRecus();
        $this->assertCount(1, $messages);
        $this->assertSame(['RCPT TO:<direction@clinique.bj>'], $messages[0]['a']);
        $this->assertStringContainsString('relais@clinique.bj', $messages[0]['de']);
        $lu = $this->lire($messages[0]);
        $this->assertSame('SIGH-CNT : message de test de la messagerie du relais', $lu['sujet']);
        $this->assertStringContainsString('Natitingou (Bénin)', $lu['corps']);
        $this->assertStringContainsString('œ et €', $lu['corps']);
        $this->assertStringContainsString('Relais SIGH-CNT', $lu['entetes']);
    }

    public function test_repondre_a_est_un_en_tete_du_message_recu_et_reste_absent_quand_il_n_est_pas_regle(): void
    {
        $this->demarrerPuits();
        $this->postJson('/panneau/smtp', $this->formulaire(['repondre' => 'cliniquenassiera@gmail.com', 'repondre_nom' => 'Clinique Nassièra Too']))->assertOk()->assertJsonPath('repondre', 'cliniquenassiera@gmail.com');
        $this->postJson('/panneau/smtp/test', ['destinataire' => 'direction@clinique.bj'])->assertOk();
        $this->assertMatchesRegularExpression('/^Reply-To:[^\\r\\n]*(\\r?\\n[ \\t][^\\r\\n]*)*cliniquenassiera@gmail\.com/mi', $this->lire($this->messagesRecus()[0])['entetes']);
        $this->postJson('/panneau/smtp', $this->formulaire(['repondre' => '', 'repondre_nom' => '']))->assertOk();
        $this->postJson('/panneau/smtp/test', ['destinataire' => 'direction@clinique.bj'])->assertOk();
        $this->assertDoesNotMatchRegularExpression('/^Reply-To:/mi', $this->lire($this->messagesRecus()[1])['entetes']);
        $this->postJson('/panneau/smtp', $this->formulaire(['repondre' => 'pas-une-adresse']))->assertStatus(422);
    }

    public function test_starttls_le_message_arrive_chiffre_et_un_certificat_non_verifiable_est_refuse_a_l_etape_chiffrement(): void
    {
        $this->demarrerPuits(['tls' => 'starttls']);
        $this->postJson('/panneau/smtp', $this->formulaire(['chiffrement' => 'starttls', 'verifier_certificat' => false]))->assertOk();
        $this->postJson('/panneau/smtp/test', ['destinataire' => 'a@clinique.bj'])->assertOk();
        $this->assertTrue($this->messagesRecus()[0]['chiffre'], 'le message doit être passé par la session chiffrée');
        // certificat auto-signé + vérification demandée : refusé, à l'étape chiffrement
        $this->postJson('/panneau/smtp', $this->formulaire(['chiffrement' => 'starttls', 'verifier_certificat' => true]))->assertOk();
        $this->postJson('/panneau/smtp/test', ['destinataire' => 'a@clinique.bj'])->assertStatus(502)->assertJsonPath('code', 'smtp_echec')->assertJsonPath('etape', 'chiffrement');
        $this->assertCount(1, $this->messagesRecus());
    }

    public function test_starttls_exige_refuse_un_serveur_qui_ne_le_propose_pas(): void
    {
        $this->demarrerPuits();
        $this->postJson('/panneau/smtp', $this->formulaire(['chiffrement' => 'starttls']))->assertOk();
        $this->postJson('/panneau/smtp/test', ['destinataire' => 'a@clinique.bj'])->assertStatus(502)->assertJsonPath('etape', 'chiffrement');
        $this->assertCount(0, $this->messagesRecus(), 'jamais de repli en clair quand le chiffrement est exigé');
    }

    public function test_ssl_implicite(): void
    {
        $this->demarrerPuits(['tls' => 'ssl']);
        $this->postJson('/panneau/smtp', $this->formulaire(['chiffrement' => 'ssl']))->assertOk();
        $this->postJson('/panneau/smtp/test', ['destinataire' => 'a@clinique.bj'])->assertOk();
        $this->assertTrue($this->messagesRecus()[0]['chiffre']);
    }

    public function test_authentification_bon_mot_de_passe_accepte_mauvais_refuse_a_l_etape_authentification(): void
    {
        $this->demarrerPuits(['user' => 'relais', 'pass' => self::MDP]);
        $this->postJson('/panneau/smtp', $this->formulaire(['utilisateur' => 'relais', 'mdp' => self::MDP]))->assertOk();
        $this->postJson('/panneau/smtp/test', ['destinataire' => 'a@clinique.bj'])->assertOk();
        $this->assertCount(1, $this->messagesRecus());

        $this->postJson('/panneau/smtp', $this->formulaire(['utilisateur' => 'relais', 'mdp' => 'mauvais-mot-de-passe']))->assertOk();
        $r = $this->postJson('/panneau/smtp/test', ['destinataire' => 'a@clinique.bj'])->assertStatus(502)->assertJsonPath('etape', 'authentification');
        $this->assertStringNotContainsString('mauvais-mot-de-passe', $r->getContent());
        $this->assertCount(1, $this->messagesRecus(), 'rien de plus n\'est arrivé');
    }

    public function test_serveur_qui_exige_une_authentification_sans_identifiant_refuse_a_l_etape_authentification(): void
    {
        $this->demarrerPuits(['user' => 'relais', 'pass' => self::MDP]);
        $this->postJson('/panneau/smtp', $this->formulaire())->assertOk();
        $this->postJson('/panneau/smtp/test', ['destinataire' => 'a@clinique.bj'])->assertStatus(502)->assertJsonPath('etape', 'authentification');
    }

    public function test_port_ferme_refuse_a_l_etape_connexion(): void
    {
        $this->demarrerPuits();
        $port = $this->puitsPort;
        $this->arreterPuits();
        $this->postJson('/panneau/smtp', $this->formulaire(['port' => $port]))->assertOk();
        $this->postJson('/panneau/smtp/test', ['destinataire' => 'a@clinique.bj'])->assertStatus(502)->assertJsonPath('code', 'smtp_echec')->assertJsonPath('etape', 'connexion');
    }

    public function test_destinataire_et_expediteur_refuses_par_le_serveur_sont_nommes(): void
    {
        $this->demarrerPuits();
        $this->postJson('/panneau/smtp', $this->formulaire())->assertOk();
        $this->postJson('/panneau/smtp/test', ['destinataire' => 'inconnu@clinique.bj'])->assertStatus(502)->assertJsonPath('etape', 'destinataire');
        $this->postJson('/panneau/smtp', $this->formulaire(['expediteur' => 'refuse@clinique.bj']))->assertOk();
        $this->postJson('/panneau/smtp/test', ['destinataire' => 'a@clinique.bj'])->assertStatus(502)->assertJsonPath('etape', 'expediteur');
        $this->assertCount(0, $this->messagesRecus());
    }

    public function test_le_mot_de_passe_n_apparait_ni_en_base_en_clair_ni_dans_le_journal_ni_dans_la_page_ni_dans_les_reponses(): void
    {
        $this->demarrerPuits(['user' => 'relais', 'pass' => self::MDP]);
        $r = $this->postJson('/panneau/smtp', $this->formulaire(['utilisateur' => 'relais', 'mdp' => self::MDP]))->assertOk();
        $this->assertStringNotContainsString(self::MDP, $r->getContent());
        $this->assertTrue($r->json('mdp_defini'));
        $this->assertArrayNotHasKey('mdp', $r->json());
        $this->postJson('/panneau/smtp/test', ['destinataire' => 'a@clinique.bj'])->assertOk();
        $this->postJson('/panneau/smtp', $this->formulaire(['utilisateur' => 'relais', 'mdp' => 'faux']))->assertOk();
        $this->postJson('/panneau/smtp/test', ['destinataire' => 'a@clinique.bj'])->assertStatus(502);
        $this->postJson('/panneau/smtp', $this->formulaire(['utilisateur' => 'relais', 'mdp' => self::MDP]))->assertOk();

        foreach (['relais_meta', 'relais_audit'] as $table) {
            $this->assertStringNotContainsString(self::MDP, json_encode(DB::table($table)->get()), "$table ne doit pas porter le mot de passe en clair");
        }
        $stocke = DB::table('relais_meta')->where('k', 'smtp_mdp')->value('v');
        $this->assertNotSame(self::MDP, $stocke);
        $this->assertSame(self::MDP, Crypt::decryptString($stocke), 'chiffré par la clé de l\'application, récupérable seulement par elle');
        $this->assertStringNotContainsString(self::MDP, $this->get('/panneau/parametres')->getContent());
        $this->assertStringNotContainsString(self::MDP, $this->getJson('/panneau/smtp')->getContent());
        $this->assertStringNotContainsString(self::MDP, (string) @file_get_contents(storage_path('logs/laravel.log')));
    }

    public function test_mot_de_passe_vide_conserve_l_ancien_et_effacer_le_retire(): void
    {
        $this->demarrerPuits(['user' => 'relais', 'pass' => self::MDP]);
        $this->postJson('/panneau/smtp', $this->formulaire(['utilisateur' => 'relais', 'mdp' => self::MDP]))->assertOk();
        $this->postJson('/panneau/smtp', $this->formulaire(['utilisateur' => 'relais', 'mdp' => '', 'expediteur_nom' => 'Autre nom']))->assertOk()->assertJsonPath('mdp_defini', true);
        $this->postJson('/panneau/smtp/test', ['destinataire' => 'a@clinique.bj'])->assertOk();
        $this->postJson('/panneau/smtp', $this->formulaire(['utilisateur' => 'relais', 'effacer_mdp' => true]))->assertOk()->assertJsonPath('mdp_defini', false);
        $this->postJson('/panneau/smtp/test', ['destinataire' => 'a@clinique.bj'])->assertStatus(502)->assertJsonPath('etape', 'authentification');
    }

    public function test_sans_reglage_le_test_est_refuse_en_le_nommant(): void
    {
        $this->postJson('/panneau/smtp/test', ['destinataire' => 'a@clinique.bj'])->assertStatus(409)->assertJsonPath('code', 'smtp_non_configure');
        $this->assertFalse(ReglagesSmtp::configure());
    }

    public function test_validation_du_formulaire(): void
    {
        $this->postJson('/panneau/smtp', $this->formulaire(['hote' => 'exemple.bj; rm -rf /', 'port' => 70000, 'chiffrement' => 'ssl3', 'expediteur' => 'pas-un-courriel']))
            ->assertStatus(422)->assertJsonValidationErrors(['hote', 'port', 'chiffrement', 'expediteur']);
    }

    public function test_reserve_au_superadmin_connecte_et_le_test_est_limite(): void
    {
        $this->demarrerPuits();
        $this->postJson('/panneau/smtp', $this->formulaire())->assertOk();
        for ($i = 0; $i < 5; $i++) {
            $this->postJson('/panneau/smtp/test', ['destinataire' => 'a@clinique.bj'])->assertOk();
        }
        $this->postJson('/panneau/smtp/test', ['destinataire' => 'a@clinique.bj'])->assertStatus(429);
        $this->app['auth']->guard()->logout();
        $this->flushSession();
        $this->postJson('/panneau/smtp', $this->formulaire())->assertStatus(401);
        $this->getJson('/panneau/smtp')->assertStatus(401);
        $this->postJson('/panneau/smtp/test', ['destinataire' => 'a@clinique.bj'])->assertStatus(401);
    }
}
