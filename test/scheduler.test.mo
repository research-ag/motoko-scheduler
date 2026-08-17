import { test } "mo:test";

import Scheduler "../src/lib";

let NANOS_PER_SECOND : Nat64 = 1_000_000_000;

test(
  "nextExecutionAt: aligned to epoch with no bias",
  func() {
    // Interval of 60s, no bias: ticks at 60, 120, 180, ...
    assert Scheduler.nextExecutionAt(90 * NANOS_PER_SECOND, 60, 0) == 120 * NANOS_PER_SECOND;
    // Strictly after the current time: at t = 0 the next tick is at t = 60.
    assert Scheduler.nextExecutionAt(0, 60, 0) == 60 * NANOS_PER_SECOND;
    // Exactly on a boundary: the next tick is the following one.
    assert Scheduler.nextExecutionAt(60 * NANOS_PER_SECOND, 60, 0) == 120 * NANOS_PER_SECOND;
  },
);

test(
  "nextExecutionAt: shifted by a bias",
  func() {
    // Interval of 60s, bias of 30s: ticks at 30, 90, 150, ...
    assert Scheduler.nextExecutionAt(90 * NANOS_PER_SECOND, 60, 30) == 150 * NANOS_PER_SECOND;
    assert Scheduler.nextExecutionAt(100 * NANOS_PER_SECOND, 60, 30) == 150 * NANOS_PER_SECOND;
    assert Scheduler.nextExecutionAt(40 * NANOS_PER_SECOND, 60, 30) == 90 * NANOS_PER_SECOND;
  },
);

test(
  "nextExecutionAt: ignores the sub-second part of now",
  func() {
    // Any time within [60, 120) maps to the same next tick at 120.
    assert Scheduler.nextExecutionAt(61 * NANOS_PER_SECOND, 60, 0) == 120 * NANOS_PER_SECOND;
    assert Scheduler.nextExecutionAt(119 * NANOS_PER_SECOND + 999_999_999, 60, 0) == 120 * NANOS_PER_SECOND;
  },
);

test(
  "initialDelaySeconds: aligned to epoch with no bias",
  func() {
    // At t = 90s the next 60s boundary (120s) is 30s away.
    assert Scheduler.initialDelaySeconds(90 * NANOS_PER_SECOND, 60, 0) == 30;
    // Exactly on a boundary waits a full interval.
    assert Scheduler.initialDelaySeconds(60 * NANOS_PER_SECOND, 60, 0) == 60;
  },
);

test(
  "initialDelaySeconds: shifted by a bias",
  func() {
    // Ticks at 30, 90, 150, ...; at t = 100s the next tick (150s) is 50s away.
    assert Scheduler.initialDelaySeconds(100 * NANOS_PER_SECOND, 60, 30) == 50;
    // At t = 90s (exactly on a tick) the next tick is a full interval away.
    assert Scheduler.initialDelaySeconds(90 * NANOS_PER_SECOND, 60, 30) == 60;
  },
);

test(
  "initialDelaySeconds and nextExecutionAt agree",
  func() {
    // The delay must land exactly on the next execution timestamp.
    let now = 12_345 * NANOS_PER_SECOND;
    let interval : Nat64 = 3_600;
    let bias : Nat64 = 120;
    let delay = Scheduler.initialDelaySeconds(now, interval, bias);
    let next = Scheduler.nextExecutionAt(now, interval, bias);
    assert now / NANOS_PER_SECOND * NANOS_PER_SECOND + delay * NANOS_PER_SECOND == next;
  },
);

test(
  "large interval: daily alignment",
  func() {
    // One-day interval, no bias: any time on a given day maps to the next
    // midnight.
    let secondsPerDay : Nat64 = 86_400;
    let now = (secondsPerDay + 45_000) * NANOS_PER_SECOND; // midway through day 1
    assert Scheduler.nextExecutionAt(now, secondsPerDay, 0) == 2 * secondsPerDay * NANOS_PER_SECOND;
    assert Scheduler.initialDelaySeconds(now, secondsPerDay, 0) == secondsPerDay - 45_000;
  },
);
