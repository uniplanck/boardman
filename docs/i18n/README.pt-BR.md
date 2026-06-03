# Board-Man

[English](../../README.md) / [ja](README.ja.md) / [zh-CN](README.zh-CN.md) / [es](README.es.md) / [pt-BR](README.pt-BR.md) / [ko](README.ko.md) / [de](README.de.md) / [fr](README.fr.md)

Board-Man é um app de produtividade para a área de transferência do macOS derivado do Clipy.

Ele mantém o histórico da área de transferência disponível na barra de menus e adiciona visibilidade orientada ao fluxo de trabalho para quem copia, cola, edita e move textos, URLs, comandos e imagens entre apps com frequência.

> Status: candidato público. Este repositório é uma edição open-source sanitizada, preparada a partir de uma build privada em desenvolvimento ativo.

## Captura de tela

![Board-Man main screenshot](../assets/board-man-main-screenshot.png)

## O que o Board-Man pode fazer

- Manter o histórico recente da área de transferência disponível na barra de menus.
- Salvar e colar snippets reutilizáveis.
- Mostrar badges de contagem de colagens para itens usados com frequência.
- Lidar com entradas de imagem da área de transferência, incluindo conteúdo apenas de imagem semelhante a capturas de tela.
- Pesquisar no histórico da área de transferência.
- Navegar pelo painel com o teclado.
- Fixar itens importantes.
- Ajustar atalhos, limites do histórico, comportamento do menu e opções de tema visual.
- Rodar localmente no macOS sem enviar o conteúdo da área de transferência para um serviço externo.

## Download

- [Baixar Board-Man v1.2.3](https://github.com/uniplanck/boardman/releases/tag/v1.2.3)
- Arquivo do app para macOS: `Board-Man-v1.2.3.zip`

## Instalação e primeira abertura

1. Baixe `Board-Man-v1.2.3.zip` na página da release.
2. Descompacte o arquivo.
3. Mova `Board-Man.app` para `/Applications`.
4. Abra o Board-Man.

Se o macOS Gatekeeper bloquear a primeira abertura, abra **System Settings > Privacy & Security** e permita o Board-Man, ou faça Control-click no app e escolha **Open**.

## Uso básico

1. Copie um texto, uma URL, um comando ou uma imagem como de costume.
2. Abra o Board-Man pela barra de menus.
3. Pesquise ou navegue pelo histórico da área de transferência.
4. Selecione um item para colá-lo no app ativo.
5. Use snippets para textos que você cola repetidamente.

## Histórico da área de transferência

O Board-Man armazena itens recentes da área de transferência para que você possa voltar a textos, URLs, comandos e entradas de imagem sem copiá-los de novo.

Use quando quiser:

- reutilizar algo copiado antes
- evitar alternar entre documentos só para copiar o mesmo texto de novo
- manter comandos ou URLs recentes por perto
- revisar o fluxo de trabalhos com muito copiar e colar

## Snippets

Snippets são entradas de texto reutilizáveis para frases, modelos, URLs, comandos e outros conteúdos que você cola com frequência.

Usos comuns:

- respostas repetidas
- modelos de comandos
- blocos de texto para marketing ou redes sociais
- mensagens de suporte
- URLs e textos curtos padronizados

## Badges de contagem de colagens

Os badges de contagem de colagens mostram quantas vezes um item foi colado.

Isso ajuda você a perceber:

- textos que reutiliza com frequência
- comandos que executa repetidamente
- recursos ou snippets centrais para seu fluxo de trabalho
- padrões de copiar e colar que talvez valham virar snippets ou automação

## Suporte a imagens da área de transferência

O Board-Man oferece suporte a entradas de imagem da área de transferência e pode mostrar conteúdo apenas de imagem na lista do histórico.

Isso é útil ao copiar:

- capturas de tela
- gráficos
- referências de design
- conteúdo visual da área de transferência entre apps

As entradas de imagem usam uma identidade baseada em timestamp, para que nomes genéricos como `TIFF image` ou `PNG image` não colidam nas contagens de colagem.

## Pesquisa e navegação por teclado

Use a pesquisa para filtrar o histórico da área de transferência. O painel foi projetado para uso pelo teclado, permitindo pesquisar, navegar pelos resultados e colar sem sair do fluxo de trabalho atual.

## Ajustes e aparência

O Board-Man inclui ajustes para comportamento do menu, atalhos, limites do histórico e aparência visual. Dependendo da build atual, você pode usar opções de tema e exibição mais clara para tornar o painel mais fácil de ler.

## Privacidade

O Board-Man é um utilitário local para macOS. O conteúdo da área de transferência é tratado localmente pelo app. Não armazene segredos, tokens, senhas ou dados privados de clientes no histórico da área de transferência, a menos que você entenda o risco.

## Licença e atribuição

O Board-Man é uma obra derivada fortemente modificada baseada no Clipy.

Este repositório preserva a atribuição e os avisos de licença do projeto original:

- `ATTRIBUTION.md`
- `LICENSE`
- `LICENSE_CLIPMENU`

O Board-Man é distribuído sob os termos da licença MIT herdados do Clipy. Ele não é endossado pelos mantenedores originais do Clipy ou do ClipMenu.
