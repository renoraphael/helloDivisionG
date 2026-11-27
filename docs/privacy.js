'use strict';

window.HDGPrivacy = (() => {
  function element(tag, text, className) {
    const node = document.createElement(tag);
    if (text) node.textContent = text;
    if (className) node.className = className;
    return node;
  }

  function button(label, run, result) {
    const item = element('button', label, 'btn');
    item.type = 'button';
    item.addEventListener('click', async () => {
      item.disabled = true;
      try {
        await run();
      } catch (error) {
        result.textContent = error.message || 'The request could not be completed.';
      } finally {
        item.disabled = false;
      }
    });
    return item;
  }

  function status() {
    const item = element('p');
    item.setAttribute('role', 'status');
    return item;
  }

  function modal(label) {
    const box = element('dialog');
    box.setAttribute('aria-label', label);
    box.style.cssText = 'width:min(34rem,calc(100% - 2rem));max-height:85dvh;overflow:auto;padding:1.25rem;border-radius:12px;color:#162f43;background:#fff';
    box.append(element('h2', label));
    document.body.append(box);
    return box;
  }

  function noticeText(text) {
    const body = element('p', text);
    body.style.whiteSpace = 'pre-wrap';
    return body;
  }

  async function review(rpc, signOut) {
    let notice = await rpc('hdg_privacy_notice');
    if (!notice || notice.acceptedAt) return;
    const box = modal('Privacy notice');
    const version = element('p', 'Version ' + notice.version);
    const body = noticeText(notice.body);
    const result = status();
    box.addEventListener('cancel', event => event.preventDefault());
    await new Promise(resolve => {
      box.append(version, body, result, button('Accept notice', async () => {
        try {
          await rpc('hdg_accept_privacy_notice', {p_version: notice.version});
        } catch (error) {
          const current = await rpc('hdg_privacy_notice');
          if (!current || current.version === notice.version) throw error;
          notice = current;
          version.textContent = 'Version ' + current.version;
          body.textContent = current.body;
          result.textContent = 'The notice changed. Please read the updated version.';
          return;
        }
        box.close();
        box.remove();
        resolve();
      }, result), button('Sign out', signOut, result));
      box.showModal();
    });
  }

  function download(data) {
    const url = URL.createObjectURL(new Blob([JSON.stringify(data, null, 2)], {type: 'application/json'}));
    const link = element('a');
    link.href = url;
    link.download = 'hello-division-g-my-data.json';
    document.body.append(link);
    link.click();
    link.remove();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  }

  const formatDate = value => new Intl.DateTimeFormat(undefined, {dateStyle: 'medium', timeStyle: 'short'}).format(new Date(value));

  async function showSettings(rpc, signOut) {
    await review(rpc, signOut);
    const [info, notice] = await Promise.all([rpc('hdg_my_privacy'), rpc('hdg_privacy_notice')]);
    const box = modal('Privacy and your data');
    box.addEventListener('close', () => box.remove(), {once: true});
    const result = status();
    const deletion = element('p');
    const updateDeadline = request => {
      deletion.textContent = 'Deletion requested. Due ' + formatDate(request.due_at) + '.';
    };
    if (notice) {
      const details = element('details');
      details.append(element('summary', 'Privacy notice · ' + notice.version), noticeText(notice.body));
      box.append(details);
    }
    box.append(button('Export my data', async () => {
      const data = await rpc('hdg_export_my_data');
      download(data);
      result.textContent = data.legacyRecordsRequireReview
        ? 'Export downloaded. Some legacy records require a separate review.'
        : 'Your data export was downloaded.';
    }, result));
    if (info.profileCount) {
      box.append(button('Remove details I added', async () => {
        if (!window.confirm('Remove your nickname, other names, pronunciation, and profile photo?')) return;
        await rpc('hdg_remove_my_details');
        result.textContent = 'Your profile details were removed.';
      }, result));
    }
    box.append(deletion);
    if (info.pending) {
      updateDeadline(info.pending);
    } else if (info.activeMembership) {
      deletion.textContent = 'You can request full deletion after your last active membership ends.';
    } else {
      const requestButton = button('Request full deletion', async () => {
        if (!window.confirm('Send a request to delete your account and personal records?')) return;
        updateDeadline(await rpc('hdg_request_deletion'));
        requestButton.remove();
      }, result);
      box.append(requestButton);
    }
    box.append(result, button('Close', () => box.close(), result));
    box.showModal();
  }

  function mountQueue(rpc, anchor) {
    if (!anchor || document.getElementById('hdg-privacy-queue')) return;
    const panel = element('section', '', 'card');
    panel.id = 'hdg-privacy-queue';
    panel.append(element('h3', 'Privacy deletion requests'));
    const result = status();
    const items = element('ul');
    async function load() {
      const queue = await rpc('hdg_privacy_deletion_queue');
      items.replaceChildren();
      result.textContent = queue.length ? '' : 'No pending deletion requests.';
      for (const item of queue) {
        const overdue = new Date(item.dueAt) < new Date();
        const row = element('li');
        row.append(element('strong', item.email || 'Account'),
          element('p', 'Requested ' + formatDate(item.requestedAt) + ' · ' +
            (overdue ? 'Overdue since ' : 'Due ') + formatDate(item.dueAt)));
        if (item.blocked) {
          const reason = {
            active: 'Active membership',
            legacy: 'Legacy records require review',
            maintainer: 'Maintainer account',
          }[item.blocked];
          row.append(element('p', reason || 'Review required'));
        } else {
          row.append(button('Complete deletion', async () => {
            if (!window.confirm('Permanently erase this account and eligible records?')) return;
            await rpc('hdg_complete_deletion', {p_request: item.id});
            await load();
          }, result));
        }
        items.append(row);
      }
    }
    panel.append(button('Load deletion requests', load, result), result, items);
    anchor.before(panel);
  }

  async function mount(rpc, signOut) {
    if (document.getElementById('hdg-privacy-settings')) return;
    const panel = element('section', '', 'card');
    panel.id = 'hdg-privacy-settings';
    const result = status();
    panel.append(button('Privacy and your data', () => showSettings(rpc, signOut), result), result);
    const settings = document.getElementById('settings');
    if (!settings) panel.style.cssText = 'position:fixed;inset:auto 1rem 1rem auto;z-index:1000';
    (settings || document.body).append(panel);
    const reports = document.getElementById('reportTable');
    if (reports && (await rpc('hdg_my_privacy')).maintainer) mountQueue(rpc, reports);
  }

  return {review, mount};
})();
