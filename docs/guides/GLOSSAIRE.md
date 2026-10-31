# Glossaire SIGH-CNT

Vocabulaire du logiciel et du métier, **tel que la maquette l'emploie** (`prototype_html/`, `CLAUDE.md`). Un terme ne change pas de sens d'un écran à l'autre : si deux écrans le disent différemment, c'est un défaut à corriger, pas une variante à ajouter. Les définitions sont reprises des documents de cadrage ; ce qui est une proposition non validée est signalé.

## Organisation et produit

| Terme | Sens |
|---|---|
| **SIGH-CNT** | Système Intégré de Gestion Hospitalière de la CLINIQUE NASSIERA TOO SARL, Natitingou (Bénin). |
| **Maquette / prototype** | `prototype_html/` : l'application de référence (PHP + PostgreSQL, interface en JavaScript). Elle fait foi de ce que la cible doit faire ; elle est **gelée** (seules les corrections de défaut s'y appliquent). |
| **Cible** | Le produit à livrer : postes Flutter, poste mère, mobile, relais en ligne (`docs/architecture/`). |
| **CDCT** | Cahier des charges technique : référence contractuelle des modules M1–M14, des règles RG-01→14 et de la matrice RBAC. |
| **Module (M1…M14)** | Domaine fonctionnel : M1 Patients & DMI, M2 RDV/Visites/Consultations, M3 Hospitalisation, M4 Maternité, M5 Laboratoire, M6 Pharmacie & Stocks, M7 Achats, M8 Facturation/Caisse, M9 Assurances & Créances, M10 RH, M11 Paie, M12 Comptabilité SYSCOHADA, M13 Administration, M14 Sécurité. S'y ajoutent MECeF, GED, RAP (rapports), PIL (pilotage), CFG (configuration), DASH (tableaux de bord). |
| **Domaine / rangée / hub** | Onglet du ruban ; ligne de pastilles d'un module ; page d'accueil d'un module. |
| **Alias, rangée secondaire** | Une rangée *alias* réunit des écrans d'un autre module sans les dupliquer ; une rangée *secondaire* apporte des écrans canoniques à un module sans créer de second hub. |
| **Écran universel** | Écran ouvert à tout agent quel que soit son module (« exprimer un besoin »). Il ne cède que devant une surcharge **d'écran** explicite. |
| **Servant** | Page de saisie qui hérite des droits du **registre** qu'elle alimente. |

## Architecture cible

| Terme | Sens |
|---|---|
| **Poste fileul** | Application Flutter desktop d'un poste de travail : base locale chiffrée, file d'envoi, synchronise avec la mère. |
| **Poste mère** | Poste Flutter (mode *mère*) sur le serveur local : **service** (HTTP + PostgreSQL + synchronisation) et **console** (DAF/administrateur). Seule autorité. |
| **Relais en ligne** | Serveur Laravel sur cPanel, **opaque** : stocke des enveloppes chiffrées, des indicateurs sans nom, le battement de cœur ; panneau superadmin minimal. |
| **Mobile** | Application Flutter minimale ; passe **uniquement** par le relais. Profils *soignant* (consultations à domicile) et *réception de secours*. |
| **Journal d'opérations** | Suite ordonnée des gestes d'écriture (créer, modifier, archiver, restaurer, sortie) ; l'ordre est la séquence (`seq`) posée par la mère, jamais l'horloge d'un poste. |
| **Famille de fusion (A, B, C, D, R)** | A fiche descriptive (fusion par champ) · B journal append-only · C pièce émise immuable · D agrégat à invariant · R référentiel (la mère seule écrit). |
| **Bail** | Quota par article alloué par la mère à un poste, consommable hors ligne : jamais de stock négatif. |
| **Plage de numéros** | Intervalle de codes réservé à un poste ; épuisé hors ligne, le poste utilise un numéro **provisoire** réconcilié à l'arrivée. |
| **Époque (`epoch`)** | Entier incrémenté par une restauration ou une réinitialisation ; un envoi d'une époque inconnue est refusé (409). |
| **Enveloppe** | Message chiffré de bout en bout (AES-256-GCM) déposé au relais ; le relais ne voit que appareil, sens, rang, taille. |
| **Clé de clinique** | Clé de chiffrement des enveloppes ; sa perte rend relais et sauvegardes irrécupérables → copie papier sous scellé (détenteur **à désigner**). |
| **Battement de cœur** | Signal minute de la mère au relais ; s'il manque plus de 5 min, le relais alerte. |
| **Lot de tournée** | Dossiers déposés par la mère dans la boîte d'un mobile pour la journée ; il expire. |
| **« À traiter »** | Écran d'un appareil listant les opérations refusées, avec la cause nommée et le geste de correction. |

## Règles de gestion

Voir [`docs/specs/REGLES-GESTION.md`](../specs/REGLES-GESTION.md) (engendré). Rappels : **RG-01** code patient `CNT/[n°]/[année]`, jamais modifié · **RG-02** médicaments au prix d'achat sans marge · **RG-03** sortie de stock justifiée, jamais négatif · **RG-09** couverture d'assurance valide **à la date** · **RG-10** écriture équilibrée avant validation · **RG-12** aucune action anonyme · **RG-13** cloisonnement RBAC · **RG-14** archivage, jamais suppression physique.

## Métier

| Terme | Sens |
|---|---|
| **CNT** | Préfixe du code patient (Clinique NASSIERA TOO). |
| **CPN / CPoN** | Consultation prénatale / postnatale. |
| **SONU, SONUB, SONUC** | Soins obstétricaux et néonatals d'urgence (de base / complets) : 10 fonctions (7 + 3). |
| **PF (A/N)** | Planification familiale, 15 méthodes ; **A** = nouvelle acceptante, codification officielle des registres papier. |
| **PTME** | Prévention de la transmission mère-enfant (4 volets). |
| **IPPOA** | Examen physique : inspection, palpation, percussion, auscultation. |
| **ASA, Mallampati** | Échelles de la consultation pré-anesthésique — *propositions à valider par les praticiens du bloc* (marquées). |
| **CRO / CRA / CPA** | Compte rendu opératoire / d'anesthésie / consultation pré-anesthésique. |
| **Biologiste médical** | Libellé du rôle d'identifiant technique `laborantin` (on ne renomme pas un identifiant technique). |
| **MECeF** | Module d'émission de factures normalisées (Bénin). La clinique utilise le **boîtier physique**, branché à la **caisse** ; le numéro fiscal vient toujours du boîtier. Protocole non documenté (10 questions au fournisseur/DGI). |
| **IFU / RCCM** | Identifiant fiscal unique 3201642748214 / registre du commerce RB/NAT/2016-B-268 — **un seul en-tête légal** sur toutes les pièces (arbitrage du 31/08/2026). |
| **AIB** | Acompte sur impôt sur les bénéfices (1 % dans le calcul du net à payer MECeF). |
| **CUMP** | Coût unitaire moyen pondéré. |
| **FEFO** | First Expired, First Out : rangement et sortie par péremption. |
| **SYSCOHADA** | Plan comptable (93 comptes) ; classes 1–5 bilan, 6–7 gestion. |
| **À-nouveaux (AN)** | Report des soldes de bilan (classes 1–5) à l'exercice suivant ; jamais les comptes de gestion. |
| **Avoir** | Pièce qui corrige une facture émise : une pièce émise ne se réécrit jamais. |
| **Tarif provisoire / arrêté** | Tarif d'attente (valeur d'essai) / arrêté par la Direction ; l'écran le dit. |
| **NS 131 / NS 132 / NS 145** | Notes de service : évaluation et sanctions / primes / secteurs de la clinique. |
| **ORTB** | Redevances annuelles : Radio 1 000 F (tous) + Télé 3 000 F (> 60 000 F brut), cumulées. |
| **BFR** | Besoin en fonds de roulement : créances + stocks − dettes fournisseurs. |
| **Six secteurs** | Laboratoire · Pharmacie · Consultation · Échographie/imagerie médicale · Maternité · Hospitalisation et soins (+ Direction, transverse). |
