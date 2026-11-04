<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * E1424 (arbitrage du 04/11/2026) : un code d'appairage EXPIRE aussi au relais. La mère déclare l'échéance qu'elle tient déjà de son côté (15 minutes) ;
 * le relais la refuse passée (`code_expire`). Colonne vide = code déclaré avant cette règle : il reste valable (aucun appareil n'est invalidé).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('relais_codes', function (Blueprint $t) {
            $t->unsignedBigInteger('expire_le')->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('relais_codes', function (Blueprint $t) {
            $t->dropColumn('expire_le');
        });
    }
};
