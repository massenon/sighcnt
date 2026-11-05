<div>
    @include('livewire.panneau._entete', ['titre' => 'Consultation des copies', 'description' => 'Les dossiers patients copiés par les postes, lisibles ici seulement avec la clé de la clinique, déchiffrés dans votre navigateur.', 'regle' => 'Le relais ne détient aucune clé : il sert des enveloppes chiffrées. La clé que vous saisissez reste dans cette page et n’est jamais envoyée au serveur.'])
    <script src="{{ asset('js/consultation.js') }}"></script>
    <div wire:ignore x-data="consultation('{{ route('panneau.consultation.appareils') }}', '{{ route('panneau.consultation.enveloppes') }}')">
        <div class="carte">
            <h2>Volume de la copie</h2>
            <p x-text="volume"></p>
        </div>
        <div class="carte">
            <h2>Clé de la clinique</h2>
            <p class="note">64 caractères hexadécimaux. Elle n’est pas conservée : fermer la page l’oublie.</p>
            <input type="password" autocomplete="off" placeholder="Clé de la clinique" x-model="cle" aria-label="Clé de la clinique" size="70">
            <p class="note">Clé perdue ? Si la récupération par courriel a été activée aux paramètres, collez le coffre reçu puis saisissez la phrase secrète.</p>
            <details>
                <summary>Ouvrir un coffre</summary>
                <textarea x-model="coffre" rows="3" cols="70" aria-label="Coffre reçu par courriel"></textarea>
                <input type="password" autocomplete="off" x-model="phrase" placeholder="Phrase secrète" aria-label="Phrase secrète">
                <button type="button" @click="ouvrirCoffre()">Retrouver la clé</button>
            </details>
        </div>
        <div class="carte">
            <h2>Dossiers patients</h2>
            <button type="button" @click="charger()">Charger et déchiffrer</button>
            <p class="note" x-text="message" role="status"></p>
            <input type="search" x-model="recherche" placeholder="Rechercher un dossier" aria-label="Rechercher un dossier">
            <table>
                <thead><tr><th>Fiche</th><th>Contenu</th><th>Archivé</th></tr></thead>
                <tbody>
                    <template x-for="f in filtrees()" :key="f.fiche">
                        <tr><td x-text="f.fiche"></td><td x-text="resume(f)"></td><td x-text="f.archive ? 'oui' : 'non'"></td></tr>
                    </template>
                </tbody>
            </table>
        </div>
    </div>
    <script>
        document.addEventListener('alpine:init', function () {
            window.Alpine.data('consultation', function (urlAppareils, urlEnveloppes) {
                return {
                    cle: '', coffre: '', phrase: '', message: '', recherche: '', volume: 'Mesure en cours…', charges: [],
                    async init() {
                        try {
                            var r = await (await fetch(urlAppareils, { headers: { Accept: 'application/json' } })).json();
                            var v = r.volume;
                            this.volume = v.fiches === 0 ? 'Aucune copie reçue.' : v.fiches + ' fiche(s), ' + v.octets + ' octets chiffrés, ' + v.moyenne + ' octets en moyenne par fiche, ' + v.maximum + ' au maximum.';
                            this.appareils = r.appareils;
                        } catch (e) { this.volume = 'Mesure indisponible.'; }
                    },
                    async charger() {
                        this.message = ''; this.charges = [];
                        try {
                            var cle = await window.SighConsultation.importerCle(this.cle);
                            for (var a of (this.appareils || [])) {
                                var depuis = 0;
                                for (;;) {
                                    var r = await (await fetch(urlEnveloppes + '?appareil=' + encodeURIComponent(a.uuid) + '&depuis_n=' + depuis, { headers: { Accept: 'application/json' } })).json();
                                    for (var e of r.env) { this.charges.push(await window.SighConsultation.dechiffrer(e, cle)); depuis = e.n; }
                                    if (r.fin) break;
                                }
                            }
                            this.message = this.filtrees().length + ' dossier(s) lisible(s).';
                        } catch (e) { this.message = 'Déchiffrement impossible : clé incorrecte ou copie altérée.'; }
                    },
                    async ouvrirCoffre() {
                        try { this.cle = await window.SighConsultation.dechiffrerCle(JSON.parse(this.coffre), this.phrase); this.message = 'Clé retrouvée.'; }
                        catch (e) { this.message = 'Coffre ou phrase secrète incorrects.'; }
                    },
                    filtrees() {
                        var q = this.recherche.toLowerCase();
                        return window.SighConsultation.fichesDe(this.charges, 'patients').filter(function (f) { return !q || JSON.stringify(f.data).toLowerCase().indexOf(q) >= 0 || String(f.fiche).toLowerCase().indexOf(q) >= 0; });
                    },
                    resume(f) { return Object.keys(f.data || {}).map(function (k) { return k + ' : ' + f.data[k]; }).join(' · '); },
                };
            });
        });
    </script>
</div>
