<?php

namespace Tests\Feature;

use App\Relais\Opacite;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/**
 * Lot IDENT (décision de la Direction, 16/11/2026) : l'identité de la clinique (dénomination, IFU, RCCM, adresse, téléphones), ses versions datées, les demandes signées d'un fileul habilité et les
 * options d'impression se DÉPOSENT au relais web, qui les stocke CHIFFRÉES et n'en lit rien (décision du 09/11). Ici, ce que le VRAI relais Laravel garantit : les octets stockés ne contiennent
 * aucune des valeurs (le RCCM compris), leur entropie est celle d'un chiffrement authentifié, et la clé de clinique n'est pas au relais. La contre-épreuve avec la clé montre que l'enveloppe n'est pas vide.
 * Le test de bout en bout (poste habilité, mère, deux fileuls, mobile) est `apps/poste/test/identite_propagation_sync_test.dart`.
 */
class IdentiteOpaqueTest extends TestCase
{
    use RefreshDatabase;

    private const SECRET = 'secret-mere-test';

    protected function setUp(): void
    {
        parent::setUp();
        config(['relais.secret_mere' => self::SECRET, 'relais.banc' => false]);
    }

    private function enveloppe(string $cle, array $charge, int $n): array
    {
        $id = "journal-$n";
        $nonce = random_bytes(12);
        $tag = '';
        $ct = openssl_encrypt(json_encode($charge, JSON_UNESCAPED_UNICODE), 'aes-256-gcm', $cle, OPENSSL_RAW_DATA, $nonce, $tag, "$id|mere|journal|$n");

        return ['id' => $id, 'appareil' => 'mere', 'dir' => 'journal', 'n' => $n, 'nonce' => base64_encode($nonce), 'ct' => base64_encode($ct.$tag)];
    }

    private function charge(): array
    {
        $motif = str_repeat('Mise à jour des informations de la clinique par la Direction ', 40);

        return ['type' => 'journal', 'ops' => [
            ['seq' => 1, 'id' => 'ref-1', 'appareil' => 'mere', 'collection' => 'identiteLegale', 'fiche' => 'IDL003', 'type' => 'creer',
                'champs' => ['version' => 3, 'debut' => '2026-12-01', 'nom' => 'CLINIQUE NASSIERA TOO SARL', 'ifu' => '3201642748214', 'rccm' => 'NAT/2021/M02-020',
                    'bp' => 'BP : 999 NATITINGOU (Rép. du Bénin)', 'telephones' => ['01 11 22 33 44', '01 55 66 77 88'], 'creePar' => 'TAKI Alimatou', 'motif' => $motif]],
            ['seq' => 2, 'id' => 'ref-2', 'appareil' => 'mere', 'collection' => 'demandesIdentite', 'fiche' => 'DIF1', 'type' => 'creer',
                'champs' => ['etat' => 'deposee', 'demandePar' => 'TAKI Alimatou', 'demandeRole' => 'direction', 'champs' => ['rccm' => 'NAT/2021/M02-020'], 'motif' => $motif]],
            ['seq' => 3, 'id' => 'ref-3', 'appareil' => 'mere', 'collection' => 'optionsImpression', 'fiche' => 'OPT-filigrane', 'type' => 'creer',
                'champs' => ['cle' => 'filigrane', 'valeur' => 'Confidentiel', 'modifiePar' => 'TAKI Alimatou']],
        ]];
    }

    public function test_l_identite_deposee_par_la_mere_est_stockee_chiffree_et_illisible(): void
    {
        $cle = random_bytes(32);
        $this->postJson('/depot', ['enveloppe' => $this->enveloppe($cle, $this->charge(), 1)], ['x-mere' => self::SECRET])->assertOk();

        $ligne = DB::table('relais_enveloppes')->where('dir', 'journal')->first();
        $this->assertNotNull($ligne);
        $octets = base64_decode($ligne->ct, true);
        foreach (['NAT/2021/M02-020', '3201642748214', 'CLINIQUE NASSIERA', 'NATITINGOU', '01 11 22 33 44', 'TAKI Alimatou', 'identiteLegale', 'demandesIdentite', 'optionsImpression', 'Confidentiel'] as $clair) {
            $this->assertStringNotContainsString($clair, $octets, "« $clair » ne doit pas se lire dans les octets stockés");
            $this->assertStringNotContainsString($clair, (string) $ligne->ct);
        }
        $this->assertGreaterThan(7.5, Opacite::entropie($octets), 'un chiffrement authentifié ressemble à du hasard : on mesure, on ne cherche pas du texte');
        $m = Opacite::mesurer();
        $this->assertSame(0, $m['lisibles']);
        $this->assertFalse(Opacite::cleDeCliniqueAuRelais());

        // Contre-épreuve : avec la clé de clinique (que le relais n'a pas), le RCCM est bien là. L'opacité ne vient donc pas d'une enveloppe vide.
        $brut = base64_decode($ligne->ct, true);
        $clair = openssl_decrypt(substr($brut, 0, -16), 'aes-256-gcm', $cle, OPENSSL_RAW_DATA, base64_decode($ligne->nonce, true), substr($brut, -16), "{$ligne->id}|mere|journal|1");
        $this->assertStringContainsString('M02-020', (string) $clair);
    }

    public function test_une_enveloppe_alteree_est_refusee_par_son_authentification_et_le_relais_ne_la_dechiffre_pas(): void
    {
        $cle = random_bytes(32);
        $env = $this->enveloppe($cle, $this->charge(), 2);
        $brut = base64_decode($env['ct'], true);
        $brut[10] = chr(ord($brut[10]) ^ 1);
        $clair = openssl_decrypt(substr($brut, 0, -16), 'aes-256-gcm', $cle, OPENSSL_RAW_DATA, base64_decode($env['nonce'], true), substr($brut, -16), "{$env['id']}|mere|journal|2");
        $this->assertFalse($clair, 'un octet changé : le déchiffrement échoue, rien d’altéré ne passe pour une identité');
    }
}
