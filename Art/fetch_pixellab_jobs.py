#!/usr/bin/env python3
"""Télécharge les images d'animations PixelLab (animate_image) à partir de leurs numéros de job.

Usage : /usr/bin/python3 Art/fetch_pixellab_jobs.py <dossier> nom/anim=job_id:frames ...
Écrit <dossier>/<nom>/<anim>/f<N>.png (f0 = image de départ), et attend les jobs encore en cours.
"""
import os, sys, time, urllib.request, urllib.error

def get(job, index):
    url = f"https://api.pixellab.ai/mcp/images/{job}/download?index={index}&inline=true"
    for _ in range(60):
        try:
            with urllib.request.urlopen(url, timeout=60) as r:
                return r.read()
        except urllib.error.HTTPError as e:
            if e.code == 423:
                time.sleep(8); continue
            if e.code in (404, 400, 416): return None
            raise
    return None

out = sys.argv[1]
for spec in sys.argv[2:]:
    path, rest = spec.split("=")
    job, n = rest.split(":")
    folder = os.path.join(out, path)
    os.makedirs(folder, exist_ok=True)
    got = 0
    for i in range(int(n) + 1):
        data = get(job, i)
        if not data or data[:4] != b"\x89PNG": break
        open(os.path.join(folder, f"f{i}.png"), "wb").write(data); got += 1
    print(path, got, "images")
