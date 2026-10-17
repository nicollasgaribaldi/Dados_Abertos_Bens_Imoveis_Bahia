"""Ingestão: repara o JSON bruto de bens imóveis da Bahia e gera a camada landing.

O arquivo publicado em dados.ba.gov.br não é JSON válido. Este script corrige
apenas a SINTAXE (sem regra de negócio) e grava arquivos novos, mantendo o
original intocado como camada raw:

    raw      db_bensimoveis_ba/imoveisproprios.json        (não é alterado)
    landing  data/processed/imoveisproprios_reparado.json  (JSON válido)
             data/processed/imoveis.csv                    (UTF-8, ';', entrada do Pentaho)
             data/processed/relatorio_reparo.json          (o que foi corrigido)

Defeitos corrigidos:
    1. BOM UTF-8 no início do arquivo;
    2. vírgula faltando entre "Exercicio":<ano> e "Municipio";
    3. vírgula sobrando antes de "}" no fim de cada objeto;
    4. campo sem valor ("Dimensoes":,) -> null.

Uso (da raiz do repositório):
    python ingestion/reparar_json.py
"""
import csv
import hashlib
import json
import re
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[1]
ORIGEM = RAIZ / "db_bensimoveis_ba" / "imoveisproprios.json"
DESTINO = RAIZ / "data" / "processed"
CAMPOS = ["NumeroPatrimonio", "Exercicio", "Endereco", "Municipio",
          "OrgaoGestor", "Destino", "Valor", "Dimensoes"]

# Cada regra: (descrição, regex, substituição). Os padrões são ancorados na
# estrutura dos objetos para não alterar o conteúdo dos textos.
REGRAS = [
    ("virgula_faltando_apos_exercicio", re.compile(r'("Exercicio":-?\d+)"'), r'\1,"'),
    ("virgula_sobrando_antes_de_chave", re.compile(r',\}(?=\s*(?:,\s*\{|\]))'), "}"),
    ("valor_vazio_para_null", re.compile(r'("[A-Za-z]+"):(?=\s*[,}])'), r"\1:null"),
]


def sha256(caminho: Path) -> str:
    h = hashlib.sha256()
    with open(caminho, "rb") as f:
        for bloco in iter(lambda: f.read(1 << 20), b""):
            h.update(bloco)
    return h.hexdigest()


def reparar(texto: str) -> tuple[str, dict]:
    contagens = {}
    for nome, padrao, troca in REGRAS:
        texto, n = padrao.subn(troca, texto)
        contagens[nome] = n
    return texto, contagens


def main() -> int:
    hash_antes = sha256(ORIGEM)
    bruto = ORIGEM.read_bytes()
    tinha_bom = bruto.startswith(b"\xef\xbb\xbf")
    texto = bruto.decode("utf-8-sig")
    registros_brutos = texto.count('{"Endereco"')

    texto, contagens = reparar(texto)
    dados = json.loads(texto)  # falha aqui se ainda houver JSON inválido

    # Validações: nada se perdeu e todo registro tem as 8 chaves
    assert len(dados) == registros_brutos, (len(dados), registros_brutos)
    for i, reg in enumerate(dados):
        if set(reg) != set(CAMPOS):
            raise ValueError(f"registro {i} com chaves inesperadas: {sorted(reg)}")

    DESTINO.mkdir(parents=True, exist_ok=True)
    (DESTINO / "imoveisproprios_reparado.json").write_text(
        json.dumps(dados, ensure_ascii=False), encoding="utf-8")

    with open(DESTINO / "imoveis.csv", "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=CAMPOS, delimiter=";", quoting=csv.QUOTE_MINIMAL)
        w.writeheader()
        for reg in dados:
            w.writerow({k: ("" if reg[k] is None else reg[k]) for k in CAMPOS})

    assert sha256(ORIGEM) == hash_antes, "o arquivo raw foi alterado!"
    relatorio = {
        "arquivo_raw": str(ORIGEM.relative_to(RAIZ)).replace("\\", "/"),
        "sha256_raw": hash_antes,
        "bom_removido": tinha_bom,
        "correcoes": contagens,
        "registros": len(dados),
    }
    (DESTINO / "relatorio_reparo.json").write_text(
        json.dumps(relatorio, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(relatorio, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
