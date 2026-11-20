<div>
    @include('livewire.panneau._entete', ['titre' => 'Journal d’audit du relais', 'description' => 'Qui a fait quoi sur le panneau : connexions, révocations, codes, changements de paramètres.', 'regle' => 'Aucune action anonyme (RG-12). Conservation '.config('relais.retention_audit_jours').' jours (30 au minimum) ; la purge ne touche jamais aux enveloppes. Les 200 dernières actions sont affichées et aucun contenu de santé n’y figure.'])
    <div class="carte">
        <h2>Journal</h2>
        @if($lignes->isEmpty())
            <p class="vide">Journal vide.</p>
        @else
            <table>
                <thead><tr><th>Quand</th><th>Acteur</th><th>Action</th><th>Détail</th></tr></thead>
                <tbody>@foreach($lignes as $l)<tr><td>{{ \App\Relais\Format::date($l->quand) }}</td><td>{{ $l->acteur }}</td><td>{{ str_replace('_', ' ', $l->action) }}</td><td><code>{{ $l->detail }}</code></td></tr>@endforeach</tbody>
            </table>
        @endif
    </div>
</div>
