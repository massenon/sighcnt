<div>
    @include('livewire.panneau._entete', ['titre' => 'Sauvegarde du relais', 'description' => 'Export de la base du relais avant toute migration ; le journal chiffré qu’elle contient sert à restaurer la mère.', 'regle' => 'Avant chaque migrate : export de la base (commande relais:exporter --avant-migration, par cron). Le contenu est déjà chiffré : un export ne contient aucune donnée lisible. Les fichiers sont déposés dans storage/app/exports.'])
    @if($message)<p class="message" role="status">{{ $message }}</p>@endif
    <div class="grille">
        <div class="carte"><h2>Dernier export</h2><div class="valeur">{{ $dernier ? \App\Relais\Format::depuis((int) $dernier->quand) : 'Aucun' }}</div></div>
        <div class="carte"><h2>Taille</h2><div class="valeur">{{ $dernier ? \App\Relais\Format::taille((int) $dernier->taille) : 'n/d' }}</div></div>
    </div>
    <div class="carte">
        <h2>Exports</h2>
        @if($exports->isEmpty())
            <p class="vide">Aucun export.</p>
        @else
            <table>
                <thead><tr><th>Date</th><th class="num">Taille</th><th>Avant migration</th></tr></thead>
                <tbody>@foreach($exports as $e)<tr><td>{{ \App\Relais\Format::date((int) $e->quand) }}</td><td class="num">{{ \App\Relais\Format::taille((int) $e->taille) }}</td><td>{{ $e->avant_migration ? 'oui' : 'non' }}</td></tr>@endforeach</tbody>
            </table>
        @endif
    </div>
    <p><button class="btn" type="button" wire:click="exporter" wire:loading.attr="disabled">Exporter maintenant</button></p>
</div>
