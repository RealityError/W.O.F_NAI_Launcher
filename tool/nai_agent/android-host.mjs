// One libnode instance, isolated Pi hosts per Flutter transport.
import { Worker } from 'node:worker_threads';
import { createInterface } from 'node:readline';

const hosts = new Map();
const send = (transportId, message) => process.stdout.write(
  JSON.stringify({ ...message, transportId }) + '\n');

function close(transportId) {
  const host = hosts.get(transportId);
  if (!host) return;
  hosts.delete(transportId);
  host.lines.close();
  void host.worker.terminate();
}

function start(transportId) {
  // A Worker owns its module globals, model registration, stdin and session.
  // Closing translation must never reinitialize or shut down the Studio host.
  const worker = new Worker(new URL('./host.mjs', import.meta.url), {
    stdin: true, stdout: true, stderr: true,
    env: { ...process.env, NAI_HOST_REINIT: '0' },
  });
  const lines = createInterface({ input: worker.stdout, crlfDelay: Infinity });
  const host = { worker, lines };
  hosts.set(transportId, host);
  const failed = () => {
    if (hosts.get(transportId) !== host) return;
    send(transportId, { type: 'transport_closed' });
    close(transportId);
  };
  lines.on('line', line => {
    if (hosts.get(transportId) !== host) return;
    try { send(transportId, JSON.parse(line)); }
    catch { failed(); }
  });
  // Runtime diagnostics can contain provider data; do not forward or persist.
  worker.stderr.resume();
  worker.on('error', failed);
  worker.on('exit', failed);
  worker.stdin.on('error', failed);
  return host;
}

const input = createInterface({ input: process.stdin, crlfDelay: Infinity });
input.on('line', line => {
  let message;
  try { message = JSON.parse(line); } catch { return; }
  const { transportId, ...payload } = message;
  if (typeof transportId !== 'string' || !/^[A-Za-z0-9_-]{1,80}$/.test(transportId)) return;
  if (payload.type === 'transport_close') { close(transportId); return; }
  try {
    const host = hosts.get(transportId)
      ?? (payload.type === 'init' ? start(transportId) : null);
    if (!host) { send(transportId, { type: 'transport_closed' }); return; }
    host.worker.stdin.write(JSON.stringify(payload) + '\n');
  } catch {
    send(transportId, { type: 'transport_closed' });
    close(transportId);
  }
});
input.on('close', () => {
  for (const transportId of hosts.keys()) close(transportId);
});
