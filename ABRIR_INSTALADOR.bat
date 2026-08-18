@echo off
title Instalador del gestor de publicaciones
cd /d "%~dp0"

where node >nul 2>nul
if errorlevel 1 (
  echo.
  echo Node.js no esta instalado.
  echo Instalalo y vuelve a ejecutar este archivo.
  echo.
  pause
  exit /b 1
)

if not exist node_modules (
  echo.
  echo Preparando el instalador...
  call npm install
  if errorlevel 1 (
    echo.
    echo No se pudieron instalar las dependencias.
    pause
    exit /b 1
  )
)

echo.
echo Abriendo el asistente...
call npm run asistente

pause
