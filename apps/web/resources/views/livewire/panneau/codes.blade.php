<div>
    <h1>Codes d'appairage</h1>
    <p class="sous-titre">Déclarés par la mère. Le code en clair n'existe que sur sa console : le relais n'en garde que l'empreinte.</p>
    @if($codes->isEmpty())
        <p class="vide">Aucun code déclaré.</p>
    @else
        <table>
            <thead><tr><th>Empreinte</th><th>État</th></tr></thead>
            <tbody>@foreach($codes as $c)<tr><td><code>{{ substr($c->hash, 0, 12) }}…</code></td><td><span class="puce {{ $c->utilise ? 'attention' : 'ok' }}">{{ $c->utilise ? 'Utilisé' : 'Disponible' }}</span></td></tr>@endforeach</tbody>
        </table>
    @endif
</div>
