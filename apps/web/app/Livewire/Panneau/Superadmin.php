<?php

namespace App\Livewire\Panneau;

use App\Models\User;
use App\Relais\Format;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Livewire\Attributes\Layout;
use Livewire\Component;

/** Comptes superadmin (création par commande uniquement), sessions ouvertes, changement de son propre mot de passe. */
#[Layout('layouts.panneau')]
class Superadmin extends Component
{
    public string $actuel = '';

    public string $nouveau = '';

    public string $confirmation = '';

    public ?string $message = null;

    public ?string $erreur = null;

    public function changerMotDePasse(): void
    {
        $this->message = $this->erreur = null;
        $u = auth()->user();
        if (! Hash::check($this->actuel, (string) $u->password)) {
            $this->erreur = 'Le mot de passe actuel est incorrect.';
        } elseif (mb_strlen($this->nouveau) < 8) {
            $this->erreur = 'Le nouveau mot de passe doit compter au moins 8 caractères.';
        } elseif ($this->nouveau !== $this->confirmation) {
            $this->erreur = 'La confirmation ne correspond pas.';
        }
        if ($this->erreur) {
            DB::table('relais_audit')->insert(['quand' => Format::maintenant(), 'acteur' => $u->email, 'action' => 'mot_de_passe_refuse', 'detail' => null]);

            return;
        }
        $u->forceFill(['password' => Hash::make($this->nouveau)])->save();
        // Le mot de passe n'est JAMAIS journalisé.
        DB::table('relais_audit')->insert(['quand' => Format::maintenant(), 'acteur' => $u->email, 'action' => 'mot_de_passe_change', 'detail' => null]);
        $this->actuel = $this->nouveau = $this->confirmation = '';
        $this->message = 'Mot de passe changé.';
    }

    /** Navigateur et système lus dans l'agent utilisateur, sans autre détail. */
    public static function appareil(?string $ua): string
    {
        $ua = (string) $ua;
        $nav = match (true) {
            str_contains($ua, 'Edg/') => 'Edge', str_contains($ua, 'Firefox') => 'Firefox', str_contains($ua, 'Chrome') => 'Chrome', str_contains($ua, 'Safari') => 'Safari', default => 'Navigateur',
        };
        $sys = match (true) {
            str_contains($ua, 'Windows') => 'Windows', str_contains($ua, 'Android') => 'Android', str_contains($ua, 'iPhone') || str_contains($ua, 'iPad') => 'iOS', str_contains($ua, 'Mac OS') => 'macOS', str_contains($ua, 'Linux') => 'Linux', default => 'système inconnu',
        };

        return $nav.' · '.$sys;
    }

    /** Adresse partiellement masquée : 41.xx.xx.12. */
    public static function adresse(?string $ip): string
    {
        $ip = (string) $ip;
        if (preg_match('/^(\d+)\.\d+\.\d+\.(\d+)$/', $ip, $m)) {
            return $m[1].'.xx.xx.'.$m[2];
        }

        return $ip === '' ? 'n/d' : substr($ip, 0, 9).'…';
    }

    public function render()
    {
        $comptes = User::orderBy('email')->get()->map(function ($u) {
            $u->derniere = DB::table('relais_audit')->where('acteur', $u->email)->where('action', 'connexion')->max('quand');

            return $u;
        });

        return view('livewire.panneau.superadmin', [
            'comptes' => $comptes,
            'sessions' => DB::table('sessions')->whereNotNull('user_id')->orderByDesc('last_activity')->get(),
        ]);
    }
}
