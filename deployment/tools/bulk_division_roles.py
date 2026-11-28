#!/usr/bin/env python3
"""Preview or apply a maintainer's Division Director, Area Director and council assignments."""
import argparse
import csv
import getpass
import json
import os
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen

PROJECTS = {"test": "oenawxeckerazwhvlpse", "production": "ovmdhkrkogivlvjnbqpj"}
COLUMNS = ("memberId", "role", "area", "title")


def call(base, path, key, body, token=None):
    headers = {"apikey": key, "Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    try:
        with urlopen(Request(base + path, json.dumps(body).encode(), headers), timeout=45) as response:
            return json.load(response)
    except HTTPError as error:
        message = "Sign-in failed" if path.startswith("/auth/") else json.load(error).get("message", "Request failed")
        raise SystemExit(f"{message} (HTTP {error.code})") from None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("file", type=Path)
    parser.add_argument("--division", default="K")
    parser.add_argument("--year", type=int, required=True, help="Program year start, such as 2026")
    parser.add_argument("--target", choices=PROJECTS, default="test")
    parser.add_argument("--email", required=True, help="Maintainer account email")
    parser.add_argument("--apply", action="store_true", help="Apply an approved batch. Default is a read-only preview.")
    args = parser.parse_args()
    key = os.environ.get("HDG_SUPABASE_PUBLISHABLE_KEY", "")
    if not key.startswith("sb_publishable_"):
        parser.error("Set HDG_SUPABASE_PUBLISHABLE_KEY to this project's publishable key.")
    with args.file.open(encoding="utf-8-sig", newline="") as source:
        reader = csv.DictReader(source)
        if reader.fieldnames != list(COLUMNS):
            parser.error("The CSV header must be memberId,role,area,title")
        rows = list(reader)
    if not 1 <= len(rows) <= 100 or any(None in row or None in row.values() for row in rows):
        parser.error("Provide 1–100 complete CSV rows.")
    base = f"https://{PROJECTS[args.target]}.supabase.co"
    print(f"{args.target.capitalize()} {args.division}, {args.year}–{args.year + 1}, {'apply' if args.apply else 'preview'}")
    session = call(base, "/auth/v1/token?grant_type=password", key, {
        "email": args.email, "password": getpass.getpass("Maintainer password: "),
    })
    result = call(base, "/rest/v1/rpc/hdg_bulk_division_roles", key, {
        "p_division": args.division, "p_year": args.year, "p_rows": rows, "p_apply": args.apply,
    }, session["access_token"])
    for row in result["rows"]:
        outcome = row["issue"] or ("already assigned" if row["existingRole"] else "assigned" if result["applied"] else "ready")
        print(f"CSV row {row['row'] + 1} · {row['role']} · {row['scope']} · {outcome}")
    return 0 if result["valid"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
