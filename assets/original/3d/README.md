# Original fixed-view 3D candidate assets

These assets are original procedural low-poly models for the formal fixed-view slices. They are not
derived from any third-party game. Rebuild them from the repository root with:

```sh
python3 assets/original/3d/sources/generate_lowpoly_assets.py
godot --headless --editor --path . --import
```

The Python standard-library generator is the source of truth for geometry, the 13-bone shared rig,
rigid skin weights, six animation curves, material palette, two weapon variants, reusable
environment modules, four qi-eating beasts, two lantern-pillar states, the lantern core, and the
foundation altar. Generator v5 keeps both arms in a relaxed readable baseline throughout all six
animation clips instead of exposing the horizontal bind pose during idle or state transitions. It
adds an enemy-only stone palette so faceted bodies stay readable under the darker lantern-pass
lighting, while retaining the v3 finite palette, humanoid silhouette contrast, and emissive crystals
across 24 manifest records. `manifest.json` records deterministic
SHA-256 hashes, byte sizes, triangle
counts, bone names, animation names, coordinates, and camera reference.

Runtime-facing files are GLB, PNG, `.tres`, and wrapper `.tscn` scenes. Godot import cache files are
not source assets. World units are meters, +Y is up, forward is -Z, and character feet rest at y=0.

The fixed camera reference is yaw 45 degrees, elevation 35.264 degrees, orthographic size 12. The
showcase and screenshot command are:

```sh
godot --path . -s res://game/presentation/action_combat_3d/tools/capture_g3_assets.gd
```

It writes `/tmp/godot-pal-3d-assets/g3_asset_showcase.png` at 640x360.

The title portrait is a deterministic transparent render of `humanoid_base.glb`, not a separately
authored directional sprite. Rebuild it with:

```sh
godot --path . -s res://assets/original/3d/sources/render_title_portrait.gd
```
