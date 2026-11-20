# Corvelyx

ComputerCraft-System für ATM10 (CC: Tweaked): Control Center, Reaktoren, Matrizen, Turbinen, ME, Wetter, Flux, Lager.

## Wie die Updates laufen

```
GitHub (privat) ──Token──> Update-Computer ──Funknetz, signiert──> alle Corvelyx-Computer
```

- Jeder Computer hat `lader.lua` als `startup.lua`. Beim Start fragt er den Update-Computer nach seinem Programm.
- Der Update-Computer prüft dieses Repo alle 10 Minuten bzw. sofort, wenn im Control Center unter **LOG → UPDATE** gedrückt wird.
- Ändert sich eine Datei, starten **nur die Computer neu, die genau dieses Programm haben**.
- Netzname, Passwort, Namen und eigene Einstellungen stehen auf jedem Computer in `corvelyx.cfg`, **nie in diesem Repo**.

## Ordner `programme`

| Datei | Computer |
|---|---|
| `lader.lua` | auf jedem Computer (wird zur `startup.lua`) |
| `update_server.lua` | Update-Computer (einziger mit GitHub-Token) |
| `corvelyx_cc.lua` | Control Center |
| `corvelyx_pocket.lua` | Advanced Pocket Computer |
| `reaktor_waechter.lua` | Fission Logic Adapter |
| `fusion_reaktor.lua` | Fusion Logic Adapter |
| `xtreme_reaktor.lua` | Extreme Reactors Computer Port |
| `corvelyx_sender.lua` | Induction Port / Turbine Valve / ME Bridge (Name in der cfg) |
| `flux_sender.lua` | Flux Plugs (Energy Detectors) |
| `lager_sender.lua` | Functional Storage Controller |
| `corvelyx_wetter.lua` | Wetter-PC |

## Einrichtung eines Computers

1. Laufendes Programm mit **Strg+T** beenden.
2. `lader.lua` in das Computerfenster ziehen.
3. `lader` eintippen. Das alte Programm und seine Einstellungen werden erkannt und übernommen (Sicherung: `startup_alt.lua`).

Einstellungen später ändern: `edit corvelyx.cfg`
