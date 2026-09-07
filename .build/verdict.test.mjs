// Verdict policy — unit tests (node:test, dependency-free).
// Run: node --test .build/verdict.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { parseSelftest, classifyTitle, EARLY_EXIT_MS } from './verdict.mjs';

test('parseSelftest accepts a full-pass title', () => {
  assert.deepEqual(parseSelftest('SELFTEST 69/69'), { ok: true, count: 69, total: 69 });
});

test('parseSelftest rejects a partial pass (failures must fail CI)', () => {
  const r = parseSelftest('SELFTEST 68/69');
  assert.equal(r.ok, false);
  assert.equal(r.count, 68);
  assert.equal(r.total, 69);
});

test('parseSelftest rejects a non-selftest title', () => {
  const r = parseSelftest('FreeCam3D');
  assert.equal(r.ok, false);
  assert.match(r.reason, /marker/);
});

test('parseSelftest rejects an empty title', () => {
  assert.equal(parseSelftest('').ok, false);
});

test('parseSelftest rejects an empty run (0/0 must never pass CI)', () => {
  const r = parseSelftest('SELFTEST 0/0');
  assert.equal(r.ok, false);
  assert.match(r.reason, /0 checks/);
});

test('classifyTitle completes on a full pass', () => {
  const c = classifyTitle('SELFTEST 69/69', null, 0);
  assert.equal(c.done, true);
  assert.deepEqual(c.verdict, { ok: true, count: 69, total: 69 });
});

test('classifyTitle completes (as a failure) on a partial pass', () => {
  const c = classifyTitle('SELFTEST 68/69', null, 0);
  assert.equal(c.done, true);
  assert.equal(c.verdict.ok, false);
  assert.equal(c.verdict.count, 68);
});

test('classifyTitle stays pending on a fresh non-selftest title', () => {
  assert.equal(classifyTitle('FreeCam3D', null, 999999).done, false);
});

test('classifyTitle stays pending while a non-selftest title is changing', () => {
  assert.equal(classifyTitle('FreeCam3D', 'Another title', EARLY_EXIT_MS + 1000).done, false);
});

test('classifyTitle stays pending below the early-exit threshold', () => {
  assert.equal(classifyTitle('FreeCam3D', 'FreeCam3D', EARLY_EXIT_MS - 1).done, false);
});

test('classifyTitle fails a stable non-selftest title at the early-exit threshold', () => {
  const c = classifyTitle('FreeCam3D', 'FreeCam3D', EARLY_EXIT_MS);
  assert.equal(c.done, true);
  assert.equal(c.verdict.ok, false);
  assert.match(c.verdict.reason, /marker/);
});

test('classifyTitle completes (as a failure) on an empty-run verdict', () => {
  const c = classifyTitle('SELFTEST 0/0', null, 0);
  assert.equal(c.done, true);
  assert.equal(c.verdict.ok, false);
});