<div>
    <h1>Journal d'administration</h1>
    <p class="sous-titre">Les 200 dernières actions (RG-12 : aucune action anonyme). Aucun contenu de santé n'y figure.</p>
    @if($lignes->isEmpty())
        <p class="vide">Journal vide.</p>
    @else
        <table>
            <thead><tr><th>Quand</th><th>Acteur</th><th>Action</th><th>Détail</th></tr></thead>
            <tbody>@foreach($lignes as $l)<tr><td>{{ \Carbon\Carbon::createFromTimestampMs($l->quand)->timezone('Africa/Porto-Novo')->format('d/m/Y H:i:s') }}</td><td>{{ $l->acteur }}</td><td>{{ str_replace('_', ' ', $l->action) }}</td><td><code>{{ $l->detail }}</code></td></tr>@endforeach</tbody>
        </table>
    @endif
</div>
