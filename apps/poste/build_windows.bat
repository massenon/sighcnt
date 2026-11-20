@echo off
rem =============================================================================
rem  SIGH-CNT Poste : construit l'installateur Windows.
rem  Usage :  build_windows.bat
rem  Resultat : build\installer\SIGH_Poste_Setup_<version>.exe  (+ .sha256)
rem  S'arrete a la PREMIERE etape qui echoue, en la nommant.
rem  Prerequis : Flutter (Desktop Windows), Visual Studio 2022 (C++), Inno Setup 6.
rem  PRD : docs/prd/PRD-POSTE-installateur-windows.md
rem =============================================================================
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"

set "EXE=sigh_poste.exe"
set "SORTIE=build\windows\x64\runner\Release"

echo.
echo [1/9] Prerequis
where flutter >nul 2>&1 || ( echo ECHEC : flutter est introuvable dans le PATH. & goto :echec )
set "ISCC="
where ISCC.exe >nul 2>&1 && set "ISCC=ISCC.exe"
if not defined ISCC if exist "%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe" set "ISCC=%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe"
if not defined ISCC if exist "%ProgramFiles%\Inno Setup 6\ISCC.exe" set "ISCC=%ProgramFiles%\Inno Setup 6\ISCC.exe"
if not defined ISCC if exist "%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe" set "ISCC=%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe"
if not defined ISCC ( echo ECHEC : Inno Setup 6 est introuvable ^(ISCC.exe^). Installez-le : https://jrsoftware.org/isdl.php & goto :echec )
echo   flutter : OK ^| ISCC : %ISCC%

echo.
echo [2/9] Fermeture de l'application ^(un sqlite3.dll verrouille ferait echouer le build^)
taskkill /F /IM %EXE% >nul 2>&1
taskkill /F /IM flutter_tester.exe >nul 2>&1
echo   OK

echo.
echo [3/9] Version ^(source unique : pubspec.yaml^)
set "VERSION="
for /f "usebackq delims=" %%V in (`powershell -NoProfile -Command "$m = Select-String -Path 'pubspec.yaml' -Pattern '^version:\s*([0-9]+\.[0-9]+\.[0-9]+)' | Select-Object -First 1; if ($m) { $m.Matches[0].Groups[1].Value }"`) do set "VERSION=%%V"
if not defined VERSION ( echo ECHEC : aucune ligne "version: x.y.z" lisible dans pubspec.yaml. & goto :echec )
echo   version : %VERSION%

echo.
echo [4/9] flutter pub get
call flutter pub get || ( echo ECHEC : flutter pub get. & goto :echec )

echo.
echo [5/9] Generation de code ^(build_runner^)
findstr /R /C:"^  build_runner:" pubspec.yaml >nul 2>&1
if errorlevel 1 (
  echo   build_runner n'est pas declare dans pubspec.yaml : etape sautee.
) else (
  call dart run build_runner build || ( echo ECHEC : dart run build_runner build. & goto :echec )
)

echo.
echo [6/9] flutter build windows --release
call flutter build windows --release || ( echo ECHEC : flutter build windows --release. Fermez l'application et tout flutter_tester, puis relancez. & goto :echec )

echo.
echo [7/9] Runtime Visual C++ ^(un poste neuf peut ne pas l'avoir : l'application ne demarrerait pas, sans message^)
for %%D in (msvcp140.dll vcruntime140.dll vcruntime140_1.dll) do (
  if not exist "%SystemRoot%\System32\%%D" ( echo ECHEC : %%D est introuvable dans %SystemRoot%\System32. Installez le "Microsoft Visual C++ Redistributable 2015-2022 x64". & goto :echec )
  copy /Y "%SystemRoot%\System32\%%D" "%SORTIE%\" >nul || ( echo ECHEC : copie de %%D vers %SORTIE%. & goto :echec )
  echo   %%D copiee
)

echo.
echo [8/9] Verification des fichiers a installer ^(le premier absent est nomme^)
for %%F in ("%SORTIE%\%EXE%" "%SORTIE%\flutter_windows.dll" "%SORTIE%\sqlite3.dll" "%SORTIE%\data\app.so" "%SORTIE%\data\icudtl.dat" "%SORTIE%\data\flutter_assets" "windows\runner\resources\app_icon.ico" "installer\sigh_poste.iss") do (
  if not exist %%F ( echo ECHEC : fichier ou dossier manquant : %%~F & goto :echec )
)
echo   OK

echo.
echo [9/9] Installateur ^(Inno Setup^)
"%ISCC%" /Qp /DAppVersion=%VERSION% installer\sigh_poste.iss || ( echo ECHEC : la compilation Inno Setup a echoue ^(voir le message ci-dessus^). & goto :echec )

set "SETUP=build\installer\SIGH_Poste_Setup_%VERSION%.exe"
if not exist "%SETUP%" ( echo ECHEC : %SETUP% n'a pas ete produit. & goto :echec )
for /f "usebackq delims=" %%H in (`powershell -NoProfile -Command "(Get-FileHash -Algorithm SHA256 '%SETUP%').Hash.ToLower()"`) do set "SHA=%%H"
> "%SETUP%.sha256" echo !SHA!  SIGH_Poste_Setup_%VERSION%.exe
for %%S in ("%SETUP%") do set "TAILLE=%%~zS"

echo.
echo ============================================================
echo  TERMINE : %SETUP%
echo  Taille  : !TAILLE! octets
echo  SHA-256 : !SHA!
echo ============================================================
endlocal
exit /b 0

:echec
echo.
echo *** CONSTRUCTION INTERROMPUE ***
endlocal
exit /b 1
