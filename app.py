import json
import os
from datetime import datetime
from typing import Dict

from flask import (
    Flask,
    flash,
    redirect,
    render_template,
    request,
    send_file,
    url_for,
)

import shift_builder
import solve

app = Flask(__name__)
app.secret_key = "supersecretkey"
UPLOAD_FOLDER = os.path.dirname(__file__)
app.config['UPLOAD_FOLDER'] = UPLOAD_FOLDER

DEFAULT_CONSTRAINTS: Dict[str, int] = {
    "overnight_per_student": 1,
    "trauma_per_student": 2,
    "ccf_per_student": 3,
    "community_per_student": 1,
    "mlf_per_student": 1,
    "total_shifts_per_student": 13,
    "min_acute_per_student": 2,
    "min_west_per_student": 1,
    "max_e18_per_student": 1,
}

CONSTRAINT_FIELDS = [
    ("overnight_per_student", "Overnight shifts per student (exact)"),
    ("trauma_per_student", "Trauma shifts per student (exact)"),
    ("ccf_per_student", "CCF shifts per student (exact)"),
    ("community_per_student", "Community shifts per student (exact)"),
    ("mlf_per_student", "MLF shifts per student (exact)"),
    ("total_shifts_per_student", "Total shifts per student (exact)"),
    ("min_acute_per_student", "Minimum acute shifts per student"),
    ("min_west_per_student", "Minimum west shifts per student"),
    ("max_e18_per_student", "Maximum E18 shifts per student"),
]


@app.route('/', methods=['GET', 'POST'])
def index():
    result = None
    errors = []
    csv_ready = False
    templates = shift_builder.list_templates()
    constraints = DEFAULT_CONSTRAINTS.copy()
    selected_template = request.form.get('template_slug') or (templates[0]['slug'] if templates else '')
    students_raw = request.form.get('students', '')
    start_date_value = request.form.get('start_date', '')
    end_date_value = request.form.get('end_date', '')

    if request.method == 'POST':
        students = [s.strip() for s in students_raw.split(',') if s.strip()]
        if not students:
            errors.append('Please enter at least one student name.')

        start_date_str = start_date_value
        end_date_str = end_date_value
        try:
            start_date = datetime.strptime(start_date_str, "%Y-%m-%d").date() if start_date_str else None
            end_date = datetime.strptime(end_date_str, "%Y-%m-%d").date() if end_date_str else None
            if not start_date or not end_date:
                errors.append('Start and end dates are required.')
            elif start_date > end_date:
                errors.append('Start date must be before end date.')
        except ValueError:
            errors.append('Invalid date format. Use YYYY-MM-DD.')
            start_date = end_date = None

        # Collect constraints from form
        for key in constraints:
            value = request.form.get(key)
            if value is None or value == '':
                continue
            try:
                constraints[key] = int(value)
            except ValueError:
                errors.append(f"Constraint '{key}' must be an integer.")

        if not selected_template:
            errors.append('Please select a shift template.')

        if not errors:
            try:
                template = shift_builder.load_template(selected_template)
                all_shifts = shift_builder.build_shifts_from_template(template, start_date, end_date)
                if not all_shifts:
                    errors.append('No shifts generated for the selected template and date range.')
                else:
                    shifts_path = os.path.join(app.config['UPLOAD_FOLDER'], 'shifts.json')
                    shift_builder.save_shifts_json(shifts_path, all_shifts)
                    result = solve.run_solver(all_shifts, students, constraints, start_date, template.get('institution', ''))
                    csv_path = os.path.join(app.config['UPLOAD_FOLDER'], 'schedule_table.csv')
                    csv_ready = os.path.exists(csv_path)
            except Exception as exc:  # pylint: disable=broad-exception-caught
                errors.append(str(exc))

    return render_template(
        'index.html',
        result=result,
        csv_ready=csv_ready,
        templates=templates,
        selected_template=selected_template,
        constraints=constraints,
        errors=errors,
        students_input=students_raw,
        start_date_value=start_date_value,
        end_date_value=end_date_value,
        constraint_fields=CONSTRAINT_FIELDS,
    )


@app.route('/define_shifts', methods=['GET', 'POST'])
def define_shifts():
    success = None
    error = None
    templates = shift_builder.list_templates()
    template_data = {t['slug']: shift_builder.load_template(t['slug']) for t in templates}

    if request.method == 'POST':
        template_name = request.form.get('template_name', '').strip()
        institution = request.form.get('institution', '').strip()
        slots_json = request.form.get('week_slots', '[]')
        slug = request.form.get('slug') or None

        if not template_name:
            error = 'Template name is required.'
        elif not institution:
            error = 'Institution name is required.'
        else:
            try:
                week_slots = json.loads(slots_json)
                sanitized_slots = []
                for slot in week_slots:
                    day_of_week = slot.get('day_of_week')
                    name = slot.get('name', '').strip()
                    start_time = slot.get('start_time', '').strip()
                    if not day_of_week or day_of_week not in shift_builder.DAY_NAME_TO_INDEX:
                        raise ValueError('Each shift requires a valid day of week.')
                    if not name:
                        raise ValueError('Each shift requires a name.')
                    if not start_time:
                        raise ValueError('Each shift requires a start time.')

                    duration_value = slot.get('duration_hours', 10)
                    block_value = slot.get('block_hours', duration_value)
                    try:
                        duration_hours = float(duration_value) if duration_value != '' else 10.0
                    except (TypeError, ValueError):
                        raise ValueError('Duration (hours) must be numeric.') from None
                    try:
                        block_hours = float(block_value) if block_value != '' else duration_hours
                    except (TypeError, ValueError):
                        raise ValueError('Block window (hours) must be numeric.') from None

                    sanitized_slots.append({
                        'day_of_week': day_of_week,
                        'name': name,
                        'category': slot.get('category', '').strip(),
                        'site': slot.get('site', '').strip(),
                        'start_time': start_time,
                        'duration_hours': duration_hours,
                        'block_hours': block_hours,
                        'is_overnight': bool(slot.get('is_overnight', False)),
                    })

                saved_slug = shift_builder.save_template(template_name, institution, sanitized_slots, slug=slug)
                success = f"Template '{template_name}' saved." if template_name else 'Template saved.'
                templates = shift_builder.list_templates()
                template_data = {t['slug']: shift_builder.load_template(t['slug']) for t in templates}
                # Pre-select the saved template
                return render_template(
                    'define_shifts.html',
                    templates=templates,
                    template_data=template_data,
                    success=success,
                    error=None,
                    selected_slug=saved_slug,
                )
            except Exception as exc:  # pylint: disable=broad-exception-caught
                error = str(exc)

    return render_template(
        'define_shifts.html',
        templates=templates,
        template_data=template_data,
        success=success,
        error=error,
        selected_slug=request.args.get('select'),
    )


@app.route('/download_shifts')
def download_shifts():
    shifts_path = os.path.join(app.config['UPLOAD_FOLDER'], 'shifts.json')
    if os.path.exists(shifts_path):
        return send_file(shifts_path, as_attachment=True)
    flash('shifts.json file not found.')
    return redirect(url_for('define_shifts'))


@app.route('/download')
def download_csv():
    csv_path = os.path.join(app.config['UPLOAD_FOLDER'], 'schedule_table.csv')
    if os.path.exists(csv_path):
        return send_file(csv_path, as_attachment=True)
    flash('CSV file not found.')
    return redirect(url_for('index'))


if __name__ == '__main__':
    app.run(debug=True)
