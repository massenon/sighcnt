<?php

namespace App\Livewire\Panneau;

use App\Relais\Format;
use App\Relais\Sms\Messages;
use App\Relais\Sms\Reglages;
use Illuminate\Support\Facades\DB;
use Livewire\Attributes\Layout;
use Livewire\Component;

/** Passerelle SMS du relais (ADR-0008) : état, envois planifiés (numéro masqué), journal, test, limites. Les identifiants du fournisseur ne s'affichent JAMAIS (« défini » ou « non défini »). */
#[Layout('layouts.panneau')]
class PasserelleSms extends Component
{
    public string $numeroTest = '';

    /** @var array<string, mixed>|null */
    public ?array $resultatTest = null;

    /** @var array<string, int|string> */
    public array $limites = [];

    /** @var list<string> */
    public array $limitesRefus = [];

    public ?string $message = null;

    public function mount(): void
    {
        $this->limites = Reglages::toutes();
    }

    public function tester(): void
    {
        $this->resultatTest = Messages::tester(trim($this->numeroTest));
        DB::table('relais_audit')->insert(['quand' => Messages::maintenant(), 'acteur' => (string) optional(auth()->user())->email, 'action' => 'sms_test', 'detail' => $this->resultatTest['ok'] ? 'accepté' : (string) $this->resultatTest['code']]);
        $this->numeroTest = '';
    }

    public function enregistrerLimites(): void
    {
        $this->limitesRefus = [];
        $acteur = (string) optional(auth()->user())->email;
        foreach (Reglages::DEFAUTS as $nom => $d) {
            $v = $this->limites[$nom] ?? null;
            if (! is_numeric($v) || (int) $v != $v) {
                $this->limitesRefus[] = $d['libelle'].' : un entier est attendu.';

                continue;
            }
            if ((int) $v === Reglages::toutes()[$nom]) {
                continue;
            }
            if (($refus = Reglages::poser($nom, (int) $v, $acteur)) !== null) {
                $this->limitesRefus[] = $refus;
            }
        }
        $this->limites = Reglages::toutes();
        $this->message = $this->limitesRefus === [] ? 'Limites de la passerelle SMS enregistrées.' : null;
    }

    public function render()
    {
        $planifies = DB::table('relais_sms')->where('etat', 'planifie')->orderBy('heure_envoi')->limit(50)->get(['type', 'heure_envoi', 'numero_masque', 'tentatives', 'code']);

        return view('livewire.panneau.passerelle-sms', ['etat' => Messages::etat(), 'planifies' => $planifies, 'journal' => array_slice(Messages::journal(30), 0, 30), 'defauts' => Reglages::DEFAUTS, 'format' => Format::class]);
    }
}
