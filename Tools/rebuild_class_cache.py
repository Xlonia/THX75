# -*- coding: utf-8 -*-
"""rebuild_class_cache.py —— th75 全局类缓存重建（m128 固化配方）
背景：作者 GUI 编辑器全量重扫会把 .godot/global_script_class_cache.cfg
重写为"宿主类 only"（kit/ 是含 project.godot 的嵌套项目，扫描不深入）——
内核类+插件类丢失=项目脚本全面解析失败。本脚本把三类条目合并进当前缓存：
  ①当前缓存保留（宿主 86 类）
  ②作者副本缓存映射（内核类，路径前缀 thx_gamekit→thxgamekit/kit/addons/thx_gamekit）
  ③插件 9 类手工条目（keshinozo）
用法：python Tools/rebuild_class_cache.py （在 th75 根执行）
验证：Godot --headless --editor --quit-after 后跑任意探针应无 "not declared"。
"""
import io, json, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CFG = os.path.join(ROOT, '.godot', 'global_script_class_cache.cfg')
COPY_SRC = r'D:/Hyomumoene/game/THXGameKit/.godot/global_script_class_cache.cfg'
PREFIX_MAP = 'res://addons/thx_gamekit/'
PREFIX_NEW = 'res://addons/thxgamekit/kit/addons/thx_gamekit/'

PLUGINS = [
    ('EntityCore', 'BattleEntity', 'versus/battle_entity.gd'),
    ('Control', 'RetreatPointPicker', 'ui/retreat_point_picker.gd'),
    ('Control', 'PresetPointPicker', 'ui/preset_point_picker.gd'),
    ('RefCounted', 'CompletionView', 'ui/completion_view.gd'),
    ('RefCounted', 'FireControl', 'versus/fire_control.gd'),
    ('RefCounted', 'KeyBindings', 'versus/key_bindings.gd'),
    ('RefCounted', 'RetSystem', 'versus/ret_system.gd'),
    ('RefCounted', 'SitCardSystem', 'versus/sit_card_system.gd'),
    ('RefCounted', 'PrivateFormation', 'versus/private_formation.gd'),
]
# 手工补漏（副本缓存过时缺的新内核类）：类名 → (base, kit 内相对路径)
EXTRA_KERNEL = [
    ('Node', 'ChapterFlow', 'core/flow/chapter_flow.gd'),
    ('RefCounted', 'BehaviorScore', 'core/flow/behavior_score.gd'),
]


def read_classes(text):
    """抽出 ConfigFile list=[...] 内的条目块列表"""
    start = text.find('list=[{')
    if start < 0:
        return []
    body = text[start + len('list='):]
    end = body.rfind(']')
    body = body[:end]
    items = []
    depth = 0
    cur = ''
    SEP = ', \n\t\r'
    for ch in body:
        if depth == 0 and ch in SEP:
            continue  # 条目间分隔符跳过（修复：', ' 前缀污染致隔条丢失——m128）
        cur += ch
        if ch == '{':
            depth += 1
        elif ch == '}':
            depth -= 1
            if depth == 0:
                items.append(cur.strip())
                cur = ''
    return [i for i in items if i.startswith('{')]


def main():
    cur = io.open(CFG, 'rb').read().decode('utf-8')
    have = set()
    import re
    for m in re.finditer(r'"class": &"([^"]+)"', cur):
        have.add(m.group(1))
    add = []
    # ②作者副本内核类（映射前缀）
    if os.path.exists(COPY_SRC):
        k = io.open(COPY_SRC, 'rb').read().decode('utf-8').replace(PREFIX_MAP, PREFIX_NEW)
        for item in read_classes(k):
            m = re.search(r'"class": &"([^"]+)"', item)
            if m and m.group(1) not in have:
                add.append(item)
                have.add(m.group(1))
    # ②b 手工补漏内核类（ChapterFlow 等）
    for base, cls, rel in EXTRA_KERNEL:
        if cls in have:
            continue
        add.append('{\n"base": &"%s",\n"class": &"%s",\n"icon": "",\n"is_abstract": false,\n"is_tool": false,\n"language": &"GDScript",\n"path": "res://addons/thxgamekit/kit/addons/thx_gamekit/%s"\n}' % (base, cls, rel))
        have.add(cls)
    # ③插件类
    for base, cls, p in PLUGINS:
        if cls in have:
            continue
        add.append('{\n"base": &"%s",\n"class": &"%s",\n"icon": "",\n"is_abstract": false,\n"is_tool": false,\n"language": &"GDScript",\n"path": "res://addons/thxgamekit/kit/addons/keshinozo/%s"\n}' % (base, cls, p))
        have.add(cls)
    if not add:
        print('无需新增（全部已在）')
        return
    # 拼接：在【尾条目闭合 } 之后】插入新条目（保结构：尾条目 } + , + 新条目 + list 闭合 ]）
    # ——注意：rfind('}]') 指向尾条目闭合 } 本身；切到 body_end+1 保住该 }（
    #   曾两次犯"把闭合 } 切掉"错=ConfigFile:688/696 解析炸——m128 二次入档）
    body_end = cur.rfind('}]')
    assert body_end > 0
    head = cur[:body_end + 1]  # 含尾条目闭合 }
    tail = cur[body_end + 1:]  # = ']\n'
    new_items = ', '.join(add)
    out = head + ', ' + new_items + tail
    io.open(CFG, 'wb').write(out.encode('utf-8'))
    print('已合并 %d 条 → 总 %d' % (len(add), len(re.findall(r'"class"', out))))


if __name__ == '__main__':
    main()
