import csv, io
# 作者 20261119 新三份数据：数百对照/双帧平滑/五帧平滑——维度分析
files = [
    ("gameAssetBase/aiTest/0.0.9/调试数据/11191442数百弹幕对照.csv", "数百对照"),
    ("gameAssetBase/aiTest/0.0.9/调试数据/11191440弹幕双帧平滑.csv", "双帧平滑"),
    ("gameAssetBase/aiTest/0.0.9/调试数据/11191442弹幕五帧平滑.csv", "五帧平滑"),
]
for fn, tag in files:
    try:
        rows = list(csv.reader(io.open(fn, encoding="utf-8-sig")))
    except Exception as e:
        print(tag, "ERR", e)
        continue
    hdr = rows[0]
    idx = {h: i for i, h in enumerate(hdr)}
    data = [r for r in rows[1:] if len(r) == len(hdr)]
    def col(name):
        return [float(r[idx[name]]) for r in data] if name in idx else []
    fps = col("time/fps")
    proc = col("time/process")
    phys = col("time/physics_process")
    dc = col("raster/total_draw_calls")
    prim = col("raster/total_primitives_drawn")
    obj = col("raster/total_objects_drawn")
    n = len(fps)
    def pct(a, p):
        b = sorted(a)
        return b[min(n - 1, int(n * p))]
    below60 = sum(1 for f in fps if f < 59.5)
    print(f"== {tag} n={n} ==")
    print(f"  fps p10={pct(fps,.1):.0f} p50={pct(fps,.5):.0f} p90={pct(fps,.9):.0f} <60帧占比={100.0*below60/n:.0f}%")
    print(f"  proc p50={pct(proc,.5)*1000:.1f} p90={pct(proc,.9)*1000:.1f} | phys p50={pct(phys,.5)*1000:.2f} p90={pct(phys,.9)*1000:.2f}")
    if dc:
        print(f"  draw p50={pct(dc,.5):.0f} max={max(dc):.0f} | prim p50={pct(prim,.5):.0f} max={max(prim):.0f} | obj p50={pct(obj,.5):.0f} max={max(obj):.0f}")
