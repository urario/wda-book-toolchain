# wda-book-toolchain

Re:VIEWで書いた原稿を組版・検査するためのコンテナイメージです。どの環境でも同じバイト列のイメージを使い、同じ原稿から同じPDF・EPUBを作るために使います。

イメージに入っているのは、公開されているツールとフォントだけです。

## 使い方

digestを指定して取得します。

```bash
docker pull ghcr.io/urario/wda-book-toolchain@sha256:<digest>
docker run --rm ghcr.io/urario/wda-book-toolchain@sha256:<digest> cat /opt/toolchain/versions.txt
```

## 版の固定

同じDockerfileから同じ中身になるよう、次をすべて固定しています。

| 対象 | 固定の方法 |
| --- | --- |
| 基点のイメージ | `ubuntu:24.04` と `node:22-bookworm-slim` をdigestで指定 |
| aptのパッケージ | `snapshot.ubuntu.com` の日付（`APT_SNAPSHOT`） |
| Re:VIEW、rake、minitest | `Gemfile.lock` |
| textlintと規則 | `package-lock.json` |
| PlantUML、epubcheck、draw.io | 版とsha256（Dockerfileの `ARG`） |

LuaTeXのフォントキャッシュ（Noto CJK）は、ビルド時に `test/font-warmup.tex` を組んで作ります。組版のたびに作ると、1回に1分ほど余計にかかるためです。

## 版を上げる手順

1. Dockerfileの `ARG`、`apt-packages.txt`、`Gemfile`、`package.json` のいずれかを変え、ロックファイルを更新します。
2. PRを作ると、Actionsがビルドとスモークテストを行います（公開はしません）。
3. mainにマージすると、Actionsが `ghcr.io/urario/wda-book-toolchain` へpushし、ジョブのサマリーにdigestとコミットSHAを出します。

TLSを中継するプロキシの内側でビルドするときは、追加のCAをBuildKitのsecret（`id=extra_ca`）で渡します。secretはイメージのレイヤーに残りません。

## 中身とライセンス

| ツール | ライセンス |
| --- | --- |
| Re:VIEW | MIT |
| TeX Live（Ubuntuのパッケージ） | 各パッケージのライセンス（主にLPPL・GPL） |
| Noto CJK、Noto | SIL Open Font License 1.1 |
| PlantUML | GPL v3（jarの版による） |
| draw.io desktop | Apache License 2.0 |
| epubcheck | BSD 3-Clause |
| textlintと規則 | MIT |
| OpenJDK | GPL v2 with Classpath Exception |

このリポジトリのDockerfileとスクリプトはMITライセンスです（[LICENSE](LICENSE)）。
