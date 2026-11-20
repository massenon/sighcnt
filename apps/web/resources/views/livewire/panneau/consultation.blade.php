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
            <input type="search" x-model="recherche" @input.debounce.200ms="page = 0; filtrer()" placeholder="Rechercher un dossier" aria-label="Rechercher un dossier">
            <table>
                <thead><tr><th>Fiche</th><th>Contenu</th><th>Archivé</th></tr></thead>
                <tbody>
                    <template x-for="f in visibles" :key="f.fiche">
                        <tr><td x-text="f.fiche"></td><td x-text="resume(f)"></td><td x-text="f.archive ? 'oui' : 'non'"></td></tr>
                    </template>
                </tbody>
            </table>
            <p class="note" role="status" x-show="nbFiltrees > 0" x-text="'Fiches ' + (page * taillePage + 1) + ' à ' + Math.min((page + 1) * taillePage, nbFiltrees) + ' sur ' + nbFiltrees"></p>
            <button type="button" @click="page = Math.max(0, page - 1); filtrer()" :disabled="page === 0">Précédent</button>
            <button type="button" @click="page = page + 1; filtrer()" :disabled="(page + 1) * taillePage >= nbFiltrees">Suivant</button>
        </div>
    </div>
    <script>
        document.addEventListener('alpine:init', function () {
            window.Alpine.data('consultation', function (urlAppareils, urlEnveloppes) {
                /* La table des versions retenues vit HORS de la réactivité d'Alpine : 18 000 fiches rendues réactives coûteraient plus cher que le déchiffrement. */
                var table = {}, index = [];
                return {
                    cle: '', coffre: '', phrase: '', message: '', recherche: '', volume: 'Mesure en cours…', visibles: [], nbFiltrees: 0, page: 0, taillePage: 50,
                    async init() {
                        try {
                            var r = await (await fetch(urlAppareils, { headers: { Accept: 'application/json' } })).json();
                            var v = r.volume;
                            this.volume = v.fiches === 0 ? 'Aucune copie reçue.' : v.fiches + ' fiche(s), ' + v.octets + ' octets chiffrés, ' + v.moyenne + ' octets en moyenne par fiche, ' + v.maximum + ' au maximum.';
                            this.appareils = r.appareils;
                        } catch (e) { this.volume = 'Mesure indisponible.'; }
                    },
                    async charger() {
                        this.message = ''; table = {}; index = []; this.visibles = []; this.nbFiltrees = 0; this.page = 0;
                        try {
                            var cle = await window.SighConsultation.importerCle(this.cle), vue = this, lu = 0;
                            for (var a of (this.appareils || [])) {
                                var depuis = 0;
                                for (;;) {
                                    var r = await (await fetch(urlEnveloppes + '?appareil=' + encodeURIComponent(a.uuid) + '&depuis_n=' + depuis + '&limite=200', { headers: { Accept: 'application/json' } })).json();
                                    await window.SighConsultation.dechiffrerParLots(r.env, cle, table);
                                    lu += r.env.length; if (r.env.length) depuis = r.env[r.env.length - 1].n;
                                    vue.message = lu + ' enveloppe(s) déchiffrée(s)…';
                                    if (r.fin) break;
                                }
                                vue.reconstruire();
                            }
                            this.message = this.nbFiltrees + ' dossier(s) lisible(s).';
                        } catch (e) { this.message = 'Déchiffrement impossible : clé incorrecte ou copie altérée.'; }
                    },
                    async ouvrirCoffre() {
                        try { this.cle = await window.SighConsultation.dechiffrerCle(JSON.parse(this.coffre), this.phrase); this.message = 'Clé retrouvée.'; }
                        catch (e) { this.message = 'Coffre ou phrase secrète incorrects.'; }
                    },
                    /* L'index de recherche (texte en minuscules) se construit UNE fois par chargement ; filtrer() ne rend que la page courante. */
                    reconstruire() {
                        index = Object.keys(table).sort().filter(function (k) { return table[k].collection === 'patients'; })
                            .map(function (k) { return { f: table[k], t: (k + ' ' + JSON.stringify(table[k].data)).toLowerCase() }; });
                        this.filtrer();
                    },
                    filtrer() {
                        var q = this.recherche.toLowerCase().trim();
                        var res = q ? index.filter(function (x) { return x.t.indexOf(q) >= 0; }) : index;
                        this.nbFiltrees = res.length;
                        this.visibles = res.slice(this.page * this.taillePage, (this.page + 1) * this.taillePage).map(function (x) { return x.f; });
                    },
                    resume(f) { return Object.keys(f.data || {}).map(function (k) { return k + ' : ' + f.data[k]; }).join(' · '); },
                };
            });
        });
    </script>
</div>
