; Instalador do painel Configurar Câmeras (só o painel: motor, servidor, página).
; Gerado por instalador\Gerar-Instalador.ps1, que roda os testes e confere a
; lista de arquivos antes de chamar o ISCC. A lista de [Files] é explícita de
; propósito: senha.local.ps1 (e qualquer *.local.ps1) nunca pode entrar.

; A versão vem de fonte\VERSAO.txt (única fonte; o painel mostra o mesmo
; número e a tag do GitHub tem que bater). /DVersao=x.y.z no ISCC tem precedência.
#ifndef Versao
  #define ArqVersao FileOpen(AddBackslash(SourcePath) + "..\fonte\VERSAO.txt")
  #define Versao Trim(FileRead(ArqVersao))
  #expr FileClose(ArqVersao)
#endif
#define Nome "Configurar Câmeras"
#define Raiz ".."

[Setup]
AppId={{7D3A9C2E-5B1F-4E8A-9C6D-2F1B3A4C5D6E}
AppName={#Nome}
AppVersion={#Versao}
AppVerName={#Nome} {#Versao}
AppPublisher=Grupo Smart Seg Engenharia
AppPublisherURL=https://github.com/xyron-robotics/ConfigurarCameras
AppUpdatesURL=https://github.com/xyron-robotics/ConfigurarCameras/releases
VersionInfoVersion={#Versao}
VersionInfoProductVersion={#Versao}
DefaultDirName={autopf}\ConfigurarCameras
DefaultGroupName={#Nome}
DisableProgramGroupPage=yes
PrivilegesRequired=admin
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17134
OutputDir=saida
OutputBaseFilename=ConfigurarCameras-{#Versao}-instalador
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayName={#Nome}
SetupIconFile=icone.ico
UninstallDisplayIcon={app}\icone.ico
; A pasta de dados (%ProgramData%\ConfigurarCameras: registro, padrões, log)
; não é tocada na desinstalação: é a única cópia do que foi feito.

[Languages]
Name: "brazilianportuguese"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"

[Tasks]
Name: "desktopicon"; Description: "Criar atalho na área de trabalho"; GroupDescription: "Atalhos:"

[Files]
Source: "{#Raiz}\fonte\Motor-Cameras.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#Raiz}\fonte\VERSAO.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#Raiz}\fonte\INICIAR-PAINEL.vbs"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#Raiz}\fonte\INICIAR-PAINEL-COM-CONSOLE.bat"; DestDir: "{app}"; Flags: ignoreversion
Source: "icone.ico"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#Raiz}\fonte\web\Servidor-Painel.ps1"; DestDir: "{app}\web"; Flags: ignoreversion
Source: "{#Raiz}\fonte\web\www\index.html"; DestDir: "{app}\web\www"; Flags: ignoreversion
Source: "{#Raiz}\fonte\web\www\app.js"; DestDir: "{app}\web\www"; Flags: ignoreversion
Source: "{#Raiz}\fonte\web\www\app.css"; DestDir: "{app}\web\www"; Flags: ignoreversion
Source: "{#Raiz}\LEIA-ME.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#Raiz}\fonte\API-INTELBRAS.md"; DestDir: "{app}"; Flags: ignoreversion

; O atalho abre o .vbs pelo wscript: sem janela de console, so o UAC e o painel.
; Sobras de versões anteriores que não existem mais no pacote.
[InstallDelete]
Type: files; Name: "{app}\INICIAR-PAINEL.bat"

[Icons]
Name: "{group}\{#Nome}"; Filename: "{sys}\wscript.exe"; Parameters: """{app}\INICIAR-PAINEL.vbs"""; WorkingDir: "{app}"; IconFilename: "{app}\icone.ico"; Comment: "Abre o painel (pede Administrador)"
Name: "{group}\Leia-me"; Filename: "{app}\LEIA-ME.md"
Name: "{autodesktop}\{#Nome}"; Filename: "{sys}\wscript.exe"; Parameters: """{app}\INICIAR-PAINEL.vbs"""; WorkingDir: "{app}"; IconFilename: "{app}\icone.ico"; Tasks: desktopicon

[Run]
Filename: "{sys}\wscript.exe"; Parameters: """{app}\INICIAR-PAINEL.vbs"""; WorkingDir: "{app}"; Description: "Abrir o painel agora"; Flags: postinstall nowait skipifsilent
; Atualização pelo painel: ele roda este instalador com /VERYSILENT /REABRIR=1
; e se fecha; esta linha reabre o painel (oculto) quando a instalação termina.
Filename: "{sys}\wscript.exe"; Parameters: """{app}\INICIAR-PAINEL.vbs"""; WorkingDir: "{app}"; Flags: nowait; Check: ParamReabrir

[Code]
// /REABRIR=1 na linha de comando (atualização pelo painel): reabre o painel no fim.
function ParamReabrir(): Boolean;
begin
  Result := ExpandConstant('{param:REABRIR|0}') = '1';
end;

// curl.exe é o único transporte até a câmera. Vem no Windows 10 1803+ e no
// Windows 11; sem ele o painel não serve para nada.
function InitializeSetup(): Boolean;
begin
  Result := True;
  if not FileExists(ExpandConstant('{sys}\curl.exe')) then
  begin
    MsgBox('Este Windows não tem o curl.exe (vem no Windows 10 1803 ou mais novo e no Windows 11). ' +
           'O painel precisa dele para falar com a câmera.', mbError, MB_OK);
    Result := False;
  end;
end;
