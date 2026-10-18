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
| **Códice: Continuar lendo** | os livros que você está lendo no Códice, com capa, progresso e título; tocar numa obra a abre (baixando o arquivo, se ele ainda não está no aparelho, e perguntando qual quando há mais de um) |

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
