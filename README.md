# codice-ereader-plugin

Plugin do [Códice](https://github.com/ocnaibill/codice) para o KOReader (Kindle com jailbreak, no começo). Conecta o leitor à sua instância por um **código aprovado no site** (sem digitar senha na tela e-ink) e mantém no aparelho a configuração do catálogo (OPDS) e da sincronização de progresso (KOSync). Plano e decisões: issue [ocnaibill/codice#327](https://github.com/ocnaibill/codice/issues/327) e a proposta `docs/Codice_Proposta_Pareamento_Leitor_2026-10-17.md` do Códice. Licença AGPLv3, como o KOReader e o Códice.

**Estado:** o pareamento, a tela inicial do Códice (a antiga), a escolha de arquivo e o OTA funcionam num Kindle 10ª geração (testados pelo mantenedor, versão 0.3.0). Na versão 0.4.0 o plugin passa a ter como base o **[Simple UI](https://github.com/doctorhetfield-cmd/simpleui.koplugin)** (MIT): a barra de navegação, a tela inicial em módulos, a barra de título e as configurações são dele, e as telas do Códice vão entrar nesse sistema. **Isso ainda não foi testado num aparelho.** Como acompanhamos o original: `UPSTREAM.md`; licenças: `NOTICE.md`.

## Instalar

> **Quem tem o Simple UI original instalado:** o plugin o desliga sozinho na primeira abertura (os dois carregam os mesmos módulos e não convivem) e pede para reiniciar. As configurações dele continuam valendo, porque o prefixo é o mesmo.

1. Baixe `codice-plugin.zip` da página de [releases](https://github.com/ocnaibill/codice-ereader-plugin/releases/latest), descompacte, ligue o Kindle ao computador por USB e copie a pasta `plugins/codice.koplugin` para `koreader/plugins/` (fica `koreader/plugins/codice.koplugin/main.lua`). Quem já tem o plugin 0.3.1 ou mais novo atualiza por **Códice → Procurar atualização do plugin**, sem USB.
2. Ejete o Kindle, abra o KOReader (reinicie se já estava aberto) e ligue o Wi-Fi.

## Conectar

1. Menu superior (ferramentas) → **Mais ferramentas → Códice → Conectar**.
2. Digite o endereço da sua instância (por exemplo `codice.exemplo.com`). O leitor mostra um código de oito letras e números; **Mostrar QR** mostra o endereço de aprovação como QR.
3. No site: **Minha conta → Aplicativos → Conectar um leitor** (ou leia o QR), digite o código, confira o aparelho e **Aprove**.
4. O leitor recebe sozinho o acesso e a configuração: o catálogo "Códice" aparece no **Catálogo OPDS** e a sincronização de progresso fica pronta (abra um livro e vire umas páginas). Se você já abriu um livro nesta sessão, reinicie o KOReader uma vez.

Depois disso, quando o Wi-Fi volta (no máximo a cada 6 horas), o plugin pergunta à instância se a configuração mudou e aplica só o que mudou. **Códice → Atualizar a configuração** faz isso na hora. **Desconectar este leitor** tira o catálogo e a sincronização do aparelho; para tirar o acesso do servidor, remova-o em Aplicativos, no site.

## Tela inicial

> Nesta versão a tela de entrada é a do Simple UI. A tela do Códice descrita abaixo é a **antiga**: continua em **Códice → Abrir o Códice**, e só abre sozinha se você ligar **Abrir a tela antiga do Códice ao iniciar**; ela será substituída por módulos do Códice dentro da home do Simple UI.

O Códice é a primeira tela: ao iniciar o KOReader, e toda vez que você fecha um livro, a home abre sozinha (mostra a última que o servidor mandou e atualiza se o Wi-Fi já estiver ligado, sem pedir). **Códice → Abrir o Códice ao iniciar** liga e desliga isso; o **Menu** da home tem **Arquivos do KOReader** para ir aos arquivos.

A home segue a da web, numa coluna que rola (deslize para cima e para baixo; ela para no começo de uma linha): saudação e números, **Continuar lendo**, **Favoritos**, algumas anotações e as **prateleiras** por categoria. As capas chegam depois da tela, algumas por vez.

Tocar numa capa abre o livro: **Ler**/**Continuar**. Se a obra tem mais de um arquivo, o plugin pergunta qual (`Português - EPUB (principal)`, `Inglês - PDF (último acessado, 20%)`...). O arquivo é baixado para a pasta `Códice` dentro da pasta de leitura (se ainda não estiver no aparelho). Isso exige um Códice com `GET /device/home` e `GET /device/works/{id}/files` (DEC-195).

**Livro novo no aparelho:** se você abre um livro que o servidor já tem lido por este mesmo Kindle e a cópia do aparelho está no começo (um download novo), o plugin pergunta "Continuar de onde parou?". Sem isso, o KOReader não pergunta e a próxima virada de página mandaria "o começo" por cima do seu progresso.

## Módulos do Códice na tela inicial do Simple UI

Os módulos do Códice entram na home do Simple UI como os dele (sem mudar nada do código dele). Para pôr um na tela: **Configurações do Simple UI → Tela Inicial → Adicionar Módulo** e escolha o do Códice.

| Módulo | O que mostra |
|---|---|
| **Códice: Continuar lendo** | os livros que você está lendo no Códice: a capa e, embaixo, um item abaixo do outro: o título, o autor e quanto já leu ("15% lido"). Quando você fecha um livro, ele vai para a frente da lista na hora, sem esperar o servidor; tocar numa obra a abre (baixando o arquivo, se ele ainda não está no aparelho, e perguntando qual quando há mais de um) |
| **Códice: Favoritos** | as obras que você marcou como favoritas no Códice; capa, barra de progresso e título |
| **Códice: Saudação** | "Bom dia, nome :)" e "O que queremos hoje?", como o topo da home da web, com o dia da semana e a data no fim da segunda linha (a hora está na barra do KOReader) |
| **Códice: Em andamento e atividade** | dois cartões lado a lado: quantas obras você está lendo (e de que formatos) e o que fez: obras completas no mês e tempo de leitura |
| **Códice: Nota aleatória** | uma nota ou destaque seu, sorteado entre os que o servidor manda; a escolha dura uns 10 minutos. Tocar nela abre a obra |
| **Códice: Prateleira 1** a **6** | as obras de cada categoria da biblioteca (as maiores primeiro, como na home da web); o título sobre a linha é o nome da categoria. Uma prateleira sem categoria correspondente fica vazia |

Os dados vêm da última home que o servidor mandou, guardada no aparelho: a tela aparece na hora, sem rede, e se atualiza sozinha quando o Wi-Fi já está ligado (nunca pede Wi-Fi). As capas chegam depois, algumas por vez. Quantas colunas e linhas, o tamanho do texto e o resto da aparência são as configurações de módulo do próprio Simple UI.

## Atualizar o plugin

**Códice → Procurar atualização do plugin** (e, quando o Wi-Fi volta, no máximo uma vez por semana, um aviso) olha a versão mais nova nos [releases](https://github.com/ocnaibill/codice-ereader-plugin/releases), baixa o zip, confere o SHA-256 publicado e a sintaxe de cada arquivo, coloca a versão nova guardando a atual em `codice.koplugin.old` e pede para reiniciar. **Voltar à versão anterior do plugin** desfaz. Desde a 0.3.1 o zip pode ter pastas (cada caminho é conferido: só nomes simples, até 6 níveis, nunca `..`), e cada arquivo `.lua` de qualquer pasta tem de carregar antes de a versão nova ser posta no lugar. O código baixado é executado pelo KOReader: a confiança é a do dono do repositório e do HTTPS, a mesma do OTA do KOReader.

Para publicar uma versão: suba `PLUGIN_VERSION` em `codice_core.lua` e crie a tag `vX.Y.Z`; o workflow `release` confere, empacota e cria o release com o zip e o hash.

## O que o plugin guarda

`koreader/settings/codice.lua` guarda o endereço, o usuário e o acesso (a senha curta do leitor, que você revoga em Aplicativos). O KOReader também guarda esse acesso em `settings/opds.lua` e a chave dele em `settings/kosync.lua`, como sempre fez com qualquer servidor.

## Diagnóstico

**Códice → Diagnóstico (protótipo)** tem os testes do protótipo (conexão, configuração ao vivo, capas, eventos de anotação). Tudo fica em `koreader/codice_proto.log`.

## Desenvolvimento

```bash
luajit tests/run.lua      # a lógica que não precisa do KOReader
```

| Arquivo | O que tem |
|---|---|
| `codice/core.lua` | endereço, versões, o que cada resposta do servidor significa, o que se escreve no OPDS e no KOSync, caminhos do zip (puro, testado) |
| `codice/http.lua` | pedidos JSON com os tempos do KOReader |
| `codice/pairing.lua` | o fluxo na tela: endereço, código, QR, espera da aprovação |
| `codice/data.lua`, `codice/covers.lua` | a última home do servidor guardada em arquivo e a atualização quieta dela; as capas guardadas em arquivo |
| `codice/modules/` | os módulos do Códice para a home do Simple UI (registrados em `codice/plugin.lua`, carregados só quando o Simple UI lista os módulos) |
| `codice/home.lua` | a tela inicial antiga do Códice: coluna que rola, capas que chegam depois, toque numa obra |
| `codice/update.lua` | a atualização do plugin (download, hash, caminhos, sintaxe, troca, volta atrás) |
| `codice/plugin.lua` | o módulo do Códice: menu, guardar o acesso, aplicar a configuração, abrir livros, atualizar quando a rede volta; é registrado pelo `main.lua` |
| `codice/diag.lua` | os testes do protótipo |
| `main.lua`, `infra/`, `screens/`, `engines/`, `features/`, `modules/`, `icons/`, `locale/` | o Simple UI (ver `UPSTREAM.md`) |

### A home pronta

No menu do Códice, **Montar a home do Códice** troca os módulos da home do Simple UI por uma home já montada, numa página: saudação, números e continuar lendo. Na primeira vez que o leitor abre sem estar conectado, o plugin oferece conectar (uma vez só; depois, a entrada fica em Códice → Conectar). Na primeira vez que o leitor é conectado a um Códice, essa home já é montada sozinha (uma vez só: depois a home é sua, e a entrada do menu serve para refazê-la). Favoritos e prateleiras seguem como módulos, para adicionar se quiser; o lugar deles é a tela da biblioteca. A mesma home aparece em **Presets** do Simple UI, com o nome "Códice". Ela substitui o layout atual: para guardar o seu, salve-o antes como predefinição.

### A prateleira (o que o leitor guarda dos livros que tem)

Ao baixar um livro, o plugin o põe numa **prateleira** local (`settings/codice_shelf.json`): título, autores, categorias, série, arquivos, favorito e quanto você leu. Ela é conferida contra os arquivos que existem (um livro apagado pelo explorador some dela) e atualizada com o servidor sempre que há rede (ao abrir a home com Wi-Fi). É a base da Biblioteca que funciona sem conexão (DEC-198): sem rede, categorias, autores, séries, favoritos e formatos saem dela. Livros baixados antes da prateleira são reconhecidos pelo nome do arquivo (`<id> - título.ext`) e preenchidos pelo servidor na primeira conexão. Precisa do servidor com a rota `GET /device/shelf`.

### A Biblioteca

Em **Códice → Biblioteca** (e como ação "Biblioteca do Códice" para uma aba ou botão do Simple UI) abre a Biblioteca do Códice (DEC-198), uma tela só dela, sem rolagem: uma página de cada vez, virada com um toque no pé da tela ou um deslize.
- **Raiz:** Categorias, Autores, Séries e coleções, Formatos, No aparelho e Todas as obras; "Buscar" procura por título e autor. **Autores** abre numa letra (a primeira que existe), com as letras no alto, e cada página traz tantos nomes quanto cabem na tela; se a letra tem mais, vira-se a página.
- **Séries:** numa grade, uma série (quadrinho ou mangá com vários volumes ou capítulos) aparece como um cartão só, com "5 capítulos" embaixo; tocar nele (ou numa série da lista Séries e coleções) abre a **página da série**, no molde da ficha de um livro: capa, nome, "5 capítulos · 1 lido", o botão **Continuar: Cap. 5 (60%)** (ou Próximo / Começar, as palavras da web) e, embaixo, os capítulos ou volumes na ordem da série, cada um com "lido", a porcentagem ou "no aparelho"; tocar num capítulo o abre, baixando se preciso. Sem conexão, a página mostra os da série que estão no aparelho. Numa série longa, só a primeira página tem a capa e o botão; as seguintes são só linhas (cabem mais), e o título da lista ("6–15 de 60 · Ir para") abre as partes para pular direto.
- **Lista de obras:** grade de capas 3×2 com a marca ↓ nas obras que estão no aparelho e a barra de progresso; filtros Todas, Baixadas e Lendo; "Ordem" por título, autor ou mais novas.
- **Ficha da obra:** série, quanto você leu, categorias e os arquivos (idioma e formato; "no aparelho" ou "baixar · tamanho"). **Ler** abre o melhor arquivo (o último lido, senão o principal), baixando se precisar; **Remover do aparelho** apaga só a cópia local, o progresso fica no Códice.
- **Sem conexão** (Wi-Fi desligado ou servidor fora do ar): uma faixa avisa, e a Biblioteca mostra só o que está no aparelho, com os números do aparelho, lendo da prateleira.

Os testes de tela rodam com um KOReader de mentira (`tests/library_stub.lua`): pegam erro de lógica e de digitação, não provam o desenho no aparelho.

### A barra de abas

A barra de baixo do Simple UI tem as cinco abas do Códice, com os ícones do próprio Simple UI: **Acervo** (a home), **Em leitura** (o que você está lendo, o último aberto primeiro), **Favoritos**, **Anotações** (suas notas e destaques, mais novos primeiro; precisam de conexão) e **Biblioteca**. A aba acesa acompanha a tela. A raiz de cada aba não tem "voltar": a barra é a saída. As entradas que saíram da barra (arquivos do KOReader, configurações, energia, atualizar o plugin) estão em **Biblioteca → Mais**. A barra é montada junto com a home na primeira conexão; quem já tinha o plugin usa **Códice → Montar a barra de abas do Códice**.

### A pergunta de conflito

Ao abrir um livro com Wi-Fi, o plugin compara o lugar daqui com o que o Códice guardou (a web, ou outro leitor). Se estão a mais de um ponto de distância, aparece a tela **Conflito de progresso detectado** (DEC-196), com os dois lugares, um sobre o outro: quem e há quanto tempo, quanto do livro, o capítulo e o trecho (o do Códice vem em palavras do servidor; o daqui, o capítulo do sumário), a divergência em pontos e dois botões: **Avançar (ou Voltar) para N% (web)** e **Permanecer em N% (aqui)**. Fechar é permanecer. Ela substitui a pergunta genérica do KOSync ("Sync to latest location?"), que o plugin desliga na configuração; quem escolheu sincronizar em silêncio continua assim. Cobre também a cópia recém-baixada, que começa na primeira página enquanto o servidor sabe onde você parou. O trecho e o capítulo do lado do Códice precisam do servidor com `GET /device/progress/files/{id}/compare`; sem ele, a tela mostra só os percentuais.

### Destaques e notas, os mesmos aqui e no Códice

Num EPUB baixado do Códice, o que você grifa ou anota no KOReader vai para o Códice (e aparece na aba Anotações e no web), e o que está no Códice e ainda não está no livro é trazido para ele ao abri-lo: o trecho é achado no livro pelo texto, a partir do parágrafo que o web guardou, e aparece como qualquer destaque do KOReader (na lista de marcadores, nas exportações dele). Editar a nota ou apagar o destaque vale dos dois lados; sem rede, a mudança fica numa fila no livro e segue ao reconectar. Apagar aqui apaga no Códice o que o aparelho criou ou já recebeu de lá; o que só existe no web e nunca veio ao aparelho não é tocado. Não há cor (o Kindle é preto e branco): o destaque novo daqui recebe a cor padrão do Códice, o editado mantém a sua, e o que veio do web chega com o traço padrão. PDF e quadrinhos ficam para depois. Precisa do servidor com `PUT`/`DELETE`/`GET /device/files/{id}/notes`.

### Tela de bloqueio

A tela de bloqueio do KOReader mostra a capa de uma das obras baixadas do Códice **cobrindo a tela inteira** (cortada nas bordas, nunca esticada), uma diferente a cada vez que o leitor dorme, com a palavra **Códice** no canto inferior esquerdo, sobre uma etiqueta branca para ler em qualquer capa; sem nenhuma obra baixada, só a palavra no canto. O plugin faz as imagens (a capa sobre a tela toda, até 12 obras) numa pasta própria e aponta o protetor de tela do KOReader para ela; elas são refeitas quando as obras do aparelho mudam. Vem ligada; em **Códice → Tela de bloqueio com as capas** liga e desliga, e desligar devolve o protetor de tela que você tinha.

### Detalhes

- Ao fechar um livro aberto pela Biblioteca, a Biblioteca volta para onde você estava (a mesma página da série, da lista...).
- Em listas de até três obras (Favoritos com poucos, por exemplo), as capas usam a largura toda.
- Depois de uma atualização, o aviso diz "Códice atualizado neste Kindle para a versão X.Y.Z".
