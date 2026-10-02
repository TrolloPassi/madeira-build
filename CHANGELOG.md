# Changelog

## Aktuell

### Behoben
- **Direkte x64-Systemaufrufe in Kindprozessen** (`patches/wine/0001`).
  Manche Spiele rufen Windows-Systemfunktionen direkt mit der
  `syscall`-Instruktion auf. Wines `ntdll` gab FEX dafür die Adresse eines
  x86-Hilfsstücks aus Madeiras JIT-Speicherkopie statt der echten Adresse.
  Im ersten Prozess fing FEX das ab, in einem vom Spiel gestarteten zweiten
  Prozess nicht, und das Spiel stürzte mit „NoExec instruction in entry block“
  ab. Betroffen war z. B. Minecraft Dungeons
  (`Dungeons-Win64-Shipping.exe`). *Noch nicht auf dem Gerät bestätigt.*
- **Hänger bei atomaren Zugriffen über eine 16-Byte-Grenze**
  (`patches/fex/0001`). `lock cmpxchg`/`xadd`/`xchg` usw. auf Adressen, die
  eine 16-Byte-Grenze überschreiten, lösten auf ARM pro Zugriff eine Ausnahme
  aus. Minecraft Dungeons hatte davon über 800.000 an einer Stelle. Solche
  Zugriffe laufen jetzt über einen gesperrten Pfad im übersetzten Code.
- **Steam-Spiele ohne Startoption „0“** (`patches/madeira-dock/0001`).
  Madeira Dock fragte Steam immer nach Startoption 0. Spiele wie PEAK haben
  aber nur andere Optionen, Steam lehnte mit Fehler 22 ab. Jetzt werden bei
  Fehler 22 die Optionen 1, 2, 3 … durchprobiert.

### Neu
- `env.MADEIRA_DOCK_LAUNCH_OPTION = <Nr>` in `madeira.cfg`: feste
  Steam-Startoption, z. B. `6` für PEAK mit DX11.
- `env.MADEIRA_DOCK_LAUNCH_ARGS = <Argumente>` in `madeira.cfg`: zusätzliche
  Startargumente für Steam.

### Enthalten
- Microsoft Visual C++ Runtime x64 (12 DLLs, unverändert und signiert) in
  `Madeira.app/x86_64-vcruntime/`.
