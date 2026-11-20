<?php

namespace App\Livewire\Panneau;

use Illuminate\Support\Facades\DB;
use Livewire\Attributes\Layout;
use Livewire\Component;

/** Journal d'audit de l'administration du relais (RG-12) : connexions, révocations, création du compte. */
#[Layout('layouts.panneau')]
class Journal extends Component
{
    public function render()
    {
        return view('livewire.panneau.journal', ['lignes' => DB::table('relais_audit')->orderByDesc('id')->limit(200)->get()]);
    }
}
