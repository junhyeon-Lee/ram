## 발 디딤 IK: 애니메이션 속 발목이 바닥(계단 면 포함)보다 내려가려 할 때만 다리를 접어 발을 바닥 위에 둔다.
## 웅크리는 동작(밀어붙이기·낮은 돌진·착지 등)에서 발이 바닥에 파묻히던 문제를 막는다.
## 공중이거나 발이 충분히 높으면 IK 를 끄고(influence 0) 애니메이션을 그대로 둔다.
##
## 구성 (Skeleton3D 의 자식 순서가 곧 처리 순서다):
##   FootGrounder(이 스크립트) → TwoBoneIK3D(왼다리) → TwoBoneIK3D(오른다리)
## 이 스크립트가 먼저 '애니메이션만 적용된' 발목 위치를 읽어 목표점을 정하고, 뒤의 IK 가 다리를 푼다.
class_name FootGrounder
extends SkeletonModifier3D

const ANKLE_MIN := 0.07       # 바닥에서 발목까지 최소 높이 (서 있을 때 약 0.08)
const BLEND_RANGE := 0.03     # 이만큼 위에서부터 IK 를 조금씩 켠다 (툭 끊기지 않게)

var legs := []                # [{ik, foot, shin, target, pole}]
var exclude: Array[RID] = []
var max_influence := 0.0      # 점검용: 이번 프레임 가장 큰 IK 세기


static func attach(skeleton: Skeleton3D, owner_body: CollisionObject3D) -> FootGrounder:
	var g := FootGrounder.new()
	g.name = "FootGrounder"
	g.exclude = [owner_body.get_rid()]
	skeleton.add_child(g)
	for side in ["L", "R"]:
		var ik := TwoBoneIK3D.new()
		ik.name = "FootIK_" + side
		ik.set_setting_count(1)
		ik.set_root_bone_name(0, "thigh." + side)
		ik.set_middle_bone_name(0, "shin." + side)
		ik.set_end_bone_name(0, "foot." + side)
		var target := Node3D.new()
		target.name = "FootTarget_" + side
		var pole := Node3D.new()
		pole.name = "KneePole_" + side
		skeleton.add_child(ik)
		skeleton.add_child(target)
		skeleton.add_child(pole)
		ik.set_target_node(0, ik.get_path_to(target))
		ik.set_pole_node(0, ik.get_path_to(pole))
		ik.influence = 0.0
		g.legs.append({"ik": ik, "foot": skeleton.find_bone("foot." + side),
			"shin": skeleton.find_bone("shin." + side), "target": target, "pole": pole})
	return g


func _process_modification_with_delta(_delta: float) -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	var space := sk.get_world_3d().direct_space_state
	max_influence = 0.0
	for leg in legs:
		var ankle: Vector3 = sk.global_transform * sk.get_bone_global_pose(leg.foot).origin
		var knee: Vector3 = sk.global_transform * sk.get_bone_global_pose(leg.shin).origin
		# 발 아래 바닥 높이 (계단이면 계단 면)
		var q := PhysicsRayQueryParameters3D.create(ankle + Vector3.UP * 0.6, ankle + Vector3.DOWN * 0.8)
		q.exclude = exclude
		var hit := space.intersect_ray(q)
		var floor_y: float = hit.position.y if not hit.is_empty() else -INF
		var need := floor_y + ANKLE_MIN - ankle.y          # 양수면 그만큼 파묻힘
		var influence := clampf((need + BLEND_RANGE) / BLEND_RANGE, 0.0, 1.0)
		var t: Node3D = leg.target
		t.global_position = Vector3(ankle.x, maxf(ankle.y, floor_y + ANKLE_MIN), ankle.z)
		# 무릎은 애니메이션의 무릎 쪽으로 굽힌다 (발목에서 무릎 쪽으로 멀리)
		var p: Node3D = leg.pole
		p.global_position = knee + (knee - ankle).normalized() * 0.5
		(leg.ik as TwoBoneIK3D).influence = influence
		max_influence = maxf(max_influence, influence)
