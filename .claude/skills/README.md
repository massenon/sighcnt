# Skills SDLC du dépôt

Skills **locaux au dépôt** : quiconque clone `sighcnt` les a, sans rien installer. Ils encadrent le
cycle de développement de SIGH-CNT et écrivent tous dans `docs/`.

| Skill | Produit | Où |
|---|---|---|
| `/prd` | Document d'exigences produit d'un module ou d'une fonctionnalité | `docs/prd/PRD-<module>-<sujet>.md` |
| `/adr` | Décision d'architecture, numérotée, avec options et conséquences | `docs/architecture/adr/ADR-NNNN-<sujet>.md` |
| `/spec` | Spécification d'un écran ou d'un module : données, règles, RBAC, hors ligne, sondes | `docs/specs/SPEC-<écran>.md` |
| `/plan` | Plan d'implémentation découpé en étapes vérifiables | `docs/plans/PLAN-<sujet>.md` |
| `/test-plan` | Stratégie de vérification : scénarios, audit RBAC, coupures, synchronisation | `docs/plans/TESTS-<sujet>.md` |
| `/review` | Revue d'une modification contre les règles de gestion et les pièges connus | réponse en séance |
| `/release` | Liste de contrôle de livraison (schéma, migration, installeur, sauvegarde) | `docs/plans/RELEASE-<version>.md` |

Ordre habituel : `/prd` → `/adr` (si une décision structurante se pose) → `/spec` → `/plan` →
`/test-plan` → implémentation → `/review` → `/release`.

Les kits du catalogue claude.ai (`sdlc-kit`, `Agentic SDLC Kit`, `plan-review-skill`) complètent
ces skills ; ils ne les remplacent pas, parce qu'ils ignorent les règles RG-01→14 et la doctrine
du prototype que ceux-ci portent.
