<?php

namespace App\Livewire\Panneau;

use App\Relais\Format;
use App\Relais\Surveillance;
use Illuminate\Support\Facades\DB;
use Livewire\Attributes\Layout;
use Livewire\Component;

/**
 * Tableau de bord du relais : battement de cœur de la mère, indicateurs sans nom de patient, volumes d'enveloppes, alertes.
 * Ce panneau ne lit JAMAIS le contenu d'une enveloppe : elles sont chiffrées de bout en bout et le relais n'a pas la clé.
 */
#[Layout('layouts.panneau')]
class Tableau extends Component
{
    public function render()
    {
        Surveillance::evaluer();
        $age = Surveillance::ageBattement();
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
            'ouvertes' => DB::table('relais_alertes')->whereNull('fin')->count(),
            'alertes' => DB::table('relais_alertes')->orderByDesc('debut')->limit(10)->get(),
            'maintenant' => Format::maintenant(),
        ]);
    }
}
