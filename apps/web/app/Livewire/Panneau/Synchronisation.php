<?php

namespace App\Livewire\Panneau;

use App\Relais\Format;
use App\Relais\Synchro\Etat;
use App\Relais\Synchro\Reglages;
use Illuminate\Support\Facades\DB;
use Livewire\Attributes\Layout;
use Livewire\Component;

/**
 * SYNCHRONISATION (lot RLS-SYNC) : la mère, ses fileuls et les mobiles, en LECTURE SEULE, réservé au superadmin. Des compteurs et des horodatages, jamais un identifiant de patient, un nom,
 * un libellé de pièce ni un motif. Les fileuls ne parlent pas au relais : c'est la mère qui publie leur état. Les mobiles, eux, passent par le relais, qui voit leurs dépôts et leurs relèves.
 */
#[Layout('layouts.panneau')]
class Synchronisation extends Component
{
    public string $periode = '24h';

    public string $nature = 'toutes';

    public const PERIODES = ['24h' => ['24 heures', 86400000], '7j' => ['7 jours', 7 * 86400000], '30j' => ['30 jours', 30 * 86400000], 'tout' => ['Toute la durée conservée', 0]];

    public const NATURES = ['toutes' => 'Toutes', 'mere' => 'Mère', 'fileul' => 'Fileuls', 'mobile' => 'Mobiles'];

    public function mount(): void
    {
        // Défense en profondeur : la route est déjà derrière le contrôle superadmin ; un composant monté autrement n'affiche rien.
        abort_unless(auth()->user()?->superadmin === true, 403, 'Le panneau du relais est réservé au superadmin.');
    }

    public function render()
    {
        $maintenant = Format::maintenant();
        $periode = array_key_exists($this->periode, self::PERIODES) ? $this->periode : '24h';
        $nature = array_key_exists($this->nature, self::NATURES) ? $this->nature : 'toutes';
        $debut = self::PERIODES[$periode][1] === 0 ? 0 : $maintenant - self::PERIODES[$periode][1];
        $base = DB::table('relais_synchro_historique')->where('quand', '>=', $debut)->when($nature !== 'toutes', fn ($q) => $q->where('nature', $nature));
        $resume = (clone $base)->selectRaw('nature, ref, COUNT(*) as releves, MAX(quand - dernier_contact) as silence_max, MAX(retard_journal) as retard_max, MAX(attente) as attente_max, MAX(conflits) as conflits_max, MAX(demandes) as demandes_max')
            ->groupBy('nature', 'ref')->orderBy('nature')->orderBy('ref')->get();
        $releves = (clone $base)->orderByDesc('quand')->orderByDesc('id')->limit(60)->get();

        return view('livewire.panneau.synchronisation', [
            'mere' => Etat::mere($maintenant),
            'fileuls' => Etat::fileuls($maintenant),
            'mereMuette' => Etat::mereSilencieuse($maintenant),
            'mobiles' => Etat::mobiles($maintenant),
            'reglages' => Reglages::toutes(),
            'resume' => $resume,
            'releves' => $releves,
            'periodes' => self::PERIODES,
            'natures' => self::NATURES,
            'total' => (int) DB::table('relais_synchro_historique')->count(),
        ]);
    }
}
