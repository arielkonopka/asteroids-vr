# Asteroids VR (Godot 4.6, Meta Quest 3)

Asteroids from the cockpit, in a space with periodic boundaries (a 3-torus):
fly out of one side of the cube and you come back in on the opposite side.

Everything is built from code — `main.tscn` contains only the root node.

| file | what |
|---|---|
| `scripts/main.gd` | environment, stars, game state: title → playing → game over, score, lives, waves, pause, power-up effects, high score |
| `scripts/torus.gd` | `Torus` — world size, fog, `wrap_pos` / `wrap_delta` |
| `scripts/ship.gd` | `Ship` — XR rig, cockpit, controls, flight, guns, haptics, shield bubble, nearest-rock locator |
| `scripts/dashboard.gd` | `Dashboard` — cockpit gauges, PAUSED / GAME OVER message, power-up status line |
| `scripts/gauge.gd` | `Gauge` — analog gauge: dial (baked once into a mipmapped texture), 3D needle, digital readout, warning lamp |
| `scripts/rock_field.gd` | `RockField` — asteroids: meshes, waves, motion, splitting, collision tests |
| `scripts/bullets.gd` | `Bullets` — player shots and hits |
| `scripts/ufo.gd` | `Ufos` — flying saucer: orbits the player, leads its shots, 3D sound |
| `scripts/powerups.gd` | `PowerUps` — crystals: shield, triple shot, extra life, bomb |
| `scripts/title_screen.gd` | `TitleScreen` — title board with high score and instructions |
| `scripts/sound.gd` | `Sound` — 3D audio: guns, explosions anchored in the world, rumble of the 4 nearest rocks, engine, alarms |
| `scripts/sfx_synth.gd` | `SfxSynth` — synthesizes every sound effect into `AudioStreamWAV` at startup (no audio files) |

## Controls

| Quest | Desktop | Action |
|---|---|---|
| right stick ↕ | ↑ ↓ | pitch (aircraft style, see `INVERT_PITCH`) |
| right stick ↔ | ← → | yaw |
| left stick ↔ | Q / E | roll |
| left trigger | W | thrust |
| left grip | S | brake |
| right trigger | Space | fire (two guns alternating, converging on the crosshair) |
| left menu button (≡) | P | pause (also automatic when the Meta menu opens or the headset is removed) |
| right trigger (title screen) | Space / Enter | start |
| — | Esc | quit |

Recenter the view by holding the Meta button on the right controller.

Dashboard gauges: **lives** (left; the lamp lights on the last life and
blinks after a hit), **speed** with the **score** counter (center),
**rocks left in the wave** in % with the **wave** number (right).

## Gameplay

- **Title screen**: high score (saved in `user://asteroids.cfg`), last
  score and a controls summary. Rocks drift in the background.
- **UFO** every 18–30 s: a large one (200 pts, inaccurate) or, from wave 3,
  a small one (1000 pts, accurate). It orbits the player and fires with
  lead; you can hear where it is. It always drops a power-up.
- **Power-ups** (8% chance from a rock, always from a UFO; fly through to
  collect): **S** shield for 10 s (ram rocks, immune to UFO fire),
  **3** triple shot for 12 s, **+** extra life (max 5), **B** bomb
  (destroys everything within 70 m).
- **Locator**: when 3 or fewer rocks remain, or none is visible through
  the fog, an arrow next to the crosshair points to the nearest one
  (red = behind you).

## Running on desktop (Linux)

```
godot --path .          # without a headset it starts in keyboard mode
```

## Building for Quest

```
tools/build.sh          # debug APK -> build/asteroids-vr.apk
tools/build.sh run      # + adb install and launch on the headset
tools/build.sh log      # adb logcat -s godot
```

The script uses the Android SDK from `$ANDROID_HOME` (default `~/opt/android-sdk`).

The "Quest" export preset (`export_presets.cfg`): Gradle build, arm64,
OpenXR, Meta plugin, Quest 2/3/Pro. The `android/`, `build/` and `.godot/`
directories are generated (and git-ignored).

### Toolchain

| What | Where from |
|---|---|
| Godot 4.6.3 | e.g. Debian `apt install godot`, or godotengine.org |
| Export templates 4.6.3 | the `.tpz` from the Godot release, unpacked to `~/.local/share/godot/export_templates/4.6.3.stable/` |
| JDK 17 | e.g. Temurin from adoptium.net |
| Android SDK: platform 36, build-tools 36.1.0, NDK 29.0.14206865, platform-tools | `sdkmanager` from the Android command-line tools |
| Debug keystore | `keytool` (Godot can also generate one) |
| Godot OpenXR Vendors 5.1.0 | bundled in `addons/godotopenxrvendors/` |

Point Godot to the JDK and SDK in Editor Settings → Export → Android.
The required SDK/NDK versions come from `config.gradle` inside
`android_source.zip` — check them again when you change the Godot version.
The export templates must match the editor version exactly; vendors
plugin 5.x requires Godot ≥ 4.6.

### Headset

1. **Developer mode**: Meta Horizon app on your phone → Devices →
   Headset settings → Developer mode (requires an "organization" on
   developers.meta.com).
2. **USB access on Linux**: udev rules, e.g. Debian's `android-udev-rules`
   package (covers Meta's vendor ID 2833), and membership in the `plugdev` group.
3. Connect the Quest with a cable, allow USB debugging in the headset;
   `adb devices` should list it.
4. Remote Deploy in the editor works too (Android icon, top right).
   The game shows up in Library → "Unknown Sources".

## How it works

- **3-torus**: logical positions live in `[0, L)^3`. The ship physically
  stays at the scene origin, and every object is drawn at its minimum
  image `wrap_delta(pos - ship_pos)`. Fog (`FOG_END` < L/2) hides the
  moment an image jumps to the other side. Stars and the sun are "at
  infinity", so they have no translational parallax.
- **Comfort**: a fixed cockpit frame in view, smoothed angular velocity
  (`ROT_SMOOTH`) and rotation limits. If you feel sick, lower `MAX_ROLL` first.
- **Splitting**: the two fragments get ±kick perpendicular to the hit
  direction, so momentum is conserved.
- **Bullet collisions**: segment–sphere tests, because at 220 m/s a bullet
  travels ~3 m per frame.

## Ideas

- Vignette during rotation (comfort option).
- A physical stick/throttle in the cockpit instead of thumbsticks.
- Ghost-rendering copies of the cube to actually *see* the torus (needs fog > L/2).
- Moving the collision loop to C++ (GDExtension) if there are hundreds of rocks.

## License

The game is licensed under GPLv3 — see [LICENSE](LICENSE) — with an
additional permission (GPLv3 section 7) to combine and distribute it with
the Godot OpenXR Vendors plugin and the Meta OpenXR SDK — see
[LICENSE-EXCEPTION](LICENSE-EXCEPTION).

Third-party code in `addons/godotopenxrvendors/` (Godot OpenXR Vendors
plugin 5.1.0) keeps its own licenses:

- the plugin itself — MIT ([LICENSE](addons/godotopenxrvendors/LICENSE)),
- vendor OpenXR loaders — Apache-2.0 (`*/LICENSE`, `meta/LICENSE-LOADER`),
- Meta-specific components (the Meta OpenXR preview headers compiled into
  the plugin) — Oculus SDK License Agreement
  ([meta/LICENSE-SDK](addons/godotopenxrvendors/meta/LICENSE-SDK)).

The additional permission exists because of those Meta components: the
Oculus SDK License forbids making the SDK subject to an open source license
(section 1.2.8), so the GPL must not extend to it. With the permission, the
game's own code stays GPL while the plugin keeps its original terms.
