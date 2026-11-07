<?php

namespace App\Livewire\Panneau;

use App\Relais\Format;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Mail;
use Livewire\Attributes\Layout;
use Livewire\Component;

/** Règles d'alerte du relais et courriel de test. Une alerte porte un type, une heure, un détail technique : jamais un contenu métier. */
#[Layout('layouts.panneau')]
class Alertes extends Component
{
    public ?string $message = null;

    public function tester(): void
    {
        $dest = (string) optional(auth()->user())->email;
        try {
            Mail::raw('Courriel de test du relais SIGH-CNT, envoyé à '.Format::date(Format::maintenant()).'. Il ne contient aucune donnée de patient.', function ($m) use ($dest) {
                $m->to($dest)->subject('Relais SIGH-CNT : courriel de test');
            });
            $this->message = 'Courriel de test envoyé à '.$dest.'.';
            $detail = 'envoyé';
        } catch (\Throwable $e) {
            $this->message = 'Le courriel de test n\'a pas pu partir : vérifier la configuration MAIL_* du relais.';
            $detail = 'échec : '.class_basename($e);
        }
        DB::table('relais_audit')->insert(['quand' => Format::maintenant(), 'acteur' => $dest, 'action' => 'courriel_test', 'detail' => $detail]);
    }

    public static function seuil(string $type): string
    {
        return match ($type) {
            'battement' => round((int) config('relais.seuil_battement_ms') / 60000, 1).' min',
            'appareil_bloque' => 'immédiat',
            'disque' => (int) config('relais.seuil_disque_pct').' %',
            'cron' => round((int) config('relais.seuil_cron_ms') / 60000, 1).' min',
            default => 'n/d',
        };
    }

    public function render()
    {
        return view('livewire.panneau.alertes', ['regles' => config('relais.alertes')]);
    }
}
