#!/usr/bin/env python3
"""Dry-run a private Division G snapshot and compare it with a normalized shadow extract."""
import argparse
from collections import Counter
from datetime import date
import hashlib
import json
from pathlib import Path
import re
from uuid import UUID

COLLECTIONS = {"tlis": "tli_session", "contests": "contest", "reports": "area_visit", "tasks": "personal_task"}
REQUIRED = (*COLLECTIONS, "clubs")


def load(path):
    return json.loads(path.read_text(encoding="utf-8"))


def iso(value):
    return date.fromisoformat(value).isoformat() if isinstance(value, str) and value else None


def club_number(value):
    value = str(value or "").strip().lstrip("0")
    return value if value.isdecimal() else None


def tagged_areas(value):
    if not value or str(value).strip().lower() in {"all", "all areas", "division g"}:
        return []
    if not re.fullmatch(r"G\d{1,2}(?:[ /,;+&]+G\d{1,2})*", str(value).strip(), re.IGNORECASE):
        raise ValueError("unresolved_area")
    return sorted(set(re.findall(r"G\d{1,2}", str(value).upper())))


def normalized(payload, plan):
    """Keep scope, identity and values separate. Report every unsafe or unmapped source row."""
    db = payload.get("data", payload)["database"]
    if any(not isinstance(db.get(name), list) for name in REQUIRED):
        raise ValueError("Snapshot lacks the required dashboard collections")
    records = {}
    blockers = Counter()
    seen = set()
    alignment = plan.get("alignment", {})
    owners = plan.get("taskOwners", {})
    rounds = plan.get("attendanceSessions", {})
    club_ids = {row.get("id"): club_number(row.get("number")) for row in db["clubs"] if row.get("id")}

    def add(kind, identifier, value):
        key = f"{kind}:{identifier}"
        if not identifier or key in seen:
            raise ValueError("missing_or_duplicate_source_id")
        seen.add(key)
        records[key] = value

    for collection, kind in COLLECTIONS.items():
        for row in db[collection]:
            try:
                source = row.get("id")
                if kind == "personal_task":
                    account = str(UUID(owners[row["assignedUser"]]))
                    title = (row.get("title") or "").strip()
                    if not title or len(title) > 200 or len(row.get("notes") or "") > 4000:
                        raise ValueError("invalid_task_fields")
                    add(kind, source, {"owner_id": account, "title": title,
                        "notes": row.get("notes") or "", "due_on": iso(row.get("dueDate")),
                        "completed": row.get("completed") is True})
                    continue
                occurred = iso(row.get("date"))
                if occurred is None:
                    raise ValueError("missing_event_date")
                day = date.fromisoformat(occurred)
                year = day.year - (day.month < 7)
                if str(year) not in alignment:
                    raise ValueError("missing_year_alignment")
                club = club_number(row.get("clubNumber")) or club_ids.get(row.get("clubId"))
                areas = tagged_areas(row.get("areas") if kind == "tli_session" else row.get("area"))
                if kind == "area_visit" and (row.get("type") != "clubVisit" or club is None):
                    raise ValueError("visit_has_no_club")
                if len(areas) > 1:
                    raise ValueError("multiple_event_areas")
                assigned_area = alignment[str(year)].get(club) if club else None
                if club and (not assigned_area or areas and assigned_area != areas[0]):
                    raise ValueError("unverified_club_alignment")
                if row.get("rawEml"):
                    blockers["area_visit:private_email_attachment_requires_review"] += 1
                area = assigned_area or (areas[0] if areas else None)
                title = (row.get("title") or row.get("name") or ("Club visit" if kind == "area_visit" else "")).strip()
                if not title or len(title) > 200:
                    raise ValueError("invalid_event_title")
                detail_exclusions = {"id", "title", "name", "area", "areas", "clubId", "clubNumber", "date", "rawEml",
                                     "sourceFilename", "subject"}
                add(kind, source, {"title": title, "occurred_on": occurred, "year_start": year,
                    "division_code": "G", "area_code": area, "club_number": club,
                    "details": {k: v for k, v in row.items() if k not in detail_exclusions}})
            except KeyError:
                blockers[f"{kind}:unverified_owner"] += 1
            except (ValueError, TypeError) as exc:
                reason = str(exc) if str(exc).replace("_", "").isalpha() else "invalid_value"
                blockers[f"{kind}:{reason}"] += 1

    # The legacy app records round flags on officer rows, often with several officers per person.
    # Only an explicit, verified mapping can turn a club round into specific session attendance.
    attendance = {}
    for officer in db.get("exco", []):
        club = club_number(officer.get("clubNumber"))
        mid = str(officer.get("memberId") or "").strip().upper().lstrip("0")
        for round_name in ("tli1", "tli2"):
            value = officer.get(round_name)
            if not isinstance(value, bool):
                continue
            mapping = rounds.get(f"{club}:{round_name}", {})
            session = mapping.get("session")
            membership = mapping.get("memberships", {}).get(mid) if mid else None
            if not membership or f"tli_session:{session}" not in records:
                blockers["attendance:unverified_session_or_member"] += 1
                continue
            previous = attendance.setdefault((session, membership), set())
            previous.add(value)
    for (session, membership), values in attendance.items():
        if len(values) != 1:
            blockers["attendance:conflicting_officer_flags"] += 1
        else:
            add("attendance", f"{session}:{membership}", {
                "session_source_id": session, "membership_id": membership, "present": next(iter(values))})

    # 009 owns official TI figures. A shadow extract must account for any separate legacy overrides.
    for club in db["clubs"]:
        if any(key in club for key in ("officialDcpGoals", "officialMembershipBase", "officialMembershipToDate",
                                     "dcpGoals", "dcpGoalsMet")):
            blockers["club_performance:verify_legacy_override_against_009"] += 1
    return records, blockers


def digest(record):
    return hashlib.sha256(json.dumps(record, ensure_ascii=False, sort_keys=True,
                                      separators=(",", ":")).encode()).hexdigest()


def compare(records, actual):
    expected = set(records)
    provided = set(actual)
    return {"missing": len(expected - provided), "unexpected": len(provided - expected),
            "different": sum(digest(records[key]) != digest(actual[key]) for key in expected & provided)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("mapping", type=Path, help="Private approved alignment, task owner and attendance mappings.")
    parser.add_argument("--shadow", type=Path, help="Private canonical extract keyed by kind and source ID.")
    args = parser.parse_args()
    records, blockers = normalized(load(args.source), load(args.mapping))
    outcome = {"mapped": dict(Counter(key.split(":", 1)[0] for key in records)),
               "blockers": dict(blockers), "compared": args.shadow is not None}
    if args.shadow:
        outcome["differences"] = compare(records, load(args.shadow))
    print(json.dumps(outcome, indent=2, sort_keys=True))
    return 1 if blockers or any(outcome.get("differences", {}).values()) else 0


if __name__ == "__main__":
    raise SystemExit(main())
