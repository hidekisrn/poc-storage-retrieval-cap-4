# Simulador de Motores de Armazenamento

> Uma aplicação web interativa que explica, de forma visual e manipulável, os principais
> conceitos do capítulo **Storage and Retrieval** do livro
> *Designing Data-Intensive Applications* (Martin Kleppmann).

Em vez de só ler sobre LSM-Trees, B-Trees e armazenamento por coluna, aqui você **escreve,
apaga e lê dados** e vê a estrutura interna do banco reagir em tempo real: a memtable
enchendo, os SSTables se fundindo na compaction, uma página de B-Tree dividindo (split) e a
diferença de I/O entre uma consulta transacional e uma analítica.

É um **POC didático** — uma única página HTML autocontida, sem back-end, sem build e sem
nenhuma dependência externa.

---

## Índice

- [O que o simulador ensina](#o-que-o-simulador-ensina)
- [Como executar](#como-executar)
- [Estrutura do projeto](#estrutura-do-projeto)
- [Como funciona por dentro](#como-funciona-por-dentro)
- [Mapa dos conceitos do capítulo](#mapa-dos-conceitos-do-capítulo)
- [Simplificações didáticas](#simplificações-didáticas-o-que-é-real-e-o-que-foi-abstraído)
- [Deploy com Docker](#deploy-com-docker)
- [Compatibilidade](#compatibilidade)
- [Créditos e referência](#créditos-e-referência)

---

## O que o simulador ensina

A aplicação é dividida em **4 abas**, cada uma cobrindo um bloco do capítulo.

### 1. LSM-Tree & SSTables
Motor de armazenamento baseado em log (LevelDB, RocksDB, Cassandra, HBase).

- **`SET` / `DELETE`** gravam primeiro no *Write-Ahead Log* (durabilidade) e na *memtable* em RAM.
- Quando a memtable atinge o limite, ela é **descarregada** (*flush*) como um **SSTable**
  ordenado e imutável em disco.
- A **compaction** funde SSTables, mantendo a versão mais recente de cada chave e
  descartando *tombstones* (marcadores de exclusão), recuperando espaço.
- A **leitura** consulta a memtable e depois os SSTables (do mais novo ao mais antigo). Cada
  SSTable tem um **Bloom filter** que evita ler o disco quando a chave "com certeza não está lá".
- Começa com uma **base grande** (41 chaves em L0/L1/memtable) para mostrar o comportamento
  em escala, incluindo atualizações e um tombstone que "esconde" um dado antigo.

### 2. B-Tree
Motor usado pelos bancos relacionais (PostgreSQL, MySQL/InnoDB, SQLite, Oracle).

- **`INSERT`** grava a chave *in-place* na página-folha; se a página estoura, ela **divide**
  (*split*) e a chave do meio sobe para o pai — podendo criar uma nova raiz e aumentar a
  altura da árvore.
- **`SEARCH`** percorre um único caminho da raiz até a folha (nº de páginas lidas = altura).
- Contadores de **páginas reescritas** (amplificação de escrita) e **páginas lidas**.
- Slider para ajustar o **máximo de chaves por página** e ver splits acontecerem mais cedo ou mais tarde.

### 3. Linha × Coluna (OLTP × OLAP)
A mesma tabela em dois arranjos físicos, lado a lado.

- **Por linha** (*row-oriented*): os campos de um registro ficam juntos. Ótimo para pegar
  um pedido inteiro; ruim para varrer uma coluna.
- **Por coluna** (*column-oriented*): os valores de uma mesma coluna ficam juntos. Lê só as
  colunas da consulta e **comprime muito bem** (selos de RLE nas colunas de baixa cardinalidade).
- Duas consultas realçam quais células cada arranjo precisa ler:
  - **OLTP** (`SELECT *` de um pedido): vantagem do arranjo por linha (1 bloco contíguo).
  - **OLAP** (receita por produto): vantagem do arranjo por coluna (lê só 3 colunas, ~2,3× menos I/O).

### 4. Comparação
O clímax do capítulo: **B-Tree × LSM-Tree** lado a lado.

- **Placar de amplificação de escrita ao vivo**, alimentado pelo que você fez nas abas
  1 e 2 (insira dados lá e volte aqui).
- **Tabela de trade-offs**: padrão de escrita, amplificação, leitura, throughput, espaço em
  disco, concorrência e maturidade.

---

## Como executar

O aplicativo é um único arquivo HTML estático. Há três formas de abrir, da mais simples à mais "de produção".

### Opção 1 — Abrir o arquivo direto (mais simples)

Basta abrir [`lsm-simulator.html`](lsm-simulator.html) no navegador (duplo clique ou
`File → Open`). Não precisa de servidor nem internet.

### Opção 2 — Servidor estático local

Útil se preferir acessar via `http://` (por exemplo, para testar em outro dispositivo da rede):

```bash
# Python (já vem no macOS/Linux)
python3 -m http.server 8080

# ou Node
npx serve .
```

Depois acesse `http://localhost:8080/lsm-simulator.html`.

### Opção 3 — Docker

Sobe um `nginx` servindo o simulador na porta **8080**:

```bash
docker compose up -d
```

Acesse **http://localhost:8080**. Para parar: `docker compose down`.

Veja a seção [Deploy com Docker](#deploy-com-docker) para o modo sem compose e outros detalhes.

---

## Estrutura do projeto

```
poc-storage-retrieval/
├── lsm-simulator.html    # A aplicação inteira: HTML + CSS + JS inline, autocontido
├── Dockerfile            # Imagem nginx:alpine servindo o HTML como index.html
├── docker-compose.yml    # Sobe o container na porta 8080
├── .dockerignore         # Só o HTML entra no contexto de build
└── README.md             # Esta documentação
```

Todo o código-fonte está em **um único arquivo** ([`lsm-simulator.html`](lsm-simulator.html),
~1.200 linhas): a marcação, os estilos e a lógica dos quatro motores estão inline. Não há
etapa de build, bundler, framework ou dependência de rede.

---

## Como funciona por dentro

### Arquitetura geral
- **Single-file, zero dependências.** CSS e JS estão embutidos no HTML. Funciona offline e
  abre direto do sistema de arquivos.
- **Design tokens em CSS custom properties**, com suporte a **tema claro/escuro** (segue a
  preferência do sistema via `prefers-color-scheme` e também um `data-theme` manual).
- **Troca de abas** puramente no cliente: cada aba é uma `<section class="view">`; um único
  script mostra/esconde as views.
- Respeita `prefers-reduced-motion` (desliga as animações).

### Motor LSM-Tree
- Estado em memória: `memtable` (um `Map`), `wal` (lista), `sstables` (lista de tabelas com
  nível, versão, entradas ordenadas e Bloom filter).
- **Bloom filter real**: array de bits dimensionado por tabela (~8 bits por chave, `k = 4`
  funções de hash). Pode dar **falso positivo** (o simulador narra isso no trace), nunca falso negativo.
- **Ordem de leitura** correta: nível mais baixo primeiro (L0 é o mais novo), depois por recência.
- **Flush** cria um SSTable em L0 e descarta o WAL correspondente.
- **Compaction** funde todos os SSTables em uma tabela de L1 (a mais recente vence; tombstones
  são eliminados).

### Motor B-Tree
- Árvore B balanceada com fator de ramificação configurável (`máx. chaves por página`).
- **Insert** com split propagado para cima (cria nova raiz quando necessário).
- **Search** por caminho raiz→folha.
- Layout calculado em JS (posição de cada nó) e desenhado com **nós HTML posicionados +
  conectores SVG**.
- Amplificação de escrita = nº de páginas criadas/reescritas por operação.

### Linha × Coluna
- Conjunto de dados fixo de 14 pedidos (7 colunas).
- Renderiza o **mesmo dado** em dois arranjos: uma "fita" por linha (registros contíguos) e
  faixas por coluna (colunas contíguas).
- Cada consulta marca as células lidas em cada arranjo e conta o total, evidenciando a
  diferença de I/O.

---

## Mapa dos conceitos do capítulo

| Conceito do DDIA (Storage & Retrieval) | Onde ver no simulador |
|---|---|
| Log estruturado, escrita sequencial | Aba **LSM** — `SET` grava no WAL + memtable |
| SSTable (ordenado e imutável) | Aba **LSM** — flush |
| LSM-Tree, memtable, níveis | Aba **LSM** — L0/L1 |
| Compaction, tombstones | Aba **LSM** — botão *Compactar* |
| Bloom filter | Aba **LSM** — bits acendendo na leitura |
| B-Tree, páginas de tamanho fixo | Aba **B-Tree** |
| Split de página, crescimento em altura | Aba **B-Tree** — `INSERT` que estoura a página |
| Escrita in-place vs. append | Aba **Comparação** |
| Amplificação de escrita/leitura | Aba **Comparação** — placar ao vivo |
| OLTP vs OLAP | Aba **Linha × Coluna** |
| Column-oriented storage | Aba **Linha × Coluna** — arranjo por coluna |
| Compressão de colunas (RLE, bitmap) | Aba **Linha × Coluna** — selos de compressão |

---

## Simplificações didáticas (o que é real e o que foi abstraído)

Este é um material de ensino, não um banco de dados. Para manter a visualização clara, algumas
coisas foram simplificadas — importante ter em mente:

- **Tudo é em memória (JavaScript).** Não há persistência real em disco; "disco" e "RAM" são
  metáforas visuais. Recarregar a página reinicia o estado.
- **LSM — compaction:** o simulador funde *todos* os SSTables numa única tabela de L1. Engines
  reais fazem compaction incremental (leveled ou size-tiered) com muitos níveis (L0…L6).
- **LSM — Bloom filter:** é um filtro de bits de verdade e pode dar falso positivo, mas é
  pequeno (para o efeito ser visível). Em produção ele é bem maior e a taxa de falso positivo, menor.
- **B-Tree — remoção não implementada.** Só há `INSERT` e `SEARCH`. Bancos reais também
  rebalanceiam/fundem páginas subutilizadas ao apagar.
- **Amplificação de escrita** é aproximada: conta registros/páginas, não bytes. Os contadores
  zeram após a carga inicial para medir a sua atividade na sessão.
- **Linha × Coluna:** conjunto de dados pequeno e fixo; "células lidas" é um *proxy* de I/O. A
  compressão é ilustrada pela cardinalidade (valores distintos), não por um encoder real.

---

## Deploy com Docker

### Com docker compose

```bash
docker compose up -d      # sobe em http://localhost:8080
docker compose down       # para e remove
```

### Sem compose

```bash
docker build -t storage-sim .
docker run --rm -p 8080:80 storage-sim
```

### Detalhes da imagem
- Base: `nginx:1.27-alpine`.
- O arquivo é copiado para `/usr/share/nginx/html/index.html` (servido na raiz `/`).
- Inclui um `HEALTHCHECK` que verifica se a página responde.
- Imagem final: **~48 MB** (quase tudo é o próprio nginx; o HTML tem ~69 KB).
- Como a página é 100% estática e autocontida, o container é *stateless* — pode escalar,
  reiniciar e ser servido atrás de qualquer proxy/CDN sem preocupação com estado.

### Publicar num registry (opcional)

```bash
docker tag storage-sim <seu-usuario>/storage-sim:1.0
docker push <seu-usuario>/storage-sim:1.0
```

---

## Compatibilidade

- Funciona em qualquer navegador moderno (Chrome, Firefox, Safari, Edge).
- Não requer internet depois de carregado.
- Responsivo: as abas e as tabelas se adaptam a telas menores; conteúdo largo rola dentro do
  próprio container.
- Temas claro e escuro, seguindo a preferência do sistema.

---

## Créditos e referência

- Conteúdo baseado no capítulo **"Storage and Retrieval"** de
  ***Designing Data-Intensive Applications***, de **Martin Kleppmann** (O'Reilly).
  É a fonte recomendada para se aprofundar — o simulador é um complemento visual, não um
  substituto do livro.
- Projeto criado como POC didático. **Não terá mais evolução** — a documentação acima descreve
  o estado final e completo do projeto.
