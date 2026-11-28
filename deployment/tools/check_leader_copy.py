#!/usr/bin/env python3
"""Normalize a Division G snapshot and report shadow parity as counts only."""
import argparse
from collections import Counter
from datetime import date
import json
from pathlib import Path
import re
from uuid import UUID

COLLECTIONS = {'tlis': 'tli_session', 'contests': 'contest', 'reports': 'area_visit'}
REQUIRED = (*COLLECTIONS, 'clubs', 'tasks', 'exco', 'taskDismissals')
STRUCTURED = {
    'tli_session': ('attendance', 'officers', 'registered', 'clubs', 'start', 'end', 'timezone',
                    'mode', 'city', 'island', 'venue', 'status', 'type'),
    'contest': ('attendance', 'categories', 'contestants', 'contestantsConfirmed', 'judgesConfirmed',
                'promoReady', 'venueConfirmed', 'start', 'end', 'mode', 'city', 'island',
                'venue', 'status', 'type', 'level', 'targetWindow'),
    'area_visit': ('round', 'reportStartDate', 'status', 'summaryScore', 'meetingObservationScore',
                   'clubExperienceScore', 'clubSupportScore', 'clubConcernsScore'),
    'club_performance': ('members', 'baseMembers', 'newMembers', 'lostMembers', 'renewedMembers',
                         'dcpGoals', 'educationAwards', 'officersTrained', 'cspSubmitted', 'officerList',
                         'adVisitMay2027', 'adVisitNov2026', 'adVisitRound1OfficialAsOf',
                         'adVisitRound1OfficialSource', 'guests', 'attendance', 'conversions', 'meetings',
                         'duesPaid', 'renewalApr2027', 'renewalOct2026', 'renewalStatus', 'mar27Override',
                         'suspensionRisk'),
}
REVIEW = {
    'tli_session': ('lead', 'notes'),
    'contest': ('chair', 'chiefJudge', 'notes', 'owner'),
    'area_visit': ('visitConductedBy', 'observations', 'concernsNotes', 'eventsPlanned', 'futureLeaders',
                   'nextGoals', 'sections', 'supportNeeded', 'sourceFilename', 'subject'),
    'club_performance': ('notes', 'suspensionReason'),
}


def load(path):
    return json.loads(path.read_text(encoding='utf-8'))


def club_number(value):
    value = str(value or '').strip().lstrip('0')
    return value if value.isdecimal() else None


def program_year(day):
    return day.year - (day.month < 7)


def tagged_areas(value):
    value = str(value or '').strip().upper()
    if value in ('', 'ALL', 'ALL AREAS', 'DIVISION G'):
        return []
    if not re.fullmatch(r'G\d{1,2}(?:[ /,;+&]+G\d{1,2})*', value):
        raise ValueError('unresolved_area')
    return sorted(set(re.findall(r'G\d{1,2}', value)))


def plan_copy(payload, plan):
    db = payload.get('data', payload)['database']
    if any(not isinstance(db.get(name), list) for name in REQUIRED):
        raise ValueError('Snapshot lacks the required dashboard collections')
    records, blockers, excluded = {}, Counter(), Counter()
    alignment = plan['alignment']
    club_ids = {row.get('id'): club_number(row.get('number')) for row in db['clubs'] if row.get('id')}

    def add(kind, source, row):
        if not source or f'{kind}:{source}' in records:
            raise ValueError('missing_or_duplicate_source_id')
        records[f'{kind}:{source}'] = row

    def event(kind, row, source, day, club, areas, title):
        year = str(program_year(day))
        aligned = alignment.get(year, {})
        if not aligned or any(area not in set(aligned.values()) for area in areas):
            raise LookupError('unverified_event_year_or_area')
        if club:
            assigned = aligned.get(club)
            if not assigned or (areas and areas != [assigned]):
                raise LookupError('unverified_club_alignment')
            areas = [assigned]
        if kind in ('area_visit', 'club_performance') and not club:
            raise LookupError('unverified_club')
        if not isinstance(title, str) or not 1 <= len(title.strip()) <= 200:
            raise ValueError('invalid_title')
        details = {key: row[key] for key in STRUCTURED[kind] if key in row}
        if kind == 'club_performance':
            details['snapshotKind'] = 'legacy_dashboard'
        add(kind, source, dict(title=title.strip(), occurred_on=day.isoformat(), year_start=int(year),
            division_code='G', area_code=areas[0] if len(areas) == 1 else None,
            area_codes=areas if len(areas) > 1 else [], club_number=club, details=details))
        excluded[f'{kind}:free_text_fields'] += sum(bool(row.get(key)) for key in REVIEW[kind])
        if kind == 'area_visit' and row.get('rawEml'):
            excluded['area_visit:raw_email_attachments'] += 1

    for collection, kind in COLLECTIONS.items():
        for row in db[collection]:
            try:
                day = date.fromisoformat(row['date'])
                club = club_number(row.get('clubNumber')) or club_ids.get(row.get('clubId'))
                if kind == 'area_visit' and row.get('type') != 'clubVisit':
                    raise LookupError('unsupported_report_type')
                if kind == 'contest':
                    # Area contests may use the longer coverage label for a combined event.
                    areas = [] if row.get('level') == 'Division' else sorted(set(
                        tagged_areas(row.get('area')) + re.findall(r'\bG\d{1,2}\b', row.get('coverage', '').upper())))
                    if row.get('level') == 'Area' and not areas:
                        raise LookupError('unverified_contest_coverage')
                else:
                    areas = tagged_areas(row.get('areas') if kind == 'tli_session' else row.get('area'))
                title = row.get('title') or row.get('name') or ('Club visit' if kind == 'area_visit' else '')
                event(kind, row, row.get('id'), day, club, areas, title)
            except (KeyError, TypeError, ValueError):
                blockers[f'{kind}:invalid_source_record'] += 1
            except LookupError as error:
                excluded[f'{kind}:{error.args[0]}'] += 1

    for row in db['clubs']:
        if not set(row) & set(STRUCTURED['club_performance']):
            continue
        kind = 'club_performance'
        try:
            club = club_number(row.get('number'))
            event(kind, row, club, date.fromisoformat(plan['sourceDate']), club,
                  tagged_areas(row.get('area')), 'Legacy dashboard figures')
        except (KeyError, TypeError, ValueError):
            blockers[f'{kind}:invalid_source_record'] += 1
        except LookupError as error:
            excluded[f'{kind}:{error.args[0]}'] += 1

    rounds = {}
    for officer in db['exco']:
        term = str(officer.get('term') or '')
        end = re.fullmatch(r'\d{4}-\d{2}-\d{2}\s+[–-]\s+(\d{4})-06-30', term)
        year = int(end[1]) - 1 if end else None
        club = club_number(officer.get('clubNumber'))
        member = str(officer.get('memberId') or '').strip().upper().lstrip('0')
        for round_no in (1, 2):
            value = officer.get(f'tli{round_no}')
            if type(value) is not bool:
                excluded['tli_round_attendance:unknown_flags'] += 1
                continue
            key = (year, round_no, club, member)
            rounds.setdefault(key, []).append(value)
    for (year, round_no, club, member), values in rounds.items():
        excluded['tli_round_attendance:duplicate_officer_flags'] += len(values) - 1
        membership = plan.get('memberships', {}).get(f'{club}:{member}')
        if club not in alignment.get(str(year), {}) or not membership:
            excluded['tli_round_attendance:unverified_membership_or_year'] += 1
        elif len(set(values)) != 1:
            excluded['tli_round_attendance:conflicting_officer_flags'] += 1
        else:
            membership = str(UUID(membership))
            add('tli_round_attendance', f'{membership}:{year}:{round_no}', dict(
                membership_id=membership, year_start=year, round_no=round_no, present=values[0]))
    if db['tasks']:
        blockers['personal_task:needs_verified_owner_and_scope'] = len(db['tasks'])
    excluded['personal_task:automatic_dismissals_pending_verification'] = len(db['taskDismissals'])
    return records, blockers, +excluded


def compare(records, actual):
    kinds = sorted({key.split(':', 1)[0] for key in records.keys() | actual.keys()}
                   | set(COLLECTIONS.values()) | {'club_performance', 'tli_round_attendance',
                                                  'tli_attendance', 'personal_task'})
    differences = {kind: dict(expected=0, missing=0, extra=0, changed=0) for kind in kinds}
    for key in records.keys() | actual.keys():
        counts = differences[key.split(':', 1)[0]]
        counts['expected'] += key in records
        counts['missing'] += key not in actual
        counts['extra'] += key not in records
        counts['changed'] += key in records and key in actual and records[key] != actual[key]
    return differences


def result(records, blockers, excluded, shadow):
    return dict(blockers=dict(blockers), exclusions=dict(excluded), parity=compare(records, shadow))


def refresh_delta(previous, current, shadow):
    """Refresh only rows that still match the known, untouched shadow baseline."""
    if previous != shadow:
        raise ValueError('Shadow drifted from its verified source revision')
    previous_keys = previous.keys()
    current_keys = current.keys()
    return {
        'insert': {key: current[key] for key in sorted(current_keys - previous_keys)},
        'update': {key: current[key] for key in sorted(current_keys & previous_keys)
                   if current[key] != previous[key]},
        'delete': sorted(previous_keys - current_keys),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path, help='Authorized private snapshot or synthetic fixture')
    parser.add_argument('mapping', type=Path, help='Verified club alignment and membership links')
    parser.add_argument('--shadow', type=Path, required=True, help='Canonical extract from the shadow tables')
    parser.add_argument('--previous-projection', type=Path,
                        help='Verified canonical projection of the revision that seeded the shadow')
    args = parser.parse_args()
    records, blockers, excluded = plan_copy(load(args.source), load(args.mapping))
    shadow = load(args.shadow)
    summary = result(records, blockers, excluded, shadow)
    if args.previous_projection:
        try:
            delta = refresh_delta(load(args.previous_projection), records, shadow)
            summary['refresh'] = {operation: dict(Counter(key.split(':', 1)[0] for key in keys))
                                  for operation, keys in delta.items()}
        except ValueError:
            summary['blockers']['shadow_baseline_drift'] = 1
    print(json.dumps(summary, indent=2, sort_keys=True))
    return int(bool(summary['blockers']) or any(any(row[k] for k in ('missing', 'extra', 'changed'))
                                     for row in summary['parity'].values()))


if __name__ == '__main__':
    raise SystemExit(main())
