/// Epoch-aligned recurring scheduler for the Internet Computer.
///
/// A `Scheduler` runs an asynchronous handler on a recurring interval whose
/// tick times are *aligned to the Unix epoch* rather than to the moment the
/// scheduler was started. For example, a scheduler with a one-day interval
/// fires at every midnight (UTC) regardless of when `start` was called, and a
/// scheduler with a one-minute interval fires at the top of every minute. The
/// alignment can be shifted with a `biasSeconds` offset, e.g. an interval of
/// `60` with a bias of `30` fires at the 30th second of every minute.
///
/// The scheduler serializes executions: it never starts a new run of the
/// handler while a previous run is still in flight (`isExecutingHandler`
/// reports whether a run is currently active). Each run is passed a
/// monotonically increasing `counter` that is reset to `0` on every `start` /
/// `startImmediately`.
///
/// The module also exposes the underlying epoch-alignment arithmetic as pure
/// functions (`nextExecutionAt` and `initialDelaySeconds`) that take the
/// current time explicitly, so the alignment logic can be unit-tested without a
/// running timer.
///
/// ```motoko name=import
/// import Scheduler "mo:motoko-scheduler";
/// ```

import Nat64 "mo:core/Nat64";
import Option "mo:core/Option";
import Prim "mo:prim";
import Timer "mo:core/Timer";

module {

  // Number of nanoseconds in one second.
  let NANOS_PER_SECOND : Nat64 = 1_000_000_000;

  // Core epoch-alignment arithmetic, shared by the public `nextExecutionAt`
  // function and the `Scheduler.nextExecutionAt` method (which would otherwise
  // shadow the public function name inside the class body).
  func nextTickNanos(
    nowNanos : Nat64,
    intervalSeconds : Nat64,
    biasSeconds : Nat64,
  ) : Nat64 {
    let intervalNanos = intervalSeconds * NANOS_PER_SECOND;
    let biasNanos = biasSeconds * NANOS_PER_SECOND;
    let elapsedIntervals = (nowNanos - biasNanos) / intervalNanos;
    NANOS_PER_SECOND * (intervalSeconds * (1 + elapsedIntervals) + biasSeconds);
  };

  /// Computes the timestamp, in nanoseconds since the Unix epoch, of the next
  /// epoch-aligned execution strictly after `nowNanos`.
  ///
  /// Ticks occur at times `biasSeconds + k * intervalSeconds` (in seconds) for
  /// integer `k`, i.e. aligned to the epoch and shifted by `biasSeconds`. The
  /// returned value is the first such tick strictly greater than `nowNanos`.
  ///
  /// `nowNanos`: the current time in nanoseconds since the epoch (as returned
  /// by the system time).
  /// `intervalSeconds`: the recurrence interval in seconds; must be positive.
  /// `biasSeconds`: the alignment offset in seconds (`0` aligns exactly to the
  /// epoch).
  ///
  /// Example:
  /// ```motoko include=import
  /// // Interval of 60s, no bias: at t = 90s the next tick is at t = 120s.
  /// let next = Scheduler.nextExecutionAt(90 * 1_000_000_000, 60, 0);
  /// assert next == 120 * 1_000_000_000;
  /// ```
  ///
  /// Traps if `intervalSeconds` is `0` (division by zero) or if `nowNanos` is
  /// smaller than `biasSeconds` expressed in nanoseconds (`Nat64` subtraction
  /// underflow).
  public func nextExecutionAt(
    nowNanos : Nat64,
    intervalSeconds : Nat64,
    biasSeconds : Nat64,
  ) : Nat64 = nextTickNanos(nowNanos, intervalSeconds, biasSeconds);

  /// Computes the delay, in seconds, from `nowNanos` until the next
  /// epoch-aligned tick.
  ///
  /// This is the delay that the scheduler waits before its very first
  /// execution so that the first tick lands on an aligned boundary; subsequent
  /// ticks then repeat every `intervalSeconds`. When `nowNanos` already sits
  /// exactly on a boundary the result is a full `intervalSeconds` (the current
  /// boundary is considered already elapsed).
  ///
  /// `nowNanos`: the current time in nanoseconds since the epoch.
  /// `intervalSeconds`: the recurrence interval in seconds; must be positive.
  /// `biasSeconds`: the alignment offset in seconds.
  ///
  /// Example:
  /// ```motoko include=import
  /// // Interval of 60s, no bias: at t = 90s the next tick is 30s away.
  /// let delay = Scheduler.initialDelaySeconds(90 * 1_000_000_000, 60, 0);
  /// assert delay == 30;
  /// ```
  ///
  /// Traps if `intervalSeconds` is `0` (division by zero) or if the whole
  /// seconds of `nowNanos` are smaller than `biasSeconds` (`Nat64` subtraction
  /// underflow).
  public func initialDelaySeconds(
    nowNanos : Nat64,
    intervalSeconds : Nat64,
    biasSeconds : Nat64,
  ) : Nat64 {
    intervalSeconds - (nowNanos / NANOS_PER_SECOND - biasSeconds) % intervalSeconds;
  };

  /// A recurring timer whose executions are aligned to the Unix epoch.
  ///
  /// The scheduler fires `handler` every `intervalSeconds`, aligned so that
  /// ticks land at `biasSeconds + k * intervalSeconds` (e.g. an interval of one
  /// day fires at midnight regardless of when `start` was called). Use
  /// `biasSeconds` to shift the alignment (e.g. interval `60`, bias `30` fires
  /// at the 30th second of every minute).
  ///
  /// `intervalSeconds`: the recurrence interval in seconds; must be positive.
  /// `biasSeconds`: the alignment offset in seconds (`0` aligns to the epoch).
  /// `handler`: the asynchronous action to run on every tick, receiving a
  /// zero-based `counter` that is reset on every `start` / `startImmediately`.
  public class Scheduler(
    intervalSeconds : Nat64,
    biasSeconds : Nat64,
    handler : (counter : Nat) -> async* (),
  ) {

    var timerId_ : ?Nat = null;

    /// Returns the id of the underlying recurring timer, or `null` when the
    /// scheduler is not currently backed by a timer (for instance before
    /// `start` or after `stop`).
    public func timerId() : ?Nat = timerId_;

    var executionLock : Bool = false;

    /// Returns `true` while a run of `handler` is currently in flight.
    ///
    /// The scheduler never starts a new run while a previous one is still
    /// executing, so this can be used to observe whether the handler is busy.
    public func isExecutingHandler() : Bool = executionLock;

    var immediateCallRunning_ : Bool = false;

    /// Returns `true` when the scheduler is active, i.e. either a recurring
    /// timer is armed or the initial immediate call (from `startImmediately`)
    /// is still running.
    public func isRunning() : Bool = not Option.isNull(timerId_) or immediateCallRunning_;

    /// Returns the timestamp, in nanoseconds since the epoch, of the next
    /// epoch-aligned execution strictly after the current system time.
    ///
    /// This is a convenience wrapper around the pure `nextExecutionAt`
    /// function using the current system time.
    public func nextExecutionAt() : Nat64 = nextTickNanos(Prim.time(), intervalSeconds, biasSeconds);

    var executionCounter : Nat = 0;

    // Runs the handler under the execution lock, guaranteeing that runs never
    // overlap and that the counter advances after each completed run.
    func handlerInternal() : async () {
      assert not executionLock;
      executionLock := true;
      try {
        await* handler(executionCounter);
      } finally {
        executionLock := false;
        executionCounter += 1;
      };
    };

    /// Runs `handler` once immediately (resetting the counter to `0`), then
    /// starts the aligned recurring timer.
    ///
    /// If the scheduler is already running it is stopped first. Any error
    /// thrown by the immediate run is swallowed so that the recurring timer is
    /// still armed afterwards.
    public func startImmediately<system>() : async* () {
      if (isRunning()) {
        stop();
      };
      immediateCallRunning_ := true;
      executionCounter := 0;
      try {
        await handlerInternal();
      } catch (_) {};
      immediateCallRunning_ := false;
      if (not isRunning()) {
        start<system>();
      };
    };

    /// Starts the aligned recurring timer, resetting the counter to `0`.
    ///
    /// The first execution is delayed until the next epoch-aligned tick (see
    /// `initialDelaySeconds`); thereafter the handler runs every
    /// `intervalSeconds`. Calling `start` while the scheduler is already
    /// running is a no-op.
    public func start<system>() {
      if (isRunning()) {
        return;
      };
      executionCounter := 0;
      let delaySeconds = initialDelaySeconds(Prim.time(), intervalSeconds, biasSeconds);
      timerId_ := (
        func() : async () {
          timerId_ := ?Timer.recurringTimer<system>(#seconds(Nat64.toNat(intervalSeconds)), handlerInternal);
          await handlerInternal();
        }
      ) |> ?Timer.setTimer<system>(#seconds(Nat64.toNat(delaySeconds)), _);
    };

    /// Stops the recurring timer, if any, so that no further executions occur.
    ///
    /// A run of `handler` that is already in flight is not interrupted. Calling
    /// `stop` when no timer is armed is a no-op.
    public func stop() {
      switch (timerId_) {
        case (?t) {
          timerId_ := null;
          Timer.cancelTimer(t);
        };
        case (_) {};
      };
    };

  };

};
