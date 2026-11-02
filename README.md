# Asteroids VR (Godot 4.6, Meta Quest 3)

Asteroids w kokpicie, w przestrzeni z periodycznymi brzegami (3-torus).
Kod (wszystko budowane z kodu, scena `main.tscn` ma tylko korzeń):

| plik | co |
|---|---|
| `scripts/main.gd` | środowisko, gwiazdy, stan gry: wynik, życia, fale, pauza, game over |
| `scripts/torus.gd` | `Torus` — rozmiar świata, mgła, `wrap_pos` / `wrap_delta` |
| `scripts/ship.gd` | `Ship` — rig XR, kokpit, sterowanie, lot, działka, haptyka |
| `scripts/dashboard.gd` | `Dashboard` — zegary w kokpicie + komunikat PAUZA / GAME OVER |
| `scripts/sound.gd` | `Sound` — dźwięk 3D: działka, wybuchy w miejscu świata, dudnienie 4 najbliższych skał, silnik, alarmy |
| `scripts/sfx_synth.gd` | `SfxSynth` — synteza wszystkich efektów do `AudioStreamWAV` przy starcie (brak plików audio) |
| `scripts/ufo.gd` | `Ufos` — latający spodek: lot wokół gracza, strzały z wyprzedzeniem, dźwięk 3D |
| `scripts/powerups.gd` | `PowerUps` — kryształy: tarcza, potrójny strzał, życie, bomba |
| `scripts/title_screen.gd` | `TitleScreen` — ekran startowy z rekordem i instrukcją |
| `scripts/gauge.gd` | `Gauge` — analogowy zegar: tarcza (pieczona raz do tekstury z mipmapami), wskazówka 3D, licznik cyfrowy, kontrolka |
| `scripts/rock_field.gd` | `RockField` — skały: siatki, fale, ruch, pękanie, testy kolizji |
| `scripts/bullets.gd` | `Bullets` — pociski i trafienia |

## Sterowanie

| Quest | Desktop | Akcja |
|---|---|---|
| prawy drążek ↕ | ↑ ↓ | pochylenie (lotniczo, `INVERT_PITCH`) |
| prawy drążek ↔ | ← → | odchylenie (yaw) |
| lewy drążek ↔ | Q / E | przechył (roll) |
| lewy spust | W | ciąg |
| lewy grip | S | hamowanie |
| prawy spust | spacja | ogień (dwa działka na zmianę, zbieżne na celowniku) |
| lewy przycisk menu (≡) | P | pauza (też automatycznie przy menu Meta / zdjęciu gogli) |
| — | Esc | wyjście |

Zegary na desce: **życia** (lewy, kontrolka = ostatnie życie / miga po
zderzeniu), **prędkość** + licznik **wyniku** (środek), **skały do zniszczenia
w fali** w % + numer **fali** (prawy).

## Rozgrywka

- **Ekran startowy**: rekord (zapisany w `user://asteroids.cfg`), ostatni
  wynik, skrót sterowania. Start: prawy spust (desktop: spacja / Enter).
- **UFO** co 18–30 s: duży (200 pkt, niecelny) lub od 3. fali mały
  (1000 pkt, celny). Krąży wokół gracza i strzela z wyprzedzeniem;
  słychać go przestrzennie. Zawsze zostawia power-up.
- **Power-upy** (8% szansy ze skały, zawsze z UFO; zbiera się przelatując):
  **T** tarcza 10 s (taranuje skały, chroni przed UFO), **3** potrójny
  strzał 12 s, **+** życie (max 5), **B** bomba (wszystko w promieniu 70 m).

Recentrowanie widoku: przytrzymaj przycisk Meta na prawym kontrolerze.

## Uruchomienie na Linuksie (desktop)

```
godot --path .          # bez gogli startuje w trybie klawiaturowym
```

## Build na Questa

```
tools/build.sh          # debug APK -> build/asteroids-vr.apk
tools/build.sh run      # + adb install i start na goglach
tools/build.sh log      # adb logcat -s godot
```

Preset eksportu „Quest” (`export_presets.cfg`): Gradle, arm64, OpenXR,
plugin Meta, Quest 2/3/Pro. Katalogi `android/`, `build/`, `.godot/`
są generowane (w `.gitignore`).

### Środowisko (stan na 2026-11)

| Co | Skąd | Gdzie |
|---|---|---|
| Godot 4.6.3 | `apt install godot` | `/usr/bin/godot` |
| szablony eksportu 4.6.3 | github.com/godotengine/godot, `.tpz` | `~/.local/share/godot/export_templates/4.6.3.stable/` |
| JDK 17 (Temurin) | adoptium.net | `~/opt/jdk17` |
| Android SDK: platform 36, build-tools 36.1.0, NDK 29.0.14206865, platform-tools | `sdkmanager` | `~/opt/android-sdk` |
| debug keystore | `keytool` | `~/.local/share/godot/keystores/debug.keystore` |
| Godot OpenXR Vendors 5.1.0 | GitHub GodotVR | `addons/godotopenxrvendors/` |

Ścieżki JDK/SDK są w ustawieniach edytora (`~/.config/godot/editor_settings-4.6.tres`).
Wersje SDK/NDK wynikają z `config.gradle` w `android_source.zip` — przy
zmianie wersji Godota sprawdź je ponownie. Szablony muszą mieć dokładnie
tę samą wersję co edytor; plugin vendors 5.x wymaga Godota ≥ 4.6.

### Gogle

1. **Tryb deweloperski**: aplikacja Meta Horizon na telefonie → Urządzenia →
   Ustawienia słuchawek → Tryb dewelopera (wymaga „organizacji” na
   developers.meta.com).
2. Reguły udev dla USB: paczka `android-udev-rules` (już zainstalowana, obejmuje Meta 2833)
   + członkostwo w grupie `plugdev`.
3. Podłącz Questa kablem, zaakceptuj debugowanie USB w goglach,
   `~/opt/android-sdk/platform-tools/adb devices` powinno go pokazać.
4. W edytorze działa też Remote Deploy (ikona Androida w prawym górnym rogu).
   Gra trafia do Biblioteki → „Nieznane źródła”.

## Jak to działa

- **3-torus**: logiczne pozycje leżą w `[0, L)^3`. Statek stoi fizycznie
  w (0,0,0) sceny, a każdy obiekt jest rysowany w minimalnym obrazie
  `wrap_delta(pos - ship_pos)`. Mgła (`FOG_END` < L/2) maskuje przeskoki.
  Gwiazdy są „w nieskończoności”, więc nie mają paralaksy translacji.
- **Komfort**: stała rama kokpitu w polu widzenia, wygładzona prędkość
  kątowa (`ROT_SMOOTH`) i limity obrotu. Jeśli mdli, najpierw zmniejsz
  `MAX_ROLL`.
- **Pękanie**: dwa odłamki dostają ±kick prostopadle do kierunku trafienia,
  więc pęd jest zachowany.
- **Kolizje pocisków**: test odcinek–kula, bo przy 220 m/s pocisk przelatuje
  ~3 m na klatkę.

## Pomysły na dalej

- Winieta przy obrotach (opcja komfortu).
- Gałka/drążek fizyczny w kokpicie zamiast thumbsticków.
- Ghost-render kopii sześcianu, żeby *zobaczyć* torus. Wymaga mgły > L/2.
- Przeniesienie pętli kolizji do C++ (GDExtension), jeśli skał będzie setki.
