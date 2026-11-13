<div>
    @include('livewire.panneau._entete', ['titre' => 'Paramètres du relais', 'description' => 'Secret de la mère, seuil de battement, rétention de l’audit, crochets du banc d’essai (fermés).', 'regle' => 'Le secret de la mère se pose dans le .env du relais (jamais en base). Les crochets du banc d’essai sont fermés en production. Les paramètres de la clinique (taux, dates, circuits, modes) ne se règlent pas ici : ils se règlent au poste, voyagent chiffrés et ce relais ne les lit pas.'])
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
    <div class="carte">
        <h2>Synchronisation : conservation et seuils</h2>
        <p class="note">Réglages de l’écran « Synchronisation », enregistrés en base, bornés et journalisés. Toutes les valeurs de départ sont des propositions à valider par la Direction.</p>
        @if($synchroMessage)<p class="message" role="status">{{ $synchroMessage }}</p>@endif
        @foreach($synchroRefus as $refus)<p class="erreur" role="alert">{{ $refus['motif'] }} {{ $refus['geste'] }}</p>@endforeach
        <table>
            <thead><tr><th>Réglage</th><th>Valeur</th><th>Bornes</th></tr></thead>
            <tbody>
            @foreach($reglagesSynchro as $cle => $d)
                <tr>
                    <td><label for="synchro-{{ $cle }}">{{ $d['libelle'] }}</label></td>
                    <td><input id="synchro-{{ $cle }}" type="number" wire:model="synchro.{{ $cle }}" min="{{ $d['min'] }}" max="{{ $d['max'] }}" step="1" aria-label="{{ $d['libelle'] }}"> {{ $d['unite'] }}</td>
                    <td>de {{ $d['min'] }} à {{ $d['max'] }} {{ $d['unite'] }}, défaut {{ $d['defaut'] }}</td>
                </tr>
            @endforeach
            </tbody>
        </table>
        <p><button class="btn" type="button" wire:click="enregistrerSynchro">Enregistrer les réglages de synchronisation</button></p>
    </div>
    <div class="carte" wire:ignore x-data="messagerieSmtp('{{ route('panneau.smtp') }}', '{{ route('panneau.smtp.envoi') }}', '{{ route('panneau.smtp.test') }}', '{{ csrf_token() }}')">
        <h2>Messagerie SMTP du relais</h2>
        <p class="note">Sans serveur SMTP réglé, le relais n'envoie aucun courriel (récupération de la clé comprise) et le dit. Le mot de passe est enregistré chiffré, jamais relu ni affiché : laisser le champ vide pour conserver l'actuel.</p>
        <label>Serveur <input type="text" x-model="f.hote" placeholder="smtp.exemple.bj" aria-label="Serveur SMTP"></label>
        <label>Port <input type="number" x-model.number="f.port" min="1" max="65535" aria-label="Port"></label>
        <label>Chiffrement
            <select x-model="f.chiffrement" aria-label="Chiffrement">
                <option value="starttls">STARTTLS (port 587)</option>
                <option value="ssl">SSL/TLS (port 465)</option>
                <option value="aucun">Aucun (réseau local de confiance)</option>
            </select>
        </label>
        <label><input type="checkbox" x-model="f.verifier_certificat"> Vérifier le certificat du serveur</label>
        <label>Identifiant <input type="text" autocomplete="off" x-model="f.utilisateur" aria-label="Identifiant SMTP"></label>
        <label>Mot de passe <input type="password" autocomplete="new-password" x-model="f.mdp" :placeholder="mdpDefini ? 'Défini (laisser vide pour conserver)' : 'Aucun mot de passe'" aria-label="Mot de passe SMTP"></label>
        <label x-show="mdpDefini"><input type="checkbox" x-model="f.effacer_mdp"> Effacer le mot de passe enregistré</label>
        <label>Adresse d'expéditeur <input type="email" x-model="f.expediteur" placeholder="relais@clinique.bj" aria-label="Adresse d'expéditeur"></label>
        <label>Nom d'expéditeur <input type="text" x-model="f.expediteur_nom" aria-label="Nom d'expéditeur"></label>
        <label>Répondre à (adresse) <input type="email" x-model="f.repondre" placeholder="secretariat@clinique.bj" aria-label="Adresse de réponse"></label>
        <label>Répondre à (nom) <input type="text" x-model="f.repondre_nom" aria-label="Nom de réponse"></label>
        <button type="button" @click="enregistrer()">Enregistrer</button>
        <hr>
        <label>Envoyer un message de test à <input type="email" x-model="test" placeholder="vous@exemple.bj" aria-label="Destinataire du test"></label>
        <button type="button" @click="envoyerTest()" :disabled="!configure">Envoyer un message de test</button>
        <p class="note" x-text="message" role="status"></p>
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
            window.Alpine.data('messagerieSmtp', function (urlReglage, urlEnvoi, urlTest, jeton) {
                var entetes = { 'Content-Type': 'application/json', Accept: 'application/json', 'X-CSRF-TOKEN': jeton };
                return {
                    f: { hote: '', port: 587, chiffrement: 'starttls', utilisateur: '', mdp: '', effacer_mdp: false, expediteur: '', expediteur_nom: '', repondre: '', repondre_nom: '', verifier_certificat: true },
                    mdpDefini: false, configure: false, test: '', message: '',
                    appliquer(r) { this.f.hote = r.hote; this.f.port = r.port; this.f.chiffrement = r.chiffrement; this.f.utilisateur = r.utilisateur; this.f.expediteur = r.expediteur; this.f.expediteur_nom = r.expediteur_nom; this.f.repondre = r.repondre; this.f.repondre_nom = r.repondre_nom; this.f.verifier_certificat = r.verifier_certificat; this.f.mdp = ''; this.f.effacer_mdp = false; this.mdpDefini = r.mdp_defini; this.configure = r.configure; },
                    async init() { this.appliquer(await (await fetch(urlReglage, { headers: { Accept: 'application/json' } })).json()); },
                    async enregistrer() {
                        var r = await fetch(urlEnvoi, { method: 'POST', headers: entetes, body: JSON.stringify(this.f) });
                        var j = await r.json();
                        if (r.ok) { this.appliquer(j); this.message = 'Réglages enregistrés.'; }
                        else { this.message = j.motif || (j.errors ? Object.values(j.errors).flat().join(' ') : j.code); }
                    },
                    async envoyerTest() {
                        this.message = 'Envoi en cours…';
                        var r = await fetch(urlTest, { method: 'POST', headers: entetes, body: JSON.stringify({ destinataire: this.test }) });
                        var j = await r.json();
                        this.message = r.ok ? 'Message de test envoyé à ' + this.test + '.' : (j.etape ? 'Échec à l\'étape « ' + j.etape + ' » : ' + j.motif + ' (' + j.detail + ')' : (j.motif || (j.errors ? Object.values(j.errors).flat().join(' ') : j.code)));
                    },
                };
            });
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
