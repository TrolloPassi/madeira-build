# madeira-build

Inoffizielle Test-Builds von [Madeira](https://github.com/willfaust/Madeira),
dem x86-Windows-Emulator für iPad/iPhone, mit ein paar Kompatibilitäts-Patches.
Kein Fork: Hier liegen nur Patches und ein GitHub-Actions-Workflow.

## Was der Build macht

Der Workflow [`build.yml`](.github/workflows/build.yml) nimmt die offizielle
Release-IPA von Madeira und ersetzt darin einzelne Windows-Dateien durch
Neubauten aus genau den Quell-Commits, die das Madeira-Release festschreibt,
plus die Patches aus [`patches/`](patches):

| Datei in `Madeira.app/` | Quelle | Patches |
|---|---|---|
| `arm64ec-windows/ntdll.dll` | [willfaust/wine](https://github.com/willfaust/wine) | [`patches/wine/`](patches/wine) |
| `arm64ec-windows/xtajit64.dll` | [willfaust/FEX](https://github.com/willfaust/FEX) | [`patches/fex/`](patches/fex) |
| `arm64ec-windows/dockhost.exe` | [willfaust/madeira-dock](https://github.com/willfaust/madeira-dock) | [`patches/madeira-dock/`](patches/madeira-dock) |
| `x86_64-vcruntime/*.dll` | Microsoft Visual C++ 2015–2022 Redistributable (x64), unverändert | – |

Alle anderen Dateien der IPA bleiben bitgleich zum Original. Gebaut wird auf
Linux- und Windows-Runnern mit llvm-mingw 20260421 (wie in Madeiras
`docs/BUILDING.md`), ein Mac ist nicht nötig. Vor dem Patchen wird `ntdll.dll`
einmal ungepatcht gebaut und mit dem Original verglichen. Weicht es ab, bricht
der Build ab.

Was sich geändert hat: [`CHANGELOG.md`](CHANGELOG.md).

## Komplettbuild auf macOS (`mac/`)

Der Workflow [`madeira-app.yml`](.github/workflows/madeira-app.yml) baut die ganze App aus
Madeiras Quellcode auf macOS-Runnern (in öffentlichen Repos kostenlos), inklusive der Teile,
die fest in die App-Binary gelinkt sind (Unix-Seite von Wine, wineserver, DXMT, FEXCore).
Stufen: [`mac/madeira-mac.sh`](mac/madeira-mac.sh), Patches: [`mac/patches/`](mac/patches)
(fex, wine, madeira, madeira-dock). VC++ Runtime, `i386-windows` und die aarch64-Dienste
kommen unverändert aus dem neuesten Release dieses Repos. Ergebnis: Vorab-Release
`madeira-<tag>-app-test`.

## Installieren

IPA aus den [Releases](../../releases) laden, in Feather oder SideStore
importieren und dort signieren. JIT (z. B. StikDebug) wie bei Madeira selbst.

Die Builds sind Vorabversionen zum Testen und nicht vom Madeira-Entwickler.
Fehler bitte nicht bei Madeira melden, ohne dazuzusagen, dass es dieser Build war.

## Lizenz

Die Patches stehen unter denselben Lizenzen wie die Projekte, die sie ändern:
Wine LGPL-2.1-or-later, FEX MIT, Madeira / madeira-dock GPL-3.0-or-later mit
Madeira Converter Exception. Die Quellen der gebauten Dateien sind die oben
verlinkten Commits plus diese Patches. Die Visual-C++-DLLs sind
Microsoft-Redistributables und stehen unter Microsofts Lizenzbedingungen.
