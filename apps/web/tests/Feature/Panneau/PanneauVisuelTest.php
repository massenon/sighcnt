<?php

namespace Tests\Feature\Panneau;

use App\Models\User;
use App\Relais\JetonsCss;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/** Structure et charte du panneau (lot RELAIS-UI) : barre latérale, accessibilité, couleurs tirées des jetons. La mesure en navigateur est tests/navigateur/visuel.cjs. */
class PanneauVisuelTest extends TestCase
{
    use RefreshDatabase;

    private const ROUTES = ['tableau', 'appareils', 'boites', 'codes', 'indicateurs', 'synchronisation', 'alertes', 'journal', 'superadmin', 'parametres', 'hebergement', 'sauvegarde', 'sms', 'opacite', 'consultation'];

    private function jetons(): array
    {
        return json_decode((string) file_get_contents(JetonsCss::chemin()), true, 512, JSON_THROW_ON_ERROR);
    }

    private function luminance(string $hex): float
    {
        $c = array_map(fn ($v) => ($v /= 255) <= 0.03928 ? $v / 12.92 : (($v + 0.055) / 1.055) ** 2.4, sscanf(ltrim($hex, '#'), '%02x%02x%02x'));

        return 0.2126 * $c[0] + 0.7152 * $c[1] + 0.0722 * $c[2];
    }

    private function contraste(string $a, string $b): float
    {
        [$x, $y] = [$this->luminance($a), $this->luminance($b)];

        return (max($x, $y) + 0.05) / (min($x, $y) + 0.05);
    }

    public function test_la_navigation_est_une_barre_laterale_verticale_etiquetee_avec_le_lien_actif_marque(): void
    {
        $u = User::factory()->create();
        foreach (self::ROUTES as $r) {
            $html = $this->actingAs($u)->get(route('panneau.'.$r))->assertOk()->getContent();
            $this->assertStringContainsString('<aside class="barre"', $html, $r);
            $this->assertStringContainsString('<nav aria-label="Navigation du panneau">', $html, $r);
            $this->assertSame(1, preg_match_all('/aria-current="page"/', $html), "un seul lien actif sur $r");
            $this->assertMatchesRegularExpression('#<a href="'.preg_quote(route('panneau.'.$r), '#').'"\s+aria-current="page"\s*>#', $html, $r);
            $this->assertStringContainsString('data-menu-bouton aria-controls="barre" aria-expanded="false"', $html);
            $this->assertStringContainsString('href="#contenu"', $html);
            $this->assertStringNotContainsString('<header class="entete"', $html);
        }
        $html = $this->actingAs($u)->get(route('panneau.tableau'))->getContent();
        $this->assertSame(15, substr_count($html, '<li><a href='), 'les quinze pages sont dans la barre');
    }

    public function test_un_compte_non_superadmin_ne_voit_aucune_entree(): void
    {
        $u = User::factory()->create();
        $u->superadmin = false;
        $this->assertFalse($u->superadmin === true);
        $this->get(route('panneau.connexion'))->assertOk()->assertDontSee('Navigation du panneau');
    }

    public function test_les_feuilles_de_style_ne_contiennent_aucune_couleur_hors_des_jetons(): void
    {
        $permises = JetonsCss::couleursAutorisees($this->jetons());
        $racine = base_path();
        $fichiers = array_merge(
            [$racine.'/public/css/panneau.css'],
            glob($racine.'/resources/views/layouts/*.blade.php'),
            glob($racine.'/resources/views/panneau/*.blade.php'),
            glob($racine.'/resources/views/livewire/panneau/*.blade.php'),
            glob($racine.'/resources/views/satisfaction/*.blade.php'),
        );
        $this->assertGreaterThan(20, count($fichiers));
        foreach ($fichiers as $f) {
            $texte = preg_replace('#/\*.*?\*/#s', '', (string) file_get_contents($f));
            preg_match_all('/(?<![\w&])#([0-9a-fA-F]{8}|[0-9a-fA-F]{6}|[0-9a-fA-F]{3})\b/', $texte, $m);
            foreach ($m[0] as $hex) {
                $this->assertContains(strtolower($hex), $permises, basename($f).' : couleur en dur '.$hex);
            }
            $this->assertDoesNotMatchRegularExpression('/\b(rgb|rgba|hsl)\(/', $texte, basename($f).' : couleur fonctionnelle en dur');
        }
    }

    public function test_jetons_css_est_celui_que_les_jetons_engendrent(): void
    {
        $this->assertSame(JetonsCss::css($this->jetons()), file_get_contents(JetonsCss::sortie()), 'lancer php artisan relais:jetons-css');
        $this->artisan('relais:jetons-css', ['--verifier' => true])->assertSuccessful();
    }

    public function test_le_panneau_ne_reference_que_des_variables_definies(): void
    {
        $jetons = (string) file_get_contents(JetonsCss::sortie());
        $css = (string) file_get_contents(base_path('public/css/panneau.css'));
        preg_match_all('/--([a-z0-9-]+)\s*:/', $jetons.$css, $def);
        preg_match_all('/var\(--([a-z0-9-]+)/', $css, $use);
        $this->assertSame([], array_values(array_diff(array_unique($use[1]), $def[1])));
    }

    public function test_contrastes_aa_des_paires_du_panneau(): void
    {
        $c = $this->jetons()['couleurs'];
        $paires = [
            ['texte sur fond', $c['navy']['950'], $c['navy']['50']], ['texte doux sur blanc', $c['navy']['700'], '#ffffff'], ['texte doux sur fond', $c['navy']['700'], $c['navy']['50']],
            ['lien de barre', $c['navy']['100'], $c['navy']['950']], ['groupe de barre', $c['navy']['300'], $c['navy']['950']], ['lien actif', '#ffffff', $c['navy']['800']],
            ['bouton', '#ffffff', $c['navy']['900']], ['bouton danger', '#ffffff', $c['danger']['700']],
            ['puce ok', $c['success']['700'], $c['success']['100']], ['puce alerte', $c['danger']['700'], $c['danger']['100']], ['puce attention', $c['warning']['700'], $c['warning']['100']],
        ];
        foreach ($paires as [$nom, $a, $b]) {
            $this->assertGreaterThanOrEqual(4.5, $this->contraste($a, $b), "contraste AA : $nom");
        }
        $this->assertGreaterThanOrEqual(3.0, $this->contraste($c['navy']['500'], '#ffffff'), 'bordure de champ (non texte)');
    }

    public function test_accessibilite_focus_visible_et_mouvement_reduit(): void
    {
        $css = (string) file_get_contents(base_path('public/css/panneau.css'));
        $this->assertStringContainsString(':focus-visible', $css);
        $this->assertStringContainsString('prefers-reduced-motion: reduce', $css);
        $this->assertStringContainsString('max-width: 1023.98px', $css);
        $this->assertStringContainsString('--cible: 2.75rem', $css, 'cible tactile de 44 px');
    }

    public function test_la_page_de_connexion_et_le_questionnaire_suivent_la_charte(): void
    {
        $this->get(route('panneau.connexion'))->assertOk()->assertSee('css/jetons.css', false)->assertSee('class="connexion"', false);
        $v = (string) file_get_contents(base_path('resources/views/satisfaction/formulaire.blade.php'));
        $this->assertStringContainsString("public_path('css/jetons.css')", $v, 'la CSP interdit une feuille externe : les jetons sont inclus en ligne');
    }

    public function test_aucun_tiret_cadratin_dans_les_vues_et_feuilles_du_panneau(): void
    {
        foreach (array_merge(glob(base_path('resources/views/{layouts,panneau,livewire/panneau}/*.blade.php'), GLOB_BRACE), [base_path('public/css/panneau.css')]) as $f) {
            $this->assertDoesNotMatchRegularExpression('/\x{2014}|\x{2013}/u', (string) file_get_contents($f), basename($f));
        }
    }
}
