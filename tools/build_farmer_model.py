"""Build the editable low-poly farmer prototype with Blender's bundled Python.

blender --background --factory-startup --python tools/build_farmer_model.py
Blender -Y is forward, exported as Godot +Z. Dimensions here are modelling units;
the Godot wrapper applies a fixed 0.28 world scale, independent of the camera.
"""
from pathlib import Path
import json
import math
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'game/player/model_3d'
OUT.mkdir(parents=True, exist_ok=True)
(OUT / 'source').mkdir(exist_ok=True)
(OUT / 'source/.gdignore').touch()
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
scene = bpy.context.scene
scene.render.fps = 30
parts = []
palette = {
    'skin': (0.91, 0.72, 0.48), 'skin_shadow': (0.72, 0.48, 0.27),
    'cap': (0.03, 0.49, 0.78), 'cap_seam': (0.035, 0.39, 0.64),
    'gold': (0.94, 0.58, 0.075), 'hair': (0.37, 0.20, 0.065),
    'shirt': (0.90, 0.88, 0.73), 'glove': (0.96, 0.95, 0.85),
    'denim': (0.06, 0.36, 0.53), 'denim_dark': (0.04, 0.24, 0.36),
    'scarf': (0.86, 0.12, 0.035), 'boot': (0.20, 0.25, 0.25),
    'sole': (0.12, 0.16, 0.16), 'eye': (0.055, 0.045, 0.035),
    'button': (0.91, 0.71, 0.29), 'bag_shadow': (0.66, 0.34, 0.035),
}


def linear(value):
    return value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4


material = bpy.data.materials.new('farmer_vertex_palette')
material.use_nodes = True
bsdf = material.node_tree.nodes.get('Principled BSDF')
bsdf.inputs['Roughness'].default_value = 1
color_node = material.node_tree.nodes.new('ShaderNodeVertexColor')
color_node.layer_name = 'Color'
material.node_tree.links.new(color_node.outputs['Color'], bsdf.inputs['Base Color'])


def finish(obj, name, color, bone):
    obj.name = name
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(material)
    colors = obj.data.color_attributes.new(name='Color', type='FLOAT_COLOR', domain='CORNER')
    key = Vector((-0.45, -0.7, 1.0)).normalized()
    base = palette[color]
    for face in obj.data.polygons:
        # A baked palette keeps the model legible in the original unlit maps.
        shade = 0.76 + 0.24 * max(0, face.normal.dot(key))
        for index in face.loop_indices:
            colors.data[index].color = (*[linear(c * shade) for c in base], 1)
    parts.append((obj, bone))
    return obj


def ellipsoid(name, position, scale, color, bone='head', segments=16, rings=8):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, location=position)
    obj = bpy.context.object
    obj.scale = scale
    return finish(obj, name, color, bone)


def box(name, position, size, color, bone, bevel=0.04):
    bpy.ops.mesh.primitive_cube_add(size=1, location=position)
    obj = bpy.context.object
    obj.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        modifier = obj.modifiers.new('rounded_edges', 'BEVEL')
        modifier.width = bevel
        modifier.segments = 2
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    return finish(obj, name, color, bone)


def mesh(name, vertices, faces, color, bone='head'):
    data = bpy.data.meshes.new(name)
    data.from_pydata(vertices, [], faces)
    data.update()
    obj = bpy.data.objects.new(name, data)
    scene.collection.objects.link(obj)
    return finish(obj, name, color, bone)


def limb(name, start, end, radius, color, bone):
    delta = Vector(end) - Vector(start)
    bpy.ops.mesh.primitive_cone_add(vertices=10, radius1=radius * 0.86, radius2=radius,
                                  depth=delta.length, location=(Vector(start) + Vector(end)) / 2)
    obj = bpy.context.object
    obj.rotation_euler = delta.to_track_quat('Z', 'Y').to_euler()
    return finish(obj, name, color, bone)


# Silhouette: a broad cap/head, short body and large mittens/boots.
box('cream_work_shirt', (0, 0, 0.80), (0.39, 0.30, 0.40), 'shirt', 'spine', 0.065)
box('overall_waist', (0, 0, 0.58), (0.37, 0.29, 0.18), 'denim_dark', 'pelvis', 0.055)
box('overall_bib', (0, -0.161, 0.75), (0.29, 0.055, 0.28), 'denim', 'spine', 0.035)
box('bib_pocket', (0, -0.194, 0.75), (0.15, 0.015, 0.10), 'denim_dark', 'spine', 0.012)
for sign, side in [(-1, 'left'), (1, 'right')]:
    box(f'{side}_overall_strap', (sign * 0.13, -0.156, 0.91), (0.065, 0.038, 0.23), 'denim', 'spine', 0.015)
    ellipsoid(f'{side}_bib_button', (sign * 0.13, -0.184, 0.855), (0.018, 0.008, 0.018), 'button', 'spine', 8, 4)
ellipsoid('neck', (0, 0, 1.04), (0.09, 0.085, 0.10), 'skin', 'spine')
box('red_neckerchief_collar', (0, -0.025, 1.025), (0.27, 0.24, 0.065), 'scarf', 'spine', 0.025)
ellipsoid('neckerchief_knot', (0, -0.176, 0.994), (0.045, 0.035, 0.04), 'scarf', 'spine', 10, 5)
mesh('neckerchief_left_tail', [(-0.025,-0.19,1.00),(-0.12,-0.19,0.87),(-0.13,-0.19,0.98)], [(0,1,2)], 'scarf', 'spine')
mesh('neckerchief_right_tail', [(0.02,-0.19,1.00),(0.08,-0.19,0.86),(0.12,-0.19,0.98)], [(0,1,2)], 'scarf', 'spine')

ellipsoid('round_canvas_backpack', (0, 0.23, 0.79), (0.185, 0.145, 0.215), 'gold', 'spine', 16, 10)
box('backpack_bottom_seam', (0, 0.286, 0.65), (0.28, 0.10, 0.065), 'bag_shadow', 'spine', 0.025)
box('backpack_top_flap', (0, 0.32, 0.92), (0.31, 0.08, 0.14), 'gold', 'spine', 0.045)
box('backpack_clasp', (0, 0.368, 0.85), (0.04, 0.015, 0.07), 'bag_shadow', 'spine', 0.01)
for sign, side in [(-1, 'left'), (1, 'right')]:
    x = sign * 0.11
    limb(f'{side}_trouser_thigh', (x, 0, 0.57), (x, 0, 0.34), 0.10, 'denim', f'thigh_{side}')
    limb(f'{side}_trouser_cuff', (x, 0, 0.34), (x, -0.005, 0.17), 0.085, 'denim_dark', f'shin_{side}')
    ellipsoid(f'{side}_boot_sole', (x,-0.055,0.045), (0.105,0.15,0.045), 'sole', f'shin_{side}', 12, 6)
    ellipsoid(f'{side}_work_boot', (x, -0.04, 0.115), (0.105, 0.15, 0.10), 'boot', f'shin_{side}', 12, 6)
    shoulder = (sign * 0.235, 0, 0.96)
    elbow = (sign * 0.28, -0.005, 0.77)
    wrist = (sign * 0.31, -0.025, 0.62)
    limb(f'{side}_rolled_sleeve', shoulder, elbow, 0.09, 'shirt', f'upper_arm_{side}')
    limb(f'{side}_forearm', elbow, wrist, 0.062, 'skin', f'forearm_{side}')
    ellipsoid(f'{side}_white_mitten', wrist, (0.085, 0.075, 0.09), 'glove', f'forearm_{side}', 12, 6)
    ellipsoid(f'{side}_glove_thumb', (sign * 0.25,-0.055,0.64), (0.038, 0.045, 0.05), 'glove', f'forearm_{side}', 10, 5)

ellipsoid('rounded_face', (0, -0.025, 1.265), (0.29, 0.24, 0.255), 'skin', 'head', 20, 12)
ellipsoid('brown_hair_back', (0, 0.12, 1.40), (0.292, 0.20, 0.18), 'hair')
for sign, side in [(-1, 'left'), (1, 'right')]:
    ellipsoid(f'{side}_ear', (sign * 0.278, -0.005, 1.26), (0.052, 0.055, 0.07), 'skin')
    ellipsoid(f'{side}_ear_inner', (sign * 0.313, -0.035, 1.265), (0.014, 0.029, 0.035), 'skin_shadow', segments=8, rings=4)
    box(f'{side}_sideburn', (sign * 0.25,-0.085,1.36), (0.045,0.09,0.12), 'hair', 'head', 0.012)
    mesh(f'{side}_hair_tuft', [(sign*.23,.015,1.46),(sign*.36,.035,1.46),(sign*.57,-.10,1.34),
                             (sign*.32,-.015,1.365),(sign*.30,.12,1.41)],
         [(0,1,4),(1,2,3),(1,3,4),(0,4,3),(0,3,2,1)], 'hair')
    ellipsoid(f'{side}_eye', (sign * 0.112,-0.254,1.285), (0.022,0.013,0.049), 'eye', segments=10, rings=6)
    ellipsoid(f'{side}_eye_glint', (sign * 0.112-0.004,-0.267,1.306), (0.006,0.004,0.010), 'glove', segments=8, rings=4)
ellipsoid('button_nose', (0,-0.263,1.205), (0.035,0.028,0.035), 'skin', segments=12, rings=6)
box('small_smile', (0,-0.253,1.135), (0.055,0.008,0.012), 'skin_shadow', 'head', 0.003)

# Blue crown; the original sprite's ochre bill projects behind the head.
vertices, faces = [], []
segments, rings = 24, 8
for ring in range(rings + 1):
    theta = (ring / rings) * math.pi / 2
    for i in range(segments):
        angle = i * math.tau / segments
        vertices.append((.35*math.sin(theta)*math.cos(angle), .025+.315*math.sin(theta)*math.sin(angle), 1.46+.275*math.cos(theta)))
for j in range(rings):
    for i in range(segments):
        a=j*segments+i; b=j*segments+(i+1)%segments
        faces.append((a,a+segments,b+segments,b))
mesh('blue_cap_crown', vertices, faces, 'cap')
ellipsoid('cap_top_button', (0,.025,1.738), (.029,.029,.018), 'cap_seam', segments=10, rings=5)
ellipsoid('ochre_cap_bill', (0,.28,1.465), (.35,.26,.035), 'gold', segments=24, rings=6)
ellipsoid('cap_adjustment_band', (0,-.263,1.46), (.11,.021,.028), 'cap_seam', segments=12, rings=6)


def chibi_height(z):
    return z * .75 if z <= .56 else z - .14


# Shorten the legs while keeping the head and upper-body volumes intact.
for obj, _ in parts:
    inverse = obj.matrix_world.inverted()
    for vertex in obj.data.vertices:
        point = obj.matrix_world @ vertex.co
        point.x *= 1.2
        point.y *= 1.2
        point.z = chibi_height(point.z)
        vertex.co = inverse @ point
    obj.data.update()

# One rigid weight per separate low-poly part; editable bones, no runtime IK.
bpy.ops.object.armature_add(enter_editmode=True)
rig = bpy.context.object
rig.name = 'FarmerRig'
armature = rig.data
armature.name = 'farmer_skeleton'
armature.edit_bones.remove(armature.edit_bones[0])


def bone(name, head, tail, parent=None):
    result = armature.edit_bones.new(name)
    result.head = (head[0]*1.2,head[1]*1.2,chibi_height(head[2]))
    result.tail = (tail[0]*1.2,tail[1]*1.2,chibi_height(tail[2]))
    if parent:
        result.parent = armature.edit_bones[parent]


bone('root', (0,0,0), (0,0,.15))
bone('pelvis', (0,0,.56), (0,0,.72), 'root')
bone('spine', (0,0,.72), (0,0,1.04), 'pelvis')
bone('head', (0,0,1.04), (0,0,1.55), 'spine')
for sign, side in [(-1, 'left'), (1, 'right')]:
    bone(f'thigh_{side}', (sign*.11,0,.56), (sign*.11,0,.34), 'pelvis')
    bone(f'shin_{side}', (sign*.11,0,.34), (sign*.11,0,.10), f'thigh_{side}')
    bone(f'upper_arm_{side}', (sign*.235,0,.96), (sign*.28,-.005,.77), 'spine')
    bone(f'forearm_{side}', (sign*.28,-.005,.77), (sign*.31,-.025,.62), f'upper_arm_{side}')
bpy.ops.object.mode_set(mode='OBJECT')
for obj, joint in parts:
    obj.parent = rig
    group = obj.vertex_groups.new(name=joint)
    group.add(list(range(len(obj.data.vertices))), 1, 'REPLACE')
    modifier = obj.modifiers.new('farmer_skin', 'ARMATURE')
    modifier.object = rig

rig.animation_data_create()
for name, duration in [('idle',60), ('walk',24), ('run',16)]:
    action = bpy.data.actions.new(name)
    rig.animation_data.action = action
    for frame in range(duration + 1):
        phase = math.tau * frame / duration
        for pose in rig.pose.bones:
            pose.rotation_mode = 'XYZ'
            pose.rotation_euler = (0,0,0)
            pose.location = (0,0,0)
        if name == 'idle':
            rig.pose.bones['spine'].location.y = math.sin(phase) * .006
            rig.pose.bones['head'].rotation_euler.x = math.sin(phase) * .012
        else:
            running = name == 'run'
            rig.pose.bones['pelvis'].location.y = (1-math.cos(phase*2)) * (.018 if running else .008)
            rig.pose.bones['spine'].rotation_euler.x = -.11 if running else -.025
            for sign, side in [(-1,'left'),(1,'right')]:
                swing = math.sin(phase) * sign
                rig.pose.bones[f'thigh_{side}'].rotation_euler.x = swing * (.72 if running else .43)
                rig.pose.bones[f'shin_{side}'].rotation_euler.x = max(0,-swing) * (1.0 if running else .55)
                rig.pose.bones[f'upper_arm_{side}'].rotation_euler.x = -swing * (.65 if running else .38)
                rig.pose.bones[f'forearm_{side}'].rotation_euler.x = -.65 if running else -.12
        for pose in rig.pose.bones:
            pose.keyframe_insert('rotation_euler', frame=frame+1, group=pose.name)
            pose.keyframe_insert('location', frame=frame+1, group=pose.name)
    action.use_fake_user = True
    action['loop'] = True
rig.animation_data.action = bpy.data.actions['idle']
scene.frame_set(1)
scene.frame_end = 61

# Export only the character. The saved Blender scene also has a viewing camera.
bpy.ops.object.select_all(action='DESELECT')
triangles = sum(sum(len(p.vertices)-2 for p in obj.data.polygons) for obj,_ in parts)
source_meshes = len(parts)
export_parts = []
for obj, _ in parts:
    copy = obj.copy()
    copy.data = obj.data.copy()
    scene.collection.objects.link(copy)
    copy.select_set(True)
    export_parts.append(copy)
bpy.context.view_layer.objects.active = export_parts[0]
bpy.ops.object.join()
export_mesh = bpy.context.object
export_mesh.name = 'farmer_skinned_mesh'
rig.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.export_scene.gltf(filepath=str(OUT/'farmer.glb'), export_format='GLB',
                         use_selection=True, export_animations=True,
                         export_animation_mode='ACTIONS', export_force_sampling=True,
                         export_cameras=False, export_lights=False)
bpy.data.objects.remove(export_mesh, do_unlink=True)

scene.world.color = (.35,.35,.35)
bpy.ops.object.camera_add(location=(3.2,-5.2,3.0))
camera = bpy.context.object
camera.name = 'FarmerReviewCamera'
camera.rotation_euler = (Vector((0,0,.90))-camera.location).to_track_quat('-Z','Y').to_euler()
camera.data.type = 'ORTHO'
camera.data.ortho_scale = 2.25
scene.camera = camera
bpy.ops.object.light_add(type='AREA', location=(-3,-4,6))
bpy.context.object.data.energy = 450
bpy.context.object.data.shape = 'DISK'
bpy.context.object.data.size = 5
scene.render.engine = 'CYCLES'
scene.cycles.samples = 16
scene.render.resolution_x = 640
scene.render.resolution_y = 640
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = 'PNG'
scene.render.film_transparent = True
scene.view_settings.view_transform = 'Standard'
scene.render.filepath = str(ROOT/'verification/farmer_3d_blender.png')
bpy.ops.object.select_all(action='DESELECT')
rig.select_set(True)
bpy.context.view_layer.objects.active = rig
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type == 'VIEW_3D':
            area.spaces.active.region_3d.view_distance = 3.2
            area.spaces.active.region_3d.view_location = Vector((0,0,.85))
            area.spaces.active.shading.type = 'MATERIAL'
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'source/farmer.blend'))
report = dict(blender=bpy.app.version_string, source_meshes=source_meshes, exported_meshes=1, triangles=triangles,
              bones=len(armature.bones), animations=['idle','walk','run'], world_scale=.28,
              notes='Hand-built prototype from four source sprite facings; hidden geometry inferred.')
(ROOT/'verification/farmer-model.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
assert len(armature.bones) == 12 and triangles < 12000
print('FARMER_MODEL_OK', report)
bpy.ops.render.render(write_still=True)
