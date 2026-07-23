# One test is missing its body

Module plus harness below; a single `test` body was replaced with
`# TODO`. Reconstruct it from its name and the surrounding suite so the
harness passes for a correct implementation of the module. Touch nothing
else.

## Module under test

```elixir
defmodule Watchdog do
  @moduledoc """
  A GenServer that monitors the liveness of registered entities via a heartbeat
  mechanism.

  Each registered entity is expected to periodically "check in" by calling
  `heartbeat/1`. If an entity fails to check in within its configured
  `interval_ms`, the `Watchdog` invokes the user-supplied timeout callback
  exactly once (as `on_timeout_fn.(name)`) and removes the registration.

  Liveness is determined purely by heartbeats — the associated `pid` is recorded
  but is not monitored for `:DOWN`/exit events.

  Timers are tagged with a unique reference so that stale timers (from a reset or
  an unregister) can never fire a spurious timeout.
  """

  use GenServer

  ## Public API

  @doc """
  Starts the `Watchdog` server.

  Accepts a `:name` option for process registration. If not provided the server
  registers itself under `#{inspect(__MODULE__)}`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  @doc """
  Begins monitoring `name`. Replaces any existing registration for `name`.

  The clock starts immediately: if no heartbeat arrives within `interval_ms`,
  `on_timeout_fn.(name)` is invoked. Synchronous — once it returns, the timer is
  armed.
  """
  @spec register(term(), pid(), non_neg_integer(), (term() -> any())) :: :ok
  def register(name, pid, interval_ms, on_timeout_fn)
      when is_integer(interval_ms) and interval_ms >= 0 and is_function(on_timeout_fn, 1) do
    GenServer.call(__MODULE__, {:register, name, pid, interval_ms, on_timeout_fn})
  end

  @doc """
  Records a heartbeat for `name`, resetting its timer. No-op for unknown names.
  Synchronous.
  """
  @spec heartbeat(term()) :: :ok
  def heartbeat(name) do
    GenServer.call(__MODULE__, {:heartbeat, name})
  end

  @doc """
  Stops monitoring `name`. After returning, no timeout callback fires for `name`.
  No-op for unknown names.
  """
  @spec unregister(term()) :: :ok
  def unregister(name) do
    GenServer.call(__MODULE__, {:unregister, name})
  end

  ## GenServer callbacks

  @impl true
  def init(_arg) do
    # State: %{name => %{pid, interval_ms, on_timeout_fn, ref, timer_ref}}
    {:ok, %{}}
  end

  @impl true
  def handle_call({:register, name, pid, interval_ms, on_timeout_fn}, _from, state) do
    state = cancel_entry(state, name)

    ref = make_ref()
    timer_ref = Process.send_after(self(), {:timeout, name, ref}, interval_ms)

    entry = %{
      pid: pid,
      interval_ms: interval_ms,
      on_timeout_fn: on_timeout_fn,
      ref: ref,
      timer_ref: timer_ref
    }

    {:reply, :ok, Map.put(state, name, entry)}
  end

  @impl true
  def handle_call({:heartbeat, name}, _from, state) do
    case Map.fetch(state, name) do
      {:ok, entry} ->
        _ = Process.cancel_timer(entry.timer_ref)
        ref = make_ref()
        timer_ref = Process.send_after(self(), {:timeout, name, ref}, entry.interval_ms)
        entry = %{entry | ref: ref, timer_ref: timer_ref}
        {:reply, :ok, Map.put(state, name, entry)}

      :error ->
        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call({:unregister, name}, _from, state) do
    {:reply, :ok, cancel_entry(state, name)}
  end

  @impl true
  def handle_info({:timeout, name, ref}, state) do
    case Map.fetch(state, name) do
      {:ok, %{ref: ^ref} = entry} ->
        # Valid, current timer fired: invoke callback once and remove.
        safe_invoke(entry.on_timeout_fn, name)
        {:noreply, Map.delete(state, name)}

      _ ->
        # Stale timer (reset/unregistered/replaced) — ignore.
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  ## Helpers

  defp cancel_entry(state, name) do
    case Map.fetch(state, name) do
      {:ok, entry} ->
        _ = Process.cancel_timer(entry.timer_ref)
        Map.delete(state, name)

      :error ->
        state
    end
  end

  defp safe_invoke(fun, name) do
    fun.(name)
  rescue
    _ -> :ok
  catch
    _, _ -> :ok
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule WatchdogTest do
  use ExUnit.Case, async: false

  # ------------------------------------------------------------------
  # Helpers
  # ------------------------------------------------------------------

  # A dummy long-lived process to pass as the monitored pid.
  defp dummy_pid do
    spawn(fn -> Process.sleep(:infinity) end)
  end

  # Build a callback that reports timeouts to the current test process.
  # Tagged so different registrations can be told apart.
  defp notifier(test_pid, tag \\ :timed_out) do
    fn name -> send(test_pid, {tag, name}) end
  end

  setup do
    start_supervised!({Watchdog, []})
    :ok
  end

  # ------------------------------------------------------------------
  # No timeout while heartbeats arrive on time
  # ------------------------------------------------------------------

  test "does not fire while heartbeats arrive within the interval" do
    test = self()
    :ok = Watchdog.register(:worker, dummy_pid(), 120, notifier(test))

    # Heartbeat every 40ms, well under the 120ms interval.
    for _ <- 1..4 do
      Process.sleep(40)
      assert :ok = Watchdog.heartbeat(:worker)
    end

    # After the last heartbeat, less than one interval has elapsed.
    refute_receive {:timed_out, :worker}, 60
  end

  # ------------------------------------------------------------------
  # Timeout fires when heartbeats stop
  # ------------------------------------------------------------------

  test "fires the callback when a heartbeat is missed" do
    test = self()
    :ok = Watchdog.register(:worker, dummy_pid(), 60, notifier(test))

    # Never heartbeat -> timeout must fire.
    assert_receive {:timed_out, :worker}, 1_000
  end

  test "callback receives the registered name" do
    test = self()
    :ok = Watchdog.register({:svc, 42}, dummy_pid(), 50, notifier(test))

    assert_receive {:timed_out, {:svc, 42}}, 1_000
  end

  # ------------------------------------------------------------------
  # Heartbeat resets the timer
  # ------------------------------------------------------------------

  test "heartbeat resets the timer so cumulative uptime exceeds the interval" do
    test = self()
    :ok = Watchdog.register(:worker, dummy_pid(), 90, notifier(test))

    # Two heartbeats spaced 60ms apart: total 120ms > 90ms interval,
    # but each heartbeat resets the clock so no timeout should occur yet.
    Process.sleep(60)
    assert :ok = Watchdog.heartbeat(:worker)
    Process.sleep(60)
    assert :ok = Watchdog.heartbeat(:worker)

    refute_receive {:timed_out, :worker}, 40

    # Now stop heartbeating; the timer should eventually fire.
    assert_receive {:timed_out, :worker}, 1_000
  end

  # ------------------------------------------------------------------
  # Unregister prevents the callback
  # ------------------------------------------------------------------

  test "unregister prevents the callback from firing" do
    test = self()
    :ok = Watchdog.register(:worker, dummy_pid(), 60, notifier(test))
    assert :ok = Watchdog.unregister(:worker)

    refute_receive {:timed_out, :worker}, 300
  end

  test "unregistering an unknown name is a harmless no-op" do
    assert :ok = Watchdog.unregister(:never_registered)
  end

  test "heartbeat for an unknown name is a harmless no-op" do
    assert :ok = Watchdog.heartbeat(:never_registered)
  end

  # ------------------------------------------------------------------
  # One-shot semantics
  # ------------------------------------------------------------------

  test "timeout fires exactly once then stops" do
    test = self()
    :ok = Watchdog.register(:worker, dummy_pid(), 50, notifier(test))

    assert_receive {:timed_out, :worker}, 1_000
    # Must not fire again for the same (now removed) registration.
    refute_receive {:timed_out, :worker}, 300
  end

  test "heartbeat after a timeout is a no-op (registration already removed)" do
    test = self()
    :ok = Watchdog.register(:worker, dummy_pid(), 50, notifier(test))

    assert_receive {:timed_out, :worker}, 1_000

    # The registration is gone; heartbeating must not re-arm anything.
    assert :ok = Watchdog.heartbeat(:worker)
    refute_receive {:timed_out, :worker}, 300
  end

  # ------------------------------------------------------------------
  # Independence between registrations
  # ------------------------------------------------------------------

  test "registrations are independent" do
    test = self()
    :ok = Watchdog.register(:fast, dummy_pid(), 60, notifier(test))
    :ok = Watchdog.register(:slow, dummy_pid(), 10_000, notifier(test))

    assert_receive {:timed_out, :fast}, 1_000
    # The slow one must not have fired.
    refute_receive {:timed_out, :slow}, 100
  end

  test "unregistering one name does not affect another" do
    test = self()
    :ok = Watchdog.register(:keep, dummy_pid(), 60, notifier(test))
    :ok = Watchdog.register(:drop, dummy_pid(), 60, notifier(test))

    assert :ok = Watchdog.unregister(:drop)

    assert_receive {:timed_out, :keep}, 1_000
    refute_receive {:timed_out, :drop}, 100
  end

  # ------------------------------------------------------------------
  # Re-registration replaces the previous registration
  # ------------------------------------------------------------------

  test "re-registering a name replaces interval and callback" do
    test = self()

    # First registration: long interval, tag :old.
    :ok = Watchdog.register(:worker, dummy_pid(), 10_000, notifier(test, :old))

    # Replace with a short interval and a different callback tag.
    :ok = Watchdog.register(:worker, dummy_pid(), 60, notifier(test, :new))

    # The new (short) registration must fire...
    assert_receive {:new, :worker}, 1_000
    # ...and the old callback must never fire.
    refute_receive {:old, :worker}, 100
  end

  test "re-registering re-arms the timer with a fresh clock" do
    test = self()

    :ok = Watchdog.register(:worker, dummy_pid(), 200, notifier(test))
    Process.sleep(120)
    # Re-register before the first interval elapses; clock restarts.
    :ok = Watchdog.register(:worker, dummy_pid(), 200, notifier(test))

    # 120ms after re-registration is still under the 200ms interval.
    refute_receive {:timed_out, :worker}, 120

    # Eventually it should fire from the fresh registration.
    assert_receive {:timed_out, :worker}, 1_000
  end

  # ------------------------------------------------------------------
  # Custom :name option
  # ------------------------------------------------------------------

  test "start_link accepts a :name option" do
    {:ok, pid} = Watchdog.start_link(name: :custom_watchdog)
    assert is_pid(pid)
    assert Process.whereis(:custom_watchdog) == pid
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
  end

  test "re-registering with a longer interval outlives the replaced deadline" do
    # TODO
  end

  test "a heartbeat for one name does not reset another name's timer" do
    test = self()
    :ok = Watchdog.register(:chatty, dummy_pid(), 10_000, notifier(test, :chatty_out))
    :ok = Watchdog.register(:quiet, dummy_pid(), 60, notifier(test, :quiet_out))

    # Heartbeats for :chatty must not touch :quiet's armed timer.
    for _ <- 1..5 do
      assert :ok = Watchdog.heartbeat(:chatty)
    end

    assert_receive {:quiet_out, :quiet}, 1_000
    refute_receive {:chatty_out, :chatty}, 50
  end

  test "a heartbeat after unregister does not revive the registration" do
    test = self()
    :ok = Watchdog.register(:worker, dummy_pid(), 60, notifier(test))
    assert :ok = Watchdog.unregister(:worker)

    # An unknown-name heartbeat must not re-arm anything for the retired registration.
    assert :ok = Watchdog.heartbeat(:worker)

    refute_receive {:timed_out, :worker}, 300
  end

  test "registering again after unregister arms a fresh timer" do
    test = self()
    :ok = Watchdog.register(:worker, dummy_pid(), 10_000, notifier(test, :first))
    assert :ok = Watchdog.unregister(:worker)

    :ok = Watchdog.register(:worker, dummy_pid(), 60, notifier(test, :second))

    assert_receive {:second, :worker}, 1_000
    refute_receive {:first, :worker}, 50
  end

  test "a value-equal composite name replaces instead of duplicating" do
    test = self()
    :ok = Watchdog.register({:svc, [1, 2]}, dummy_pid(), 60, notifier(test, :old))

    # Same name by value, built independently.
    key = {:svc, Enum.to_list(1..2)}
    :ok = Watchdog.register(key, dummy_pid(), 60, notifier(test, :new))

    assert_receive {:new, {:svc, [1, 2]}}, 1_000
    refute_receive {:old, {:svc, [1, 2]}}, 200
    refute_receive {:new, {:svc, [1, 2]}}, 200
  end
end
```
