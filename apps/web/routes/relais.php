<?php

use App\Http\Controllers\RecuperationController;
use App\Http\Controllers\RelaisController;
use App\Http\Controllers\SauvegardeController;
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
Route::get('/pair/appareils', [RelaisController::class, 'appareilsPair']);
Route::get('/compteur', [RelaisController::class, 'compteur']);
Route::post('/mere/revoquer', [RelaisController::class, 'revoquer']);
Route::post('/mere/activer', [RelaisController::class, 'activerMere']);
Route::post('/mere/desactiver', [RelaisController::class, 'desactiverMere']);
Route::post('/mere/battement', [RelaisController::class, 'battement']);
Route::post('/mere/indicateurs', [RelaisController::class, 'indicateurs']);
Route::post('/recuperation/envoyer', [RecuperationController::class, 'envoyer']);
Route::get('/admin/etat', [RelaisController::class, 'etat']);

Route::post('/banc/alterer', [RelaisController::class, 'bancAlterer']);
Route::post('/banc/retirer', [RelaisController::class, 'bancRetirer']);
Route::get('/banc/tout', [RelaisController::class, 'bancTout']);
Route::get('/banc/ids', [RelaisController::class, 'bancIds']);

/* Lot 5 (ADR-0007) : la sauvegarde hors site, RÉSERVÉE À LA MÈRE (blocs opaques chiffrés par la clé de la clinique, que le relais ne détient pas). Contrat : packages/sync/banc/relais-sauvegarde.js. */
Route::get('/sauvegarde/etat', [SauvegardeController::class, 'etat']);
Route::post('/sauvegarde/manquants', [SauvegardeController::class, 'manquants']);
Route::put('/sauvegarde/bloc/{id}', [SauvegardeController::class, 'deposerBloc']);
Route::get('/sauvegarde/bloc/{id}', [SauvegardeController::class, 'lireBloc']);
Route::post('/sauvegarde/copie', [SauvegardeController::class, 'ouvrir']);
Route::post('/sauvegarde/copie/{id}/blocs', [SauvegardeController::class, 'attacher']);
Route::post('/sauvegarde/copie/{id}/valider', [SauvegardeController::class, 'valider']);
Route::get('/sauvegarde/copies', [SauvegardeController::class, 'copies']);
Route::get('/sauvegarde/copie/{id}', [SauvegardeController::class, 'copie']);
Route::post('/banc/sauvegarde/reglage', [SauvegardeController::class, 'bancReglage']);
Route::post('/banc/sauvegarde/alterer', [SauvegardeController::class, 'bancAlterer']);
Route::post('/banc/sauvegarde/vieillir', [SauvegardeController::class, 'bancVieillir']);
Route::get('/banc/sauvegarde/tout', [SauvegardeController::class, 'bancTout']);
