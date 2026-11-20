<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * E1600 : la mère déclare avec chaque code d'appairage de mobile le PROFIL et la FONCTION du soignant. Le relais les range comme une
 * étiquette d'affichage (panneau Codes et Appareils) : il n'en tire aucun droit, la mère relit sa propre table à chaque dépôt.
 * Aucune donnée de santé : un libellé de profil et une fonction (medecin, sage_femme, infirmier, aide_soignant).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('relais_codes', function (Blueprint $t) {
            $t->string('profil', 32)->nullable();
            $t->string('fonction', 32)->nullable();
        });
        Schema::table('relais_appareils', function (Blueprint $t) {
            $t->string('profil', 32)->nullable();
            $t->string('fonction', 32)->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('relais_appareils', function (Blueprint $t) {
            $t->dropColumn(['profil', 'fonction']);
        });
        Schema::table('relais_codes', function (Blueprint $t) {
            $t->dropColumn(['profil', 'fonction']);
        });
    }
};
