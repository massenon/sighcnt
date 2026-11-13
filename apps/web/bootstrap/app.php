<?php

use Illuminate\Foundation\Application;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Foundation\Configuration\Middleware;

return Application::configure(basePath: dirname(__DIR__))
    ->withRouting(
        web: __DIR__.'/../routes/web.php',
        commands: __DIR__.'/../routes/console.php',
        health: '/up',
        then: function () {
            // Le relais (contrat de packages/sync/banc/relais.js) : API SANS session ni CSRF, jetons d'appareil.
            \Illuminate\Support\Facades\Route::middleware([])->group(base_path('routes/relais.php'));
        },
    )
    ->withMiddleware(function (Middleware $middleware): void {
        // Le panneau est le seul espace authentifié du relais.
        $middleware->redirectGuestsTo('/panneau/connexion');
        $middleware->redirectUsersTo('/panneau');
        // Lot RLS-SYNC : le panneau est réservé au superadmin (403 sinon, tentative journalisée).
        $middleware->alias(['superadmin' => \App\Http\Middleware\ExigerSuperadmin::class]);
    })
    ->withExceptions(function (Exceptions $exceptions): void {
        //
    })->create();
