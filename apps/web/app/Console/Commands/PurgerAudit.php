<?php

namespace App\Console\Commands;

use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

/**
 * Purge le JOURNAL D'AUDIT du relais au-delà d'une durée de conservation. Simulation par défaut (`--oui` pour appliquer).
 *
 * Ce que cette commande ne touche JAMAIS : les enveloppes. Le journal chiffré sert à restaurer la mère ; une boîte
 * d'appareil est une suite contiguë (appareil, sens, rang) — en retirer une crée un « trou » que la mère détecte et traite
 * comme une altération (appareil bloqué). La rétention des enveloppes se règle donc côté mère, jamais ici.
 */
class PurgerAudit extends Command
{
    protected $signature = 'relais:purger {--jours=365 : durée de conservation de l\'audit} {--oui : appliquer (sinon simulation)}';

    protected $description = 'Purge le journal d\'audit du relais au-delà de la conservation (jamais les enveloppes)';

    public function handle(): int
    {
        $jours = (int) $this->option('jours');
        if ($jours < 30) {
            $this->error('La conservation minimale de l\'audit est de 30 jours.');

            return self::FAILURE;
        }
        $limite = (int) (microtime(true) * 1000) - $jours * 86400 * 1000;
        $n = DB::table('relais_audit')->where('quand', '<', $limite)->count();
        if (! $this->option('oui')) {
            $this->info("Simulation : $n ligne(s) d'audit de plus de $jours jours seraient purgées. Relancer avec --oui.");

            return self::SUCCESS;
        }
        DB::table('relais_audit')->where('quand', '<', $limite)->delete();
        DB::table('relais_audit')->insert([
            'quand' => (int) (microtime(true) * 1000), 'acteur' => 'console', 'action' => 'audit_purge', 'detail' => "$n ligne(s) de plus de $jours jours",
        ]);
        $this->info("$n ligne(s) purgée(s).");

        return self::SUCCESS;
    }
}
