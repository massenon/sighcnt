<?php

namespace App\Livewire\Panneau;

use Livewire\Attributes\Layout;
use Livewire\Component;

/** Consultation des copies chiffrées : la page n'envoie rien au serveur de ce qu'elle déchiffre, la clé reste dans le navigateur. */
#[Layout('layouts.panneau')]
class Consultation extends Component
{
    public function render()
    {
        return view('livewire.panneau.consultation');
    }
}
