# Epoch-aligned recurring scheduler for Motoko

## Overview

`motoko-scheduler` provides a recurring timer whose executions are **aligned to
the Unix epoch** rather than to the moment the scheduler is started. A daily
scheduler therefore fires at every midnight (UTC), a minutely scheduler fires at
the top of every minute, and so on — no matter when `start` was called. The
alignment can be shifted with a `biasSeconds` offset (e.g. interval `60`, bias
`30` fires at the 30th second of every minute).

The package exposes:

- `Scheduler` — a class wrapping a self-re-arming timer that runs an
  asynchronous handler on every aligned tick, serializing executions so a new
  run never overlaps a previous one;
- `nextExecutionAt` / `initialDelaySeconds` — the underlying epoch-alignment
  arithmetic as **pure functions** that take the current time explicitly, so the
  alignment logic can be unit-tested without a running timer.

### Links

The package is published on [MOPS](https://mops.one/motoko-scheduler) and [GitHub](https://github.com/research-ag/motoko-scheduler).

The API documentation can be found [here](https://mops.one/motoko-scheduler/docs).

For updates, help, questions, feedback and other requests related to this package join us on:

- [OpenChat group](https://oc.app/2zyqk-iqaaa-aaaar-anmra-cai)
- [Twitter](https://twitter.com/mr_research_ag)
- [Dfinity forum](https://forum.dfinity.org/)

### Motivation

Naively re-arming a `recurringTimer` makes ticks drift relative to wall-clock
time: they happen `interval` after the _start_ time, which is arbitrary. Many
workloads (auction sessions, consolidation jobs, daily snapshots, hourly
reports) want ticks that land on predictable, epoch-aligned boundaries and stay
put across canister upgrades and restarts. This package encapsulates that
alignment math and the "don't overlap a still-running handler" bookkeeping.

### Interface

```motoko
module {
  // Pure epoch-alignment arithmetic (current time passed explicitly).
  public func nextExecutionAt(
    nowNanos : Nat64,
    intervalSeconds : Nat64,
    biasSeconds : Nat64,
  ) : Nat64; // next aligned tick, in nanoseconds since the epoch

  public func initialDelaySeconds(
    nowNanos : Nat64,
    intervalSeconds : Nat64,
    biasSeconds : Nat64,
  ) : Nat64; // seconds until the next aligned tick

  public class Scheduler(
    intervalSeconds : Nat64,
    biasSeconds : Nat64,
    handler : (counter : Nat) -> async* (),
  ) {
    public func timerId() : ?Nat;
    public func isExecutingHandler() : Bool;
    public func isRunning() : Bool;
    public func nextExecutionAt() : Nat64;
    public func startImmediately<system>() : async* ();
    public func start<system>() : ();
    public func stop() : ();
  };
};

```

## Usage

### Install with mops

You need `mops` installed. In your project directory run:

```
mops add motoko-scheduler
```

In the Motoko source file import the package as:

```
import Scheduler "mo:motoko-scheduler";
```

### Example

```motoko
import Scheduler "mo:motoko-scheduler";

persistent actor {
  // Consolidate backlog every minute, at the 30th second.
  transient let consolidation = Scheduler.Scheduler(
    60,
    30,
    func(counter : Nat) : async* () {
      // ... perform the recurring work; `counter` starts at 0 on each start ...
    },
  );

  consolidation.start<system>();

  // Query when the next tick is scheduled (nanoseconds since the epoch).
  public query func nextTick() : async Nat64 {
    consolidation.nextExecutionAt();
  };
};

```

The pure alignment functions can be used (and tested) on their own:

```motoko
import Scheduler "mo:motoko-scheduler";

// Interval of 60s, no bias: at t = 90s the next tick is at t = 120s, 30s away.
assert Scheduler.nextExecutionAt(90 * 1_000_000_000, 60, 0) == 120 * 1_000_000_000;
assert Scheduler.initialDelaySeconds(90 * 1_000_000_000, 60, 0) == 30;

```

### Build & test

We need up-to-date versions of `node`, `moc` and `mops` installed.

Then run:

```
git clone git@github.com:research-ag/motoko-scheduler.git
mops install
mops test
```

### Format the code

We use `prettier` with the `prettier-plugin-motoko` plugin (configured in `.prettierrc`). The CI checks formatting on every pull request.

To format the code locally run:

```
npx -y prettier --plugin prettier-plugin-motoko --write '**/*.{mo,json,md}'
```

To only check the formatting (as CI does) run:

```
npx -y prettier --plugin prettier-plugin-motoko --check '**/*.{mo,json,md}'
```

## Design

Ticks occur at the times `biasSeconds + k * intervalSeconds` seconds since the
epoch, for integer `k`. Given the current time `nowNanos`:

- `nextExecutionAt` returns the first such tick **strictly after** `nowNanos`
  (a time sitting exactly on a boundary maps to the following boundary), so
  repeatedly calling it never returns the same tick twice.
- `initialDelaySeconds` returns how long to wait before the very first
  execution so it lands on an aligned boundary; the `Scheduler` uses it to arm a
  one-shot timer, and once that fires it installs a `recurringTimer` at the
  fixed `intervalSeconds` cadence.

The `Scheduler` serializes handler runs: `handlerInternal` takes an execution
lock (`isExecutingHandler`) and refuses to start a new run while a previous one
is in flight. Each run receives a zero-based `counter` that is reset on every
`start` / `startImmediately`.

## Implementation notes

- Timestamps are `Nat64` nanoseconds since the epoch (matching the system time).
  Intervals, biases and delays are expressed in whole seconds.
- Both pure functions divide by `intervalSeconds`, so they **trap** when it is
  `0`, and subtract `biasSeconds` from `nowNanos`, so they trap on `Nat64`
  underflow when `nowNanos` is smaller than `biasSeconds` (not a concern for
  real wall-clock timestamps).
- `startImmediately` swallows any error thrown by the first (immediate) run so
  that the recurring timer is still armed afterwards.
- `stop` cancels the recurring timer but does not interrupt a handler run that
  is already in flight.

## Copyright

MR Research AG, 2026

## Authors

Main author: AndyGura
Contributors: TimoHanke

## License

Apache-2.0
