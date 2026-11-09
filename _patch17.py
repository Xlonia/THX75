# -*- coding: utf-8 -*-
p = 'scripts/versus/battle_arena.gd'
s = open(p, encoding='utf-8').read()

# ⑤ Hr 直线斥力（\t 单层缩进）
old = '\t## 【R-ETA（策划）】点向类追踪弹规避力（弹幕侧累积；读后清零）'
assert old in s, "reta"
new = '''\t## 【Hr 直线斥力（新二 20261021 简化版）】快弹（≥4px/f）1.5秒距内且朝向
\t## 角色的直线分量>1秒距 → 垂直逃离中线斥力（速度×4）；>慢机速度→强制插 c 卡
\tvar n_spd2 := ent.normal_speed()
\tvar hr_forced_c := false
\tfor b2 in bullets:
\t\tvar bl2: Bullet = b2
\t\tif bl2.hidden_now or bl2.track_speed < 4.0 or bl2.source_side == ent.side:
\t\t\tcontinue
\t\tvar to_ent: Vector2 = ent.position - bl2.pos
\t\tif to_ent.length() > n_spd2 * 60.0 * 1.5:
\t\t\tcontinue
\t\tif to_ent.dot(bl2.track_dir) < n_spd2 * 60.0 * 1.0:
\t\t\tcontinue
\t\tvar perp3 := Vector2(-bl2.track_dir.y, bl2.track_dir.x)
\t\tif to_ent.dot(perp3) < 0.0:
\t\t\tperp3 = -perp3
\t\tvar mag3 := bl2.track_speed * 4.0
\t\tpush += perp3 * minf(mag3 / 255.0, 1.0) * 1.2
\t\tif mag3 > n_spd2:
\t\t\thr_forced_c = true
\tif hr_forced_c and ent.sit_cards != null and not ent.sit_cards.ring.is_empty():
\t\tent.sit_cards.ring[0] = "c"
''' + old
s = s.replace(old, new, 1)

# ⑥ 攻击夹角
old2 = '\tvar tgt_pos: Vector2 = target.position'
assert old2 in s, "tgt"
s = s.replace(old2, '''\tvar tgt_pos: Vector2 = target.position
\t## 【攻击夹角（新二 20261021）】攻击方向与朝向夹角<1 弧度不发起攻击
\tvar tgt_dir2 := target.position - ent.position
\tvar atk_ang := absf(ent.facing.angle_to(tgt_dir2.normalized())) if tgt_dir2.length() > 0.01 else 0.0''', 1)

idx = s.find('\tmatch ent.current_sit_card:', s.find('func _ai_drive'))
assert idx > 0, "match"
s = s[:idx] + '\tif atk_ang < 1.0 and (ent.current_sit_card == "a" or ent.current_sit_card == "c"):\n\t\tanchor = 0.0 ## 攻击夹角不足——不发起攻击（新二）\n' + s[idx:]

# ⑦ 号召乘数
old4 = '\tif rally_appeal > 0.0:'
assert old4 in s, "rally"
s = s.replace(old4, '''\tif rally_appeal > 0.0:
\t\t## 【号召乘数（新二 20261021）】号召强度 × 剩余能力/普通符卡数
\t\tvar appeal2 := rally_appeal * maxf(1.0, float(ent.spell_cards))''', 1)
old5 = "push += (rally_point - ent.position).normalized() * minf(rally_appeal * 0.25, 1.0) * 0.4"
assert old5 in s, "rally use"
s = s.replace(old5, "push += (rally_point - ent.position).normalized() * minf(appeal2 * 0.25, 1.0) * 0.4")

# ⑧ 指令圈 2 秒
s = s.replace('\t\t\t\tcmd_frames = 300 ## 5秒', '\t\t\t\tcmd_frames = 120 ## 【新二 20261021】2秒；重复点击延长（不叠加）')

# ⑨ 杂兵 APF
old6 = '\t## 杂兵排布每3帧一次（formation 步进+sync_private_pos 降频）'
assert old6 in s, "fm"
new6 = '''\t## 【杂兵 APF（新二 20261021）】Hd×2 + 所属角色 Hcs×5（共用 owner 的 Hcs；
\t## RET-SP 完全跳过）——每 0.2s 一次写入 meta，formation 移动侧消费
\tif time_frames % 12 == 0:
\t\tfor fm in formations:
\t\t\tvar priv2: BattleEntity = fm.private_ent
\t\t\tvar owner2: BattleEntity = fm.owner
\t\t\tif priv2 == null or owner2 == null or priv2.dead:
\t\t\t\tcontinue
\t\t\tvar push3 := Vector2.ZERO
\t\t\tvar spin3 := TAU / 32.0 * float(time_frames % 2)
\t\t\tfor k3 in 32:
\t\t\t\tvar ring3: PackedInt32Array = owner2.sit16_1d if k3 < 16 else owner2.sit16_2d
\t\t\t\tvar v3: int = ring3[k3 % 16] if (k3 % 16) < ring3.size() else 0
\t\t\t\tvar a3 := spin3 - PI / 2.0 + TAU * float(k3 % 16) / 16.0
\t\t\t\tvar dv3 := Vector2(cos(a3), sin(a3))
\t\t\t\tvar v_hcs3: float = owner2.hcs_pts[k3] if k3 < owner2.hcs_pts.size() else 0.0
\t\t\t\tvar hot3 := (float(v3) / 255.0) * 2.0 + (v_hcs3 / 255.0) * 5.0
\t\t\t\tpush3 -= dv3 * (hot3 / 7.0) * (1.0 if k3 < 16 else 2.0)
\t\t\tpriv2.set_meta("apf_push", push3.limit_length(1.0) * priv2.normal_speed() * 0.5)
''' + old6
s = s.replace(old6, new6, 1)
open(p, 'w', encoding='utf-8', newline='\n').write(s)
print("all ok")
