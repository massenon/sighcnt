<?php

namespace App\Livewire\Panneau;

use Livewire\Attributes\Layout;
use Livewire\Component;

/** Paramètres du relais, en LECTURE : ils se posent dans le .env (jamais en base). Le secret de la mère n'est jamais affiché. */
#[Layout('layouts.panneau')]
class Parametres extends Component
{
    public function render()
    {
        return view('livewire.panneau.parametres', [
            'secretDefini' => (string) config('relais.secret_mere') !== '',
            'banc' => (bool) config('relais.banc'),
            'seuil' => round((int) config('relais.seuil_battement_ms') / 60000, 1),
            'retention' => (int) config('relais.retention_audit_jours'),
            'disque' => (int) config('relais.seuil_disque_pct'),
        ]);
    }
}
