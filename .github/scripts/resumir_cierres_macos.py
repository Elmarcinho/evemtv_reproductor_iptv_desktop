#!/usr/bin/env python3
"""Resume los informes de cierre de macOS (.ips) como anotaciones de GitHub.

Para diagnosticar fallos de las pruebas de integración en el runner de
macOS sin descargar artefactos: tipo de excepción, señal, motivo de
terminación y las primeras funciones del hilo que se cayó. Uso:
    python3 resumir_cierres_macos.py <carpeta con .ips> <log de la prueba>
"""
import glob
import json
import os
import sys


def anotar(nivel: str, titulo: str, texto: str) -> None:
    texto = texto.replace("%", "%25").replace("\r", "").replace("\n", "%0A")
    print(f"::{nivel} title={titulo}::{texto[:3500]}")


def resumir_ips(ruta: str) -> str:
    with open(ruta, encoding="utf-8", errors="replace") as f:
        cabecera = f.readline()
        cuerpo = f.read()
    try:
        meta = json.loads(cabecera)
        datos = json.loads(cuerpo)
    except json.JSONDecodeError:
        return f"{os.path.basename(ruta)}: formato no reconocido"
    exc = datos.get("exception", {})
    term = datos.get("termination", {})
    lineas = [
        f"{os.path.basename(ruta)} | proceso={meta.get('app_name') or datos.get('procName')}",
        f"excepción={exc.get('type')} señal={exc.get('signal')} "
        f"subtipo={exc.get('subtype', '')}",
        f"terminación={term.get('indicator', '')} {term.get('namespace', '')}",
    ]
    imagenes = datos.get("usedImages", [])
    hilo = next(
        (h for h in datos.get("threads", []) if h.get("triggered")), None
    )
    if hilo:
        lineas.append(f"hilo caído: {hilo.get('name') or hilo.get('queue', '')}")
        for marco in hilo.get("frames", [])[:15]:
            img = imagenes[marco.get("imageIndex", 0)] if imagenes else {}
            lineas.append(
                f"  {img.get('name', '?')} {marco.get('symbol', '?')}"
            )
    asercion = datos.get("asi") or datos.get("crashInfo")
    if asercion:
        lineas.append(f"mensaje: {json.dumps(asercion)[:600]}")
    return "\n".join(lineas)


def main() -> None:
    carpeta, log = sys.argv[1], sys.argv[2]
    informes = sorted(
        glob.glob(os.path.join(carpeta, "*.ips")), key=os.path.getmtime
    )
    if not informes:
        anotar(
            "warning",
            "macOS: sin informes de cierre",
            "No hubo informe de cierre: la app no se cayó (se colgó, "
            "se cerró sola o la mató el tiempo límite).",
        )
    for ruta in informes[-3:]:
        anotar("error", "macOS: informe de cierre", resumir_ips(ruta))
    gpu = os.path.join(carpeta, "gpu.txt")
    if os.path.exists(gpu):
        with open(gpu, encoding="utf-8", errors="replace") as f:
            anotar("warning", "macOS: GPU de la máquina", f.read())
    registro = os.path.join(carpeta, "registro_sistema.txt")
    if os.path.exists(registro):
        with open(registro, encoding="utf-8", errors="replace") as f:
            lineas = f.readlines()
        claves = ("terminat", "exit", "kill", "sandbox", "deny", "metal",
                  "gpu", "crash", "abort", "jetsam", "signal", "error")
        relevantes = [l for l in lineas if any(k in l.lower() for k in claves)]
        anotar(
            "error",
            "macOS: registro del sistema (relevante)",
            "".join(relevantes[-60:]) or "(sin líneas relevantes)",
        )
        anotar("warning", "macOS: registro del sistema (final)", "".join(lineas[-40:]))
    if os.path.exists(log):
        with open(log, encoding="utf-8", errors="replace") as f:
            ultimas = f.readlines()[-40:]
        anotar("error", "macOS: final de la salida de la prueba", "".join(ultimas))


if __name__ == "__main__":
    main()
