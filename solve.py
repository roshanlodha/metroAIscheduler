from ortools.sat.python import cp_model
from datetime import date, datetime, timedelta
import itertools
from icalendar import Calendar, Event
import pytz
import json
from collections import defaultdict
import csv

def load_shifts_json(filename):
    with open(filename, 'r') as f:
        data = json.load(f)
    for s in data:
        s['start'] = datetime.fromisoformat(s['start'])
        s['end'] = datetime.fromisoformat(s['end'])
    return data

def run_solver(filepath, students):
    all_shifts = load_shifts_json(filepath)
    start_date = min([s['start'] for s in all_shifts])
    end_date = max([s['end'] for s in all_shifts])
    num_days = (end_date - start_date).days + 1
    all_dates = [
        start_date + timedelta(days=i)
        for i in range(num_days)
    ]

    model = cp_model.CpModel()
    x = {}
    for student in students:
        for s in all_shifts:
            x[(s['id'], student)] = model.NewBoolVar(f"x_{s['id']}_{student}")

    for student in students:
        model.Add(
            sum(x[(s['id'], student)] for s in all_shifts if s['category']=='overnight')
            == 1
        )
        model.Add(
            sum(x[(s['id'], student)] for s in all_shifts if s['category']=='trauma')
            == 2
        )
        model.Add(
            sum(x[(s['id'], student)] for s in all_shifts if s['category']=='ccf')
            == 3
        )
        model.Add(
            sum(x[(s['id'], student)] for s in all_shifts if s['category']=='community')
            == 1
        )
        model.Add(
            sum(x[(s['id'], student)] for s in all_shifts if s['category']=='mlf')
            == 1
        )
        model.Add(
            sum(x[(s['id'], student)] for s in all_shifts) == 13
        )
        model.Add(
            sum(x[(s['id'], student)] for s in all_shifts if s['name'] == 'E18')
            <= 1
        )
        model.Add(
            sum(x[(s['id'], student)] for s in all_shifts if s['category']=='acute')
            >= 2
        )
        model.Add(
            sum(x[(s['id'], student)] for s in all_shifts if s['category']=='west')
            >= 1
        )

        for s1, s2 in itertools.combinations(all_shifts, 2):
            v1 = x[(s1['id'], student)]
            v2 = x[(s2['id'], student)]
            if not s1['is_overnight'] and not s2['is_overnight']:
                delta_h = abs((s1['start'] - s2['start']).total_seconds())/3600.0
                if delta_h < 20:
                    model.Add(v1 + v2 <= 1)
            if s1['start'] < s2['end'] and s2['start'] < s1['end']:
                model.Add(v1 + v2 <= 1)

    for s in all_shifts:
        model.Add(
            sum(x[(s['id'], student)] for student in students) <= 1
        )

    solver = cp_model.CpSolver()
    solver.parameters.max_time_in_seconds = 60
    status = solver.Solve(model)

    if status in (cp_model.OPTIMAL, cp_model.FEASIBLE):
        for student in students:
            assigned = [s for s in all_shifts if solver.Value(x[(s['id'], student)])]
            print(f"{student} assigned {len(assigned) + 1} ED shifts:")
            cal = Calendar()
            cal.add('prodid', '-//MetroAI Scheduler//mxm.dk//')
            cal.add('version', '2.0')

            orientation_date = start_date - timedelta(days=1)
            orientation_start = datetime(orientation_date.year, orientation_date.month, orientation_date.day, 9, 0, tzinfo=pytz.timezone('America/New_York'))
            orientation_end = datetime(orientation_date.year, orientation_date.month, orientation_date.day, 15, 0, tzinfo=pytz.timezone('America/New_York'))
            event = Event()
            event.add('summary', 'Orientation')
            event.add('dtstart', orientation_start)
            event.add('dtend', orientation_end)
            event.add('location', 'Metro')
            cal.add_component(event)

            conf_time_zone = pytz.timezone('America/New_York')
            for d in all_dates:
                if d.weekday() == 2:
                    conf_start = datetime(d.year, d.month, d.day, 7, 0, tzinfo=conf_time_zone)
                    conf_end = datetime(d.year, d.month, d.day, 12, 0, tzinfo=conf_time_zone)
                    event = Event()
                    event.add('summary', 'Conference')
                    event.add('dtstart', conf_start)
                    event.add('dtend', conf_end)
                    event.add('location', 'Metro')
                    cal.add_component(event)

            for s in assigned:
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

            # with open(f"{student}_schedule.ics", "wb") as f: 
            #     f.write(cal.to_ical())
            print(f"iCal calendar saved as {student}_schedule.ics")

        schedule_table = defaultdict(dict)
        for student in students:
            assigned = [s for s in all_shifts if solver.Value(x[(s['id'], student)])]
            for s in assigned:
                if s['is_overnight']:
                    day1 = s['start'].date()
                    day2 = (s['start'] + timedelta(days=1)).date()
                    info = f"{s['name']} ({s['site']})"
                    schedule_table[student][day1] = info
                    schedule_table[student][day2] = info
                else:
                    day = s['start'].date()
                    info = f"{s['name']} ({s['site']})"
                    schedule_table[student][day] = info

        header = ["Student"] + [d.strftime("%m/%d") for d in all_dates]
        rows = []
        for student in students:
            row = [student]
            for d in all_dates:
                shift_info = schedule_table[student].get(d.date(), "")
                row.append(shift_info)
            rows.append(row)

        print("\t".join(header))
        for row in rows:
            print("\t".join(row))

        with open("schedule_table.csv", "w", newline='') as csvfile:
            writer = csv.writer(csvfile)
            writer.writerow(header)
            writer.writerows(rows)
        print("Schedule table saved as schedule_table.csv")
    else:
        print("No feasible assignment found.")
