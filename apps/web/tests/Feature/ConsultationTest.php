<?php

namespace Tests\Feature;

use App\Http\Controllers\ConsultationController;
use App\Models\User;
use App\Relais\Opacite;
use App\Relais\VolumeCopie;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\Concerns\AvecPuitsSmtp;
use Tests\TestCase;

/**
 * Le sens « copie » et la consultation (PRD relais consultable, option B). Le relais reste OPAQUE : il stocke des enveloppes chiffrées par les postes et les sert
 * au seul superadmin, dont le navigateur les déchiffre (public/js/consultation.js). Les tests d'interopérabilité font déchiffrer par CE script (sous Node) des
 * enveloppes fabriquées ici avec le format des postes : nonce de 12 octets, texte chiffré suivi de l'étiquette GCM, AAD « id|appareil|dir|n ».
 */
class ConsultationTest extends TestCase
{
    use AvecPuitsSmtp, RefreshDatabase;

    private const SECRET = 'secret-mere-test';

    private const CLE = 'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90';

    protected function setUp(): void
    {
        parent::setUp();
        config(['relais.secret_mere' => self::SECRET, 'relais.banc' => false]);
    }

    private function appairer(string $uuid): array
    {
        $code = 'CODE-'.$uuid;
        $this->postJson('/mere/code', ['hash' => hash('sha256', $code)], ['x-mere' => self::SECRET])->assertOk();

        return ['Authorization' => 'Bearer '.$this->postJson('/appairage', ['code' => $code, 'uuid' => $uuid])->assertOk()->json('jeton')];
    }

    /** Une enveloppe réelle, au format des postes. */
    private function enveloppe(array $charge, string $appareil, int $n, string $dir = 'copie', ?string $cle = null): array
    {
        $id = "$appareil-$dir-$n";
        $nonce = random_bytes(12);
        $ct = openssl_encrypt(json_encode($charge), 'aes-256-gcm', hex2bin($cle ?? self::CLE), OPENSSL_RAW_DATA, $nonce, $tag, "$id|$appareil|$dir|$n", 16);

        return ['id' => $id, 'appareil' => $appareil, 'dir' => $dir, 'n' => $n, 'nonce' => base64_encode($nonce), 'ct' => base64_encode($ct.$tag)];
    }

    private function node(array $entree): array
    {
        $proc = proc_open(['node', base_path('tests/js/dechiffrer.mjs')], [0 => ['pipe', 'r'], 1 => ['pipe', 'w'], 2 => ['pipe', 'w']], $tubes);
        fwrite($tubes[0], json_encode($entree));
        fclose($tubes[0]);
        $sortie = stream_get_contents($tubes[1]);
        proc_close($proc);

        return json_decode($sortie, true) ?? ['erreur' => 'sortie illisible : '.$sortie];
    }

    private function exigerNode(): void
    {
        if (trim((string) shell_exec('command -v node')) === '') {
            $this->markTestSkipped('Node absent : l\'interopérabilité du script du navigateur n\'est pas mesurable ici.');
        }
    }

    private function superadmin(): User
    {
        return User::factory()->create();
    }

    // --- le sens « copie » ----------------------------------------------------------------------------------------------

    public function test_un_appareil_depose_sa_copie_de_facon_idempotente_a_rangs_contigus(): void
    {
        $f1 = $this->appairer('F1');
        $e1 = $this->enveloppe(['collection' => 'patients', 'fiche' => 'p1', 'data' => ['nom' => 'Awa']], 'F1', 1);
        $this->postJson('/depot', ['enveloppe' => $e1], $f1)->assertOk()->assertJsonMissing(['rejeu' => true]);
        $this->postJson('/depot', ['enveloppe' => $e1], $f1)->assertOk()->assertJson(['rejeu' => true]);
        $this->assertSame(1, DB::table('relais_enveloppes')->where('dir', 'copie')->count());
        $autre = $this->enveloppe(['x' => 1], 'F1', 1);
        $autre['id'] = 'F1-copie-1bis';
        $this->postJson('/depot', ['enveloppe' => $autre], $f1)->assertStatus(409)->assertJson(['code' => 'rang_deja_pris']);
    }

    public function test_seul_un_appareil_appaire_depose_et_seulement_chez_lui(): void
    {
        $f1 = $this->appairer('F1');
        $this->appairer('F2');
        $this->postJson('/depot', ['enveloppe' => $this->enveloppe([], 'F2', 1)], $f1)->assertStatus(403)->assertJson(['code' => 'depot_interdit']);
        $this->postJson('/depot', ['enveloppe' => $this->enveloppe([], 'F1', 1)])->assertStatus(401);
        $this->postJson('/depot', ['enveloppe' => $this->enveloppe([], 'F1', 1)], ['x-mere' => self::SECRET])->assertStatus(403);
        $this->assertSame(0, DB::table('relais_enveloppes')->count());
    }

    public function test_ni_un_appareil_ni_la_mere_ne_relevent_une_copie_par_le_contrat_du_relais(): void
    {
        $f1 = $this->appairer('F1');
        $f2 = $this->appairer('F2');
        $this->postJson('/depot', ['enveloppe' => $this->enveloppe(['a' => 1], 'F1', 1)], $f1)->assertOk();
        $this->getJson('/releve?dir=copie&appareil=F1&depuis_n=0', $f1)->assertStatus(403);
        $this->getJson('/releve?dir=copie&appareil=F1&depuis_n=0', $f2)->assertStatus(403);
        $this->getJson('/releve?dir=copie&appareil=F1&depuis_n=0', ['x-mere' => self::SECRET])->assertStatus(403);
    }

    public function test_la_mere_publie_la_copie_consolidee_sous_l_appareil_mere_et_pas_ailleurs(): void
    {
        $m = ['x-mere' => self::SECRET];
        $this->postJson('/depot', ['enveloppe' => $this->enveloppe(['lot' => []], 'mere', 1)], $m)->assertOk();
        $this->postJson('/depot', ['enveloppe' => $this->enveloppe([], 'F1', 1)], $m)->assertStatus(403)->assertJson(['code' => 'depot_interdit']);
        $this->getJson('/releve?dir=copie&appareil=mere&depuis_n=0', $m)->assertStatus(403);
    }

    public function test_une_copie_plus_recente_remplace_la_precedente_et_les_lots_se_deplient(): void
    {
        $this->exigerNode();
        $charges = [
            ['collection' => 'patients', 'fiche' => 'p1', 'data' => ['tel' => '90'], 'ordre' => [1, 100, 'A', 'o1']],
            ['lot' => [['collection' => 'patients', 'fiche' => 'p1', 'data' => ['tel' => '91'], 'ordre' => [2, 200, 'A', 'o2']], ['collection' => 'patients', 'fiche' => 'p2', 'data' => ['tel' => '92'], 'ordre' => [1, 150, 'B', 'o3']], ['collection' => 'factures', 'fiche' => 'f1', 'data' => []]]],
        ];
        $fiches = $this->node(['action' => 'fiches', 'charges' => $charges, 'collection' => 'patients'])['fiches'];
        $this->assertSame(['p1' => '91', 'p2' => '92'], array_column(array_map(fn ($f) => ['f' => $f['fiche'], 't' => $f['data']['tel']], $fiches), 't', 'f'));
    }

    public function test_toutes_les_ordres_de_lecture_donnent_la_meme_liste_et_une_version_obsolete_tardive_ne_remplace_rien(): void
    {
        $this->exigerNode();
        $v = fn (string $fiche, string $tel, array $ordre, bool $archive = false) => ['collection' => 'patients', 'fiche' => $fiche, 'data' => ['tel' => $tel], 'archive' => $archive, 'ordre' => $ordre];
        $charges = [
            $v('p1', '90', [1, 100, 'A', 'o1']),
            $v('p1', '91', [2, 200, 'A', 'o2']),
            $v('p1', '95', [3, 300, 'B', 'o3']),               // la plus informée : trois opérations connues
            ['lot' => [$v('p2', '10', [1, 120, 'B', 'o4']), $v('p2', '10', [2, 220, 'B', 'o5'], true), $v('p1', '89', [1, 99, 'C', 'o0'])]], // une obsolète dans un lot
            $v('p2', '11', [2, 220, 'A', 'o6']),               // même nombre d'opérations, autre appareil : départage déterministe
            $v('p3', '7', [1, 50, 'A', 'o7']),
        ];
        $r = $this->node(['action' => 'convergence', 'charges' => $charges, 'collection' => 'patients']);
        $this->assertSame(720, $r['permutations']);
        $this->assertSame(1, $r['distincts'], 'tous les ordres de lecture doivent donner la même liste');
        $tels = array_column(array_map(fn ($f) => ['f' => $f['fiche'], 't' => $f['data']['tel']], $r['fiches']), 't', 'f');
        $this->assertSame('95', $tels['p1'], 'la version la plus informée l\'emporte sur les plus anciennes, lot compris');
        $this->assertSame('7', $tels['p3']);
    }

    public function test_une_ancienne_enveloppe_sans_ordre_reste_lisible_et_la_plus_ancienne(): void
    {
        $this->exigerNode();
        $charges = [
            ['collection' => 'patients', 'fiche' => 'p1', 'data' => ['tel' => '1']],
            ['collection' => 'patients', 'fiche' => 'p1', 'data' => ['tel' => '2'], 'ordre' => [1, 10, 'A', 'x']],
        ];
        $fiches = $this->node(['action' => 'fiches', 'charges' => $charges, 'collection' => 'patients'])['fiches'];
        $this->assertCount(1, $fiches);
        $this->assertSame('2', $fiches[0]['data']['tel'], 'toute version avec ordre l\'emporte sur une version sans ordre');
        $inverse = $this->node(['action' => 'fiches', 'charges' => array_reverse($charges), 'collection' => 'patients'])['fiches'];
        $this->assertSame('2', $inverse[0]['data']['tel']);
    }

    public function test_la_consultation_est_fermee_aux_visiteurs_et_ouverte_au_superadmin(): void
    {
        $f1 = $this->appairer('F1');
        $this->postJson('/depot', ['enveloppe' => $this->enveloppe(['a' => 1], 'F1', 1)], $f1)->assertOk();
        foreach (['/panneau/consultation', '/panneau/consultation/appareils', '/panneau/consultation/enveloppes?appareil=F1', '/panneau/consultation/reglage'] as $url) {
            $this->get($url)->assertRedirect('/panneau/connexion');
        }
        $this->actingAs($this->superadmin());
        $this->get('/panneau/consultation')->assertOk()->assertSee('Consultation des copies')->assertSee('js/consultation.js', false);
        $this->getJson('/panneau/consultation/enveloppes?appareil=F1')->assertOk()->assertJsonCount(1, 'env')->assertJsonPath('env.0.n', 1);
        $this->assertDatabaseHas('relais_audit', ['action' => 'copie_lue']);
    }

    // --- l'opacité --------------------------------------------------------------------------------------------------------

    public function test_le_relais_ne_contient_aucun_clair_ni_aucune_cle(): void
    {
        $f1 = $this->appairer('F1');
        $charge = ['collection' => 'patients', 'fiche' => 'p1', 'data' => ['nom' => 'Dossou Awa Marguerite', 'telephone' => '97000001', 'diagnostic' => 'paludisme grave']];
        $this->postJson('/depot', ['enveloppe' => $this->enveloppe($charge, 'F1', 1)], $f1)->assertOk();
        // tout ce que la base détient, toutes tables confondues
        $tout = '';
        foreach (DB::select("select name from sqlite_master where type='table'") as $t) {
            $tout .= json_encode(DB::table($t->name)->get());
        }
        foreach (['Dossou', 'Awa', 'Marguerite', '97000001', 'paludisme', 'telephone', 'diagnostic', self::CLE] as $clair) {
            $this->assertStringNotContainsString($clair, $tout, "« $clair » est lisible au relais");
        }
        $this->assertSame(0, Opacite::mesurer()['lisibles']);
        $this->assertFalse(Opacite::cleDeCliniqueAuRelais());
    }

    public function test_le_code_du_relais_n_importe_aucune_fonction_de_chiffrement(): void
    {
        $interdits = '/\b(openssl_(en|de)crypt|sodium_crypto_\w+|Crypt::(en|de)crypt\w*|mcrypt_\w+|hash_pbkdf2)\b/';
        foreach (['Http/Controllers/RelaisController.php', 'Http/Controllers/ConsultationController.php', 'Relais/VolumeCopie.php'] as $f) {
            $this->assertSame(0, preg_match($interdits, (string) file_get_contents(app_path($f))), "$f chiffre ou déchiffre : le relais doit rester opaque");
        }
    }

    // --- l'interopérabilité du navigateur (script réel sous Node) ---------------------------------------------------------

    public function test_le_script_du_navigateur_dechiffre_une_enveloppe_des_postes(): void
    {
        $this->exigerNode();
        $charge = ['collection' => 'patients', 'fiche' => 'p1', 'data' => ['nom' => 'Dossou Awa']];
        $e = $this->enveloppe($charge, 'F1', 3);
        $this->assertSame($charge, $this->node(['env' => $e, 'cle' => self::CLE])['charge']);
    }

    public function test_une_enveloppe_deplacee_altere_ou_lue_avec_une_autre_cle_ne_se_dechiffre_pas(): void
    {
        $this->exigerNode();
        $e = $this->enveloppe(['a' => 1], 'F1', 3);
        $deplacee = $e;
        $deplacee['n'] = 4; // l'AAD porte le rang : une enveloppe rejouée sous un autre rang est refusée
        $this->assertArrayHasKey('erreur', $this->node(['env' => $deplacee, 'cle' => self::CLE]));
        $autreSens = $e;
        $autreSens['dir'] = 'pair';
        $this->assertArrayHasKey('erreur', $this->node(['env' => $autreSens, 'cle' => self::CLE]));
        $this->assertArrayHasKey('erreur', $this->node(['env' => $e, 'cle' => str_repeat('0', 64)]));
        $abimee = $e;
        $abimee['ct'] = base64_encode(substr_replace(base64_decode($e['ct']), chr(ord(base64_decode($e['ct'])[0]) ^ 1), 0, 1));
        $this->assertArrayHasKey('erreur', $this->node(['env' => $abimee, 'cle' => self::CLE]));
        $this->assertArrayHasKey('erreur', $this->node(['env' => $e, 'cle' => 'trop-court']));
    }

    // --- la récupération de la clé par courriel ---------------------------------------------------------------------------

    public function test_la_recuperation_est_desactivee_par_defaut(): void
    {
        $this->actingAs($this->superadmin());
        $this->getJson('/panneau/consultation/reglage')->assertOk()->assertJson(['actif' => false, 'coffre' => false]);
        $this->postJson('/panneau/consultation/coffre/envoyer')->assertStatus(409)->assertJson(['code' => 'recuperation_desactivee']);
    }

    public function test_seul_un_coffre_chiffre_est_accepte_jamais_la_cle_nue(): void
    {
        $this->actingAs($this->superadmin());
        $base = ['actif' => true, 'courriel' => 'direction@clinique.test'];
        foreach ([self::CLE, base64_encode(hex2bin(self::CLE)), ['v' => 1, 'kdf' => 'PBKDF2-SHA256', 'iter' => 1000, 'sel' => 'AAAAAAAAAAAAAAAAAAAAAA==', 'nonce' => 'AAAAAAAAAAAAAAAA', 'ct' => base64_encode(random_bytes(48))],
            ['v' => 1, 'kdf' => 'PBKDF2-SHA256', 'iter' => 310000, 'sel' => base64_encode(random_bytes(16)), 'nonce' => base64_encode(random_bytes(12)), 'ct' => base64_encode(hex2bin(self::CLE))]] as $mauvais) {
            $this->postJson('/panneau/consultation/reglage', $base + ['coffre' => $mauvais])->assertStatus(422)->assertJson(['code' => 'coffre_invalide']);
        }
        $this->assertNull(DB::table('relais_meta')->where('k', 'cle_recup_coffre')->value('v'));
        $this->postJson('/panneau/consultation/reglage', ['actif' => true, 'courriel' => 'pas-un-courriel', 'coffre' => []])->assertStatus(422)->assertJson(['code' => 'courriel_invalide']);
    }

    public function test_le_coffre_se_cree_dans_le_navigateur_et_se_rouvre_avec_la_phrase_seulement(): void
    {
        $this->exigerNode();
        $this->actingAs($this->superadmin());
        $phrase = 'une phrase secrete assez longue';
        $coffre = $this->node(['action' => 'coffre', 'cle' => self::CLE, 'phrase' => $phrase])['coffre'];
        $this->assertTrue(ConsultationController::coffreValide($coffre));
        $this->postJson('/panneau/consultation/reglage', ['actif' => true, 'courriel' => 'direction@clinique.test', 'coffre' => $coffre])->assertOk()->assertJson(['actif' => true]);
        // ce que le relais conserve : le coffre, ni la clé ni la phrase
        $stocke = json_encode(DB::table('relais_meta')->get()).json_encode(DB::table('relais_audit')->get());
        $this->assertStringNotContainsString(self::CLE, $stocke);
        $this->assertStringNotContainsString($phrase, $stocke);
        $this->assertSame(self::CLE, $this->node(['action' => 'ouvrir', 'coffre' => $coffre, 'phrase' => $phrase])['cle']);
        $this->assertArrayHasKey('erreur', $this->node(['action' => 'ouvrir', 'coffre' => $coffre, 'phrase' => 'une autre phrase assez longue']));
        $this->assertArrayHasKey('erreur', $this->node(['action' => 'coffre', 'cle' => self::CLE, 'phrase' => 'courte']));
    }

    public function test_l_envoi_par_courriel_ne_porte_que_le_coffre_et_la_desactivation_l_efface(): void
    {
        $this->exigerNode();
        $this->demarrerPuits();
        $this->reglerSmtp();
        $this->actingAs($this->superadmin());
        $coffre = $this->node(['action' => 'coffre', 'cle' => self::CLE, 'phrase' => 'une phrase secrete assez longue'])['coffre'];
        $this->postJson('/panneau/consultation/reglage', ['actif' => true, 'courriel' => 'direction@clinique.test', 'coffre' => $coffre])->assertOk();
        $this->postJson('/panneau/consultation/coffre/envoyer')->assertOk()->assertJson(['envoye' => true]);
        $messages = $this->messagesRecus();
        $this->assertCount(1, $messages);
        $corps = $messages[0]['de'].implode(' ', $messages[0]['a']).$messages[0]['data'];
        $this->assertStringContainsString('direction@clinique.test', $corps);
        $this->assertStringNotContainsString(self::CLE, $corps);
        $this->assertStringNotContainsString('une phrase secrete', $corps);
        $this->postJson('/panneau/consultation/reglage', ['actif' => false])->assertOk()->assertJson(['actif' => false]);
        $this->assertSame(0, DB::table('relais_meta')->whereIn('k', ['cle_recup_actif', 'cle_recup_courriel', 'cle_recup_coffre'])->count());
        $this->postJson('/panneau/consultation/coffre/envoyer')->assertStatus(409);
        $this->arreterPuits();
    }

    // --- Q4 : le volume copié ---------------------------------------------------------------------------------------------

    public function test_le_volume_de_la_copie_se_mesure_par_fiche_sans_voir_le_contenu(): void
    {
        $this->assertSame(0, VolumeCopie::mesurer()['fiches']);
        $f1 = $this->appairer('F1');
        $f2 = $this->appairer('F2');
        foreach ([1 => 10, 2 => 400] as $n => $taille) {
            $this->postJson('/depot', ['enveloppe' => $this->enveloppe(['data' => str_repeat('x', $taille)], 'F1', $n)], $f1)->assertOk();
        }
        $this->postJson('/depot', ['enveloppe' => $this->enveloppe(['data' => 'y'], 'F2', 1)], $f2)->assertOk();
        $this->postJson('/depot', ['enveloppe' => $this->enveloppe(['data' => 'pair'], 'F2', 1, 'pair')], $f2)->assertOk(); // une autre boîte ne compte pas
        $m = VolumeCopie::mesurer();
        $this->assertSame(3, $m['fiches']);
        $this->assertCount(2, $m['appareils']);
        $tailles = DB::table('relais_enveloppes')->where('dir', 'copie')->pluck('taille')->all();
        $this->assertSame(array_sum($tailles), $m['octets']);
        $this->assertSame(max($tailles), $m['maximum']);
        $this->assertSame((int) round(array_sum($tailles) / 3), $m['moyenne']);
        $this->artisan('relais:copie-volume')->expectsOutputToContain('3 fiche(s)')->assertSuccessful();
    }
}
