<div wire:poll.15s>
    <h1>Tableau de bord</h1>
    <p class="sous-titre">État du relais en ligne. Actualisé toutes les 15 secondes.</p>

    <div class="grille">
        <div class="carte">
            <h2>Poste mère</h2>
            @if($age === null)
                <span class="puce alerte">Jamais vue</span>
                <p>Aucun battement de cœur reçu.</p>
            @elseif($alerte)
                <span class="puce alerte">Silencieuse</span>
                <p>Dernier signe il y a {{ intdiv($age, 60000) }} min {{ intdiv($age % 60000, 1000) }} s — au-delà du seuil de {{ $seuilMinutes }} min.</p>
            @else
                <span class="puce ok">En ligne</span>
                <p>Dernier signe il y a {{ intdiv($age, 1000) }} s.</p>
            @endif
        </div>
        <div class="carte"><h2>Enveloppes stockées</h2><div class="valeur">{{ $total }}</div>
            <p>Dernier dépôt : {{ $dernier ? \Carbon\Carbon::createFromTimestampMs($dernier)->timezone('Africa/Porto-Novo')->format('d/m/Y H:i:s') : '—' }}</p></div>
        <div class="carte"><h2>Appareils</h2><div class="valeur">{{ $actifs }}</div><p>actifs · {{ $revoques }} révoqué(s)</p></div>
    </div>

    <h2>Volumes par sens</h2>
    <table>
        <thead><tr><th>Sens</th><th class="num">Enveloppes</th><th class="num">Taille (Ko)</th></tr></thead>
        <tbody>
        @foreach(['journal' => 'Journal de la mère (sauvegarde chiffrée)', 'vers_mere' => 'Mobiles → mère', 'vers_mobile' => 'Mère → mobiles'] as $cle => $libelle)
            <tr><td>{{ $libelle }}</td><td class="num">{{ $parSens[$cle]->n ?? 0 }}</td><td class="num">{{ number_format(((int) ($parSens[$cle]->taille ?? 0)) / 1024, 1, ',', ' ') }}</td></tr>
        @endforeach
        </tbody>
    </table>

    <h2>Indicateurs de la clinique</h2>
    @if(count($indicateurs))
        <table>
            <thead><tr><th>Indicateur</th><th class="num">Valeur</th></tr></thead>
            <tbody>@foreach($indicateurs as $k => $v)<tr><td>{{ str_replace('_', ' ', $k) }}</td><td class="num">{{ is_scalar($v) ? $v : json_encode($v) }}</td></tr>@endforeach</tbody>
        </table>
    @else
        <p class="vide">Aucun indicateur reçu.</p>
    @endif

    <p class="note">Ce panneau ne lit <strong>jamais</strong> le contenu des enveloppes : elles sont chiffrées de bout en bout avec la clé de la clinique, que le relais ne détient pas. Les indicateurs ci-dessus sont des agrégats sans nom de patient.</p>
</div>
