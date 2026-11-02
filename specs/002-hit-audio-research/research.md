# Hit-feedback audio design brief — OpenSaberQ3 (Godot 4.6, Quest 3)

Research output for `specs/002-hit-audio-research/spec.md`. Copy-pasteable design, every
number tagged.

**Tag legend**

| Tag | Meaning |
|---|---|
| **[V]** | VERIFIED — primary source (engine docs/source, vendor doc, developer statement) |
| **[V2]** | VERIFIED from a third-party mod/patch that exposes the shipped behaviour |
| **[P]** | PLAUSIBLE — inference from secondary sources |
| **[U]** | UNVERIFIED — no source found; do not build on it |
| **[D]** | DERIVED — arithmetic from inputs stated inline |
| **[TS]** | TUNING START — deliberate estimate, measure on device |

---

## 0. Current state, measured

| Fact | Evidence |
|---|---|
| One `AudioStreamPlayer3D` per saber, fixed stream | `game/sabers/default/default_saber.tscn:323-327` (`stream = ExtResource("4")` → `res://game/data/beepcube_cut.ogg`) |
| `max_polyphony` = 1 (engine default) | `class_audiostreamplayer3d.html` — property default `1` **[V]** |
| So each hit restarts the single voice: two hits < sample length apart cut each other off | engine behaviour of `play()` when polyphony is exhausted **[V]** |
| `attenuation_model = 3` | scene:326 → `ATTENUATION_DISABLED` = no distance attenuation, **still positional** **[V]** |
| No low-pass currently audible | with attenuation disabled there is no distance factor to filter; if any dulling appears, set `attenuation_filter_cutoff_hz = 20500` (documented switch) **[V]** |
| Emitter sits mid-blade, not at the tip | scene:324 transform y = 0.759516; tip marker y = 1.2554 (`:320-321`) |
| Only variation is `randf_range(0.9,1.1)` on `pitch_scale`, applied **after** `super.hit()` already called `play()` | `game/sabers/particles/particles_saber.gd:19-21` |
| `hit(time_offset)` receives nothing but a time offset | `default_saber.gd:60` |
| Score data exists but is computed **after** the audio call | `LightSaber.gd:136` (`saber_visual.hit`) vs `:143` (`note.cut`); values at `BeepCube.gd:132-139`, `LightSaber.gd:140` |
| Physics runs at 120 Hz | `project.godot:144` |

**Non-obvious consequence:** `AudioStreamPlayer3D.play()` "queues the audio to play on the
**next physics frame**" **[V]**. At 120 Hz that is up to **8.3 ms [D]** of added latency on
top of the Android audio buffer. `AudioStreamPlaybackPolyphonic.play_stream()` is documented
to start **"immediately"** **[V]**, so the polyphonic path is also the lower-latency path.

---

## 1. How shipping VR rhythm games do hit audio

### Beat Saber — [V2]

Source: `HitsoundTweaks`, a Beat Saber mod whose documented options expose base-game
behaviour (`github.com/GalaxyMaster2/HitsoundTweaks`, GPL-3.0, README).

| Finding | Quote / basis |
|---|---|
| Hit sound **pitch is randomised at runtime** | `RandomPitchMin` default **0.9**, `RandomPitchMax` default **1.2** — "the minimum value for randomized hitsound pitch" |
| Hit sound is **spatialised, located at the saber tip** | `EnableSpatialization` default **`true`**; `StaticSoundPos` = "hitsounds are located at your feet, **instead of your saber tips**" |
| Hit sound is **suppressed when the saber is not moving** | option `IgnoreSaberSpeed` — "hitsounds **always play even when the sabers are not moving**" |
| Chain elements are a **separate layer with its own volume multiplier** | `EnableChainElementHitsounds`, `ChainElementVolumeMultiplier` default **0.8** |
| There is **no cut-score → audio mapping** exposed anywhere | the mod's option list is exhaustive about what the base game varies: speed gate, position, spatialisation, pitch range, chain layer. No angle/accuracy/score term exists to configure. **[P]** by absence |
| The base game has known **hit-sound consistency bugs** (sounds dropped/replaced) that the mod patches | README: "fixes several base game bugs to make them more reliable and consistent" |

Beat Saber's spread, converted: 0.9 = **−1.82 st**, 1.2 = **+3.16 st** **[D]**.
So Beat Saber varies pitch *more* than ±2 st, and does **not** vary it by score.

### Ragnarock (WanadevStudio) — [V]

Source: Meta Quest blog interview, 21 Oct 2021, `meta.com/blog/drumming-in-valhalla-...`.
Quotes from Côme de Percin (Creative Director):

- "we try to **play the hit drum sound on tempo with the music**. Even if you are a bit
  desynchronized, the sound will be played **synchronously by default** (although pro players
  can disable this behavior in order to perform better)."
- "the **hammer velocity is taken into account to increase/decrease the volume** of the drum
  sound. That also enhances the credibility of the whole thing."

Two directly transferable mechanisms: **velocity → gain**, and **beat-quantised hit sound**
with a player toggle. Note this project already has half of it (`default_saber.gd:61-68`
queues late/future hits; `play(-time_offset)` skips into the sample for past hits).

### Pistol Whip (Cloudhead) — [P]

Developer copy: "**Take aim and fire on the beat**" (`cloudheadgames.com/pistol-whip`). The
studio's own framing is music-first ("the music … was by far my most important job" — audio
lead, UploadVR interview). No source describes the per-shot audio graph. **Do not cite the
mapping as fact**; the useful takeaway is only that the *beat grid*, not the hit vector, is
the design centre.

### Audica (Harmonix) — [P]

Harmonix designer Ryan Challinor (Meta blog, 7 Mar 2019): "We use the more **discrete action
of firing a gun** to provide a stronger connection to a song's unique rhythm." That is a
*timing* argument, not an audio-graph statement. Audica's shots are widely reported to trigger
musical elements of the track, but no primary source confirms the routing — **[U]** if you
need it precise.

### The anti-fatigue technique that is actually standard

- **Round-robin / no-repeat random containers** are the industry baseline for repeated SFX:
  Wwise Random Container — `Shuffle` "avoids repetition of sounds until all objects have been
  played", and `Limit Repetition` exists specifically "to avoid objects being repeated one
  after the other" **[V]** (`audiokinetic.com` Wwise docs, *Creating Random Containers*).
- **Pitch randomisation** on top of round-robin: Wwise exposes a per-container pitch
  randomiser with min/max offsets, and Beat Saber ships exactly this **[V]/[V2]**.
- **Layering** (transient + body + tail) rather than one sample **[V]** — the layering principle
  is standard game-audio practice; GDC's *Sound Design for Video Games* primer and the
  *Audio Choreography for Battle Design* talk both build repeated impacts from several
  synchronised layers **[P]** for the exact layer counts.

**What this implies for us:** randomise *sample* and *pitch*, drive *gain and layer* from the
physical gesture. Nobody credible drives pitch from score.

---

## 2. Spatialisation on Quest 3 in Godot 4.6

All rows sourced to `docs.godotengine.org/en/stable/classes/class_audiostreamplayer3d.html`
(4.7 docs; identical surface in 4.6) **[V]**.

| Property | Reality | Use for hit audio |
|---|---|---|
| `attenuation_model` | `0` inverse distance, `1` inverse square, `2` logarithmic, `3` **disabled** ("No attenuation … The sound will still be heard positionally") | **keep 3.** Source is 0.5–1.2 m from the ears; any distance curve just makes it quieter for no reason |
| `unit_size` | attenuation "factor", default `10.0`; meaning depends on model | irrelevant while model = 3 |
| `max_distance` | linear hard cutoff, `0.0` = off; docs note setting it saves mixing CPU | leave `0` (always audible, it's in your hand) |
| `panning_strength` | default `1.0`, multiplied by `audio/general/3d_panning_strength`; `0.0` = mono. 2-speaker case uses the **WebAudio StereoPannerNode** cosine-half-azimuth law; >2 speakers use SPCAP | **0.7–0.9 [TS]** — full hard-pan on a hand-held source sounds like a fly in one ear |
| HRTF | **does not exist in Godot.** Only stereo amplitude panning. Open proposals: godot-proposals **#949** ("HRTF-based 3D audio"), **#4377** ("Resource type for audio spatialization models … HRTF's to better spatialize audio around the headset") | do not design around binaural cues; see §3 for the consequence |
| Doppler | `doppler_tracking`: `0` disabled, `1` idle step, `2` physics step | **keep 0.** Doppler on a 150 ms transient from a source at your ear is inaudible at best, a wobble at worst |
| Reverb | `area_mask` routes to `Area3D` reverb (`reverb_bus_enabled`, `reverb_bus_name`, `amount`, `uniformity`) | optional; a small `amount` on a room bus glues hits together, but this project has no room model — skip in v1 |
| Low-pass | `attenuation_filter_cutoff_hz` default `5000.0`; **set `20500` to disable** | set `20500` explicitly so a future attenuation change cannot silently muffle hits |
| Hiding the node | "Hiding an AudioStreamPlayer3D node does **not** disable its audio output" | never rely on visibility |
| `max_polyphony` | default `1`; "Playing additional sounds after this value is reached will **cut off the oldest sounds**" | this is the bug; see §5 |

### Meta first-party SDK — [V]

The **Meta XR Audio SDK** provides "HRTF based object and ambisonic spatialization, and room
acoustics simulation"; it succeeds the Oculus Spatializer; "Meta provides free … spatializer
plugins for engines and middleware including **Unity, Unreal, FMOD, and Wwise**"; it supports
"PCVR as well as Quest, Quest 2, Quest Pro, Quest 3, and Quest 3S"
(`developers.meta.com/vr/documentation/unity/meta-xr-audio-sdk-unity`).

**Verdict: not usable from Godot.** There is no Godot plugin, and the officially sponsored
Godot/Meta integration — the **Godot Meta Toolkit** (MIT, W4 Games, Meta-sponsored, announced
in the Feb 2025 Godot XR update) — covers the Platform SDK, not audio. **No maintained Godot
binding found as of 2026-11.** Using it would mean writing a GDExtension around the C/C++
SDK yourself; out of scope.

Meta's own performance note is worth keeping: the spatializer is "highly optimized … there is
some overhead for spatializing sounds compared to traditional 3D panning … it should not
impact frame rate because real-time audio systems process audio in a **separate thread**"
**[V]**. But they also name the honest cost of *engine* panning: **front/back ambiguity**,
**elevation ambiguity**, and **hard panning** **[V]**.

**Design consequence.** With no HRTF, a hit sound panned only by note position is an ambiguous,
easily-misleading cue. Beat Saber's answer — put the sound **at the saber**, where the player
already knows their hand is — is the correct one for a clone, and it is corroborated **[V2]**.
Keep the emitter on the saber; do not chase per-note panning.

---

## 3. Driving variation from gameplay data

### What exists, and when it exists at contact

| Value | Where | Available at contact? | Note |
|---|---|---|---|
| `controller_speed` (Vector3, m/s) | `LightSaber.gd:140`, computed `:139-140` | **yes** — computed *before* `note.cut()` on `:143` | single-frame finite difference at 120 Hz; noisy. Use `length()`, clamp |
| `cut_angle_accuracy` 0–1 | `BeepCube.gd:132` — `clamp((dot-0.7)/0.3,0,1)` | **yes**, but computed *inside* `cut()` | 0 at ≈45.6° off, 1 at 0° **[D]** |
| `cut_distance_accuracy` 0–1 | `BeepCube.gd:135` — `clamp((0.1-|d|)/0.1,0,1)` | **yes** | 0 at ≥10 cm off centre (sourced threshold: the code itself) |
| `travel_distance_factor` 0–1 | `BeepCube.gd:136-137` — swing AABB longest axis | **yes** | trailing measure of the swing *so far*, reset after each cut (`:147`); not instantaneous speed |
| `beat_accuracy` 0–1 | `BeepCube.gd:139` — `(1-|z|)/0.5` | **yes** | |
| note world position | `Cuttable.transform.origin` | **yes** | |
| which saber / wrong saber | `BeepCube.gd:131` compares `saber_type == which_saber` | **yes**, if you read `note.which_saber` before calling `cut()` | |
| cut-piece split angle, piece impulses | `BeepCube.gd:158-178` | **no** — only after the split | **never** use for audio |

**Conclusion:** everything you want is known at contact except the cosmetic split geometry.
No value must wait for the swing to "complete" — the only trap is *ordering*.

### How the data reaches `hit()`

`hit()` is called at `LightSaber.gd:136`; the values are computed at `:140-143`. Minimal
change that keeps one source of truth:

```gdscript
# game/LightSaber.gd, replacing lines 136-143
var o := controller.global_transform.origin
var controller_speed: Vector3 = (saber_end - saber_end_past) / last_dt
const BEAT_DISTANCE := 4.0
var cutplane := Plane(o, saber_end, saber_end_past + Vector3(0, 0,
        BEAT_DISTANCE * Map.current_info.beats_per_minute * last_dt / 30))
var info := note.cut(type, controller_speed, cutplane, controller)  # returns HitInfo
saber_visual.hit(time_offset, info)
```

`Cuttable.cut()` keeps its body and gains a `HitInfo` return (a `RefCounted` with
`speed_len`, `angle_acc`, `dist_acc`, `travel`, `beat_acc`, `is_correct_saber`, `note_pos`).
`note.cut()` already hides the cube before returning; audio does not depend on the cube, so
firing the sound microseconds after the split is harmless. `saber_visual.hit()` then owns
audio only — scoring stays in `BeepCube.cut()` where it belongs.

Do **not** duplicate the accuracy maths in `LightSaber.gd`; two copies will drift.

`_pending_hits` (`default_saber.gd:18`) must become an array of `{remaining, info}` so a
future-beat hit keeps the gesture data it was struck with.

### Parameter table

Anchoring rule (per G0): **physical speed and centrality drive gain, layer and filtering.
Pitch carries only small jitter.** Rationale: loudness→force is a perceptual mapping that
holds for everyone; pitch→score is a mapping nobody ships and that depends on musical key data
this project does not have (see "key-lock" below).

| # | Input | Audio target | Mapping | Tag |
|---|---|---|---|---|
| 1 | `speed_len` = `controller_speed.length()` | **gain** | `-6 dB at 1 m/s → 0 dB at 8 m/s`, linear, clamped outside | **[TS]** |
| 2 | `speed_len` | **layer** | `< 3 m/s` → soft layer; `3–7` → hard layer; `> 7` → hard **+ accent layer** | thresholds **[TS]** |
| 3 | `cut_angle_accuracy` | **layer bias** | `< 0.5` → soft layer regardless of speed (a glancing cut *should* sound dull); `≥ 0.5` → normal rules | threshold **[TS]**; 0.5 sits mid-scale of the game's own 0.7–1.0 dot window **[V]** (code) |
| 4 | `cut_distance_accuracy` | **gain** | `0 dB` at 1.0 → `-1.5 dB` at 0.0, linear | **[TS]** |
| 5 | `travel_distance_factor` | **gain trim** | `0 dB` at 1.0 → `-0.5 dB` at 0.0 | **[TS]** |
| 6 | `beat_accuracy` | **accent mute** | `< 0.2` (hit >40 cm/±~0.1 beat off) → drop the accent layer | **[TS]**; the 0.5 m window is the game's own **[V]** |
| 7 | `is_correct_saber` | **sample set** | wrong-saber cut uses a separate dull "bad cut" set | design choice **[TS]** |
| 8 | `saber_type` 0/1 | **pan bias** | `panning_strength` 0.9 L / 0.75 R, or symmetric 0.85 | **[TS]** |
| 9 | note position | **nothing** | deliberately not mapped — see §2 | **[V2]** |
| 10 | `speed_len` + `cut_angle_accuracy` | **filter** | **not a runtime filter.** `AudioStreamPolyphonic` has no per-voice DSP, and `attenuation_filter_cutoff_hz` is a whole-node property, so a shared 3D node cannot low-pass one voice and not another. Instead the **soft layer is a pre-filtered, darker sample set** (HPF at 120 Hz + LPF at ~4 kHz before import) | **[TS]**; constraint is **[V]** (no per-voice filter exists) |
| 11 | (all hits) | **pitch** | uniform in **±1.0 st** (`0.943–1.059`), hard ceiling ±2 st | spread **[TS]**; ceiling **FR-012**; Beat Saber ships ±1.82/+3.16 st **[V2]** so ±1 is conservative |
| 12 | (all hits) | **gain jitter** | uniform **±0.5 dB** | **[TS]** |
| 13 | (all hits) | **sample choice** | round-robin, **no immediate repeat** | **[V]** (Wwise `Shuffle` + `Limit Repetition`) |

**Gain budget — split it, do not sum-then-clamp.** The three gesture terms span at most
`-6 - 1.5 - 0.5 = -8 dB`. Add the ±0.5 dB jitter and clamp the **total** to `[-8.5, +0.5]`:

```gdscript
var g := speed_gain + centrality_gain + travel_trim + randf_range(-0.5, 0.5)
g = clampf(g, -8.5, 0.5)   # total span exactly 9.0 dB -> FR-012
```

Summing wider terms and clamping afterwards is wrong: every slow, off-centre hit would land on
the same floor and the variation would disappear. Set the randomizer's
`random_volume_offset_db = 0` so the jitter is counted exactly once, in the line above. **[TS]**

Gain is not the main signal — the **soft / hard / accent layer switch** is. 6 dB of speed range
is clearly audible (roughly a 2:1 loudness ratio) without making a fast hit sound like a
different game. **[TS]**

**Node-level filter is disabled, not tuned.** `attenuation_filter_cutoff_hz = 20500` (the
documented way to switch it off **[V]**) so that the only filtering in the chain is the one
baked into the soft layer. With `attenuation_model = 3` there is no distance factor to filter
anyway; this makes that explicit rather than incidental.

**Key-lock (optional, default OFF).** Pitch-quantising to the map's musical key needs key data.
This project's map path (`game/Map.gd`, `game/BeatmapInfo`) parses note cut direction and
angle offset; **no musical key field is used** **[V]** (code). So key-lock is a new data
dependency, not a tuning exercise. Default off; revisit only if a key is added to the map
metadata.

### Anti-fatigue limits (FR-012, normative)

| Limit | Value | Basis |
|---|---|---|
| Pitch spread | **≤ ±2 st**, ship ±1 st | **[V2]** Beat Saber ±1.82/+3.16 st as upper bound; **[TS]** ours |
| Gain range | **≤ 9 dB** end to end, jitter included | **[TS]**; enforced by the clamp in the table above |
| Round-robin variants | **≥ 3 per layer** (3 soft, 3 hard, 1 accent) | **[V]** Wwise `Shuffle` / `Limit Repetition` |
| No exact repeat | same sample **and** pitch never twice in a row | **[V]** same source; `AudioStreamRandomizer` `PLAYBACK_RANDOM_NO_REPEATS` gives it free **[V]** |
| Volume jitter | ±0.5 dB, counted **inside** the 9 dB budget | **[TS]** |

---

## 4. The GPU question — false economy

### (a) What Tempest actually is — [V]

Mark Cerny, *The Road to PS5* (GDC 2020, ~44:31): "we're calling the hardware unit that we
built the Tempest Engine … it's **based on AMD's GPU technology**, we **modified a compute
unit** in such a way as to make it very close to the **SPUs in PlayStation 3** … the Tempest
engine has **no caches**, all data access is via **DMA** … more power than a CPU thanks to the
parallelism that a GPU can achieve and more efficient than our GPU thanks to the SPU-like
architecture … roughly the same SIMD power and bandwidth as all **eight Jaguar cores in the
PS4** combined … enough for something like **5,000 sound sources**."

So: a **GPU compute unit repurposed into a dedicated, cacheless, DMA-fed audio DSP**. It is
fixed-function audio hardware that happens to be built from a GPU CU. It is not "the GPU runs
the audio", and it is not something an engine can adopt by writing a compute shader.

### (b) GPU audio that actually ships — [V]

AMD **TrueAudio Next**: "a software development kit for **GPU accelerated** and multi-core
high-performance audio signal processing … **Fast OpenCL parallel batch convolution engine**"
(GPUOpen). Its shipping consumer of note is Steam Audio, where the GPU path is documented as
exactly one thing: "**TrueAudio Next. Multi-channel convolution reverb**, using AMD TrueAudio
Next for GPU acceleration … allowing significantly more sources to be processed"
(Valve, Steam Audio Unity docs).

GPU audio in shipping products = **convolution reverb**, on desktop AMD GPUs, behind an SDK.
**No evidence of GPU-synthesised one-shot sample playback in any shipping mobile or VR title
was found — [U], and nothing in the mobile audio stack (AAudio/Oboe) offers such a path [V].**

### (c) Could Godot do it, and what would readback cost — [V] + [D]

- Godot mixes on its **own audio thread**: the mixing internals are `thread_*`-prefixed and
  the thread is registered as `audio_thread` (`servers/audio/audio_server.cpp`); `_mix()` is
  documented as running there and as only usable from **GDExtension**, not GDScript **[V]**.
- An `AudioStreamPlayback` that synthesised on the GPU would have to have its samples **already
  in system memory when `_mix()` is called**. That means a GPU→CPU readback **inside the audio
  callback**.
- Budget: an Android low-latency stream runs ~**480-frame** blocks ≈ **10 ms** at 48 kHz
  **[V]** (Android low-latency guidance; ring buffer of 2 periods). A Quest frame at 90 Hz is
  **11.1 ms** **[D]**. A single readback sync costs at least one frame plus a pipeline flush,
  so **one readback ≥ one whole audio block** **[D]**. You would have to synthesise ≥3 blocks
  (~30 ms) ahead and still stall the renderer to fetch them.
- Work avoided: 8 voices × 48 kHz = **384 k sample-mixes/s**; at a generous 50 ops/sample that
  is **~19 MOPS** **[D]**. That is noise on any mobile CPU, and it is already on a thread that
  is not the frame budget.

**Verdict: false economy.** The PS5 comparison does not transfer (dedicated silicon, not a
compute shader), GPU audio on desktop exists only as convolution reverb, and on Quest the
readback alone would cost more than the mixing it replaces — while inverting the one property
that makes game audio cheap, namely that it runs on a thread that never waits for graphics
(Meta states this explicitly **[V]**). Spend the effort on sample selection and per-voice
parameter control instead.

---

## 5. Cheapest correct Godot pattern at ~8 hits/s (FR-006, FR-010)

### Mechanism choice

| Option | Polyphony | Per-hit pitch/gain | Verdict |
|---|---|---|---|
| current: one player, `play()` | 1 → **cuts off** | one shared property | rejected |
| `max_polyphony = N` on the player | yes, steals oldest | **no** — `pitch_scale`/`volume_db` are node-wide, shared by every voice | rejected (kills the whole mapping) |
| **`AudioStreamPolyphonic` on the existing player, `polyphony = 8`** | yes | **yes** — `play_stream(stream, from_offset, volume_db, pitch_scale)` per voice | **recommended** |
| pool of 8 `AudioStreamPlayer3D` nodes | yes | yes | fallback if per-note *position* is ever needed |

`AudioStreamPolyphonic` — "AudioStream that lets the user play custom streams at any time from
code, **simultaneously using a single player**", `polyphony` default 32; per-voice
`play_stream(stream, from_offset, volume_db, pitch_scale, playback_type, bus)` returning an id,
`stop_stream(id)`, `is_stream_playing(id)`, `set_stream_pitch_scale(id, …)`,
`set_stream_volume(id, …)`; returns `INVALID_ID` when full **[V]**.

Keep it on **one `AudioStreamPlayer3D` per saber**, so panning is anchored to the saber **[V2]**
and no node is created per hit.

### Lifecycle rules (get these wrong and every voice dies)

1. In `_ready()`: set `stream` to the `AudioStreamPolyphonic`, call `play()` **exactly once**,
   then cache `_voices := get_stream_playback() as AudioStreamPlaybackPolyphonic`. Every later
   hit is `_voices.play_stream(...)`; the player is never played again.
2. **Any subsequent `play()` or `stop()` on that player creates a new playback**, which
   silences every voice and invalidates every stored id. So deleting the old `hitsound.play()`
   paths is mandatory, not cosmetic — in `default_saber.gd:33,62,65` **and** `particles_saber.gd`.
3. Spatialisation carries through: voices are mixed first, then panned and attenuated at the
   node's **current** transform. All voices therefore follow the saber. That is exactly the
   behaviour §2 argues for, and it is why per-note panning is not available on this path.

### Voice-steal rule

`polyphony = 8`. At 8 hits/s with a ≤0.15 s sample the steady-state concurrency is
`8 × 0.15 ≈ 1.2` voices; 8 is ~6× headroom **[D]**. Rule:

1. `id = play_stream(sample, from_offset, gain_db, pitch_semitones_to_ratio(p), 0, &"SFX")`.
2. If `id == INVALID_ID`: walk the ring oldest→newest, skip any id where
   `is_stream_playing(id) == false`, stop the first still-playing id, then retry once.
3. Track ids in a fixed 8-slot ring; drop dead ids on the way past (step 2 does this for free).
4. If every slot is somehow still playing, drop the hit rather than stopping the newest voice.

**Bus caveat [P]:** `play_stream()`'s `bus` argument defaults to `&"Master"`. It is not
documented whether a 3D player honours it or overrides it with the node's own `bus`. Pass
`&"SFX"` explicitly **and** verify on device by dragging the in-game SFX slider while hitting
(`Settings.gd:93-97` sets the `SFX` bus): if hits do not follow the slider, they are going to
`Master` and the limiter in §7 step 6 is not protecting them.

Cheaper and better: since `polyphony` is a hard cap, the ring makes stealing *deterministic*
(oldest first) instead of relying on engine order.

### Stream format, bus, allocation

- **Sample format:** short one-shots as `AudioStreamWAV` (uncompressed PCM), not Ogg. Ogg is
  right for the song; a 150 ms hit does not need a decoder. **[TS]** — but it also removes a
  per-voice decompress from the hit path.
- **Preload, never `load()` in the hit path.** `preload()` the 7 samples at script load.
- **Bus:** keep the existing `SFX` bus (`audiobuslayout.tres:16-21`); it is already wired to
  the player (`default_saber.tscn:327`) and to `Settings.audio_sfx` (`Settings.gd:93-97`).
  Add an **`AudioEffectHardLimiter`** (or `AudioEffectLimiter`) on `SFX` so 8 near-simultaneous
  hits cannot clip the Master bus. Ceiling ≈ **-1 dB**, which is **[TS]**.
- **`max_distance`**: leave `0`. Every hit is ≤1.3 m from the listener; a cutoff only buys
  skipping that never triggers here.
- **Per-hit node churn is real but not the bottleneck.** At 8 hits/s, `instantiate()` +
  `add_child()` + `queue_free()` is 8 tree mutations/s — small in absolute terms **[D]**, but
  it also throws away per-voice control, costs the 8.3 ms `play()` physics-frame deferral
  **[V]**, and mutates the scene tree from inside an `area_entered` signal. It is the wrong
  shape even where it is not the wrong cost. `AudioStreamPlaybackPolyphonic` still allocates a
  playback object per `play_stream` **[P]**, but that is one `RefCounted`, not a node.
- **`AudioStreamRandomizer`** (`PLAYBACK_RANDOM_NO_REPEATS`, `random_pitch_semitones`,
  `random_volume_offset_db = 0`) is the zero-code way to get round-robin, and `playback_mode`
  alone satisfies FR-012's no-repeat rule **[V]**. It cannot take a per-hit pitch from
  gameplay, so the gameplay mapping must go through `play_stream`; use the randomizer purely as
  the *variant pool* behind each layer. Whether it re-rolls per playback instance when nested
  inside `AudioStreamPolyphonic` is **[P]** — see test #1 below.

---

## 6. Sample sources and licences (FR-007)

| Source | Licence | Attribution obligation | Caveat |
|---|---|---|---|
| **Kenney** — *Impact Sounds*, *Sci-fi Sounds*, *UI Audio* (`kenney.nl/assets/category:Audio`) | **CC0** — "all game assets on the asset pages are public domain licensed (CC0). You're free to use them, even in commercial projects" **[V]** | **none** — "Attribution is not required" **[V]** | sounds are stylised/cartoonish; may not read as a lightsaber |
| **Freesound** (`freesound.org`) | **per file**: CC0, CC-BY, or CC-BY-NC **[V]** | CC0: none. CC-BY: name + link + licence, as CC's attribution guide **[V]** | **filter to CC0 in search.** Freesound's own table says a CC-BY sample cannot be re-published under CC0 — `by → cc0 = No` **[V]**. Also: the exporter must exclude CC-BY-NC entirely for a store build |
| **OpenGameArt** | per file (CC0 / CC-BY / CC-BY-SA / GPL) | per file | CC-BY-SA on audio pulls a share-alike obligation into the asset, not the code — but mixing it into an MIT repo is a licence-compatibility argument you do not want to have. CC0 only |
| **Sonniss GDC bundles** (`sonniss.com/gameaudiogdc`) | royalty-free, "**No attribution is required** … unlimited number of projects for the rest of your lifetime" **[V]** | none | "licensed for **media production** (games, film, TV, interactive projects) only"; resale/redistribution is **not** granted. Safe inside a built APK; **not** safe as loose `.wav` files committed to a public repo **[P]** — treat as a build-time input, never a checked-in asset |
| **Pixabay audio** | Pixabay licence, no attribution | none | also restricts redistributing files "as-is" — same repo caveat as Sonniss **[P]** |

**Project-specific finding (do this before adding anything):** the shipped hit stream is
`res://game/data/beepcube_cut.ogg` (`default_saber.tscn:4,325`), and it has **no row in
`ATTRIBUTION.md`**. That file's own rule is "If an asset's provenance cannot be established,
it does not ship", so the current hit sound is either documented or replaced as part of this
work — replacing it is the cheaper path.

**Recommended provenance workflow:** one row per file in `ATTRIBUTION.md` with
`file | author | licence | source URL | date`. Any CC-BY row means the attribution must be
visible in-app or in the release notes, not only in the repo.

---

## 7. Implementation order (FR-008)

Dependency order; each step names the file.

| # | Step | File | Why first |
|---|---|---|---|
| 1 | `cut()` returns a `HitInfo` (`speed_len`, `angle_acc`, `dist_acc`, `travel`, `beat_acc`, `is_correct_saber`, `note_pos`); same struct built where the maths already lives | `game/BeepCube/BeepCube.gd` | one source of truth for scoring; audio must not re-derive it |
| 2 | Capture `controller_speed` and the cut plane *before* the audio call; `saber_visual.hit(time_offset, info)` | `game/LightSaber.gd` (lines 136-143) | **unblocks everything**; without it no mapping is possible |
| 3 | `hit(time_offset, info)`; `_pending_hits` holds `{remaining, info}`; gain → layer → pitch → `play_stream`; id ring + steal rule | `game/sabers/default/default_saber.gd` | the actual feature |
| 4 | `stream = AudioStreamPolyphonic` (`polyphony = 8`), emitter moved from mid-blade to `tip` (y≈1.2554), `attenuation_filter_cutoff_hz = 20500`, keep `attenuation_model = 3`, `max_distance = 0`, `panning_strength` 0.85 | `game/sabers/default/default_saber.tscn` | scene must match the script's expectations |
| 5 | Delete **every** `hitsound.play()` and the post-hoc `pitch_scale` write — `play()` on the polyphonic player would re-create the playback and kill all voices; override `hit(info)` and forward | `game/sabers/particles/particles_saber.gd` | it currently fights the manager; also the ordering bug (`play()` then `pitch_scale`) |
| 6 | `AudioEffectHardLimiter` on the `SFX` bus, ceiling ≈ -1 dB | `audiobuslayout.tres` | 8 voices sum; protect Master |
| 7 | Add 3 soft (pre-filtered) + 3 hard + 1 accent `AudioStreamWAV` files, then a provenance row per file | `game/data/`, `ATTRIBUTION.md` | content step; also resolves the undocumented `beepcube_cut.ogg` |
| 8 | On-device tests, in this order: **#1** `AudioStreamRandomizer` nested in `AudioStreamPolyphonic` re-rolls per hit (pass: 20 rapid hits, no immediate sample repeat) — if it fails, roll variants in GDScript; **#2** `play_stream(bus: &"SFX")` respects the bus (pass: hits follow the SFX slider); **#3** hit-to-sound latency with `play_stream` vs the old `play()` (expect ~8 ms better at 120 Hz physics) | measurement only | the two **[P]** claims in this brief |

Steps 1–3 are one change; do not land 3 before 1–2.

---

## 8. Sources

| # | Source | Used for |
|---|---|---|
| 1 | Godot docs, `AudioStreamPlayer3D` (`docs.godotengine.org/en/stable/classes/class_audiostreamplayer3d.html`) | attenuation models/units, `panning_strength`, Doppler, `max_polyphony`, `play()` physics-frame queue, filter cutoff |
| 2 | Godot docs, `AudioStreamPolyphonic` / `AudioStreamPlaybackPolyphonic` | single-player polyphony, per-voice `play_stream`, `INVALID_ID`, "starts immediately" |
| 3 | Godot docs, `AudioStreamRandomizer` | no-repeat playback modes, `random_pitch_semitones`, `random_volume_offset_db` |
| 4 | Godot docs, `AudioStreamPlayback` | `_mix()` is GDExtension-only |
| 5 | Godot source, `servers/audio/audio_server.cpp` | mixing on a dedicated `audio_thread` |
| 6 | Godot source, `main/main.cpp` | `audio/driver/output_latency` default 15 ms, range 1–100 |
| 7 | godot-proposals #949, #4377; Godot forum "No HRTF positional audio?" | no HRTF |
| 8 | Meta Horizon OS docs, *Meta XR Audio SDK Overview / Features* | HRTF spatializer, supported engines (Unity/Unreal/FMOD/Wwise), Quest 3 support, separate-thread performance note, panning pitfalls |
| 9 | Godot XR update, Feb 2025 (`godotengine.org/article/godot-xr-update-feb-2025`) | Godot Meta Toolkit = Platform SDK, not audio |
| 10 | Mark Cerny, *The Road to PS5*, GDC 2020, ~44:06–45:22 | Tempest = modified AMD GPU compute unit, cacheless, DMA, ~5000 sources |
| 11 | AMD GPUOpen, *TrueAudio Next* | "Fast OpenCL parallel batch convolution engine" |
| 12 | Valve, Steam Audio Unity docs — reverb effects | TrueAudio Next = convolution reverb only |
| 13 | Android Developers, *Low latency audio* | 480-frame periods, ~20 ms achievable, AAudio buffer tuning |
| 14 | Meta Quest blog, *Drumming in Valhalla* (21 Oct 2021) | Ragnarock: velocity → volume, beat-quantised hit sound + toggle |
| 15 | `github.com/GalaxyMaster2/HitsoundTweaks` README | Beat Saber: pitch 0.9–1.2, saber-tip spatialisation, speed gate, chain layer |
| 16 | Audiokinetic Wwise docs, *Creating Random Containers* | `Shuffle`, `Limit Repetition`, pitch randomiser |
| 17 | `kenney.nl/support` | CC0, no attribution |
| 18 | `freesound.org/help/faq` (§Licenses) | per-file licences, attribution format, `by → cc0 = No` table |
| 19 | `sonniss.com/gameaudiogdc` | royalty-free, no attribution, media-production-only, no redistribution |
| 20 | Meta Quest blog, *Bullseye! Harmonix Rhythm Shooter Audica* (7 Mar 2019) | Audica design intent (timing, not audio graph) |
| 21 | `cloudheadgames.com/pistol-whip`; UploadVR *Smoke & Thunder* interview | Pistol Whip beat-first framing |
