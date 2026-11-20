<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // Journal d'audit de l'administration du relais (RG-12 : aucune action anonyme). Jamais de contenu de santé.
        Schema::create('relais_audit', function (Blueprint $t) {
            $t->id();
            $t->unsignedBigInteger('quand');       // ms
            $t->string('acteur', 190);
            $t->string('action', 64);
            $t->text('detail')->nullable();
            $t->index('quand');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('relais_audit');
    }
};
