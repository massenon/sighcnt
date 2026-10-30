<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('relais_codes', function (Blueprint $t) {
            $t->string('hash', 64)->primary();   // sha256 du code d'appairage : le clair n'est jamais conservé
            $t->boolean('utilise')->default(false);
        });

        Schema::create('relais_appareils', function (Blueprint $t) {
            $t->string('uuid', 64)->primary();
            $t->string('jeton_hash', 64);        // jamais le jeton en clair
            $t->string('etat', 16)->default('actif'); // actif | revoque
        });

        // Enveloppes CHIFFRÉES de bout en bout : le relais ne voit que (appareil, sens, rang, taille).
        Schema::create('relais_enveloppes', function (Blueprint $t) {
            $t->id('rid');
            $t->string('id', 128)->unique();     // clé d'idempotence : redéposer ne duplique pas
            $t->string('appareil', 64);
            $t->string('dir', 16);               // vers_mere | vers_mobile | journal
            $t->unsignedBigInteger('n');         // rang contigu par (appareil, sens)
            $t->text('nonce');
            $t->longText('ct');
            $t->unsignedInteger('taille');
            $t->unsignedBigInteger('recu');      // ms
            $t->unique(['appareil', 'dir', 'n']);
            $t->index(['dir', 'appareil', 'n']);
        });

        Schema::create('relais_meta', function (Blueprint $t) {
            $t->string('k', 64)->primary();
            $t->text('v')->nullable();
        });
    }

    public function down(): void
    {
        foreach (['relais_meta', 'relais_enveloppes', 'relais_appareils', 'relais_codes'] as $table) {
            Schema::dropIfExists($table);
        }
    }
};
