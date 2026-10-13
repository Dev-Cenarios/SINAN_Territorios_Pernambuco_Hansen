# Prompt padrão para geração de README — Projeto Cenários

> **Como usar:** rode este prompt com um assistente de IA que tenha **acesso de
> leitura ao repositório** (ex: Claude Code, Cursor, Copilot Workspace, ou
> colando os arquivos relevantes num chat comum). O assistente deve explorar o
> código-fonte sozinho e extrair funcionalidades, tecnologias, estrutura de
> pastas e fontes de dados — você só precisa informar o que **não existe no
> código** (eixo do projeto e dados de contato dos desenvolvedores).
> Isso garante que todo README do Programa Cenários siga a mesma estrutura,
> sem depender de preenchimento manual repetitivo.

---

## 🧩 Prompt reutilizável (uso com IA agente com acesso ao repositório)

```
Você é um redator técnico especializado em documentação de repositórios
científicos. Você TEM ACESSO DE LEITURA a este repositório através das suas
ferramentas (listagem de diretórios, leitura de arquivos, busca de texto).
Investigue o código-fonte por conta própria — NÃO peça ao usuário para colar
manualmente estrutura de pastas, dependências ou funcionalidades: descubra
isso lendo o repositório.

TAREFA: gerar um README.md completo e padronizado, seguindo RIGOROSAMENTE a
estrutura de tópicos e o texto institucional fixo especificados abaixo.

=====================================================================
PASSO 1 — INVESTIGAÇÃO AUTÔNOMA DO REPOSITÓRIO
=====================================================================
Antes de escrever qualquer coisa, explore o repositório e levante:

a) Nome e propósito do repositório
   - Leia o nome da pasta raiz, arquivos de metadados (DESCRIPTION, package.json,
     pyproject.toml, setup.py, Cargo.toml) e qualquer README/CHANGELOG existente.

b) Eixo do Programa Cenários (Hanseníase ou Tuberculose)
   - Infira pelo nome do repositório, README existente, nomes de variáveis/
     tabelas (ex: "TB", "hanseniase", "SINAN-TB") ou comentários no código.
   - Se houver ambiguidade real, sinalize isso claramente no início da sua
     resposta e pergunte ao usuário antes de prosseguir — não adivinhe.

c) Funcionalidades principais
   - Para apps Shiny/golem: leia os módulos em R/ (ex: mod_*.R), a UI principal
     (app_ui.R) e identifique abas, filtros, mapas, gráficos e exportações.
   - Para apps web (React/Vue/Next etc.): leia rotas, componentes de página e
     menus de navegação.
   - Para pacotes/bibliotecas: leia as funções exportadas (NAMESPACE, __init__.py,
     index.ts) e seus docstrings/roxygen.
   - Liste cada funcionalidade com uma frase objetiva do que ela faz.

d) Estrutura do projeto
   - Gere a árvore de diretórios você mesmo, usando suas próprias ferramentas
     de listagem de arquivos (não peça ao usuário para rodar `tree`).
   - Ignore pastas irrelevantes para o leitor: .git, node_modules, renv,
     app_cache, .Rproj.user, __pycache__, .venv, dist, build.
   - Limite a profundidade a 2-3 níveis, expandindo mais apenas pastas-chave
     (ex: R/, inst/app/www/).
   - Formate como bloco de código no estilo do comando `tree` do Linux
     (caracteres ├──, └──, │).

e) Fonte de dados
   - Procure por strings de conexão, leitura de CSV/parquet/API, nomes de
     bases conhecidas (SINAN, IBGE, CNES, malha censitária) em código-fonte,
     scripts de ETL ou pasta de dados.
   - Descreva granularidade, periodicidade de atualização (se identificável)
     e eventuais restrições (dados sensíveis/LGPD).

f) Tecnologias e pré-requisitos
   - Extraia linguagem(ns), framework(s) e dependências com versões dos
     arquivos de manifesto (DESCRIPTION, renv.lock, package.json,
     requirements.txt, pyproject.toml, Dockerfile).
   - Identifique pré-requisitos de ambiente (banco de dados, variáveis de
     ambiente, credenciais de API) procurando por arquivos .env.example,
     configs de conexão, etc.

g) Instalação
   - Procure por scripts de setup, CI (GitHub Actions), Dockerfile ou
     instruções já existentes em README/CONTRIBUTING para reconstruir o passo
     a passo real de instalação e execução local.
   - Teste mentalmente a sequência: ela deve ser reproduzível do zero
     (clone → dependências → configuração → execução).

h) Troubleshooting
   - Procure por issues resolvidas, comentários "# workaround", "# fix", ou
     seções de troubleshooting em documentação existente.
   - Se não encontrar nada documentado, gere no máximo 2-3 itens plausíveis
     com base em erros comuns do stack identificado (ex: versão de pacote R,
     variável de ambiente ausente) e marque-os como sugestão a validar.

i) Desenvolvedores
   - Verifique DESCRIPTION (campo Authors@R), package.json (author/contributors),
     CODEOWNERS, ou commits/tags de autoria via metadados do repositório.
   - Isso é o único bloco em que, se a informação não estiver disponível no
     repositório, você deve perguntar diretamente ao usuário em vez de
     inventar nomes ou contatos.

=====================================================================
PASSO 2 — GERAÇÃO DO README, NESTA ESTRUTURA OBRIGATÓRIA
=====================================================================

1. **Introdução do material do repositório**
   Parágrafo curto e específico (baseado no que você levantou no passo 1a/1c)
   explicando o que É este repositório/painel, qual problema ele resolve e
   para quem é destinado. Não repita o texto institucional — isso vem a seguir.

2. **Sobre o Projeto Cenários** (texto institucional fixo — reproduza
   EXATAMENTE o texto abaixo, adaptando apenas a frase final de
   contextualização do repositório específico e o link "Saiba mais" conforme
   o eixo identificado no passo 1b):

   ---
   ## Sobre o Projeto

   O Programa Cenários, coordenado pelo Prof. Dr. Walter Massa Ramalho da
   Universidade de Brasília (UnB), é uma iniciativa científica e tecnológica que
   reúne pesquisadores, gestores de saúde e parceiros nacionais e internacionais
   para desenvolver soluções inovadoras no enfrentamento de doenças determinadas
   socialmente. Atualmente, o programa é composto por dois grandes eixos de
   pesquisa:

   ### 1. Hanseníase – Modelagem de Cenários de Risco
   Cenários Hanseníase tem como objetivo identificar áreas de risco e cadeias
   invisíveis de transmissão da hanseníase no Brasil, com foco especial nas
   regiões metropolitanas de Brasília (DF), Recife (PE), Palmas (TO) e demais
   capitais. A proposta integra inteligência artificial generativa,
   georreferenciamento por setores censitários e rastreamento de contatos. Os
   resultados incluem um dashboard nacional, algoritmos de análise espacial e
   temporal, e relatórios técnicos para subsidiar ações estratégicas do SUS,
   com foco na redução de desigualdades e modernização da vigilância.

   ### 2. Tuberculose – Cenários de Risco e Determinantes Sociais
   Cenários TB visa apoiar a eliminação da tuberculose como problema de saúde
   pública no Brasil e em países lusófonos africanos e latino-americanos. A
   pesquisa combina modelagem epidemiológica, vinculação de bases de dados
   (linkage) e estratificação de cenários para avaliar a situação dos
   municípios e orientar ações prioritárias. Entre as entregas previstas estão
   toolkits com árvores de decisão e IA, dashboards interativos, matrizes de
   indicadores e metodologias de microplanejamento integradas à atenção
   primária. Também serão promovidas parcerias com municípios e capacitações
   para gestores de saúde.

   Este [painel/material] — o [NOME_DO_REPOSITORIO] — é uma das entregas do
   eixo [Hanseníase|Tuberculose], com foco em [RECORTE_ESPECIFICO identificado
   no passo 1a/1b].

   [Saiba mais sobre o projeto!]([LINK_SAIBA_MAIS — usar
   https://cenarios.unb.br/hanseniase-modelagem-de-cenarios-de-risco/ para o
   eixo Hanseníase, ou
   https://cenarios.unb.br/tuberculose-cenarios-de-risco-e-determinantes-sociais/
   para o eixo Tuberculose])

   ### Abordagem Comum
   Ambos os projetos compartilham princípios e tecnologias:

   * Uso de dados sociais, econômicos e epidemiológicos para subsidiar decisões.
   * Georreferenciamento de casos para detalhamento espacial.
   * Análise temporal para identificar tendências e rupturas.
   * Ferramentas digitais abertas para garantir transparência e replicabilidade.
   * Interação com gestores e oficinas de validação para alinhar resultados às
     necessidades locais.

   Essa atuação integrada fortalece o SUS, promove equidade em saúde e
   posiciona o Brasil na vanguarda da aplicação de ciência de dados e
   inteligência artificial em saúde pública.
   ---

3. **Sumário** — lista Markdown com âncoras para todas as seções numeradas abaixo.

4. **1. Funcionalidades** — bullets com cada funcionalidade levantada no passo
   1c, cada uma com um link de detalhamento (seção interna do próprio README,
   wiki, ou "documentação em construção" se não houver).

5. **2. Estrutura do projeto** — a árvore de diretórios gerada no passo 1d, em
   um bloco de código ```` ```text ```` no formato `tree`, com comentários
   breves sobre a função das pastas/arquivos mais importantes.

6. **3. Fonte de dados** — o que foi levantado no passo 1e.

7. **4. Tecnologias e pré-requisitos** — o que foi levantado no passo 1f.

8. **5. Instalação** — passo a passo reproduzível em bloco de código, baseado
   no passo 1g.

9. **6. Troubleshooting** — lista ou tabela baseada no passo 1h.

10. **7. Desenvolvedores** — nome, papel/função e contato de cada responsável,
    baseado no passo 1i (perguntando ao usuário se não encontrado no repo).

=====================================================================
REGRAS
=====================================================================
- Priorize sempre o que foi encontrado no repositório sobre suposições.
- Nunca invente funcionalidades, tecnologias, dados ou nomes de pessoas.
  Se uma informação não puder ser encontrada nem inferida com segurança,
  pergunte ao usuário (não insira dados fictícios).
- Mantenha o texto institucional da seção 2 fiel ao original, alterando
  apenas os trechos indicados entre colchetes.
- Gere o resultado final como um único bloco de código Markdown pronto para
  salvar como README.md.
```

---

## 🌳 Caso a IA não tenha acesso direto ao repositório

Se você for usar este prompt em um chat sem acesso a arquivos (ex: colando
texto em um LLM sem ferramentas), gere a árvore de diretórios você mesmo antes
e cole o resultado no lugar da instrução do passo 1d.

### Linux / macOS / Git Bash
```bash
sudo apt install tree   # se necessário
tree -L 3 -I 'node_modules|.git|renv|app_cache|.Rproj.user'
```

### Windows (PowerShell)
```powershell
tree /F /A
```
Para um resultado mais próximo do estilo Linux, instale via
`winget install tree` / `choco install tree` / `scoop install tree` (se algum
gerenciador estiver disponível) e use o mesmo comando acima.

### Alternativa via Git (não precisa instalar nada)
```bash
git ls-files | tree --fromfile
```
(usa apenas os arquivos versionados — omite automaticamente node_modules,
caches etc.; requer o pacote `tree` instalado)

### Exemplo de formatação esperada
```text
Cenarios_TB_Recife/
├── R/                  # Módulos Shiny e funções do golem
├── inst/
│   └── app/
│       └── www/        # Assets estáticos (CSS, imagens, favicon)
├── dev/                # Scripts de desenvolvimento do golem
├── docs/                # Documentação complementar
├── tests/               # Testes automatizados
├── app.R                 # Ponto de entrada da aplicação Shiny
├── DESCRIPTION            # Metadados do pacote R
└── README.md              # Este arquivo
```

---

## 💡 Dica de uso

Com um assistente que já tem acesso ao repositório (como neste ambiente
Claude Code), basta pedir diretamente:
*"gere o README deste repositório usando o prompt padrão em
`docs/PROMPT_TEMPLATE_README.md`"* — o assistente vai explorar o código,
extrair funcionalidades/tecnologias/estrutura reais e só voltará a perguntar
o que genuinamente não conseguir inferir (eixo ambíguo, contato dos
desenvolvedores).
