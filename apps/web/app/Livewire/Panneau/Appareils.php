<?php

namespace App\Livewire\Panneau;

use Illuminate\Support\Facades\DB;
use Livewire\Attributes\Layout;
use Livewire\Component;

/** Appareils connus du relais (mobiles) : état, volumes, révocation. Aucun contenu de dossier. */
#[Layout('layouts.panneau')]
class Appareils extends Component
{
    public ?string $message = null;

    /** Révoque l'accès d'un appareil AU RELAIS. La mère l'apprend à sa relève ; sa propre fiche reste à tenir à jour sur sa console. */
    public function revoquer(string $uuid): void
    {
        $n = DB::table('relais_appareils')->where('uuid', $uuid)->where('etat', 'actif')->update(['etat' => 'revoque']);
        if ($n === 0) {
            $this->message = 'Appareil inconnu ou déjà révoqué.';

            return;
        }
        DB::table('relais_audit')->insert([
            'quand' => (int) (microtime(true) * 1000), 'acteur' => (string) optional(auth()->user())->email, 'action' => 'appareil_revoque', 'detail' => $uuid,
        ]);
        $this->message = 'Appareil révoqué : il ne peut plus ni déposer ni relever. L\'effacement des données du téléphone a lieu à son prochain contact.';
    }

    public function render()
    {
        $lignes = DB::table('relais_appareils as a')
            ->leftJoin('relais_enveloppes as e', 'e.appareil', '=', 'a.uuid')
            ->selectRaw("a.uuid, a.etat,
                SUM(CASE WHEN e.dir = 'vers_mere' THEN 1 ELSE 0 END) as deposees,
                SUM(CASE WHEN e.dir = 'vers_mobile' THEN 1 ELSE 0 END) as boite,
                MAX(e.recu) as dernier")
            ->groupBy('a.uuid', 'a.etat')->orderBy('a.uuid')->get();

        return view('livewire.panneau.appareils', ['lignes' => $lignes]);
    }
}
