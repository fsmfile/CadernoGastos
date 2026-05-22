# Caderno de Gastos

PWA leve para registro compartilhado de gastos de viagem, com sincronização via Google Sheets.

**Versão atual:** 1.3.0

## Funcionalidades

- 🗺️ **Múltiplas viagens** — cada uma com orçamento e gastos isolados
- 💰 **Saldo em tempo real** — separado em conta (débito) e crédito, com barras de progresso
- 📒 Registro de gastos com local, item, valor, data, categoria e tipo
- 🏷️ 12 categorias pré-cadastradas com emojis
- ☁️ Sincronização automática com planilha do Google compartilhada
- 🔐 Sistema de aprovação de remoções entre os dois usuários
- 📱 Funciona offline (PWA com service worker)
- 🍎 Instalável no iOS e Android como app nativo

## Como instalar e usar

### 1. Hospedar

A forma mais simples é usar **GitHub Pages**:

1. Em `Settings → Pages` deste repositório
2. Em "Source", escolha **Deploy from a branch**
3. Branch: `main` / pasta `/ (root)`
4. Salve. Em ~1 minuto seu app estará em `https://fsmfile.github.io/CadernoGastos/`

### 2. Criar a planilha do Google

1. Vá em [sheets.new](https://sheets.new) e crie uma planilha em branco
2. Compartilhe com a outra pessoa
3. **Extensões → Apps Script**
4. Apague o conteúdo padrão e cole o script disponível no app (botão "Copiar" no menu ⚙️)
5. Salve e clique em **Implantar → Nova implantação**
6. Tipo: **App da Web** · Acesso: **Qualquer pessoa**
7. Copie a URL gerada

### 3. Configurar no celular

#### iPhone (iOS)
1. Abra o link **no Safari** (não no Chrome — só o Safari instala PWA no iOS)
2. Botão Compartilhar (□↑) → **Adicionar à Tela de Início**
3. Abra pelo ícone na tela inicial
4. ⚙️ → cole a URL do Apps Script, digite seu nome → Salvar

#### Android (S23 Ultra ou outros)
1. Abra o link no Chrome
2. Menu (⋮) → **Adicionar à tela inicial** (ou "Instalar app")
3. ⚙️ → cole a URL do Apps Script, digite seu nome → Salvar

## Estrutura

```
├── index.html              App completo (HTML + CSS + JS)
├── manifest.webmanifest    Manifest do PWA
├── sw.js                   Service Worker (offline)
├── icon.svg                Ícone vetorial
├── icon-192.png            Ícone Android (home screen)
├── icon-512.png            Ícone Android (splash screen)
├── apple-touch-icon.png    Ícone iOS (180x180)
└── favicon-32.png          Favicon do navegador
```

## Stack

Tudo client-side: HTML + CSS + Vanilla JS. Sem build, sem dependências, sem framework. O backend é um Google Apps Script ligado à planilha — gratuito e sem limite prático para uso pessoal.

## Histórico de versões

- **1.3.0** — Múltiplas viagens com orçamento próprio + saldo em tempo real (débito/crédito)
- **1.2.0** — PWA completo (manifest, service worker, ícones, offline)
- **1.1.1** — Correção do botão "Copiar" do código do Apps Script
- **1.1.0** — Sistema de aprovação de remoções entre dois usuários
- **1.0.0** — Lançamento inicial com categorias, datas e sincronização

## Licença

Uso pessoal.
