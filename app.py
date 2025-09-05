from flask import Flask, render_template, request, redirect, url_for, flash, send_file
import os
import solve
import shift_builder 
from datetime import datetime

app = Flask(__name__)
app.secret_key = "supersecretkey"
UPLOAD_FOLDER = os.path.dirname(__file__)
app.config['UPLOAD_FOLDER'] = UPLOAD_FOLDER

@app.route('/', methods=['GET', 'POST'])
def index():
    result = None
    csv_ready = False
    if request.method == 'POST':
        students_raw = request.form.get('students', '')
        students = [s.strip() for s in students_raw.split(',') if s.strip()]
        if not students:
            flash('Please enter at least one student name.')
            return redirect(request.url)
        if 'shiftsfile' not in request.files:
            flash('No file part')
            return redirect(request.url)
        file = request.files['shiftsfile']
        if file.filename == '':
            flash('No selected file')
            return redirect(request.url)
        if file and file.filename.endswith('.json'):
            filepath = os.path.join(app.config['UPLOAD_FOLDER'], 'shifts.json')
            file.save(filepath)
            # Pass students to the solver
            result = solve.run_solver(filepath, students)
            csv_path = os.path.join(app.config['UPLOAD_FOLDER'], 'schedule_table.csv')
            csv_ready = os.path.exists(csv_path)
        else:
            flash('Please upload a .json file')
            return redirect(request.url)
    return render_template('index.html', result=result, csv_ready=csv_ready)

@app.route('/define_shifts', methods=['GET', 'POST'])
def define_shifts():
    shifts_ready = False
    error = None
    if request.method == 'POST':
        start_date_str = request.form.get('start_date')
        end_date_str = request.form.get('end_date')
        try:
            start_date = datetime.strptime(start_date_str, "%Y-%m-%d").date()
            end_date = datetime.strptime(end_date_str, "%Y-%m-%d").date()
            if start_date > end_date:
                error = "Start date must be before end date."
            else:
                # Call shift_builder to generate shifts.json
                shift_builder.save_shifts_json("shifts.json", shift_builder.build_shifts(start_date, end_date))
                shifts_ready = True
        except Exception as e:
            error = str(e)
    return render_template('define_shifts.html', shifts_ready=shifts_ready, error=error)

@app.route('/download_shifts')
def download_shifts():
    shifts_path = os.path.join(app.config['UPLOAD_FOLDER'], 'shifts.json')
    if os.path.exists(shifts_path):
        return send_file(shifts_path, as_attachment=True)
    else:
        flash('shifts.json file not found.')
        return redirect(url_for('define_shifts'))

@app.route('/download')
def download_csv():
    csv_path = os.path.join(app.config['UPLOAD_FOLDER'], 'schedule_table.csv')
    if os.path.exists(csv_path):
        return send_file(csv_path, as_attachment=True)
    else:
        flash('CSV file not found.')
        return redirect(url_for('index'))

if __name__ == '__main__':
    app.run(debug=True)