# -*- coding: utf-8 -*-
# 修复：RET-SP 接管块插错位置（插进了 _entity_ticks 的 move 段内）——
# 移回 _ai_drive 的 push 修正区（墙检测块之前）
p = 'scripts/versus/battle_arena.gd'
s = open(p, encoding='utf-8').read()

# 1) 删除误插块（_entity_ticks 内）
bad = '''		## 【v0.0.8 RET-SP·L228】防御态势（d/h/e）RET-SP 接管移动：倾向最高的
	## 第一步方向直驱（与 APF 合成——树主导向），无方向时回落 APF
	if ent.ret != null and ent.ret.sp_dirs.size() > 0 and ent.current_sit_card in ["d", "h", "e"]:
		push = push * 0.4 + ent.ret.sp_dirs[0] * 1.2
	## 【v0.0.8·L227】RET 接管期不穿 wall：最终方向在墙方向上的分量清零
'''
assert bad in s
s = s.replace(bad, '		## 【v0.0.8·L227】RET 接管期不穿 wall：最终方向在墙方向上的分量清零\n')

# 2) 插入正确位置：_ai_drive 内墙检测块之前（ret_gravity meta 写入后）
anchor = '''		if ent.ret != null and ent.ret.path_tendency != Vector2.ZERO:
			var ret_w := 1.6 if ent.get_meta("ret_mode", false) else 0.6
			ent.set_meta("ret_gravity", ent.ret.path_tendency.normalized() * ret_w)'''
assert anchor in s
s = s.replace(anchor, anchor + '''
		## 【v0.0.8 RET-SP·L228】防御态势（d/h/e）RET-SP 接管：倾向最高的第一步
		## 方向与 APF 合成（树主导向 1.2 / APF 0.4），无方向时回落 APF
		if ent.ret != null and ent.ret.sp_dirs.size() > 0 and ent.current_sit_card in ["d", "h", "e"]:
			push = push * 0.4 + ent.ret.sp_dirs[0] * 1.2''')
open(p, 'w', encoding='utf-8', newline='\n').write(s)
print("relocate ok")
