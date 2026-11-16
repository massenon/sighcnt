<?php

namespace Tests\Feature;

use App\Livewire\Panneau\PasserelleSms;
use App\Models\User;
use App\Relais\Sms\Messages;
use App\Relais\Sms\Reglages;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\Client\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * LOT SMS-R (ADR-0008) : la passerelle SMS du relais. AUCUN envoi réel : les bibliothèques Twilio et Vonage passent par le client HTTP de Laravel, que `Http::fake()` remplace.
 * Les mutations rouges du lot (mot médical admis, consentement ignoré : côté mère ; identifiant non opaque, clair gardé après envoi, plafond dépassable, appareil appairé admis : ici) sont
 * décrites dans `docs/architecture/ECARTS-MAQUETTE.md` E2850 à E2869.
 */
class SmsTest extends TestCase
{
    use RefreshDatabase;

    private const SECRET = 'secret-mere-test';

    private const JETON = 'jeton-twilio-TRES-SECRET-4711';

    protected function setUp(): void
    {
        parent::setUp();
        config(['relais.secret_mere' => self::SECRET, 'relais.banc' => false, 'relais.sms.fournisseur' => 'twilio', 'relais.sms.expediteur' => '+22900000000',
            'relais.sms.twilio_sid' => 'ACtest', 'relais.sms.twilio_token' => self::JETON, 'relais.sms.vonage_key' => 'cle', 'relais.sms.vonage_secret' => 'secretvonage']);
        Http::preventStrayRequests();
    }

    private function id(string $graine): string
    {
        return hash_hmac('sha256', $graine, 'cle-de-clinique-de-test');
    }

    private function message(string $graine = 'a', array $plus = []): array
    {
        return $plus + ['id' => $this->id($graine), 'numero' => '+22997000001', 'texte' => 'Rappel : rendez-vous demain a 09:00. Clinique Nassiera Too.', 'type' => 'rappel_rdv', 'heureEnvoi' => Messages::maintenant() - 1000];
    }

    private function mere(string $methode, string $url, array $corps = [])
    {
        return $this->withHeaders(['x-mere' => self::SECRET])->json($methode, $url, $corps);
    }

    private function twilioOk(): void
    {
        Http::fake(['api.twilio.com/*' => Http::response(['sid' => 'SM'.str_repeat('1', 32), 'status' => 'queued'], 201)]);
    }

    public function test_un_appareil_appaire_est_refuse_en_le_nommant_sur_toute_la_famille(): void
    {
        foreach ([['GET', '/sms/etat'], ['POST', '/sms/deposer'], ['POST', '/sms/annuler'], ['POST', '/sms/tester'], ['GET', '/sms/journal']] as [$m, $u]) {
            $this->withHeaders(['Authorization' => 'Bearer uuid.secret'])->json($m, $u, [])->assertStatus(403)->assertJsonPath('code', 'sms_reserve_mere');
            $this->flushHeaders();
            $this->json($m, $u, [])->assertStatus(403)->assertJsonPath('code', 'mere_requise');
        }
        $this->assertSame(0, DB::table('relais_sms')->count());
    }

    public function test_le_depot_est_idempotent_et_refuse_ce_qui_n_est_pas_opaque_ou_mal_forme(): void
    {
        $m = $this->message();
        $r = $this->mere('POST', '/sms/deposer', ['messages' => [$m]])->assertOk();
        $this->assertSame('planifie', $r->json('messages.0.etat'));
        $r = $this->mere('POST', '/sms/deposer', ['messages' => [$m]])->assertOk();
        $this->assertSame('existant', $r->json('messages.0.etat'));
        $this->assertSame(1, DB::table('relais_sms')->count());

        $refus = $this->mere('POST', '/sms/deposer', ['messages' => [
            $this->message('b', ['id' => 'CNT530/25']),
            $this->message('c', ['id' => 'patient-17']),
            $this->message('d', ['numero' => '97000001']),
            $this->message('e', ['texte' => str_repeat('x', 321)]),
            $this->message('f', ['texte' => '  ']),
            $this->message('g', ['type' => 'campagne']),
            $this->message('h', ['heureEnvoi' => 'demain']),
        ]])->assertOk()->json('messages');
        $this->assertSame(['IDENTIFIANT_NON_OPAQUE', 'IDENTIFIANT_NON_OPAQUE', 'NUMERO_INVALIDE', 'TEXTE_TROP_LONG', 'TEXTE_VIDE', 'TYPE_INCONNU', 'HEURE_INVALIDE'], array_column($refus, 'code'));
        $this->assertSame(1, DB::table('relais_sms')->count(), 'rien de refusé n’entre dans la file');
        $this->assertTrue(mb_strlen(str_repeat('é', 320)) === 320);
        $this->assertSame('planifie', $this->mere('POST', '/sms/deposer', ['messages' => [$this->message('i', ['texte' => str_repeat('é', 320)])]])->json('messages.0.etat'), '320 caractères passent');
    }

    public function test_le_cron_envoie_a_l_heure_et_efface_le_clair(): void
    {
        $this->twilioOk();
        $this->mere('POST', '/sms/deposer', ['messages' => [$this->message('a'), $this->message('futur', ['heureEnvoi' => Messages::maintenant() + 3600000])]])->assertOk();
        $this->artisan('relais:sms-envoyer')->assertSuccessful();

        $a = DB::table('relais_sms')->where('id', $this->id('a'))->first();
        $this->assertSame('envoye', $a->etat);
        $this->assertNull($a->texte, 'le texte est effacé après l’envoi');
        $this->assertNull($a->numero, 'le numéro est effacé après l’envoi');
        $this->assertSame('••••0001', $a->numero_masque);
        $this->assertSame('SM'.str_repeat('1', 32), $a->id_fournisseur);
        $this->assertSame('planifie', DB::table('relais_sms')->where('id', $this->id('futur'))->value('etat'), 'un message futur reste planifié');
        Http::assertSentCount(1);
        Http::assertSent(fn (Request $r) => str_contains($r->url(), 'api.twilio.com') && str_contains($r->body(), 'To=%2B22997000001') && str_contains($r->body(), 'From=%2B22900000000'));

        $this->artisan('relais:sms-envoyer')->assertSuccessful();
        Http::assertSentCount(1);
    }

    public function test_vonage_passe_par_sa_bibliotheque(): void
    {
        config(['relais.sms.fournisseur' => 'vonage']);
        Http::fake(['*' => Http::response(['message-count' => '1', 'messages' => [['to' => '22997000001', 'message-id' => 'VG-1', 'status' => '0', 'remaining-balance' => '1', 'message-price' => '0.01', 'network' => '1']]], 200)]);
        $this->mere('POST', '/sms/deposer', ['messages' => [$this->message('a')]])->assertOk();
        $this->artisan('relais:sms-envoyer')->assertSuccessful();
        $a = DB::table('relais_sms')->first();
        $this->assertSame('envoye', $a->etat);
        $this->assertSame('VG-1', $a->id_fournisseur);
        $this->assertSame('vonage', $a->fournisseur);
        $this->assertNull($a->texte);
        Http::assertSent(fn (Request $r) => str_contains($r->url(), '/sms/json') && str_contains($r->body(), '22997000001'));
    }

    public function test_le_plafond_du_jour_refuse_sans_reporter(): void
    {
        $this->twilioOk();
        Reglages::poser('plafond_jour', 2, 'test');
        $this->mere('POST', '/sms/deposer', ['messages' => [$this->message('a', ['heureEnvoi' => Messages::maintenant() - 3000]), $this->message('b', ['heureEnvoi' => Messages::maintenant() - 2000]), $this->message('c', ['heureEnvoi' => Messages::maintenant() - 1000])]])->assertOk();
        $this->artisan('relais:sms-envoyer')->assertSuccessful();
        $this->assertSame(2, DB::table('relais_sms')->where('etat', 'envoye')->count());
        $c = DB::table('relais_sms')->where('id', $this->id('c'))->first();
        $this->assertSame(['refuse', 'PLAFOND_ATTEINT'], [$c->etat, $c->code], 'bloqué par le plafond : refusé, nommé, PAS reporté');
        $this->assertNull($c->texte);
        Http::assertSentCount(2);
        $this->artisan('relais:sms-envoyer')->assertSuccessful();
        Http::assertSentCount(2);
        $this->assertSame(0, $this->mere('GET', '/sms/etat')->json('plafondRestant'));
    }

    public function test_cinq_tentatives_quand_le_fournisseur_ne_repond_pas_puis_refus(): void
    {
        Http::fake(['api.twilio.com/*' => Http::response('', 503)]);
        $this->mere('POST', '/sms/deposer', ['messages' => [$this->message('a')]])->assertOk();
        for ($i = 1; $i <= 4; $i++) {
            $this->artisan('relais:sms-envoyer')->assertSuccessful();
            $l = DB::table('relais_sms')->first();
            $this->assertSame(['planifie', $i], [$l->etat, (int) $l->tentatives], 'tentative '.$i);
            $this->assertNotNull($l->texte, 'le clair reste tant que le message n’est pas fini');
            $this->artisan('relais:sms-envoyer')->assertSuccessful();
            Http::assertSentCount($i);
            DB::table('relais_sms')->update(['prochaine' => null]);
        }
        $this->artisan('relais:sms-envoyer')->assertSuccessful();
        $l = DB::table('relais_sms')->first();
        $this->assertSame(['refuse', 'FOURNISSEUR_INJOIGNABLE', 5], [$l->etat, $l->code, (int) $l->tentatives]);
        $this->assertNull($l->texte);
        $this->assertNull($l->numero);
    }

    public function test_un_refus_du_fournisseur_est_nomme_et_n_est_pas_retente(): void
    {
        $reponse = [401, []];
        Http::fake(['api.twilio.com/*' => function () use (&$reponse) { return Http::response($reponse[1], $reponse[0]); }]);
        foreach ([[401, [], 'IDENTIFIANTS_REFUSES'], [402, [], 'SOLDE_INSUFFISANT'], [400, ['code' => 21211, 'message' => 'invalide'], 'NUMERO_INVALIDE'], [400, ['code' => 21612, 'message' => 'x'], 'EXPEDITEUR_NON_AUTORISE']] as [$http, $corps, $code]) {
            DB::table('relais_sms')->delete();
            $reponse = [$http, $corps];
            $this->mere('POST', '/sms/deposer', ['messages' => [$this->message('a')]])->assertOk();
            $this->artisan('relais:sms-envoyer')->assertSuccessful();
            $l = DB::table('relais_sms')->first();
            $this->assertSame(['refuse', $code, 1], [$l->etat, $l->code, (int) $l->tentatives], $code);
            $this->assertNull($l->texte);
        }
    }

    public function test_sans_identifiants_le_message_attend_et_le_dit_puis_perime(): void
    {
        config(['relais.sms.twilio_token' => '']);
        $this->mere('POST', '/sms/deposer', ['messages' => [$this->message('a')]])->assertOk();
        $this->artisan('relais:sms-envoyer')->assertSuccessful();
        $this->assertSame('planifie', DB::table('relais_sms')->value('etat'));
        $e = $this->mere('GET', '/sms/etat')->assertOk()->json();
        $this->assertFalse($e['identifiantsDefinis']);
        $this->assertFalse($e['configuree']);
        $t = $this->mere('POST', '/sms/tester', ['numero' => '+22997000001'])->assertOk();
        $this->assertSame('SECRET_NON_DEFINI', $t->json('code'));
        Http::assertNothingSent();

        DB::table('relais_sms')->update(['heure_envoi' => Messages::maintenant() - 4 * 3600000]);
        $this->artisan('relais:sms-envoyer')->assertSuccessful();
        $this->assertSame('HEURE_DEPASSEE', DB::table('relais_sms')->value('code'));
        $this->assertNull(DB::table('relais_sms')->value('texte'));
    }

    public function test_annuler_retire_un_envoi_planifie_mais_pas_un_envoi_parti(): void
    {
        $this->twilioOk();
        $this->mere('POST', '/sms/deposer', ['messages' => [$this->message('a'), $this->message('b', ['heureEnvoi' => Messages::maintenant() + 3600000])]])->assertOk();
        $this->artisan('relais:sms-envoyer')->assertSuccessful();
        $r = $this->mere('POST', '/sms/annuler', ['ids' => [$this->id('a'), $this->id('b'), $this->id('inconnu')]])->assertOk()->json('messages');
        $this->assertSame(['deja_parti', 'retire', 'inconnu'], array_column($r, 'etat'));
        $b = DB::table('relais_sms')->where('id', $this->id('b'))->first();
        $this->assertSame('retire', $b->etat);
        $this->assertNull($b->texte);
        $this->assertNull($b->numero);
        // Replanifié (rendez-vous rétabli) : permis ; un message parti, jamais.
        $r = $this->mere('POST', '/sms/deposer', ['messages' => [$this->message('b', ['heureEnvoi' => Messages::maintenant() + 7200000]), $this->message('a')]])->json('messages');
        $this->assertSame(['planifie', 'existant'], array_column($r, 'etat'));
        Http::assertSentCount(1);
    }

    public function test_le_test_d_envoi_et_le_journal_ne_rendent_ni_secret_ni_clair(): void
    {
        $this->twilioOk();
        $t = $this->mere('POST', '/sms/tester', ['numero' => '+22997000002'])->assertOk();
        $this->assertTrue($t->json('ok'));
        Http::assertSent(fn (Request $r) => str_contains($r->body(), urlencode(Messages::TEXTE_TEST)));
        $this->assertSame('NUMERO_INVALIDE', $this->mere('POST', '/sms/tester', ['numero' => '0022997'])->json('code'));

        $this->mere('POST', '/sms/deposer', ['messages' => [$this->message('a')]])->assertOk();
        $this->artisan('relais:sms-envoyer')->assertSuccessful();
        $brut = $this->mere('GET', '/sms/journal')->assertOk()->getContent().$this->mere('GET', '/sms/etat')->getContent().$t->getContent();
        foreach ([self::JETON, 'ACtest', 'secretvonage', '22997000001', '22997000002', 'rendez-vous', 'Clinique'] as $interdit) {
            $this->assertStringNotContainsString($interdit, $brut, 'jamais : '.$interdit);
        }
        $this->assertSame('test', $this->mere('GET', '/sms/journal')->json('messages.1.type'));
    }

    public function test_le_panneau_dit_defini_ou_non_sans_rendre_le_secret_et_regle_les_limites(): void
    {
        $this->actingAs(User::factory()->create(['superadmin' => true]));
        $this->twilioOk();
        $this->mere('POST', '/sms/deposer', ['messages' => [$this->message('a', ['heureEnvoi' => Messages::maintenant() + 3600000])]])->assertOk();
        $this->get('/panneau/sms')->assertOk()->assertSee('Passerelle SMS')->assertSee('défini')->assertSee('••••0001')->assertSee('Ce que le relais ne voit jamais')
            ->assertDontSee(self::JETON)->assertDontSee('22997000001')->assertDontSee('rendez-vous demain');
        Livewire::test(PasserelleSms::class)->set('numeroTest', '+22997000003')->call('tester')->assertSee('Accepté par le fournisseur')
            ->set('limites.plafond_jour', 0)->call('enregistrerLimites')->assertSee('Plafond de messages par jour')
            ->set('limites.plafond_jour', 150)->call('enregistrerLimites')->assertSee('enregistrées');
        $this->assertSame(150, Reglages::toutes()['plafond_jour']);
        $this->assertSame(1, DB::table('relais_audit')->where('action', 'reglage_sms')->count());
    }

    public function test_la_tache_est_planifiee_chaque_minute_sans_chevauchement(): void
    {
        $e = collect(app(\Illuminate\Console\Scheduling\Schedule::class)->events())->first(fn ($ev) => str_contains($ev->command, 'relais:sms-envoyer'));
        $this->assertNotNull($e);
        $this->assertSame('* * * * *', $e->expression);
        $this->assertTrue($e->withoutOverlapping);
    }

    public function test_le_plafond_compte_les_jours_a_l_heure_du_benin(): void
    {
        // 23:30 UTC le 10 est déjà le 11 au Bénin (UTC+1).
        $ms = \Carbon\CarbonImmutable::parse('2026-11-10 23:30:00', 'UTC')->getTimestampMs();
        $this->assertSame('2026-11-11', Messages::jour($ms));
        $this->assertSame('2026-11-10', Messages::jour($ms - 3600000));
    }
}
