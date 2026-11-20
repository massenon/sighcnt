; =============================================================================
;  SIGH-CNT Poste : installateur Windows (Inno Setup 6)
;
;  Compile par build_windows.bat, qui passe la version lue dans pubspec.yaml :
;      ISCC.exe /DAppVersion=0.1.0 installer\sigh_poste.iss
;  Produit : build\installer\SIGH_Poste_Setup_<version>.exe
;
;  Installe TOUT le dossier de sortie de `flutter build windows --release`
;  (build\windows\x64\runner\Release\) dans {autopf}\SIGH-CNT. Droits
;  administrateur (decision de la Direction, 05/11/2026, Q3).
;
;  Les DONNEES ne sont JAMAIS dans le dossier d'installation :
;    %LOCALAPPDATA%\SIGHCNT\donnees  (base, magasin, cle de chiffrement, sauvegardes de la mere)
;  (lib/core/dossier_donnees.dart). Une MISE A JOUR (meme AppId) n'y touche jamais.
;
;  DESINSTALLATION (decision de la Direction, 05/11/2026, Q1) :
;    1. une sauvegarde est proposee d'abord (Documents\SIGH-CNT-Sauvegarde-AAAA-MM-JJ_HHMM,
;       jamais supprimee par le desinstallateur) ;
;    2. un avertissement Oui / Non, « Non » par defaut ; Non ANNULE la desinstallation ;
;    3. les donnees ne sont supprimees que sur « Oui » ;
;    4. en mode silencieux (/SILENT, /VERYSILENT), les donnees sont GARDEES.
;  Les exports faits par l'utilisateur (dossier Telechargements) ne sont pas touches.
; =============================================================================

#ifndef AppVersion
  #define AppVersion "0.1.0"
#endif

#define AppName "SIGH-CNT Poste"
#define AppPublisher "Clinique Nassiera Too"
#define AppExeName "sigh_poste.exe"
#define SetupBaseName "SIGH_Poste_Setup"
#define SourceDir AddBackslash(SourcePath) + "..\build\windows\x64\runner\Release"
#define IconFile AddBackslash(SourcePath) + "..\windows\runner\resources\app_icon.ico"

#if !FileExists(SourceDir + "\" + AppExeName)
  #error "Executable absent : lancez d'abord flutter build windows --release (build_windows.bat le fait)."
#endif

[Setup]
; Identifiant FIXE de l'application : NE JAMAIS LE CHANGER. C'est lui qui fait
; qu'une nouvelle version REMPLACE l'ancienne au lieu de s'installer a cote.
AppId={{9765A5AC-1B97-4E82-A6EA-207654C34C64}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
VersionInfoVersion={#AppVersion}
VersionInfoCompany={#AppPublisher}
VersionInfoProductName={#AppName}
DefaultDirName={autopf}\SIGH-CNT
DefaultGroupName=SIGH-CNT
DisableProgramGroupPage=yes
OutputDir=..\build\installer
OutputBaseFilename={#SetupBaseName}_{#AppVersion}
#if FileExists(IconFile)
SetupIconFile={#IconFile}
#endif
UninstallDisplayIcon={app}\{#AppExeName}
UninstallDisplayName={#AppName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
; Flutter Windows ne produit que du x64.
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
; Une mise a jour ferme l'application ouverte avant de remplacer ses fichiers.
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "french"; MessagesFile: "compiler:Languages\French.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{group}\{cm:UninstallProgram,{#AppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Seulement si l'utilisateur a repondu Oui a l'avertissement (SupprimerLesDonnees, pose par InitializeUninstall).
Type: filesandordirs; Name: "{localappdata}\SIGHCNT"; Check: SupprimerLesDonnees

[Code]
var
  SupprimerDonnees: Boolean;

function SupprimerLesDonnees(): Boolean;
begin
  Result := SupprimerDonnees;
end;

// Copie un dossier (sous-dossiers compris) ; un dossier source absent n'est pas une erreur (rien a sauvegarder).
function CopierDossier(Source, Cible: String): Boolean;
var
  Code: Integer;
begin
  if not DirExists(Source) then
  begin
    Result := True;
    Exit;
  end;
  Result := Exec(ExpandConstant('{cmd}'),
    '/C xcopy "' + Source + '" "' + Cible + '\" /E /I /H /Y /Q', '', SW_HIDE, ewWaitUntilTerminated, Code)
    and (Code = 0);
end;

// Le poste est ferme d'abord (une base ouverte ne se copie pas de facon coherente), puis copie horodatee dans Documents.
function SauvegarderAvantSuppression(var Dossier: String): Boolean;
var
  Code: Integer;
begin
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /IM {#AppExeName}', '', SW_HIDE, ewWaitUntilTerminated, Code);
  Dossier := ExpandConstant('{userdocs}\SIGH-CNT-Sauvegarde-') + GetDateTimeString('yyyy/mm/dd_hhnn', '-', #0);
  Result := ForceDirectories(Dossier)
    and CopierDossier(ExpandConstant('{localappdata}\SIGHCNT'), Dossier + '\donnees-du-poste');
end;

// Sauvegarde proposee (Oui par defaut), puis avertissement Oui / Non (Non par defaut). Non ANNULE la desinstallation.
function InitializeUninstall(): Boolean;
var
  Dossier: String;
begin
  Result := True;
  SupprimerDonnees := False;
  // Silencieux : aucune question possible, donc aucune suppression.
  if UninstallSilent then
    Exit;

  if MsgBox(
    'Voulez-vous faire une SAUVEGARDE de ce poste avant de continuer ?' + #13#10 + #13#10 +
    'Elle sera enregistree dans votre dossier Documents (SIGH-CNT-Sauvegarde-...) et ne sera pas supprimee.',
    mbConfirmation, MB_YESNO or MB_DEFBUTTON1) = IDYES then
  begin
    if SauvegarderAvantSuppression(Dossier) then
      MsgBox('Sauvegarde terminee :' + #13#10 + Dossier, mbInformation, MB_OK)
    else if MsgBox(
      'La sauvegarde a echoue (espace disque ou acces refuse).' + #13#10 + #13#10 +
      'Continuer QUAND MEME vers la desinstallation ?',
      mbError, MB_YESNO or MB_DEFBUTTON2) <> IDYES then
    begin
      Result := False;
      Exit;
    end;
  end;

  if MsgBox(
    'Desinstaller {#AppName} supprimera aussi TOUTES les donnees de ce poste :' + #13#10 +
    '  - la base locale (comptes, patients, factures, stocks, comptabilite...)' + #13#10 +
    '  - la cle de chiffrement du poste' + #13#10 +
    '  - la configuration du poste (mode, appairage, adresse de la mere)' + #13#10 +
    '  - les sauvegardes de la mere stockees dans ce dossier' + #13#10 + #13#10 +
    'Les saisies NON ENCORE SYNCHRONISEES seront PERDUES, definitivement. ' +
    'Sur un poste MERE, cette base est la copie de reference de la clinique : les postes fileuls ne la reconstituent pas entierement.' + #13#10 + #13#10 +
    'Cette action est irreversible. Voulez-vous desinstaller et supprimer ces donnees ?' + #13#10 + #13#10 +
    'Oui : tout supprimer.     Non : annuler la desinstallation.',
    mbError, MB_YESNO or MB_DEFBUTTON2) = IDYES then
    SupprimerDonnees := True
  else
    Result := False;
end;
