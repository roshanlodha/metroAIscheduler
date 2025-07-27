# MetroAI Scheduler

Automated shift scheduling for acting interns at Metro/CCF rotation.

## Overview

This tool generates optimal shift assignments for a group of students (acting interns) rotating through Metro and CCF, subject to a set of scheduling constraints. For each student, an individual `.ics` calendar file is produced, which can be imported into most calendar applications.

## Features

- Automatically assigns shifts to students based on customizable constraints.
- Generates `.ics` calendar files for each student, including orientation and conference events.
- Prints a summary of each student's schedule to the console for quick inspection.

## Requirements

- Python 3.8+
- [Google OR-Tools](https://developers.google.com/optimization) (`pip install ortools`)
- [icalendar](https://pypi.org/project/icalendar/) (`pip install icalendar`)
- [pytz](https://pypi.org/project/pytz/) (`pip installed with icalendar by default`)

## Setup

1. **Clone the repository** and navigate to the project directory.
2. **(Optional but recommended)**: Create and activate a Python virtual environment:
    ```sh
    python3 -m venv env
    source env/bin/activate
    ```
3. **Install dependencies**:
    ```sh
    pip install ortools icalendar
    ```

## Usage

Run the scheduler with:
```sh
python solve.py
```
This will generate a `.ics` file for each student in the current directory.

## Configuration

- **Students**:  
  Edit the `students` list near the top of `solve.py` to specify the names of the acting interns.

- **Rotation Dates**:  
  Adjust `start_date` and `end_date` in `solve.py` to set the rotation window.

- **Shifts and Constraints**:  
  Shift definitions and scheduling constraints are defined in `solve.py`. These can be modified if needed, but the defaults are set for typical Metro/CCF rotations.

## Output

- For each student, a file named `<student>_schedule.ics` will be created.
- The script also prints a summary of each student's assigned shifts to the console.

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.

## Credits

Developed by Roshan Lodha.
