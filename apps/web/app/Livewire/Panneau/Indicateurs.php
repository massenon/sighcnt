<?php

namespace App\Livewire\Panneau;

use App\Relais\Format;
use Illuminate\Support\Facades\DB;
use Livewire\Attributes\Layout;
use Livewire\Component;

/** Indicateurs publiés par la mère à chaque battement : agrégats en clair, aucun nom, aucun motif. */
#[Layout('layouts.panneau')]
class Indicateurs extends Component
{
    public function render()
    {
        $dernier = json_decode((string) DB::table('relais_meta')->where('k', 'indicateurs')->value('v'), true) ?: [];
        $historique = DB::table('relais_indicateurs_historique')->where('quand', '>=', Format::maintenant() - 24 * 3600 * 1000)
            ->orderByDesc('quand')->limit(48)->get()->map(function ($l) {
                $c = json_decode($l->charge, true) ?: [];

                return (object) [
                    'quand' => $l->quand,
                    'seq' => $c['seq'] ?? null,
                    'actifs' => $c['appareils_actifs'] ?? null,
                    'conflits' => $c['conflits_ouverts'] ?? ($c['conflits'] ?? null),
                    'bloques' => $c['appareils_bloques'] ?? null,
                ];
            });

        return view('livewire.panneau.indicateurs', ['dernier' => $dernier, 'historique' => $historique]);
    }
}
