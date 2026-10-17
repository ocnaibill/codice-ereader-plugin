# codice-ereader-plugin

Plugin do [Códice](https://github.com/ocnaibill/codice) para o KOReader (Kindle com jailbreak, no começo). Conecta o leitor à sua instância por um **código aprovado no site** (sem digitar senha na tela e-ink) e mantém no aparelho a configuração do catálogo (OPDS) e da sincronização de progresso (KOSync). Plano e decisões: issue [ocnaibill/codice#327](https://github.com/ocnaibill/codice/issues/327) e a proposta `docs/Codice_Proposta_Pareamento_Leitor_2026-10-17.md` do Códice. Licença AGPLv3, como o KOReader e o Códice.

**Estado:** a lógica (`codice_core.lua`) tem testes; as telas e o pareamento **ainda não foram testados num aparelho**. Testado antes, num Kindle 10ª geração com KOReader v2026.07.2: HTTPS com a instância, configuração do OPDS ao vivo, capas numa lista e eventos de anotação (o protótipo, hoje em *Diagnóstico*).

## Instalar

1. Ligue o Kindle ao computador por USB e copie a pasta `plugins/codice.koplugin` para `koreader/plugins/` (fica `koreader/plugins/codice.koplugin/main.lua`).
2. Ejete o Kindle, abra o KOReader (reinicie se já estava aberto) e ligue o Wi-Fi.

## Conectar

1. Menu superior (ferramentas) → **Mais ferramentas → Códice → Conectar**.
2. Digite o endereço da sua instância (por exemplo `codice.exemplo.com`). O leitor mostra um código de oito letras e números; **Mostrar QR** mostra o endereço de aprovação como QR.
3. No site: **Minha conta → Aplicativos → Conectar um leitor** (ou leia o QR), digite o código, confira o aparelho e **Aprove**.
4. O leitor recebe sozinho o acesso e a configuração: o catálogo "Códice" aparece no **Catálogo OPDS** e a sincronização de progresso fica pronta (abra um livro e vire umas páginas). Se você já abriu um livro nesta sessão, reinicie o KOReader uma vez.

Depois disso, quando o Wi-Fi volta (no máximo a cada 6 horas), o plugin pergunta à instância se a configuração mudou e aplica só o que mudou. **Códice → Atualizar a configuração** faz isso na hora. **Desconectar este leitor** tira o catálogo e a sincronização do aparelho; para tirar o acesso do servidor, remova-o em Aplicativos, no site.

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
| `main.lua` | o plugin: menu, guardar o acesso, aplicar a configuração, atualizar quando a rede volta |
| `codice_diag.lua` | os testes do protótipo |
