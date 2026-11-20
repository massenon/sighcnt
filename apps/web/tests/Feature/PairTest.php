<?php

namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Le sens « pair » du relais (ADR-0006) : les fileuls s'échangent leurs opérations par le relais, la mère étant éteinte. Le contrat est celui du relais de
 * référence (packages/sync/banc/relais.js) ; le relais reste OPAQUE et sans règle métier.
 */
class PairTest extends TestCase
{
    use RefreshDatabase;

    private const SECRET = 'secret-mere-test';

    protected function setUp(): void
    {
        parent::setUp();
        config(['relais.secret_mere' => self::SECRET, 'relais.banc' => false]);
    }

    private function appairer(string $uuid): array
    {
        $code = 'CODE-'.$uuid;
        $this->postJson('/mere/code', ['hash' => hash('sha256', $code)], ['x-mere' => self::SECRET])->assertOk();
        $r = $this->postJson('/appairage', ['code' => $code, 'uuid' => $uuid])->assertOk();

        return ['Authorization' => 'Bearer '.$r->json('jeton')];
    }

    private function env(string $id, string $appareil, int $n, string $dir = 'pair'): array
    {
        return ['enveloppe' => ['id' => $id, 'appareil' => $appareil, 'dir' => $dir, 'n' => $n, 'nonce' => 'bm9uY2U=', 'ct' => 'AAAA']];
    }

    public function test_un_appareil_depose_dans_son_propre_journal_pair_de_facon_idempotente(): void
    {
        $f1 = $this->appairer('F1');
        $this->postJson('/depot', $this->env('F1-pair-1', 'F1', 1), $f1)->assertOk()->assertJsonMissing(['rejeu' => true]);
        $this->postJson('/depot', $this->env('F1-pair-1', 'F1', 1), $f1)->assertOk()->assertJson(['rejeu' => true]);
        $this->assertDatabaseCount('relais_enveloppes', 1);
        $this->postJson('/depot', $this->env('F1-pair-1bis', 'F1', 1), $f1)->assertStatus(409)->assertJson(['code' => 'rang_deja_pris']);
    }

    public function test_un_appareil_ne_depose_jamais_dans_le_journal_d_un_autre(): void
    {
        $f1 = $this->appairer('F1');
        $this->appairer('F2');
        $this->postJson('/depot', $this->env('x-1', 'F2', 1), $f1)->assertStatus(403)->assertJson(['code' => 'depot_interdit']);
        $this->assertDatabaseCount('relais_enveloppes', 0);
    }

    public function test_la_mere_de_retour_ne_depose_que_dans_son_propre_journal_pair_et_relit_tous_les_journaux(): void
    {
        $mere = ['x-mere' => self::SECRET];
        $f1 = $this->appairer('F1');
        // dans le journal d'un fileul : interdit (comme tout autre appareil)
        $this->postJson('/depot', $this->env('x-1', 'F1', 1), $mere)->assertStatus(403)->assertJson(['code' => 'depot_interdit']);
        // dans SON journal (appareil « mere ») : permis, idempotent
        $this->postJson('/depot', $this->env('pair-mere-1', 'mere', 1), $mere)->assertOk();
        $this->postJson('/depot', $this->env('pair-mere-1', 'mere', 1), $mere)->assertOk()->assertJson(['rejeu' => true]);
        $this->postJson('/depot', $this->env('F1-pair-1', 'F1', 1), $f1)->assertOk();
        // la mère relève le journal pair des fileuls et la liste des journaux ; les fileuls relèvent celui de la mère
        $this->getJson('/releve?dir=pair&appareil=F1&depuis_n=0', $mere)->assertOk()->assertJsonCount(1, 'env');
        $liste = collect($this->getJson('/pair/appareils', $mere)->assertOk()->json('appareils'))->pluck('max_n', 'uuid')->map(fn ($n) => (int) $n)->all();
        $this->assertSame(['F1' => 1, 'mere' => 1], $liste);
        $this->getJson('/releve?dir=pair&appareil=mere&depuis_n=0', $f1)->assertOk()->assertJsonCount(1, 'env');
        // un sens inconnu reste interdit à la mère
        $this->postJson('/depot', $this->env('m-2', 'mere', 1, 'inconnu'), $mere)->assertStatus(403)->assertJson(['code' => 'depot_interdit']);
    }

    public function test_tout_appareil_appaire_releve_le_journal_pair_des_autres_mais_pas_leur_boite_privee(): void
    {
        $f1 = $this->appairer('F1');
        $f2 = $this->appairer('F2');
        foreach ([1, 2, 3] as $n) {
            $this->postJson('/depot', $this->env("F1-pair-$n", 'F1', $n), $f1)->assertOk();
        }
        $r = $this->getJson('/releve?dir=pair&appareil=F1&depuis_n=1&limite=50', $f2)->assertOk();
        $this->assertSame([2, 3], collect($r->json('env'))->pluck('n')->all());
        $this->assertTrue($r->json('fin'));
        // la boîte vers_mobile d'un autre appareil reste privée
        $this->getJson('/releve?dir=vers_mobile&appareil=F1&depuis_n=0', $f2)->assertStatus(403)->assertJson(['code' => 'lecture_interdite']);
    }

    public function test_sans_jeton_ou_apres_revocation_le_journal_pair_est_ferme(): void
    {
        $f1 = $this->appairer('F1');
        $this->postJson('/depot', $this->env('F1-pair-1', 'F1', 1), $f1)->assertOk();
        $this->getJson('/releve?dir=pair&appareil=F1&depuis_n=0')->assertStatus(401);
        $this->getJson('/pair/appareils')->assertStatus(401);
        $this->postJson('/mere/revoquer', ['uuid' => 'F1'], ['x-mere' => self::SECRET])->assertOk();
        $this->getJson('/releve?dir=pair&appareil=F1&depuis_n=0', $f1)->assertStatus(401)->assertJson(['code' => 'appareil_revoque']);
        $this->postJson('/depot', $this->env('F1-pair-2', 'F1', 2), $f1)->assertStatus(401);
    }

    public function test_la_liste_des_journaux_pair_ne_donne_que_l_appareil_et_le_dernier_rang(): void
    {
        $f1 = $this->appairer('F1');
        $f2 = $this->appairer('F2');
        $this->postJson('/depot', $this->env('F1-pair-1', 'F1', 1), $f1)->assertOk();
        $this->postJson('/depot', $this->env('F1-pair-2', 'F1', 2), $f1)->assertOk();
        $this->postJson('/depot', $this->env('F2-pair-1', 'F2', 1), $f2)->assertOk();
        $this->postJson('/depot', $this->env('F2-vm-1', 'F2', 1, 'vers_mere'), $f2)->assertOk();
        $r = $this->getJson('/pair/appareils', $f1)->assertOk();
        $liste = collect($r->json('appareils'))->mapWithKeys(fn ($a) => [$a['uuid'] => (int) $a['max_n']])->all();
        $this->assertSame(['F1' => 2, 'F2' => 1], $liste, 'seuls les journaux pair, sans contenu, sans la boîte vers la mère');
        foreach ($r->json('appareils') as $a) {
            $this->assertEqualsCanonicalizing(['uuid', 'max_n'], array_keys($a));
        }
    }
}
