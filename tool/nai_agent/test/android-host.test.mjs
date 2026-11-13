import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createInterface } from 'node:readline';
import { createServer } from 'node:http';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { listenFetchTestServer } from './fixture-http.mjs';
import { finishReply } from './fixture-host.mjs';

test('Android host isolates concurrent Studio and translation sessions', { timeout: 60000 }, async () => {
  const root = await mkdtemp(join(tmpdir(), 'studio-android-host-'));
  const bodies = [], pending = new Map(), sessions = new Map(), events = [];
  let studioReply;
  const server = createServer(async (req, res) => {
    let body = ''; for await (const part of req) body += part;
    const request = JSON.parse(body); bodies.push(request);
    res.setHeader('Content-Type', 'text/event-stream');
    if (request.messages.some(message => message.content === 'studio-running'
      || Array.isArray(message.content) && message.content.some(part => part.text === 'studio-running'))) {
      studioReply = res;
    } else if (!request.messages.some(message => message.role === 'tool')) {
      res.end('data: ' + JSON.stringify({ id: 'test', object: 'chat.completion.chunk', model: 'test',
        choices: [{ index: 0, delta: { role: 'assistant', tool_calls: [{ index: 0, id: 'read-blocks',
          type: 'function', function: { name: 'mcp__nai_studio__translation_blocks_read', arguments: '{}' } }] },
          finish_reason: 'tool_calls' }],
      }) + '\n\ndata: [DONE]\n\n');
    } else finishReply(res, 'translation-done');
  });
  await listenFetchTestServer(server);
  const child = spawn(process.execPath, [fileURLToPath(new URL('../android-host.mjs', import.meta.url))],
    { stdio: ['pipe', 'pipe', 'pipe'] });
  let diagnostic = '', sequence = 0;
  child.stderr.on('data', data => { diagnostic += data; });
  const lines = createInterface({ input: child.stdout });
  const send = (transportId, fields) => child.stdin.write(JSON.stringify({
    protocol: 1, transportId, workspaceId: 'shared-workspace', sessionId: sessions.get(transportId), ...fields,
  }) + '\n');
  lines.on('line', line => {
    const message = JSON.parse(line); events.push(message);
    const transport = message.transportId;
    if (message.type === 'ready') sessions.set(transport, message.sessionId);
    if (message.type === 'request_permit') send(transport, { type: 'permit_result', requestId: message.requestId });
    if (message.type === 'tool_request') {
      assert.equal(transport, 'translation');
      assert.equal(message.name, 'translation_blocks_read');
      send(transport, { type: 'tool_result', toolCallId: message.toolCallId,
        result: { content: [{ type: 'text', text: '{"version":"v1","blocks":[]}' }] } });
    }
    const key = `${transport}/${message.id}`;
    if (['ready', 'response', 'error'].includes(message.type) && pending.has(key)) {
      const request = pending.get(key); pending.delete(key); clearTimeout(request.timer);
      message.type === 'error' ? request.reject(new Error(message.message)) : request.resolve(message);
    }
  });
  const request = (transport, type, fields = {}) => new Promise((resolve, reject) => {
    const id = String(++sequence), key = `${transport}/${id}`;
    const timer = setTimeout(() => { pending.delete(key); reject(new Error(`Timeout ${key}/${type}: ${diagnostic}`)); }, 20000);
    pending.set(key, { resolve, reject, timer }); send(transport, { id, type, ...fields });
  });
  const initialize = (transport, translation = false) => request(transport, 'init', {
    cwd: join(root, transport, 'workspace'), agentDir: join(root, transport, 'agent'),
    systemPrompt: 'Synthetic test only.',
    ...(translation ? { sessionKind: 'translation', seedSystemPrompt: 'original-system', seedMessages: [
      { role: 'user', content: 'original-request' }, { role: 'assistant', content: 'original-response' },
    ] } : {}),
    config: { providerId: 'test', modelId: 'test', protocol: 'openaiChatCompletions',
      baseUrl: `http://127.0.0.1:${server.address().port}`, tools: true, nextSuggestion: false },
  });
  try {
    await initialize('studio');
    const running = request('studio', 'prompt', { text: 'studio-running' });
    for (let i = 0; !studioReply && i < 1000; i++) await new Promise(resolve => setTimeout(resolve, 10));
    assert.ok(studioReply, JSON.stringify({ bodies, events, diagnostic }));
    await initialize('translation', true);
    await request('translation', 'prompt', { text: 'adjust-blocks' });
    assert.equal((await request('studio', 'state')).streaming, true);
    assert.ok(events.some(event => event.transportId === 'translation' && event.type === 'tool_request'));
    const translation = bodies.find(body => body.messages[0].content === 'original-system');
    assert.equal(translation.messages[1].content, 'original-request');
    assert.equal(translation.messages[2].content, 'original-response');
    assert.deepEqual(translation.tools.map(tool => tool.function.name).sort(), [
      'mcp__nai_studio__translation_blocks_edit', 'mcp__nai_studio__translation_blocks_read',
    ]);
    await request('translation', 'shutdown');
    send('translation', { type: 'transport_close' });
    finishReply(studioReply, 'studio-done');
    await running;
    assert.equal((await request('studio', 'state')).streaming, false);
    await initialize('translation-again', true);
    await request('translation-again', 'shutdown');
    await request('studio', 'shutdown');
  } finally {
    for (const request of pending.values()) clearTimeout(request.timer);
    lines.close(); child.kill();
    server.closeAllConnections(); await new Promise(resolve => server.close(resolve));
    await rm(root, { recursive: true, force: true, maxRetries: 20, retryDelay: 100 });
  }
});
