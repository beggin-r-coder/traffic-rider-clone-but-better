# Throttle Rush

A first-person motorcycle traffic racer for mobile, built with **Godot 4.7** (Mobile renderer,
falls back to OpenGL/Compatibility on devices without Vulkan).

Ride a superbike down an endless highway, split lanes at 300 km/h, chain near misses, and lean
into real curves. Inspired by the traffic-racer genre, with a focus on:

- **Lean-based steering.** The bike rolls with spring-damped roll dynamics and a roll-rate limit;
  the path curvature comes from the lean angle (`κ = g·tanφ / v²`), so lane changes have the
  natural lean-in / lean-out feel and you lean through actual bends in the road.
- **Steering assist** (default): your input chooses where you want to go, the bike works out the lean,
  and it leans through bends by itself. **Pro mode** (assist off): your input is the lean angle.
- **Real road**: smooth curves (clothoid-style ramps), S-bends and hills, rolling terrain, trees,
  guard rails, street lights, km signs, distant mountains.
- **Engine model**: power curve, 6-speed auto gearbox with shift cut, traction limit when leaned,
  braking that gets weaker the more you lean, drag, and road slope.
- **First-person cockpit** from the supplied 2022 Yamaha R1 model with gloved rider arms, head
  that stays more upright than the bike, speed FOV, vibration, and a chase cam with a full rider.
- **Procedural audio**: crossplane inline-4 engine (uneven 270-180-90-180° firing order) baked into
  RPM loops and cross-faded, plus wind, tyre roar, rail scrape, horns, near-miss whoosh, crash.
- **Modes**: One-Way, Two-Way (oncoming lane = x2 score), Time Trial (checkpoints add time).
  **Time of day**: Day, Sunset, Night (headlight + street-light pools) and Cloudy. Each run picks one of
  20 hand-picked cloudy sky panoramas for that time of day; the sun light, fog, ambient light and
  distant mountains are tinted from the picture so everything matches.

## Screenshots

| Cockpit | Sunset (two-way) |
|---|---|
| ![](docs/cockpit.png) | ![](docs/sunset.png) |
| **Night** | **Cloudy** |
| ![](docs/night.png) | ![](docs/cloudy.png) |
| **Day, chase cam** | **Garage** |
| ![](docs/day_chase.png) | ![](docs/garage.png) |

## Rain mode

Toggle **Weather: Rain** in the menu (any time of day; `--rain` on the command line).

- **Wet road with real-time reflections:** a second camera renders the scene mirrored about the road
  surface under the bike (half resolution on High, a third and every other frame on Medium). The road
  shader blends it in by Fresnel: sharp in puddles, blurred and streaked vertically on soaked asphalt,
  distorted by animated raindrop ripples. Puddles collect in the worn tyre ruts; asphalt darkens, paint
  less so. Low graphics uses sky reflections only.
- **Rain:** streak particles stretched along the rain's velocity *relative to you*, so they rake
  towards you at speed; splashes on the road ahead; spray off the rear tyre.
- **Simulated water drops** (`scripts/drop_sim.gd`): rain on the visor and the bodywork is a particle
  simulation — beads land, touching drops merge (volume conserved), heavy drops run with stick-slip
  motion, shed trails of tiny droplets and sweep up beads; wind takes over with speed. Drops render into
  a water map (normal + thickness) that the visor/bike shaders use for lens refraction and highlights.
- **Visor drops (first person):** drops bead on the helmet visor, refract the view, and get blown
  outwards/upwards by the airflow as you speed up (slide down when slow).
- **Wet bike and rider:** every surface gets a glossier clear coat, plus an overlay pass of water
  droplets placed in the bike's own space (they stick to it); a share of them run down and get blown
  backwards faster with speed.
- **Lights in the rain:** street lights switch on (warm sodium with some cool LED ones), every lamp and
  every car head/tail light gets a glowing halo, and brake lights flare. These are in the reflection too,
  so on the wet road each light becomes a long vertical streak (multi-tap smear towards the viewer,
  longer at grazing angles, with a fake-HDR boost so bright lights glow and bloom).
- **Atmosphere:** overcast skies, soft overhead light without hard shadows, grey mist, headlight and car
  lights on, rain and tyre-hiss audio, and ~22% less grip (braking, acceleration, cornering).

![](docs/rain_cockpit.png)
![](docs/rain_chase.png)
![](docs/rain_night.png)

## Rider

The rider is a Ready Player Me style avatar (`assets/rider/rider.glb`) posed procedurally every frame
by `scripts/rider_model.gd`, against contact points measured on the R1 mesh:

- **Posture:** pelvis on the seat, spine curved into a sport tuck (deeper at speed), neck/head counter-
  rotated so the eyes stay level, looking into turns; hangs off the inside of the bike when leaning.
- **Arms:** two-bone IK from the shoulders to the clip-ons, elbows low and out.
- **Hands:** each glove is oriented along the grip axis with the knuckles on the top-front of the bar;
  every finger joint is solved so the next joint lands on a circle hugging the grip (grip radius +
  finger thickness), so all four fingers wrap the bar and the thumb closes underneath. No floating.
- **Throttle:** the right hand rolls back around the grip (up to 30°) with the throttle.
- **Brake:** index and middle fingers lift off the grip onto the brake lever and pull it; the lever is
  cut out of the bike mesh at load time and pivots back towards the grip with brake pressure, and the
  fingers follow it. Gear shifts blip the left fingers on the (also pivoting) clutch lever.
- **Legs:** IK to the footpegs, balls of the feet on the pegs, knees against the tank (inside knee out
  when hanging off).
- **First person:** the helmet is hidden and anything within ~0.6 m of the camera is dithered away, so
  you see the rider's forearms and gloves on the bars.

![](docs/rider_hands.png)
![](docs/rider_poses.png)

Review tool: `godot --path . res://scenes/pose_test.tscn -- --posetest=DIR` renders side/front/hand
close-ups/first-person views for cruise, full throttle, braking and leaning (`--posenum` prints joint
positions in the grip's frame, `--markers` shows the measured contact points).

## Shiny bike

The R1 has a clear-coated metallic paint, polished aluminium/chrome parts, gold forks and real mirror
glass. On Medium/High graphics a reflection probe rides with the bike and re-captures the world every
frame, so the paint and chrome reflect the actual road, trees, traffic and sky (the bike is on its own
render layer, so it doesn't reflect itself). Low graphics falls back to sky-only reflections.

![](docs/bike_reflections.png)

## Forest road

A dense forest built from Poly Haven plants, layered so it has real volume but stays cheap on phones:

- **Trees (depth impostors).** Fir trees, young firs/pines, a broadleaf tree, island tree and searsia are
  millions of triangles each, so they are baked offline from **16 directions** into one 4096x3584
  atlas holding colour, normals and **per-pixel depth**. In game each tree is a 2-triangle card that
  turns to the camera and, per pixel: blends the two nearest views (no popping), parallax-shifts each
  view by its depth (the canopy has real depth as you ride past), lights and shadows the pixel at its
  true depth, and on High writes that depth to the z-buffer so trees intersect each other and the
  ground correctly. Species/per-tree colour variation, translucent backlighting and wind sway on top.
  All trees in a road chunk are **one draw call**.
- **Undergrowth (real meshes).** Ferns and shrubs right next to the rail are the actual Poly Haven
  meshes (2-9k triangles, auto-LOD), culled beyond 100 m.
- **Verge grass.** A strip of real Poly Haven grass tufts is baked into a texture and drawn on
  crossed cards that sway, in two thick bands along the verge.
- **Far band.** Behind the last row, staggered rows of baked fir frames over a dark interior, so gaps
  never show open land.

Graphics quality scales density (Low 55 %, Medium 85 %, High 100 % + depth writing).

Re-bake (needs the source glTFs from Poly Haven in a folder and a real renderer, e.g. under xvfb):
`godot --path . -- --bake-vegetation=DIR` and `godot --path . -- --bake-grass=DIR`

## Garage

Cash earned from runs buys **Engine**, **Brakes** and **Handling** upgrades (5 levels each), and the
bike can be repainted (the paint shader only recolours the blue livery, so decals stay intact).
Test flags: `--cash=N`, `--paint=N`, `--menu --garage --shot=PATH`.

## Controls

| | Phone | Keyboard (desktop testing) |
|---|---|---|
| Steer / lean | Tilt the phone like a steering wheel (or on-screen arrows in *Settings → Steering: Touch*) | A / D or ← → |
| Throttle | GAS pedal (bottom right) | W or ↑ |
| Brake | BRAKE pedal (bottom left) | S or ↓ |
| Camera | Pause menu | C |
| Pause | II button | Esc / P |

Scoring starts above 100 km/h and scales with speed. Near misses (passing a car with < 1 m gap at
80+ km/h) give bonus points and build a combo.

## Project layout

```
scenes/          main_menu.tscn, game.tscn (thin; everything is built in code)
scripts/
  game.gd        autoload: settings, save file, dev flags
  game_world.gd  gameplay scene: world setup, game loop, scoring, autopilot/test harness
  rider.gd       bike physics (road/Frenet coordinates), cameras, crash
  bike_visual.gd loads the R1 glTF, splits the wheels so they spin, lean/brake light
  rider_arms.gd  first-person arms + gloves;  rider_body.gd  full rider for chase cam/crash
  road.gd        curvature/elevation program, road<->world mapping, chunk streaming, scenery
  props.gd       procedural trees, rocks, street lights, signs
  traffic.gd     traffic spawning, car-following, lane changes, near-miss/crash detection
  car_factory.gd procedural car/SUV/van/truck meshes (lofted cross-sections)
  hud.gd         HUD, pedals, tilt input, pause and game-over panels
  bike_audio.gd  procedural audio synthesis + playback
  main_menu.gd   showroom menu, settings
shaders/         road (scanned asphalt + markings), terrain, mountain backdrop, showroom floor, speed lines
assets/bike/     supplied model (see license.txt)
assets/audio/    pre-baked engine loops (regenerate with --bake-audio)
```

## Dev / test flags

Pass after `--` on the command line (read via `OS.get_cmdline_user_args()`):

| Flag | Effect |
|---|---|
| `--fresh` | ignore the save file |
| `--nosave` | don't write the save file |
| `--game` | skip the menu, start riding |
| `--autotest` | autopilot rides (dodges traffic, brakes, takes bends); prints a status line every 5 s, restarts after crashes |
| `--until=N` | stop the autotest after N simulated seconds (across restarts) |
| `--shot=PATH` (`--at=T`) | save a screenshot at game time T (default 6 s) and quit; uses the autopilot unless `--noauto` |
| `--shots=DIR` (`--times=a,b,c`) | save screenshots at several times, then quit |
| `--menu --shot=PATH` (`--settings`) | screenshot the main menu (or settings) |
| `--mode=0/1/2` | One-Way / Two-Way / Time Trial |
| `--time=day/sunset/night/cloudy` | time of day |
| `--rain` | rain mode |
| `--sky=N` | force a specific sky panorama (see `scripts/sky_library.gd`) |
| `--view=fp/chase` | camera |
| `--seed=N` | road + traffic seed |
| `--touch` | on-screen steering buttons instead of tilt |
| `--quality=0/1/2` | graphics quality |
| `--photo` | close 3/4 camera riding alongside the bike (for screenshots) |
| `--posetest=DIR` | (with `res://scenes/pose_test.tscn`) render rider pose review images |
| `--audiotest` | render every procedural sound offline, check samples are finite, print peak/RMS |
| `--bake-vegetation=DIR` | bake the tree impostor atlas (16 views, colour/normal/depth) from Poly Haven glTFs in DIR |
| `--bake-grass=DIR` | bake the verge grass strip from Poly Haven grass_medium_02 in DIR |
| `--bake-audio` | re-bake the engine loops into `assets/audio/` |

Examples:

```bash
# Fast logic check (no rendering):
godot --headless --path . --fixed-fps 60 -- --fresh --nosave --autotest --until=120

# Screenshot on a virtual screen (software Vulkan / OpenGL):
xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-method mobile \
  --resolution 1280x720 --fixed-fps 20 -- --fresh --nosave --seed=5 --shot=/tmp/out.png --at=8
```

## Building for Android

1. Install the Godot 4.7 Android export templates and set up the Android SDK/JDK in the editor.
2. `export_presets.cfg` contains an arm64 Android preset (landscape, immersive, vibrate permission).
   Add your keystore in *Project → Export*.
3. Export, install, and **calibrate**: tilt steering takes the phone's position at the start of a
   run (and when resuming from pause) as neutral.

## Credits

- Motorcycle model: "2022 Yamaha R1" by Hari on Sketchfab, Sketchfab Standard license
  (`assets/bike/license.txt`).
- Road surface: "Asphalt 02" by Rob Tuytel, [Poly Haven](https://polyhaven.com/a/asphalt_02), CC0
  (4K colour, normal and AO/roughness maps in `assets/textures/asphalt_02/`).
- Vegetation: fir_tree_01, fir_sapling, pine_sapling_small, tree_small_02, island_tree_02,
  searsia_lucida (baked to impostors), shrub_02, fern_02 (real meshes), grass_medium_02 (baked grass strip)
  from [Poly Haven](https://polyhaven.com/models), CC0.
- Rider: the supplied "bike rider 3D" avatar (Ready Player Me based), posed procedurally.
- Skies: "Cloudy Skyboxes" by Screaming Brain Studios, CC0 (`assets/skies/`).
- Everything else (lane markings, scenery, cars, audio, UI) is procedural.
