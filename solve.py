import csv
from collections import defaultdict
from datetime import date, datetime, timedelta
from typing import Dict, List

import pytz
from icalendar import Calendar, Event
from ortools.sat.python import cp_model


def run_solver(
    all_shifts: List[Dict],
    students: List[str],
    constraints: Dict[str, int],
    start_date: date,
    institution: str = "",
) -> str:
    """Execute the solver using in-memory shifts and user-provided constraints."""
    if not all_shifts:
        raise ValueError('No shifts provided to solver.')

    tz = pytz.timezone('America/New_York')
    min_start = min(s['start'] for s in all_shifts)
    max_end = max(s.get('block_end', s['end']) for s in all_shifts)

    schedule_start = min(start_date, min_start.date())
    schedule_end_date = max_end.date()
    num_days = (schedule_end_date - schedule_start).days + 1
    all_dates = [schedule_start + timedelta(days=i) for i in range(num_days)]

    model = cp_model.CpModel()
    x = {}
    for student in students:
        for shift in all_shifts:
            x[(shift['id'], student)] = model.NewBoolVar(f"x_{shift['id']}_{student}")

    def apply_equal_constraint(category: str, key: str) -> None:
        required = constraints.get(key)
        if required is None:
            return
        for student in students:
            model.Add(
                sum(x[(s['id'], student)] for s in all_shifts if s['category'] == category)
                == required
            )

    def apply_max_constraint(filter_fn, key: str) -> None:
        limit = constraints.get(key)
        if limit is None:
            return
        for student in students:
            model.Add(
                sum(x[(s['id'], student)] for s in all_shifts if filter_fn(s))
                <= limit
            )

    def apply_min_constraint(category: str, key: str) -> None:
        minimum = constraints.get(key)
        if minimum is None:
            return
        for student in students:
            model.Add(
                sum(x[(s['id'], student)] for s in all_shifts if s['category'] == category)
                >= minimum
            )

    apply_equal_constraint('overnight', 'overnight_per_student')
    apply_equal_constraint('trauma', 'trauma_per_student')
    apply_equal_constraint('ccf', 'ccf_per_student')
    apply_equal_constraint('community', 'community_per_student')
    apply_equal_constraint('mlf', 'mlf_per_student')

    total_required = constraints.get('total_shifts_per_student')
    if total_required is not None:
        for student in students:
            model.Add(sum(x[(s['id'], student)] for s in all_shifts) == total_required)

    apply_max_constraint(lambda s: s['name'] == 'E18', 'max_e18_per_student')
    apply_min_constraint('acute', 'min_acute_per_student')
    apply_min_constraint('west', 'min_west_per_student')

    for student in students:
        for i, s1 in enumerate(all_shifts):
            for s2 in all_shifts[i + 1:]:
                v1 = x[(s1['id'], student)]
                v2 = x[(s2['id'], student)]

                if not s1.get('is_overnight') and not s2.get('is_overnight'):
                    delta_h = abs((s1['start'] - s2['start']).total_seconds()) / 3600.0
                    if delta_h < 20:
                        model.Add(v1 + v2 <= 1)

                if s1['start'] < s2.get('block_end', s2['end']) and s2['start'] < s1.get('block_end', s1['end']):
                    model.Add(v1 + v2 <= 1)

    for shift in all_shifts:
        model.Add(sum(x[(shift['id'], student)] for student in students) <= 1)

    solver = cp_model.CpSolver()
    solver.parameters.max_time_in_seconds = 60
    status = solver.Solve(model)

    if status not in (cp_model.OPTIMAL, cp_model.FEASIBLE):
        raise ValueError('No feasible assignment found.')

    orientation_location = institution or 'Metro'

    for student in students:
        assigned = [s for s in all_shifts if solver.Value(x[(s['id'], student)])]
        cal = Calendar()
        cal.add('prodid', '-//MetroAI Scheduler//mxm.dk//')
        cal.add('version', '2.0')

        orientation_date = start_date - timedelta(days=1)
        orientation_start = datetime(
            orientation_date.year,
            orientation_date.month,
            orientation_date.day,
            9,
            0,
            tzinfo=tz,
        )
        orientation_end = orientation_start + timedelta(hours=6)
        orientation_event = Event()
        orientation_event.add('summary', 'Orientation')
        orientation_event.add('dtstart', orientation_start)
        orientation_event.add('dtend', orientation_end)
        orientation_event.add('location', orientation_location)
        cal.add_component(orientation_event)

        for d in all_dates:
            if d.weekday() == 2:
                conf_start = datetime(d.year, d.month, d.day, 7, 0, tzinfo=tz)
                conf_end = conf_start + timedelta(hours=5)
                conference = Event()
                conference.add('summary', 'Conference')
                conference.add('dtstart', conf_start)
                conference.add('dtend', conf_end)
                conference.add('location', 'Metro')
                cal.add_component(conference)

        for shift in assigned:
            site = shift.get('site') or institution
            event = Event()
            event.add('summary', f"{shift['name']} ({site})" if site else shift['name'])
            event.add('dtstart', shift['start'].replace(tzinfo=tz))
            event.add('dtend', shift['end'].replace(tzinfo=tz))
            if site:
                event.add('location', site)
            cal.add_component(event)

            if shift.get('is_overnight'):
                second_start = (shift['start'] + timedelta(days=1)).replace(tzinfo=tz)
                second_end = second_start + (shift['end'] - shift['start'])
                overnight = Event()
                overnight.add('summary', f"{shift['name']} ({site})" if site else shift['name'])
                overnight.add('dtstart', second_start)
                overnight.add('dtend', second_end)
                if site:
                    overnight.add('location', site)
                cal.add_component(overnight)

        with open(f"{student}_schedule.ics", "wb") as ics_file:
            ics_file.write(cal.to_ical())

    schedule_table = defaultdict(dict)
    for student in students:
        assigned = [s for s in all_shifts if solver.Value(x[(s['id'], student)])]
        for shift in assigned:
            info = f"{shift['name']} ({shift.get('site') or institution})" if (shift.get('site') or institution) else shift['name']
            if shift.get('is_overnight'):
                first_day = shift['start'].date()
                schedule_table[student][first_day] = info
                schedule_table[student][first_day + timedelta(days=1)] = info
            else:
                schedule_table[student][shift['start'].date()] = info

    header = ["Student"] + [d.strftime("%m/%d") for d in all_dates]
    rows = []
    for student in students:
        row = [student]
        for d in all_dates:
            row.append(schedule_table[student].get(d, ""))
        rows.append(row)

    print("\t".join(header))
    for row in rows:
        print("\t".join(row))

    with open("schedule_table.csv", "w", newline='', encoding='utf-8') as csvfile:
        writer = csv.writer(csvfile)
        writer.writerow(header)
        writer.writerows(rows)

    return f"Generated schedule for {len(students)} students covering {len(all_shifts)} shifts."
