<div>
    @include('livewire.panneau._entete', ['titre' => 'Appareils', 'description' => 'Les appareils appairés : état, dernier contact, boîte aux lettres. Révocation.', 'regle' => 'Un appareil révoqué est effacé à son prochain contact s’il s’agit d’un mobile ; sa fiche reste (RG-14). Le jeton n’est jamais conservé en clair : seule son empreinte l’est. Le relais ne connaît d’un appareil que son identifiant, son état et le volume de ses enveloppes.'])
    @if($message)<p class="message" role="status">{{ $message }}</p>@endif
    <div class="carte">
        <h2>Appareils</h2>
        @if($lignes->isEmpty())
            <p class="vide">Aucun appareil appairé.</p>
        @else
            <table>
                <thead><tr><th>Appareil</th><th>Fonction</th><th>Identifiant</th><th>État</th><th>Dernier contact</th><th class="num">En attente</th><th></th></tr></thead>
                <tbody>
                @foreach($lignes as $l)
                    <tr wire:key="{{ $l->uuid }}">
                        <td>Mobile {{ \Illuminate\Support\Str::limit($l->uuid, 8, '') }}</td>
                        <td>{{ $l->profil ? ($l->profil === 'reception' ? 'Réception de secours' : 'Soignant'.($l->fonction ? ' · '.str_replace('_', ' ', $l->fonction) : '')) : 'non précisé' }}</td>
                        <td><code title="{{ $l->uuid }}">{{ \Illuminate\Support\Str::limit($l->uuid, 13, '…') }}</code></td>
                        <td><span class="puce {{ $l->etat === 'actif' ? 'ok' : 'alerte' }}">{{ $l->etat === 'actif' ? 'Actif' : 'Révoqué' }}</span></td>
                        <td>{{ \App\Relais\Format::depuis($l->dernier ? (int) $l->dernier : null) }}</td>
                        <td class="num">{{ (int) $l->boite }}</td>
                        <td>@if($l->etat === 'actif')<button class="btn danger" wire:click="revoquer('{{ $l->uuid }}')" wire:confirm="Révoquer cet appareil ? Il ne pourra plus ni déposer ni relever.">Révoquer</button>@endif</td>
                    </tr>
                @endforeach
                </tbody>
            </table>
        @endif
    </div>
    <p class="note">Révoquer coupe l'accès <strong>au relais</strong>. La fiche de l'appareil sur la console de la mère reste à mettre à jour : la révocation faite là-bas coupe aussi l'accès ici.</p>
</div>
