from ortools.sat.python import cp_model
from datetime import date, datetime, timedelta
import itertools
from icalendar import Calendar, Event
import pytz
import json
from collections import defaultdict
import csv

# ----------------------
# 1. Problem parameters
# ----------------------

students = ['Roshan', 'Roshan2', 'Roshan3', 'Roshan4', 'Roshan5', 'Roshan6', 'Roshan7']
shifts_file = "bidmc_shifts.json"

# ----------------------
# 2. Load shifts file
# ----------------------

def load_shifts_json(filename):
    with open(filename, 'r') as f:
        data = json.load(f)
    # Convert ISO strings back to datetime objects
    for s in data:
        s['start'] = datetime.fromisoformat(s['start'])
        s['end'] = datetime.fromisoformat(s['end'])
    return data

all_shifts = load_shifts_json(shifts_file)
start_date = min([s['start'] for s in all_shifts])
end_date = max([s['end'] for s in all_shifts])
num_days = (end_date - start_date).days + 1
all_dates = [
    start_date + timedelta(days=i)
    for i in range(num_days)
    #if (start_date + timedelta(days=i)).weekday() != 2
]

# ----------------------
# 3. Build the CSP model
# ----------------------

model = cp_model.CpModel()
x = {}
for student in students:
    for s in all_shifts:
        x[(s['id'], student)] = model.NewBoolVar(f"x_{s['id']}_{student}")

# -----------------------------
# 4. Per‐student requirements
# -----------------------------

# Build consecutive-overnight structure once
nights = [s for s in all_shifts if s['category'] == 'overnight']
nights.sort(key=lambda s: s['start'])

def hours_between(a, b):
    return (b['start'] - a['start']).total_seconds() / 3600.0

# Identify consecutive-night pairs (next night starts ~24h later; ensure no overlap)
consec_pairs = []
incident_pairs = {s['id']: [] for s in nights}
for i in range(len(nights) - 1):
    s1, s2 = nights[i], nights[i + 1]
    h = hours_between(s1, s2)
    if 20 <= h <= 28 and s1['end'] <= s2['start']:
        consec_pairs.append((s1, s2))
        incident_pairs[s1['id']].append((s1, s2))
        incident_pairs[s2['id']].append((s1, s2))

# Pair decision vars: y[(pair_id, student)]
y = {}
for (s1, s2) in consec_pairs:
    pid = f"{s1['id']}__{s2['id']}"
    for student in students:
        y[(pid, student)] = model.NewBoolVar(f"y_pair_{pid}__{student}")

for student in students:
    # Exactly one back-to-back overnight pair
    model.Add(
        sum(y[(f"{p1['id']}__{p2['id']}", student)] for (p1, p2) in consec_pairs) == 1
    )

    # Tie night selections to the chosen pair:
    # For each night n, x[n, student] == sum of incident selected pairs containing n
    for n in nights:
        incident = [y[(f"{p1['id']}__{p2['id']}", student)] for (p1, p2) in incident_pairs[n['id']]]
        if incident:
            model.Add(x[(n['id'], student)] == sum(incident))
        else:
            # Nights without a valid consecutive neighbor cannot be chosen
            model.Add(x[(n['id'], student)] == 0)

    # Category and total requirements
    model.Add(sum(x[(s['id'], student)] for s in all_shifts if s['category'] == 'overnight') == 2)
    model.Add(sum(x[(s['id'], student)] for s in all_shifts if s['category'] == 'trauma') == 1)
    model.Add(sum(x[(s['id'], student)] for s in all_shifts if s['category'] == 'community') == 1)
    model.Add(sum(x[(s['id'], student)] for s in all_shifts) == 15)

    # Rest & overlap constraint
    min_time_off = timedelta(hours=12) # 12 hours off between shifts
    for s1, s2 in itertools.combinations(all_shifts, 2):
        v1 = x[(s1['id'], student)]
        v2 = x[(s2['id'], student)]

        if not (s1['end'] + min_time_off < s2['start'] or s2['end'] + min_time_off < s1['start']):
            model.Add(v1 + v2 <= 1)

# No overlapping shifts
for s in all_shifts:
    model.Add(sum(x[(s['id'], student)] for student in students) <= 1)

# ----------------
# 5. Solve & print
# ----------------

solver = cp_model.CpSolver()
solver.parameters.max_time_in_seconds = 60
status = solver.Solve(model)

if status in (cp_model.OPTIMAL, cp_model.FEASIBLE):
    for student in students:
        assigned = [s for s in all_shifts if solver.Value(x[(s['id'], student)])]
        cal = Calendar()
        cal.add('prodid', '-//MetroAI Scheduler//mxm.dk//')
        cal.add('version', '2.0')

        # Add orientation event
        orientation_date = start_date - timedelta(days=2)
        orientation_start = datetime(orientation_date.year, orientation_date.month, orientation_date.day, 9, 0, tzinfo=pytz.timezone('America/New_York'))
        orientation_end = datetime(orientation_date.year, orientation_date.month, orientation_date.day, 15, 0, tzinfo=pytz.timezone('America/New_York'))
        event = Event()
        event.add('summary', 'Orientation')
        event.add('dtstart', orientation_start)
        event.add('dtend', orientation_end)
        event.add('location', 'BIDMC')
        cal.add_component(event)

        # Add shadow event
        shadow_date = start_date - timedelta(days=1)
        shadow_start = datetime(shadow_date.year, shadow_date.month, shadow_date.day, 2, 0, tzinfo=pytz.timezone('America/New_York'))
        shadow_end = datetime(shadow_date.year, shadow_date.month, shadow_date.day, 6, 0, tzinfo=pytz.timezone('America/New_York'))
        event = Event()
        event.add('summary', 'Shadowing')
        event.add('dtstart', shadow_start)
        event.add('dtend', shadow_end)
        event.add('location', 'BIDMC')
        cal.add_component(event)

        # Add conference events (every Wednesday)
        conf_time_zone = pytz.timezone('America/New_York')
        for d in all_dates:
            if d.weekday() == 2:  # Wednesday
                conf_start = datetime(d.year, d.month, d.day, 7, 0, tzinfo=conf_time_zone)
                conf_end = datetime(d.year, d.month, d.day, 12, 0, tzinfo=conf_time_zone)
                event = Event()
                event.add('summary', 'Conference')
                event.add('dtstart', conf_start)
                event.add('dtend', conf_end)
                event.add('location', 'BIDMC')
                cal.add_component(event)

        # Add assigned shifts
        for s in assigned:
            event = Event()
            event.add('summary', f"{s['name']} ({s['site']})")
            event.add('dtstart', s['start'].replace(tzinfo=pytz.timezone('America/New_York')))
            event.add('dtend', s['end'].replace(tzinfo=pytz.timezone('America/New_York')))
            event.add('location', s['site'])
            cal.add_component(event)

        # Write to file
        with open(f"{student}_schedule.ics", "wb") as f:
            f.write(cal.to_ical())
        print(f"iCal calendar saved as {student}_schedule.ics")

if status in (cp_model.OPTIMAL, cp_model.FEASIBLE):
    # Build: student -> date -> shift info (mark both days for overnights)
    schedule_table = defaultdict(dict)
    for student in students:
        assigned = [s for s in all_shifts if solver.Value(x[(s['id'], student)])]
        for s in assigned:
            label = s['name']
            d = s['start'].date()
            schedule_table[student][d] = label

    # Compute week ranges: weeks start on Sunday
    range_start = start_date.date()
    range_end = end_date.date()
    days_to_prev_sun = (range_start.weekday() + 1) % 7   # Mon=0,...,Sun=6; distance back to Sunday
    week_start = range_start - timedelta(days=days_to_prev_sun)

    master_csv = "schedule.csv"
    with open(master_csv, "w", newline='') as csvfile:
        writer = csv.writer(csvfile)

        while week_start <= range_end:
            week_end = min(week_start + timedelta(days=6), range_end)
            week_dates = [week_start + timedelta(days=i) for i in range((week_end - week_start).days + 1)]

            # Header and rows for this week
            header = ["Student"] + [d.strftime("%m/%d") for d in week_dates]
            rows = []
            for student in students:
                row = [student]
                for d in week_dates:
                    row.append(schedule_table[student].get(d, ""))
                rows.append(row)

            # ---- Pretty print ----
            col_width = 15
            fmt = "".join(["{:<" + str(col_width) + "}" for _ in header])
            print(f"Week {week_start.strftime('%Y-%m-%d')} to {week_end.strftime('%Y-%m-%d')}")
            print(fmt.format(*header))
            for row in rows:
                print(fmt.format(*row))
            print()

            # Write this week's section to the single CSV
            writer.writerow(header)
            writer.writerows(rows)
            writer.writerow([])  # blank line between weeks

            week_start = week_start + timedelta(days=7)

    print(f"All weeks saved to {master_csv}")
