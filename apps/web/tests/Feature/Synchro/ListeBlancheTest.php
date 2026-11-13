<?php

namespace Tests\Feature\Synchro;

use App\Relais\Synchro\ListeBlanche;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use PHPUnit\Framework\Attributes\DataProvider;
use Tests\TestCase;

/**
 * Lot RLS-SYNC : la liste blanche des indicateurs de synchronisation, rejouée sur les vecteurs PARTAGÉS avec le domaine Dart et le banc Node
 * (packages/domaine/test/vecteurs/synchro_fileuls.json), puis sur la ROUTE du relais : un refus nommé, jamais un contenu enregistré.
 */
class ListeBlancheTest extends TestCase
{
    use RefreshDatabase;

    private static function vecteurs(): array
    {
        $f = dirname(__DIR__, 5).'/packages/domaine/test/vecteurs/synchro_fileuls.json';
        if (! is_file($f)) {
            test()->markTestSkipped('packages/domaine absent (déploiement sans le dépôt entier).');
        }

        return json_decode(file_get_contents($f), true);
    }

    /** @return array<string, array{0: array, 1: bool, 2: ?string, 3: ?string}> */
    public static function casValider(): array
    {
        $f = dirname(__DIR__, 5).'/packages/domaine/test/vecteurs/synchro_fileuls.json';
        $v = is_file($f) ? json_decode(file_get_contents($f), true) : ['valider' => []];
        $cas = [];
        foreach ($v['valider'] as $c) {
            $charge = $c['charge'];
            if (($charge['fileuls'] ?? null) === 'GENERER_201') {
                $charge['fileuls'] = array_map(fn ($i) => ['poste' => 'F'.$i], range(0, 200));
            }
            $cas[$c['nom']] = [$charge, $c['ok'], $c['code'] ?? null, $c['chemin'] ?? null];
        }

        return $cas;
    }

    /** @dataProvider casValider */
    #[DataProvider('casValider')]
    public function test_les_vecteurs_partages(array $charge, bool $ok, ?string $code, ?string $chemin): void
    {
        $refus = ListeBlanche::verifier($charge);
        if ($ok) {
            $this->assertNull($refus, (string) ($refus['motif'] ?? ''));
        } else {
            $this->assertNotNull($refus, 'un refus était attendu');
            $this->assertSame($code, $refus['code']);
            $this->assertSame($chemin, $refus['chemin']);
            $this->assertNotSame('', $refus['motif']);
            $this->assertNotSame('', $refus['geste']);
        }
    }

    public function test_les_cles_et_la_borne_sont_celles_du_vecteur(): void
    {
        $v = self::vecteurs();
        $this->assertSame($v['cles'], ListeBlanche::CLES);
        $this->assertSame($v['max'], ListeBlanche::MAX);
    }

    public function test_le_nom_technique_d_un_poste_valides_et_invalides(): void
    {
        $v = self::vecteurs();
        foreach ($v['poste']['valides'] as $s) {
            $this->assertTrue(ListeBlanche::posteValide($s), $s);
        }
        foreach ($v['poste']['invalides'] as $s) {
            $this->assertFalse(ListeBlanche::posteValide($s), json_encode($s));
        }
    }

    private function mere(array $indicateurs)
    {
        config(['relais.secret_mere' => 's3cret']);

        return $this->postJson('/mere/indicateurs', ['indicateurs' => $indicateurs], ['x-mere' => 's3cret']);
    }

    public function test_un_envoi_permis_est_enregistre_et_relu_par_la_mere(): void
    {
        $charge = ['seq_max' => 9, 'fileuls' => [['poste' => 'Poste caisse', 'dernierContact' => 1790000000000, 'retardJournal' => 4, 'conflitsOuverts' => 1, 'demandesImportEnAttente' => 0]]];
        $this->mere($charge)->assertOk();
        $this->getJson('/admin/etat', ['x-mere' => 's3cret'])->assertOk()->assertJsonPath('indicateurs.fileuls.0.poste', 'Poste caisse');
        $this->assertSame($charge, json_decode(DB::table('relais_meta')->where('k', 'indicateurs')->value('v'), true));
    }

    public function test_une_cle_inconnue_est_refusee_nommee_et_rien_n_est_enregistre(): void
    {
        $this->mere(['seq_max' => 1, 'fileuls' => [['poste' => 'F1']]])->assertOk();
        $avant = DB::table('relais_meta')->where('k', 'indicateurs')->value('v');
        $this->assertSame(1, DB::table('relais_indicateurs_historique')->count());
        $releves = DB::table('relais_synchro_historique')->count();

        foreach ([['nom', 'KOUASSI Awa'], ['patientId', 'CNT/12/26'], ['motif', 'doublon'], ['libelle', 'Facture 123']] as [$cle, $valeur]) {
            $r = $this->mere(['seq_max' => 2, 'fileuls' => [['poste' => 'F1', $cle => $valeur]]]);
            $r->assertStatus(422)->assertJsonPath('code', 'indicateur_cle_inconnue')->assertJsonPath('chemin', "fileuls[0].$cle");
            $this->assertNotEmpty($r->json('motif'));
            $this->assertNotEmpty($r->json('geste'));
            $this->assertStringNotContainsString($valeur, $r->getContent(), 'le refus ne recopie pas la valeur');
        }
        $this->assertSame($avant, DB::table('relais_meta')->where('k', 'indicateurs')->value('v'), 'un envoi refusé ne remplace rien');
        $this->assertSame(1, DB::table('relais_indicateurs_historique')->count(), 'ni historique des indicateurs');
        $this->assertSame($releves, DB::table('relais_synchro_historique')->count(), 'ni relevé de synchronisation');
    }

    public function test_un_nom_de_dossier_et_un_compteur_non_numerique_sont_refuses(): void
    {
        $this->mere(['fileuls' => [['poste' => 'CNT/12/26']]])->assertStatus(422)->assertJsonPath('code', 'indicateur_valeur_invalide')->assertJsonPath('chemin', 'fileuls[0].poste');
        $this->mere(['fileuls' => [['poste' => 'F1', 'conflitsOuverts' => 'trois']]])->assertStatus(422)->assertJsonPath('chemin', 'fileuls[0].conflitsOuverts');
        $this->mere(['fileuls' => [['poste' => 'F1', 'retardJournal' => 'KOUASSI Awa']]])->assertStatus(422)->assertJsonPath('chemin', 'fileuls[0].retardJournal');
        $this->mere(['fileuls' => [['poste' => 'F1', 'demandesImportEnAttente' => true]]])->assertStatus(422);
        $this->assertNull(DB::table('relais_meta')->where('k', 'indicateurs')->value('v'));
    }

    public function test_une_cle_de_forme_douteuse_n_est_jamais_recopiee_dans_la_reponse(): void
    {
        $r = $this->mere(['fileuls' => [['poste' => 'F1', 'KOUASSI Awa' => 3]]]);
        $r->assertStatus(422)->assertJsonPath('code', 'indicateur_cle_inconnue');
        $this->assertStringNotContainsString('KOUASSI', $r->getContent());
    }

    public function test_l_autorisation_precede_la_validation(): void
    {
        config(['relais.secret_mere' => 's3cret']);
        $this->postJson('/mere/indicateurs', ['indicateurs' => ['fileuls' => [['poste' => 'F1', 'nom' => 'x']]]])->assertStatus(403)->assertJsonPath('code', 'mere_requise');
    }

    public function test_les_indicateurs_anciens_passent_toujours(): void
    {
        $this->mere(['patients_actifs' => 12, 'seq_max' => 5, 'retard_replication' => 0, 'appareils_actifs' => 4])->assertOk();
    }
}
