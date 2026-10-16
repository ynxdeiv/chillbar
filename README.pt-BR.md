<p align="center">
  <img src="docs/images/icon.png" width="128" alt="Ícone do Chillbar">
</p>

<h1 align="center">Chillbar</h1>

<p align="center">
  <b>Seu ar-condicionado direto na barra de menus do Mac.</b><br>
  Ligue, ajuste a temperatura e troque o modo com um clique — direto pelo Wi-Fi, sem nuvem.
</p>

<p align="center">
  <a href="https://github.com/ynxdeiv/chillbar/releases/latest/download/Chillbar.dmg"><b>⬇️ Baixar para macOS</b></a> ·
  <a href="README.md">🇺🇸 Read in English</a>
</p>

<p align="center">
  <img src="docs/images/popover-light.png" width="380" alt="Chillbar no modo claro">
  <img src="docs/images/popover-dark.png" width="380" alt="Chillbar no modo escuro">
</p>

## O que ele faz

- **Controle em um clique** na barra de menus: liga/desliga, temperatura, modo, ventilação, oscilar, turbo, dormir, IonAir, visor e mais — os mesmos botões do controle remoto.
- **Rápido e privado:** depois da configuração, o Chillbar fala com o ar **direto pelo seu Wi-Fi**. O próprio aparelho confirma cada comando em cerca de meio segundo.
- **Sempre sincero:** mostra *Enviando…* até o ar confirmar e avisa se ele não confirmar.
- **Conhece o seu modelo:** trava o que o aparelho trava (por exemplo, no Elgin Eco Inverter III o modo Auto fixa 25 °C).
- **Tempo ligado e consumo estimado** enquanto o ar funciona.
- Visual **Liquid Glass** no macOS 26, tema claro e escuro, **português e inglês**.

## Instalar

1. **[Baixe o `Chillbar.dmg`](https://github.com/ynxdeiv/chillbar/releases/latest/download/Chillbar.dmg)**, abra e arraste o **Chillbar** para **Aplicativos**.
2. Abra o Chillbar. Como ele ainda não é autenticado pela Apple, o macOS bloqueia a primeira abertura:
   - Abra **Ajustes do Sistema → Privacidade e Segurança**, role até o fim e clique em **Abrir Mesmo Assim** ao lado de *Chillbar*.
   - Ou, no Terminal: `xattr -dr com.apple.quarantine /Applications/Chillbar.app`
3. Quando o macOS perguntar, **permita o acesso à Rede Local** — é assim que o Chillbar alcança o seu ar.

Precisa do macOS 14 Sonoma ou mais novo (Liquid Glass no macOS 26).

## Configurar em dois minutos

Você só precisa do celular com o app **Smart Life**:
[App Store](https://apps.apple.com/app/smart-life-smart-living/id1115101477) ·
[Google Play](https://play.google.com/store/apps/details?id=com.tuya.smartlife)

| | |
|---|---|
| **1. Adicione o ar no Smart Life.** Se ele está em outro app (como o *Elgin Smart*), remova de lá primeiro, reinicie o Wi-Fi do ar (Elgin: aperte **IONAIR 8×** no controle) e adicione no Smart Life. | <img src="docs/images/setup-welcome.png" width="300" alt="Boas-vindas"> |
| **2. Copie seu código de usuário.** No Smart Life: **Eu → ⚙ → Conta e Segurança → Código de usuário**. Cole no Chillbar. | <img src="docs/images/setup-userCode.png" width="300" alt="Código de usuário"> |
| **3. Escaneie o QR code** com o Smart Life (**Eu →** ícone de escanear) e toque em **Confirmar**. O Chillbar acha o ar no seu Wi-Fi e pronto. | <img src="docs/images/setup-scan.png" width="300" alt="Escanear o QR code"> |

A configuração abre sozinha na primeira vez. Para refazer: ícone na barra de menus → **⋯ → Configurar ar-condicionado…**

## Funciona com o meu ar-condicionado?

O Chillbar funciona com **ares-condicionados Wi-Fi feitos na plataforma Tuya** que usam o **protocolo local 3.3** — a mesma plataforma dos apps *Smart Life*, *Tuya Smart* e de muitos apps de marca.

| Situação | Ar-condicionado |
|---|---|
| ✅ **Testado** | **Elgin Eco Inverter III Wi-Fi** — 45HJFI12C2WF (12.000 BTU/h, só frio), app *Elgin Smart*, módulo Wi-Fi TYAUX-J2 |
| 🟡 **Deve funcionar** | Outros splits **Elgin** Wi-Fi controlados pelo app **Elgin Smart** (Eco Inverter II/III com módulo TYAUX-J ou TYAUX-J2) e ares **fabricados pela AUX** na plataforma Tuya com os mesmos pontos de dados |
| 🟡 **Talvez** | Outros ares Tuya (categoria *Ar-condicionado* no Smart Life). A conexão funciona, mas os botões podem precisar de um [perfil do aparelho](#adicione-o-seu-modelo) |
| ❌ **Ainda não** | Aparelhos com o app **Elgin Air** / *AC Freedom* (módulo Broadlink BLI206-P), aparelhos Tuya com protocolo 3.4/3.5 e ares só com infravermelho |

**Teste rápido:** se o seu ar funciona no app **Smart Life** (ou num app de marca que diga *Powered by Tuya*), é bem provável que seja compatível. Testou outro modelo? [Abra uma issue](https://github.com/ynxdeiv/chillbar/issues) e conte — ajuda todo mundo.

## Como funciona

- **Configuração (uma vez):** o Chillbar usa o SDK oficial de compartilhamento da Tuya — o mesmo login por QR do Home Assistant — para buscar a chave local do seu ar. Não precisa de conta de desenvolvedor da Tuya.
- **No dia a dia:** o Chillbar fala com o aparelho direto na sua rede (TCP 6668, descoberta pela UDP 6667). Nada passa por servidores do Chillbar — eles não existem.
- **A chave fica no seu Mac,** nas Chaves (Keychain). Nunca é exibida, registrada ou enviada a outro lugar.

> O login por QR usa o cadastro público de compartilhamento do Home Assistant, como outras ferramentas open source. Se a Tuya restringir esse cadastro, novas configurações vão precisar de uma chave de desenvolvedor da Tuya; os aparelhos já configurados continuam funcionando, porque a chave fica salva no seu Mac.

## Problemas comuns

| Problema | Solução |
|---|---|
| **“Sem conexão”** | Confira se o Mac e o ar estão no mesmo Wi-Fi e se a **Rede Local** está permitida em *Ajustes do Sistema → Privacidade e Segurança → Rede Local*. |
| **“O aparelho não confirmou”** | O ar pode estar fora de alcance ou o seu modelo pode não ter essa função. Tente de novo ou abra uma issue com o seu modelo. |
| **Parou depois de parear de novo** | Parear de novo no Smart Life muda a chave. Refaça a configuração: **⋯ → Configurar ar-condicionado…** |
| **Pedido de acesso às Chaves depois de atualizar** | Clique em **Sempre permitir** (versões de desenvolvimento são assinadas localmente). |

## Compilar o código

Precisa do Swift 6 (Xcode 16+ ou as Command Line Tools).

```bash
git clone https://github.com/ynxdeiv/chillbar.git
cd chillbar
scripts/test.sh        # roda os testes
scripts/build-app.sh   # build/Chillbar.app
scripts/make-dmg.sh    # build/Chillbar-<versão>.dmg
```

## Adicione o seu modelo

Cada modelo é descrito por um pequeno arquivo JSON em [`Sources/ACTuya/Profiles`](Sources/ACTuya/Profiles): qual ponto de dados liga o aparelho, a temperatura, os modos e o que cada modo permite. Copie o perfil do Elgin, ajuste para o seu aparelho e abra um pull request — não precisa saber Swift.

## Créditos

Feito por **deiv** — [GitHub](https://github.com/ynxdeiv) · [LinkedIn](https://www.linkedin.com/in/deivcst/) · [X](https://x.com/2003setembro)

Construído sobre o trabalho de [tinytuya](https://github.com/jasonacox/tinytuya), do [SDK de compartilhamento](https://github.com/tuya/tuya-device-sharing-sdk) da Tuya, do [tuya-local](https://github.com/make-all/tuya-local) e do [Home Assistant](https://www.home-assistant.io). Veja os [avisos de terceiros](THIRD_PARTY_NOTICES.md).

O Chillbar é um projeto independente, sem vínculo com Elgin, Tuya, Smart Life ou Apple. Todas as marcas pertencem aos seus donos.

## Licença

[Apache License 2.0](LICENSE)
