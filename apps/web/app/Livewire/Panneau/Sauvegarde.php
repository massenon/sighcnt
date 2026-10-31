<?php

namespace App\Livewire\Panneau;

use App\Relais\Exporteur;
use App\Relais\Format;
use Illuminate\Support\Facades\DB;
use Livewire\Attributes\Layout;
use Livewire\Component;

/** Exports de la base du relais. Le contenu est déjà chiffré de bout en bout : un export ne contient rien de lisible. */
#[Layout('layouts.panneau')]
class Sauvegarde extends Component
{
    public ?string $message = null;

    public function exporter(): void
    {
        $e = Exporteur::exporter(false, (string) optional(auth()->user())->email);
        $this->message = 'Export créé : '.$e->fichier.' ('.Format::taille((int) $e->taille).').';
    }

    public function render()
    {
        $exports = DB::table('relais_exports')->orderByDesc('quand')->limit(20)->get();

        return view('livewire.panneau.sauvegarde', ['exports' => $exports, 'dernier' => $exports->first()]);
    }
}
