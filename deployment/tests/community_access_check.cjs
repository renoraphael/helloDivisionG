const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const source = fs.readFileSync(new URL('../../docs/cloud-sync.js', 'file://' + __filename), 'utf8');

function fixture(mode, path = '') {
  const requests = [];
  const writes = [];
  const nodes = new Map();
  class Element {
    constructor() {
      this.children = [];
      this.classList = { add() {}, remove() {} };
    }
    set innerHTML(value) {
      for (const match of value.matchAll(/id="([^"]+)"/g)) nodes.set(match[1], new Element());
    }
    appendChild(node) {
      if (node.id) nodes.set(node.id, node);
      this.append(node);
    }
    append(...nodes) { this.children.push(...nodes); }
    remove() {}
    querySelector() { return this.heading ??= new Element(); }
    addEventListener() {}
    get childElementCount() { return this.children.length; }
  }
  const body = new Element();
  const confirmed = {
    access_token: 'fixture-token', expires_at: Date.now() / 1000 + 3600, user: { id: 'fixture' }
  };
  const context = {
    HDG_ENTRY_LOADER: true, URLSearchParams, Date, structuredClone,
    crypto: { randomUUID: () => 'fixture-request-id' },
    location: { search: path, hash: '', protocol: 'https:' },
    sessionStorage: { getItem: key => mode && key==='hdg.cloud.session.v1' ? JSON.stringify(confirmed) : null },
    document: {
      body, getElementById: id => nodes.get(id), createElement: () => new Element(),
      open() {}, write(html) { writes.push(html); }, close() {}, addEventListener() {}
    },
    setInterval() {}, addEventListener() {},
    async fetch(url, options) {
      requests.push({ url, headers: options.headers });
      const route = new URL(url).pathname;
      return {
        ok: true,
        json: async () => {
          if (route.endsWith('hdg_access_mode')) return mode;
          if (route.endsWith('hdg_member_community')) return { clubs: [{ name: 'Fixture Club' }], meetings: [] };
          if (route.endsWith('hdg_sync_state')) return [{ revision: 1 }];
          if (route.endsWith('hdg_open_ballot')) return { title: 'Fixture ballot', choices: {} };
          throw new Error('Unexpected request ' + route);
        },
        text: async () => '<html>hdg-cloud-adapter window.__HDG_APP_RELEASE__="v632-community";</html>'
      };
    }
  };
  context.window = context;
  vm.runInNewContext(source, context);
  return { requests, writes, nodes, body, cloud: context.HDGCloud };
}

async function verifyCacheOrder() {
  const { serializeCacheWrites } = require('../../docs/cloud-sync.js');
  const events = [];
  let finishFirst;
  const write = serializeCacheWrites(async value => {
    events.push('start ' + value);
    if (value === 'startup') await new Promise(resolve => { finishFirst = resolve; });
    events.push('finish ' + value);
    if (value === 'failed') throw Error('fixture write error');
  });
  const first = write('startup');
  const second = write('server');
  await Promise.resolve();
  assert.deepEqual(events, ['start startup']);
  finishFirst();
  await Promise.all([first, second]);
  assert.deepEqual(events, ['start startup', 'finish startup', 'start server', 'finish server']);
  await assert.rejects(write('failed'));
  await write('next');
  assert.equal(events.at(-1), 'finish next');
}

async function main() {
  await verifyCacheOrder();
  let app = fixture(null, '?view=signup');
  await app.cloud.boot();
  assert.equal(app.nodes.get('hdg-sign-in').textContent, 'Create account');
  assert.equal(app.nodes.get('hdg-password').autocomplete, 'new-password');
  assert.equal(app.requests.length, 0);

  app = fixture('none');
  await app.cloud.boot();
  assert.equal(app.requests.length, 1);
  assert.match(app.nodes.get('hdg-auth-message').textContent, /not matched/);
  assert.equal(app.writes.length, 0);

  app = fixture('member');
  await app.cloud.boot();
  assert.equal(app.requests.length, 2);
  assert.match(app.requests[1].url, /hdg_member_community$/);
  assert.equal(app.writes.length, 0);
  assert.equal(app.body.children.at(-1).className, 'hdg-member-community');

  app = fixture('leader');
  await app.cloud.boot();
  assert.equal(app.requests.length, 3);
  assert.match(app.requests[2].url, /v632-community\.html$/);
  assert.equal(app.requests[2].headers.Authorization, 'Bearer fixture-token');
  assert.equal(app.writes.length, 1);

  app = fixture(null);
  const ballot = await app.cloud.openBallot('fixture-token');
  assert.equal(ballot.title, 'Fixture ballot');
  assert.equal(app.requests[0].headers.Authorization, undefined);
  console.log('PASS: sign-up, unmatched login, member-only request, protected leader load, and anonymous ballot');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
