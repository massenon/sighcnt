<?php

namespace App\Livewire\Panneau;

use Illuminate\Support\Facades\DB;
use Livewire\Attributes\Layout;
use Livewire\Component;

/** Boîtes aux lettres : pour chaque appareil, volumes par sens, rangs, tailles. Le relais ne voit que (appareil, sens, rang, taille). */
#[Layout('layouts.panneau')]
class Boites extends Component
{
    public function render()
    {
        $boites = DB::table('relais_enveloppes')->whereIn('dir', ['vers_mobile', 'vers_mere'])
            ->selectRaw("appareil,
                SUM(CASE WHEN dir = 'vers_mobile' THEN 1 ELSE 0 END) as vers,
                SUM(CASE WHEN dir = 'vers_mere' THEN 1 ELSE 0 END) as depuis,
                MAX(CASE WHEN dir = 'vers_mere' THEN n END) as rang,
                SUM(taille) as taille, MIN(recu) as ancienne")
            ->groupBy('appareil')->orderBy('appareil')->get();

        return view('livewire.panneau.boites', [
            'boites' => $boites,
            'vers' => (int) $boites->sum('vers'),
            'depuis' => (int) $boites->sum('depuis'),
        ]);
    }
}
