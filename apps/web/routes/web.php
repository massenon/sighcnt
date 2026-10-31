<?php

use App\Http\Controllers\PanneauAuthController;
use App\Livewire\Panneau\Alertes;
use App\Livewire\Panneau\Appareils;
use App\Livewire\Panneau\Boites;
use App\Livewire\Panneau\Codes;
use App\Livewire\Panneau\Hebergement;
use App\Livewire\Panneau\Indicateurs;
use App\Livewire\Panneau\Journal;
use App\Livewire\Panneau\Opacite;
use App\Livewire\Panneau\Parametres;
use App\Livewire\Panneau\Sauvegarde;
use App\Livewire\Panneau\Superadmin;
use App\Livewire\Panneau\Tableau;
use Illuminate\Support\Facades\Route;

// L'accueil renvoie au panneau : le relais n'a aucune page publique.
Route::redirect('/', '/panneau');

Route::prefix('panneau')->group(function () {
    Route::get('/connexion', [PanneauAuthController::class, 'formulaire'])->name('panneau.connexion')->middleware('guest');
    Route::post('/connexion', [PanneauAuthController::class, 'connecter'])->name('panneau.connexion.envoi')->middleware(['guest', 'throttle:6,1']);

    // Les douze écrans du module RLS (maquette), chacun une page Livewire. Tout est derrière l'authentification.
    Route::middleware('auth')->group(function () {
        Route::get('/', Tableau::class)->name('panneau.tableau');
        Route::get('/appareils', Appareils::class)->name('panneau.appareils');
        Route::get('/boites', Boites::class)->name('panneau.boites');
        Route::get('/codes', Codes::class)->name('panneau.codes');
        Route::get('/indicateurs', Indicateurs::class)->name('panneau.indicateurs');
        Route::get('/alertes', Alertes::class)->name('panneau.alertes');
        Route::get('/journal', Journal::class)->name('panneau.journal');
        Route::get('/superadmin', Superadmin::class)->name('panneau.superadmin');
        Route::get('/parametres', Parametres::class)->name('panneau.parametres');
        Route::get('/hebergement', Hebergement::class)->name('panneau.hebergement');
        Route::get('/sauvegarde', Sauvegarde::class)->name('panneau.sauvegarde');
        Route::get('/opacite', Opacite::class)->name('panneau.opacite');
        Route::post('/deconnexion', [PanneauAuthController::class, 'deconnecter'])->name('panneau.deconnexion');
    });
});
