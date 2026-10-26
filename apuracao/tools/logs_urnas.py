#!/usr/bin/env python3
"""Processa os logs das urnas publicados pelo TSE e gera resumos de votos por horário.

  python3 logs_urnas.py uf rj            -> saida/rj.json   (um estado)
  python3 logs_urnas.py juntar saida     -> saida/brasil.json (junta os estados)

Cada linha "O voto do eleitor foi computado" do logd.dat (dentro do -log.jez) é um voto.
O log usa o horário local da urna; como a votação abre às 8h de Brasília, a hora do
primeiro voto mais comum entre as urnas de cada município revela o fuso local.
Os votos são somados em faixas de 5 minutos no horário de Brasília (288 faixas no dia).
"""
import io, json, sys, time, zipfile, urllib.request, urllib.error
from array import array
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone, timedelta

BASE = "https://resultados.tse.jus.br/oficial"
CICLO, PLEITO, DIA = "ele2026", 3221, b"25/10/2026"
VOTO = b"O voto do eleitor foi computado"
NB = 288  # faixas de 5 minutos
FUSO_UF = {"ac": 2, "am": 1, "rr": 1, "ro": 1, "mt": 1, "ms": 1}
BRT = timezone(timedelta(hours=-3))


def get(url, tentativas=6):
    erro = None
    for i in range(tentativas):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "apuracao-logs/1.0"})
            with urllib.request.urlopen(req, timeout=90) as r:
                return r.read()
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return None
            erro = e
        except Exception as e:
            erro = e
        time.sleep(min(60, 2 ** i))
    raise RuntimeError(f"{url}: {erro}")


def logs_do_jez(z, prof=0):
    for nome in z.namelist():
        if nome.endswith(".dat"):
            yield z.read(nome)
        elif nome.endswith(".jez") and prof < 2:
            with zipfile.ZipFile(io.BytesIO(z.read(nome))) as interno:
                yield from logs_do_jez(interno, prof + 1)


def seg(l):
    return int(l[11:13]) * 3600 + int(l[14:16]) * 60 + int(l[17:19])


def secao(uf, mun, zona, sec):
    pasta = f"{BASE}/{CICLO}/arquivo-urna/{PLEITO}/dados/{uf}/{mun}/{zona}/{sec}"
    aux = get(f"{pasta}/p{PLEITO:06d}-{uf}-m{mun}-z{zona}-s{sec}-aux.json")
    if aux is None:
        return None
    hs = json.loads(aux).get("hashes", [])
    h = next((x for x in hs if x.get("st") == "Totalizado"), hs[-1] if hs else None)
    arq = h and next((a for a in h.get("arq", []) if a.get("tp") == "log" or a.get("nm", "").endswith("-log.jez")), None)
    if not arq:
        return {"semlog": True}
    dados = get(f"{pasta}/{h['hash']}/{arq['nm']}")
    if dados is None:
        return {"semlog": True}
    linhas = set()
    with zipfile.ZipFile(io.BytesIO(dados)) as z:
        for conteudo in logs_do_jez(z):
            for l in conteudo.split(b"\n"):
                if l.startswith(DIA) and VOTO in l:
                    linhas.add(l.rstrip(b"\r"))
    votos = sorted(seg(l) for l in linhas)
    hist = array("H", [0]) * NB
    for v in votos:
        hist[v // 300] += 1
    return {"hist": hist, "n": len(votos), "pri": votos[0] if votos else None, "ult": votos[-1] if votos else None,
            "bytes": len(dados)}


def faz_uf(uf, saida, parte=1, partes=1):
    cs = get(f"{BASE}/{CICLO}/arquivo-urna/{PLEITO}/config/{uf}/{uf}-p{PLEITO:06d}-cs.json")
    if cs is None:
        print(f"[{uf}] lista de seções não publicada"); return
    cs = json.loads(cs)
    tarefas, nomes = [], {}
    for abr in cs["abr"]:
        for mu in abr["mu"]:
            nomes[mu["cd"]] = mu.get("nm") or mu["cd"]
            for z in mu["zon"]:
                for s in z["sec"]:
                    tarefas.append((mu["cd"], z["cd"], s["ns"]))
    if partes > 1:  # divide por município para não separar o cálculo do fuso
        tarefas = [t for t in tarefas if int(t[0]) % partes == parte - 1]
    print(f"[{uf}] parte {parte}/{partes}: {len(tarefas)} seções", flush=True)
    res, erros, feitos = {}, 0, 0
    def um(t):
        try:
            return t, secao(uf, *t)
        except Exception as e:
            return t, {"erro": str(e)}
    with ThreadPoolExecutor(32) as ex:
        for t, r in ex.map(um, tarefas):
            feitos += 1
            if r and "erro" in r:
                erros += 1
            res[t] = r
            if feitos % 2000 == 0:
                print(f"  {feitos}/{len(tarefas)}", flush=True)
    # fuso por município: hora mais comum do primeiro voto
    prim = {}
    for (mun, _, _), r in res.items():
        if r and r.get("pri") is not None:
            prim.setdefault(mun, Counter())[r["pri"] // 3600] += 1
    muns = {}
    total_bytes = 0
    for (mun, zona, sec), r in res.items():
        m = muns.setdefault(mun, {"cd": mun, "nm": nomes.get(mun, mun), "secoes": 0, "urnas": 0, "semlog": 0,
                                  "erros": 0, "votos": 0, "pos17": 0, "urnasPos17": 0, "ult": None, "ultSec": None,
                                  "bins": [0] * NB})
        m["secoes"] += 1
        if r is None or r.get("semlog"):
            m["semlog"] += 1; continue
        if "erro" in r:
            m["erros"] += 1; continue
        total_bytes += r["bytes"]
        c = prim.get(mun)
        fuso = max(-1, min(3, 8 - c.most_common(1)[0][0])) if c else FUSO_UF.get(uf, 0)
        m["fuso"] = fuso
        m["urnas"] += 1
        m["votos"] += r["n"]
        k = fuso * 12
        p17 = 0
        for i, q in enumerate(r["hist"]):
            if q:
                j = min(NB - 1, max(0, i + k))
                m["bins"][j] += q
                if j >= 17 * 12:
                    p17 += q
        m["pos17"] += p17
        m["urnasPos17"] += p17 > 0
        if r["ult"] is not None:
            u = r["ult"] + fuso * 3600
            if m["ult"] is None or u > m["ult"]:
                m["ult"], m["ultSec"] = u, f"{int(zona)}/{int(sec)}"
    out = {"uf": uf.upper(), "gerado": datetime.now(BRT).strftime("%d/%m/%Y %H:%M"), "dia": DIA.decode(),
           "secoes": len(tarefas), "erros": erros, "bytes": total_bytes,
           "municipios": sorted(muns.values(), key=lambda m: m["nm"])}
    nome = uf if partes == 1 else f"{uf}-parte{parte}"
    with open(f"{saida}/{nome}.json", "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, separators=(",", ":"))
    print(f"[{uf}] ok: {sum(m['votos'] for m in muns.values())} votos, {sum(m['pos17'] for m in muns.values())} após 17h, {erros} erros")


def juntar(pasta):
    import glob, os
    grupos = {}
    for p in sorted(glob.glob(f"{pasta}/*.json")):
        b = os.path.basename(p)
        if b == "brasil.json":
            continue
        grupos.setdefault(b.split("-parte")[0].replace(".json", ""), []).append(p)
    ufs = []
    for uf, arqs in sorted(grupos.items()):
        partes = [json.load(open(a, encoding="utf-8")) for a in arqs]
        d = {"uf": uf.upper(), "gerado": max(x["gerado"] for x in partes), "secoes": sum(x["secoes"] for x in partes),
             "erros": sum(x["erros"] for x in partes), "bytes": sum(x.get("bytes", 0) for x in partes),
             "municipios": sorted((m for x in partes for m in x["municipios"]), key=lambda m: m["nm"])}
        if len(arqs) > 1:
            with open(f"{pasta}/{uf}.json", "w", encoding="utf-8") as f:
                json.dump(d, f, ensure_ascii=False, separators=(",", ":"))
            for a in arqs:
                if "-parte" in a:
                    os.remove(a)
        ms = d["municipios"]
        s = lambda k: sum(m[k] for m in ms)
        bins = [sum(m["bins"][i] for m in ms) for i in range(NB)]
        ult = max((m for m in ms if m["ult"] is not None), key=lambda m: m["ult"], default=None)
        ufs.append({"uf": d["uf"], "secoes": d["secoes"], "urnas": s("urnas"), "semlog": s("semlog"), "erros": s("erros"),
                    "votos": s("votos"), "pos17": s("pos17"), "urnasPos17": s("urnasPos17"),
                    "ult": ult and ult["ult"], "ultLocal": ult and f"{ult['nm']} · seção {ult['ultSec']}", "bins": bins,
                    "gerado": d["gerado"], "bytes": d.get("bytes", 0)})
    tot = {k: sum(u[k] for u in ufs) for k in ("secoes", "urnas", "semlog", "erros", "votos", "pos17", "urnasPos17", "bytes")}
    tot["bins"] = [sum(u["bins"][i] for u in ufs) for i in range(NB)]
    todas = "ac al am ap ba ce df es go ma mg ms mt pa pb pe pi pr rj rn ro rr rs sc se sp to".upper().split()
    faltam = [u for u in todas if u not in {x["uf"] for x in ufs}]
    out = {"gerado": datetime.now(BRT).strftime("%d/%m/%Y %H:%M"), "dia": DIA.decode(), "total": tot, "ufs": ufs, "faltam": faltam}
    with open(f"{pasta}/brasil.json", "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, separators=(",", ":"))
    print(f"Brasil: {tot['votos']} votos, {tot['pos17']} após 17h, {len(ufs)} UFs")


if __name__ == "__main__":
    if sys.argv[1] == "uf":
        import os
        os.makedirs(sys.argv[3] if len(sys.argv) > 3 else "saida", exist_ok=True)
        pa = sys.argv[4].split("/") if len(sys.argv) > 4 else ["1", "1"]
        faz_uf(sys.argv[2].lower(), sys.argv[3] if len(sys.argv) > 3 else "saida", int(pa[0]), int(pa[1]))
    else:
        juntar(sys.argv[2])
