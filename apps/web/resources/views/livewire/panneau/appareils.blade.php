<div>
    <h1>Appareils</h1>
    <p class="sous-titre">Mobiles appairés au relais. Le relais ne voit d'eux que leur identifiant et le volume de leurs enveloppes.</p>
    @if($message)<p class="message" role="status">{{ $message }}</p>@endif
    @if($lignes->isEmpty())
        <p class="vide">Aucun appareil appairé.</p>
    @else
        <table>
            <thead><tr><th>Identifiant</th><th>État</th><th class="num">Déposées</th><th class="num">Dans sa boîte</th><th>Dernier dépôt</th><th></th></tr></thead>
            <tbody>
            @foreach($lignes as $l)
                <tr wire:key="{{ $l->uuid }}">
                    <td><code title="{{ $l->uuid }}">{{ \Illuminate\Support\Str::limit($l->uuid, 13, '…') }}</code></td>
                    <td><span class="puce {{ $l->etat === 'actif' ? 'ok' : 'alerte' }}">{{ $l->etat === 'actif' ? 'Actif' : 'Révoqué' }}</span></td>
                    <td class="num">{{ (int) $l->deposees }}</td><td class="num">{{ (int) $l->boite }}</td>
                    <td>{{ $l->dernier ? \Carbon\Carbon::createFromTimestampMs($l->dernier)->timezone('Africa/Porto-Novo')->format('d/m/Y H:i:s') : '—' }}</td>
                    <td>@if($l->etat === 'actif')<button class="btn danger" wire:click="revoquer('{{ $l->uuid }}')" wire:confirm="Révoquer cet appareil ? Il ne pourra plus ni déposer ni relever.">Révoquer</button>@endif</td>
                </tr>
            @endforeach
            </tbody>
        </table>
    @endif
    <p class="note">Révoquer coupe l'accès <strong>au relais</strong>. La fiche de l'appareil sur la console de la mère reste à mettre à jour : la révocation faite là-bas coupe aussi l'accès ici.</p>
</div>
