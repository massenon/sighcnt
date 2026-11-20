<?php

namespace Tests\Feature\Synchro;

use App\Livewire\Panneau\Alertes;
use App\Livewire\Panneau\Parametres;
use App\Livewire\Panneau\Synchronisation;
use App\Models\User;
use App\Relais\Exporteur;
use App\Relais\Opacite;
use App\Relais\Surveillance;
use App\Relais\Synchro\Etat;
use App\Relais\Synchro\Historique;
use App\Relais\Synchro\Reglages;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Livewire\Livewire;
use Tests\TestCase;

/** Lot RLS-SYNC : l'écran « Synchronisation », son historique à part, ses réglages bornés, ses alertes et son accès réservé au superadmin. */
class SynchronisationTest extends TestCase
{
    use RefreshDatabase;

    private const MIN = 60000;

    private function maintenant(): int
    {
        return (int) (microtime(true) * 1000);
    }

    private function superadmin(): User
    {
        return User::factory()->create(['email' => 'dg@clinique.test']);
    }

    /** La mère publie : battement et indicateurs frais, avec les fileuls donnés. */
    private function mere(array $fileuls, int $battementIl = 0, array $plus = []): void
    {
        $t = $this->maintenant();
        DB::table('relais_meta')->updateOrInsert(['k' => 'battement'], ['v' => (string) ($t - $battementIl)]);
        DB::table('relais_meta')->updateOrInsert(['k' => 'indicateurs'], ['v' => json_encode(['seq_max' => 120] + $plus + ['fileuls' => $fileuls])]);
        DB::table('relais_meta')->updateOrInsert(['k' => 'indicateurs_le'], ['v' => (string) ($t - $battementIl)]);
    }

    private function fileul(string $poste, ?int $contactIl, ?int $retard = 0, int $conflits = 0, int $demandes = 0): array
    {
        return ['poste' => $poste, 'dernierContact' => $contactIl === null ? null : $this->maintenant() - $contactIl, 'retardJournal' => $retard, 'conflitsOuverts' => $conflits, 'demandesImportEnAttente' => $demandes];
    }

    private function mobile(string $uuid, ?int $depotIl, ?int $releveIl = null, int $boite = 0, int $releveN = 0, string $etat = 'actif'): void
    {
        $t = $this->maintenant();
        DB::table('relais_appareils')->insert(['uuid' => $uuid, 'jeton_hash' => hash('sha256', 'x'.$uuid), 'etat' => $etat, 'profil' => 'soignant', 'fonction' => 'infirmier',
            'dernier_releve' => $releveIl === null ? null : $t - $releveIl, 'releve_n' => $releveN]);
        if ($depotIl !== null) {
            DB::table('relais_enveloppes')->insert(['id' => 'd-'.$uuid, 'appareil' => $uuid, 'dir' => 'vers_mere', 'n' => 1, 'nonce' => 'n', 'ct' => 'c', 'taille' => 1, 'recu' => $t - $depotIl]);
        }
        for ($i = 1; $i <= $boite; $i++) {
            DB::table('relais_enveloppes')->insert(['id' => 'b-'.$uuid.'-'.$i, 'appareil' => $uuid, 'dir' => 'vers_mobile', 'n' => $i, 'nonce' => 'n', 'ct' => 'c', 'taille' => 1, 'recu' => $t]);
        }
    }

    // --- accès : superadmin seul ------------------------------------------------------------------

    public function test_l_ecran_est_ferme_aux_visiteurs_et_ouvert_au_superadmin(): void
    {
        $this->get(route('panneau.synchronisation'))->assertRedirect('/panneau/connexion');
        $this->actingAs($this->superadmin())->get(route('panneau.synchronisation'))->assertOk()->assertSee('Synchronisation');
    }

    public function test_un_compte_non_superadmin_n_a_ni_la_route_ni_l_entree_de_menu(): void
    {
        $simple = User::factory()->create(['email' => 'simple@clinique.test', 'superadmin' => false]);
        $this->actingAs($simple)->get(route('panneau.synchronisation'))->assertForbidden();
        $this->assertDatabaseHas('relais_audit', ['action' => 'acces_refuse_non_superadmin', 'acteur' => 'simple@clinique.test']);
        // Aucune entrée de menu : le gabarit ne propose rien à un compte qui n'est pas superadmin.
        $html = $this->actingAs($simple)->view('layouts.panneau', ['slot' => 'x']);
        $html->assertDontSee('Synchronisation')->assertDontSee('Indicateurs reçus');
        // Et le composant, monté hors route, refuse de s'afficher.
        Livewire::actingAs($simple)->test(Synchronisation::class)->assertForbidden();
        // Le superadmin, lui, voit l'entrée.
        $this->actingAs($this->superadmin())->view('layouts.panneau', ['slot' => 'x'])->assertSee('Synchronisation');
    }

    public function test_un_compte_dont_le_statut_est_indetermine_est_refuse(): void
    {
        $flou = User::factory()->create(['email' => 'flou@clinique.test']);
        $flou->forceFill(['superadmin' => null]);
        $this->actingAs($flou)->get(route('panneau.synchronisation'))->assertForbidden();
        $this->actingAs($flou)->get(route('panneau.parametres'))->assertForbidden(); // une page sans contrôle propre : seule la barrière de la route la protège
        $this->assertSame(true, $this->superadmin()->superadmin, 'tout compte créé sans précision est superadmin (seul chemin : relais:superadmin)');
    }

    public function test_un_non_superadmin_n_ouvre_aucune_autre_page_du_panneau(): void
    {
        $simple = User::factory()->create(['email' => 'simple@clinique.test', 'superadmin' => false]);
        foreach (['tableau', 'appareils', 'parametres', 'opacite', 'sauvegarde'] as $r) {
            $this->actingAs($simple)->get(route('panneau.'.$r))->assertForbidden();
        }
    }

    // --- lecture : jamais zéro pour une valeur non publiée --------------------------------------------

    public function test_rien_n_est_publie_donc_tout_se_lit_non_publie(): void
    {
        $r = Livewire::actingAs($this->superadmin())->test(Synchronisation::class)
            ->assertSee('Non publié : la mère n’a encore rien publié sur ses fileuls.')
            ->assertSee('Dernier battement : non publié')->assertSee('Numéro de séquence : non publié')->assertSee('Version du protocole : non publié');
        $r->assertDontSee('Dernier battement : jamais');
        $this->assertNull(Etat::fileuls());
        $this->assertSame(Etat::NON_PUBLIE, Etat::mere()['etat']);
    }

    public function test_une_valeur_non_calculable_n_est_jamais_affichee_comme_zero(): void
    {
        $this->mere([['poste' => 'Poste neuf', 'dernierContact' => null, 'retardJournal' => null, 'conflitsOuverts' => 2, 'demandesImportEnAttente' => 0]]);
        $html = Livewire::actingAs($this->superadmin())->test(Synchronisation::class)->html();
        preg_match('#<tr[^>]*>\s*<td>Poste neuf</td>(.*?)</tr>#s', $html, $m);
        $ligne = preg_replace('/\s+/', ' ', strip_tags($m[1] ?? ''));
        $this->assertStringContainsString('Jamais vu', $ligne);
        $this->assertStringContainsString('jamais vu', $ligne);
        $this->assertStringContainsString('non publié', $ligne, 'le retard de journal est null : « non publié »');
        $this->assertSame(1, preg_match('/non publié 2 0$/', trim($ligne)), $ligne);
        $this->assertSame(Etat::JAMAIS_VU, Etat::fileuls()[0]['etat']);
    }

    public function test_les_fileuls_sont_juges_sur_les_seuils_regles(): void
    {
        $this->mere([
            $this->fileul('F1', 1 * self::MIN), $this->fileul('F2', 90 * self::MIN), $this->fileul('F3', 300 * self::MIN),
            $this->fileul('F4', 1 * self::MIN, 900), $this->fileul('F5', null, null),
        ]);
        $etats = array_column(Etat::fileuls(), 'etat', 'poste');
        $this->assertSame(['F1' => 'a_jour', 'F2' => 'en_retard', 'F3' => 'silencieux', 'F4' => 'en_retard', 'F5' => 'jamais_vu'], $etats);
        $this->assertSame([], Reglages::poser(['fileul_en_retard_min' => 100, 'fileul_silencieux_min' => 200], 'test'));
        $this->assertSame('a_jour', array_column(Etat::fileuls(), 'etat', 'poste')['F2'], 'le seuil réglé en base fait foi');
        $this->assertSame('silencieux', array_column(Etat::fileuls(), 'etat', 'poste')['F3']);
    }

    public function test_la_mere_est_a_jour_en_retard_ou_silencieuse_sur_un_seuil_regle(): void
    {
        foreach ([[30000, Etat::A_JOUR], [3 * self::MIN, Etat::EN_RETARD], [10 * self::MIN, Etat::SILENCIEUX]] as [$age, $etat]) {
            $this->mere([], $age);
            $this->assertSame($etat, Etat::mere()['etat'], "silence de $age ms");
        }
        $this->assertSame([], Reglages::poser(['mere_en_retard_min' => 20, 'mere_silencieuse_min' => 30], 't'));
        $this->mere([], 10 * self::MIN);
        $this->assertSame(Etat::A_JOUR, Etat::mere()['etat']);
        $this->mere([], 0, ['protocole' => 3]);
        Livewire::actingAs($this->superadmin())->test(Synchronisation::class)->assertSee('Numéro de séquence : 120')->assertSee('Version du protocole : 3');
    }

    public function test_quand_la_mere_ne_publie_plus_l_etat_des_fileuls_est_inconnu_et_aucune_alerte_de_fileul_ne_se_leve(): void
    {
        $this->mere([$this->fileul('F1', 500 * self::MIN)], 20 * self::MIN);
        $this->assertSame('inconnu', Etat::fileuls()[0]['etat']);
        Surveillance::evaluer();
        $this->assertDatabaseMissing('relais_alertes', ['type' => 'fileul_silencieux']);
        Livewire::actingAs($this->superadmin())->test(Synchronisation::class)->assertSee('La mère ne publie plus : l’état de ses fileuls n’est pas établi');
    }

    public function test_les_mobiles_montrent_depot_releve_et_enveloppes_en_attente(): void
    {
        $this->mobile('mobile-aaaa-1111', 5 * self::MIN, 2 * self::MIN, 3, 1);
        $this->mobile('mobile-bbbb-2222', null);
        $this->mobile('mobile-cccc-3333', 10 * self::MIN, null, 0, 0, 'revoque');
        $m = array_column(Etat::mobiles(), null, 'uuid');
        $this->assertSame(2, $m['mobile-aaaa-1111']['attente'], 'trois enveloppes posées, la relève est au rang 1');
        $this->assertSame(Etat::A_JOUR, $m['mobile-aaaa-1111']['etat']);
        $this->assertSame(Etat::JAMAIS_VU, $m['mobile-bbbb-2222']['etat']);
        $this->assertNull($m['mobile-bbbb-2222']['dernier_depot']);
        $this->assertSame(Etat::REVOQUE, $m['mobile-cccc-3333']['etat']);
        Livewire::actingAs($this->superadmin())->test(Synchronisation::class)->assertSee('Mobile mobile-a')->assertSee('Soignant · infirmier')->assertSee('Jamais vu')->assertSee('Révoqué');
    }

    // --- le relais note la relève d'un mobile ------------------------------------------------------------

    public function test_la_releve_d_un_mobile_est_notee_avec_son_rang_sans_jamais_reculer(): void
    {
        config(['relais.secret_mere' => 's3cret']);
        DB::table('relais_appareils')->insert(['uuid' => 'mob-1', 'jeton_hash' => hash('sha256', 'sec'), 'etat' => 'actif', 'profil' => 'soignant', 'fonction' => 'infirmier']);
        for ($i = 1; $i <= 5; $i++) {
            $this->postJson('/depot', ['enveloppe' => ['id' => "v$i", 'appareil' => 'mob-1', 'dir' => 'vers_mobile', 'n' => $i, 'nonce' => 'n', 'ct' => 'c']], ['x-mere' => 's3cret'])->assertOk();
        }
        $this->assertSame(5, Etat::mobiles()[0]['attente']);
        $this->assertNull(Etat::mobiles()[0]['dernier_releve']);
        // Le relais note ce qu'il REMET : une fournée de deux enveloppes (rangs 4 et 5 avec limite 1 : le rang 4 seul).
        $this->getJson('/releve?dir=vers_mobile&appareil=mob-1&depuis_n=3&limite=1', ['Authorization' => 'Bearer mob-1.sec'])->assertOk()->assertJsonPath('env.0.n', 4);
        $this->assertSame(1, Etat::mobiles()[0]['attente'], 'rangs 1 à 4 relevés, le 5 attend');
        $this->assertNotNull(Etat::mobiles()[0]['dernier_releve']);
        $this->getJson('/releve?dir=vers_mobile&appareil=mob-1&depuis_n=0&limite=1', ['Authorization' => 'Bearer mob-1.sec'])->assertOk()->assertJsonPath('env.0.n', 1);
        $this->assertSame(1, Etat::mobiles()[0]['attente'], 'le rang relevé ne recule jamais');
        $this->getJson('/releve?dir=vers_mobile&appareil=mob-1&depuis_n=4', ['Authorization' => 'Bearer mob-1.sec'])->assertOk();
        $this->assertSame(0, Etat::mobiles()[0]['attente']);
        // Un mobile qui lit la boîte d'un autre est refusé : rien n'est noté.
        DB::table('relais_appareils')->insert(['uuid' => 'mob-2', 'jeton_hash' => hash('sha256', 'sec2'), 'etat' => 'actif']);
        $this->getJson('/releve?dir=vers_mobile&appareil=mob-1&depuis_n=0', ['Authorization' => 'Bearer mob-2.sec2'])->assertStatus(403);
        $this->assertNull(DB::table('relais_appareils')->where('uuid', 'mob-2')->value('dernier_releve'));
    }

    // --- historique : conservé, échantillonné, purgé à la durée réglée -------------------------------------------

    public function test_l_historique_est_echantillonne_a_l_intervalle_regle_et_a_part(): void
    {
        $t = $this->maintenant();
        $f = [['poste' => 'F1', 'dernierContact' => $t, 'retardJournal' => 4, 'conflitsOuverts' => 0, 'demandesImportEnAttente' => 1]];
        $this->assertSame(1, Historique::echantillonnerFileuls($f, $t));
        $this->assertSame(0, Historique::echantillonnerFileuls($f, $t + 9 * self::MIN), 'intervalle réglé : 10 min');
        $this->assertSame(1, Historique::echantillonnerFileuls($f, $t + 10 * self::MIN));
        $this->assertSame([], Reglages::poser(['echantillon_minutes' => 1], 't'));
        $this->assertSame(1, Historique::echantillonnerFileuls($f, $t + 11 * self::MIN + 5000));
        $this->assertSame(3, DB::table('relais_synchro_historique')->where('ref', 'F1')->count());
        $this->assertSame(0, DB::table('relais_indicateurs_historique')->count(), 'un historique à part, jamais le champ libre des indicateurs');
        $ligne = (array) DB::table('relais_synchro_historique')->orderBy('id')->first();
        $this->assertEqualsCanonicalizing(['id', 'quand', 'nature', 'ref', 'dernier_contact', 'retard_journal', 'conflits', 'demandes', 'attente'], array_keys($ligne));
    }

    public function test_l_historique_garde_la_duree_reglee_et_la_purge_ne_retire_rien_en_dessous(): void
    {
        $now = $this->maintenant();
        $jour = 86400000;
        foreach ([1, 29, 31, 89, 91, 200] as $j) {
            DB::table('relais_synchro_historique')->insert(['quand' => $now - $j * $jour, 'nature' => 'fileul', 'ref' => 'J'.$j, 'dernier_contact' => null, 'retard_journal' => 1]);
        }
        $this->assertSame(2, Historique::purger($now), 'durée par défaut : 90 jours (3 mois), seuls 91 et 200 jours partent');
        $this->assertEqualsCanonicalizing(['J1', 'J29', 'J31', 'J89'], DB::table('relais_synchro_historique')->pluck('ref')->all());
        $this->assertSame([], Reglages::poser(['conservation_jours' => 30], 'dg'));
        $this->assertSame(2, Historique::purger($now), '30 jours : 31 et 89 partent, 29 reste');
        $this->assertEqualsCanonicalizing(['J1', 'J29'], DB::table('relais_synchro_historique')->pluck('ref')->all());
        $this->assertSame([], Reglages::poser(['conservation_jours' => 365], 'dg'));
        $this->assertSame(0, Historique::purger($now));
    }

    public function test_une_valeur_hors_borne_en_base_ne_fait_jamais_purger_en_dessous_du_plancher(): void
    {
        $now = $this->maintenant();
        DB::table('relais_meta')->where('k', Reglages::cle('conservation_jours'))->update(['v' => '1']);
        DB::table('relais_synchro_historique')->insert(['quand' => $now - 40 * 86400000, 'nature' => 'fileul', 'ref' => 'F1']);
        DB::table('relais_synchro_historique')->insert(['quand' => $now - 10 * 86400000, 'nature' => 'fileul', 'ref' => 'F2']);
        $this->assertSame(30, Reglages::valeur('conservation_jours'), 'ramenée au plancher');
        $this->assertSame(1, Historique::purger($now));
        $this->assertSame(['F2'], DB::table('relais_synchro_historique')->pluck('ref')->all());
    }

    public function test_la_commande_surveiller_releve_les_mobiles_et_purge(): void
    {
        $this->mobile('mob-1', 5 * self::MIN);
        DB::table('relais_synchro_historique')->insert(['quand' => $this->maintenant() - 120 * 86400000, 'nature' => 'fileul', 'ref' => 'ANCIEN']);
        $this->artisan('relais:surveiller')->assertSuccessful();
        $this->assertDatabaseMissing('relais_synchro_historique', ['ref' => 'ANCIEN']);
        $this->assertDatabaseHas('relais_synchro_historique', ['nature' => 'mere', 'ref' => 'mere']);
        $this->assertDatabaseHas('relais_synchro_historique', ['nature' => 'mobile', 'ref' => 'mob-1']);
    }

    public function test_l_ecran_montre_l_historique_sur_la_periode(): void
    {
        $now = $this->maintenant();
        DB::table('relais_synchro_historique')->insert([
            ['quand' => $now - 3600000, 'nature' => 'fileul', 'ref' => 'Poste caisse', 'dernier_contact' => $now - 3700000, 'retard_journal' => 12, 'conflits' => 0, 'demandes' => 0, 'attente' => null],
            ['quand' => $now - 10 * 86400000, 'nature' => 'fileul', 'ref' => 'Poste ancien', 'dernier_contact' => $now - 10 * 86400000, 'retard_journal' => 7, 'conflits' => 0, 'demandes' => 0, 'attente' => null],
        ]);
        Livewire::actingAs($this->superadmin())->test(Synchronisation::class)->assertSee('Poste caisse')->assertDontSee('Poste ancien')
            ->set('periode', '30j')->assertSee('Poste ancien')
            ->set('nature', 'mobile')->assertDontSee('Poste ancien')->assertSee('Aucun relevé sur la période choisie.');
    }

    // --- réglages : en base, bornés, journalisés ------------------------------------------------------------------

    public function test_les_reglages_sont_semes_en_base_avec_leurs_defauts(): void
    {
        foreach (Reglages::DEFAUTS as $nom => $d) {
            $this->assertSame((string) $d['defaut'], DB::table('relais_meta')->where('k', Reglages::cle($nom))->value('v'), $nom);
        }
        $this->assertSame(90, Reglages::valeur('conservation_jours'));
    }

    public function test_un_reglage_hors_borne_est_refuse_en_le_nommant_et_rien_n_est_enregistre(): void
    {
        foreach ([29, 366, 0, -5] as $v) {
            $refus = Reglages::poser(['conservation_jours' => $v, 'echantillon_minutes' => 5], 'dg');
            $this->assertCount(1, $refus);
            $this->assertSame('conservation_jours', $refus[0]['cle']);
            $this->assertStringContainsString('30 à 365', $refus[0]['motif']);
            $this->assertNotSame('', $refus[0]['geste']);
        }
        $this->assertSame(90, Reglages::valeur('conservation_jours'));
        $this->assertSame(10, Reglages::valeur('echantillon_minutes'), 'tout ou rien : le réglage valide du même lot n\'est pas enregistré');
        $this->assertSame('inconnu', Reglages::poser(['inconnu' => 3], 'dg')[0]['cle']);
        $this->assertCount(1, Reglages::poser(['conservation_jours' => 'beaucoup'], 'dg'));
        $this->assertCount(1, Reglages::poser(['conservation_jours' => 12.5], 'dg'));
    }

    public function test_un_seuil_de_silence_doit_depasser_celui_du_retard(): void
    {
        $refus = Reglages::poser(['fileul_en_retard_min' => 300], 'dg');
        $this->assertSame('fileul_silencieux_min', $refus[0]['cle']);
        $this->assertSame(30, Reglages::valeur('fileul_en_retard_min'));
    }

    public function test_un_reglage_modifie_est_journalise_avec_l_ancienne_et_la_nouvelle_valeur(): void
    {
        $this->assertSame([], Reglages::poser(['conservation_jours' => 120], 'dg@clinique.test'));
        $this->assertDatabaseHas('relais_audit', ['acteur' => 'dg@clinique.test', 'action' => 'reglage_synchro', 'detail' => 'conservation_jours : 90 → 120']);
        $n = DB::table('relais_audit')->where('action', 'reglage_synchro')->count();
        Reglages::poser(['conservation_jours' => 120], 'dg@clinique.test');
        $this->assertSame($n, DB::table('relais_audit')->where('action', 'reglage_synchro')->count(), 'une valeur inchangée n\'est pas journalisée');
    }

    public function test_le_superadmin_regle_la_conservation_dans_les_parametres(): void
    {
        $c = Livewire::actingAs($this->superadmin())->test(Parametres::class)->assertSee('Synchronisation : conservation et seuils')->assertSee('de 30 à 365 jours, défaut 90')
            ->set('synchro.conservation_jours', '200')->call('enregistrerSynchro')->assertSee('Réglages de synchronisation enregistrés.');
        $this->assertSame(200, Reglages::valeur('conservation_jours'));
        $c->set('synchro.conservation_jours', '10')->call('enregistrerSynchro')->assertSee('hors des bornes (30 à 365');
        $this->assertSame(200, Reglages::valeur('conservation_jours'));
    }

    // --- alertes : le relais signale -----------------------------------------------------------------------------

    public function test_un_fileul_silencieux_leve_puis_resout_une_alerte_sans_nom(): void
    {
        $this->mere([$this->fileul('Poste secret', 300 * self::MIN)]);
        Surveillance::evaluer();
        $this->assertDatabaseHas('relais_alertes', ['type' => 'fileul_silencieux', 'fin' => null]);
        $detail = DB::table('relais_alertes')->where('type', 'fileul_silencieux')->value('detail');
        $this->assertStringContainsString('1 fileul(s) silencieux', $detail);
        $this->assertStringNotContainsString('secret', (string) $detail, 'un compte, jamais le nom du poste');
        $this->assertDatabaseHas('relais_audit', ['acteur' => 'système', 'action' => 'alerte_fileul_silencieux']);
        Surveillance::evaluer();
        $this->assertSame(1, DB::table('relais_alertes')->where('type', 'fileul_silencieux')->count(), 'idempotent');
        $this->mere([$this->fileul('Poste secret', 1 * self::MIN)]);
        Surveillance::evaluer();
        $this->assertDatabaseMissing('relais_alertes', ['type' => 'fileul_silencieux', 'fin' => null]);
        $this->assertDatabaseHas('relais_audit', ['action' => 'alerte_resolue', 'detail' => 'fileul_silencieux']);
    }

    public function test_un_fileul_jamais_vu_ne_leve_pas_d_alerte_de_silence(): void
    {
        $this->mere([$this->fileul('F1', null, null)]);
        Surveillance::evaluer();
        $this->assertDatabaseMissing('relais_alertes', ['type' => 'fileul_silencieux']);
    }

    public function test_un_mobile_silencieux_et_une_boite_qui_grossit_levent_leurs_alertes(): void
    {
        $this->mobile('mob-silencieux', 4000 * self::MIN, 4000 * self::MIN);
        $this->mobile('mob-boite', 1 * self::MIN, 1 * self::MIN, 12);
        $this->mobile('mob-neuf', null);
        Reglages::poser(['boite_enveloppes_max' => 10], 't');
        Surveillance::evaluer();
        $this->assertDatabaseHas('relais_alertes', ['type' => 'mobile_silencieux', 'fin' => null]);
        $this->assertStringContainsString('1 mobile(s) silencieux', DB::table('relais_alertes')->where('type', 'mobile_silencieux')->value('detail'));
        $this->assertDatabaseHas('relais_alertes', ['type' => 'boite_grossit', 'fin' => null]);
        $this->assertStringContainsString('1 boîte(s)', DB::table('relais_alertes')->where('type', 'boite_grossit')->value('detail'));
        // Un mobile révoqué ne signale plus rien.
        DB::table('relais_appareils')->whereIn('uuid', ['mob-silencieux', 'mob-boite'])->update(['etat' => 'revoque']);
        Surveillance::evaluer();
        $this->assertDatabaseMissing('relais_alertes', ['type' => 'mobile_silencieux', 'fin' => null]);
        $this->assertDatabaseMissing('relais_alertes', ['type' => 'boite_grossit', 'fin' => null]);
    }

    public function test_les_nouvelles_alertes_figurent_a_l_ecran_des_alertes_avec_leur_seuil_regle(): void
    {
        $html = Livewire::actingAs($this->superadmin())->test(Alertes::class)->html();
        foreach (['Fileul silencieux', 'Mobile silencieux', 'Boîte aux lettres qui grossit', '240 min', '2880 min', '200 enveloppes'] as $t) {
            $this->assertStringContainsString($t, $html);
        }
    }

    // --- opacité, export, téléphone ------------------------------------------------------------------------------

    public function test_l_opacite_etend_sa_mesure_a_l_historique_de_synchronisation(): void
    {
        DB::table('relais_synchro_historique')->insert(['quand' => 1, 'nature' => 'fileul', 'ref' => 'F1']);
        $this->assertSame(['lignes' => 1, 'colonnes_hors_liste' => [], 'refs_hors_liste' => 0], Opacite::historiqueSynchro());
        DB::table('relais_synchro_historique')->insert(['quand' => 2, 'nature' => 'fileul', 'ref' => 'CNT/12/26']);
        $this->assertSame(1, Opacite::historiqueSynchro()['refs_hors_liste']);
        Schema::table('relais_synchro_historique', fn ($t) => $t->string('motif')->nullable());
        $this->assertSame(['motif'], Opacite::historiqueSynchro()['colonnes_hors_liste']);
        Livewire::actingAs($this->superadmin())->test(\App\Livewire\Panneau\Opacite::class)->assertSee('Historique de synchronisation')->assertSee('ALERTE');
    }

    public function test_l_opacite_est_verte_sur_un_historique_propre(): void
    {
        DB::table('relais_synchro_historique')->insert(['quand' => 1, 'nature' => 'fileul', 'ref' => 'Poste caisse']);
        Livewire::actingAs($this->superadmin())->test(\App\Livewire\Panneau\Opacite::class)->assertSee('Historique de synchronisation')
            ->assertSee('0 colonne(s) hors liste, 0 référence(s) hors forme');
    }

    public function test_l_export_du_relais_embarque_l_historique_de_synchronisation(): void
    {
        $this->assertContains('relais_synchro_historique', Exporteur::TABLES);
        DB::table('relais_synchro_historique')->insert(['quand' => 5, 'nature' => 'fileul', 'ref' => 'EXPORT-F1', 'retard_journal' => 3]);
        $e = Exporteur::exporter(false, 'test');
        $chemin = Exporteur::dossier().'/'.$e->fichier;
        $contenu = implode('', gzfile($chemin));
        @unlink($chemin);
        $this->assertStringContainsString('"t":"relais_synchro_historique"', $contenu);
        $this->assertStringContainsString('EXPORT-F1', $contenu);
    }

    public function test_un_telephone_ne_lit_rien_de_la_synchronisation(): void
    {
        config(['relais.secret_mere' => 's3cret']);
        $this->mere([$this->fileul('Poste caisse', 1 * self::MIN)]);
        DB::table('relais_appareils')->insert(['uuid' => 'tel-1', 'jeton_hash' => hash('sha256', 'sec'), 'etat' => 'actif', 'profil' => 'soignant', 'fonction' => 'infirmier']);
        $h = ['Authorization' => 'Bearer tel-1.sec'];
        // L'état du relais, les indicateurs et la publication sont ceux de la mère seule.
        $this->getJson('/admin/etat', $h)->assertStatus(403)->assertJsonPath('code', 'mere_requise');
        $this->postJson('/mere/indicateurs', ['indicateurs' => ['fileuls' => []]], $h)->assertStatus(403);
        $this->getJson('/mere/appareils', $h)->assertStatus(403);
        // Aucune boîte de lecture d'un téléphone ne porte l'historique ni les indicateurs.
        foreach (['indicateurs', 'synchro', 'copie', 'vers_mere', 'journal', 'meta'] as $dir) {
            $this->getJson("/releve?dir=$dir&appareil=tel-1&depuis_n=0", $h)->assertStatus(403)->assertJsonPath('code', 'lecture_interdite');
        }
        $r = $this->getJson('/releve?dir=vers_mobile&appareil=tel-1&depuis_n=0', $h)->assertOk();
        $this->assertStringNotContainsString('Poste caisse', $r->getContent());
        // Et le panneau, sans session, ne répond pas.
        $this->get(route('panneau.synchronisation'), $h)->assertRedirect('/panneau/connexion');
    }
}
