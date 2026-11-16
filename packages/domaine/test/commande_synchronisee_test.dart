import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

/// LOT CMD : la commande de stock gros voyage. Règles pures : identité par le contenu, référence provisoire puis définitive, refus au rejeu d'une validation écrite directement,
/// décision signée (dépôt et application sous le rôle de l'auteur).
typedef M = Map<String, Object?>;

M commande({String ref = 'BC-2026-0001', String statut = 'attente_validation', Object? par, String fournisseur = 'F1', String date = '2026-11-16', num q = 10}) => {
      'id': 'COM1',
      'reference': ref,
      'fournisseur': fournisseur,
      'date': date,
      'statutCommande': statut,
      if (par != null) 'valideePar': par,
      'lignes': [
        {'produitId': 'P1', 'quantite': q, 'prixUnitaire': 100},
        {'produitId': 'P2', 'quantite': 5, 'prixUnitaire': 40},
      ],
    };

final signe = DateTime.utc(2026, 11, 16, 9, 30);
final comptes = [
  {'id': 'U1', 'statut': 'actif', 'nom': 'Mme DAF', 'role': 'da'},
  {'id': 'U2', 'statut': 'actif', 'nom': 'M. STOCK', 'role': 'gestionnaire_stock'},
];

void main() {
  test('identité par le contenu : même fournisseur, jour et lignes (ordre indifférent) = même identité ; le numéro n\'y entre pas ; une ligne change = autre commande', () {
    final a = identiteSyncCommande(commande(ref: 'BC-2026-P1-0001'))!;
    final b = identiteSyncCommande({...commande(ref: 'BC-2026-P2-0007'), 'lignes': (commande()['lignes'] as List).cast<M>().reversed.toList(), 'date': '2026-11-16T08:00'})!;
    expect(a, startsWith('CMD-'));
    expect(b, a);
    expect(identiteSyncCommande(commande(q: 11)), isNot(a));
    expect(identiteSyncCommande({...commande(), 'lignes': <M>[]}), isNull, reason: 'jamais une identité inventée');
  });

  test('référence provisoire par poste (année de la pièce), rang par poste ; définitive par la mère : plus grand rang définitif de l\'année + 1, les provisoires ne comptent pas', () {
    final jour = DateTime(2026, 11, 16);
    final deja = [commande(ref: 'BC-2027-P1AB-0001')];
    expect(referenceCommandeProvisoire(date: '2027-01-02', poste: 'f-1ab', commandes: deja, maintenant: jour), 'BC-2027-PF1AB-0001', reason: 'poste normalisé, autre poste : rang 1');
    expect(referenceCommandeProvisoire(date: '2027-01-02', poste: 'P1AB', commandes: deja, maintenant: jour), 'BC-2027-PP1AB-0001');
    expect(referenceCommandeProvisoire(date: '2027-01-02', poste: '1AB', commandes: deja, maintenant: jour), 'BC-2027-P1AB-0002');
    expect(referenceCommandeProvisoire(date: '2026-12-31', poste: '1AB', commandes: deja, maintenant: jour), 'BC-2026-P1AB-0001', reason: 'le compteur repart chaque année');
    expect(estReferenceCommandeProvisoire('BC-2027-P1AB-0001'), isTrue);
    expect(estReferenceCommandeProvisoire('BC-2027-0001'), isFalse);
    expect(estReferenceCommandeDefinitive('BC-2026-0412'), isTrue);
    expect(referenceCommandeDefinitive('BC-2026-PF1-0001', ['BC-2026-0001', 'BC-2026-0004', 'BC-2025-0099', 'BC-2026-PF2-0009', 'ANCIEN']), 'BC-2026-0005');
    expect(referenceCommandeDefinitive('BC-2027-PF1-0001', ['BC-2026-0004']), 'BC-2027-0001');
    expect(referenceCommandeDefinitive('BC-2026-0005', ['BC-2026-0005']), isNull, reason: 'une référence définitive ne se réécrit jamais');
  });

  test('rejeu à la mère : une validation écrite directement est refusée (nommée), une commande validée ne change pas de validateur, le circuit d\'une validée reste libre', () {
    final avant = commande();
    expect(refusRejeuValidationCommande(avant, {...avant, 'statutCommande': 'validee', 'valideePar': 'Mme DAF', 'dateValidation': '2026-11-16'})!.code, 'COMMANDE_VALIDATION_DIRECTE');
    expect(refusRejeuValidationCommande(null, {...avant, 'statutCommande': 'transmise'})!.code, 'COMMANDE_VALIDATION_DIRECTE', reason: 'créée déjà « transmise » : refusée aussi');
    expect(refusRejeuValidationCommande(avant, {...avant, 'montant': 12})?.code, isNull, reason: 'une autre correction passe');
    final validee = {...avant, 'statutCommande': 'validee', 'valideePar': 'Mme DAF', 'dateValidation': '2026-11-16'};
    expect(refusRejeuValidationCommande(validee, {...validee, 'statutCommande': 'transmise'}), isNull);
    expect(refusRejeuValidationCommande(validee, {...validee, 'valideePar': 'Autre'})!.code, 'COMMANDE_VALIDATION_FIGEE');
    expect(refusRejeuValidationCommande(avant, {...avant, 'valideePar': 'Mme DAF'})!.code, 'COMMANDE_VALIDATION_DIRECTE', reason: 'un validateur seul suffit à être refusé');
  });

  test('dépôt : sans droit refusé nommé, jamais deux décisions en attente, la cible est l\'identité de synchronisation', () {
    final c = {...commande(), 'idSync': 'CMD-abc'};
    VerdictDepotValidation depot(bool geste, {List<M> demandes = const []}) => commandeDeposerValidation(
        commande: c, role: 'da', acteur: 'Mme DAF', maintenant: signe, gesteAccorde: geste, libelleRole: 'Directrice Administrative', valideurs: 'Directrice Administrative', demandes: [...demandes]);
    final sans = depot(false);
    expect(sans.ok, isFalse);
    expect(sans.refus!.code, 'VALIDATION_COMMANDE_RESERVEE');
    final ok = depot(true);
    expect(ok.ok, isTrue);
    expect(ok.fiche!['famille'], valFamilleCommandeStock);
    expect(ok.fiche!['cible'], 'CMD-abc');
    expect(ok.fiche!['etat'], valEtatDeposee);
    expect(depot(true, demandes: [ok.fiche!]).refus!.code, 'DEMANDE_DEJA_DEPOSEE');
    final deja = commandeDeposerValidation(
        commande: commande(statut: 'validee', par: 'X'), role: 'da', acteur: 'Mme DAF', maintenant: signe, gesteAccorde: true, libelleRole: 'DAF', valideurs: 'DAF', demandes: const []);
    expect(deja.refus!.code, 'COMMANDE_DEJA_VALIDEE');
  });

  test('application par la mère : sous le rôle de l\'auteur, datée de la signature ; sans droit, compte inconnu, commande inconnue ou déjà validée : refus nommé ; rejeu sans effet', () {
    final dep = commandeDeposerValidation(
        commande: {...commande(), 'idSync': 'CMD-abc'}, role: 'da', acteur: 'Mme DAF', maintenant: signe, gesteAccorde: true, libelleRole: 'DAF', valideurs: 'DAF', demandes: const []).fiche!;
    ApplicationValidationCommande? applique(M d, {Iterable<M>? cmds, bool geste = true, Iterable<M>? cpt}) => commandeAppliquerDemande(d,
        maintenant: DateTime.utc(2026, 11, 16, 18),
        commandes: cmds ?? [{...commande(), 'idSync': 'CMD-abc'}],
        gesteDe: (r) => geste && r == 'da',
        libelleRole: (r) => r,
        valideurs: 'DAF',
        comptes: cpt ?? comptes);
    final ok = applique(dep)!;
    expect(ok.ok, isTrue);
    expect(ok.patch!['statutCommande'], 'validee');
    expect(ok.patch!['valideePar'], 'Mme DAF', reason: 'le nom de l\'AUTEUR, pas celui de la mère');
    expect(ok.patch!['dateValidation'], signe.toLocal().toIso8601String().substring(0, 10), reason: 'la date de la SIGNATURE');
    expect(ok.champsDemande['etat'], valEtatAppliquee);
    expect(ok.commandeId, 'COM1');
    final sans = applique(dep, geste: false)!;
    expect(sans.ok, isFalse);
    expect(sans.champsDemande['resultatCode'], 'VALIDATION_COMMANDE_RESERVEE');
    expect(applique({...dep, 'demandePar': 'Inconnu'})!.champsDemande['resultatCode'], 'SIGNATAIRE_INCONNU');
    expect(applique({...dep, 'cible': 'CMD-zzz'})!.champsDemande['resultatCode'], 'COMMANDE_INCONNUE');
    expect(applique(dep, cmds: [commande(statut: 'validee', par: 'X')..['idSync'] = 'CMD-abc'])!.champsDemande['resultatCode'], 'COMMANDE_DEJA_VALIDEE');
    expect(applique({...dep, 'etat': valEtatAppliquee}), isNull, reason: 'idempotence : une demande déjà traitée ne se retraite jamais');
  });
}
