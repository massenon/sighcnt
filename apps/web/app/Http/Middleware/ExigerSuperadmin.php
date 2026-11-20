<?php

namespace App\Http\Middleware;

use App\Relais\Format;
use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Symfony\Component\HttpFoundation\Response;

/**
 * Le panneau est réservé au SUPERADMIN (décision de la Direction du 13/11/2026, lot RLS-SYNC). Un compte connecté qui ne l'est pas n'obtient pas la page : 403, tentative journalisée (RG-12),
 * et le menu ne lui propose rien (voir layouts/panneau.blade.php). Fermé par défaut : seul `superadmin === true` passe.
 */
class ExigerSuperadmin
{
    public function handle(Request $request, Closure $next): Response
    {
        $u = $request->user();
        if ($u === null || $u->superadmin !== true) {
            DB::table('relais_audit')->insert(['quand' => Format::maintenant(), 'acteur' => (string) ($u?->email ?? ''), 'action' => 'acces_refuse_non_superadmin', 'detail' => $request->path()]);
            abort(403, 'Le panneau du relais est réservé au superadmin.');
        }

        return $next($request);
    }
}
