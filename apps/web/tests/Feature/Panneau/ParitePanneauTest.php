<?php

namespace Tests\Feature\Panneau;

use App\Models\User;
use App\Relais\Exporteur;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/**
 * MESURE DE PARITÉ N1 (contenu) des douze écrans du module RLS contre leur fiche extraite de la maquette
 * (docs/architecture/ecrans/rls-*.json). Même logique que apps/poste/test/parite/extracteur.dart :
 *  - sont attendus : titre, description, kpis, onglets, tableaux (en-têtes), champs, cartes (chiffres neutralisés) et commandes
 *    (chiffres de fin retirés) ;
 *  - un libellé est présent s'il égale ou est contenu dans UN texte visible (jamais dans la concaténation de toute la page) ;
 *  - normalisation : espaces réduits, trim, minuscules.
 * Une seule règle en plus de celle du poste : les tirets cadratins et demi-cadratins sont ramenés à une virgule des deux côtés
 * (règle de rédaction du dépôt, écart E1420). La mesure ne porte que sur <main> : le menu du panneau nomme les douze écrans sur
 * chaque page et rendrait la comparaison complaisante.
 */
class ParitePanneauTest extends TestCase
{
    use RefreshDatabase;

    private const ECRANS = [
        'rls-tableau' => 'panneau.tableau', 'rls-appareils' => 'panneau.appareils', 'rls-boites' => 'panneau.boites',
        'rls-codes' => 'panneau.codes', 'rls-indicateurs' => 'panneau.indicateurs', 'rls-alertes' => 'panneau.alertes',
        'rls-journal' => 'panneau.journal', 'rls-superadmin' => 'panneau.superadmin', 'rls-parametres' => 'panneau.parametres',
        'rls-hebergement' => 'panneau.hebergement', 'rls-sauvegarde' => 'panneau.sauvegarde', 'rls-opacite' => 'panneau.opacite',
    ];

    private const BLOCS = ['div', 'p', 'table', 'thead', 'tbody', 'tr', 'td', 'th', 'ul', 'ol', 'li', 'section', 'main', 'header', 'nav', 'form', 'h1', 'h2', 'h3', 'h4', 'article', 'pre', 'label'];

    private function dossierFiches(): string
    {
        return base_path('../../docs/architecture/ecrans');
    }

    public static function normaliser(string $s): string
    {
        $s = mb_strtolower(trim(preg_replace('/\s+/u', ' ', $s)));

        return preg_replace('/\s*[—–]\s*/u', ', ', $s);
    }

    /** Textes visibles de <main> : un texte par élément qui ne contient aucun bloc, plus le texte direct des blocs, plus les attributs lisibles. */
    public static function textesVisibles(string $html): array
    {
        $dom = new \DOMDocument();
        @$dom->loadHTML('<?xml encoding="UTF-8">'.$html, LIBXML_NOERROR | LIBXML_NOWARNING);
        $main = $dom->getElementsByTagName('main')->item(0);
        $out = [];
        $ajouter = function (?string $t) use (&$out) {
            $t = self::normaliser((string) $t);
            if ($t !== '') {
                $out[$t] = true;
            }
        };
        $aDesBlocs = function (\DOMElement $e) {
            foreach ($e->getElementsByTagName('*') as $d) {
                if (in_array($d->tagName, self::BLOCS, true)) {
                    return true;
                }
            }

            return false;
        };
        $marche = function (\DOMNode $n) use (&$marche, &$ajouter, $aDesBlocs) {
            if (! $n instanceof \DOMElement || in_array($n->tagName, ['script', 'style'], true)) {
                return;
            }
            foreach (['title', 'placeholder', 'aria-label'] as $a) {
                if ($n->hasAttribute($a)) {
                    $ajouter($n->getAttribute($a));
                }
            }
            if ($n->tagName === 'input' && in_array($n->getAttribute('type'), ['submit', 'button'], true)) {
                $ajouter($n->getAttribute('value'));
            }
            if (! $aDesBlocs($n)) {
                $ajouter($n->textContent);

                return;
            }
            $direct = '';
            foreach ($n->childNodes as $c) {
                if ($c instanceof \DOMText) {
                    $direct .= ' '.$c->textContent;
                }
            }
            $ajouter($direct);
            foreach ($n->childNodes as $c) {
                $marche($c);
            }
        };
        if ($main) {
            $marche($main);
        }

        return array_keys($out);
    }

    /** @return array{attendus: int, manquants: list<string>} */
    public static function comparer(array $fiche, array $textes): array
    {
        $attendus = [];
        $ajouter = function ($v) use (&$ajouter, &$attendus) {
            if (is_string($v) && trim($v) !== '') {
                $attendus[] = self::normaliser($v);
            }
            if (is_array($v)) {
                array_walk($v, fn ($x) => $ajouter($x));
            }
        };
        foreach (['titre', 'description', 'kpis', 'onglets', 'tableaux', 'champs'] as $k) {
            $ajouter($fiche[$k] ?? null);
        }
        $cartes = [];
        foreach ($fiche['cartes'] ?? [] as $c) {
            if (is_string($c) && trim($c) !== '') {
                $cartes[] = preg_replace('/\d+/', '#', self::normaliser($c));
            }
        }
        foreach ($fiche['commandes'] ?? [] as $c) {
            if (is_string($c) && trim(preg_replace('/\d+$/', '', $c)) !== '') {
                $attendus[] = self::normaliser(trim(preg_replace('/\d+$/', '', $c)));
            }
        }
        $uniques = array_values(array_unique($attendus));
        $cartes = array_values(array_unique($cartes));
        $neutres = array_map(fn ($t) => preg_replace('/\d+/', '#', $t), $textes);
        $trouve = fn (string $a, array $dans) => (bool) array_filter($dans, fn ($t) => $t === $a || str_contains($t, $a));
        $manquants = [];
        foreach ($uniques as $a) {
            if (! $trouve($a, $textes)) {
                $manquants[] = $a;
            }
        }
        foreach ($cartes as $a) {
            if (! $trouve($a, $neutres)) {
                $manquants[] = $a;
            }
        }

        return ['attendus' => count($uniques) + count($cartes), 'manquants' => $manquants];
    }

    /** Jeu minimal qui fait DESSINER chaque tableau (les en-têtes d'un tableau vide ne se dessinent pas). */
    private function peupler(User $u): void
    {
        $maintenant = (int) (microtime(true) * 1000);
        DB::table('relais_meta')->insert([
            ['k' => 'battement', 'v' => (string) $maintenant],
            ['k' => 'cron_dernier', 'v' => (string) $maintenant],
            ['k' => 'indicateurs', 'v' => json_encode(['seq' => 12480, 'appareils_actifs' => 8, 'conflits_ouverts' => 3, 'appareils_bloques' => 1])],
        ]);
        DB::table('relais_appareils')->insert([
            ['uuid' => 'mobile-parite-1', 'jeton_hash' => 'h1', 'etat' => 'actif'],
            ['uuid' => 'mobile-parite-2', 'jeton_hash' => 'h2', 'etat' => 'revoque'],
        ]);
        foreach ([['mobile-parite-1', 'vers_mere', 1], ['mobile-parite-1', 'vers_mobile', 1], ['mobile-parite-1', 'journal', 1]] as $i => [$app, $dir, $n]) {
            DB::table('relais_enveloppes')->insert(['id' => 'e'.$i, 'appareil' => $app, 'dir' => $dir, 'n' => $n, 'nonce' => 'nn', 'ct' => base64_encode(random_bytes(2000)), 'taille' => 2668, 'recu' => $maintenant - 60000]);
        }
        DB::table('relais_codes')->insert([['hash' => str_repeat('a', 64), 'utilise' => false, 'cree' => $maintenant, 'utilise_le' => null],['hash' => str_repeat('b', 64), 'utilise' => true, 'cree' => $maintenant - 86400000, 'utilise_le' => $maintenant - 3600000]]);
        DB::table('relais_alertes')->insert(['type' => 'appareil_bloque', 'detail' => 'parité', 'debut' => $maintenant - 7200000, 'fin' => $maintenant - 3600000]);
        DB::table('relais_indicateurs_historique')->insert(['quand' => $maintenant - 3600000, 'charge' => json_encode(['seq' => 12391, 'appareils_actifs' => 8, 'conflits_ouverts' => 3, 'appareils_bloques' => 1])]);
        DB::table('relais_audit')->insert(['quand' => $maintenant, 'acteur' => $u->email, 'action' => 'connexion', 'detail' => null]);
        DB::table('sessions')->insert(['id' => 's1', 'user_id' => $u->id, 'ip_address' => '41.12.34.12', 'user_agent' => 'Mozilla/5.0 (Windows NT 10.0) Chrome/120', 'payload' => '', 'last_activity' => time()]);
        Exporteur::exporter(false, $u->email);
    }

    public function test_parite_n1_des_douze_ecrans_du_panneau_contre_les_fiches_de_la_maquette(): void
    {
        if (! is_dir($this->dossierFiches())) {
            $this->markTestSkipped('docs/architecture/ecrans absent (déploiement sans le dépôt entier).');
        }
        $u = User::factory()->create(['email' => 'superadmin@clinique.test']);
        $this->peupler($u);
        $rapport = [];
        $echecs = [];
        foreach (self::ECRANS as $id => $route) {
            $fiche = json_decode(file_get_contents($this->dossierFiches()."/$id.json"), true);
            $html = $this->actingAs($u)->get(route($route))->assertOk()->getContent();
            $m = self::comparer($fiche, self::textesVisibles($html));
            $rapport[] = ['id' => $id, 'route' => $route, 'attendus' => $m['attendus'], 'presents' => $m['attendus'] - count($m['manquants']),
                'taux' => $m['attendus'] ? round(($m['attendus'] - count($m['manquants'])) / $m['attendus'], 3) : 1, 'manquants' => $m['manquants']];
            if ($m['manquants']) {
                $echecs[] = "$id : ".implode(' | ', $m['manquants']);
            }
        }
        foreach (glob(Exporteur::dossier().'/relais-*.jsonl.gz') as $f) {
            @unlink($f);
        }
        if (is_writable(base_path('../../docs/architecture'))) {
            file_put_contents(base_path('../../docs/architecture/rapport-parite-rls.json'), json_encode([
                '_doc' => 'ENGENDRÉ par apps/web/tests/Feature/Panneau/ParitePanneauTest.php, ne pas éditer. Parité N1 (contenu) des écrans du panneau superadmin du relais contre la maquette.',
                'ecrans' => $rapport,
            ], JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES)."\n");
        }
        $this->assertSame([], $echecs, "Libellés de la maquette absents du panneau :\n".implode("\n", $echecs));
        $this->assertCount(12, $rapport);
    }

    public function test_la_mesure_n_est_pas_complaisante(): void
    {
        // Un libellé attendu qui n'est pas affiché est BIEN signalé, et la concaténation de la page ne compte pas.
        $fiche = ['titre' => 'Titre', 'description' => 'Alpha beta', 'kpis' => ['Gamma'], 'tableaux' => [['Delta', 'Epsilon']], 'cartes' => ['Carte 12'], 'commandes' => ['Valider3']];
        $textes = self::textesVisibles('<html><body><main><h1>Titre</h1><p>Alpha</p><p>beta</p><div><span>Gamma</span></div><table><tr><th>Delta</th></tr></table><h2>Carte 7</h2><button>Valider</button></main></body></html>');
        $m = self::comparer($fiche, $textes);
        $this->assertEqualsCanonicalizing(['alpha beta', 'epsilon'], $m['manquants']);
        $this->assertSame(7, $m['attendus']);
    }

    public function test_aucun_tiret_cadratin_dans_les_vues_et_classes_du_panneau(): void
    {
        $fichiers = array_merge(
            glob(resource_path('views/livewire/panneau/*.php')) ?: [], glob(resource_path('views/layouts/*.php')) ?: [],
            glob(app_path('Livewire/Panneau/*.php')) ?: [], glob(app_path('Relais/*.php')) ?: [],
        );
        $fautifs = array_filter($fichiers, fn ($f) => preg_match('/[—–]/u', file_get_contents($f)));
        $this->assertSame([], array_values($fautifs));
    }
}
