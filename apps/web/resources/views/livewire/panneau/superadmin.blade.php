<div>
    @include('livewire.panneau._entete', ['titre' => 'Comptes superadmin', 'description' => 'Les comptes qui administrent le relais : création par commande, mot de passe, sessions, double facteur.', 'regle' => 'Un compte se crée par commande (relais:superadmin, tâche cron à usage unique sur cPanel) : pas d’inscription publique. Mot de passe de 12 caractères au moins.'])
    @if($message)<p class="message" role="status">{{ $message }}</p>@endif
    @if($erreur)<p class="erreur" role="alert">{{ $erreur }}</p>@endif
    <div class="carte">
        <h2>Comptes</h2>
        <table>
            <thead><tr><th>Courriel</th><th>Créé</th><th>Dernière connexion</th><th>Double facteur</th></tr></thead>
            <tbody>
            @foreach($comptes as $c)
                <tr>
                    <td>{{ $c->email }}</td>
                    <td>{{ $c->created_at ? $c->created_at->timezone('Africa/Porto-Novo')->format('d/m/Y') : 'n/d' }}</td>
                    <td>{{ \App\Relais\Format::depuis($c->derniere ? (int) $c->derniere : null) }}</td>
                    <td><span class="puce attention">Non activé</span></td>
                </tr>
            @endforeach
            </tbody>
        </table>
    </div>
    <div class="carte">
        <h2>Sessions ouvertes</h2>
        @if($sessions->isEmpty())
            <p class="vide">Aucune session enregistrée.</p>
        @else
            <table>
                <thead><tr><th>Appareil</th><th>Adresse</th><th>Depuis</th></tr></thead>
                <tbody>
                @foreach($sessions as $s)
                    <tr><td>{{ \App\Livewire\Panneau\Superadmin::appareil($s->user_agent) }}</td><td>{{ \App\Livewire\Panneau\Superadmin::adresse($s->ip_address) }}</td><td>{{ \App\Relais\Format::depuis((int) $s->last_activity * 1000) }}</td></tr>
                @endforeach
                </tbody>
            </table>
        @endif
    </div>
    <form class="formulaire" style="margin:16px 0" wire:submit="changerMotDePasse">
        <label for="actuel">Mot de passe actuel</label>
        <input id="actuel" type="password" wire:model="actuel" autocomplete="current-password" required>
        <label for="nouveau">Nouveau mot de passe (8 caractères au moins)</label>
        <input id="nouveau" type="password" wire:model="nouveau" autocomplete="new-password" required>
        <label for="confirmation">Confirmation</label>
        <input id="confirmation" type="password" wire:model="confirmation" autocomplete="new-password" required>
        <p><button class="btn" type="submit">Changer le mot de passe</button></p>
    </form>
    <p class="note">Le double facteur n’est pas encore pris en charge par le relais : la colonne le dit au lieu de le laisser supposer.</p>
</div>
