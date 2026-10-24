PSX Motel 3D Trash and Clutter v1.0
by AssetsFactory

7 free trash and clutter props to dirty up a run-down 1990s motel, each modelled one by one,
in 2 versions:
  detailed/  bevelled real shapes, 256 px/m textures (linear filtering)
  ps1/       authentic PS1 cut, 128 px 16-colour textures, nearest filtering, no specular

Want the rest of the room? PSX Motel 3D Props has 25 more props (beds, CRT TV, dresser with opening
drawers, bathtub, ice machine, vending machine...) in the same 2 versions, with lit lamps and TV:
https://assetsfactory.itch.io/psx-motel-3d-props

SCALE, AXES, PIVOTS
  1 unit = 1 metre, real-world sizes. Blender: Z up, front towards -Y (Godot/Unity: front towards +Z).
  Pivot: centre of the footprint, on the floor.

FOLDERS
  detailed/ and ps1/
    fbx/  one FBX per prop + its textures folder (Unity, Unreal, Godot)
    glb/  one GLB per prop, textures embedded, with a convex collision hull named <Prop>-colonly (Godot)
    obj/  one OBJ + MTL per prop
  blend/                 one Blender file per version with every prop
  godot_demo_detailed/   Godot 4 project: open it and press F5 (right mouse = orbit, wheel = zoom)
  godot_demo_ps1/

TESTED
  Every GLB passes the Khronos glTF validator. Every FBX, GLB and OBJ was re-imported into a clean
  Blender 5.2 and checked. Both Godot demo projects import all props with Godot 4.7 (headless).
  Not tested in Unity or Unreal.

PROPS (detailed / PS1 triangles, size)
  SM_Motel_BeerBottle          884 /  112 tris   0.06 x 0.06 x 0.24 m
  SM_Motel_CardboardBox        644 /   62 tris   0.49 x 0.36 x 0.30 m
  SM_Motel_CrushedCan          932 /  112 tris   0.07 x 0.12 x 0.05 m
  SM_Motel_Newspaper           878 /  104 tris   0.31 x 0.38 x 0.02 m
  SM_Motel_PizzaBox            800 /  104 tris   0.36 x 0.36 x 0.04 m
  SM_Motel_TakeoutCup          960 /  114 tris   0.10 x 0.10 x 0.22 m
  SM_Motel_TrashBag            930 /   94 tris   0.49 x 0.42 x 0.57 m

AI tools were used in the making of these assets. The 3D models were built object by object with
Python scripts in Blender: no AI-generated mesh.

License: see LICENSE.txt. In short: free for your commercial and non-commercial projects,
do not resell or share the files themselves.
