# PRD — documents d'exigences produit

Un PRD par module ou par fonctionnalité, produit par `/prd`, nommé `PRD-<module>-<sujet>.md`.
Chaque exigence cite sa source dans `docs/cadrage/` ; ce qui n'a pas de source est une proposition
à valider, et le dit. Section « Hors ligne et synchronisation » obligatoire.

| PRD | Objet | Statut |
|---|---|---|
| [PRD-M12-cloture-exercice](PRD-M12-cloture-exercice.md) | Clôture d'exercice (résultat, à-nouveaux au solde et ligne à ligne), sélecteur d'exercice, lecture seule des exercices clos, exercices ouverts simultanés, N / N-1, archive | brouillon 20/10/2026 |
| [PRD-M6-suivi-ventes-secteurs](PRD-M6-suivi-ventes-secteurs.md) | Point des ventes détaillé par patient et par secteur ; « Imagerie médicale » remplace « Échographie » comme secteur de recette | brouillon 20/10/2026 |
| [PRD-SOCLE-application-sans-rechargement](PRD-SOCLE-application-sans-rechargement.md) | Document unique (routeur, modules paresseux, hydratation unique + deltas), flux d'événements entre postes, notifications consommatrices, planificateur de tâches serveur | brouillon 20/10/2026 |
| [PRD-SOCLE-synchronisation-bidirectionnelle](PRD-SOCLE-synchronisation-bidirectionnelle.md) | Synchronisation dans les deux sens entre postes, hub, client web et mobile : opérations, familles de fusion, conflits nommés, archivage au lieu de suppression, numéros provisoires, hors ligne | brouillon 26/10/2026 |
| [PRD-FLUTTER-poste-fidelite-maquette](PRD-FLUTTER-poste-fidelite-maquette.md) | Poste Flutter desktop 100 % fidèle à la maquette : définition mesurable de la fidélité (écrans, règles, droits, visuel, impression), tranches verticales, banc de validation | brouillon 26/10/2026 |

Ordre de livraison recommandé : SOCLE (P0) → M6 → M12, le socle rendant les deux autres plus
simples à sonder (pas de rechargement entre les étapes d'un parcours).
