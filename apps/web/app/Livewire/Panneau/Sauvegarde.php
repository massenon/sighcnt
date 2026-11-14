<?php

namespace App\Livewire\Panneau;

use App\Relais\Exporteur;
use App\Relais\Format;
use App\Relais\Sauvegarde\Entrepot;
use App\Relais\Sauvegarde\Reglages;
use Illuminate\Support\Facades\DB;
use Livewire\Attributes\Layout;
use Livewire\Component;

/** Exports de la base du relais. Le contenu est déjà chiffré de bout en bout : un export ne contient rien de lisible. */
#[Layout('layouts.panneau')]
class Sauvegarde extends Component
{
    public ?string $message = null;

    /** @var array<string, int|string> */
    public array $limites = [];

    /** @var list<string> */
    public array $limitesRefus = [];

    public function mount(): void
    {
        $this->limites = Reglages::toutes();
    }

    /** Lot 5 : les limites de la copie hors site (quota, limite par copie, taille de bloc, rotation) : bornées, journalisées. Un refus nomme le réglage et la borne ; rien n'est enregistré d'un réglage refusé. */
    public function enregistrerLimites(): void
    {
        $this->limitesRefus = [];
        $acteur = (string) optional(auth()->user())->email;
        foreach (Reglages::DEFAUTS as $nom => $d) {
            $v = $this->limites[$nom] ?? null;
            if (! is_numeric($v) || (int) $v != $v) {
                $this->limitesRefus[] = $d['libelle'].' : un entier est attendu.';

                continue;
            }
            if ((int) $v === Reglages::toutes()[$nom]) {
                continue;
            }
            if (($refus = Reglages::poser($nom, (int) $v, $acteur)) !== null) {
                $this->limitesRefus[] = $refus;
            }
        }
        $this->limites = Reglages::toutes();
        $this->message = $this->limitesRefus === [] ? 'Limites de la copie hors site enregistrées.' : null;
    }

    public function exporter(): void
    {
        $e = Exporteur::exporter(false, (string) optional(auth()->user())->email);
        $this->message = 'Export créé : '.$e->fichier.' ('.Format::taille((int) $e->taille).').';
    }

    public function render()
    {
        $exports = DB::table('relais_exports')->orderByDesc('quand')->limit(20)->get();

        return view('livewire.panneau.sauvegarde', ['exports' => $exports, 'dernier' => $exports->first(), 'horsSite' => Entrepot::resume(), 'defauts' => Reglages::DEFAUTS]);
    }
}
