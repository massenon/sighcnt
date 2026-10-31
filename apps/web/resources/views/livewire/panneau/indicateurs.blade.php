<div>
    @include('livewire.panneau._entete', ['titre' => 'Indicateurs reçus', 'description' => 'Les compteurs publiés par la mère à chaque battement. Aucun nom, aucun motif.', 'regle' => 'Les indicateurs sont des agrégats en clair publiés par la mère, sans nom de patient. Le relais les affiche tels qu’il les reçoit et ne les interprète pas.'])
    <div class="carte">
        <h2>Dernier envoi</h2>
        @if($dernier === [])
            <p class="vide">Aucun indicateur reçu.</p>
        @else
            <pre><code>{{ json_encode($dernier, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) }}</code></pre>
        @endif
    </div>
    <div class="carte">
        <h2>Historique (24 h)</h2>
        @if($historique->isEmpty())
            <p class="vide">Aucun envoi sur les dernières 24 heures.</p>
        @else
            <table>
                <thead><tr><th>Heure</th><th class="num">Séquence</th><th class="num">Appareils actifs</th><th class="num">Conflits</th><th class="num">Bloqués</th></tr></thead>
                <tbody>
                @foreach($historique as $h)
                    <tr>
                        <td>{{ \Carbon\Carbon::createFromTimestampMs($h->quand)->timezone('Africa/Porto-Novo')->format('H:i') }}</td>
                        <td class="num">{{ $h->seq ?? 'n/d' }}</td><td class="num">{{ $h->actifs ?? 'n/d' }}</td>
                        <td class="num">{{ $h->conflits ?? 'n/d' }}</td><td class="num">{{ $h->bloques ?? 'n/d' }}</td>
                    </tr>
                @endforeach
                </tbody>
            </table>
        @endif
    </div>
</div>
