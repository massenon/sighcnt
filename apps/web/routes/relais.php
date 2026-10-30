<?php

use App\Http\Controllers\RelaisController;
use Illuminate\Support\Facades\Route;

/*
| Contrat du relais (packages/sync/banc/relais.js). Sans session, sans CSRF : l'authentification est le jeton
| d'appareil (Bearer uuid.secret) ou le secret de la mère (en-tête x-mere). Chemins identiques à ceux du banc.
*/
Route::post('/mere/code', [RelaisController::class, 'code']);
Route::post('/appairage', [RelaisController::class, 'appairage']);
Route::post('/depot', [RelaisController::class, 'depot']);
Route::get('/releve', [RelaisController::class, 'releve']);
Route::get('/mere/appareils', [RelaisController::class, 'appareilsMere']);
Route::get('/compteur', [RelaisController::class, 'compteur']);
Route::post('/mere/revoquer', [RelaisController::class, 'revoquer']);
Route::post('/mere/battement', [RelaisController::class, 'battement']);
Route::post('/mere/indicateurs', [RelaisController::class, 'indicateurs']);
Route::get('/admin/etat', [RelaisController::class, 'etat']);

Route::post('/banc/alterer', [RelaisController::class, 'bancAlterer']);
Route::post('/banc/retirer', [RelaisController::class, 'bancRetirer']);
Route::get('/banc/tout', [RelaisController::class, 'bancTout']);
Route::get('/banc/ids', [RelaisController::class, 'bancIds']);
