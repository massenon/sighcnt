<?php

namespace App\Console\Commands;

use App\Models\User;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;

/**
 * Crée (ou remet à jour) le compte SUPERADMIN du panneau. Sur un cPanel sans SSH, on le lance par une tâche cron à usage
 * unique : `php artisan relais:superadmin courriel@exemple.bj --mot-de-passe='…'`. Le mot de passe n'est jamais journalisé.
 */
class CreerSuperadmin extends Command
{
    protected $signature = 'relais:superadmin {courriel} {--mot-de-passe= : 12 caractères au moins}';

    protected $description = 'Crée ou met à jour le compte superadmin du panneau du relais';

    public function handle(): int
    {
        $mdp = (string) $this->option('mot-de-passe');
        if (mb_strlen($mdp) < 12) {
            $this->error('Le mot de passe doit compter au moins 12 caractères.');

            return self::FAILURE;
        }
        $courriel = mb_strtolower(trim((string) $this->argument('courriel')));
        if (! filter_var($courriel, FILTER_VALIDATE_EMAIL)) {
            $this->error('Courriel invalide.');

            return self::FAILURE;
        }
        $existe = User::where('email', $courriel)->exists();
        User::updateOrCreate(['email' => $courriel], ['name' => 'Superadmin', 'password' => Hash::make($mdp)]);
        DB::table('relais_audit')->insert([
            'quand' => (int) (microtime(true) * 1000), 'acteur' => 'console', 'action' => $existe ? 'superadmin_mis_a_jour' : 'superadmin_cree', 'detail' => $courriel,
        ]);
        $this->info($existe ? 'Compte mis à jour.' : 'Compte créé.');

        return self::SUCCESS;
    }
}
