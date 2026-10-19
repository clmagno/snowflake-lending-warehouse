"""Generate a synthetic consumer-lending dataset.

Produces three raw feeds that look like what a lender's core banking system
would export each day:

* borrowers.csv          - one row per customer (contains PII columns)
* loans.csv              - one row per loan account
* payments/payments_YYYY_MM.csv - repayments, partitioned by month

Borrower behaviour is driven by credit score, so delinquency, catch-up
payments, prepayments and defaults all appear in realistic proportions.
The feed also contains a small share of duplicate payment records (the
same payment_id re-sent by the source system), which the warehouse has to
de-duplicate.

Everything is seeded, so the same arguments always produce the same data.

Usage:
    python data_generator/generate.py --borrowers 5000 --out data/raw
"""

from __future__ import annotations

import argparse
import csv
import random
from collections import defaultdict
from dataclasses import dataclass
from datetime import date, datetime, timedelta
from pathlib import Path

from faker import Faker

AS_OF = date(2026, 9, 30)
FIRST_ORIGINATION = date(2022, 1, 1)
LAST_ORIGINATION = date(2026, 8, 31)

# product -> (min principal, max principal, terms in months, base annual rate)
PRODUCTS = {
    "HOME_LOAN_VARIABLE": (250_000, 1_200_000, [300, 360], 0.0619),
    "HOME_LOAN_FIXED": (250_000, 1_000_000, [300, 360], 0.0589),
    "PERSONAL_LOAN": (5_000, 50_000, [36, 60], 0.1149),
    "CAR_LOAN": (15_000, 90_000, [48, 60], 0.0899),
}
PRODUCT_WEIGHTS = [0.35, 0.20, 0.25, 0.20]
REGIONS = ["NSW", "VIC", "QLD", "WA", "SA", "TAS", "ACT", "NT"]
REGION_WEIGHTS = [0.31, 0.26, 0.20, 0.10, 0.07, 0.02, 0.02, 0.02]
EMPLOYMENT = ["FULL_TIME", "PART_TIME", "SELF_EMPLOYED", "CASUAL"]
EMPLOYMENT_WEIGHTS = [0.62, 0.14, 0.16, 0.08]
CHANNELS = ["BROKER", "DIRECT", "ONLINE"]
CHANNEL_WEIGHTS = [0.55, 0.25, 0.20]
PAYMENT_METHODS = ["DIRECT_DEBIT", "BPAY", "BANK_TRANSFER"]
PAYMENT_METHOD_WEIGHTS = [0.78, 0.12, 0.10]

DUPLICATE_RATE = 0.004


@dataclass
class Loan:
    loan_id: str
    borrower_id: str
    product: str
    principal: float
    interest_rate: float
    term_months: int
    origination_date: date
    channel: str
    credit_score: int


def add_months(d: date, months: int) -> date:
    month_index = d.month - 1 + months
    year = d.year + month_index // 12
    month = month_index % 12 + 1
    # clamp the day to the length of the target month
    for day in (d.day, 30, 29, 28):
        try:
            return date(year, month, day)
        except ValueError:
            continue
    raise ValueError(d)


def random_date(rng: random.Random, start: date, end: date) -> date:
    return start + timedelta(days=rng.randint(0, (end - start).days))


def installment(principal: float, annual_rate: float, term: int) -> float:
    r = annual_rate / 12
    return round(principal * r / (1 - (1 + r) ** -term), 2)


def make_borrowers(rng: random.Random, fake: Faker, n: int) -> list[dict]:
    borrowers = []
    for i in range(1, n + 1):
        first, last = fake.first_name(), fake.last_name()
        score = int(min(1000, max(300, rng.gauss(720, 110))))
        borrowers.append(
            {
                "borrower_id": f"B{i:07d}",
                "first_name": first,
                "last_name": last,
                "email": f"{first}.{last}{rng.randint(1, 999)}@example.com".lower(),
                "date_of_birth": random_date(rng, date(1955, 1, 1), date(2002, 12, 31)).isoformat(),
                "region": rng.choices(REGIONS, REGION_WEIGHTS)[0],
                "employment_type": rng.choices(EMPLOYMENT, EMPLOYMENT_WEIGHTS)[0],
                "annual_income": round(max(35_000, rng.gauss(115_000, 45_000)), -2),
                "credit_score": score,
                "created_at": None,  # filled in from the first loan
            }
        )
    return borrowers


def make_loans(rng: random.Random, borrowers: list[dict]) -> list[Loan]:
    loans = []
    seq = 0
    for b in borrowers:
        n_loans = rng.choices([1, 2, 3], [0.82, 0.15, 0.03])[0]
        first_date = None
        for _ in range(n_loans):
            seq += 1
            product = rng.choices(list(PRODUCTS), PRODUCT_WEIGHTS)[0]
            lo, hi, terms, base_rate = PRODUCTS[product]
            # weaker credit pays a higher rate
            risk_margin = max(0.0, (750 - b["credit_score"]) / 100) * 0.012
            orig = random_date(rng, FIRST_ORIGINATION, LAST_ORIGINATION)
            first_date = min(first_date or orig, orig)
            loans.append(
                Loan(
                    loan_id=f"L{seq:08d}",
                    borrower_id=b["borrower_id"],
                    product=product,
                    principal=round(rng.uniform(lo, hi), -2),
                    interest_rate=round(base_rate + risk_margin + rng.uniform(-0.004, 0.004), 4),
                    term_months=rng.choice(terms),
                    origination_date=orig,
                    channel=rng.choices(CHANNELS, CHANNEL_WEIGHTS)[0],
                    credit_score=b["credit_score"],
                )
            )
        signup = first_date - timedelta(days=rng.randint(1, 30))
        b["created_at"] = datetime.combine(signup, datetime.min.time()).isoformat()
    return loans


def borrower_profile(rng: random.Random, credit_score: int) -> tuple[float, float, int | None]:
    """Return (miss probability per month, prepay probability, default month or None)."""
    if credit_score >= 800:
        miss, prepay, default_p = 0.004, 0.05, 0.001
    elif credit_score >= 700:
        miss, prepay, default_p = 0.015, 0.03, 0.006
    elif credit_score >= 600:
        miss, prepay, default_p = 0.045, 0.015, 0.03
    else:
        miss, prepay, default_p = 0.10, 0.005, 0.09
    default_month = rng.randint(4, 30) if rng.random() < default_p else None
    return miss, prepay, default_month


def make_payments(rng: random.Random, loans: list[Loan]) -> list[dict]:
    payments = []
    seq = 0

    def emit(loan: Loan, paid_on: date, amount: float) -> None:
        nonlocal seq
        if paid_on > AS_OF:
            return
        seq += 1
        row = {
            "payment_id": f"P{seq:09d}",
            "loan_id": loan.loan_id,
            "payment_date": paid_on.isoformat(),
            "amount": round(amount, 2),
            "payment_method": rng.choices(PAYMENT_METHODS, PAYMENT_METHOD_WEIGHTS)[0],
            "source_extracted_at": datetime.combine(paid_on + timedelta(days=1), datetime.min.time())
            .replace(hour=2)
            .isoformat(),
        }
        payments.append(row)
        if rng.random() < DUPLICATE_RATE:
            # the source system re-sends the same payment in a later extract
            dup = dict(row)
            dup["source_extracted_at"] = (
                datetime.fromisoformat(row["source_extracted_at"]) + timedelta(days=rng.randint(1, 5))
            ).isoformat()
            payments.append(dup)

    for loan in loans:
        due_amount = installment(loan.principal, loan.interest_rate, loan.term_months)
        miss_p, prepay_p, default_month = borrower_profile(rng, loan.credit_score)
        owed_catch_up = 0.0
        for k in range(1, loan.term_months + 1):
            due = add_months(loan.origination_date, k)
            if due > AS_OF:
                break
            if default_month and k >= default_month:
                break  # borrower stops paying
            if rng.random() < miss_p:
                owed_catch_up += due_amount
                continue
            amount = due_amount
            offset = rng.choices([rng.randint(-3, 2), rng.randint(3, 12), rng.randint(13, 40)], [0.9, 0.08, 0.02])[0]
            if owed_catch_up and rng.random() < 0.6:
                amount += owed_catch_up  # catches up on missed instalments
                owed_catch_up = 0.0
            emit(loan, due + timedelta(days=offset), amount)
            if rng.random() < prepay_p:
                emit(loan, due + timedelta(days=rng.randint(5, 20)), round(due_amount * rng.uniform(0.5, 3), 2))
    return payments


def write_csv(path: Path, rows: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--borrowers", type=int, default=5000, help="number of borrowers to generate")
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--out", type=Path, default=Path("data/raw"))
    args = parser.parse_args()

    rng = random.Random(args.seed)
    fake = Faker("en_AU")
    fake.seed_instance(args.seed)

    borrowers = make_borrowers(rng, fake, args.borrowers)
    loans = make_loans(rng, borrowers)
    payments = make_payments(rng, loans)

    write_csv(args.out / "borrowers.csv", borrowers)
    write_csv(
        args.out / "loans.csv",
        [
            {
                "loan_id": loan.loan_id,
                "borrower_id": loan.borrower_id,
                "product_code": loan.product,
                "principal_amount": loan.principal,
                "annual_interest_rate": loan.interest_rate,
                "term_months": loan.term_months,
                "origination_date": loan.origination_date.isoformat(),
                "origination_channel": loan.channel,
            }
            for loan in loans
        ],
    )

    by_month: dict[str, list[dict]] = defaultdict(list)
    for p in payments:
        by_month[p["payment_date"][:7].replace("-", "_")].append(p)
    for month, rows in sorted(by_month.items()):
        write_csv(args.out / "payments" / f"payments_{month}.csv", rows)

    print(
        f"borrowers={len(borrowers):,} loans={len(loans):,} payments={len(payments):,} "
        f"payment_files={len(by_month)} -> {args.out}"
    )


if __name__ == "__main__":
    main()
