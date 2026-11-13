"""Counts which map features a folder of BeatSaver maps uses.

    python tools/dev/census.py [folder-of-map-folders]

Reads only; prints one line per feature with the number of maps that use it.
"""
import collections, glob, json, os, sys

root = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.environ.get("TEMP", "."), "toolchain", "allsongs")
OBJECT_KEYS = {"animation", "track", "noteJumpMovementSpeed", "noteJumpStartBeatOffset", "coordinates", "position",
               "worldRotation", "localRotation", "rotation", "scale", "size", "uninteractable", "interactable", "fake",
               "color", "disableNoteGravity", "disableNoteLook", "definitePosition"}


def custom(o):
    return o.get("customData") or o.get("_customData") or {}


def load(path):
    try:
        with open(path, encoding="utf-8-sig") as f:
            return json.load(f)
    except Exception:
        return None


maps = 0
feat = collections.Counter()
events = collections.Counter()
for d in sorted(os.listdir(root)):
    info = next((x for x in (load(os.path.join(root, d, n)) for n in ("Info.dat", "info.dat")) if isinstance(x, dict)), None)
    if info is None:
        continue
    maps += 1
    found = set()
    sets = info.get("_difficultyBeatmapSets") or []
    diffs = [x for s in sets for x in s.get("_difficultyBeatmaps", [])] or info.get("difficultyBeatmaps", [])
    for x in diffs:
        c = custom(x)
        found.update("requires " + r for r in (c.get("_requirements") or c.get("requirements") or []))
    for path in glob.glob(os.path.join(root, d, "*.dat")):
        if os.path.basename(path).lower() in ("info.dat", "bpminfo.dat", "audiodata.dat"):
            continue
        m = load(path)
        if not isinstance(m, dict):
            continue
        c = custom(m)
        for e in c.get("customEvents") or c.get("_customEvents") or []:
            kind = str(e.get("t") or e.get("_type"))
            events[kind] += 1
            found.add("event " + kind)
        if c.get("environment") or c.get("_environment"):
            found.add("chroma environment objects")
        for key in ("colorNotes", "_notes", "bombNotes", "obstacles", "_obstacles"):
            for o in m.get(key) or []:
                if isinstance(o, dict):
                    found.update("object " + k.lstrip("_") for k in custom(o) if k.lstrip("_") in OBJECT_KEYS)
        if m.get("sliders") or m.get("_sliders") or m.get("arcs"):
            found.add("arcs")
        if m.get("burstSliders") or m.get("chains"):
            found.add("chains")
        if m.get("rotationEvents"):
            found.add("90/360 rotation")
        if m.get("lightColorEventBoxGroups"):
            found.add("box-group lighting")
        found.add("format v" + str(m.get("version") or m.get("_version") or "?")[:1])
    for x in found:
        feat[x] += 1

print("maps", maps, "in", root)
for name, count in sorted(feat.items(), key=lambda kv: (-kv[1], kv[0])):
    print("%4d  %s" % (count, name))
print("custom events:", dict(events.most_common()))
