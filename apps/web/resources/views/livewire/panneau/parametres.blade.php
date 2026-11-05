<div>
    @include('livewire.panneau._entete', ['titre' => 'Paramètres du relais', 'description' => 'Secret de la mère, seuil de battement, rétention de l’audit, crochets du banc d’essai (fermés).', 'regle' => 'Le secret de la mère se pose dans le .env du relais (jamais en base). Les crochets du banc d’essai sont fermés en production.'])
    <div class="carte">
        <h2>Paramètres</h2>
        <table>
            <thead><tr><th>Paramètre</th><th>Valeur</th><th>Où</th></tr></thead>
            <tbody>
                <tr><td>Seuil de battement</td><td>{{ $seuil }} min</td><td><code>RELAIS_SEUIL_BATTEMENT_MS</code></td></tr>
                <tr><td>Secret de la mère</td><td>@if($secretDefini)•••••••• (défini, non affichable)@else<span class="puce alerte">Non défini</span>@endif</td><td><code>RELAIS_SECRET_MERE</code></td></tr>
                <tr><td>Rétention de l’audit</td><td>{{ $retention }} jours</td><td><code>RELAIS_RETENTION_AUDIT_JOURS</code>, commande <code>relais:purger</code></td></tr>
                <tr><td>Espace disque minimal</td><td>{{ $disque }} %</td><td><code>RELAIS_SEUIL_DISQUE_PCT</code></td></tr>
                <tr><td>Crochets du banc</td><td><span class="puce {{ $banc ? 'alerte' : 'ok' }}">{{ $banc ? 'OUVERTS' : 'Fermés' }}</span></td><td><code>RELAIS_BANC={{ $banc ? 'true' : 'false' }}</code></td></tr>
            </tbody>
        </table>
    </div>
    <div class="carte" wire:ignore x-data="recuperationCle('{{ route('panneau.consultation.reglage') }}', '{{ route('panneau.consultation.coffre.envoi') }}', '{{ csrf_token() }}')">
        <h2>Récupération de la clé par courriel</h2>
        <p class="note">Désactivée par défaut. Activée, le relais conserve seulement un coffre : la clé de la clinique chiffrée dans votre navigateur par une phrase secrète. Ni la clé ni la phrase ne quittent le navigateur.</p>
        <label><input type="checkbox" x-model="actif"> Activer la récupération par courriel</label>
        <div x-show="actif">
            <input type="email" x-model="courriel" placeholder="Courriel de récupération" aria-label="Courriel de récupération">
            <input type="password" autocomplete="off" x-model="cle" placeholder="Clé de la clinique (64 hex)" aria-label="Clé de la clinique" size="60">
            <input type="password" autocomplete="off" x-model="phrase" placeholder="Phrase secrète (12 caractères)" aria-label="Phrase secrète">
        </div>
        <button type="button" @click="enregistrer()">Enregistrer</button>
        <button type="button" x-show="coffre" @click="envoyer()">Envoyer le coffre par courriel</button>
        <p class="note" x-text="message" role="status"></p>
    </div>
    <script src="{{ asset('js/consultation.js') }}"></script>
    <script>
        document.addEventListener('alpine:init', function () {
            window.Alpine.data('recuperationCle', function (urlReglage, urlEnvoi, jeton) {
                var entetes = { 'Content-Type': 'application/json', Accept: 'application/json', 'X-CSRF-TOKEN': jeton };
                return {
                    actif: false, courriel: '', cle: '', phrase: '', coffre: false, message: '',
                    async init() { var r = await (await fetch(urlReglage, { headers: { Accept: 'application/json' } })).json(); this.actif = r.actif; this.courriel = r.courriel || ''; this.coffre = r.coffre; },
                    async enregistrer() {
                        try {
                            var corps = { actif: this.actif };
                            if (this.actif) { corps.courriel = this.courriel; corps.coffre = await window.SighConsultation.chiffrerCle(this.cle, this.phrase); }
                            var r = await fetch(urlReglage, { method: 'POST', headers: entetes, body: JSON.stringify(corps) });
                            var j = await r.json();
                            this.message = r.ok ? (j.actif ? 'Récupération activée.' : 'Récupération désactivée, coffre effacé.') : (j.motif || j.code);
                            this.cle = ''; this.phrase = ''; this.coffre = r.ok && j.actif;
                        } catch (e) { this.message = e.message; }
                    },
                    async envoyer() { var r = await fetch(urlEnvoi, { method: 'POST', headers: entetes }); var j = await r.json(); this.message = r.ok ? 'Coffre envoyé.' : (j.motif || j.code); },
                };
            });
        });
    </script>
    <p class="note">Faire tourner le secret : le changer dans le .env du relais <strong>et</strong> dans la configuration de la mère, dans la même minute.</p>
</div>
