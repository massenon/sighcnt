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
            'valides' => DB::table('relais_codes')->where('utilise', false)->where(fn ($q) => $q->whereNull('expire_le')->orWhere('expire_le', '>=', Format::maintenant()))->count(),
            'utilises' => DB::table('relais_codes')->where('utilise', true)->where(fn ($q) => $q->where('utilise_le', '>=', $depuis30j)->orWhereNull('utilise_le'))->count(),
            // E1424 : un code non utilisé dont l'échéance déclarée par la mère est passée est « expiré » (refusé à l'appairage).
            'expires' => DB::table('relais_codes')->where('utilise', false)->whereNotNull('expire_le')->where('expire_le', '<', Format::maintenant())->count(),
        ]);
    }
}
