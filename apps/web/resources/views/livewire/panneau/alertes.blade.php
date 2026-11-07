<div>
    @include('livewire.panneau._entete', ['titre' => 'Alertes et notifications', 'description' => 'Règles d’alerte du relais et canaux de notification du superadmin (courriel).', 'regle' => 'Une alerte porte un type, un appareil, une heure, jamais un contenu métier. Le courriel du superadmin ne contient aucun nom de patient.'])
    @if($message)<p class="message" role="status">{{ $message }}</p>@endif
    <div class="carte">
        <h2>Règles</h2>
        <table>
            <thead><tr><th>Alerte</th><th>Seuil</th><th>Canal</th><th>Active</th></tr></thead>
            <tbody>
            @foreach($regles as $r)
                <tr><td>{{ $r['libelle'] }}</td><td>{{ \App\Livewire\Panneau\Alertes::seuil($r['type']) }}</td><td>{{ $r['canal'] }}</td>
                    <td><span class="puce {{ $r['active'] ? 'ok' : 'attention' }}">{{ $r['active'] ? 'Oui' : 'Non' }}</span></td></tr>
            @endforeach
            </tbody>
        </table>
    </div>
    <p><button class="btn" type="button" wire:click="tester">Envoyer un courriel de test</button></p>
    <p class="note">Les seuils se règlent dans le fichier .env du relais (voir « Paramètres du relais »). Les alertes levées se lisent au tableau de bord.</p>
</div>
