@echo off
REM Abre o painel web do ConfigurarCameras COM a janela de console (diagnostico):
REM a mensagem de erro fica na tela ate apertar Enter. O atalho normal e o
REM INICIAR-PAINEL.vbs, sem console. Pede Administrador (UAC) uma vez:
REM preparar a placa de rede do PC exige.
title Painel - Configurar Cameras
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0web\Servidor-Painel.ps1" %*
if errorlevel 1 pause
