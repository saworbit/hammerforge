@tool
extends Node
class_name Baker

func bake_from_csg(csg_node: CSGCombiner3D) -> Node3D:
    if not csg_node:
        return null

    var mesh: Mesh = null
    var mesh_xform := Transform3D.IDENTITY
    var meshes = csg_node.get_meshes()
    if meshes.size() == 0:
        return null
    var first = meshes[0]
    if first is Mesh:
        mesh = first
    elif first is Array and first.size() > 0 and first[0] is Mesh:
        mesh = first[0]
        if first.size() > 1 and first[1] is Transform3D:
            mesh_xform = first[1]
    if not mesh:
        return null

    var result = Node3D.new()
    result.name = "BakedGeometry"

    var mesh_inst = MeshInstance3D.new()
    mesh_inst.mesh = mesh
    mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    mesh_inst.transform = mesh_xform
    result.add_child(mesh_inst)

    var static_body = StaticBody3D.new()
    static_body.name = "FloorCollision"
    static_body.transform = mesh_xform
    var collision = CollisionShape3D.new()
    if mesh is Mesh:
        collision.shape = mesh.create_trimesh_shape()
    static_body.add_child(collision)
    result.add_child(static_body)

    return result
