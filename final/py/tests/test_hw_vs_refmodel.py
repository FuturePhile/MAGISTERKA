# tests/test_hw_vs_refmodel.py
import csv, os, math
import pytest
from fuzzy_refmodel import DEFAULT_CFG, top_step

CSV = "hw_eval.csv"

@pytest.mark.skipif(not os.path.exists(CSV), reason="Run HDL sim to generate hw_eval.csv first")
def test_parity_mae_and_plateaus():
    rows = []
    with open(CSV, newline="") as f:
        rdr = csv.DictReader(f)
        for r in rdr:
            rows.append(r)

    assert rows, "No data in hw_eval.csv"

    mae = 0.0
    n = 0
    for r in rows:
        T   = int(r["T"]); dT = int(r["dT"])
        rm  = int(r["REG_MODE"]); dm = int(r["DT_MODE"])
        if dm != 0:  # compare only external dT path bit-exactly
            continue
        G_hw = int(r["G"])
        G_ref,_ = top_step(T, dT, DEFAULT_CFG, rm, 0, None)

        # Plateau cases are exact; others within ±1 due to rounding
        tol = 0 if (T==0 and dT==0) else 1
        assert abs(G_hw - G_ref) <= tol
        mae += abs(G_hw - G_ref)
        n += 1

    assert n >= 20
    mae /= max(n,1)
    # REQ-310: MAE ≤ 1% (scale 0..100) -> ≤ 1.0
    assert mae <= 1.0
