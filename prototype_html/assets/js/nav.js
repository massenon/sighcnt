/* =============================================================================
 * SIGH-CNT — Manifeste de navigation
 * -----------------------------------------------------------------------------
 * SOURCE UNIQUE DE VÉRITÉ pour toutes les pages et tous les liens du prototype.
 * Le méga-menu horizontal, la recherche globale, le fil d'Ariane et le plan du
 * site sont générés à partir de cet objet : aucun lien n'est écrit en dur dans
 * le HTML, ce qui garantit l'absence de lien cassé (critère de recette).
 *
 * Structure : DOMAINES > MODULES (M1..M14) > ÉCRANS
 * `roles` : liste des rôles autorisés (RBAC — CDCT §12.1). '*' = tous.
 * `icon`  : icône propre à l'écran, affichée dans les colonnes du méga-menu,
 *           dans la recherche globale et sur le plan du site.
 * ========================================================================== */
(function (global) {
  'use strict';

  /* ==========================================================================
   * L’EXTENSION DES PAGES VIT ICI, ET NULLE PART AILLEURS (23/09/2026)
   * --------------------------------------------------------------------------
   * Les pages passent en `.php` : elles sont servies par Apache, ce qui met
   * l’API des données à la MÊME ORIGINE que l’interface. Leur contenu ne
   * change pas d’une ligne — ce sont toujours les dix lignes engendrées qui
   * appellent `SIGH.mount()`, et l’interface reste construite en JavaScript.
   *
   * Le manifeste étant la SOURCE UNIQUE des liens, il suffit de changer cette
   * constante : aucun href n’est écrit à la main, donc aucun n’est à reprendre.
   * ======================================================================== */
  var EXT = '.php';

  /* --- Rôles (CDCT §5 « Acteurs et rôles » + §12.1 matrice RBAC) ----------- */
  var ROLES = {
    admin: { id: 'admin', label: 'Administrateur système', short: 'Admin', color: 'navy', home: 'dash-admin' },
    direction: { id: 'direction', label: 'Direction / Gérance', short: 'Direction', color: 'navy', home: 'dash-direction' },
    dm: { id: 'dm', label: 'Directeur Médical', short: 'Dir. Médical', color: 'info', home: 'dash-direction' },
    da: { id: 'da', label: 'Directrice Administrative', short: 'Dir. Admin.', color: 'info', home: 'dash-direction' },
    medecin: { id: 'medecin', label: 'Médecin', short: 'Médecin', color: 'info', home: 'dash-medecin' },
    infirmier: { id: 'infirmier', label: 'Infirmier / Sage-femme', short: 'Infirmier', color: 'success', home: 'dash-infirmier' },
    pharmacien: { id: 'pharmacien', label: 'Pharmacien', short: 'Pharmacien', color: 'success', home: 'dash-pharmacien' },
    /* Renommé par la Direction le 26/08/2026. L'identifiant technique reste
       « laborantin » — le changer romprait toutes les listes `roles` du
       manifeste, les surcharges enregistrées et les comptes existants, pour un
       gain nul : c'est le LIBELLÉ que lisent les agents. */
    laborantin: { id: 'laborantin', label: 'Biologiste médical', short: 'Biologiste', color: 'info', home: 'dash-laborantin' },
    stock: { id: 'stock', label: 'Gestionnaire de Stock', short: 'Gest. Stock', color: 'warning', home: 'dash-stock' },
    caissier: { id: 'caissier', label: 'Caissier', short: 'Caissier', color: 'warning', home: 'dash-caissier' },
    comptable: { id: 'comptable', label: 'Comptable', short: 'Comptable', color: 'warning', home: 'dash-comptable' },
    rh: { id: 'rh', label: 'Responsable RH', short: 'RH', color: 'navy', home: 'dash-rh' },
    reception: { id: 'reception', label: 'Réception / Accueil', short: 'Accueil', color: 'success', home: 'dash-receptionniste' },
    agentadmin: { id: 'agentadmin', label: 'Agent Administratif', short: 'Agent adm.', color: 'navy', home: 'dash-admin-agent' },
    ambulancier: { id: 'ambulancier', label: 'Ambulancier', short: 'Ambulancier', color: 'danger', home: 'dash-ambulancier' },

    /* Les cinq rôles décidés par la Direction le 24/08/2026. Ils ont leurs
       écrans, leurs comptes et leur tableau de bord : leur place est ici, au
       même titre que les quinze précédents. Le mécanisme d'enregistrement
       dynamique reste réservé aux rôles inventés en cours d'exploitation. */
    aide_soignant: { id: 'aide_soignant', label: 'Aide-soignant(e)', short: 'Aide-soign.', color: 'success', home: 'dash-aide-soignant' },
    echographiste: { id: 'echographiste', label: 'Technicien d’échographie', short: 'Échographie', color: 'info', home: 'dash-echographiste' },
    surveillant: { id: 'surveillant', label: 'Surveillant', short: 'Surveillant', color: 'success', home: 'dash-surveillant' },
    assistant_comptable: { id: 'assistant_comptable', label: 'Assistant de Direction', short: 'Assist. Dir.', color: 'warning', home: 'dash-assistant-comptable' },

    /* Les trois rôles de la PHASE 2, décidés le 31/08/2026 : les deux
       praticiens que la matrice cible des Instructions distingue du médecin,
       et le 16ᵉ rôle créé par arbitrage — l'Assistant Comptable, DISTINCT de
       l'Assistant de Direction ci-dessus. L'identifiant technique
       `aide_comptable` évite la collision avec `assistant_comptable`
       (conservé tel quel : renommer un identifiant technique romprait listes,
       surcharges et comptes — doctrine posée pour « laborantin »). */
    chirurgien: { id: 'chirurgien', label: 'Chirurgien', short: 'Chirurgien', color: 'danger', home: 'dash-chirurgien' },
    anesthesiste: { id: 'anesthesiste', label: 'Anesthésiste — Réanimateur', short: 'Anesthésiste', color: 'info', home: 'dash-anesthesiste' },
    aide_comptable: { id: 'aide_comptable', label: 'Assistant Comptable', short: 'Assist. Compta', color: 'warning', home: 'dash-aide-comptable' },
    /* LE POSTE N'EXISTE PAS. Le rôle avait été créé le 24/08/2026 sur une
       lecture erronée de la liste des comptes : KINNOU A. Ganiou est
       BIOLOGISTE MÉDICAL, ce que la Direction a rectifié depuis. Le rôle est
       conservé au référentiel — un rôle s'archive, il ne se supprime pas
       (RG-14), et des fiches de maintenance portent sa signature — mais il est
       ARCHIVÉ : il n'ouvre plus de session et disparaît des écrans.
       Le parc technique, lui, reste : c'est un besoin réel, tenu par
       l'administration. */
  };

  var ALL = '*';

  /* --- Arborescence des écrans -------------------------------------------- */
  var NAV = [
    /* ====================================================================
     * ACCUEIL — le domaine dédié de la cible (Instructions, phase 3)
     * --------------------------------------------------------------------
     * La plaque tournante administrative : rendez-vous, file, écran d'appel,
     * courriers, orientation, tarifs publics, constantes. TOUT y est ALIAS :
     * chaque écran garde sa rangée canonique (M1, M2, M13, CFG), sa page et
     * ses droits — l'ACCUEIL ne fait que les réunir là où l'agent d'accueil
     * commence sa journée.
     * ================================================================== */
    {
      domain: 'Accueil',
      icon: 'door-open',
      modules: [
        {
          /* Décision du 02/09/2026 : le bloc « RDV, Visites & Consultations »
             est DÉPLACÉ — pas dupliqué — de SOINS vers ACCUEIL : la rangée
             CANONIQUE vit ici, et SOINS n'en garde ni rangée ni alias. Le
             domaine de rattachement (fil d'Ariane, onglet courant, hub) suit
             la rangée canonique. */
          /* RANGÉE CANONIQUE DE M2 — resserrée le 06/09/2026 sur le travail
             de l'ACCUEIL : recevoir, orienter, appeler. Ce qui relève du
             GESTE CLINIQUE (fiche, pathologies, ordonnances, prescriptions,
             salle de soins) et de l'IMAGERIE vit dans le domaine SOINS, en
             rangées `secondaire` — même module, même droits, autre rangée.
             Le registre des visites a FUSIONNÉ dans « Rendez-vous & visites ». */
          code: 'M2', label: 'RDV, Visites & Consultations', icon: 'calendar-days',
          roles: ['reception', 'medecin', 'infirmier', 'dm', 'admin', 'direction'],
          items: [
            { id: 'm2-agenda', label: 'Agenda', icon: 'calendar-days' },
            { id: 'm2-rendezvous', label: 'Rendez-vous & visites', icon: 'calendar-check' },
            { id: 'm2-file-attente', label: 'File d’attente', icon: 'list-ordered' },
            { id: 'm2-file-cabinet', label: 'File par cabinet', icon: 'door-open' },
            { id: 'm2-agenda-medecin', label: 'Agenda du médecin', icon: 'calendar-check-2',
              roles: ['medecin', 'chirurgien', 'dm', 'admin', 'direction', 'reception'] },
            { id: 'm2-affichage', label: 'Écran d’appel des patients', icon: 'monitor' },
            { id: 'm2-domicile', label: 'Consultations & soins à domicile', icon: 'house' },
            { id: 'm2-registre-appels', label: 'Registre des appels', icon: 'phone-call' },
            { id: 'm2-consultations', label: 'Consultations', icon: 'stethoscope' },
          ],
        },
        {
          code: 'M1', label: 'Patients & constantes', icon: 'users', alias: true,
          items: [
            { id: 'm1-patients', label: 'Répertoire des patients', icon: 'users', alias: true },
            { id: 'm1-constantes', label: 'Constantes à l’accueil', icon: 'activity', alias: true },
            { id: 'm1-externe', label: 'Patient externe', icon: 'user-plus', alias: true },
          ],
        },
        {
          code: 'M13', label: 'Courriers & orientation', icon: 'mail', alias: true,
          items: [
            { id: 'm13-courriers', label: 'Courriers (départ / arrivée)', icon: 'mail', alias: true },
            /* Le même écran, le même libellé qu'à sa rangée canonique : un
               alias qui se nomme autrement fait croire à deux écrans. */
            { id: 'm13-repertoire-ambulances', label: 'Répertoire des ambulances', icon: 'ambulance', alias: true },
            /* « Validations en attente » a QUITTÉ cette rangée le 06/09/2026 :
               l'accueil oriente des patients, il n'arbitre pas les files de
               validation des autres postes. L'écran reste en M13. */
          ],
        },
        {
          code: 'CFG', label: 'Tarification & information patient', icon: 'tags', alias: true,
          items: [
            { id: 'cfg-tarifs', label: 'Référentiel tarifaire public', icon: 'tags', alias: true },
            { id: 'cfg-catalogue', label: 'Catalogue des prestations', icon: 'book-open', alias: true },
            { id: 'cfg-certificats', label: 'Tarifs des certificats & attestations', icon: 'file-badge', alias: true },
          ],
        },
      ],
    },
    {
      domain: 'Soins',
      icon: 'stethoscope',
      modules: [
        {
          code: 'M1', label: 'Patients & Dossier médical', icon: 'users', roles: ALL,
          items: [
            { id: 'm1-patients', label: 'Répertoire des patients', icon: 'users' },
            { id: 'm1-patient-profil', label: 'Fiche patient', icon: 'user-round' },
            /* LE MÉDECIN ET LA SAGE-FEMME Y ENTRENT (cible du 10/10/2026).
               Ils reçoivent des patients adressés de l'extérieur et ne
               pouvaient pas leur ouvrir de dossier : il fallait passer par
               l'accueil, puis revenir. Ce qui reste fermé, et doit le rester,
               c'est LA CAISSE — lui donner ce pouvoir ouvrirait une recette
               sans acte à l'origine. */
            { id: 'm1-externe', label: 'Patient externe', icon: 'user-plus',
              roles: ['reception', 'admin', 'direction', 'da', 'laborantin',
                'medecin', 'infirmier'] },
            /* Dossier médical et dossier étendu : FUSIONNÉS dans le répertoire
               (Bug 1, arbitrage du 31/08/2026). Leurs pages subsistent hors
               ruban (STANDALONE) et renvoient — retirer une entrée du
               manifeste n'est jamais la bonne façon de fermer un écran. */
            { id: 'm1-antecedents', label: 'Antécédents & allergies', icon: 'shield-alert' },
            /* « Certificats — externes » a FUSIONNÉ ici (22/09/2026) : le
               registre porte les pièces des patients de la clinique ET des
               patients adressés de l'extérieur, en quatre onglets. Deux
               registres sur la même collection finissaient toujours par ne
               pas dire la même chose. La page subsiste hors ruban et
               renvoie — retirer une entrée du manifeste casserait tout lien
               qui la vise. */
            { id: 'm1-pieces', label: 'Certificats & attestations', icon: 'stamp' },
            { id: 'm1-constantes', label: 'Constantes à l’accueil', icon: 'thermometer' },
            { id: 'm1-reference', label: 'Fiches de référence', icon: 'share-2' },
            { id: 'm1-contre-reference', label: 'Fiches de contre-référence', icon: 'reply' },
            { id: 'm1-documents', label: 'Documents numérisés', icon: 'paperclip' },
            { id: 'm1-numerisation', label: 'Plan de numérisation', icon: 'scan-line' },
          ],
        },
        /* --------------------------------------------------------------------
         * DEUX RANGÉES SECONDAIRES DE M2 (06/09/2026)
         * --------------------------------------------------------------------
         * La rangée CANONIQUE de M2 vit dans ACCUEIL (déplacement du
         * 02/09/2026) et porte le travail de réception. Le GESTE CLINIQUE et
         * l'IMAGERIE n'y avaient rien à faire : on ne cherche pas une
         * ordonnance ni un compte rendu d'échographie dans le menu de
         * l'accueil.
         *
         * `secondaire: true` : la rangée paraît au ruban et ses écrans y sont
         * CANONIQUES (une page, un fil d'Ariane, une entrée d'index), mais
         * elle ne crée pas de second hub et ne redéfinit pas le module. Un
         * ALIAS aurait affiché les mêmes écrans DEUX fois ; un module nouveau
         * aurait fallu réécrire dix fiches RBAC pour un simple regroupement
         * visuel. Le module reste M2 : mêmes droits, exactement.
         * ------------------------------------------------------------------ */
        {
          code: 'M2', label: 'Consultations & prescriptions', icon: 'stethoscope', secondaire: true,
          roles: ['reception', 'medecin', 'infirmier', 'dm', 'admin', 'direction'],
          items: [
            /* REFONTE ZONE 2 (14/09/2026) — le DOSSIER précède la FICHE : le
               médecin consigne l'anamnèse et l'examen IPPOA au dossier, la
               fiche en fait le récapitulatif et porte SEULE la prescription.
               L'ordre des pastilles est celui du geste. */
            { id: 'm2-dossiers-consultation', label: 'Dossiers de consultation', icon: 'folder-heart' },
            { id: 'm2-consultation-fiche', label: 'Fiche de consultation', icon: 'clipboard-list' },
            { id: 'm2-pathologies', label: 'Pathologies & morbidité', icon: 'activity' },
            { id: 'm2-ordonnances', label: 'Ordonnances', icon: 'scroll-text' },
            { id: 'm2-prescriptions', label: 'Prescriptions', icon: 'clipboard-plus' },
            { id: 'm2-salle-soins', label: 'Salle de soins', icon: 'syringe' },
          ],
        },
        {
          /* IMAGERIE MÉDICALE — et non « échographie » : la clinique fait
             aussi de l'ECG et des radiographies au catalogue. L'écran de
             saisie s'appelle « Tableau Échographie » parce que c'est le
             tableau que l'échographiste remplit ; le domaine, lui, est
             l'imagerie médicale. L'échographiste y accède par ses surcharges
             d'écran — le module M2 ne le liste pas. */
          code: 'M2', label: 'Imagerie médicale', icon: 'scan-line', secondaire: true,
          roles: ['reception', 'medecin', 'infirmier', 'dm', 'admin', 'direction'],
          items: [
            { id: 'm2-dashboard-imagerie', label: 'Poste d’imagerie médicale', icon: 'gauge' },
            { id: 'm2-imagerie-demandes', label: 'Demandes d’imagerie médicale', icon: 'scan-search' },
            { id: 'm2-imagerie', label: 'Tableau Échographie', icon: 'scan-line' },
            /* Vague 61 — quatre modalités branchées sur le même socle : même
               demande, même caisse, même compte rendu par variables. Des
               écrans d'une fabrique, pas des modules : les droits de M2
               s'appliquent tels quels. */
            { id: 'm2-imagerie-radiographie', label: 'Tableau Radiographie', icon: 'bone' },
            { id: 'm2-imagerie-mammographie', label: 'Tableau Mammographie', icon: 'ribbon' },
            { id: 'm2-imagerie-scanner', label: 'Tableau Scanner', icon: 'radiation' },
            { id: 'm2-imagerie-irm', label: 'Tableau IRM', icon: 'magnet' },
            { id: 'm2-echographie-galerie', label: 'Galerie des clichés', icon: 'images' },
          ],
        },
        {
          code: 'M3', label: 'Hospitalisation', icon: 'bed-double',
          roles: ['medecin', 'infirmier', 'dm', 'admin', 'direction', 'reception'],
          items: [
            { id: 'm3-admissions', label: 'Admissions', icon: 'log-in' },
            { id: 'm3-observation', label: 'Mise en observation', icon: 'activity' },
            { id: 'm3-plan-lits', label: 'Plan des lits', icon: 'layout-grid' },
            { id: 'm3-chambres', label: 'Chambres & lits', icon: 'bed-double' },
            { id: 'm3-feuille-temperature', label: 'Feuille de température', icon: 'thermometer' },
            { id: 'm3-soins', label: 'Feuille de soins', icon: 'heart-pulse' },
            { id: 'm3-administrations', label: 'Administration des traitements', icon: 'pill' },
            /* Phase 7 — l'anesthésie et les demandes du service. La CPA et le
               CR d'anesthésie sont les pièces du rôle anesthésiste (créé en
               phase 2) ; sa fiche RBAC lui accorde M3 en écriture. */
            { id: 'm3-cpa', label: 'Consultation pré-anesthésique', icon: 'stethoscope' },
            { id: 'm3-bloc-cro', label: 'Comptes rendus opératoires', icon: 'scissors' },
            { id: 'm3-cr-anesthesie', label: 'Comptes rendus d’anesthésie', icon: 'syringe' },
            { id: 'm3-bloc-checklist', label: 'Check-listes du bloc', icon: 'list-checks' },
            { id: 'm3-demande-examen', label: 'Demande d’examen', icon: 'clipboard-list' },
            { id: 'm3-bons-pansements', label: 'Bons de pansement', icon: 'bandage' },
            { id: 'm3-surveillance', label: 'Fiche de surveillance', icon: 'activity' },
            { id: 'm3-transfusion', label: 'Surveillance transfusionnelle', icon: 'droplets' },
            { id: 'm3-glasgow', label: 'Score de Glasgow', icon: 'brain' },
            { id: 'm3-rapport', label: 'Rapport médical', icon: 'file-text' },
            { id: 'm3-visites-patients', label: 'Visites aux hospitalisés', icon: 'users-round' },
            { id: 'm3-sorties', label: 'Sorties d’hospitalisation', icon: 'log-out' },
            { id: 'm3-sortie-avis-medical', label: 'Sortie contre avis médical', icon: 'triangle-alert' },
          ],
        },
        {
          code: 'M4', label: 'Maternité, Naissances & Décès', icon: 'baby',
          roles: ['medecin', 'infirmier', 'dm', 'admin', 'direction'],
          items: [
            /* LE DOSSIER OUVRE LA RANGÉE parce qu'il ouvre le suivi : c'est la
               pièce qu'on crée à la première CPN et qui tient toutes les
               autres — CPN, partogramme, accouchement, nouveau-né, CPoN. */
            { id: 'm4-dossier-obstetrical', label: 'Dossier obstétrical', icon: 'folder-open' },
            { id: 'm4-maternite', label: 'Suivi maternité', icon: 'baby' },
            /* Les sept écrans du rapport officiel du 27/08/2026 (phase 4). */
            { id: 'm4-cpn', label: 'CPN & carte maternelle', icon: 'clipboard-list' },
            { id: 'm4-partogramme', label: 'Partogramme', icon: 'activity' },
            { id: 'm4-accouchements', label: 'Accouchements', icon: 'heart-handshake' },
            { id: 'm4-dossier-bebe', label: 'Dossier bébé & soins du nouveau-né', icon: 'baby' },
            { id: 'm4-cpon', label: 'Consultations post-natales (CPoN)', icon: 'stethoscope' },
            { id: 'm4-planification', label: 'Planification familiale', icon: 'heart-handshake' },
            { id: 'm4-sonu', label: 'Registre SONUB / SONUC', icon: 'siren' },
            { id: 'm4-ptme', label: 'Registre PTME', icon: 'shield-check' },
            { id: 'm4-soins-curatifs', label: 'Soins curatifs & urgences maternité', icon: 'cross' },
            { id: 'm4-comptes-rendus', label: 'Comptes rendus de maternité', icon: 'file-text' },
            { id: 'm4-naissances', label: 'Registre des naissances', icon: 'book-marked' },
            { id: 'm4-deces', label: 'Registre des décès', icon: 'cross' },
          ],
        },
        {
          /* La clinique ne pratique PAS la banque de sang : garder son nom
             dans l'intitulé du module annonce une activité inexistante au seul
             endroit que tout le monde lit — le ruban. Les deux écrans restent
             au manifeste, fermés par `modulesActifs` : rouvrir l'activité
             rendrait le module en l'état, intitulé compris. */
          code: 'M5', label: 'Laboratoire', icon: 'flask-conical',
          roles: ['laborantin', 'medecin', 'dm', 'admin', 'direction'],
          items: [
            /* Ouverts aussi aux soignants : la sage-femme doit atteindre les
               résultats de son secteur. Ce qu'elle y voit est décidé par le
               filtre de données, pas par l'accès à l'écran. */
            { id: 'm5-demandes', label: 'Demandes d’analyses', icon: 'clipboard-list', roles: ['laborantin', 'medecin', 'dm', 'admin', 'direction', 'infirmier'] },
            /* Vues par service (phase 6) : une lecture du MÊME registre, pas
               une seconde collection — la sage-femme suit ses bilans,
               l'hospitalisation ses lits. */
            { id: 'm5-demandes-maternite', label: 'Demandes — maternité', icon: 'baby', roles: ['laborantin', 'medecin', 'dm', 'admin', 'direction', 'infirmier'] },
            { id: 'm5-demandes-hospitalisation', label: 'Demandes — hospitalisation', icon: 'bed', roles: ['laborantin', 'medecin', 'dm', 'admin', 'direction', 'infirmier'] },
            { id: 'm5-resultats', label: 'Saisie des résultats', icon: 'file-check-2', roles: ['laborantin', 'medecin', 'dm', 'admin', 'direction', 'infirmier'] },
            { id: 'm5-resultats-comparatif', label: 'Comparatif des résultats', icon: 'git-compare-arrows', roles: ['laborantin', 'medecin', 'dm', 'admin', 'direction', 'infirmier'] },
            { id: 'm5-impression-resultats', label: 'Impression des résultats', icon: 'printer', roles: ['laborantin', 'medecin', 'dm', 'admin', 'direction'] },
            { id: 'm5-catalogue', label: 'Catalogue des analyses', icon: 'list-checks' },
            { id: 'm5-unites', label: 'Unités de mesure', icon: 'ruler' },
            { id: 'm5-valeurs-reference', label: 'Valeurs de référence', icon: 'target' },
            { id: 'm5-prelevement', label: 'Salle de prélèvement', icon: 'syringe', roles: ['laborantin', 'infirmier', 'admin', 'direction', 'dm'] },
            { id: 'm5-stats', label: 'Statistiques du laboratoire', icon: 'chart-column' },
            { id: 'm5-reactifs', label: 'Réactifs & consommables', icon: 'test-tubes' },
            { id: 'm5-reactifs-stats', label: 'Statistiques des réactifs', icon: 'chart-column' },
            { id: 'm5-banque-sang', label: 'Banque de sang', icon: 'droplet' },
            { id: 'm5-donneurs', label: 'Donneurs & transfusions', icon: 'droplets' },
          ],
        },
      ],
    },
    {
      domain: 'Logistique',
      icon: 'package',
      modules: [
        {
          code: 'M6', label: 'Pharmacie & Stocks', icon: 'pill',
          roles: ['pharmacien', 'stock', 'da', 'comptable', 'medecin', 'admin', 'direction'],
          items: [
            { id: 'm6-pharmacie-interne', label: 'Pharmacie interne — urgences', icon: 'syringe' },
            { id: 'm6-pharmacie-externe', label: 'Pharmacie externe — voie orale', icon: 'store' },
            { id: 'm6-dashboard', label: 'Tableau de bord stock', icon: 'gauge' },
            { id: 'm6-produits', label: 'Référentiel produits', icon: 'pill' },
            { id: 'm6-stock-gros', label: 'Stock gros (magasin)', icon: 'warehouse' },
            { id: 'm6-stock-detail', label: 'Stock détail (pharmacie)', icon: 'store' },
            { id: 'm6-transferts', label: 'Transferts gros → détail', icon: 'arrow-left-right' },
            { id: 'm6-mouvements', label: 'Mouvements de stock', icon: 'arrow-down-up' },
            { id: 'm6-lots', label: 'Lots & péremptions (FEFO)', icon: 'calendar-clock' },
            { id: 'm6-alertes', label: 'Alertes & seuils', icon: 'bell-ring' },
            { id: 'm6-inventaire', label: 'Inventaires', icon: 'clipboard-check' },
            { id: 'm6-pertes', label: 'Pertes, casses & rebuts', icon: 'trash-2' },
            { id: 'm6-dispensation', label: 'Dispensation', icon: 'package-open' },
            { id: 'm6-etiquetage', label: 'Étiquetage & emplacements', icon: 'tags' },
            { id: 'm6-reprise', label: 'Reprise SAGE 100', icon: 'database' },
            /* Les points du gestionnaire de stock. Ouverts aussi à la caisse,
               à la comptabilité et à la Direction : ce sont les mêmes chiffres
               que chacun recompose aujourd'hui à la main de son côté. */
            { id: 'm6-point-ventes', label: 'Suivi des ventes', icon: 'coins',
              roles: ['stock', 'da', 'comptable', 'dm', 'caissier', 'admin', 'direction', 'assistant_comptable'] },
            { id: 'm6-point-stock', label: 'Point du stock valorisé', icon: 'warehouse',
              roles: ['stock', 'da', 'comptable', 'dm', 'pharmacien', 'admin', 'direction', 'assistant_comptable'] },
          ],
        },
        {
          code: 'M7', label: 'Achats & Fournisseurs', icon: 'truck',
          roles: ['stock', 'da', 'comptable', 'admin', 'direction'],
          items: [
            /* EXPRIMER UN BESOIN APPARTIENT À TOUT AGENT (NEINSTRUCTION2) :
               le médecin sans papier, la sage-femme sans gants, la réception
               dont l’imprimante est vide. L’écran reste en M7 — c’est là que
               le besoin devient commande — mais il s’ouvre à tous les postes,
               chacun sur SA vue. */
            { id: 'm7-besoins', label: 'Bons d’expression de besoins', icon: 'clipboard-list',
              universel: true },
            { id: 'm7-commandes', label: 'Bons de commande', icon: 'shopping-cart', roles: ['stock', 'da', 'admin', 'direction', 'comptable', 'laborantin'] },
            { id: 'm7-livraisons', label: 'Bons de livraison', icon: 'truck', roles: ['stock', 'da', 'admin', 'direction', 'comptable', 'laborantin'] },
            { id: 'm7-receptions', label: 'Réceptions & contrôles', icon: 'package-check', roles: ['stock', 'da', 'admin', 'direction', 'comptable', 'laborantin'] },
            { id: 'm7-ecarts', label: 'Écarts de livraison', icon: 'triangle-alert', roles: ['stock', 'da', 'admin', 'direction', 'comptable', 'laborantin'] },
            /* Les deux PV de la cible (phase 5) — l'assistant comptable y
               accède par sa fiche RBAC (M7 en écriture), sans figurer ici. */
            { id: 'm7-pv-reception-consommables', label: 'PV de réception — consommables', icon: 'clipboard-check',
              roles: ['stock', 'da', 'admin', 'direction', 'comptable'] },
            { id: 'm7-pv-reception-reactifs', label: 'PV de réception — réactifs', icon: 'flask-conical',
              roles: ['stock', 'da', 'admin', 'direction', 'comptable', 'laborantin'] },
            { id: 'm7-fournisseurs', label: 'Fournisseurs', icon: 'building-2' },
            { id: 'm7-factures-fournisseurs', label: 'Factures fournisseurs', icon: 'file-text' },
          ],
        },
      ],
    },
    {
      domain: 'Financier',
      icon: 'wallet',
      modules: [
        {
          code: 'M8', label: 'Facturation & Caisse', icon: 'receipt',
          /* Décision de la Direction (26/08/2026) : le DA, le comptable, le
             gestionnaire de stock ET LE DIRECTEUR MÉDICAL ont accès à la
             caisse. Les trois premiers l'avaient déjà ; lui seul manquait. */
          roles: ['caissier', 'comptable', 'da', 'stock', 'dm', 'admin', 'direction'],
          items: [
            { id: 'm8-dashboard', label: 'Tableau de bord facturation', icon: 'gauge' },
            { id: 'm8-facturation', label: 'Nouvelle facture', icon: 'file-plus-2' },
            { id: 'm8-factures', label: 'Factures', icon: 'receipt' },
            { id: 'm8-proforma', label: 'Factures pro-forma', icon: 'file-text' },
            { id: 'm8-paiements', label: 'Paiements', icon: 'banknote' },
            { id: 'm8-reliquats', label: 'Reliquats', icon: 'coins' },
            { id: 'm8-remboursements', label: 'Remboursements & annulations', icon: 'undo-2' },
            /* Phase 5 — le canal de correction d'une pièce émise. Le caissier
               le CONSULTE (surcharge d'écran) ; l'émission est au Comptable
               et à la DAF. */
            { id: 'm8-facture-avoir', label: 'Factures d’avoir', icon: 'file-minus-2' },
            { id: 'm8-caisse', label: 'État de caisse journalier', icon: 'calculator' },
            { id: 'm8-operations', label: 'Opérations de caisse', icon: 'scroll-text' },
            { id: 'm8-recettes', label: 'Recettes par période', icon: 'trending-up' },
          ],
        },
        {
          code: 'M9', label: 'Assurances & Créances', icon: 'shield-check',
          roles: ['caissier', 'comptable', 'da', 'admin', 'direction'],
          items: [
            { id: 'm9-dashboard', label: 'Tableau de bord assurances', icon: 'gauge' },
            { id: 'm9-compagnies', label: 'Compagnies partenaires', icon: 'building-2' },
            { id: 'm9-assures', label: 'Assurés & cartes', icon: 'id-card' },
            { id: 'm9-conventions', label: 'Conventions & garanties', icon: 'file-signature' },
            { id: 'm9-prises-en-charge', label: 'Prises en charge', icon: 'shield-check' },
            { id: 'm9-factures-assureur', label: 'Factures mensuelles assureur', icon: 'files' },
            { id: 'm9-facture-mere', label: 'Facture mère assurance', icon: 'layers' },
            { id: 'm9-historique', label: 'Historique par assureur', icon: 'history' },
            { id: 'm9-creances', label: 'Créances', icon: 'hourglass' },
            { id: 'm9-relances', label: 'Relances', icon: 'send' },
          ],
        },
        {
          code: 'MECEF', label: 'MECeF — Facture normalisée', icon: 'file-badge',
          roles: ['caissier', 'comptable', 'da', 'admin', 'direction'],
          items: [
            { id: 'mecef-dashboard', label: 'Tableau de bord fiscal', icon: 'gauge' },
            { id: 'mecef-factures', label: 'Factures normalisées', icon: 'file-badge' },
            { id: 'mecef-transmission', label: 'Transmission & réponses', icon: 'signal' },
            { id: 'mecef-avoirs', label: 'Avoirs & annulations', icon: 'file-minus-2' },
            { id: 'mecef-journal', label: 'Journal des transactions', icon: 'scroll-text' },
            { id: 'mecef-config', label: 'Configuration fiscale', icon: 'settings-2' },
          ],
        },
        {
          code: 'M12', label: 'Comptabilité SYSCOHADA', icon: 'book-open-check',
          roles: ['comptable', 'da', 'admin', 'direction'],
          items: [
            { id: 'm12-dashboard', label: 'Tableau de bord comptable', icon: 'gauge' },
            { id: 'm12-plan-comptable', label: 'Plan comptable OHADA', icon: 'list-tree' },
            { id: 'm12-journaux', label: 'Journaux comptables', icon: 'book-open-text' },
            { id: 'm12-ecritures', label: 'Écritures comptables', icon: 'pencil-line' },
            /* La saisie des dépenses est ouverte à la caisse et à la DAF, pas
               seulement au comptable : c'est au fil de la journée qu'une
               dépense se constate, et attendre le comptable ferait ressaisir
               de mémoire en fin de mois. L'écriture qu'elle produit naît en
               BROUILLON — la validation reste comptable. */
            { id: 'm12-depenses', label: 'Dépenses journalières', icon: 'receipt-text',
              roles: ['comptable', 'da', 'caissier', 'assistant_comptable', 'admin', 'direction'] },
            { id: 'm12-grand-livre', label: 'Grand livre', icon: 'book-open-check' },
            { id: 'm12-balance', label: 'Balance générale & âgée', icon: 'scale' },
            { id: 'm12-analytique', label: 'Comptabilité analytique', icon: 'pie-chart' },
            { id: 'm12-budgets', label: 'Budgets', icon: 'target' },
            { id: 'm12-immobilisations', label: 'Immobilisations & amortissements', icon: 'building' },
            { id: 'm12-banques', label: 'Banques & rapprochements', icon: 'landmark' },
            { id: 'm12-compte-resultat', label: 'Compte de résultat', icon: 'chart-no-axes-combined' },
            /* Vague 61 — le tableau des flux au format du feuillet 8/51 de la
               liasse déposée, déposé OU calculé depuis le journal. */
            { id: 'm12-flux-tresorerie', label: 'Tableau des flux de trésorerie', icon: 'arrow-left-right' },
            { id: 'm12-seuil-rentabilite', label: 'Seuil de rentabilité', icon: 'target' },
            { id: 'm12-etats-financiers', label: 'États financiers', icon: 'file-spreadsheet' },
            { id: 'm12-baseline-2025', label: 'Baseline 2025', icon: 'history' },
            { id: 'm12-echeances', label: 'Échéances fiscales & paiements', icon: 'calendar-clock' },
            { id: 'm12-cloture', label: 'Exercices & clôtures', icon: 'lock' },
            /* LE BILAN D'OUVERTURE : sans à-nouveaux, un exercice s'ouvrait
               sur un journal vide et il fallait relire tout l'historique pour
               connaître la situation au 1ᵉʳ janvier. */
            { id: 'm12-ouverture', label: 'Bilan d’ouverture & à-nouveaux', icon: 'calendar-plus' },
          ],
        },
      ],
    },
    {
      domain: 'RH',
      icon: 'users-round',
      modules: [
        {
          code: 'M10', label: 'Ressources humaines', icon: 'id-card',
          roles: ['rh', 'da', 'admin', 'direction'],
          items: [
            { id: 'm10-fiches-poste', label: 'Fiches de poste', icon: 'file-badge' },
            { id: 'm10-dashboard', label: 'Tableau de bord RH', icon: 'gauge' },
            { id: 'm10-personnel', label: 'Personnel', icon: 'users' },
            { id: 'm10-employe-profil', label: 'Fiche employé', icon: 'id-card' },
            { id: 'm10-contrats', label: 'Contrats', icon: 'file-signature' },
            /* BADGES DU PERSONNEL — le badge est une PIÈCE IMPRIMÉE rattachée
               à un agent : sa place est en M10, où vivent déjà l'agent, sa
               fonction et son service. Un module séparé aurait créé une
               seconde vérité sur l'identité du personnel.
               Le registre et la vérification sont ouverts au SURVEILLANT (il
               contrôle à l'entrée) ; sa fiche RBAC les lui donne en LECTURE.
               L'Assistant de Direction, lui, n'a pas M10 au module : c'est sa
               fiche RBAC qui les lui ACCORDE nommément — l'ajouter ici
               n'aurait aucun effet et ferait croire l'inverse. */
            { id: 'm10-badges', label: 'Badges du personnel', icon: 'id-card',
              roles: ['rh', 'da', 'admin', 'direction', 'surveillant'] },
            { id: 'm10-badges-verification', label: 'Vérifier un badge', icon: 'scan-face',
              roles: ['rh', 'da', 'admin', 'direction', 'surveillant'] },
            { id: 'm10-badges-modeles', label: 'Modèles de badge', icon: 'layout-template' },
            { id: 'm10-badges-impression', label: 'Planche d’impression des badges', icon: 'printer' },
            { id: 'm10-planning', label: 'Planning & gardes', icon: 'calendar-days' },
            { id: 'm10-stats-gardes', label: 'Statistiques de garde', icon: 'chart-column' },
            { id: 'm10-stats-permanences', label: 'Statistiques des permanences', icon: 'clock-9' },
            { id: 'm10-stats-presence', label: 'Taux de présence par service', icon: 'user-check' },
            { id: 'm10-presences', label: 'Présences & absences', icon: 'user-check' },
            { id: 'm10-conges', label: 'Congés', icon: 'plane' },
            { id: 'm10-missions', label: 'Ordres de mission', icon: 'briefcase' },
            { id: 'm10-evaluations', label: 'Évaluations (NS 131)', icon: 'clipboard-check' },
            { id: 'm10-sanctions', label: 'Sanctions', icon: 'gavel' },
            { id: 'm10-primes', label: 'Primes (NS 132)', icon: 'gift' },
            { id: 'm10-evenements', label: 'Événements du personnel', icon: 'calendar-heart' },
            { id: 'm10-participations', label: 'Frais de participation', icon: 'hand-coins' },
            { id: 'm10-assurance-personnel', label: 'Assurance du personnel', icon: 'shield-check' },
            { id: 'm10-prestataires', label: 'Prestataires externes', icon: 'handshake' },
            { id: 'm10-securite-entretien', label: 'Sécurité & entretien', icon: 'shield' },
          ],
        },
        {
          code: 'M11', label: 'Paie & Primes', icon: 'banknote',
          roles: ['rh', 'da', 'comptable', 'admin', 'direction'],
          items: [
            { id: 'm11-prets-etudes', label: 'Prêts-études et avances', icon: 'graduation-cap' },
            { id: 'm11-dashboard', label: 'Tableau de bord paie', icon: 'gauge' },
            { id: 'm11-calcul', label: 'Calcul de la paie', icon: 'calculator' },
            { id: 'm11-bulletins', label: 'Bulletins de paie', icon: 'file-text' },
            { id: 'm11-cotisations', label: 'Cotisations CNSS / ITS / VPS', icon: 'percent' },
            { id: 'm11-heures-sup', label: 'Heures supplémentaires', icon: 'clock' },
            { id: 'm11-avances', label: 'Avances sur salaire', icon: 'hand-coins' },
            { id: 'm11-ortb', label: 'Redevance ORTB', icon: 'radio' },
            { id: 'm11-validation', label: 'Validation Direction', icon: 'badge-check' },
          ],
        },
      ],
    },
    {
      domain: 'Administration',
      icon: 'building-2',
      modules: [
        {
          code: 'M13', label: 'Administration & Ambulance', icon: 'mail',
          /* L'ASSISTANT DE DIRECTION Y ENTRE (cible du 10/10/2026) : courriers,
             réunions, plan annuel, notes de service et ambulance SONT son
             métier, et il n'en voyait aucun. */
          roles: ['agentadmin', 'da', 'admin', 'direction', 'ambulancier',
            'assistant_comptable'],
          items: [
            { id: 'm13-courriers', label: 'Courriers (départ / arrivée)', icon: 'mail' },
            { id: 'm13-reunions', label: 'Réunions', icon: 'users-round' },
            { id: 'm13-evenements', label: 'Événements & notifications', icon: 'calendar-clock' },
            { id: 'm13-plan-annuel', label: 'Plan annuel de travail', icon: 'calendar-range' },
            { id: 'm13-notes-service', label: 'Notes de service', icon: 'megaphone' },
            { id: 'm13-ambulance', label: 'Interventions ambulance', icon: 'ambulance' },
            { id: 'm13-repertoire-ambulances', label: 'Répertoire des ambulances', icon: 'phone-call',
              roles: ['reception', 'ambulancier', 'admin', 'direction', 'da', 'dm', 'infirmier', 'surveillant'] },
            /* Le parc technique n'avait pas d'écran : le tableau de bord de
               l'ingénieur biomédical comptait les pannes d'une collection que
               rien n'alimentait et renvoyait vers une adresse inexistante.
               Ouvert au biomédical et au laboratoire — c'est le laboratoire
               qui constate qu'un automate ne répond plus. */
            { id: 'm13-maintenance', label: 'Parc technique & maintenance', icon: 'wrench',
              roles: ['admin', 'direction', 'da', 'laborantin', 'agentadmin'] },
            /* Phase 10 — le questionnaire est une donnée : le formulaire naît
               du modèle (principe KoboCollect, hors ligne). L'accueil
               recueille, la direction lit. */
            { id: 'adm-validations', label: 'Validations en attente', icon: 'list-checks',
              roles: ['da', 'admin', 'direction', 'dm', 'comptable', 'surveillant', 'agentadmin'] },
            { id: 'adm-enquetes', label: 'Enquêtes & questionnaires', icon: 'clipboard-list',
              roles: ['agentadmin', 'da', 'admin', 'direction', 'reception'] },
            { id: 'adm-satisfaction', label: 'Satisfaction des patients', icon: 'thumbs-up',
              roles: ['agentadmin', 'da', 'admin', 'direction', 'dm'] },
          ],
        },
        {
          code: 'GED', label: 'Gestion documentaire', icon: 'folder-open',
          roles: ['agentadmin', 'da', 'admin', 'direction', 'comptable',
            'assistant_comptable'],
          items: [
            { id: 'ged-bibliotheque', label: 'Bibliothèque documentaire', icon: 'folder-open' },
            { id: 'ged-workflow', label: 'Workflow de validation', icon: 'git-branch' },
            { id: 'ged-archives', label: 'Archivage & conservation', icon: 'archive' },
          ],
        },
        {
          /* ==================================================================
           * IMPRIMER EST L'AFFAIRE DE TOUS, PAS « LES ÉTATS DE LA DIRECTION »
           * ------------------------------------------------------------------
           * Le module porte `roles: ALL` — et c'est juste pour la bibliothèque
           * des états : le CDCT fait de l'impression une exigence de chaque
           * poste. Mais comme ce sont les listes de CHAQUE écran qui filtrent
           * et qu'aucune n'était posée, tout le monde héritait du module : un
           * médecin, un caissier, la réception pouvaient ÉCRIRE ET ANNULER
           * dans « États de la Direction » et dans le générateur de rapports.
           *
           * L'inventaire le montrait sur dix-sept rôles, et NEINSTRUCTION du
           * 24/09/2026 le nomme : « Administration — Interdit » pour les
           * postes cliniques et de caisse. On ferme donc les trois écrans qui
           * PRODUISENT, et l'on garde ouverte la bibliothèque qui IMPRIME.
           * ================================================================ */
          code: 'RAP', label: 'Rapports & Impression', icon: 'printer', roles: ALL,
          items: [
            { id: 'rapports-bibliotheque', label: 'Bibliothèque des états', icon: 'printer' },
            { id: 'rapports-direction', label: 'États de la Direction', icon: 'chart-no-axes-combined',
              roles: ['direction', 'da', 'dm', 'admin'] },
            { id: 'rapports-generateur', label: 'Générateur de rapports', icon: 'file-cog',
              roles: ['direction', 'da', 'dm', 'admin', 'comptable', 'assistant_comptable'] },
            { id: 'rapports-historique', label: 'Historique des éditions', icon: 'history',
              roles: ['direction', 'da', 'dm', 'admin', 'comptable', 'assistant_comptable'] },
          ],
        },
      ],
    },
    {
      domain: 'Système',
      icon: 'settings',
      modules: [
        {
          code: 'M14', label: 'Sécurité & Utilisateurs', icon: 'shield',
          roles: ['admin', 'direction', 'da'],
          items: [
            { id: 'm14-utilisateurs', label: 'Utilisateurs', icon: 'user-cog' },
            { id: 'm14-roles', label: 'Rôles & permissions (RBAC)', icon: 'key-round' },
            { id: 'm14-soignants', label: 'Prescripteurs & exécutants de soins', icon: 'user-round-cog' },
            { id: 'm14-sessions', label: 'Sessions actives', icon: 'monitor' },
            { id: 'm14-audit', label: 'Journal d’audit', icon: 'scroll-text' },
            { id: 'm14-sauvegardes', label: 'Sauvegardes & restauration', icon: 'database-backup' },
            { id: 'm14-taches', label: 'Tâches planifiées', icon: 'timer' },
          ],
        },
        {
          code: 'CFG', label: 'Configuration Clinique', icon: 'sliders-horizontal',
          roles: ['admin', 'da', 'direction'],
          items: [
            { id: 'cfg-organisation', label: 'Organisation & organigramme', icon: 'network' },
            { id: 'cfg-branding', label: 'Identité & papier à en-tête', icon: 'image' },
            { id: 'cfg-tarifs', label: 'Référentiel tarifaire', icon: 'tag' },
            { id: 'cfg-catalogue', label: 'Catalogue tarifaire (deux prix)', icon: 'list-ordered' },
            { id: 'cfg-imagerie-catalogue', label: 'Catalogue de l’imagerie', icon: 'scan-line' },
            { id: 'cfg-entetes', label: 'Papier à en-tête officiel', icon: 'file-badge' },
            { id: 'cfg-types-piece', label: 'Types de pièces certifiantes', icon: 'stamp' },
            { id: 'cfg-rappels', label: 'Rappels & messages', icon: 'bell-ring' },
            { id: 'cfg-certificats', label: 'Certificats médicaux', icon: 'file-badge' },
            { id: 'cfg-natures-facture', label: 'Natures de facture', icon: 'receipt-text' },
            { id: 'cfg-centres-couts', label: 'Centres de coûts', icon: 'target' },
            { id: 'cfg-regles', label: 'Règles métier versionnées', icon: 'shield-check' },
            { id: 'cfg-fiscalite', label: 'Paramètres fiscaux (IFU / RCCM)', icon: 'landmark' },
            { id: 'cfg-comptabilite', label: 'Paramètres comptables & obligations', icon: 'book-open-check' },
            { id: 'cfg-notifications', label: 'Notifications', icon: 'bell' },
            { id: 'cfg-compte', label: 'Mon compte', icon: 'circle-user' },
            { id: 'cfg-modules', label: 'Activité des modules', icon: 'toggle-right' },
            { id: 'cfg-systeme', label: 'Paramètres système', icon: 'settings' },
          ],
        },
      ],
    },
    /* Pilotage vient en DERNIER : l’ordre cible des Instructions place les
       domaines de travail avant l’analyse. */
    {
      domain: 'Pilotage',
      icon: 'layout-dashboard',
      modules: [
        /* ====================================================================
         * DEUX RANGÉES, ET NON UNE DE VINGT.
         * --------------------------------------------------------------------
         * Le domaine ne portait qu'un seul module : vingt pastilles à la file,
         * où « Direction » et « Statistiques de la Direction » se suivaient
         * sans qu'on sache laquelle ouvrir. Ce ne sont pourtant pas des objets
         * de même nature — les unes lisent l'ACTIVITÉ DE LA CLINIQUE toutes
         * fonctions confondues, les autres montrent à un agent CE QUI
         * L'ATTEND à son poste. La coupure sépare donc deux usages, elle ne
         * range pas des cartes par commodité.
         * ================================================================== */
        {
          code: 'PIL', label: 'Pilotage & analyse', icon: 'chart-no-axes-combined', roles: ALL,
          items: [
            { id: 'dash-direction', label: 'Direction', icon: 'building-2', roles: ['direction', 'dm', 'da', 'admin'] },
            { id: 'dash-da', label: 'Statistiques de la Direction', icon: 'trending-up',
              roles: ['direction', 'dm', 'da', 'admin', 'comptable', 'assistant_comptable'] },
            { id: 'dash-croise', label: 'Tableau de bord dynamique croisé', icon: 'chart-scatter',
              roles: ['direction', 'dm', 'da', 'admin', 'comptable', 'surveillant', 'assistant_comptable'] },
            { id: 'dash-admin', label: 'Administrateur', icon: 'settings', roles: ['admin'] },
            { id: 'm4-stats-maternite', label: 'Statistiques maternité & naissances', icon: 'baby',
              roles: ['infirmier', 'medecin', 'dm', 'da', 'direction', 'admin', 'surveillant'] },
            { id: 'm2-stats-echographie', label: 'Statistiques de l’imagerie médicale', icon: 'scan-line',
              roles: ['medecin', 'dm', 'da', 'direction', 'admin', 'echographiste'] },
            /* Phase 9 — les statistiques transverses, toutes CALCULÉES. */
            { id: 'm5-stats-examens', label: 'Statistiques des examens', icon: 'flask-conical',
              roles: ['laborantin', 'medecin', 'dm', 'da', 'direction', 'admin'] },
            { id: 'm2-stats-consultations', label: 'Statistiques des consultations', icon: 'stethoscope',
              roles: ['medecin', 'dm', 'da', 'direction', 'admin'] },
            { id: 'm3-stats-bloc', label: 'Statistiques du bloc & anesthésie', icon: 'scissors',
              roles: ['medecin', 'chirurgien', 'anesthesiste', 'dm', 'da', 'direction', 'admin'] },
            /* L'HOSPITALISATION MANQUAIT au pilotage : c'est pourtant le
               séjour qui pèse le plus lourd au compte de résultat, et le seul
               dont la durée moyenne se pilote. */
            { id: 'm3-stats-hospitalisations', label: 'Statistiques des hospitalisations', icon: 'bed-double',
              roles: ['medecin', 'infirmier', 'chirurgien', 'dm', 'da', 'direction', 'admin', 'surveillant'] },
            { id: 'm10-cout-agent', label: 'Coût global de l’agent', icon: 'user-cog',
              roles: ['da', 'direction', 'admin', 'comptable'] },
            { id: 'm12-rentabilite-groupes', label: 'Recettes & charges par groupe', icon: 'scale',
              roles: ['da', 'direction', 'admin', 'comptable', 'dm'] },
            /* Vague 64 — la grille « objectif fixé / réel atteint » sur les
               quatre axes du document. Sa place est au PILOTAGE et non en
               M12 : c'est une lecture de direction, pas une pièce comptable. */
            { id: 'm12-tableau-decisionnel', label: 'Tableau de bord décisionnel', icon: 'gauge',
              roles: ['da', 'direction', 'admin', 'comptable'] },
          ],
        },
        /* ====================================================================
         * GESTION & TRÉSORERIE — DÉPLACÉE AU PILOTAGE (24/09/2026)
         * --------------------------------------------------------------------
         * Elle vivait en sous-section du domaine FINANCIER : c'est là que le
         * document la demandait. La Direction l'a rangée au PILOTAGE, et
         * c'est cohérent avec ce qu'elle contient — le besoin en fonds de
         * roulement et le coût à l'activité ne sont pas des pièces
         * comptables, ce sont des lectures de direction, comme la grille
         * objectif / réel qui les précède désormais dans la même colonne.
         *
         * Elle reste une rangée `secondaire` DE M12 : ses écrans restent
         * canoniques, le hub du module ne se dédouble pas, et surtout LES
         * DROITS NE BOUGENT PAS D'UN POUCE — un module nouveau aurait imposé
         * de reprendre seize fiches RBAC pour un simple regroupement visuel.
         * ================================================================== */
        {
          code: 'M12', label: 'Gestion & trésorerie', icon: 'gauge-circle',
          secondaire: true,
          roles: ['comptable', 'da', 'admin', 'direction'],
          items: [
            { id: 'm12-bfr', label: 'Besoin en fonds de roulement', icon: 'scale' },
            { id: 'm12-cout-activite', label: 'Coût à l’activité', icon: 'calculator' },
          ],
        },
        {
          code: 'DASH', label: 'Tableaux de bord par poste', icon: 'gauge', roles: ALL,
          items: [
            { id: 'dash-medecin', label: 'Médecin', icon: 'stethoscope', roles: ['medecin', 'dm', 'admin'] },
            { id: 'dash-infirmier', label: 'Infirmier / Sage-femme', icon: 'heart-pulse', roles: ['infirmier', 'dm', 'admin'] },

            /* Ces deux tableaux existent toujours — leur page, leurs liens, leur
               contenu — mais l'activité est FERMÉE : ils sortent du menu par
               `modulesActifs`, comme la banque de sang. Les retirer du
               manifeste aurait supprimé leur page et cassé les liens qui les
               visent. */
            /* L'ACTIVITÉ CONTINUE, seul le compte a changé. La pharmacie est
               tenue par la Caissière-Dispensatrice : son tableau lui revient.
               L'intitulé cesse de nommer un rôle qui n'ouvre plus de session. */
            { id: 'dash-pharmacien', label: 'Pharmacie', icon: 'pill',
              roles: ['caissier', 'stock', 'da', 'admin', 'direction'] },
            { id: 'dash-laborantin', label: 'Biologiste médical', icon: 'flask-conical', roles: ['laborantin', 'admin'] },
            { id: 'dash-stock', label: 'Gestionnaire de stock', icon: 'package', roles: ['stock', 'da', 'admin'] },
            { id: 'dash-caissier', label: 'Caisse', icon: 'banknote', roles: ['caissier', 'admin'] },
            { id: 'dash-comptable', label: 'Comptabilité', icon: 'calculator', roles: ['comptable', 'da', 'admin'] },
            { id: 'dash-rh', label: 'Ressources humaines', icon: 'users-round', roles: ['rh', 'da', 'admin'] },
            { id: 'dash-receptionniste', label: 'Accueil', icon: 'door-open', roles: ['reception', 'admin'] },
            { id: 'dash-admin-agent', label: 'Agent administratif', icon: 'briefcase', roles: ['agentadmin', 'admin'] },
            { id: 'dash-ambulancier', label: 'Ambulance', icon: 'ambulance', roles: ['ambulancier', 'admin'] },
            { id: 'dash-aide-soignant', label: 'Aide-soignante', icon: 'hand-heart',
              roles: ['aide_soignant', 'admin', 'dm'] },
            { id: 'dash-echographiste', label: 'Échographie', icon: 'scan-line',
              roles: ['echographiste', 'admin', 'dm'] },
            { id: 'dash-surveillant', label: 'Surveillant', icon: 'clipboard-check',
              roles: ['surveillant', 'admin', 'da', 'dm'] },
            /* Icône distincte de l'agent administratif : deux pastilles au
               même dessin dans la même rangée se lisent comme un doublon. */
            { id: 'dash-assistant-comptable', label: 'Assistant de Direction', icon: 'contact-round',
              roles: ['assistant_comptable', 'admin', 'da'] },

            /* Les trois tableaux de la phase 2 — chacun réservé à son rôle,
               plus les directions concernées. Sans tableau propre, un rôle
               retombe sur celui d'un autre profil (leçon de la vague 31). */
            { id: 'dash-chirurgien', label: 'Chirurgien', icon: 'slice',
              roles: ['chirurgien', 'admin', 'dm', 'direction'] },
            { id: 'dash-anesthesiste', label: 'Anesthésiste', icon: 'syringe',
              roles: ['anesthesiste', 'admin', 'dm', 'direction'] },
            { id: 'dash-aide-comptable', label: 'Assistant Comptable', icon: 'calculator',
              roles: ['aide_comptable', 'admin', 'da', 'direction'] },

            /* LA MATERNITÉ EST UN POSTE, pas une spécialité du médecin : la
               sage-femme de garde y arrive avec trois questions — qui est en
               travail, quels termes tombent cette semaine, quelles grossesses
               sont à risque. Le tableau du médecin n'y répond pas. */
            { id: 'dash-maternite', label: 'Maternité', icon: 'baby',
              roles: ['infirmier', 'medecin', 'dm', 'admin', 'direction'] },

            { id: 'dash-patient', label: 'Espace patient', icon: 'user-round', roles: ['reception', 'medecin', 'admin'] },
          ],
        },
      ],
    },
  ];

  /* --- Écrans hors méga-menu (authentification, erreurs, impression) ------- */
  var STANDALONE = [
    { id: 'index', label: 'Connexion', path: '../index' + EXT, root: true, icon: 'log-in' },
    { id: 'auth-forgot', label: 'Mot de passe oublié', icon: 'key-round' },
    { id: 'auth-reset', label: 'Réinitialisation du mot de passe', icon: 'lock' },
    { id: 'auth-2fa', label: 'Vérification en 2 étapes', icon: 'smartphone' },
    { id: 'auth-lock', label: 'Écran verrouillé', icon: 'lock' },
    { id: 'error-404', label: 'Page introuvable', icon: 'file-search' },
    { id: 'error-403', label: 'Accès refusé', icon: 'shield-alert' },
    { id: 'plan-du-site', label: 'Plan du site', icon: 'map' },
    {
      id: 'aide-apropos', label: 'Aide & À propos', icon: 'life-buoy',
      module: 'SUP', moduleLabel: 'Aide & assistance', domain: 'Système', dansRecherche: true,
    },
    {
      id: 'contact-editeur', label: 'Contactez l’éditeur', icon: 'mail',
      module: 'SUP', moduleLabel: 'Aide & assistance', domain: 'Système', dansRecherche: true,
    },
    /* Pages fusionnées dans le répertoire (Bug 1) : hors ruban et hors
       recherche, conservées parce que liens et surcharges les visent — elles
       renvoient vers m1-patients. */
    {
      id: 'm1-dossier-medical', label: 'Dossier médical informatisé', icon: 'file-text',
      module: 'M1', moduleLabel: 'Patients & Dossier médical', domain: 'Soins',
    },
    /* Le dossier de consultation a QUITTÉ le répertoire (14/09/2026) pour son
       propre écran, m2-dossiers-consultation : l'ancienne page renvoie
       désormais là-bas. */
    {
      id: 'm1-dossier-etendu', label: 'Dossier de consultation étendu', icon: 'clipboard-plus',
      module: 'M1', moduleLabel: 'Patients & Dossier médical', domain: 'Soins',
    },
    /* LES PAGES DE SAISIE (21/09/2026) — des modales devenues des PAGES.
       Elles sont hors ruban parce qu'elles ne sont pas des destinations qu'on
       choisit dans un menu : on y arrive depuis un registre, pour une fiche
       précise ou pour en ouvrir une. Elles portent le module de leur registre
       et héritent donc EXACTEMENT de ses droits — une page de saisie qui
       s'ouvrirait plus largement que le registre qu'elle alimente serait une
       porte dérobée. */
    {
      id: 'm2-dossier-consultation-nouveau', label: 'Dossier de consultation — saisie', icon: 'clipboard-plus',
      servant: 'm2-dossiers-consultation',
      module: 'M2', moduleLabel: 'Consultations & prescriptions', domain: 'Soins',
    },
    {
      id: 'm2-ordonnance-nouvelle', label: 'Nouvelle ordonnance — saisie', icon: 'pill',
      servant: 'm2-ordonnances',
      module: 'M2', moduleLabel: 'Consultations & prescriptions', domain: 'Soins',
    },
    /* UNE page pour les CINQ modalités : elle lit la sienne dans son adresse
       (`#modalite=scanner`). Cinq pages auraient recopié cinq fois le même
       écran — c'est précisément pour l'éviter que les cinq tableaux sortent
       d'une fabrique unique. */
    {
      id: 'm2-imagerie-cr', label: 'Compte rendu d’imagerie — saisie', icon: 'file-scan',
      servant: 'm2-imagerie',
      module: 'M2', moduleLabel: 'Imagerie médicale', domain: 'Soins',
    },
    /* La feuille de comptage : on y passe une heure, la main sur le rayon.
       Hors ruban parce qu'elle ne se choisit pas dans un menu — on y arrive
       en lançant un inventaire, et elle porte son contexte dans son adresse
       (magasin, type, date, périmètre, opérateur). Module M6 : elle hérite
       EXACTEMENT des droits du registre qu'elle alimente. */
    {
      id: 'm6-inventaire-feuille', label: 'Feuille d’inventaire — comptage', icon: 'clipboard-list',
      servant: 'm6-inventaires',
      module: 'M6', moduleLabel: 'Pharmacie & Stocks', domain: 'Logistique',
    },
    /* L'ouverture d'un dossier patient : une page, parce qu'on la remplit
       devant la personne, au guichet. Module M1 — mêmes droits que le
       répertoire qu'elle alimente. */
    {
      id: 'm1-patient-nouveau', label: 'Ouvrir un dossier patient', icon: 'user-plus',
      servant: 'm1-patients',
      module: 'M1', moduleLabel: 'Patients & Dossier médical', domain: 'Accueil',
    },
    /* Le cahier de la parturiente : on l'ouvre avec elle, en plusieurs
       minutes — douze facteurs de surveillance et un plan d'accouchement. */
    {
      id: 'm4-dossier-obstetrical-nouveau', label: 'Ouvrir un dossier obstétrical', icon: 'folder-plus',
      servant: 'm4-dossier-obstetrical',
      module: 'M4', moduleLabel: 'Maternité, Naissances & Décès', domain: 'Soins',
    },
    /* Le registre des visites a FUSIONNÉ dans « Rendez-vous & visites »
       (06/09/2026) : un seul écran tient les rendez-vous pris et les passages
       sans rendez-vous. Sa page subsiste hors ruban et renvoie — retirer une
       entrée du manifeste n'est jamais la bonne façon de fermer un écran,
       elle casserait tout lien qui la vise. */
    {
      id: 'm2-visites', label: 'Registre des visites de suivi clinique', icon: 'user-check',
      module: 'M2', moduleLabel: 'RDV, Visites & Consultations', domain: 'Accueil',
    },
    /* Les certificats des externes ont rejoint le registre unique : la page
       subsiste et renvoie, elle n'affiche plus de second registre. */
    {
      id: 'm1-certificats-externes', label: 'Certificats — patients externes', icon: 'file-badge',
      module: 'M1', moduleLabel: 'Patients & Dossier médical', domain: 'Accueil',
    },
    /* LA FICHE D'ENQUÊTE OUVERTE À UN TIERS. Elle est hors ruban ET hors
       recherche, et c'est le point essentiel : une page d'enquête qui
       afficherait la coquille de l'application serait une porte. Ni ruban,
       ni recherche, ni session, ni fil d'Ariane — elle est plus restreinte
       encore que l'aide et le contact éditeur, qui, eux, s'adressent à un
       agent connecté. Son seul laissez-passer est le jeton porté par
       l'adresse ; sans jeton valide, elle ne montre rien. */
    {
      id: 'enquete-publique', label: 'Fiche d’enquête (lien partagé)', icon: 'clipboard-list',
      module: 'M13', moduleLabel: 'Administration & Ambulance', domain: 'Administration',
    },
  ];

  /* --- Pages d'accueil de module (hubs) ------------------------------------
   * Chaque module dispose d'une page qui présente ses écrans sous forme de
   * cartes (icône, titre, description). Elle sert de point d'entrée : depuis le
   * fil d'Ariane, depuis l'intitulé du module dans le méga-menu et depuis les
   * raccourcis permanents. On navigue ainsi de page en page sans repasser par
   * le menu. Ces entrées ne figurent pas dans les colonnes du ruban.
   * ---------------------------------------------------------------------- */
  function hubId(code) { return 'hub-' + String(code).toLowerCase(); }

  /* --- Index plat : id -> { id, label, href, module, domain, roles } ------- */
  /* --------------------------------------------------------------------------
   * ALIAS DE MANIFESTE (phase 3) : un écran ne peut appartenir qu'à UNE rangée
   * canonique — c'est elle qui décide de sa page, de son module et de son fil
   * d'Ariane. Le domaine ACCUEIL, lui, RÉUNIT des écrans venus de M1, M2, M13
   * et CFG : ses rangées portent `alias: true` et ses écrans aussi. Une entrée
   * d'alias apparaît dans le ruban mais n'engendre NI page, NI hub, NI entrée
   * d'index — et ses droits sont ceux de l'écran canonique, jamais les siens.
   * ------------------------------------------------------------------------ */
  var INDEX = {};

  /** Une entrée d'écran, indexée depuis la rangée qui la porte. */
  function indexerEcran(domain, mod, item) {
    if (item.alias) return; /* l'entrée canonique fait foi */
    INDEX[item.id] = {
      id: item.id,
      label: item.label,
      href: item.id + EXT,
      module: mod.code,
      moduleLabel: mod.label,
      icon: item.icon || mod.icon,
      moduleIcon: mod.icon,
      domain: domain.domain,
      domainIcon: domain.icon,
      roles: item.roles || mod.roles || ALL,
      /* Un écran que TOUT poste peut ouvrir, quel que soit son module. */
      universel: !!item.universel,
    };
  }

  NAV.forEach(function (domain) {
    domain.modules.forEach(function (mod) {
      if (mod.alias) return; /* une rangée d'alias n'indexe rien */
      /* Une rangée SECONDAIRE indexe ses écrans — ils sont canoniques chez
         elle — mais ne crée pas de second hub : un module a UN hub, celui de
         sa rangée canonique, sinon le fil d'Ariane renverrait tantôt à l'un
         tantôt à l'autre selon l'ordre de déclaration. */
      if (mod.secondaire) {
        mod.items.forEach(function (item) { indexerEcran(domain, mod, item); });
        return;
      }
      INDEX[hubId(mod.code)] = {
        id: hubId(mod.code),
        label: mod.label,
        href: hubId(mod.code) + EXT,
        module: mod.code,
        moduleLabel: mod.label,
        icon: mod.icon,
        moduleIcon: mod.icon,
        domain: domain.domain,
        domainIcon: domain.icon,
        roles: mod.roles || ALL,
        hub: true,
      };
      mod.items.forEach(function (item) { indexerEcran(domain, mod, item); });
    });
  });
  STANDALONE.forEach(function (item) {
    INDEX[item.id] = {
      id: item.id,
      label: item.label,
      href: item.path || item.id + EXT,
      module: item.module || 'AUTH',
      moduleLabel: item.moduleLabel || 'Accès',
      icon: item.icon || 'lock',
      moduleIcon: item.icon || 'lock',
      domain: item.domain || 'Système',
      domainIcon: 'settings',
      roles: ALL,
      /* Hors ruban, mais accessibles à la recherche globale lorsque la page
         s'adresse à l'utilisateur plutôt qu'au parcours d'authentification. */
      standalone: !item.dansRecherche,
      /* Le registre qu'une page de saisie alimente : c'est sur LUI que ses
         droits se résolvent, et pas sur son module. */
      servant: item.servant || null,
    };
  });

  /* ==========================================================================
   * SURCHARGES RBAC — la matrice administrable
   * --------------------------------------------------------------------------
   * Le manifeste ci-dessus donne les droits d'ORIGINE. L'administrateur peut
   * les corriger depuis « Rôles & permissions » : ses décisions vivent dans la
   * collection `rbac` du magasin, une fiche par rôle, et c'est `can()` qui les
   * applique. Sans cette couche, l'écran d'édition écrivait dans le vide.
   *
   * Quatre droits par module, tels que la Direction les a demandés :
   *   voir     — le module apparaît, ses écrans s'ouvrent ;
   *   editer   — créer et modifier y est permis ;
   *   annuler  — archiver et annuler y est permis ;
   *   lectureSeule — dérivé : le module est visible mais figé.
   *
   * Le cache évite de relire le magasin à chaque appel — `can()` est appelé
   * des centaines de fois par page (ruban, recherche, fil d'Ariane).
   * ======================================================================== */
  var DROITS = ['voir', 'editer', 'annuler'];
  var _cacheRbac = null;

  function magasin() {
    return global.SIGH && global.SIGH.store ? global.SIGH.store : null;
  }

  /** Les surcharges, indexées par rôle. Relues après toute modification. */
  function surcharges() {
    if (_cacheRbac) return _cacheRbac;
    _cacheRbac = {};
    var S = magasin();
    if (!S) return _cacheRbac;
    try {
      var fiches = S.collection('rbac', { module: 'M14', entite: 'rôle', prefix: 'RBAC' }).all();
      /* Une seule fiche par rôle est la règle, mais un doublon ne doit pas
         rendre la matrice imprévisible : on FUSIONNE champ par champ, la
         dernière fiche l'emportant sur ce qu'elle définit — et seulement sur
         cela. Sans cette fusion, un second enregistrement effaçait le
         renommage et l'archivage portés par le premier. */
      fiches.forEach(function (f) {
        if (!f.role) return;
        var deja = _cacheRbac[f.role];
        if (!deja) { _cacheRbac[f.role] = f; return; }
        var fusion = Object.assign({}, deja);
        Object.keys(f).forEach(function (k) {
          if (f[k] === undefined || f[k] === null) return;
          if (k === 'droits' || k === 'droitsEcrans') {
            fusion[k] = Object.assign({}, deja[k] || {}, f[k] || {});
            return;
          }
          fusion[k] = f[k];
        });
        _cacheRbac[f.role] = fusion;
      });
    } catch (e) { /* magasin indisponible : on s'en tient au manifeste */ }
    return _cacheRbac;
  }

  /** À appeler après avoir écrit une fiche de rôle. */
  function invaliderRbac() { _cacheRbac = null; appliquerRenommages(); }

  /* ==========================================================================
   * MODULES DÉSACTIVÉS
   * --------------------------------------------------------------------------
   * Une clinique n'exerce pas toutes les activités que le logiciel sait tenir.
   * Nassiera Too ne pratique ni la banque de sang ni la transfusion : laisser
   * ces écrans au ruban donnerait à croire qu'ils attendent d'être remplis.
   *
   * Un module désactivé se comporte comme un rôle archivé : il sort du menu,
   * de la recherche et de ses propres adresses. Il n'est PAS supprimé — la
   * clinique peut ouvrir l'activité demain, et ses données de démonstration
   * l'attendent intactes.
   * ======================================================================== */
  var _cacheModules = null;

  /**
   * Deux index : les ÉCRANS fermés et les MODULES entièrement fermés.
   * La distinction compte — la clinique ferme la banque de sang, pas le
   * laboratoire. Une entrée sans liste d'écrans ferme le module entier.
   */
  function modulesDesactives() {
    if (_cacheModules) return _cacheModules;
    _cacheModules = { ecrans: {}, modules: {}, fiches: [] };
    var St = magasin();
    if (!St) return _cacheModules;
    try {
      St.collection('modulesActifs').all().forEach(function (m) {
        /* Une fiche ARCHIVÉE ne ferme plus rien (RG-14) : la laisser agir
           fermerait un module depuis une fiche que l'écran de pilotage ne
           montre plus — une fermeture invisible est une fermeture
           indébrayable. */
        if (m.statut === 'archive') return;
        _cacheModules.fiches.push(m);
        if (m.actif !== false) return;
        if (m.ecrans && m.ecrans.length) {
          m.ecrans.forEach(function (id) { _cacheModules.ecrans[id] = m; });
        } else if (m.module) {
          _cacheModules.modules[m.module] = m;
        }
      });
    } catch (e) { /* magasin indisponible : tout reste ouvert */ }
    return _cacheModules;
  }

  /** Le module entier est-il ouvert ? */
  function moduleActif(code) { return !modulesDesactives().modules[code]; }

  /** L'écran est-il ouvert ? Un écran d'un module fermé l'est aussi. */
  function ecranActif(id, code) {
    var d = modulesDesactives();
    if (id && d.ecrans[id]) return false;
    if (code && d.modules[code]) return false;
    return true;
  }

  /** La fiche d'activité qui ferme un écran, pour pouvoir le DIRE. */
  function fermeturePour(id, code) {
    var d = modulesDesactives();
    return d.ecrans[id] || d.modules[code] || null;
  }

  function invaliderModules() { _cacheModules = null; }

  /** Un rôle archivé n'ouvre plus rien — ses comptes sont hors service. */
  function roleArchive(roleId) {
    var f = surcharges()[roleId];
    return !!(f && f.statut === 'archive');
  }

  /** Droits d'origine d'un rôle sur un module, lus dans le manifeste. */
  function droitsOrigine(roleId, code) {
    /* LA RANGÉE CANONIQUE SEULE FAIT FOI. La boucle retenait la DERNIÈRE
       rangée portant le code : elle ne tombait juste que parce que les
       rangées d'alias — qui ne déclarent aucun rôle, donc ouvriraient le
       module à tout le monde — étaient déclarées avant les canoniques.
       Une rangée secondaire ajoutée après aurait suffi à fausser les droits
       d'origine d'un module entier. */
    var mod = null;
    NAV.forEach(function (dom) {
      dom.modules.forEach(function (x) {
        if (x.alias || x.secondaire || mod) return;
        if (x.code === code) mod = x;
      });
    });
    /* Écran hors ruban : la matrice ne le gouverne pas — seul le manifeste
       décide. Le confondre avec un module fermé rendait l'aide et le contact
       éditeur inatteignables. */
    if (!mod) {
      return { voir: true, editer: true, annuler: true, lectureSeule: false, origine: true, horsMatrice: true };
    }
    var ouvert = !!(mod && mod.items.some(function (it) {
      var roles = it.roles || mod.roles || ALL;
      return roles === ALL || roles.indexOf(roleId) !== -1;
    }));
    /* Par défaut, qui voit un module peut y agir : c'est le comportement
       qu'avait le prototype avant que la matrice ne devienne administrable.
       Restreindre est une décision explicite de l'administrateur. */
    return { voir: ouvert, editer: ouvert, annuler: ouvert, lectureSeule: false, origine: true };
  }

  /**
   * Droits effectifs d'un rôle sur un module : manifeste, puis surcharge.
   * C'est le point unique consulté par le ruban, la recherche et les écrans.
   */
  function droits(roleId, code) {
    var base = droitsOrigine(roleId, code);
    if (base.horsMatrice) return base;
    /* Un module accordé par surcharge à un rôle absent du manifeste : la base
       est fermée, la surcharge l'ouvre. Sans cela, le rôle verrait l'écran
       sans pouvoir y agir, quoi qu'on ait coché. */
    if (roleArchive(roleId)) {
      return { voir: false, editer: false, annuler: false, lectureSeule: true, origine: false, roleArchive: true };
    }
    var f = surcharges()[roleId];
    if (!f || !f.droits || !f.droits[code]) return base;
    var o = f.droits[code];
    var d = {
      voir: o.voir != null ? !!o.voir : base.voir,
      editer: o.editer != null ? !!o.editer : base.editer,
      annuler: o.annuler != null ? !!o.annuler : base.annuler,
      origine: false,
    };
    /* La lecture seule est une conséquence, jamais une quatrième dimension
       indépendante : un module visible sans droit d'agir EST en lecture seule. */
    if (!d.voir) { d.editer = false; d.annuler = false; }
    d.lectureSeule = d.voir && !d.editer && !d.annuler;
    return d;
  }

  /**
   * Droits d'un rôle sur un ÉCRAN précis.
   *
   * L'écran l'emporte sur le module : sans cette priorité, ouvrir M1 en
   * lecture seule rouvrirait les écrans qu'on vient d'en fermer. Sans
   * surcharge d'écran, les droits du module s'appliquent — c'est le cas de la
   * quasi-totalité des écrans, et il ne faut pas avoir à les déclarer un à un.
   */
  /* ==========================================================================
   * UN ÉCRAN UNIVERSEL — OUVERT À TOUS LES POSTES, QUEL QUE SOIT LE MODULE
   * --------------------------------------------------------------------------
   * L'expression d'un besoin appartient à TOUT agent : le médecin qui n'a plus
   * de papier, la sage-femme à court de gants, la réception dont l'imprimante
   * est vide. L'écran vit en M7, que la plupart des rôles n'ouvrent pas — et
   * le réserver à la logistique reviendrait à demander aux services de passer
   * par un tiers pour dire ce qui leur manque, ce qui est exactement la
   * lenteur que le module doit supprimer.
   *
   * UNE DÉCLARATION, PAS SEIZE SURCHARGES. Écrire `m7-besoins` dans la fiche
   * de chacun des seize rôles aurait tenu — jusqu'au premier rôle créé en
   * exploitation, qui ne l'aurait pas eue. Le manifeste le porte donc une
   * fois, et le moteur l'applique.
   *
   * CE QUE `universel` NE FAIT PAS : il ne rouvre pas un module DÉSACTIVÉ
   * (`ecranActif` tranche avant, pour tous les rôles, administrateur
   * compris), il ne ressuscite pas un rôle archivé, et il cède devant une
   * surcharge d'écran EXPLICITE — un administrateur qui ferme nommément cet
   * écran à un rôle garde le dernier mot.
   * ======================================================================== */
  function estUniversel(ecranId) {
    var e = ecranId && INDEX[ecranId];
    return !!(e && e.universel);
  }

  function droitsEcran(roleId, ecranId, code) {
    var base = droits(roleId, code);
    if (!ecranId) return base;
    var f = surcharges()[roleId];
    var o = f && f.droitsEcrans && f.droitsEcrans[ecranId];
    if (!o && estUniversel(ecranId)) {
      /* Voir et écrire — exprimer un besoin, c'est écrire. Mais jamais
         ANNULER : retirer le bon d'un autre service n'appartient pas à
         celui qui passe par là. */
      return { voir: true, editer: true, annuler: base.annuler,
        origine: false, universel: true, lectureSeule: false };
    }
    if (!o) return base;
    var d = {
      voir: o.voir != null ? !!o.voir : base.voir,
      editer: o.editer != null ? !!o.editer : base.editer,
      annuler: o.annuler != null ? !!o.annuler : base.annuler,
      origine: false, surchargeEcran: true,
    };
    if (!d.voir) { d.editer = false; d.annuler = false; }
    d.lectureSeule = d.voir && !d.editer && !d.annuler;
    return d;
  }

  /** Le libellé d'un rôle peut être renommé (Laborantin → Biologiste médical). */
  function appliquerRenommages() {
    var sur = surcharges();

    /* Un rôle CRÉÉ par l'administrateur entre dans ROLES comme les autres :
       tout ce qui lit N.ROLES — ruban, bandeau, impressions, écran de
       connexion — le voit sans rien savoir de sa provenance. Un rôle nouveau
       n'apparaît dans AUCUNE liste `roles` du manifeste : il part donc de
       zéro, et l'administrateur lui ouvre ce qu'il veut par surcharge. C'est
       le comportement sûr — l'inverse donnerait tous les droits à un rôle
       qu'on vient d'inventer. */
    Object.keys(sur).forEach(function (r) {
      var f = sur[r];
      if (!f.nouveau || ROLES[r]) return;
      ROLES[r] = {
        id: r, label: f.libelle || r, short: f.libelleCourt || f.libelle || r,
        color: f.couleur || 'neutral', home: f.accueil || 'plan-du-site',
        cree: true, creeLe: f.definiLe || null,
      };
    });

    Object.keys(ROLES).forEach(function (r) {
      var f = sur[r];
      if (!ROLES[r].labelOrigine) ROLES[r].labelOrigine = ROLES[r].label;
      if (!ROLES[r].shortOrigine) ROLES[r].shortOrigine = ROLES[r].short;
      ROLES[r].label = (f && f.libelle) ? f.libelle : ROLES[r].labelOrigine;
      /* L'intitulé COURT suit le long. C'est lui que portent le ruban et le
         bandeau — l'oublier laissait le rôle renommé à l'endroit le plus
         visible de l'écran, ce qui fait croire à deux rôles distincts. */
      ROLES[r].short = (f && f.libelleCourt) ? f.libelleCourt
        : ((f && f.libelle) ? f.libelle : ROLES[r].shortOrigine);
      ROLES[r].archive = !!(f && f.statut === 'archive');
    });
  }

  /**
   * Habilitation d'un rôle sur une entrée du manifeste.
   * La propriété entry.module (code) déclenche la consultation des surcharges ;
   * seul le manifeste s'applique — c'est le cas des écrans hors ruban.
   */
  /** Une surcharge pose-t-elle EXPLICITEMENT un droit pour cet écran ? */
  function surchargeExplicite(roleId, ecranId, code) {
    var f = surcharges()[roleId];
    if (!f) return null;
    var parEcran = f.droitsEcrans && ecranId && f.droitsEcrans[ecranId];
    if (parEcran && parEcran.voir != null) return !!parEcran.voir;
    var parModule = f.droits && code && f.droits[code];
    if (parModule && parModule.voir != null) return !!parModule.voir;
    return null;
  }

  /* ==========================================================================
   * UNE PAGE DE SAISIE PORTE LES DROITS DU REGISTRE QU'ELLE ALIMENTE
   * --------------------------------------------------------------------------
   * Les grandes saisies ont quitté les modales pour des PAGES (vagues 63-65),
   * et une page est un ÉCRAN : elle hérite donc de son module. C'est trop
   * large ou trop étroit selon le rôle — l'échographiste a M2 en LECTURE et
   * `m2-imagerie` en écriture par surcharge d'écran. Résultat : il ne pouvait
   * plus saisir un compte rendu, alors qu'il le saisissait la veille dans une
   * modale ouverte depuis un écran où il a le droit d'écrire.
   *
   * L'entrée déclare donc `servant` — l'écran dont elle prolonge le geste — et
   * c'est SUR LUI que les droits se résolvent. L'alternative aurait été
   * d'ajouter six surcharges d'écran à seize fiches de rôle : on l'aurait
   * oubliée au premier rôle créé, et le défaut serait revenu sans bruit.
   * ======================================================================== */
  function ecranDesDroits(entry) {
    if (!entry) return null;
    return entry.servant || entry.id;
  }

  function can(roleId, entry) {
    if (!entry) return false;
    if (roleArchive(roleId)) return false;

    /* ======================================================================
     * LES DRAPEAUX VIENNENT DE L'INDEX, PAS DE L'APPELANT
     * ----------------------------------------------------------------------
     * Cinq endroits fabriquent une entrée SYNTHÉTIQUE pour interroger `can`
     * — le ruban, les cartes de hub, les accès rapides, la recherche, la
     * matrice. Chacun recopie ce qu'il croit utile, et chacun oublie ce qu'il
     * ne connaît pas : le module la première fois, l'identifiant la
     * deuxième, `universel` aujourd'hui. Le défaut est revenu trois fois.
     *
     * Dès que l'appelant nomme l'écran, on RELIT donc ses propriétés à la
     * source. Un drapeau ajouté demain au manifeste sera pris en compte par
     * les cinq appelants sans qu'aucun soit retouché.
     * ==================================================================== */
    var canonique = entry.id ? INDEX[entry.id] : null;
    if (canonique && (canonique.universel || canonique.servant)) {
      entry = {
        id: entry.id,
        roles: entry.roles, module: entry.module || entry.code,
        universel: canonique.universel, servant: canonique.servant,
      };
    }

    var code = entry.module || entry.code;
    /* Une page de saisie se ferme si le registre qu'elle alimente est fermé :
       sinon son adresse serait une porte dérobée. */
    if (entry.servant && INDEX[entry.servant] && entry.servant !== entry.id) {
      return can(roleId, INDEX[entry.servant]);
    }

    /* Une activité que la clinique n'exerce pas se ferme pour TOUS les rôles,
       administrateur compris : ce n'est pas une habilitation, et rien ne la
       rouvre — pas même une surcharge. */
    if (!ecranActif(entry.id, code)) return false;

    /* LA SURCHARGE DÉCIDE quand elle se prononce — dans les deux sens. Une
       matrice administrable qui ne saurait qu'enlever ne permettrait jamais
       de doter un rôle nouvellement créé : il n'apparaît dans aucune liste du
       manifeste, et resterait inutilisable quoi qu'on lui ouvre. */
    var explicite = surchargeExplicite(roleId, entry.id, code);
    if (explicite === false) return false;
    if (explicite === true) return true;

    /* Un écran UNIVERSEL est ouvert à tout poste — après `ecranActif` et
       après une surcharge explicite, qui gardent la main. */
    if (entry.universel) return true;

    /* Sans surcharge, le manifeste fait foi. */
    var permis = entry.roles === ALL || (entry.roles && entry.roles.indexOf(roleId) !== -1);
    if (!permis) return false;
    if (!code) return true;
    return droitsEcran(roleId, entry.id, code).voir;
  }

  /** Domaine contenant un écran donné — sert à ouvrir le bon onglet du ruban. */
  function domainOf(id) {
    var e = INDEX[id];
    return e ? e.domain : null;
  }

  /**
   * Arborescence filtrée par rôle : domaines > modules > écrans habilités.
   * Les domaines et modules entièrement interdits sont retirés, de sorte que le
   * méga-menu n'affiche jamais une colonne vide.
   */
  function tree(roleId) {
    return NAV.map(function (domain) {
      var modules = domain.modules.map(function (mod) {
        var items = mod.items.filter(function (it) {
          /* Un ALIAS s'évalue avec les droits de son écran CANONIQUE : lui
             donner les rôles de sa rangée d'accueil ouvrirait par le ruban ce
             que le manifeste ferme par ailleurs. */
          var ref = it.alias ? INDEX[it.id] : null;
          return can(roleId, {
            roles: ref ? ref.roles : (it.roles || mod.roles || ALL),
            module: ref ? ref.module : mod.code,
            id: it.id,
          });
        });
        return items.length
          ? { code: mod.code, label: mod.label, icon: mod.icon, hub: hubId(mod.code), items: items }
          : null;
      }).filter(Boolean);
      return modules.length ? { domain: domain.domain, icon: domain.icon, modules: modules } : null;
    }).filter(Boolean);
  }

  /** Module par son code (M6, MECEF…), enrichi de son domaine et de son hub. */
  function module(code) {
    var canonique = null, domaine = null, tous = [];
    NAV.forEach(function (dom) {
      dom.modules.forEach(function (mod) {
        if (mod.alias || mod.code !== code) return; /* la rangée canonique fait foi */
        /* Les rangées SECONDAIRES apportent leurs écrans au hub — sans quoi
           il n'en montrerait qu'une partie et l'on croirait le module
           amputé — mais c'est la rangée CANONIQUE qui le nomme et le situe. */
        tous = tous.concat(mod.items);
        if (mod.secondaire || canonique) return;
        canonique = mod; domaine = dom;
      });
    });
    if (!canonique) return null;
    return {
      code: canonique.code, label: canonique.label, icon: canonique.icon,
      roles: canonique.roles || ALL, items: tous,
      domain: domaine.domain, domainIcon: domaine.icon, hub: hubId(code),
    };
  }

  /** Modules mis en avant : les quatre postes de travail les plus fréquentés. */
  var RACCOURCIS = [
    { code: 'M1', court: 'Patients' },
    { code: 'M2', court: 'Consultations' },
    { code: 'M6', court: 'Pharmacie' },
    { code: 'M8', court: 'Facturation' },
  ];

  /* ==========================================================================
   * RUBRIQUES — le contenu des écrans, pour la recherche globale
   * --------------------------------------------------------------------------
   * Un écran ne se résume pas à son titre : chercher « actes » doit ouvrir le
   * référentiel tarifaire *sur son onglet Actes*, et non laisser l'utilisateur
   * le chercher à la main. Chaque rubrique déclare l'écran, l'onglet visé et
   * les mots que l'utilisateur emploiera réellement.
   *
   * Comme les entrées d'écran, ces rubriques vivent dans le manifeste : c'est
   * ici, et nulle part ailleurs, que se déclare un point d'entrée.
   * ======================================================================== */
  var RUBRIQUES = [
    { ecran: 'cfg-tarifs', onglet: 'produits', label: 'Produits & médicaments',
      motsCles: 'tarif prix médicament produit pharmacie prix d’achat prix de vente marge RG-02' },
    { ecran: 'cfg-tarifs', onglet: 'analyses', label: 'Analyses de laboratoire',
      motsCles: 'tarif prix analyse laboratoire biologie examen catalogue' },
    { ecran: 'cfg-tarifs', onglet: 'actes', label: 'Actes & hospitalisation',
      motsCles: 'acte actes soin chirurgie accouchement échographie consultation hospitalisation chambre tarif prix' },
    { ecran: 'cfg-natures-facture', onglet: null, label: 'Natures de facture',
      motsCles: 'nature facture type émission maternité observation consultation CPN spécialiste généraliste' },
    { ecran: 'cfg-centres-couts', onglet: null, label: 'Centres de coûts',
      motsCles: 'centre de coût analytique imputation service ventilation charge comptabilité' },
    { ecran: 'cfg-organisation', onglet: 'secteurs', label: 'Secteurs de la clinique (NS 145)',
      motsCles: 'secteur service responsable adjoint NS 145 répartition accueil maternité bloc laboratoire' },
    { ecran: 'cfg-organisation', onglet: 'organigramme', label: 'Organigramme et postes',
      motsCles: 'organigramme poste département hiérarchie effectif titulaire rattachement' },
    { ecran: 'cfg-systeme', onglet: 'corbeille', label: 'Corbeille — éléments archivés',
      motsCles: 'corbeille archive archivé restaurer restauration supprimé suppression RG-14' },
    { ecran: 'cfg-systeme', onglet: 'installation', label: 'Installation et données',
      motsCles: 'installation technique collection données version stockage maintenance réinitialiser' },
    { ecran: 'm5-resultats', onglet: 'attente', label: 'Résultats à saisir',
      motsCles: 'résultat analyse saisie attente laboratoire biologie' },
    { ecran: 'm5-resultats', onglet: 'valides', label: 'Résultats validés',
      motsCles: 'résultat validé compte rendu biologique laboratoire' },
    { ecran: 'm6-alertes', onglet: 'rupture', label: 'Ruptures de stock',
      motsCles: 'rupture stock zéro manquant alerte' },
    { ecran: 'm6-alertes', onglet: 'seuil', label: 'Produits sous le seuil',
      motsCles: 'seuil alerte réapprovisionnement stock minimum' },
    { ecran: 'm6-alertes', onglet: 'peremption', label: 'Péremptions',
      motsCles: 'péremption périmé expiration FEFO lot date limite RG-05' },
    { ecran: 'm8-paiements', onglet: 'aregler', label: 'Factures à encaisser',
      motsCles: 'encaisser encaissement paiement règlement caisse impayé à régler' },
    { ecran: 'm8-paiements', onglet: 'historique', label: 'Historique des règlements',
      motsCles: 'historique paiement règlement reçu encaissement' },
    { ecran: 'm9-compagnies', onglet: 'assures', label: 'Assurés d’une compagnie',
      motsCles: 'assuré assurance compagnie police souscripteur carte prise en charge' },
    { ecran: 'm9-compagnies', onglet: 'factures', label: 'Factures d’une compagnie',
      motsCles: 'facture assureur compagnie créance relevé' },
    { ecran: 'm12-balance', onglet: 'generale', label: 'Balance générale',
      motsCles: 'balance générale comptabilité syscohada solde débit crédit' },
    { ecran: 'm12-etats-financiers', onglet: 'bilan', label: 'Bilan',
      motsCles: 'bilan actif passif états financiers syscohada' },
    { ecran: 'm12-flux-tresorerie', label: 'Tableau des flux de trésorerie',
      motsCles: 'flux trésorerie tft cafg liasse feuillet cash flow financement investissement' },
    { ecran: 'm12-bfr', label: 'Besoin en fonds de roulement',
      motsCles: 'bfr besoin fonds roulement encours créances stocks dettes fournisseurs trésorerie dso' },
    { ecran: 'm12-cout-activite', label: 'Coût à l’activité',
      motsCles: 'coût activité cah consommables marge séjour acte analytique revient' },
    { ecran: 'm12-tableau-decisionnel', onglet: 'grille', label: 'Grille objectif / réel',
      motsCles: 'décisionnel objectif réel pilotage dso occupation rotation seuil alerte axes' },
    { ecran: 'm12-tableau-decisionnel', onglet: 'objectifs', label: 'Objectifs & seuils du pilotage',
      motsCles: 'objectifs seuils cibles alerte pilotage paramétrage direction' },
    { ecran: 'm2-imagerie-radiographie', label: 'Radiographie',
      motsCles: 'radio radiographie rx thorax bassin rachis fracture cliché' },
    { ecran: 'm2-imagerie-mammographie', label: 'Mammographie',
      motsCles: 'mammographie sein acr birads dépistage' },
    { ecran: 'm2-imagerie-scanner', label: 'Scanner',
      motsCles: 'scanner tdm tomodensitométrie injection contraste' },
    { ecran: 'm2-imagerie-irm', label: 'IRM',
      motsCles: 'irm résonance magnétique gadolinium séquences' },
    { ecran: 'mecef-transmission', onglet: 'attente', label: 'Transmissions MECeF en attente',
      motsCles: 'mecef transmission attente dgi normalisée fiscal' },
    { ecran: 'mecef-transmission', onglet: 'rejets', label: 'Rejets MECeF',
      motsCles: 'mecef rejet erreur transmission dgi' },
    { ecran: 'm6-dashboard', onglet: 'lots', label: 'Lots et FEFO',
      motsCles: 'lot fefo péremption numéro de lot traçabilité' },
    { ecran: 'm10-dashboard', onglet: 'primes', label: 'Primes (NS 132)',
      motsCles: 'prime garde permanence bloc accouchement NS 132 rémunération' },
    { ecran: 'm10-dashboard', onglet: 'planning', label: 'Planning du mois',
      motsCles: 'planning garde permanence repos roulement' },
    { ecran: 'm10-badges', onglet: 'badges', label: 'Badges émis',
      motsCles: 'badge carte professionnelle personnel identification port visible' },
    { ecran: 'm10-badges', onglet: 'retires', label: 'Badges retirés (perte, départ)',
      motsCles: 'badge perdu retiré perte vol départ restitution' },
    { ecran: 'm10-badges-verification', onglet: 'verifier', label: 'Vérifier un badge présenté',
      motsCles: 'vérifier badge contrôle qr numéro de série validité entrée' },
    { ecran: 'adm-enquetes', onglet: 'partage', label: 'Liens de partage d’une enquête',
      motsCles: 'enquête lien partage jeton qr questionnaire tiers public satisfaction' },
  ];

  global.SIGH = global.SIGH || {};
  global.SIGH.nav = {
    ROLES: ROLES,
    NAV: NAV,
    STANDALONE: STANDALONE,
    INDEX: INDEX,
    EXT: EXT,
    ALL: ALL,
    RACCOURCIS: RACCOURCIS,
    RUBRIQUES: RUBRIQUES,
    can: can,
    droits: droits,
    droitsEcran: droitsEcran,
    droitsOrigine: droitsOrigine,
    DROITS: DROITS,
    roleArchive: roleArchive,
    moduleActif: moduleActif, ecranActif: ecranActif, fermeturePour: fermeturePour,
    modulesDesactives: modulesDesactives,
    invaliderModules: invaliderModules,
    invaliderRbac: invaliderRbac,
    appliquerRenommages: appliquerRenommages,
    tree: tree,
    module: module,
    hubId: hubId,
    domainOf: domainOf,
    get: function (id) { return INDEX[id] || null; },
    ecranDesDroits: ecranDesDroits,
    ids: function () { return Object.keys(INDEX); },
  };

  /* Les rôles renommés le sont dès le chargement : tout ce qui lit
     N.ROLES[x].label — ruban, bandeau, impressions — suit sans le savoir. */
  appliquerRenommages();
})(window);
