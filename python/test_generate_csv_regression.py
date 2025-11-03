# test_generate_csv_regression.py
# Generator CSV w formacie zgodnym z TB (odpala się tylko z --csv)
import csv
import random
import sys
import pytest

from fuzzy_refmodel import (
    DEFAULT_CFG, top_step, EstimatorRTLExact,
)

CSV_FIELDS = [
    "run_id","source","case_id","idx","reg_mode","dt_mode",
    "T_in","dT_in","alpha","k_dt",
    "Tneg_a","Tneg_b","Tneg_c","Tneg_d",
    "Tzero_a","Tzero_b","Tzero_c","Tzero_d",
    "Tpos_a","Tpos_b","Tpos_c","Tpos_d",
    "dTneg_a","dTneg_b","dTneg_c","dTneg_d",
    "dTzero_a","dTzero_b","dTzero_c","dTzero_d",
    "dTpos_a","dTpos_b","dTpos_c","dTpos_d",
    "S_w","S_wg","G_exp","G_impl","valid_impl",
    "tool_ver","git_rev","seed"
]

def pytest_addoption(parser):
    parser.addoption("--csv",      action="store", default=None, help="Ścieżka do CSV z wynikami")
    parser.addoption("--run-id",   action="store", default="py_run", help="run_id do CSV")
    parser.addoption("--git-rev",  action="store", default="", help="git rev do CSV")
    parser.addoption("--seed",     action="store", type=int, default=0, help="seed do Random bloku")

@pytest.fixture(scope="session")
def csv_ctx(request):
    path = request.config.getoption("--csv")
    if not path:
        pytest.skip("Pomijam generator CSV (brak --csv)")
    run_id  = request.config.getoption("--run-id")
    git_rev = request.config.getoption("--git-rev")
    seed    = request.config.getoption("--seed")

    f = open(path, "w", newline="")
    w = csv.DictWriter(f, fieldnames=CSV_FIELDS)
    w.writeheader()

    ctx = {"f": f, "w": w, "run_id": run_id, "git_rev": git_rev, "seed": seed}
    yield ctx
    f.close()

def _row_base(cfg, run_id, source, case_id, idx, reg_mode, dt_mode,
              T_in, dT_in, alpha, k_dt, S_w, S_wg, G_exp, G_impl, valid_impl,
              tool_ver, git_rev, seed):
    return {
        "run_id": run_id,
        "source": source,
        "case_id": case_id,
        "idx": idx,
        "reg_mode": reg_mode,
        "dt_mode": dt_mode,
        "T_in": T_in,
        "dT_in": dT_in,
        "alpha": alpha,
        "k_dt": k_dt,
        "Tneg_a": cfg.mf_T.neg.a,   "Tneg_b": cfg.mf_T.neg.b,   "Tneg_c": cfg.mf_T.neg.c,   "Tneg_d": cfg.mf_T.neg.d,
        "Tzero_a": cfg.mf_T.zero.a, "Tzero_b": cfg.mf_T.zero.b, "Tzero_c": cfg.mf_T.zero.c, "Tzero_d": cfg.mf_T.zero.d,
        "Tpos_a": cfg.mf_T.pos.a,   "Tpos_b": cfg.mf_T.pos.b,   "Tpos_c": cfg.mf_T.pos.c,   "Tpos_d": cfg.mf_T.pos.d,
        "dTneg_a": cfg.mf_dT.neg.a,   "dTneg_b": cfg.mf_dT.neg.b,   "dTneg_c": cfg.mf_dT.neg.c,   "dTneg_d": cfg.mf_dT.neg.d,
        "dTzero_a": cfg.mf_dT.zero.a, "dTzero_b": cfg.mf_dT.zero.b, "dTzero_c": cfg.mf_dT.zero.c, "dTzero_d": cfg.mf_dT.zero.d,
        "dTpos_a": cfg.mf_dT.pos.a,   "dTpos_b": cfg.mf_dT.pos.b,   "dTpos_c": cfg.mf_dT.pos.c,   "dTpos_d": cfg.mf_dT.pos.d,
        "S_w": S_w, "S_wg": S_wg, "G_exp": G_exp, "G_impl": G_impl, "valid_impl": valid_impl,
        "tool_ver": tool_ver, "git_rev": git_rev, "seed": seed,
    }

def test_generate_csv(csv_ctx):
    w       = csv_ctx["w"]
    run_id  = csv_ctx["run_id"]
    git_rev = csv_ctx["git_rev"]
    seed    = csv_ctx["seed"]
    toolver = f"Python {sys.version.split()[0]}/pytest {pytest.__version__}"
    source  = "py"
    cfg     = DEFAULT_CFG

    # ========== Block 1: DT_MODE=0 (Grid) ==========
    Ts  = [-128, -64, -32, -16, 0, 16, 32, 64, 96, 127]
    dTs = [-60, -30, -10, 0, 10, 30, 60]
    for reg_mode in (0,1):
        idx = 0
        for T_in in Ts:
            for dT_in in dTs:
                G, dbg = top_step(T_in, dT_in, cfg, reg_mode=reg_mode, dt_mode=0, estimator=None)
                row = _row_base(cfg, run_id, source, f"Grid_T={T_in}_dT={dT_in}", idx, reg_mode, 0,
                                T_in, dT_in, 32, 3, dbg["S_w"], dbg["S_wg"], G, G, 1,
                                toolver, git_rev, seed)
                w.writerow(row)
                idx += 1

    # ========== Block 2: DT_MODE=0 (Random) ==========
    random.seed(seed if seed else 0xC0FFEE)
    N = 1000
    for i in range(N):
        T_in  = random.randint(-128,127)
        dT_in = random.randint(-128,127)
        G, dbg = top_step(T_in, dT_in, cfg, reg_mode=1, dt_mode=0, estimator=None)
        row = _row_base(cfg, run_id, source, "Random", i, 1, 0,
                        T_in, dT_in, 32, 3, dbg["S_w"], dbg["S_wg"], G, G, 1,
                        toolver, git_rev, seed)
        w.writerow(row)

    # ========== Block 3: DT_MODE=1 (Estimator – logging) ==========
    est = EstimatorRTLExact(alpha=32, k_dt=3, d_max=64)
    est.init_pulse(0)
    # INIT: T=0
    T_in = 0
    G, dbg = top_step(T_in, 0, cfg, reg_mode=1, dt_mode=1, estimator=est)
    row = _row_base(cfg, run_id, source, "EST_INIT", 0, 1, 1,
                    T_in, 0, 32, 3, "", "", "", G, 1,
                    toolver, git_rev, seed)
    w.writerow(row)

    # Ramp up: 0 -> +40 step 2
    idx = 0
    for i in range(20):
        T_in = (i+1) * 2
        G, dbg = top_step(T_in, 0, cfg, reg_mode=1, dt_mode=1, estimator=est)
        row = _row_base(cfg, run_id, source, "EST_RampUp", idx, 1, 1,
                        T_in, 0, 32, 3, "", "", "", G, 1,
                        toolver, git_rev, seed)
        w.writerow(row); idx += 1

    # Ramp down: +40 -> 0
    idx = 0
    for i in range(20, -1, -1):
        T_in = i * 2
        G, dbg = top_step(T_in, 0, cfg, reg_mode=1, dt_mode=1, estimator=est)
        row = _row_base(cfg, run_id, source, "EST_RampDown", idx, 1, 1,
                        T_in, 0, 32, 3, "", "", "", G, 1,
                        toolver, git_rev, seed)
        w.writerow(row); idx += 1

    # Random walk (100 kroków, ±5)
    T = 0
    idx = 0
    for _ in range(100):
        step = random.randint(-5,5)
        T = max(-128, min(127, T + step))
        G, dbg = top_step(T, 0, cfg, reg_mode=1, dt_mode=1, estimator=est)
        row = _row_base(cfg, run_id, source, "EST_RandWalk", idx, 1, 1,
                        T, 0, 32, 3, "", "", "", G, 1,
                        toolver, git_rev, seed)
        w.writerow(row); idx += 1
