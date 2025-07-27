from ortools.sat.python import cp_model
from datetime import date, datetime, timedelta
import itertools
from icalendar import Calendar, Event
import pytz

# ----------------------
# 1. Problem parameters
# ----------------------

students = ['Lodha', 'Kareti', 'Schmidt', 'Cipriani', 'Pozo', 'Oleson', 'Cowles']

# Rotation window: July 1–25, 2025 (skip Wednesdays)
start_date = date(2025, 7, 1)
end_date   = date(2025, 7, 25)
num_days   = (end_date - start_date).days + 1
all_dates = [
    start_date + timedelta(days=i)
    for i in range(num_days)
    #if (start_date + timedelta(days=i)).weekday() != 2
]

# Shift definitions: key → start hour (24h)
shift_defs = {
    # Metro shifts
    'West':        7,
    # 'WestAM':        7,
    # 'WestPM':       17,
    'Acute':            7,
    # 'A1':            7,
    # 'A2':            7,
    # 'C1':            11,
    # 'C2':            11,
    # 'E1':            15,
    # 'E2':            15,
    'Trauma':       14,

    # CCF shifts
    'E12':           7,
    'E18':          10,

    # Overnight shifts
    'Metro Night': 21,  # overnight at Metro
    'CCF Night': 21,   # overnight at CCF
    
    # Community Shifts
    'Com Parma': 7,
    'Com Breckville': 7,

    # MLF Shifts
    'MLF Wayne': 7,
    'MLF Lorain': 7,
}

# Categories by name
west_names      = {'West', 'WestAM', 'WestPM'}
acute_names     = {'Acute', 'A1', 'A2', 'C1', 'C2', 'E1', 'E2'}
trauma_names    = {'Trauma'}
ccf_names       = {'E12', 'E18'}
overnight_names = {'Metro Night', 'CCF Night'}
community_names = {'Com Parma', 'Com Breckville'}
mlf_names       = {'MLF Wayne', 'MLF Lorain'}

# ------------------------
# 2. Build the all_shifts
# ------------------------

all_shifts = []
for current_date in all_dates:
    # Skip Wednesdays (weekday() == 2)
    if current_date.weekday() == 2:
        continue
    for name, hour in shift_defs.items():
        is_overnight = name in overnight_names
        # Prevent overnight shifts from starting on Tuesday or Wednesday
        if is_overnight and current_date.weekday() in (1, 2):  # 1=Tuesday, 2=Wednesday
            continue
        start_dt = datetime(
            current_date.year,
            current_date.month,
            current_date.day,
            hour, 0
        )
        if is_overnight:
            duration = timedelta(hours=48)
        elif name in {'West', 'Com Parma', 'Com Breckville', 'E18'}:
            duration = timedelta(hours=8)
        else:
            duration = timedelta(hours=10)

        # Determine category
        if is_overnight:
            category = 'overnight'
        elif name in trauma_names:
            category = 'trauma'
        elif name in ccf_names:
            category = 'ccf'
        elif name in acute_names:
            category = 'acute'
        elif name in west_names:
            category = 'west'
        elif name in community_names:
            category = 'community'
        elif name in mlf_names:
            category = 'mlf'
        
        if is_overnight:
            site = 'CCF' if name == 'CCF Night' else 'Metro'
        elif name in community_names:
            site = name.strip('Com ').replace(' ', '')
        elif name in mlf_names:
            site = name.strip('MLF ').replace(' ', '')
        else:
            site = 'CCF' if name in ccf_names else 'Metro'

        all_shifts.append({
            'id':           f"{name}_{start_dt:%Y%m%d%H}",
            'start':        start_dt,
            'end':          start_dt + duration,
            'name':         name,
            'category':     category,
            'site':         site,
            'is_overnight': is_overnight,
        })

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

for student in students:
    # 1 overnight block
    model.Add(
        sum(x[(s['id'], student)] for s in all_shifts if s['category']=='overnight')
        == 1
    )
    # 2 trauma shifts
    model.Add(
        sum(x[(s['id'], student)] for s in all_shifts if s['category']=='trauma')
        == 2
    )
    # 3 CCF shifts
    model.Add(
        sum(x[(s['id'], student)] for s in all_shifts if s['category']=='ccf')
        == 3
    )
    # 1 community shifts
    model.Add(
        sum(x[(s['id'], student)] for s in all_shifts if s['category']=='community')
        == 1
    )
    # 1 MLF shifts
    model.Add(
        sum(x[(s['id'], student)] for s in all_shifts if s['category']=='mlf')
        == 1
    )
    # 14 total shifts (encoded as 12 + 1 overnight block)
    model.Add(
        sum(x[(s['id'], student)] for s in all_shifts) == 13
    )
    # at most 1 E18 shift
    model.Add(
        sum(x[(s['id'], student)] for s in all_shifts if s['name'] == 'E18')
        <= 1
    )
    # at least 2 acute shifts
    model.Add(
        sum(x[(s['id'], student)] for s in all_shifts if s['category']=='acute')
        >= 2
    )
    # at least 1 West shifts
    model.Add(
        sum(x[(s['id'], student)] for s in all_shifts if s['category']=='west')
        >= 1
    )

    # Rest & overlap constraints
    for s1, s2 in itertools.combinations(all_shifts, 2):
        v1 = x[(s1['id'], student)]
        v2 = x[(s2['id'], student)]
        # 20h between starts for two non-overnights
        if not s1['is_overnight'] and not s2['is_overnight']:
            delta_h = abs((s1['start'] - s2['start']).total_seconds())/3600.0
            if delta_h < 20:
                model.Add(v1 + v2 <= 1)
        # no time overlap
        if s1['start'] < s2['end'] and s2['start'] < s1['end']:
            model.Add(v1 + v2 <= 1)

# ----------------------------------
# 5. Global “no double-booking” rule
# ----------------------------------

for s in all_shifts:
    model.Add(
        sum(x[(s['id'], student)] for student in students) <= 1
    )

# ----------------
# 6. Solve & print
# ----------------

solver = cp_model.CpSolver()
solver.parameters.max_time_in_seconds = 60
status = solver.Solve(model)

# if status in (cp_model.OPTIMAL, cp_model.FEASIBLE):
#     for student in students:
#         assigned = [s for s in all_shifts if solver.Value(x[(s['id'], student)])]
#         print(f"{student} assigned {len(assigned) + 1} ED shifts:")
#         for s in sorted(assigned, key=lambda x: x['start']):
#             if s['is_overnight']:
#                 weekday   = s['start'].strftime('%A')
#                 month_day = f"{s['start'].month}/{s['start'].day}"
#                 start_tm  = s['start'].strftime('%I:%M %p')
#                 end_tm = (s['start'] + timedelta(hours=10)).strftime('%I:%M %p')
#                 print(f"  • {s['name']} ({s['site']}): {weekday} {month_day}, {start_tm} - {end_tm}")
#                 print(f"  • {s['name']} ({s['site']}): {(s['start'] + timedelta(days=1)).strftime('%A')} {s['start'].month}/{s['start'].day + 1}, {start_tm} - {end_tm}")
#             else:
#                 weekday   = s['start'].strftime('%A')
#                 month_day = f"{s['start'].month}/{s['start'].day}"
#                 start_tm  = s['start'].strftime('%I:%M %p')
#                 end_tm    = s['end'].strftime('%I:%M %p')
#                 print(f"  • {s['name']} ({s['site']}): {weekday} {month_day}, {start_tm} - {end_tm}")
#         print()
# else:
#     print("No feasible assignment found.")

if status in (cp_model.OPTIMAL, cp_model.FEASIBLE):
    for student in students:
        assigned = [s for s in all_shifts if solver.Value(x[(s['id'], student)])]
        print(f"{student} assigned {len(assigned) + 1} ED shifts:")
        cal = Calendar()
        cal.add('prodid', '-//MetroAI Scheduler//mxm.dk//')
        cal.add('version', '2.0')

        # Add orientation event
        orientation_date = start_date - timedelta(days=1)
        orientation_start = datetime(orientation_date.year, orientation_date.month, orientation_date.day, 9, 0, tzinfo=pytz.timezone('America/New_York'))
        orientation_end = datetime(orientation_date.year, orientation_date.month, orientation_date.day, 15, 0, tzinfo=pytz.timezone('America/New_York'))
        event = Event()
        event.add('summary', 'Orientation')
        event.add('dtstart', orientation_start)
        event.add('dtend', orientation_end)
        event.add('location', 'Metro')
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
                event.add('location', 'Metro')
                cal.add_component(event)

        # Add assigned shifts
        for s in assigned:
            # For overnight, add a second event for the next day if needed
            if s['is_overnight']:
                overnight_start = (s['start']).replace(tzinfo=pytz.timezone('America/New_York'))
                overnight_end = (overnight_start + timedelta(hours=10))
                event = Event()
                event.add('summary', f"{s['name']} ({s['site']})")
                event.add('dtstart', overnight_start)
                event.add('dtend', overnight_end)
                event.add('location', s['site'])
                cal.add_component(event)

                overnight_start = (s['start'] + timedelta(days=1)).replace(tzinfo=pytz.timezone('America/New_York'))
                overnight_end = (overnight_start + timedelta(hours=10))
                event2 = Event()
                event2.add('summary', f"{s['name']} ({s['site']})")
                event2.add('dtstart', overnight_start)
                event2.add('dtend', overnight_end)
                event2.add('location', s['site'])
                cal.add_component(event2)
            else:
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