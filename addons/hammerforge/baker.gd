@tool
extends Node
class_name Baker

func bake_from_csg(csg_node: CSGCombiner3D) -> Node3D:
    var mesh = csg_node.mesh
    if not mesh:
        return null

    var result = Node3D.new()
    result.name = "BakedGeometry"

    var mesh_inst = MeshInstance3D.new()
    mesh_inst.mesh = mesh
    mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    result.add_child(mesh_inst)

    var static_body = StaticBody3D.new()
    static_body.name = "FloorCollision"
    var collision = CollisionShape3D.new()
    if mesh is Mesh:
        collision.shape = mesh.create_trimesh_shape()
    static_body.add_child(collision)
    result.add_child(static_body)

    return result
