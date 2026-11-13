<?php

use App\Relais\Synchro\Reglages;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * LOT RLS-SYNC : l'écran « Synchronisation » du panneau (mère, fileuls, mobiles).
 *
 *  - `relais_synchro_historique` : un HISTORIQUE À PART (jamais le champ libre `charge` des indicateurs, purgé à 48 h). Des compteurs et des horodatages, rien d'autre : la colonne `ref`
 *    est le nom technique d'un poste ou l'identifiant d'un appareil, jamais un nom de personne ni d'un dossier. Conservé 3 mois par défaut, réglage borné.
 *  - `relais_appareils.dernier_releve` et `releve_n` : le relais note QUAND un mobile a relevé sa boîte et JUSQU'À QUEL RANG (le `depuis_n` qu'il envoie), de quoi dire combien d'enveloppes
 *    l'attendent. Un rang et une heure : le relais ne lit toujours aucun contenu.
 *  - `users.superadmin` : le panneau est réservé au superadmin. Tout compte existant l'est (le seul chemin de création est `relais:superadmin`) ; un compte créé autrement ne l'est pas.
 *  - les réglages de l'écran sont SEMÉS dans `relais_meta` avec leurs défauts (à valider par la Direction).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('relais_synchro_historique', function (Blueprint $t) {
            $t->id();
            $t->unsignedBigInteger('quand');
            $t->string('nature', 8);                              // mere | fileul | mobile
            $t->string('ref', 64);                                // nom technique du poste, identifiant d'appareil ou « mere »
            $t->unsignedBigInteger('dernier_contact')->nullable(); // ms ; null = jamais vu
            $t->unsignedBigInteger('retard_journal')->nullable();  // opérations en attente (fileul) ; null = non calculable
            $t->unsignedInteger('conflits')->nullable();
            $t->unsignedInteger('demandes')->nullable();
            $t->unsignedInteger('attente')->nullable();            // enveloppes en attente (mobile)
            $t->index('quand');
            $t->index(['nature', 'ref', 'quand']);
        });

        Schema::table('relais_appareils', function (Blueprint $t) {
            $t->unsignedBigInteger('dernier_releve')->nullable();
            $t->unsignedBigInteger('releve_n')->default(0);
        });

        Schema::table('users', function (Blueprint $t) {
            $t->boolean('superadmin')->default(true);
        });

        Reglages::semer();
    }

    public function down(): void
    {
        Schema::table('users', function (Blueprint $t) {
            $t->dropColumn('superadmin');
        });
        Schema::table('relais_appareils', function (Blueprint $t) {
            $t->dropColumn(['dernier_releve', 'releve_n']);
        });
        Schema::dropIfExists('relais_synchro_historique');
        \Illuminate\Support\Facades\DB::table('relais_meta')->where('k', 'like', 'reglage.synchro.%')->delete();
    }
};
