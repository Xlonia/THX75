import csv, sys, io
# 作者 20261117 新三份调试数据速扫：fps/proc/phys/draw_calls/primitives/objects
files = [
    ("11171637.csv", "16:37"),
    ("11171645（可投降）.csv", "16:45可投降"),
    ("11171647（不投降）.csv", "16:47不投降"),
]
for fn, tag in files:
    rows = list(csv.reader(io.open(fn, encoding="utf-8-sig")))
    hdr = rows[0]
    idx = {h: i for i, h in enumerate(hdr)}
    data = [r for r in rows[1:] if len(r) == len(hdr)]
    def col(name):
        return [float(r[idx[name]]) for r in data]
    fps = col("time/fps")
    proc = col("time/process")
    phys = col("time/physics_process")
    dc = col("raster/total_draw_calls")
    prim = col("raster/total_primitives_drawn")
    objs = col("object/objects")
    n = len(fps)
    def pct(a, p):
        b = sorted(a)
        return b[min(n - 1, int(n * p))]
    print(f"== {tag} n={n} ==")
    print(f"  fps   p10={pct(fps,.1):.0f} p50={pct(fps,.5):.0f} min={min(fps):.0f}")
    print(f"  proc  p50={pct(proc,.5)*1000:.1f}ms p90={pct(proc,.9)*1000:.1f}ms max={max(proc)*1000:.1f}ms")
    print(f"  phys  p50={pct(phys,.5)*1000:.2f}ms p90={pct(phys,.9)*1000:.2f}ms max={max(phys)*1000:.1f}ms")
    print(f"  draw  p50={pct(dc,.5):.0f} max={max(dc):.0f}  prim p50={pct(prim,.5):.0f} max={max(prim):.0f}")
    print(f"  objs  p50={pct(objs,.5):.0f} max={max(objs):.0f}")
    # 分段：每 n/8 段的 fps 均值与 prim 均值
    seg = n // 8
    line = "  seg fps/prim: "
    for i in range(8):
        s = fps[i*seg:(i+1)*seg]; q = prim[i*seg:(i+1)*seg]
        line += f"{sum(s)/len(s):.0f}/{sum(q)/len(q):.0f}  "
    print(line)
