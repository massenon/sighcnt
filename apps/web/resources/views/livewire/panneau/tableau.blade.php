<div wire:poll.15s>
    @include('livewire.panneau._entete', ['titre' => 'Tableau de bord du relais', 'description' => 'La mère est-elle vivante, à jour, sauvegardée ? Volumes et alertes, sans aucun nom de patient.', 'regle' => 'Le relais lève une alerte « battement » si la mère se tait plus de '.$seuilMinutes.' minutes. Les indicateurs sont le seul contenu en clair. Actualisé toutes les 15 secondes.'])

    <div class="grille">
        <div class="carte">
            <h2>Mère</h2>
            @if($age === null)
                <span class="puce alerte">Jamais vue</span>
                <p>Aucun battement de cœur reçu.</p>
            @elseif($alerte)
                <span class="puce alerte">Silencieuse</span>
                <p>Dernier signe il y a {{ intdiv($age, 60000) }} min {{ intdiv($age % 60000, 1000) }} s, au-delà du seuil de {{ $seuilMinutes }} min.</p>
            @else
                <span class="puce ok">En ligne</span>
                <p>Dernier signe il y a {{ intdiv($age, 1000) }} s.</p>
            @endif
        </div>
        <div class="carte"><h2>Appareils actifs</h2><div class="valeur">{{ $actifs }}</div><p>{{ $revoques }} révoqué(s)</p></div>
        <div class="carte"><h2>Enveloppes stockées</h2><div class="valeur">{{ $total }}</div>
            <p>Dernier dépôt : {{ \App\Relais\Format::date($dernier) }}</p></div>
        <div class="carte"><h2>Alertes</h2><div class="valeur">{{ $ouvertes }}</div><p>en cours</p></div>
    </div>

    <div class="carte">
        <h2>Dernières alertes</h2>
        @if($alertes->isEmpty())
            <p class="vide">Aucune alerte levée.</p>
        @else
            <table>
                <thead><tr><th>Quand</th><th>Alerte</th><th>Durée</th></tr></thead>
                <tbody>
                @foreach($alertes as $a)
                    <tr>
                        <td>{{ \App\Relais\Format::depuis($a->debut) }}</td>
                        <td>{{ \App\Relais\Surveillance::libelle($a->type) }}</td>
                        <td>@if($a->fin){{ \App\Relais\Format::duree($a->fin - $a->debut) }} (résolue)@else en cours ({{ \App\Relais\Format::duree($maintenant - $a->debut) }})@endif</td>
                    </tr>
                @endforeach
                </tbody>
            </table>
        @endif
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
