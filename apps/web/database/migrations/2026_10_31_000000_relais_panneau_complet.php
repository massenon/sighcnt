<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Panneau superadmin complet : de quoi montrer les douze écrans du module RLS sans que le relais ne sache rien de plus.
 * Aucune de ces tables ne contient de donnée de santé : horodatages, compteurs publiés par la mère, noms de fichiers d'export.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('relais_codes', function (Blueprint $t) {
            $t->unsignedBigInteger('cree')->nullable();       // ms, posé à la déclaration du code par la mère
            $t->unsignedBigInteger('utilise_le')->nullable(); // ms, posé à l'appairage
        });

        // Alertes du relais : un type, un instant, un détail technique. Jamais un contenu métier.
        Schema::create('relais_alertes', function (Blueprint $t) {
            $t->id();
            $t->string('type', 32);
            $t->string('detail', 190)->nullable();
            $t->unsignedBigInteger('debut');
            $t->unsignedBigInteger('fin')->nullable();
            $t->index(['type', 'fin']);
        });

        // Historique des indicateurs publiés par la mère (seul contenu en clair accepté), purgé au-delà de 48 h.
        Schema::create('relais_indicateurs_historique', function (Blueprint $t) {
            $t->id();
            $t->unsignedBigInteger('quand');
            $t->text('charge');
            $t->index('quand');
        });

        Schema::create('relais_exports', function (Blueprint $t) {
            $t->id();
            $t->unsignedBigInteger('quand');
            $t->unsignedBigInteger('taille');
            $t->boolean('avant_migration')->default(false);
            $t->string('fichier', 190);
        });
    }

    public function down(): void
    {
        foreach (['relais_exports', 'relais_indicateurs_historique', 'relais_alertes'] as $table) {
            Schema::dropIfExists($table);
        }
        Schema::table('relais_codes', function (Blueprint $t) {
            $t->dropColumn(['cree', 'utilise_le']);
        });
    }
};
