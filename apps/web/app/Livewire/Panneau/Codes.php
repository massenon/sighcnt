<?php

namespace App\Livewire\Panneau;

use Illuminate\Support\Facades\DB;
use Livewire\Attributes\Layout;
use Livewire\Component;

/** Codes d'appairage déclarés par la mère. Seul le HACHAGE existe ici : le code en clair n'est jamais conservé. */
#[Layout('layouts.panneau')]
class Codes extends Component
{
    public function render()
    {
        return view('livewire.panneau.codes', [
            'codes' => DB::table('relais_codes')->orderBy('utilise')->orderBy('hash')->get(),
        ]);
    }
}
