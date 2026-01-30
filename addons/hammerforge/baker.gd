@tool
extends Node
class_name Baker

func bake_from_csg(
    csg_node: CSGCombiner3D,
    material_override: Material = null,
    collision_layer: int = 1,
    collision_mask: int = 1
) -> Node3D:
    if not csg_node:
        return null

    var entries = csg_node.get_meshes()
    if entries.is_empty():
        return null

    var result = Node3D.new()
    result.name = "BakedGeometry"

    var static_body = StaticBody3D.new()
    static_body.name = "FloorCollision"
    static_body.collision_layer = collision_layer
    static_body.collision_mask = collision_mask
    result.add_child(static_body)

    var mesh_count := 0
    for entry in entries:
        var mesh: Mesh = null
        var mesh_xform := Transform3D.IDENTITY
        if entry is Mesh:
            mesh = entry
        elif entry is Array:
            if entry.size() > 0 and entry[0] is Mesh:
                mesh = entry[0]
            if entry.size() > 1 and entry[1] is Transform3D:
                mesh_xform = entry[1]
        if not mesh:
            continue

        var mesh_inst = MeshInstance3D.new()
        mesh_inst.name = "BakedMesh_%d" % mesh_count
        mesh_inst.mesh = mesh
        mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
        mesh_inst.transform = mesh_xform
        if material_override:
            mesh_inst.material_override = material_override
        result.add_child(mesh_inst)

        var collision = CollisionShape3D.new()
        collision.shape = mesh.create_trimesh_shape()
        collision.transform = mesh_xform
        static_body.add_child(collision)

        mesh_count += 1

    if mesh_count == 0:
        return null

    return result
