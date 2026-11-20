<?php

namespace App\Http\Controllers;

use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;

class PanneauAuthController extends Controller
{
    public function formulaire()
    {
        return view('panneau.connexion');
    }

    public function connecter(Request $r): RedirectResponse
    {
        $donnees = $r->validate(['courriel' => ['required', 'email'], 'mot_de_passe' => ['required', 'string']]);
        if (! Auth::attempt(['email' => mb_strtolower($donnees['courriel']), 'password' => $donnees['mot_de_passe']], false)) {
            DB::table('relais_audit')->insert(['quand' => (int) (microtime(true) * 1000), 'acteur' => $donnees['courriel'], 'action' => 'connexion_refusee', 'detail' => $r->ip()]);

            return back()->withErrors(['courriel' => 'Identifiants refusés.'])->onlyInput('courriel');
        }
        $r->session()->regenerate();
        DB::table('relais_audit')->insert(['quand' => (int) (microtime(true) * 1000), 'acteur' => $donnees['courriel'], 'action' => 'connexion', 'detail' => $r->ip()]);

        return redirect()->route('panneau.tableau');
    }

    public function deconnecter(Request $r): RedirectResponse
    {
        $acteur = (string) optional($r->user())->email;
        Auth::logout();
        $r->session()->invalidate();
        $r->session()->regenerateToken();
        DB::table('relais_audit')->insert(['quand' => (int) (microtime(true) * 1000), 'acteur' => $acteur, 'action' => 'deconnexion', 'detail' => null]);

        return redirect()->route('panneau.connexion');
    }
}
