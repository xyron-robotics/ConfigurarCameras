' Abre o painel Configurar Cameras SEM janela de console: so o pedido do
' Windows (UAC) e a janela do painel aparecem. Erro na subida vira uma caixa
' de mensagem. Para ver o console (diagnostico), use INICIAR-PAINEL-COM-CONSOLE.bat.
' Argumentos passados aqui vao para o Servidor-Painel.ps1 (ex. -PastaDados D:\obra).
Option Explicit
Dim sh, pasta, args, i
Set sh = CreateObject("WScript.Shell")
pasta = Left(WScript.ScriptFullName, InStrRev(WScript.ScriptFullName, "\"))
args = ""
For i = 0 To WScript.Arguments.Count - 1
    args = args & " """ & WScript.Arguments(i) & """"
Next
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & pasta & "web\Servidor-Painel.ps1"" -Oculto" & args, 0, False
