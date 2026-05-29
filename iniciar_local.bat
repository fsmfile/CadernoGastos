@echo off
title Fluxy - Servidor Local

echo ===================================================================
echo                   FLUXY - INICIALIZADOR LOCAL
echo ===================================================================
echo.
echo [*] Detectando ferramentas no ambiente para rodar o PWA...
echo.

:: 1. Tentar Node.js
where node >nul 2>nul
if %errorlevel% equ 0 (
    echo [OK] Node.js detectado!
    echo [i] Iniciando servidor local com 'http-server'
    echo [i] Caching desativado para evitar problemas com Service Worker.
    echo [i] O navegador deve abrir automaticamente em http://localhost:8080
    echo [!] Para parar o servidor, feche esta janela ou pressione Ctrl+C.
    echo.
    npx -y http-server -p 8080 -c-1 -o
    goto end
)

:: 2. Tentar Python
where python >nul 2>nul
if %errorlevel% equ 0 (
    echo [OK] Python detectado!
    echo [i] Iniciando servidor com 'python -m http.server'
    echo [i] Abrindo o navegador em http://localhost:8080
    echo [!] Para parar o servidor, feche esta janela ou pressione Ctrl+C.
    echo.
    start http://localhost:8080
    python -m http.server 8080
    goto end
)

:: 3. Caso nenhum esteja disponível
echo [!] AVISO: Node.js ou Python nao foram detectados no PATH do sistema.
echo [!] Sem um servidor HTTP, recursos de PWA e Service Worker sw.js
echo     podem nao carregar corretamente por restricoes do navegador.
echo.
echo [i] Abrindo o arquivo index.html diretamente no navegador como fallback...
echo.
start index.html

:end
echo.
echo ===================================================================
echo [OK] Processo concluido ou servidor encerrado.
echo ===================================================================
pause
