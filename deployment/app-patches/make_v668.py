#!/usr/bin/env python3
"""Build a private rollback-compatibility preview with owner-only tasks."""
import argparse
from hashlib import sha256
from pathlib import Path

APP = '<title>Hello Division G! v667 Preview</title>'
OLD_TASKS = '      <details class="editor-disclosure tasks-editor no-print" id="taskEditorDisclosure">'
BRIDGE = "cloud.accountId=()=>session&&session.user&&session.user.id||'';"
BRIDGE_METHODS = """
cloud.privateTasks=()=>request('/rest/v1/hdg_personal_tasks?division_code=eq.G&select=id,area_code,year_start,title,notes,due_on,completed,updated_at&order=completed.asc,due_on.asc.nullslast,id.asc');
cloud.savePrivateTask=row=>request('/rest/v1/rpc/hdg_save_personal_task',{
 p_id:row.id||null,p_division:'G',p_year:row.year_start||null,p_area:row.area_code||null,
 p_title:row.title,p_notes:row.notes,p_due:row.due_on,p_completed:row.completed,p_expected_at:row.updated_at||null
});
cloud.deletePrivateTask=row=>request('/rest/v1/rpc/hdg_delete_personal_task',{
 p_id:row.id,p_expected_at:row.updated_at
});"""
PANEL = '''      <section class="card tasks-editor" aria-labelledby="hdgPrivateTaskTitle">
        <div class="tasks-section-head">
          <h2 id="hdgPrivateTaskTitle">My private tasks</h2>
          <button id="hdgPrivateTaskRefresh" class="btn ghost" type="button">Refresh tasks</button>
        </div>
        <p id="hdgPrivateTaskStatus" role="status">Refresh to load your tasks.</p>
        <form id="hdgPrivateTaskForm">
          <fieldset>
            <div class="form-grid">
              <label class="field">Task<input name="title" required maxlength="200"></label>
              <label class="field">Due date<input name="due" type="date"></label>
              <label class="field">Notes<textarea name="notes" maxlength="4000" rows="2"></textarea></label>
            </div>
            <button type="submit" class="btn primary">Add private task</button>
          </fieldset>
        </form>
        <ul id="hdgPrivateTaskList"></ul>
      </section>
'''


def build(source):
    for marker in (APP, OLD_TASKS, BRIDGE):
        if source.count(marker) != 1:
            raise ValueError('Unexpected v667 structure')
    first = source.index(OLD_TASKS)
    last = source.index('</details>', first) + len('</details>')
    source = source[:first] + PANEL + source[last:]
    source = source.replace(APP, APP.replace('v667', 'v668'))
    source = source.replace(BRIDGE, BRIDGE + BRIDGE_METHODS)
    # The embedded connected client also preserves its pending queue on pause.
    auth_catch = "   else if(error.status===401||error.status===403){this.status('Sign in or officer approval is required. Local changes are preserved.','auth');}"
    if source.count(auth_catch) != 1:
        raise ValueError('Unexpected shared save queue structure')
    source = source.replace(auth_catch, "   else if(error.code==='PT503'){this.status('Division G leader saves are paused. Your edits are saved on this device and will retry automatically.','offline');}\n" + auth_catch)
    end = source.lower().rindex('</body>')
    script = Path(__file__).with_name('leader-cutover').joinpath('private-tasks.js').read_text()
    return source[:end] + '<script id="hdg-v668-private-tasks">\n' + script + '</script>\n' + source[end:]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('source_sha256')
    args = parser.parse_args()
    source = args.source.read_bytes()
    if sha256(source).hexdigest() != args.source_sha256:
        raise SystemExit('Unexpected v667 source hash')
    preview = build(source.decode('utf-8')).encode('utf-8')
    with args.output.open('xb') as output:
        output.write(preview)
    print(f'Private v668 preview built. SHA-256 {sha256(preview).hexdigest()}')


if __name__ == '__main__':
    main()
