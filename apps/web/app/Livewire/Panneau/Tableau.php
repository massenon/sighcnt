<?php

namespace App\Livewire\Panneau;

use Illuminate\Support\Facades\DB;
use Livewire\Attributes\Layout;
use Livewire\Component;

/**
 * Tableau de bord du relais : battement de cœur de la mère, indicateurs sans nom de patient, volumes d'enveloppes.
 * Ce panneau ne lit JAMAIS le contenu d'une enveloppe : elles sont chiffrées de bout en bout et le relais n'a pas la clé.
 */
#[Layout('layouts.panneau')]
class Tableau extends Component
{
    public function render()
    {
        $bt = DB::table('relais_meta')->where('k', 'battement')->value('v');
        $age = $bt === null ? null : (int) (microtime(true) * 1000) - (int) $bt;
        $seuil = (int) config('relais.seuil_battement_ms');
        $ind = json_decode((string) DB::table('relais_meta')->where('k', 'indicateurs')->value('v'), true) ?: [];
        $parSens = DB::table('relais_enveloppes')->selectRaw('dir, COUNT(*) as n, SUM(taille) as taille')->groupBy('dir')->get()->keyBy('dir');

        return view('livewire.panneau.tableau', [
            'age' => $age,
            'alerte' => $age === null || $age > $seuil,
            'seuilMinutes' => round($seuil / 60000, 1),
            'indicateurs' => $ind,
            'parSens' => $parSens,
            'total' => DB::table('relais_enveloppes')->count(),
            'actifs' => DB::table('relais_appareils')->where('etat', 'actif')->count(),
            'revoques' => DB::table('relais_appareils')->where('etat', 'revoque')->count(),
            'dernier' => DB::table('relais_enveloppes')->max('recu'),
        ]);
    }
}
