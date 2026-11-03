#!/usr/bin/env node
/**
 * Parser tests for Jot — no dependencies.
 *
 * The parser lives inside index.html (single-file app), so we slice it out
 * between the `#region parser` markers and evaluate it with the few helpers
 * it depends on. Run: node test/parser.test.js
 */
'use strict';

const fs = require('fs');
const path = require('path');

const html = fs.readFileSync(path.join(__dirname, '..', 'index.html'), 'utf8');
const start = html.indexOf('/* #region parser');
const end = html.indexOf('/* #endregion parser');
if (start < 0 || end < 0) {
  console.error('parser region markers not found in index.html');
  process.exit(1);
}

const source = html.slice(start, end);

// Minimal copies of the helpers defined outside the region.
function pad(n) { return n < 10 ? '0' + n : '' + n; }
function startOfDay(d) { return new Date(d.getFullYear(), d.getMonth(), d.getDate()); }
function daysInMonth(y, m) { return new Date(y, m + 1, 0).getDate(); }
const WEEK_CN = '日一二三四五六';
const settings = { lang: 'en' };

const build = new Function(
  'settings', 'WEEK_CN', 'pad', 'startOfDay', 'daysInMonth',
  source + '\nreturn { parseQuick: parseQuick };'
);
const parser = build(settings, WEEK_CN, pad, startOfDay, daysInMonth);

// Tuesday, 3 Nov 2026, 10:00 local time
const NOW = new Date(2026, 10, 3, 10, 0, 0, 0);

function fmt(ms) {
  if (ms === null || ms === undefined) return null;
  const d = new Date(ms);
  return d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate()) +
         ' ' + pad(d.getHours()) + ':' + pad(d.getMinutes());
}

let pass = 0;
const failures = [];

function check(lang, input, expect) {
  settings.lang = lang;
  const r = parser.parseQuick(input, NOW);
  const got = {
    due: fmt(r.due),
    title: r.title,
    repeat: r.repeat,
    weekday: r.repeatWeekday,
    monthDay: r.repeatMonthDay
  };
  const ok = got.due === expect.due &&
             (expect.title === undefined || got.title === expect.title) &&
             (expect.repeat === undefined || got.repeat === expect.repeat) &&
             (expect.weekday === undefined || got.weekday === expect.weekday) &&
             (expect.monthDay === undefined || got.monthDay === expect.monthDay);
  if (ok) { pass++; return; }
  failures.push({ lang, input, expect, got });
}

/* ---------------- English (default) ---------------- */

check('en', 'pay rent tomorrow 9am',            { due: '2026-11-04 09:00', title: 'pay rent' });
check('en', 'water in 30 min',                   { due: '2026-11-03 10:30', title: 'water' });
check('en', 'in 2 hours take the cake out',      { due: '2026-11-03 12:00', title: 'take the cake out' });
check('en', 'in 3 days pay the deposit',         { due: '2026-11-06 10:00', title: 'pay the deposit' });
check('en', 'call mom at 8pm',                   { due: '2026-11-03 20:00', title: 'call mom' });
check('en', '9pm dinner with Sam',               { due: '2026-11-03 21:00', title: 'dinner with Sam' });
check('en', 'tomorrow at 9:30pm pack bags',      { due: '2026-11-04 21:30', title: 'pack bags' });
check('en', 'dentist on friday 3pm',             { due: '2026-11-06 15:00', title: 'dentist' });
check('en', 'next wednesday 8pm gym',            { due: '2026-11-04 20:00', title: 'gym' });
check('en', 'flight Oct 31 3pm',                 { due: '2027-10-31 15:00', title: 'flight' });
check('en', 'standup every Monday 10am',         { due: '2026-11-09 10:00', title: 'standup', repeat: 'weekly', weekday: 1 });
check('en', 'take meds every day 8am',           { due: '2026-11-04 08:00', title: 'take meds', repeat: 'daily' });
check('en', 'every month on the 5th pay the bill', { due: '2026-11-05 09:00', title: 'pay the bill', repeat: 'monthly', monthDay: 5 });
check('en', 'remind me to call the plumber tomorrow 9am', { due: '2026-11-04 09:00', title: 'call the plumber' });
check('en', 'buy milk',                          { due: null, title: 'buy milk', repeat: 'none' });
check('en', 'tomorrow 9am',                      { due: '2026-11-04 09:00' });

/* ---------------- Chinese ---------------- */

check('zh', '明天 9 点 交房租',        { due: '2026-11-04 09:00', title: '交房租' });
check('zh', '30 分钟后 喝水',          { due: '2026-11-03 10:30', title: '喝水' });
check('zh', '每周一 10 点 例会',       { due: '2026-11-09 10:00', title: '例会', repeat: 'weekly', weekday: 1 });
check('zh', '每天 8 点 吃药',          { due: '2026-11-04 08:00', title: '吃药', repeat: 'daily' });
check('zh', '后天 下午 3 点 交材料',   { due: '2026-11-05 15:00', title: '交材料' });
check('zh', '下周三 晚 8 点 健身',     { due: '2026-11-11 20:00', title: '健身' });
check('zh', '今晚 8 点 倒垃圾',        { due: '2026-11-03 20:00', title: '倒垃圾' });
check('zh', '10 月 31 日下午 3 点 交材料', { due: '2027-10-31 15:00', title: '交材料' });
check('zh', '买牛奶',                  { due: null, title: '买牛奶' });

/* ---------------- mixed: English UI, Chinese input ---------------- */

check('en', '明天 9 点 交房租', { due: '2026-11-04 09:00', title: '交房租' });

/* ---------------- report ---------------- */

if (failures.length) {
  console.log('\nFAILED ' + failures.length + ' / ' + (pass + failures.length) + '\n');
  failures.forEach(function (f) {
    console.log('  [' + f.lang + '] ' + JSON.stringify(f.input));
    console.log('    expected: ' + JSON.stringify(f.expect));
    console.log('    got     : ' + JSON.stringify(f.got) + '\n');
  });
  process.exit(1);
}
console.log('parser: ' + pass + ' cases passed');
