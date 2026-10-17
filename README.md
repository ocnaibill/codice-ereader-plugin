# codice-ereader-plugin

Plugin do [Códice](https://github.com/ocnaibill/codice) para o KOReader (Kindle com jailbreak, no começo). Conecta o leitor à sua instância por um **código aprovado no site** (sem digitar senha na tela e-ink) e mantém no aparelho a configuração do catálogo (OPDS) e da sincronização de progresso (KOSync). Plano e decisões: issue [ocnaibill/codice#327](https://github.com/ocnaibill/codice/issues/327) e a proposta `docs/Codice_Proposta_Pareamento_Leitor_2026-10-17.md` do Códice. Licença AGPLv3, como o KOReader e o Códice.

**Estado:** o pareamento e a tela inicial funcionam num Kindle 10ª geração (testados pelo mantenedor). Na versão 0.3.0: a home rola, abre sozinha ao iniciar e ao fechar um livro, pergunta qual arquivo abrir e avisa quando um livro novo no aparelho começaria do início; **isso ainda não foi testado num aparelho**. A lógica (`codice_core.lua`) tem testes. Testado antes, num Kindle 10ª geração com KOReader v2026.07.2: HTTPS com a instância, configuração do OPDS ao vivo, capas numa lista e eventos de anotação (o protótipo, hoje em *Diagnóstico*).

## Instalar

1. Ligue o Kindle ao computador por USB e copie a pasta `plugins/codice.koplugin` para `koreader/plugins/` (fica `koreader/plugins/codice.koplugin/main.lua`).
2. Ejete o Kindle, abra o KOReader (reinicie se já estava aberto) e ligue o Wi-Fi.

## Conectar

1. Menu superior (ferramentas) → **Mais ferramentas → Códice → Conectar**.
2. Digite o endereço da sua instância (por exemplo `codice.exemplo.com`). O leitor mostra um código de oito letras e números; **Mostrar QR** mostra o endereço de aprovação como QR.
3. No site: **Minha conta → Aplicativos → Conectar um leitor** (ou leia o QR), digite o código, confira o aparelho e **Aprove**.
4. O leitor recebe sozinho o acesso e a configuração: o catálogo "Códice" aparece no **Catálogo OPDS** e a sincronização de progresso fica pronta (abra um livro e vire umas páginas). Se você já abriu um livro nesta sessão, reinicie o KOReader uma vez.

Depois disso, quando o Wi-Fi volta (no máximo a cada 6 horas), o plugin pergunta à instância se a configuração mudou e aplica só o que mudou. **Códice → Atualizar a configuração** faz isso na hora. **Desconectar este leitor** tira o catálogo e a sincronização do aparelho; para tirar o acesso do servidor, remova-o em Aplicativos, no site.

## Tela inicial

O Códice é a primeira tela: ao iniciar o KOReader, e toda vez que você fecha um livro, a home abre sozinha (mostra a última que o servidor mandou e atualiza se o Wi-Fi já estiver ligado, sem pedir). **Códice → Abrir o Códice ao iniciar** liga e desliga isso; o **Menu** da home tem **Arquivos do KOReader** para ir aos arquivos.

A home segue a da web, numa coluna que rola (deslize para cima e para baixo; ela para no começo de uma linha): saudação e números, **Continuar lendo**, **Favoritos**, algumas anotações e as **prateleiras** por categoria. As capas chegam depois da tela, algumas por vez.

Tocar numa capa abre o livro: **Ler**/**Continuar**. Se a obra tem mais de um arquivo, o plugin pergunta qual (`Português - EPUB (principal)`, `Inglês - PDF (último acessado, 20%)`...). O arquivo é baixado para a pasta `Códice` dentro da pasta de leitura (se ainda não estiver no aparelho). Isso exige um Códice com `GET /device/home` e `GET /device/works/{id}/files` (DEC-195).

**Livro novo no aparelho:** se você abre um livro que o servidor já tem lido por este mesmo Kindle e a cópia do aparelho está no começo (um download novo), o plugin pergunta "Continuar de onde parou?". Sem isso, o KOReader não pergunta e a próxima virada de página mandaria "o começo" por cima do seu progresso.

## Atualizar o plugin

**Códice → Procurar atualização do plugin** (e, quando o Wi-Fi volta, no máximo uma vez por semana, um aviso) olha a versão mais nova nos [releases](https://github.com/ocnaibill/codice-ereader-plugin/releases), baixa o zip, confere o SHA-256 publicado e a sintaxe de cada arquivo, coloca a versão nova guardando a atual em `codice.koplugin.old` e pede para reiniciar. **Voltar à versão anterior do plugin** desfaz. O código baixado é executado pelo KOReader: a confiança é a do dono do repositório e do HTTPS, a mesma do OTA do KOReader.

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
| `codice_core.lua` | endereço, versões, o que cada resposta do servidor significa, o que se escreve no OPDS e no KOSync (puro, testado) |
| `codice_http.lua` | pedidos JSON com os tempos do KOReader |
| `codice_pairing.lua` | o fluxo na tela: endereço, código, QR, espera da aprovação |
| `codice_home.lua` | a tela inicial: coluna que rola, capas que chegam depois, toque numa obra |
| `codice_update.lua` | a atualização do plugin (download, hash, sintaxe, troca, volta atrás) |
| `main.lua` | o plugin: menu, guardar o acesso, aplicar a configuração, abrir livros, atualizar quando a rede volta |
| `codice_diag.lua` | os testes do protótipo |
