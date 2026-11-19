import io, os
# 【m98】数据 csv 被误标记 csv_translation 导入器（编辑器默认对新增 csv 生效）——
# 我们的数据表是程序读取（FileAccess），不是翻译表 → 改 keep 导入器（不导入）
# translation 错误输出（locale 无效/locale 无翻译）=每次启动 10+ 条的根因
DATA_CSVS = [
    'spell.csv', 'danmaku_clip.csv', 'danmaku_event.csv', 'danmaku_event_regular.csv',
    'danmaku_event_functed.csv', 'danmaku_event_laser.csv', 'danmaku_event_nodes.csv',
    'danmaku_event_physical.csv', 'privates.csv', 'Enemy.csv', 'charas_elements_arrays.csv',
]
KEEP = '[remap]\n\nimporter="keep"\n'
for fn in DATA_CSVS:
    ip = 'gameAssetBase/' + fn + '.import'
    if not os.path.exists(ip):
        print('SKIP(no import)', fn)
        continue
    s = io.open(ip, encoding='utf-8').read()
    if 'importer="csv_translation"' in s:
        io.open(ip, 'w', encoding='utf-8', newline='').write(KEEP)
        print('OK keep', fn)
    else:
        print('SKIP(already)', fn)
