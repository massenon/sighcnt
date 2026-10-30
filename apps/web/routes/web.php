<?php

use App\Http\Controllers\PanneauAuthController;
use App\Livewire\Panneau\Appareils;
use App\Livewire\Panneau\Codes;
use App\Livewire\Panneau\Journal;
use App\Livewire\Panneau\Tableau;
use Illuminate\Support\Facades\Route;

// L'accueil renvoie au panneau : le relais n'a aucune page publique.
Route::redirect('/', '/panneau');

Route::prefix('panneau')->group(function () {
    Route::get('/connexion', [PanneauAuthController::class, 'formulaire'])->name('panneau.connexion')->middleware('guest');
    Route::post('/connexion', [PanneauAuthController::class, 'connecter'])->name('panneau.connexion.envoi')->middleware(['guest', 'throttle:6,1']);

    Route::middleware('auth')->group(function () {
        Route::get('/', Tableau::class)->name('panneau.tableau');
        Route::get('/appareils', Appareils::class)->name('panneau.appareils');
        Route::get('/codes', Codes::class)->name('panneau.codes');
        Route::get('/journal', Journal::class)->name('panneau.journal');
        Route::post('/deconnexion', [PanneauAuthController::class, 'deconnecter'])->name('panneau.deconnexion');
    });
});

