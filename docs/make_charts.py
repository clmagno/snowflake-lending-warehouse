"""Render the README charts from the marts in data/lending.duckdb.

Run after `dbt build --target dev`:
    python docs/make_charts.py
"""

from pathlib import Path

import duckdb
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
from matplotlib.ticker import PercentFormatter  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
DB = ROOT / "data" / "lending.duckdb"
OUT = ROOT / "docs"

SURFACE = "#fcfcfb"
TEXT = "#0b0b0b"
TEXT_2 = "#52514e"
GRID = "#e6e5e1"
SERIES = ["#2a78d6", "#eb6834", "#1baf7a", "#eda100"]  # validated categorical order

plt.rcParams.update(
    {
        "figure.facecolor": SURFACE,
        "axes.facecolor": SURFACE,
        "axes.edgecolor": GRID,
        "axes.labelcolor": TEXT_2,
        "xtick.color": TEXT_2,
        "ytick.color": TEXT_2,
        "text.color": TEXT,
        "font.size": 10,
        "axes.spines.top": False,
        "axes.spines.right": False,
        "axes.grid": True,
        "grid.color": GRID,
        "grid.linewidth": 0.8,
    }
)


def end_label(ax, x, y, text, color):
    ax.plot([x], [y], "o", color=color, markersize=5, markeredgecolor=SURFACE, markeredgewidth=1.5)
    ax.annotate(text, (x, y), xytext=(8, 0), textcoords="offset points", va="center", color=TEXT, fontsize=9)


def arrears_trend(con) -> None:
    df = con.sql(
        """
        select snapshot_month, product_family, pct_loans_30_plus_dpd
        from marts.mart_portfolio_monthly
        where snapshot_month >= '2023-01-01'
        order by 1
        """
    ).df()
    labels = {"HOME_LOAN": "Home loans", "PERSONAL_LOAN": "Personal loans", "CAR_LOAN": "Car loans"}
    fig, ax = plt.subplots(figsize=(9, 4.4))
    for color, (family, name) in zip(SERIES, labels.items(), strict=False):
        s = df[df.product_family == family]
        ax.plot(s.snapshot_month, s.pct_loans_30_plus_dpd, color=color, linewidth=2)
        last = s.iloc[-1]
        rate = last.pct_loans_30_plus_dpd
        end_label(ax, last.snapshot_month, rate, f"{name} {rate:.1%}", color)
    ax.yaxis.set_major_formatter(PercentFormatter(1.0, decimals=1))
    ax.set_ylim(bottom=0)
    ax.set_title("Share of active loans 30+ days past due, by product", loc="left", fontsize=12, fontweight="bold")
    ax.margins(x=0.02)
    ax.set_xlim(right=ax.get_xlim()[1] + 120)
    fig.text(0.01, 0.01, "Source: marts.mart_portfolio_monthly (synthetic data)", color=TEXT_2, fontsize=8)
    fig.tight_layout(rect=(0, 0.03, 1, 1))
    fig.savefig(OUT / "arrears_trend.png", dpi=150)
    plt.close(fig)


def vintage_curves(con) -> None:
    df = con.sql(
        """
        select year(origination_quarter) as cohort, months_on_book,
               sum(loans_ever_90_plus) * 1.0 / sum(loans_observed) as rate,
               sum(loans_observed) as n
        from marts.mart_vintage_curves
        where months_on_book between 1 and 36
        group by 1, 2
        order by 1, 2
        """
    ).df()
    cohorts = [2022, 2023, 2024]  # 2025 loans are too young to show 90+ arrears yet
    fig, ax = plt.subplots(figsize=(9, 4.4))
    for color, cohort in zip(SERIES, cohorts, strict=False):
        s = df[df.cohort == cohort]
        # only plot months where the whole cohort has been observed
        full = s[s.n >= s.n.max() * 0.98]
        ax.plot(full.months_on_book, full.rate, color=color, linewidth=2)
        last = full.iloc[-1]
        end_label(ax, last.months_on_book, last.rate, f"{cohort} loans", color)
    ax.yaxis.set_major_formatter(PercentFormatter(1.0, decimals=1))
    ax.set_ylim(bottom=0)
    ax.set_xlabel("Months on book")
    ax.set_title("Vintage curves: share of loans ever 90+ days past due", loc="left", fontsize=12, fontweight="bold")
    ax.set_xlim(0, 41)
    fig.text(0.01, 0.01, "Source: marts.mart_vintage_curves, all products (synthetic data)", color=TEXT_2, fontsize=8)
    fig.tight_layout(rect=(0, 0.03, 1, 1))
    fig.savefig(OUT / "vintage_curves.png", dpi=150)
    plt.close(fig)


if __name__ == "__main__":
    con = duckdb.connect(str(DB), read_only=True)
    arrears_trend(con)
    vintage_curves(con)
    print("wrote docs/arrears_trend.png and docs/vintage_curves.png")
