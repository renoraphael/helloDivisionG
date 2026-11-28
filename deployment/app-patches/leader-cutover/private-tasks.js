(() => {
  const form = document.getElementById('hdgPrivateTaskForm');
  if (!form) return;
  const status = document.getElementById('hdgPrivateTaskStatus');
  const list = document.getElementById('hdgPrivateTaskList');
  const refresh = document.getElementById('hdgPrivateTaskRefresh');
  const cloud = window.HDGCloud;
  let busy = false;

  async function run(action) {
    if (busy) return;
    const account = cloud?.accountId?.();
    if (!account) {
      list.replaceChildren();
      status.textContent = 'Sign in to load your tasks.';
      return;
    }
    busy = true;
    form.querySelector('fieldset').disabled = true;
    refresh.disabled = true;
    for (const button of list.querySelectorAll('button')) button.disabled = true;
    let message = '';
    try {
      if (action && !await action()) message = 'This task changed elsewhere. The latest version is shown.';
      const rows = await cloud.privateTasks();
      if (account !== cloud.accountId()) return;
      list.replaceChildren(...rows.map(taskRow));
      status.textContent = message || (rows.length ? '' : 'No private tasks yet.');
    } catch (_) {
      if (account === cloud.accountId()) status.textContent = 'Could not confirm the request. Refresh your tasks before retrying.';
    } finally {
      if (account !== cloud.accountId()) list.replaceChildren();
      busy = false;
      form.querySelector('fieldset').disabled = false;
      refresh.disabled = false;
      for (const button of list.querySelectorAll('button')) button.disabled = false;
    }
  }

  function taskRow(task) {
    const item = document.createElement('li');
    const title = document.createElement('strong');
    title.textContent = task.title;
    item.append(title);
    if (task.due_on || task.notes) {
      const details = document.createElement('p');
      details.textContent = [task.due_on && 'Due ' + task.due_on, task.notes].filter(Boolean).join(' · ');
      item.append(details);
    }
    const completion = document.createElement('button');
    completion.type = 'button';
    completion.className = 'btn ghost';
    completion.textContent = task.completed ? 'Reopen' : 'Mark complete';
    completion.addEventListener('click', () => run(async () => {
      const saved = await cloud.savePrivateTask({...task, completed: !task.completed});
      return saved.applied;
    }));
    const remove = document.createElement('button');
    remove.type = 'button';
    remove.className = 'btn ghost';
    remove.textContent = 'Delete';
    remove.addEventListener('click', () => {
      if (window.confirm('Delete this private task?')) run(() => cloud.deletePrivateTask(task));
    });
    item.append(completion, remove);
    return item;
  }

  refresh.addEventListener('click', () => run());
  form.addEventListener('submit', event => {
    event.preventDefault();
    const values = new FormData(form);
    const title = String(values.get('title') || '').trim();
    if (!title) return;
    run(async () => {
      const saved = await cloud.savePrivateTask({title, notes: String(values.get('notes') || '').trim(),
        due_on: values.get('due') || null, completed: false});
      if (saved.applied) form.reset();
      return saved.applied;
    });
  });
})();
