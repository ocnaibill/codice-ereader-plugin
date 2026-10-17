# codice-ereader-plugin

Plugin do Códice para o KOReader (Kindle com jailbreak, no começo). Plano e decisões: issue [ocnaibill/codice#327](https://github.com/ocnaibill/codice/issues/327). Licença AGPLv3, como o KOReader e o Códice.

**Estado: protótipo.** Ele só responde a quatro perguntas no aparelho, antes de se escrever o plugin de verdade.

## Instalar o protótipo (Kindle com KOReader)

1. Tenha no aparelho o `opds.lua` que o Códice gera em *Minha conta → Aplicativos* (já em `koreader/settings/opds.lua`). O protótipo lê o endereço e o acesso dali; nada fica gravado no plugin.
2. Ligue o Kindle ao computador por USB e copie a pasta `plugins/codice.koplugin` para `koreader/plugins/` (fica `koreader/plugins/codice.koplugin/main.lua`).
3. Ejete o Kindle, abra o KOReader (reinicie se já estava aberto) e ligue o Wi-Fi.
4. Menu superior → ferramentas (ícone de engrenagem/chave) → **Mais ferramentas → Códice (protótipo)**.

## O que testar, nesta ordem

| Item | O que fazer | O que me contar |
|---|---|---|
| 0. Ambiente | tocar | a versão do KOReader e o que aparece |
| 1. Conexão | tocar (com Wi-Fi) | o código HTTP, o tempo e quantas entradas |
| 2. Configuração ao vivo | tocar; depois abrir **Catálogo OPDS** sem reiniciar | se a entrada "Códice (protótipo)" aparece na lista |
| 2b. KOSync | abrir um livro e repetir o item 2 | o servidor que ele mostra |
| 3. Capas numa lista | tocar (com Wi-Fi) | se as capas aparecem, o aspecto e quanto demora |
| 4. Anotações | abrir um livro, destacar um trecho, voltar e abrir **5. Ver o log** | as linhas "4 anotações" |

Tudo o que o plugin faz fica em `koreader/codice_proto.log`; se preferir, cole o conteúdo desse arquivo.

Para desfazer o teste 2: no Catálogo OPDS, mantenha o dedo sobre a entrada "Códice (protótipo)" e apague, ou remova a pasta do plugin.
