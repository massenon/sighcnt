# ADR-0009 : Satisfaction en ligne, exception PUBLIQUE du relais, aveugle par chiffrement dans le navigateur

Statut : **accepté le 16/11/2026** (décisions de la Direction, `docs/decisions/DECISIONS-A-VALIDER.md` section AQ points 14 et 16 : « la proposition du point 14 est VALIDÉE »). Les modalités chiffrées (algorithmes, tailles, limites) sont une proposition technique du lot SAT, à confirmer à la recette.
Date : 2026-11-16
Concerne : relais web (apps/web), poste mère (packages/sync_dart), domaine (`qual_en_ligne`), poste (`adm-enquetes`, `adm-satisfaction`).

## Contexte

Jusqu'ici le relais n'avait AUCUNE page publique (`/` renvoyait au panneau superadmin) et ne recevait que des enveloppes d'appareils appairés. La Direction veut qu'un patient réponde à un questionnaire de satisfaction sur son téléphone, par un code QR ou une adresse personnalisée de `sighcnt.nassieratoo.com`, et que les réponses redescendent à la mère puis aux fileuls pour l'analyse. Le lien « maquetté » du PRD (`PRD-SATISFACTION-collecte-web-qr-et-analyse.md`) laissait la collecte locale à la machine.

Contraintes qui ne bougent pas : ce n'est **pas un portail patient** (CDCT §4.3, hors périmètre) ; **aucun nom ni numéro de dossier** n'est demandé ; le texte médical ne quitte jamais la clinique ; un relais piraté ne doit lire aucune réponse.

## Options

1. **Page publique qui écrit en clair chez l'hébergeur** (base du relais lisible). Écartée : un relais compromis lirait tous les commentaires libres (qui peuvent contenir des données personnelles).
2. **Réponse transmise en clair à la mère par un canal direct.** Écartée : la mère n'est pas joignable depuis Internet (architecture hors ligne d'abord).
3. **Chiffrement DANS LE NAVIGATEUR par la clé publique de la clinique, dépôt d'un bloc opaque au relais** (retenue).

## Décision

**Une exception publique, bornée, aveugle.** Le relais gagne deux surfaces et rien d'autre :

- **Publiques, sans cookie ni session** : `GET /s/{jeton}` (le formulaire) et `POST /s/{jeton}` (dépôt d'une enveloppe). Un jeton inconnu, expiré ou révoqué reçoit **une seule réponse générique** (404, aucune enquête nommée). Le relais ne connaît un jeton que par son **empreinte SHA-256**.
- **Réservées à la mère** (en-tête `x-mere`) : `POST /satisfaction/publier` (clé publique, liens anonymes avec leur questionnaire) et `GET /satisfaction/releve` (enveloppes après un curseur). Un appareil appairé reçoit **403 `satisfaction_reservee_mere`**.

**Enveloppe (version 1).** Le navigateur tire une paire X25519 éphémère, calcule le secret avec la clé publique de la clinique, dérive la clé par **HKDF-SHA-256** (sel = clé éphémère puis clé publique de la clinique, info `sigh-satisfaction-v1`) et chiffre en **AES-256-GCM** (vecteur de 12 octets, **donnée associée = identifiant de la réponse**). Le texte clair est **rembourré** à 1, 2, 4 ou 8 Kio (deux octets de longueur, puis zéros) : la taille du chiffré ne révèle ni la longueur d'un commentaire ni l'absence d'un commentaire au-delà de ces quatre paliers. L'enveloppe est `{v, id, epk, iv, ct}` ; elle fait **16 Kio au plus**.

**Clé de la clinique.** La paire X25519 est **dérivée de la clé de la clinique** (déjà détenue par la mère, jamais envoyée) par HKDF : aucun secret de plus à sauvegarder, la perte de la clé de la clinique est déjà le cas traité par le projet. Seule la **clé publique** est publiée au relais. Sans la clé privée, aucune enveloppe n'est lisible, par le relais comme par quiconque.

**Ce que le relais vérifie, et rien de plus** : forme de l'enveloppe (version, identifiant de 32 hexadécimaux, clé éphémère de 32 octets, vecteur de 12 octets, texte chiffré d'une des quatre tailles), taille, **débit** (10 réponses par empreinte d'adresse par 10 minutes ; l'empreinte est un HMAC effacé avec la fenêtre, jamais l'adresse), **champ piège** (rempli : succès apparent, rien de stocké), **200 liens au plus**, anti-rejeu par identifiant unique (la seconde réception est acceptée sans effet).

**Ce que la mère vérifie, après ouverture** (domaine `qual_en_ligne`, 15 refus nommés) : la forme, le lien (connu, non révoqué, non expiré à la date de réception), la cohérence enquête, version et point avec le lien (l'attribution vient du lien que le relais a vu, jamais d'une déclaration du navigateur : n'importe qui peut chiffrer pour la clé publique), les questions, les bornes, et **tout champ d'identité** (nom, prénom, téléphone, courriel, dossier, patient) est refusé.

**Données.** `reponsesEnquetes` (famille B, identité `REPW-<id>`), `jetonsEnquete` (famille A), jamais vers un téléphone. Le questionnaire est une donnée versionnée par date ; une réponse garde la version sous laquelle elle a été donnée.

## Conséquences

- Le relais n'est plus muet côté Internet : il faut un nom d'hôte public, TLS, et la limite de débit en dépend de l'adresse vue (derrière un mandataire, régler les mandataires de confiance).
- Une réponse en ligne est lue après coup (la mère doit être allumée) ; les enveloppes attendent au relais, jamais purgées (RG-14).
- Le navigateur doit offrir WebCrypto avec X25519 (Chrome 133, Firefox 130, Safari 17 ou plus récents). **Sur un navigateur plus ancien la page le dit** (message nommé) ; aucun repli en JavaScript n'est livré (non vérifié sur les téléphones du terrain, à mesurer).
- Rien n'est chiffré côté « signature » : un tiers qui connaît un lien peut répondre (c'est le but) ; la protection contre l'abus est le débit, le champ piège, le plafond de liens, la révocation. Le taux de réponse n'est « non calculable » tant que les passages à l'accueil ne sont pas comptés.
- Hors lot : mode kiosque hors ligne (file locale chiffrée), langues autres que le français, alertes par SMS.
