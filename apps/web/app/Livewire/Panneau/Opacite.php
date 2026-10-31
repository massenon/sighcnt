<?php

namespace App\Livewire\Panneau;

use App\Relais\Opacite as MesureOpacite;
use Livewire\Attributes\Layout;
use Livewire\Component;

/** Preuve d'opacité : ce que le relais détient et ne détient pas, avec une mesure faite sur les enveloppes réellement stockées. */
#[Layout('layouts.panneau')]
class Opacite extends Component
{
    public function render()
    {
        return view('livewire.panneau.opacite', [
            'mesure' => MesureOpacite::mesurer(),
            'cle' => MesureOpacite::cleDeCliniqueAuRelais(),
        ]);
    }
}
