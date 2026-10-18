# Como este plugin acompanha o Simple UI

Este plugin é um **fork do [Simple UI](https://github.com/doctorhetfield-cmd/simpleui.koplugin)** (MIT, por Doctor Hetfield), com o Códice em cima. O histórico do Simple UI está neste repositório (importado por merge, com a autoria dos commits dele), e o remoto `upstream` aponta para ele.

- **Base atual:** Simple UI 2.7.5, commit `7eb80f9` ("fix: prevent Homescreen closure when main menu is open").

## Regras para o fork não virar um problema

1. **O código do Códice fica na pasta `codice/`**, nunca misturado aos arquivos do Simple UI. O plugin do Códice é um módulo que o `main.lua` registra em cada tela principal do KOReader (`require("codice/plugin").install(self.ui)`).
2. **Todo arquivo do Simple UI que alteramos está na lista abaixo.** Mexa em arquivo dele só quando for inevitável, e escreva aqui o que mudou e por quê.
3. **Atualizar o upstream é um merge, em pedaços**, a cada poucas semanas, olhando o que mudou:
   ```bash
   git fetch upstream
   git log --oneline HEAD..upstream/main      # o que entrou
   git diff HEAD...upstream/main --stat       # onde mexeram
   git merge upstream/main                    # os conflitos só podem estar na lista abaixo
   ```
   Depois do merge: `luajit tests/run.lua`, atualizar a "base atual" acima, subir a versão (`codice/core.lua` e `_meta.lua`) e testar no aparelho.
4. **Identidade própria:** a pasta do plugin é `codice.koplugin`; o `_meta.lua` mantém `name = "simpleui"` porque o código herdado procura por ele; as configurações continuam com o prefixo `simpleui_` na pasta `settings/simpleui/` (mudar isso agora criaria conflito em quase todo arquivo). O Simple UI original, se instalado ao lado, é desligado sozinho pelo `codice/plugin.lua`.
5. **Licenças:** os arquivos do Simple UI continuam MIT (`LICENSE.simpleui` acompanha o plugin, como a licença exige); os do Códice são AGPLv3 (`LICENSE`). Ver `NOTICE.md`.

## Arquivos do Simple UI que alteramos

| Arquivo | O que mudou | Por quê |
|---|---|---|
| `main.lua` | no começo de `SimpleUIPlugin:init()`, um `pcall` que chama `require("codice/plugin").install(self.ui)` | registra o módulo do Códice em cada tela principal, antes de qualquer coisa do Simple UI poder parar |
| `_meta.lua` | nome de exibição, descrição, autor e versão (a versão é a do Códice) | identidade do fork |
| `infra/sui_updater.lua` | no fim do arquivo, as funções públicas são trocadas por versões que não usam a rede e `checkForUpdates` chama o atualizador do Códice | o atualizador original instalaria o zip do Simple UI original por cima deste plugin |

Os arquivos `LICENSE`, `README.md` e `.gitignore` também diferem do upstream (o README e a licença dele estão em `README.simpleui.md` e `LICENSE.simpleui`), e **removemos `.github/FUNDING.yml`** (o link de apoio é do autor original, não nosso). O `CONTRIBUTING.md` é o dele e vale para o que mexe nos ganchos do KOReader (ver a seção "Patching KOReader classes").

## Como os módulos do Códice entram na home do Simple UI

Pelo registro de módulos externos que o próprio Simple UI oferece (`Registry.register("codice/modules/<nome>")`, feito em `codice/plugin.lua`), sem mexer em arquivo dele. Cada módulo é feito sobre `engines/sui_book_grid.lua` (`GridRenderer.makeModule`) com uma célula própria (`renderCell`), como o módulo de Coleções dele faz. **Se uma atualização do upstream mudar o contrato de `makeModule` (os campos `getFileList`, `renderCell`, `getCellHeight`), os módulos em `codice/modules/` são os primeiros a conferir.**

## Ideias para devolver ao upstream

Pontos de extensão genéricos que facilitariam o fork (módulos externos que desenham uma tela inteira, abas de barra registradas por plugin com título e ícone próprios). Se virarem pull request, deixam de ser alteração nossa.
