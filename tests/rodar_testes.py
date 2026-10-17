"""Roda os testes de qualidade do pipeline e imprime um relatório.

1. Raw x landing: o número de registros do relatório de reparo bate com a staging.
2. Testes SQL de tests/testes_qualidade.sql: "teste" deve retornar 0 linhas;
   "alerta" é um problema conhecido da fonte e só tem a contagem reportada.

Uso (da raiz do repositório, com o banco no ar e o pipeline já executado):
    python tests/rodar_testes.py
Sai com código 1 se algum teste falhar.
"""
import json
import re
import sys
from pathlib import Path

import psycopg2

RAIZ = Path(__file__).resolve().parents[1]


def ler_env() -> dict:
    cfg = {}
    for linha in (RAIZ / ".env").read_text(encoding="utf-8").splitlines():
        if "=" in linha and not linha.lstrip().startswith("#"):
            k, v = linha.split("=", 1)
            cfg[k.strip()] = v.strip()
    return cfg


def conectar():
    c = ler_env()
    return psycopg2.connect(host=c.get("POSTGRES_HOST", "localhost"), port=c.get("POSTGRES_PORT", "5437"),
                            dbname=c["POSTGRES_DB"], user=c["POSTGRES_USER"], password=c["POSTGRES_PASSWORD"])


def testes_sql():
    texto = (RAIZ / "tests" / "testes_qualidade.sql").read_text(encoding="utf-8")
    partes = re.split(r"^-- (teste|alerta): ", texto, flags=re.M)[1:]
    for tipo, bloco in zip(partes[0::2], partes[1::2]):
        nome, sql = bloco.split("\n", 1)
        yield tipo, nome.strip(), sql.strip().rstrip(";")


def main() -> int:
    falhas = 0
    with conectar() as conn, conn.cursor() as cur:
        relatorio = json.loads((RAIZ / "data" / "processed" / "relatorio_reparo.json").read_text(encoding="utf-8"))
        cur.execute("SELECT count(*) FROM stg.bens_imoveis")
        n_stg = cur.fetchone()[0]
        ok = n_stg == relatorio["registros"]
        falhas += not ok
        print(f"[{'OK' if ok else 'FALHOU'}] raw_igual_staging  (raw={relatorio['registros']}, stg={n_stg})")

        alertas = []
        for tipo, nome, sql in testes_sql():
            cur.execute(sql)
            linhas = cur.fetchall()
            if tipo == "alerta":
                alertas.append(f"[ALERTA] {nome}: {len(linhas)} linha(s)")
                continue
            ok = len(linhas) == 0
            falhas += not ok
            print(f"[{'OK' if ok else 'FALHOU'}] {nome}" + ("" if ok else f"  -> {len(linhas)} linha(s), ex.: {linhas[:3]}"))

        print("\nAlertas da fonte (tratados com flags, não bloqueiam):")
        print("\n".join(alertas))

    total = 1 + sum(1 for t in testes_sql() if t[0] == "teste")
    print(f"\n{total - falhas}/{total} testes de integridade aprovados")
    return 1 if falhas else 0


if __name__ == "__main__":
    sys.exit(main())
