# conftest.py — rejestracja własnych opcji CLI i wygodne fixture'y

import os
import pathlib
import random
import pytest

def pytest_addoption(parser: pytest.Parser):
    group = parser.getgroup("csv-meta")
    group.addoption("--csv", action="store", default="", help="Ścieżka do CSV z wynikami")
    group.addoption("--run-id", action="store", default="py_run", help="Identyfikator uruchomienia")
    group.addoption("--git-rev", action="store", default="", help="Commit / wersja kodu")
    group.addoption("--seed", action="store", type=int, default=0, help="Seed RNG (0 = brak)")

@pytest.fixture(scope="session")
def cli_opts(request: pytest.FixtureRequest):
    """Zwraca słownik z wartościami flag i przygotowuje RNG oraz katalog na wyniki."""
    csv_path = request.config.getoption("--csv") or "results/py.csv"
    run_id   = request.config.getoption("--run-id")
    git_rev  = request.config.getoption("--git-rev")
    seed     = request.config.getoption("--seed")

    # Utwórz katalog docelowy na CSV
    out_dir = pathlib.Path(csv_path).expanduser().resolve().parent
    out_dir.mkdir(parents=True, exist_ok=True)

    # Ustaw seed jeśli podano
    if seed and isinstance(seed, int):
        random.seed(seed)

    return {
        "csv": str(pathlib.Path(csv_path)),
        "run_id": run_id,
        "git_rev": git_rev,
        "seed": seed,
    }

@pytest.fixture
def csv_writer(cli_opts):
    """Prosty 'writer': otwiera plik, dokłada nagłówek jeśli pusty, zwraca funkcję emitującą wiersze."""
    path = cli_opts["csv"]
    # Jeśli plik nie istnieje albo pusty → nagłówek
    need_header = (not os.path.exists(path)) or (os.path.getsize(path) == 0)

    f = open(path, "a", newline="", encoding="utf-8")

    if need_header:
        f.write(
            "run_id,source,case_id,idx,reg_mode,dt_mode,"
            "T_in,dT_in,alpha,k_dt,"
            "Tneg_a,Tneg_b,Tneg_c,Tneg_d,"
            "Tzero_a,Tzero_b,Tzero_c,Tzero_d,"
            "Tpos_a,Tpos_b,Tpos_c,Tpos_d,"
            "dTneg_a,dTneg_b,dTneg_c,dTneg_d,"
            "dTzero_a,dTzero_b,dTzero_c,dTzero_d,"
            "dTpos_a,dTpos_b,dTpos_c,dTpos_d,"
            "S_w,S_wg,G_exp,G_impl,valid_impl,"
            "tool_ver,git_rev,seed\n"
        )
        f.flush()

    def emit(**row):
        # 'row' podaj po nazwach z nagłówka (albo minimalny podzbiór)
        fields = [
            row.get("run_id",""), row.get("source","py"), row.get("case_id",""), row.get("idx",0),
            row.get("reg_mode",0), row.get("dt_mode",0),
            row.get("T_in",0), row.get("dT_in",0), row.get("alpha",0), row.get("k_dt",0),
            row.get("Tneg_a",-128), row.get("Tneg_b",-64), row.get("Tneg_c",-32), row.get("Tneg_d",0),
            row.get("Tzero_a",-16), row.get("Tzero_b",0), row.get("Tzero_c",0), row.get("Tzero_d",16),
            row.get("Tpos_a",0), row.get("Tpos_b",32), row.get("Tpos_c",64), row.get("Tpos_d",127),
            row.get("dTneg_a",-100), row.get("dTneg_b",-50), row.get("dTneg_c",-30), row.get("dTneg_d",-5),
            row.get("dTzero_a",-10), row.get("dTzero_b",0), row.get("dTzero_c",0), row.get("dTzero_d",10),
            row.get("dTpos_a",5), row.get("dTpos_b",25), row.get("dTpos_c",35), row.get("dTpos_d",60),
            row.get("S_w",-1), row.get("S_wg",-1), row.get("G_exp",-1), row.get("G_impl",-1), int(bool(row.get("valid_impl",0))),
            row.get("tool_ver","pytest"), row.get("git_rev",""), row.get("seed",0),
        ]
        line = ",".join(str(x) for x in fields) + "\n"
        f.write(line)

    yield emit
    f.close()
