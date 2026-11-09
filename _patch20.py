# -*- coding: utf-8 -*-
BS = chr(92)
p = 'scripts/danmaku/danmaku_expr.gd'
s = open(p, encoding='utf-8').read()

# ① gettarget 参数捕获扩为词字符（x_copy/hpweapon/dm_smn/1d_ht_aver…）
old = '\tre_gt.compile("gettarget' + BS+BS + '(' + BS+BS + 's*([a-z]+)' + BS+BS + 's*' + BS+BS + ')")'
assert old in s, "re_gt"
new = '\tre_gt.compile("gettarget' + BS+BS + '(' + BS+BS + 's*([A-Za-z_0-9]+)' + BS+BS + 's*' + BS+BS + ')")'
s = s.replace(old, new)

# ② gtmap 扩展：dm_* 快照参数 + 态势热图变量重排（1d_ht_aver→ht1daver）+ 未知透传
old2 = '''\tvar gtmap := {"x": "target_x", "y": "target_y", "d": "d", "ap": "target_ap",
\t\t"pp": "target_pp", "normal": "target_normal", "hpweapon": "target_hpweapon",
\t\t"hpbody": "target_hpbody", "hpmove": "target_hpmove",
\t\t"kp": "target_kp", "sp": "target_sp"}'''
assert old2 in s, "gtmap"
new2 = '''\t## 【修复 20261025b】参数名含下划线/数字（x_copy、dm_smn、1d_ht_aver…）此前
\t## 被 [a-z]+ 拒收→gettarget(x_copy) 原样残留→执行期静默失败回退 0（Youshio1
\t## 弹幕全程静止的根因）。现扩为词字符；未知名透传（编译期对未注册名报错可见）。
\tvar gtmap := {"x": "target_x", "y": "target_y", "d": "d", "ap": "target_ap",
\t\t"pp": "target_pp", "normal": "target_normal", "hpweapon": "target_hpweapon",
\t\t"hpbody": "target_hpbody", "hpmove": "target_hpmove",
\t\t"kp": "target_kp", "sp": "target_sp",
\t\t"dm_apfrepul": "target_dm_apfrepul", "dm_situate": "target_dm_situate",
\t\tdm_smn": "target_dm_smn", "dm_sms": "target_dm_sms"}
\tvar re_shs := RegEx.new()
\tre_shs.compile("^([0-9])d_([a-z]+)_(aver|vectsum)$") ## 1d_ht_aver → ht1daver'''
assert new2.count('dm_smn"') == 1
# 修正 new2 里的引号笔误
new2 = new2.replace('\t\tdm_smn": "target_dm_smn", "dm_sms": "target_dm_sms"}',
                    '\t\t"dm_smn": "target_dm_smn", "dm_sms": "target_dm_sms"}')
s = s.replace(old2, new2)

# ③ 替换循环体：映射→态势重排→透传
old3 = '''\twhile mgt != null:
\t\tvar gk: String = mgt.strings[1]
\t\tout = out.substr(0, mgt.get_start()) + gtmap.get(gk, gk) + out.substr(mgt.get_end())
\t\tmgt = re_gt.search(out)'''
assert old3 in s, "loop"
new3 = '''\twhile mgt != null:
\t\tvar gk: String = mgt.strings[1]
\t\tvar mapped: String = gtmap.get(gk, "")
\t\tif mapped == "":
\t\t\tvar mshs := re_shs.search(gk)
\t\t\tif mshs != null:
\t\t\t\tmapped = mshs.strings[2] + mshs.strings[1] + "d" + mshs.strings[3]
\t\t\telse:
\t\t\t\tmapped = gk ## 透传（未注册名在编译期可见报错，不再静默）
\t\tout = out.substr(0, mgt.get_start()) + mapped + out.substr(mgt.get_end())
\t\tmgt = re_gt.search(out)'''
s = s.replace(old3, new3)

# ④ getchara 同修（"normal" 含 o 不在 [xydapn] 内——同样拒收）+ 未知透传
old4 = '\tre_gc.compile("getchara' + BS+BS + '(' + BS+BS + 's*([xydapn]{1,6})' + BS+BS + 's*' + BS+BS + ')")'
assert old4 in s, "re_gc"
s = s.replace(old4, '\tre_gc.compile("getchara' + BS+BS + '(' + BS+BS + 's*([A-Za-z_0-9]+)' + BS+BS + 's*' + BS+BS + ')")')
old5 = 'out = out.substr(0, mgc.get_start()) + selfmap.get(gv, "self_x") + out.substr(mgc.get_end())'
assert old5 in s, "selfmap fallback"
s = s.replace(old5, 'out = out.substr(0, mgc.get_start()) + selfmap.get(gv, gv) + out.substr(mgc.get_end())')

open(p, 'w', encoding='utf-8', newline='\n').write(s)
print("regex fix ok")
