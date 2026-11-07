# PRD — documents d'exigences produit

Un PRD par module ou par fonctionnalité, produit par `/prd`, nommé `PRD-<module>-<sujet>.md`.
Chaque exigence cite sa source dans `docs/cadrage/` ; ce qui n'a pas de source est une proposition
à valider, et le dit. Section « Hors ligne et synchronisation » obligatoire.

| PRD | Objet | Statut |
|---|---|---|
| [PRD-M12-cloture-exercice](PRD-M12-cloture-exercice.md) | Clôture d'exercice (résultat, à-nouveaux au solde et ligne à ligne), sélecteur d'exercice, lecture seule des exercices clos, exercices ouverts simultanés, N / N-1, archive | brouillon 20/10/2026 |
| [PRD-M12-selecteur-exercice-barre-superieure](PRD-M12-selecteur-exercice-barre-superieure.md) | Sélecteur d'exercice dans la barre supérieure (session, écrans à année, dates relatives), trois états, clôture par pièces CL et AN, réouverture par contre-passation, archive immuable ; complète le PRD de clôture du 20/10 | brouillon 05/11/2026 |
| [PRD-M6-suivi-ventes-secteurs](PRD-M6-suivi-ventes-secteurs.md) | Point des ventes détaillé par patient et par secteur ; « Imagerie médicale » remplace « Échographie » comme secteur de recette | brouillon 20/10/2026 |
| [PRD-SOCLE-application-sans-rechargement](PRD-SOCLE-application-sans-rechargement.md) | Document unique (routeur, modules paresseux, hydratation unique + deltas), flux d'événements entre postes, notifications consommatrices, planificateur de tâches serveur | brouillon 20/10/2026 |
| [PRD-SOCLE-synchronisation-bidirectionnelle](PRD-SOCLE-synchronisation-bidirectionnelle.md) | Synchronisation dans les deux sens entre postes, hub, client web et mobile : opérations, familles de fusion, conflits nommés, archivage au lieu de suppression, numéros provisoires, hors ligne | brouillon 26/10/2026 |
| [PRD-FLUTTER-poste-fidelite-maquette](PRD-FLUTTER-poste-fidelite-maquette.md) | Poste Flutter desktop 100 % fidèle à la maquette : définition mesurable de la fidélité (écrans, règles, droits, visuel, impression), tranches verticales, banc de validation | brouillon 26/10/2026 |
| [PRD-POSTE-premiere-installation](PRD-POSTE-premiere-installation.md) | Première installation du poste (premier compte, modale de configurations, activation de la mère, appairage du relais, des fileuls et des mobiles), rejoindre une clinique, barre des tâches et logo | arrêté 02/11/2026 |
| [PRD-RELAIS-copie-consultable](PRD-RELAIS-copie-consultable.md) | Relais opaque mais consultable : la mère dépose une copie chiffrée de la base, le navigateur la déchiffre avec la clé de clinique (option B) | proposé 05/11/2026 |
| [PRD-POSTE-installateur-windows](PRD-POSTE-installateur-windows.md) | Installateur Windows du poste : `build_windows.bat` + Inno Setup, identifiant fixe, données hors du dossier d'installation, désinstallation avec sauvegarde et avertissement Non par défaut | proposé 05/11/2026 |

| [PRD-SMS-passerelle-et-test-envoi](PRD-SMS-passerelle-et-test-envoi.md) | Passerelle SMS (Vonage et Twilio) réglable et testable : écran de configuration et Test SMS (maquette, poste, relais), secrets tenus par le relais, journal des envois, consentement, matrice des canaux enfin exécutée | proposé 07/11/2026 |

| [PRD-RELAIS-en-ligne-consultation-et-configuration](PRD-RELAIS-en-ligne-consultation-et-configuration.md) | Relais en ligne : consultation à règles métier complètes (option A relais opaque ou B relais en clair, décision Q1 bloquante), configuration et journal d'opérations conservés sans exception, restauration depuis le relais seul | proposé 07/11/2026 |

| [PRD-SATISFACTION-collecte-web-qr-et-analyse](PRD-SATISFACTION-collecte-web-qr-et-analyse.md) | Satisfaction des patients : collecte par lien et QR à l'accueil, enveloppes scellées par le relais, kiosque hors ligne, questionnaires avancés, analyse complète (filtres avancés, NPS, alertes, modération, exports) | proposé 07/11/2026 |

| [PRD-MECEF-facturation-normalisee-deux-modes](PRD-MECEF-facturation-normalisee-deux-modes.md) | Facturation normalisée MECeF : deux modes (boîtier CC300 au poste, e-MECeF en ligne par le relais) choisis par réglage, montants entiers, reprise sans doublon fiscal, avoirs, secrets au panneau ; la documentation remise vient d'autres projets | proposé 07/11/2026 |

Ordre de livraison recommandé : SOCLE (P0) → M6 → M12, le socle rendant les deux autres plus
simples à sonder (pas de rechargement entre les étapes d'un parcours).
| `PRD-M10-planning-individuel-et-libre-service-agent.md` | Planning et gardes individuels (régime propre à un agent, historique daté), filtres avancés, CRUD du planning, espace « Mes » de l'agent (17 rubriques, mobile et poste, validation DAF) et revue d'écarts des écrans | proposé le 06/11/2026 |
