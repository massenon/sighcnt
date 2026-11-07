# Hub de clinique

Cible : un mini-serveur Linux sur onduleur, Docker Compose avec PostgreSQL 16, `apps/hub`
(synchronisation, invariants, RBAC serveur, tranches de numéros, audit chaîné), passerelle MECeF,
sauvegardes (`pg_dump` chiffré + réplica hors site), serveur de mises à jour des postes.

À produire en P3/P4 : `docker-compose.yml`, `PRA.md` (procédure de reprise : restauration +
rejeu des journaux des postes), scripts de sauvegarde et de restauration à blanc.
