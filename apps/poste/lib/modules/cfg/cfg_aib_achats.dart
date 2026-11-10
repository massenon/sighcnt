import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../donnees/aib_poste.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'cfa_commun.dart';

/// Le pendant poste de l'écran « Barème de l'AIB » de la maquette (onglets « Réglages » et « Achats à écrire », lot L2, Direction du 09/11/2026). Les quatre réglages se
/// règlent aux cartes de la famille « AIB » juste au-dessus (mêmes règles : rôle, compte au plan, motif, date postérieure, activation complète) ; cette section
/// dit l'état de la charge des 5 % et du branchement, et liste CE QUE LE BRANCHEMENT ÉCRIRAIT sur les factures fournisseurs. Désactivé (défaut), le moteur liste et
/// n'écrit RIEN ; actif, la commande « Écrire » pose en brouillon une pièce équilibrée par facture listée, rien d'autre.
class SectionAibAchats extends StatefulWidget {
  const SectionAibAchats({super.key, required this.c, required this.estMere});
  final ContexteEcran c;
  final bool estMere;

  @override
  State<SectionAibAchats> createState() => _EtatSectionAibAchats();
}

class _EtatSectionAibAchats extends State<SectionAibAchats> {
  AibPoste _aib() {
    final c = widget.c;
    return AibPoste(c.magasin,
        auteur: () => c.agent.nom.isEmpty ? 'Utilisateur' : c.agent.nom,
        role: c.role,
        libelleRole: c.donnees?.matrice.libelle(c.role) ?? c.role,
        fileul: !widget.estMere,
        horloge: () => c.aujourdhui);
  }

  String _lib(Object? iso) => iso == null || '$iso'.isEmpty ? '' : aibDateFr('$iso');

  void _ecrire(AibPoste aib, Map<String, Object?> ap) {
    final r = aib.ecrire(du: '${ap['du']}', au: '${ap['au']}');
    if (r['ok'] != true) {
      ToastsSigh.afficher(context, '${r['code']} : ${r['motif']}', type: TypeToast.erreur, detail: '${r['geste'] ?? ''}', duree: const Duration(seconds: 12));
      return;
    }
    final n = (r['pieces'] as List).length;
    setState(() {});
    ToastsSigh.afficher(context, '$n pièce(s) posée(s) en brouillon, équilibrées.', type: TypeToast.succes);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final aib = _aib();
    return ListenableBuilder(
        listenable: Listenable.merge([for (final n in const ['parametres', 'ecritures', 'facturesFournisseurs', 'fournisseurs', 'comptes']) c.magasin.collection(n)]),
        builder: (ctx, _) {
          final d = aib.donnees();
          final charge = aibChargeALaDate(d, aib.aujourdhui);
          final ap = aib.apercu();
          final br = ap['branchement'] as Map<String, Object?>;
          final lignes = (ap['lignes'] as List).cast<Map<String, Object?>>();
          final actif = ap['ecrire'] == true;
          final peutEcrire = widget.estMere && c.droit.editer && aibRolesEcriture.contains(c.role);
          return cfaPile([
            NoteSigh(
                charge['ok'] == true
                    ? 'Qui supporte les 5 % : ${charge['libelle']}${charge['arrete'] == true ? '' : ' (réglage non arrêté)'}. ${charge['message'] ?? 'Réglage arrêté.'} Aucun effet comptable n’en découle : la valeur à la date est portée par chaque vente et listée aux achats.'
                    : '${charge['code']} : ${charge['motif']}',
                ton: charge['ok'] == true && charge['arrete'] == true ? TonSigh.info : TonSigh.attention,
                icone: LucideIcons.scale),
            NoteSigh(
                'Branchement sur les achats : ${br['actif'] == true ? 'actif' : 'désactivé'}. ${br['actif'] == true ? 'Le moteur écrit ce qui est listé ci-dessous.' : 'Le moteur liste ce qu’il faudrait écrire et n’écrit rien. L’activation exige les deux comptes et la charge arrêtés, et un motif.'}',
                ton: br['actif'] == true ? TonSigh.succes : TonSigh.info,
                icone: LucideIcons.plug),
            NoteSigh('${ap['message']}', ton: actif ? TonSigh.succes : TonSigh.attention, icone: actif ? LucideIcons.circleCheck : LucideIcons.info),
            NoteSigh(
                'Base : le montant facturé (la fiche fournisseur ne distingue pas le hors taxes). Situation du fournisseur d’après son IFU ; un fournisseur sans IFU relève de la situation « sans IFU actif ». Une ligne sans taux au barème porte son refus et n’a pas de montant.',
                ton: TonSigh.info),
            MiniTableauSigh(
                vide: 'Aucune facture fournisseur sur la période.',
                colonnes: [
                  ColonneMini('Facture', (l) => '${l['reference']}', rendu: (l) => cfaCode(l['reference'])),
                  ColonneMini('Date', (l) => _lib(l['date'])),
                  ColonneMini('Fournisseur', (l) => '${l['fournisseur']}'),
                  ColonneMini('IFU', (l) => '${l['ifu'] ?? '—'}'),
                  ColonneMini('Situation', (l) => l['refus'] != null ? '${l['refus']}' : '${l['situation']}',
                      rendu: (l) => l['refus'] != null ? BadgeSigh('${l['refus']}', ton: TonSigh.attention) : Text('${l['situation']}')),
                  ColonneMini('Taux', (l) => l['refus'] != null ? '—' : '${l['taux']} %', droite: true),
                  ColonneMini('Base', (l) => money(l['base'], avecDevise: false), droite: true),
                  ColonneMini('AIB', (l) => l['refus'] != null ? '—' : money(l['aib'], avecDevise: false), droite: true),
                  ColonneMini('Supporté par', (l) => l['supporte'] == null ? '—' : '${l['supporte'] == 'clinique' ? 'La clinique' : 'L’acheteur'}${l['chargeArretee'] == true ? '' : ' (non arrêté)'}'),
                  ColonneMini('Pièce', (l) => l['ecriteSous'] == null ? 'Non écrite' : '${l['ecriteSous']}',
                      rendu: (l) => l['ecriteSous'] == null ? cfaDiscret('Non écrite') : BadgeSigh('${l['ecriteSous']}', ton: TonSigh.succes)),
                ],
                lignes: lignes),
            if (actif && peutEcrire)
              Align(
                  alignment: Alignment.centerLeft,
                  child: BoutonSigh(
                      libelle: 'Écrire ${nombre(ap['aEcrire'])} pièce(s) en brouillon', icone: LucideIcons.penLine, taille: TailleBouton.sm, onPressed: () => _ecrire(aib, ap))),
          ], espace: 12);
        });
  }
}
