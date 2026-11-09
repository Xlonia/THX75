# -*- coding: utf-8 -*-
p = 'scripts/versus/battle_arena.gd'
s = open(p, encoding='utf-8').read()

# ① dm_situate 多图权重（Ht3 Hd2 He1 Hp2 → sit_mean 换多图加权）
old = '''		var sum := 0
		for v in ent.sit16_1d:
			sum += v
		var mean := sum / 16 if ent.sit16_1d.size() == 16 else 0
		ent.set_meta("sit_mean", mean)'''
new = '''		## 【dm_situate 权重 20261021（新二文档）】Ht3 Hd2 He1 Hp2 加权平均
		## （十六点图取 1d 环；He/Hp 图取角色 49 点中心近似——逐环随表现批）
		var sum := 0
		for v in ent.sit16_1d:
			sum += v
		var mean := sum / 16 if ent.sit16_1d.size() == 16 else 0
		var he_at := float(ent.get_meta("hd_at", 0)) * 0.0 ## He 中心未采样
		var wsum := float(mean) * 3.0 + float(ent.get_meta("hd_at", 0)) * 2.0 + he_at * 1.0 + ent.hcs_at * 0.0
		## Ht(=sit16 1d 均值×3)+Hd(中心×2)；He/Hp 全图中心未实装暂 0
		ent.set_meta("sit_mean", int(wsum / 5.0))
		ent.set_meta("sit_mean_ht", mean) ## 原始 Ht 均值（滞回用——文档阈值基于十六点）'''
assert old in s
s = s.replace(old, new)

# ② 滞回用 Ht 均值（RET 接管阈值语义为态势十六点）
old = '''	var mean := 0
	if ent.sit16_1d.size() == 16:
		for v in ent.sit16_1d:
			mean += v
		mean /= 16
	if mean > 192:'''
new = '''	var mean := 0
	if ent.sit16_1d.size() == 16:
		for v in ent.sit16_1d:
			mean += v
		mean /= 16
	## 【免疫期 Sl 全可用 20261021】被弹免疫 0.5s 内 RET-SP 第一方向不视为不可用
	if ent.immune_frames > 0:
		mean = 0 ## 视为低热 → 不触发接管；且 Sl 分母段按可用处理（sit_cards.SL 段）
	if mean > 192:'''
assert old in s
s = s.replace(old, new)

# ③ 攻击态势 Shs-1d=0 / Shs-2d=1 权重（map_force Ht 部分）
old = '''				## Ht 权重=同向十六点（该环对应方向）
				var ring_arr: PackedInt32Array = e2.sit16_1d if k < 16 else (e2.sit16_2d if k < 32 else e2.sit16_5d)
				var v_ht: int = ring_arr[k % 16] if (k % 16) < ring_arr.size() else 0'''
new = '''				## Ht 权重=同向十六点；【Shs 权重 20261021】攻击态势 Shs-1d=0、Shs-2d=1，
				## 否则均 1（新二文档）；1d 环仅在非攻击态势参与
				var ring_arr: PackedInt32Array = e2.sit16_1d if k < 16 else (e2.sit16_2d if k < 32 else e2.sit16_5d)
				var v_ht: int = ring_arr[k % 16] if (k % 16) < ring_arr.size() else 0
				var shs_w := 1.0
				if e2.current_sit_card == "a" or e2.current_sit_card == "c":
					shs_w = 0.0 if k < 16 else 1.0'''
assert old in s
s = s.replace(old, new)
old = '''				var hot := (float(v_ht) / 255.0) * 1.0 + (float(v_hd) / 255.0) * 3.0 \\
					+ (v_hcs / 255.0) * 5.0 + (v_hct / 255.0) * 10.0 \\
					+ (float(v_he) / 255.0) * 2.0 + (float(v_hp) / 255.0) * 3.0'''
new = '''				var hot := (float(v_ht) / 255.0) * 1.0 * shs_w + (float(v_hd) / 255.0) * 3.0 \\
					+ (v_hcs / 255.0) * 5.0 + (v_hct / 255.0) * 10.0 \\
					+ (float(v_he) / 255.0) * 2.0 + (float(v_hp) / 255.0) * 3.0'''
assert old in s
s = s.replace(old, new)

# ④ 攻击态势关 Hcs/Hct、中性关 Hct（权重0——新二"四权重运算情况"）
old = '''			var f := Vector2.ZERO
			## 【权重表 20261020（游戏逻辑介绍）】dm_apfrepul：Ht1 Hd3 Hcs5 Hct10 He2 Hp3（分母24）
			var ht_arr: PackedInt32Array'''
new2 = '''			var f := Vector2.ZERO
			## 【权重表 20261021（新二）】dm_apfrepul：Ht1 Hd3 Hcs5 Hct10 He2 Hp3（分母24）；
			## 攻击态势(a/c) Hcs/Hct 均 0；中性(r/n/s) Hct 0（实时运算关闭）
			var card := e2.current_sit_card
			var w_hcs := 5.0 if card not in ["a", "c", "r", "n", "s"] else (5.0 if card in ["d", "h", "e"] else 0.0)
			var w_hct := 10.0 if card in ["d", "h", "e"] else 0.0'''
if old in s:
    s = s.replace(old, new2 + ''' ''' + '''var ht_arr: PackedInt32Array''')
else:
    # 宽松：直接在权重使用处替换
    pass
# 直接改 hot 公式加入 w_hcs/w_hct（若上面替换失败则在 hot 行补）
if 'var w_hcs := 5.0' not in s:
    old_a = '''			var f := Vector2.ZERO
			## 【权重表 20261020（游戏逻辑介绍）】dm_apfrepul：Ht1 Hd3 Hcs5 Hct10 He2 Hp3（分母24）'''
    new_a = '''			var f := Vector2.ZERO
			## 【权重表 20261021（新二）】dm_apfrepul：Ht1 Hd3 Hcs5 Hct10 He2 Hp3（分母24）；
			## 攻击态势(a/c) Hcs/Hct 均 0；中性(r/n/s) Hct 0（实时运算关闭）
			var card := e2.current_sit_card
			var w_hcs := 5.0 if card in ["d", "h", "e"] else 0.0
			var w_hct := 10.0 if card in ["d", "h", "e"] else 0.0'''
    assert old_a in s
    s = s.replace(old_a, new_a)
s = s.replace('''				var hot := (float(v_ht) / 255.0) * 1.0 * shs_w + (float(v_hd) / 255.0) * 3.0 \\
					+ (v_hcs / 255.0) * 5.0 + (v_hct / 255.0) * 10.0 \\
					+ (float(v_he) / 255.0) * 2.0 + (float(v_hp) / 255.0) * 3.0''',
'''				var hot := (float(v_ht) / 255.0) * 1.0 * shs_w + (float(v_hd) / 255.0) * 3.0 \\
					+ (v_hcs / 255.0) * w_hcs + (v_hct / 255.0) * w_hct \\
					+ (float(v_he) / 255.0) * 2.0 + (float(v_hp) / 255.0) * 3.0''')

open(p, 'w', encoding='utf-8', newline='\n').write(s)
print("weights ok")
