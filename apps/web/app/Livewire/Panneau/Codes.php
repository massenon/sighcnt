<?php

namespace App\Livewire\Panneau;

use App\Relais\Format;
use Illuminate\Support\Facades\DB;
use Livewire\Attributes\Layout;
use Livewire\Component;

/** Codes d'appairage déclarés par la mère. Seul le HACHAGE existe ici : le code en clair n'est jamais conservé. */
#[Layout('layouts.panneau')]
class Codes extends Component
{
    public function render()
    {
        $depuis30j = Format::maintenant() - 30 * 86400 * 1000;

        return view('livewire.panneau.codes', [
            'codes' => DB::table('relais_codes')->orderBy('utilise')->orderByDesc('cree')->orderBy('hash')->get(),
            'valides' => DB::table('relais_codes')->where('utilise', false)->count(),
            'utilises' => DB::table('relais_codes')->where('utilise', true)->where(fn ($q) => $q->where('utilise_le', '>=', $depuis30j)->orWhereNull('utilise_le'))->count(),
            // Le relais n'applique aucune expiration aux codes (le contrat n'en porte pas) : aucun code n'y est jamais « expiré ».
            'expires' => 0,
        ]);
    }
}
