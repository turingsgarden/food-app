import json
from pathlib import Path

import numpy as np

GROUPS = {
    "1": "1 Milk / dairy",
    "2": "2 Meat / poultry / fish / mixtures",
    "3": "3 Eggs",
    "4": "4 Beans / nuts / seeds",
    "5": "5 Grain products",
    "6": "6 Fruits",
    "7": "7 Vegetables",
    "8": "8 Fats / oils / dressings",
    "9": "9 Sugars / sweets / beverages",
}
COLORS = ["#1f77b4", "#d62728", "#bcbd22", "#8c564b", "#ff7f0e",
          "#e377c2", "#2ca02c", "#7f7f7f", "#9467bd"]

HTML = """<!doctype html>
<html><head><meta charset="utf-8"><title>FNDDS vector map</title>
<style>
body{font-family:-apple-system,Helvetica,Arial,sans-serif;margin:16px;color:#222}
#wrap{display:flex;gap:16px;align-items:flex-start}
canvas{border:1px solid #ccc;border-radius:6px;background:#fff}
#side{width:300px;font-size:13px}
.row{display:flex;align-items:center;gap:6px;margin:3px 0;cursor:pointer}
.sw{width:12px;height:12px;border-radius:50%;display:inline-block}
input[type=text]{width:100%;padding:6px;box-sizing:border-box;margin:6px 0 12px}
#tip{position:fixed;pointer-events:none;background:#222;color:#fff;padding:6px 8px;border-radius:4px;font-size:12px;display:none;max-width:340px}
.note{color:#666;margin-top:14px;line-height:1.5}
</style></head><body>
<h3>FNDDS vector map: __N__ foods, text-embedding-3-large (3072 dims) reduced to 2D with t-SNE</h3>
<div id="wrap"><canvas id="c" width="900" height="640"></canvas>
<div id="side">
<b>Search a food</b><input id="q" type="text" placeholder="e.g. milk, pizza, croissant">
<div id="hits"></div>
<b>Food groups</b><div id="legend"></div>
<div class="note">Each dot is one FNDDS food. Dots that sit close together have similar descriptions in embedding space.
Hover a dot to see its food code and name. Colour = first digit of the food code (the FNDDS commodity group).</div>
</div></div><div id="tip"></div>
<script>
const P = __DATA__;
const GN = __GROUPS__, GC = __COLORS__;
const cv = document.getElementById('c'), ctx = cv.getContext('2d');
const tip = document.getElementById('tip'), qi = document.getElementById('q'), hits = document.getElementById('hits');
let xs = P.map(p => p[0]), ys = P.map(p => p[1]);
const x0 = Math.min(...xs), x1 = Math.max(...xs), y0 = Math.min(...ys), y1 = Math.max(...ys);
const pad = 20, W = cv.width, H = cv.height;
const sx = x => pad + (x - x0) / (x1 - x0) * (W - 2 * pad);
const sy = y => pad + (y - y0) / (y1 - y0) * (H - 2 * pad);
const on = GN.map(() => true);
let query = '';
const scr = P.map(p => [sx(p[0]), sy(p[1])]);
function match(p) { return query && p[4].toLowerCase().includes(query); }
function draw() {
  ctx.clearRect(0, 0, W, H);
  for (let i = 0; i < P.length; i++) {
    const p = P[i]; if (!on[p[2]]) continue;
    const m = match(p);
    ctx.globalAlpha = query ? (m ? 1 : 0.12) : 0.75;
    ctx.fillStyle = GC[p[2]];
    ctx.beginPath(); ctx.arc(scr[i][0], scr[i][1], m ? 5 : 3, 0, 6.2832); ctx.fill();
    if (m) { ctx.strokeStyle = '#000'; ctx.lineWidth = 1; ctx.stroke(); }
  }
  ctx.globalAlpha = 1;
}
const lg = document.getElementById('legend');
GN.forEach((n, i) => {
  const d = document.createElement('label'); d.className = 'row';
  d.innerHTML = '<input type="checkbox" checked><span class="sw" style="background:' + GC[i] + '"></span>' + n;
  d.querySelector('input').onchange = e => { on[i] = e.target.checked; draw(); };
  lg.appendChild(d);
});
qi.oninput = () => {
  query = qi.value.trim().toLowerCase(); draw();
  const m = query ? P.filter(match) : [];
  hits.innerHTML = query ? '<div class="note">' + m.length + ' matches' + (m.length ? ': ' + m.slice(0, 5).map(p => p[4]).join('; ') + (m.length > 5 ? ' ...' : '') : '') + '</div>' : '';
};
cv.onmousemove = e => {
  const r = cv.getBoundingClientRect(), mx = (e.clientX - r.left) * W / r.width, my = (e.clientY - r.top) * H / r.height;
  let best = -1, bd = 64;
  for (let i = 0; i < P.length; i++) {
    if (!on[P[i][2]]) continue;
    const dx = scr[i][0] - mx, dy = scr[i][1] - my, d = dx * dx + dy * dy;
    if (d < bd) { bd = d; best = i; }
  }
  if (best < 0) { tip.style.display = 'none'; return; }
  const p = P[best];
  tip.innerHTML = '<b>' + p[3] + '</b><br>' + p[4] + '<br><span style="color:#aaa">' + GN[p[2]] + '</span>';
  tip.style.left = (e.clientX + 14) + 'px'; tip.style.top = (e.clientY + 14) + 'px'; tip.style.display = 'block';
};
cv.onmouseleave = () => { tip.style.display = 'none'; };
draw();
</script></body></html>
"""


def build_html(codes, names, xy, out_path):
    pts = []
    for c, n, (x, y) in zip(codes, names, xy):
        g = int(str(c)[0]) - 1
        g = min(max(g, 0), 8)
        pts.append([round(float(x), 2), round(float(y), 2), g, str(c), str(n)])
    html = (HTML.replace("__N__", str(len(pts)))
                .replace("__DATA__", json.dumps(pts, ensure_ascii=False))
                .replace("__GROUPS__", json.dumps(list(GROUPS.values())))
                .replace("__COLORS__", json.dumps(COLORS)))
    Path(out_path).write_text(html, encoding="utf-8")


def main():
    import chromadb
    from sklearn.decomposition import PCA
    from sklearn.manifold import TSNE

    col = chromadb.PersistentClient(path="outputs/chroma_db").get_collection("fndds")
    data = col.get(include=["embeddings", "metadatas"])
    codes = data["ids"]
    names = [m["main_description"] for m in data["metadatas"]]
    emb = np.array(data["embeddings"], dtype=np.float32)
    print("loaded from Chroma:", emb.shape[0], "vectors of dimension", emb.shape[1])

    print("step 1/2: PCA 3072 -> 50 dims ...")
    x50 = PCA(n_components=50, random_state=42).fit_transform(emb)
    print("step 2/2: t-SNE 50 -> 2 dims (takes about 1 to 3 minutes) ...")
    xy = TSNE(n_components=2, perplexity=30, init="pca", random_state=42).fit_transform(x50)

    build_html(codes, names, xy, "outputs/chroma_map.html")
    print("saved outputs/chroma_map.html")

    norm = emb / np.linalg.norm(emb, axis=1, keepdims=True)
    print("\nnearest neighbours (cosine) for a few foods:")
    for probe in ["Croissant", "Milk, whole", "Banana, raw", "Coffee, brewed"]:
        idx = [i for i, n in enumerate(names) if n == probe]
        if not idx:
            continue
        i = idx[0]
        sims = norm @ norm[i]
        order = np.argsort(-sims)[1:6]
        print(f"- {probe} ({codes[i]}):")
        for j in order:
            print(f"    {sims[j]:.3f}  {names[j]} ({codes[j]})")


if __name__ == "__main__":
    main()