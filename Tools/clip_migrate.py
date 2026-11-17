import csv, io, json, sys

# 【m85 片段迁移】Characters.csv 三槽（main/rest→Main_Cd、sub→Sub_Cd）事件直引
# → 单弹幕片段引用（clip_{Char}_{slot}_{Event}，长度=Cd 最低长度，ticks={"0":[E]}）
# 同时生成 danmaku_clip.csv（三列：clip_name,length,ticks——RFC4180 引号双写）
def migrate(char_csv, clip_csv):
    raw = io.open(char_csv, encoding='utf-8-sig', newline='').read()
    nl = '\r\n' if '\r\n' in raw else '\n'
    lines = raw.split(nl)
    rows = list(csv.reader(io.open(char_csv, encoding='utf-8-sig')))
    hdr = rows[0]
    i_main, i_rest, i_sub = hdr.index('main_evs'), hdr.index('rest_evs'), hdr.index('sub_evs')
    i_mcd, i_scd = hdr.index('Main_Cd'), hdr.index('Sub_Cd')
    clips = []
    out_rows = [rows[0]]
    n = 0
    for r in rows[1:]:
        if not r or not r[0].strip():
            out_rows.append(r)
            continue
        d = dict(zip(hdr, r))
        mcd = max(1, int(float(d.get('Main_Cd', 4) or 4)))
        scd = max(1, int(float(d.get('Sub_Cd', 2) or 2)))
        for col_i, slot, cd in ((i_main, 'main', mcd), (i_rest, 'rest', mcd), (i_sub, 'sub', scd)):
            names = [x.strip() for x in (r[col_i] if col_i < len(r) else '').split(';') if x.strip()]
            if not names:
                continue
            new_refs = []
            for ev in names:
                cn = 'clip_%s_%s_%s' % (r[0], slot, ev)
                clips.append([cn, cd, {"0": [ev]}])
                new_refs.append(cn)
                n += 1
            r[col_i] = ';'.join(new_refs)
        out_rows.append(r)
    buf = io.StringIO()
    w = csv.writer(buf, lineterminator='\n', quoting=csv.QUOTE_MINIMAL)
    w.writerow(['clip_name', 'length', 'ticks', 'group'])
    for cn, cd, tk in clips:
        w.writerow([cn, cd, json.dumps(tk, separators=(',', ':')), 'legacy'])
    io.open(clip_csv, 'w', encoding='utf-8', newline='').write(buf.getvalue())
    with io.open(char_csv, 'w', encoding='utf-8-sig', newline='') as f:
        w2 = csv.writer(f, lineterminator=nl, quoting=csv.QUOTE_MINIMAL)
        w2.writerows(out_rows)
    print('OK %s -> %s (%d clips)' % (char_csv, clip_csv, n))

if __name__ == '__main__':
    migrate(sys.argv[1], sys.argv[2])
