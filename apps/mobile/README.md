# apps/mobile — application Flutter mobile (version minimale)

Deux profils sur la même application (spec §11) :

| Profil | Contenu |
|---|---|
| **Soignant** | agenda du jour, dossier en lecture, constantes, notes, prescription selon droits, **consultation à domicile** |
| **Réception de secours** | module Réception seulement, utilisable quand les postes fileuls sont hors service ; ni caisse, ni comptabilité, ni stock |

**Jamais sur le réseau local** : le mobile échange **uniquement par le relais** (`apps/web`), en enveloppes
**chiffrées de bout en bout** (clé de clinique), avec un lot préparé par la mère (tournée du jour), base chiffrée,
PIN/biométrie, expiration du lot. Android d'abord.

## Profil soignant (état du 31/10/2026)

| Écran | Source |
|---|---|
| **Agenda du jour** | rendez-vous du lot du jour (`mobAgendaDuJour`), les planifiés d'un jour passé signalés à part |
| **Dossier en lecture** | identité, couverture à la date (RG-09), allergies, motif, dernières constantes hors bornes, notes, prescriptions |
| **Constantes** | bornes et messages de l'écran du simulateur (`mobReglesConstantes`) |
| **Note de consultation** | motif, anamnèse, quatre temps de l'examen, diagnostic, orientation de la fiche ; les constantes du jour sont reprises |
| **Prescription selon droits** | médicaments, analyses ; commande ABSENTE sans habilitation (`D.CAPACITES`) ; refus nommés refaits au moteur, puis par la mère |
| **À traiter** | refus de la mère : code, motif, geste |

### La suite du simulateur (01/11/2026, E1650 à E1668)

| Écran | Profil | Source |
|---|---|---|
| **Visite prénatale (CPN)**, **post-natale (CPoN)**, **surveillance mère-bébé** | sage-femme, depuis le dossier de la patiente | `mob_suite.dart` (`mobErreursCpn`, `mobChampsCpn`…) ; une ligne de journal par geste (`cpn`, `cpon`, `surveillances`) |
| **Orienter un patient** | réception de secours | listes de la page ; ligne de journal `orientations` au nom de l'agent |
| **Lot de tournée** | profils cliniques (absent de la réception) | état, validité restante, expiration, rafraîchir |
| **Réglages** | tous | profil, agent, garanties vraies, réinitialisation de l'appairage (refusée tant que des saisies ne sont pas parties) |
| **Code PIN** | tous, au démarrage et après 5 minutes d'inactivité | `mob_pin.dart` (règle de la page), port `CoffrePin`, `CoffrePinSecurise` (haché PBKDF2) |

Parité N1 mesurée contre les pages du simulateur : `test/parite_mobile_test.dart` (162/162, exclusions nommées en tête du test).
Limite à connaître : le coffre du système, la biométrie et SQLCipher n'ont pas été exercés sur un appareil (E1658).

Chaque geste est UNE opération `creer` (aucune suppression, RG-14), nommée à l'agent (RG-12). Les règles sont dans `packages/domaine/lib/src/mobile/`
(jamais recopiées ici) ; le service `lib/moteur/service_soignant.dart` n'importe pas Flutter.

```bash
cd apps/mobile && flutter pub get && flutter analyze && flutter test            # 68 tests, dont 2 bouts en bout contre le banc (e2e_banc_test.dart, e2e_suite_test.dart)
SIGH_E2E_MERE=dart flutter test test/e2e_banc_test.dart                          # idem avec la mère Dart (packages/sync_dart/construire.sh mere)
cd ../.. && npm run banc:sync                                                    # scénario R25 : le même parcours côté protocole
```

Limites (ECARTS-MAQUETTE E1570 à E1573) : base SQLite en clair (SQLCipher non branché), aucun build Android, ni PIN, ni coffre, ni push.
Écarts de contenu avec la maquette : E1550 à E1566.

Référence du protocole : `packages/sync/banc/` (scénarios mobile : `packages/sync/banc/README.md`).
