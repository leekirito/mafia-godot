extends Node3D
## Procedural first-pass art. No external models or destructive Blender edits.
var camera: Camera3D
var lamp: OmniLight3D
var figures: Array = []
var tags: Array = []
var seats: Array = []
var card: MeshInstance3D
var blood_marks: Array = []
var night := false
var active_game := false
var time := 0.0
var base_camera := Vector3(0, 3.0, 7.7)
var aim := Vector3(0, 1.0, 0)
var inspect := false
var blood_enabled := true
var grain_enabled := true
var look_offset := Vector2.ZERO
var mat_wood: ShaderMaterial
var mat_wall: ShaderMaterial

func material(color: Color, metallic := 0.0, rough := 0.8) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = rough
	return m

func textured(base: Color, grain: float) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """shader_type spatial;
uniform vec4 base_color : source_color;
uniform float grain = 1.0;
varying vec3 pos;
void vertex(){ pos = VERTEX; }
float hash(vec3 p){return fract(sin(dot(p,vec3(127.1,311.7,74.7)))*43758.5453);}
void fragment(){
 float n = hash(floor(pos*80.0));
 float streak = sin(pos.x*grain*65.0 + sin(pos.z*12.0)*2.0)*0.07;
 ALBEDO = base_color.rgb*(0.7+n*0.4+streak);
 ROUGHNESS = 0.85;
}"""
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("base_color", base)
	m.set_shader_parameter("grain", grain)
	return m

func mesh_at(parent: Node3D, mesh: Mesh, pos: Vector3, mat: Material) -> MeshInstance3D:
	var obj := MeshInstance3D.new()
	obj.mesh = mesh
	obj.position = pos
	obj.material_override = mat
	parent.add_child(obj)
	return obj

func box(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh_at(parent, mesh, pos, mat)

func cylinder(parent: Node3D, pos: Vector3, radius: float, height: float, mat: Material, vertices := 24) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = vertices
	return mesh_at(parent, mesh, pos, mat)

func _ready() -> void:
	mat_wood = textured(Color("30251c"), 0.2)
	mat_wall = textured(Color("353936"), 1.0)
	var metal := material(Color("292c29"), 0.6)
	var black := material(Color("101412"))
	var brass := material(Color("8e7145"), 0.7, 0.4)
	box(self, Vector3(0, -0.14, 0), Vector3(18, 0.25, 18), mat_wall)
	box(self, Vector3(0, 2.5, -6), Vector3(18, 5, 0.3), mat_wall)
	box(self, Vector3(-7, 2.5, 0), Vector3(0.3, 5, 14), mat_wall)
	box(self, Vector3(7, 2.5, 0), Vector3(0.3, 5, 14), mat_wall)
	box(self, Vector3(0, 5, 0), Vector3(18, 0.2, 18), black)
	# Wall battens and service pipes.
	for x in [-6.0, -3.0, 0.0, 3.0, 6.0]:
		box(self, Vector3(x, 2.5, -5.8), Vector3(0.12, 5, 0.12), metal)
	for y in [3.7, 4.0]:
		var pipe := cylinder(self, Vector3(0, y, -5.65), 0.055, 14, metal)
		pipe.rotation.z = PI / 2.0
	box(self, Vector3(4.4, 1.5, -5.75), Vector3(1.5, 3, 0.15), black)
	box(self, Vector3(4.4, 1.5, -5.64), Vector3(1.3, 2.8, 0.08), metal)
	box(self, Vector3(4.85, 1.4, -5.5), Vector3(0.08, 0.35, 0.1), brass)
	var sign := Label3D.new()
	sign.text = "NO ONE LEAVES"
	sign.font_size = 44
	sign.pixel_size = 0.009
	sign.position = Vector3(0, 3.05, -5.78)
	sign.modulate = Color("a58b62")
	add_child(sign)
	var sub := Label3D.new()
	sub.text = "UNTIL THE TABLE AGREES"
	sub.font_size = 22
	sub.pixel_size = 0.007
	sub.position = Vector3(0, 2.62, -5.77)
	sub.modulate = Color("716c54")
	add_child(sub)
	# Oval table, iron rim, pedestal and central runner.
	var rim := cylinder(self, Vector3(0, 1.12, 0), 2.65, 0.19, metal, 64)
	rim.scale.z = 1.28
	var top := cylinder(self, Vector3(0, 1.23, 0), 2.6, 0.12, mat_wood, 64)
	top.scale.z = 1.28
	cylinder(self, Vector3(0, 0.55, 0), 0.75, 1.1, black)
	box(self, Vector3(0, 1.299, 0), Vector3(0.8, 0.012, 5.4), material(Color("293c33")))
	for i in range(12):
		var angle := TAU * float(i) / 12.0
		var pos := Vector3(sin(angle) * 3.25, 0, cos(angle) * 4.05)
		seats.append(pos)
		var root := Node3D.new()
		root.position = pos
		root.rotation.y = angle
		add_child(root)
		box(root, Vector3(0, 0.52, 0), Vector3(0.75, 0.12, 0.7), mat_wood)
		box(root, Vector3(0, 1.1, 0.32), Vector3(0.76, 1.0, 0.1), mat_wood)
		for x in [-0.3, 0.3]:
			for z in [-0.25, 0.25]: box(root, Vector3(x, 0.25, z), Vector3(0.06, 0.5, 0.06), metal)
		var person := Node3D.new()
		root.add_child(person)
		var coat := material(Color.from_hsv(0.09 + i * 0.015, 0.16, 0.12 + (i % 3) * 0.035))
		var torso_mesh := CylinderMesh.new()
		torso_mesh.top_radius = 0.36
		torso_mesh.bottom_radius = 0.27
		torso_mesh.height = 0.78
		torso_mesh.radial_segments = 7
		mesh_at(person, torso_mesh, Vector3(0, 1.04, 0), coat)
		var head_mesh := SphereMesh.new()
		head_mesh.radius = 0.23
		head_mesh.height = 0.54
		head_mesh.radial_segments = 12
		head_mesh.rings = 6
		mesh_at(person, head_mesh, Vector3(0, 1.68, 0), black)
		var mask := mesh_at(person, head_mesh, Vector3(0, 1.68, -0.12), material(Color("a99d7f")))
		mask.scale = Vector3(0.9, 0.92, 0.45)
		for x in [-0.075, 0.075]:
			box(person, Vector3(x, 1.72, -0.228), Vector3(0.075, 0.04, 0.018), black)
		box(person, Vector3(0, 1.55, -0.222), Vector3(0.07, 0.012, 0.015), black)
		for x in [-0.34, 0.34]:
			var arm := box(person, Vector3(x, 0.98, -0.18), Vector3(0.16, 0.6, 0.2), coat)
			arm.rotation.x = -0.4
		figures.append(person)
		var nameplate := Label3D.new()
		nameplate.text = "SEAT %02d" % (i + 1)
		nameplate.position = Vector3(pos.x * 0.79, 1.48, pos.z * 0.79)
		nameplate.font_size = 28
		nameplate.pixel_size = 0.004
		nameplate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		nameplate.modulate = Color("c0ad83")
		add_child(nameplate)
		tags.append(nameplate)
		var back_mat := material(Color.WHITE)
		back_mat.albedo_texture = load("res://assets/cards/back.png")
		var table_card := box(self, Vector3(pos.x * 0.67, 1.32, pos.z * 0.67), Vector3(0.21, 0.006, 0.3), back_mat)
		table_card.rotation.y = angle
		var stain := cylinder(self, Vector3(pos.x * 0.75, 1.315, pos.z * 0.75), 0.22, 0.004, material(Color("4b1212")), 11)
		stain.scale.z = 0.6
		stain.visible = false
		blood_marks.append(stain)
	# Overhead pendant and candle clusters.
	var shade := CylinderMesh.new()
	shade.top_radius = 0.32
	shade.bottom_radius = 0.75
	shade.height = 0.35
	mesh_at(self, shade, Vector3(0, 3.6, 0), metal)
	cylinder(self, Vector3(0, 4.2, 0), 0.015, 1.0, black)
	var glow := material(Color("ffe0a1"))
	glow.emission_enabled = true
	glow.emission = Color("ffd894")
	glow.emission_energy_multiplier = 3.0
	cylinder(self, Vector3(0, 3.4, 0), 0.45, 0.03, glow)
	lamp = OmniLight3D.new()
	lamp.position = Vector3(0, 3.2, 0)
	lamp.light_color = Color("ffdaa0")
	lamp.light_energy = 3.5
	lamp.omni_range = 9
	lamp.shadow_enabled = true
	add_child(lamp)
	for z in [-1.0, 1.0]:
		cylinder(self, Vector3(0, 1.34, z), 0.12, 0.04, brass)
		cylinder(self, Vector3(0, 1.52, z), 0.05, 0.32, material(Color("b7aa7c")))
		var flame := OmniLight3D.new()
		flame.position = Vector3(0, 1.74, z)
		flame.light_color = Color("ff9f42")
		flame.light_energy = 0.5
		flame.omni_range = 2.5
		add_child(flame)
		box(self, Vector3(0, 1.70, z), Vector3(0.025, 0.06, 0.025), glow)
	var fill := OmniLight3D.new()
	fill.position = Vector3(0, 3, -4.5)
	fill.light_color = Color("739c89")
	fill.light_energy = 1.6
	fill.omni_range = 7
	add_child(fill)
	var env := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("080c0b")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("788177")
	settings.ambient_light_energy = 0.28
	settings.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	settings.fog_enabled = true
	settings.fog_light_color = Color("17211c")
	settings.fog_density = 0.018
	env.environment = settings
	add_child(env)
	camera = Camera3D.new()
	camera.position = base_camera
	camera.fov = 68
	add_child(camera)
	camera.look_at(aim)
	camera.current = true
	var face := material(Color.WHITE)
	face.albedo_texture = load("res://assets/cards/back.png")
	face.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var plane := QuadMesh.new()
	plane.size = Vector2(0.27, 0.383)
	card = mesh_at(camera, plane, Vector3(0.29, -0.27, -0.65), face)
	card.rotation.z = -0.12
	card.visible = false

func update_match(data: Dictionary) -> void:
	active_game = not data.is_empty() and data.get("phase", "lobby") != "lobby"
	night = data.get("phase", "") == "night"
	var ps: Array = data.get("players", [])
	var self_id: int = data.get("self_id", 1)
	var me := 0
	for i in range(ps.size()):
		if ps[i].id == self_id: me = i
	for i in range(12):
		var source := (me + i) % maxi(ps.size(), 1)
		var occupied := i < ps.size()
		figures[i].visible = occupied and i != 0
		tags[i].visible = occupied and i != 0
		if occupied:
			var p: Dictionary = ps[source]
			figures[i].rotation.x = 0.85 if not p.alive else 0.0
			tags[i].text = p.name.to_upper() + ("  †" if not p.alive else "")
			tags[i].modulate = Color("66584c") if not p.alive else Color("c8b78c")
			blood_marks[i].visible = not p.alive and blood_enabled
		else:
			blood_marks[i].visible = false
	if ps.is_empty():
		for i in range(1, 10): figures[i].visible = true
	var role: String = data.get("role", "")
	if role != "": card.material_override.albedo_texture = load("res://assets/cards/%s.png" % role.to_lower())
	card.visible = active_game and inspect
	base_camera = Vector3(0, 1.83, 4.02) if active_game else Vector3(0, 3.0, 7.7)
	aim = Vector3(0, 1.35, -0.7) if active_game else Vector3(0, 1.0, 0)

func _process(delta: float) -> void:
	time += delta
	if not camera: return
	var desired := 0.20 if night else 3.5
	lamp.light_energy = lerpf(lamp.light_energy, desired, delta * 2.0)
	camera.position = camera.position.lerp(base_camera, minf(delta * 3, 1))
	camera.look_at(aim + Vector3(look_offset.x, look_offset.y, 0))
	card.visible = active_game and inspect
	for i in range(figures.size()):
		if figures[i].rotation.x < 0.4:
			figures[i].position.y = sin(time * 0.8 + i * 1.4) * 0.006
