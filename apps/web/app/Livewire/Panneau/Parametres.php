<?php

namespace App\Livewire\Panneau;

use App\Relais\Synchro\Reglages;
use Livewire\Attributes\Layout;
use Livewire\Component;

/**
 * Paramètres du relais. Le secret de la mère, le seuil de battement et la rétention de l'audit se posent dans le .env (jamais en base) : ils sont ici en LECTURE ; le secret n'est jamais affiché.
 * Lot RLS-SYNC : les réglages de l'écran « Synchronisation » (durée de conservation de l'historique, intervalle des relevés, seuils « en retard » et « silencieux ») sont, eux, enregistrés EN BASE,
 * bornés, modifiables ici par le superadmin et journalisés.
 */
#[Layout('layouts.panneau')]
class Parametres extends Component
{
    /** @var array<string, int|string> */
    public array $synchro = [];

    /** @var list<array{cle: string, motif: string, geste: string}> */
    public array $synchroRefus = [];

    public ?string $synchroMessage = null;

    public function mount(): void
    {
        $this->synchro = Reglages::toutes();
    }

    public function enregistrerSynchro(): void
    {
        $this->synchroMessage = null;
        $this->synchroRefus = Reglages::poser($this->synchro, (string) optional(auth()->user())->email);
        if ($this->synchroRefus === []) {
            $this->synchro = Reglages::toutes();
            $this->synchroMessage = 'Réglages de synchronisation enregistrés.';
        }
    }

    public function render()
    {
        return view('livewire.panneau.parametres', [
            'secretDefini' => (string) config('relais.secret_mere') !== '',
            'banc' => (bool) config('relais.banc'),
            'seuil' => round((int) config('relais.seuil_battement_ms') / 60000, 1),
            'retention' => (int) config('relais.retention_audit_jours'),
            'disque' => (int) config('relais.seuil_disque_pct'),
            'reglagesSynchro' => Reglages::DEFAUTS,
        ]);
    }
}
