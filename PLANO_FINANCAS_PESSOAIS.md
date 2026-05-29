# Plano de Implementação — Módulo de Finanças Pessoais

## 1. Contexto e Objetivo

Transformar o app **Caderno de Gastos** (atualmente focado em viagens) em um **controle financeiro pessoal completo**, replicando a lógica da planilha `dados_antigos/Finanças.xlsx`.

### O que a planilha faz hoje (referência)

A planilha possui **uma aba por ano** (ex: `2022_Fabio`, `2023_Fabio`) com a seguinte estrutura:

| Seção | Linhas | Descrição |
|-------|--------|-----------|
| **Entradas** | 3–10 | Fontes de renda por mês (Salário, Sal Extra, Empresa, Outros) + Saldo Mês Anterior |
| **Saídas** | 13–31 | Despesas fixas e variáveis por mês (Casa, Condomínio, NET, Celular, Cartões, Empréstimo, Uber, Pets, etc.) |
| **Total Saída** | 31 | Soma das saídas de cada mês |
| **Saldo** | 32 | Saldo acumulado = Entrada − Saída (carrega mês a mês) |
| **Saldo total mês** | 34 | Entrada − Saída daquele mês isolado |
| **Saldo Cheque Especial** | 36 | Limite de cheque especial + saldo |
| **Resumo Anual** | 37–39 | Créditos no ano, Débitos no ano, Saldo no ano |

#### Características-chave da planilha:
1. **Meses futuros preenchidos** — Despesas fixas já têm valor para todos os 12 meses
2. **Valores variáveis por mês** — Cartões de crédito com parcelas decrescentes
3. **Entradas não-fixas** — Salário Extra (13º, bônus) e Outros (recebíveis esporádicos)
4. **Projeção** — Os meses futuros mostram o saldo projetado
5. **Saldo mês anterior transportado** — Acumulado cascateado mês a mês
6. **Cheque especial** — Limite de crédito que complementa o saldo

---

## 2. Arquitetura de Dados (Supabase)

### 2.1. Nova migração: `005_financas_pessoais.sql`

Criar as seguintes tabelas no schema existente:

```sql
-- =====================================================================
-- TABELA: lancamentos_financeiros
-- Representa TODAS as linhas da planilha (entradas e saídas)
-- =====================================================================
CREATE TABLE IF NOT EXISTS lancamentos_financeiros (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  carteira_id     UUID NOT NULL REFERENCES carteiras(id) ON DELETE CASCADE,
  
  -- Identificação
  descricao       TEXT NOT NULL,                       -- "Sal. Fabio", "Casa", "Card NuBank"
  tipo            TEXT NOT NULL CHECK (tipo IN ('entrada', 'saida')),
  categoria       TEXT NOT NULL DEFAULT 'outros',      -- agrupamento livre
  
  -- Recorrência
  recorrencia     TEXT NOT NULL DEFAULT 'fixo'
                  CHECK (recorrencia IN ('fixo', 'variavel', 'unico', 'parcelado')),
  -- 'fixo'      → mesmo valor todo mês (salário, aluguel)
  -- 'variavel'  → valor muda por mês (cartão de crédito, uber)
  -- 'unico'     → só aparece em um mês (viagem, 13o)
  -- 'parcelado' → parcelas com valor e quantidade definidos
  
  -- Valores
  valor_padrao    NUMERIC(12, 2) NOT NULL DEFAULT 0,   -- valor padrão mensal (para 'fixo')
  
  -- Parcelamento (quando recorrencia = 'parcelado')
  parcelas_total  INT,
  parcela_atual   INT,
  
  -- Período de vigência
  mes_inicio      INT NOT NULL DEFAULT 1,              -- mês início (1-12)
  ano_inicio      INT NOT NULL,                        -- ano início
  mes_fim         INT,                                 -- mês fim (NULL = indefinido/ativo)
  ano_fim         INT,                                 -- ano fim
  
  -- Ordenação visual
  ordem           INT NOT NULL DEFAULT 0,
  
  -- Controle
  ativo           BOOLEAN NOT NULL DEFAULT TRUE,
  criado_em       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  atualizado_em   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =====================================================================
-- TABELA: lancamento_valores_mes
-- Valor REAL de cada lançamento em cada mês/ano
-- Para 'fixo': gerado automaticamente a partir de valor_padrao
-- Para 'variavel'/'unico': preenchido manualmente
-- Para 'parcelado': calculado a partir do valor e parcelas
-- =====================================================================
CREATE TABLE IF NOT EXISTS lancamento_valores_mes (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  lancamento_id     UUID NOT NULL REFERENCES lancamentos_financeiros(id) ON DELETE CASCADE,
  mes               INT NOT NULL CHECK (mes BETWEEN 1 AND 12),
  ano               INT NOT NULL,
  valor             NUMERIC(12, 2) NOT NULL DEFAULT 0,
  observacao        TEXT,                              -- nota livre (ex: "parcela 3/10")
  realizado         BOOLEAN NOT NULL DEFAULT FALSE,    -- se o valor já foi efetivado
  criado_em         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  
  UNIQUE(lancamento_id, mes, ano)
);

-- =====================================================================
-- TABELA: saldo_inicial
-- Saldo da conta no início de um período (equivale a "Saldo Mês Anterior")
-- =====================================================================
CREATE TABLE IF NOT EXISTS saldo_inicial (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  carteira_id     UUID NOT NULL REFERENCES carteiras(id) ON DELETE CASCADE,
  mes             INT NOT NULL CHECK (mes BETWEEN 1 AND 12),
  ano             INT NOT NULL,
  valor           NUMERIC(12, 2) NOT NULL DEFAULT 0,
  criado_em       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  
  UNIQUE(carteira_id, mes, ano)
);

-- =====================================================================
-- TABELA: config_financeira
-- Configurações gerais (cheque especial, meta de poupança, etc.)
-- =====================================================================
CREATE TABLE IF NOT EXISTS config_financeira (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  carteira_id     UUID NOT NULL REFERENCES carteiras(id) ON DELETE CASCADE,
  chave           TEXT NOT NULL,                       -- 'cheque_especial', 'meta_mensal', etc.
  valor           TEXT NOT NULL,                       -- valor como texto (flexível)
  criado_em       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  
  UNIQUE(carteira_id, chave)
);
```

### 2.2. Índices

```sql
CREATE INDEX idx_lanc_carteira ON lancamentos_financeiros(carteira_id);
CREATE INDEX idx_lanc_tipo ON lancamentos_financeiros(tipo);
CREATE INDEX idx_lanc_ativo ON lancamentos_financeiros(ativo);
CREATE INDEX idx_valmes_lancamento ON lancamento_valores_mes(lancamento_id);
CREATE INDEX idx_valmes_periodo ON lancamento_valores_mes(ano, mes);
CREATE INDEX idx_saldo_carteira_periodo ON saldo_inicial(carteira_id, ano, mes);
```

### 2.3. RLS (Row Level Security)

Seguir o mesmo padrão da migração `002_carteiras.sql`:

```sql
ALTER TABLE lancamentos_financeiros ENABLE ROW LEVEL SECURITY;
ALTER TABLE lancamento_valores_mes  ENABLE ROW LEVEL SECURITY;
ALTER TABLE saldo_inicial           ENABLE ROW LEVEL SECURITY;
ALTER TABLE config_financeira       ENABLE ROW LEVEL SECURITY;

-- Políticas: membros da carteira têm acesso completo
CREATE POLICY "Members access lancamentos"
  ON lancamentos_financeiros FOR ALL TO authenticated
  USING    (carteira_id IN (SELECT auth_carteiras()))
  WITH CHECK (carteira_id IN (SELECT auth_carteiras()));

-- lancamento_valores_mes: acesso via JOIN com lancamentos_financeiros
CREATE POLICY "Members access valores_mes"
  ON lancamento_valores_mes FOR ALL TO authenticated
  USING (lancamento_id IN (
    SELECT id FROM lancamentos_financeiros 
    WHERE carteira_id IN (SELECT auth_carteiras())
  ))
  WITH CHECK (lancamento_id IN (
    SELECT id FROM lancamentos_financeiros 
    WHERE carteira_id IN (SELECT auth_carteiras())
  ));

CREATE POLICY "Members access saldo_inicial"
  ON saldo_inicial FOR ALL TO authenticated
  USING    (carteira_id IN (SELECT auth_carteiras()))
  WITH CHECK (carteira_id IN (SELECT auth_carteiras()));

CREATE POLICY "Members access config_financeira"
  ON config_financeira FOR ALL TO authenticated
  USING    (carteira_id IN (SELECT auth_carteiras()))
  WITH CHECK (carteira_id IN (SELECT auth_carteiras()));
```

### 2.4. Realtime

```sql
ALTER PUBLICATION supabase_realtime ADD TABLE lancamentos_financeiros;
ALTER PUBLICATION supabase_realtime ADD TABLE lancamento_valores_mes;
ALTER PUBLICATION supabase_realtime ADD TABLE saldo_inicial;
```

---

## 3. Tipo de Carteira

O app já tem o conceito de **carteira** com tipo (`'viagem'` ou `'comum'`), conforme `004_tipo_carteiras.sql`. 

- Carteiras do tipo `'viagem'` → continuam funcionando como hoje (gastos de viagem)
- Carteiras do tipo `'comum'` → habilitam o módulo de **Finanças Pessoais**

A nova funcionalidade deve ser ativada **apenas para carteiras do tipo `'comum'`**.

---

## 4. Frontend — Novas Telas e Componentes

### 4.1. Seletor de Tipo de Carteira (já existente: expandir)

Ao criar uma nova carteira, o usuário escolhe:
- 🧳 **Viagem** — comportamento atual
- 💰 **Finanças** — novo módulo

### 4.2. Tela Principal de Finanças (nova seção no `index.html`)

Quando a carteira ativa for do tipo `'comum'`, renderizar uma tela diferente da tela de viagens. A tela deve ter:

#### A) Card de Saldo (topo)
```
┌──────────────────────────────────────────┐
│  SALDO ATUAL                              │
│  R$ 5.511,93                              │
│                                           │
│  ┌─────────┐  ┌─────────┐                │
│  │ ENTRADAS │  │ SAÍDAS  │                │
│  │ R$ 6.053 │  │ R$ 541  │                │
│  └─────────┘  └─────────┘                │
│                                           │
│  Saldo Mês: R$ 5.511,93                  │
│  Cheque Especial: R$ 840,00              │
│  Saldo Futuro (Dez): R$ 32.922,45        │
└──────────────────────────────────────────┘
```

Informações calculadas:
- **Saldo Atual** = Saldo inicial + Entradas realizadas − Saídas realizadas (até o mês atual)
- **Saldo do Mês** = Total Entrada do mês − Total Saída do mês
- **Saldo Futuro** = Projeção acumulada até dezembro (considera fixos + variáveis preenchidos)
- **Cheque Especial** = Limite configurado + saldo atual (mostra quanto tem disponível)

#### B) Seletor de Ano e Mês
```
◀ 2025 ▶    [Jan] [Fev] [Mar] [Abr] [Mai] [Jun] ...
                                ^^^^ (mês selecionado)
```

- Navegação por ano com setas
- Chips de meses na horizontal com scroll
- Mês atual destacado em cor diferente
- Meses futuros com indicação visual (opacidade ou ícone de projeção)

#### C) Seção ENTRADAS (lista)
```
┌──────────────────────────────────────────┐
│  📥 ENTRADAS                    R$ 6.053 │
├──────────────────────────────────────────┤
│  Sal. Fabio           R$ 4.104,45   🔒   │
│  Sal Extra            R$ 1.500,00   ✏️   │
│  Empresa              R$ 449,00     🔒   │
│  Outros               —             ✏️   │
└──────────────────────────────────────────┘
```

- 🔒 = fixo (valor preenchido automaticamente)
- ✏️ = variável/único (valor editável inline)
- Tap em um item → expande detalhes (valor por mês, editar, histórico)
- Botão `+ Nova Entrada` no final

#### D) Seção SAÍDAS (lista)
```
┌──────────────────────────────────────────┐
│  📤 SAÍDAS                     R$ 8.360  │
├──────────────────────────────────────────┤
│  Casa                 R$ 368,00     🔒   │
│  Condomínio           R$ 336,00     🔒   │
│  NET                  R$ 270,00     🔒   │
│  Celular              R$ 140,00     🔒   │
│  Card Carrefour       R$ 531,41   3/10   │
│  Card Trigg           R$ 1.506,88   ✏️   │
│  Card NuBank          R$ 337,23     ✏️   │
│  Empréstimo           R$ 541,52     🔒   │
│  Uber                 R$ 104,00     ✏️   │
│  Pets                 R$ 230,00     🔒   │
│  Outros               R$ 60,00      ✏️   │
│  Academia             R$ 100,00     🔒   │
└──────────────────────────────────────────┘
```

- Parcelas mostram `parcela_atual/parcelas_total`
- Itens inativos no mês selecionado ficam ocultos ou esmaecidos
- Totalizador da seção atualizado em tempo real
- Botão `+ Nova Saída` no final

#### E) Resumo Mensal (card inferior)
```
┌──────────────────────────────────────────┐
│  RESUMO — JUNHO 2025                      │
│                                           │
│  Total Entradas:        R$ 7.916,84       │
│  Total Saídas:          R$ 8.360,15       │
│  ─────────────────────────────────        │
│  Saldo do Mês:          −R$ 443,31  ⚠️    │
│  Saldo Acumulado:       −R$ 1.198,82      │
│  Disponível (c/ Ch.Esp): −R$ 358,82      │
└──────────────────────────────────────────┘
```

#### F) Visão Anual (Dashboard — novo modal ou seção)
```
┌──────────────────────────────────────────┐
│  📊 VISÃO ANUAL — 2025                    │
│                                           │
│  Gráfico de barras: Entrada vs Saída      │
│  por mês (12 meses)                       │
│                                           │
│  Jan  Fev  Mar  Abr  Mai  Jun  Jul  ...  │
│  ██   ██   ██   ██   ██   ██   ██        │
│  ▓▓   ▓▓   ▓▓   ▓▓   ▓▓   ▓▓   ▓▓        │
│                                           │
│  Créditos no ano:   R$ 85.892,79          │
│  Débitos no ano:    R$ 70.576,70          │
│  Saldo no ano:      R$ 15.316,09          │
└──────────────────────────────────────────┘
```

- Gráfico de barras empilhadas (Entradas em verde, Saídas em vermelho)
- Linha de saldo acumulado sobreposta
- Cards resumo no final

---

## 5. Lógica de Negócio (JavaScript)

### 5.1. Cálculo de Saldo

```javascript
// Pseudocódigo da lógica principal
function calcularSaldoMes(carteira_id, ano, mes) {
  const saldoAnterior = getSaldoMesAnterior(carteira_id, ano, mes);
  const entradas = somarLancamentos(carteira_id, ano, mes, 'entrada');
  const saidas = somarLancamentos(carteira_id, ano, mes, 'saida');
  
  return {
    saldoAnterior,
    totalEntradas: entradas,
    totalSaidas: saidas,
    saldoMes: entradas - saidas,
    saldoAcumulado: saldoAnterior + entradas - saidas
  };
}

function getSaldoMesAnterior(carteira_id, ano, mes) {
  if (mes === 1) {
    // Buscar saldo final de dezembro do ano anterior
    return calcularSaldoAcumuladoFinal(carteira_id, ano - 1, 12);
  }
  return calcularSaldoAcumuladoFinal(carteira_id, ano, mes - 1);
}

function calcularSaldoAcumuladoFinal(carteira_id, ano, mes) {
  // Recursivamente calcula desde o saldo_inicial mais antigo
  const saldoInicial = buscarSaldoInicial(carteira_id, ano);
  let saldo = saldoInicial;
  for (let m = 1; m <= mes; m++) {
    saldo += somarLancamentos(carteira_id, ano, m, 'entrada');
    saldo -= somarLancamentos(carteira_id, ano, m, 'saida');
  }
  return saldo;
}
```

### 5.2. Valor do Lançamento em um Mês

```javascript
function getValorLancamento(lancamento, ano, mes) {
  // 1. Verificar se o lançamento está ativo neste mês
  if (!isAtivoNoPeriodo(lancamento, ano, mes)) return 0;
  
  // 2. Buscar override na tabela lancamento_valores_mes
  const override = buscarValorMes(lancamento.id, ano, mes);
  if (override) return override.valor;
  
  // 3. Se é fixo, usar valor_padrao
  if (lancamento.recorrencia === 'fixo') return lancamento.valor_padrao;
  
  // 4. Se é variável/único sem override, retorna 0 (não preenchido)
  return 0;
}
```

### 5.3. Projeção de Saldo Futuro

```javascript
function calcularSaldoFuturo(carteira_id, ano) {
  // Calcula o saldo projetado até dezembro
  // Para meses passados: usa valores realizados
  // Para meses futuros: usa valor_padrao (fixos) + overrides preenchidos
  const mesAtual = new Date().getMonth() + 1;
  let saldo = getSaldoInicialAno(carteira_id, ano);
  
  for (let mes = 1; mes <= 12; mes++) {
    const entradas = somarLancamentosProjetados(carteira_id, ano, mes);
    const saidas = somarLancamentosProjetados(carteira_id, ano, mes);
    saldo += entradas - saidas;
  }
  
  return saldo; // Saldo projetado em 31/12
}
```

### 5.4. Criação/Edição de Lançamentos

#### Modal de Novo Lançamento:
```
┌──────────────────────────────────────────┐
│  Novo Lançamento                    ✕    │
│                                           │
│  Descrição:  [Card NuBank            ]   │
│  Tipo:       (•) Saída  ( ) Entrada      │
│  Categoria:  [Cartão de Crédito   ▼  ]   │
│                                           │
│  Recorrência:                             │
│  [Fixo] [Variável] [Único] [Parcelado]   │
│                                           │
│  Valor: R$ [337,23                   ]   │
│                                           │
│  Vigência:                                │
│  De: [Jun/2023 ▼]  Até: [Dez/2023 ▼]   │
│  (ou ☐ Sem data fim — ativo indefinido)  │
│                                           │
│  ── Se parcelado ──                      │
│  Nº Parcelas: [10]  Parcela atual: [3]   │
│                                           │
│  [         Salvar         ]              │
│  [  Cancelar  ] [  Excluir  ]            │
└──────────────────────────────────────────┘
```

#### Edição inline de valor mensal:
- Ao tocar no valor de um lançamento variável, abre campo de edição rápida
- Salva em `lancamento_valores_mes`
- Checkbox "Realizado" para marcar que o valor já foi pago/recebido

---

## 6. Categorias Sugeridas

### Entradas:
| Emoji | Categoria |
|-------|-----------|
| 💼 | Salário |
| 🏢 | Empresa / CLT |
| 💰 | Renda Extra |
| 🎁 | 13º Salário |
| 📈 | Investimentos |
| 🔄 | Reembolsos |
| 📦 | Outros |

### Saídas:
| Emoji | Categoria |
|-------|-----------|
| 🏠 | Moradia (aluguel, condomínio) |
| 📡 | Telecomunicações (internet, celular) |
| 💳 | Cartão de Crédito |
| 🏦 | Empréstimo / Financiamento |
| 🐾 | Pets |
| 🚗 | Transporte (Uber, combustível) |
| 🏋️ | Saúde / Academia |
| 🦷 | Plano Dental / Saúde |
| 🍽️ | Alimentação |
| 🎮 | Streaming / Lazer |
| ✈️ | Viagens |
| 📦 | Outros |

---

## 7. Etapas de Implementação (ordem sugerida para a IA)

### Etapa 1 — Banco de Dados
1. Criar arquivo `supabase/migrations/005_financas_pessoais.sql` com todas as tabelas, índices, RLS e realtime descritos na seção 2
2. **Não** alterar tabelas existentes (viagens, gastos, ajustes)

### Etapa 2 — Camada de Dados (JavaScript)
3. No `nao_ofuscado/index.html`, criar o módulo JS para CRUD de lançamentos financeiros:
   - `carregarLancamentos(carteira_id, ano)` — busca todos os lançamentos + valores_mes
   - `salvarLancamento(lancamento)` — insert/update em `lancamentos_financeiros`
   - `salvarValorMes(lancamento_id, ano, mes, valor)` — insert/upsert em `lancamento_valores_mes`
   - `excluirLancamento(id)` — soft delete (ativo = false)
   - `carregarSaldoInicial(carteira_id, ano)` — busca saldo_inicial
   - `salvarSaldoInicial(carteira_id, ano, mes, valor)` — upsert
   - `carregarConfigFinanceira(carteira_id)` — busca config (cheque especial, etc.)
   - `salvarConfigFinanceira(carteira_id, chave, valor)` — upsert

### Etapa 3 — Motor de Cálculos
4. Implementar funções de cálculo (seção 5):
   - `calcularSaldoMes()` — saldo de um mês específico
   - `calcularResumoAnual()` — créditos, débitos e saldo no ano
   - `calcularSaldoFuturo()` — projeção até fim do ano
   - `getValorLancamento()` — valor efetivo de um lançamento em um mês
   - `isAtivoNoPeriodo()` — verifica se lançamento está vigente
   - `calcularChequeEspecial()` — limite + saldo

### Etapa 4 — UI: Tela Principal de Finanças
5. Criar a seção HTML/CSS para a tela de finanças pessoais:
   - Card de Saldo (com saldo atual, projetado, cheque especial)
   - Seletor de Ano/Mês
   - Lista de Entradas com totalizador
   - Lista de Saídas com totalizador
   - Resumo Mensal
6. Mostrar esta tela **somente quando a carteira ativa for do tipo `'comum'`**
7. Esconder a tela de viagens quando estiver no modo finanças

### Etapa 5 — UI: Modais e Formulários
8. Modal de Novo/Editar Lançamento
9. Edição inline de valor mensal (para lançamentos variáveis)
10. Modal de Configurações Financeiras (cheque especial, saldo inicial)
11. Toggle "Realizado" para marcar pagamentos/recebimentos

### Etapa 6 — UI: Dashboard Anual
12. Implementar a Visão Anual:
    - Gráfico de barras Entrada vs Saída por mês (reutilizar padrão do dashboard existente)
    - Linha de saldo acumulado
    - Cards resumo (créditos, débitos, saldo no ano)

### Etapa 7 — Integração e Ajustes Finais
13. Garantir que a navegação entre carteiras (viagem ↔ finanças) funcione corretamente
14. Manter o padrão visual existente (cores, fontes, animações do Caderno de Gastos)
15. Supabase Realtime: atualização em tempo real dos valores
16. PWA: garantir que o service worker cache as novas funcionalidades

---

## 8. Design e UX — Diretrizes

### 8.1. Manter a identidade visual existente
- Mesmas fontes: Fraunces (títulos), DM Sans (corpo), JetBrains Mono (valores)
- Mesma paleta: `--paper`, `--ink`, `--accent`, `--debito`, `--credito`
- Mesmos border-radius, shadows, e animações

### 8.2. Novos elementos visuais
- **Verde** para entradas / saldo positivo (usar `--debito: #5d6b3c`)
- **Vermelho** para saídas / saldo negativo (usar `--accent: #c44d3e`)
- **Amarelo/âmbar** para projeção / valores não realizados (usar `--pending: #c98a2b`)
- Badge de recorrência: 🔒 fixo, ✏️ variável, 📦 único, 🔄 parcelado

### 8.3. Responsividade
- Layout mobile-first (já é o padrão do app)
- Tabela de meses com scroll horizontal em telas pequenas
- Cards empilhados em mobile, grid em tablet+

### 8.4. Interações
- Swipe horizontal no seletor de meses
- Tap para expandir detalhes de lançamento
- Long press para editar/excluir
- Pull-to-refresh (já implementado no app)
- Animações de transição ao trocar mês/ano

---

## 9. Modelo de Dados — Exemplos

### Lançamento Fixo (Salário)
```json
{
  "descricao": "Sal. Fabio",
  "tipo": "entrada",
  "categoria": "salario",
  "recorrencia": "fixo",
  "valor_padrao": 4104.45,
  "mes_inicio": 1,
  "ano_inicio": 2023,
  "mes_fim": null,
  "ano_fim": null
}
```
→ Aparece em todos os meses a partir de Jan/2023 com R$ 4.104,45

### Lançamento Único (13º Salário)
```json
{
  "descricao": "13º Salário",
  "tipo": "entrada",
  "categoria": "13o",
  "recorrencia": "unico",
  "valor_padrao": 4104.45,
  "mes_inicio": 12,
  "ano_inicio": 2023,
  "mes_fim": 12,
  "ano_fim": 2023
}
```

### Lançamento Variável (Cartão de Crédito)
```json
{
  "descricao": "Card Trigg",
  "tipo": "saida",
  "categoria": "cartao",
  "recorrencia": "variavel",
  "valor_padrao": 0,
  "mes_inicio": 6,
  "ano_inicio": 2023,
  "mes_fim": 12,
  "ano_fim": 2023
}
```
→ Cada mês tem um registro em `lancamento_valores_mes`:
```json
[
  {"mes": 6, "ano": 2023, "valor": 1506.88},
  {"mes": 7, "ano": 2023, "valor": 866.40},
  {"mes": 8, "ano": 2023, "valor": 796.93},
  ...
]
```

### Lançamento de Viagem Planejada
```json
{
  "descricao": "Viagem Bahia",
  "tipo": "saida",
  "categoria": "viagem",
  "recorrencia": "unico",
  "valor_padrao": 5000.00,
  "mes_inicio": 7,
  "ano_inicio": 2025,
  "mes_fim": 7,
  "ano_fim": 2025
}
```
→ Impacta o saldo projetado de Julho/2025 em diante

---

## 10. Notas Importantes para a IA Executora

1. **Não quebrar o fluxo existente** — O módulo de viagens deve continuar funcionando 100%. A tela de finanças é uma alternativa para carteiras `tipo = 'comum'`.

2. **Arquivo único** — Todo o app é um único `index.html` (com CSS e JS inline). Manter esse padrão.

3. **Supabase Client** — Já existe no app. Usar o mesmo client (`supabase`) para todas as operações.

4. **Categorias editáveis** — As categorias da seção 6 são sugestões iniciais. O usuário poderá criar novas categorias.

5. **Performance** — Carregar dados por ano (não todos de uma vez). Usar cache local para evitar requests repetidos.

6. **Offline** — O app é PWA. Considerar cache offline dos dados financeiros (IndexedDB ou localStorage).

7. **Moeda** — Sempre BRL (R$). Formato: `1.234,56`.

8. **Saldo Inicial** — Ao criar uma carteira financeira, pedir o saldo atual da conta para configurar `saldo_inicial`.

9. **Meses sem valor** — Para lançamentos variáveis, meses sem registro em `lancamento_valores_mes` devem mostrar `—` (traço) e não R$ 0,00.

10. **Cheque Especial** — Valor configurável em `config_financeira`. Mostrar `Saldo + Limite` como "Disponível". Alertar quando saldo ficar negativo.
