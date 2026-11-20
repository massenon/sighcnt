<?php

namespace App\Relais;

/**
 * Traduit les jetons de design du projet (docs/design/design-tokens.json, seule source des couleurs, engendré par la maquette) en variables CSS.
 * Le relais tourne sur un cPanel sans npm : le fichier public/css/jetons.css est ENGENDRÉ ici (php artisan relais:jetons-css) puis téléversé avec le reste,
 * jamais édité à la main. Un test compare le fichier au résultat de cette fonction : une dérive des jetons fait rougir la suite.
 */
class JetonsCss
{
    public static function chemin(): string
    {
        return base_path('../../docs/design/design-tokens.json');
    }

    public static function sortie(): string
    {
        return public_path('css/jetons.css');
    }

    /** @param array<string, mixed> $jetons le contenu décodé de design-tokens.json */
    public static function css(array $jetons): string
    {
        $l = ['/* ENGENDRÉ par php artisan relais:jetons-css depuis docs/design/design-tokens.json. Ne pas éditer : régénérer. */', ':root {'];
        foreach ($jetons['couleurs'] as $famille => $nuances) {
            foreach ($nuances as $n => $hex) {
                $l[] = "  --{$famille}-{$n}: {$hex};";
            }
        }
        foreach ($jetons['ombres'] as $nom => $valeur) {
            $l[] = "  --ombre-{$nom}: {$valeur};";
        }
        foreach ($jetons['police'] as $nom => $pile) {
            $l[] = "  --police-{$nom}: ".implode(', ', array_map(fn ($p) => str_contains($p, ' ') ? '"'.$p.'"' : $p, $pile)).';';
        }
        $l[] = '}';

        return implode("\n", $l)."\n";
    }

    /** @return list<string> les couleurs hexadécimales (minuscules) que les jetons autorisent */
    public static function couleursAutorisees(array $jetons): array
    {
        $r = [];
        foreach ($jetons['couleurs'] as $nuances) {
            foreach ($nuances as $hex) {
                $r[] = strtolower($hex);
            }
        }

        return $r;
    }
}
