<?php

use App\Http\Controllers\SatisfactionController;
use Illuminate\Support\Facades\Route;

/*
| Lot SAT (ADR-0009) : la satisfaction en ligne. Sans session, sans cookie, sans CSRF (le groupe n'a aucun intergiciel).
| PUBLIQUES : le formulaire d'un lien de collecte et le dépôt d'une enveloppe scellée dans le navigateur. RÉSERVÉES À LA MÈRE : la publication de la clé publique et des liens, le relevé.
*/
Route::get('/s/{jeton}', [SatisfactionController::class, 'formulaire']);
Route::post('/s/{jeton}', [SatisfactionController::class, 'deposer']);
Route::post('/satisfaction/publier', [SatisfactionController::class, 'publier']);
Route::get('/satisfaction/releve', [SatisfactionController::class, 'releve']);
