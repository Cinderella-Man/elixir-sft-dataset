# Complete the blanked test

You get a module and its ExUnit harness, minus the body of ONE `test` —
the `# TODO` marks the spot, and its name says what it must prove. Write
exactly that test so the harness passes against a correct implementation
of the module.

## Module under test

```elixir
defmodule RecurringWatchdog do
  @moduledoc """
  A GenServer that monitors liveness via heartbeats and keeps re-alerting every
  interval while an entity stays silent.

  Each registered entity is expected to periodically call `heartbeat/1`. If no
  heartbeat arrives within `interval_ms`, `on_timeout_fn.(name)` is invoked and the
  status becomes `:alerting`; the watchdog then re-arms another interval and fires
  again, repeating until a heartbeat (which resets status to `:healthy`) or an
  unregister.

  Timers are tagged with a unique reference so stale timers (from a reset or an
  unregister) can never fire spuriously.
  """

  use GenServer

  ## Public API

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  @doc "Registers a recurring watchdog for `name`/`pid` firing `fun` every `interval_ms`."
  @spec register(term(), pid(), non_neg_integer(), (term() -> any())) :: :ok
  def register(name, pid, interval_ms, on_timeout_fn)
      when is_integer(interval_ms) and interval_ms >= 0 and is_function(on_timeout_fn, 1) do
    GenServer.call(__MODULE__, {:register, name, pid, interval_ms, on_timeout_fn})
  end

  @spec heartbeat(term()) :: :ok
  def heartbeat(name), do: GenServer.call(__MODULE__, {:heartbeat, name})

  @spec unregister(term()) :: :ok
  def unregister(name), do: GenServer.call(__MODULE__, {:unregister, name})

  @spec status(term()) :: {:ok, :healthy | :alerting} | {:error, :not_registered}
  def status(name), do: GenServer.call(__MODULE__, {:status, name})

  ## GenServer callbacks

  @impl true
  def init(_arg), do: {:ok, %{}}

  @impl true
  def handle_call({:register, name, pid, interval_ms, fun}, _from, state) do
    state = cancel_entry(state, name)
    ref = make_ref()
    timer = Process.send_after(self(), {:tick, name, ref}, interval_ms)

    entry = %{
      pid: pid,
      interval_ms: interval_ms,
      fun: fun,
      status: :healthy,
      ref: ref,
      timer: timer
    }

    {:reply, :ok, Map.put(state, name, entry)}
  end

  def handle_call({:heartbeat, name}, _from, state) do
    case Map.fetch(state, name) do
      {:ok, entry} ->
        _ = Process.cancel_timer(entry.timer)
        ref = make_ref()
        timer = Process.send_after(self(), {:tick, name, ref}, entry.interval_ms)
        {:reply, :ok, Map.put(state, name, %{entry | status: :healthy, ref: ref, timer: timer})}

      :error ->
        {:reply, :ok, state}
    end
  end

  def handle_call({:unregister, name}, _from, state) do
    {:reply, :ok, cancel_entry(state, name)}
  end

  def handle_call({:status, name}, _from, state) do
    case Map.fetch(state, name) do
      {:ok, entry} -> {:reply, {:ok, entry.status}, state}
      :error -> {:reply, {:error, :not_registered}, state}
    end
  end

  @impl true
  def handle_info({:tick, name, ref}, state) do
    case Map.fetch(state, name) do
      {:ok, %{ref: ^ref} = entry} ->
        safe_invoke(entry.fun, name)
        new_ref = make_ref()
        timer = Process.send_after(self(), {:tick, name, new_ref}, entry.interval_ms)
        {:noreply, Map.put(state, name, %{entry | status: :alerting, ref: new_ref, timer: timer})}

      _ ->
        # Stale timer (reset/unregistered/replaced) — ignore.
        {:noreply, state}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  ## Helpers

  defp cancel_entry(state, name) do
    case Map.fetch(state, name) do
      {:ok, entry} ->
        _ = Process.cancel_timer(entry.timer)
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
defmodule RecurringWatchdogTest do
  use ExUnit.Case, async: false

  # ------------------------------------------------------------------
  # Helpers
  # ------------------------------------------------------------------

  defp dummy_pid do
    spawn(fn -> Process.sleep(:infinity) end)
  end

  defp notifier(test_pid, tag \\ :alert) do
    fn name -> send(test_pid, {tag, name}) end
  end

  setup do
    start_supervised!({RecurringWatchdog, []})
    :ok
  end

  # ------------------------------------------------------------------
  # Healthy while heartbeats arrive
  # ------------------------------------------------------------------

  test "stays healthy while heartbeats arrive within the interval" do
    test = self()
    :ok = RecurringWatchdog.register(:w, dummy_pid(), 100, notifier(test))

    for _ <- 1..4 do
      Process.sleep(40)
      assert :ok = RecurringWatchdog.heartbeat(:w)
    end

    refute_receive {:alert, :w}, 60
    assert {:ok, :healthy} = RecurringWatchdog.status(:w)
  end

  # ------------------------------------------------------------------
  # Recurring alerts
  # ------------------------------------------------------------------

  test "fires repeatedly while heartbeats are missing" do
    test = self()
    :ok = RecurringWatchdog.register(:w, dummy_pid(), 50, notifier(test))

    assert_receive {:alert, :w}, 1_000
    assert_receive {:alert, :w}, 1_000
    assert_receive {:alert, :w}, 1_000
  end

  test "status becomes alerting after the first miss and healthy again after a heartbeat" do
    test = self()
    :ok = RecurringWatchdog.register(:w, dummy_pid(), 50, notifier(test))

    assert_receive {:alert, :w}, 1_000
    assert {:ok, :alerting} = RecurringWatchdog.status(:w)

    assert :ok = RecurringWatchdog.heartbeat(:w)
    assert {:ok, :healthy} = RecurringWatchdog.status(:w)
  end

  test "resumed heartbeats silence the recurring alerts" do
    test = self()
    :ok = RecurringWatchdog.register(:w, dummy_pid(), 60, notifier(test))

    assert_receive {:alert, :w}, 1_000

    # Heartbeat steadily, faster than the interval.
    for _ <- 1..5 do
      Process.sleep(30)
      assert :ok = RecurringWatchdog.heartbeat(:w)
    end

    refute_receive {:alert, :w}, 40
    assert {:ok, :healthy} = RecurringWatchdog.status(:w)
  end

  test "callback receives the registered name" do
    test = self()
    :ok = RecurringWatchdog.register({:svc, 7}, dummy_pid(), 50, notifier(test))

    assert_receive {:alert, {:svc, 7}}, 1_000
  end

  # ------------------------------------------------------------------
  # Independence, replacement, unregister
  # ------------------------------------------------------------------

  test "registrations are independent" do
    test = self()
    :ok = RecurringWatchdog.register(:fast, dummy_pid(), 50, notifier(test))
    :ok = RecurringWatchdog.register(:slow, dummy_pid(), 10_000, notifier(test))

    assert_receive {:alert, :fast}, 1_000
    refute_receive {:alert, :slow}, 100
  end

  test "unregister stops the recurring alerts" do
    test = self()
    :ok = RecurringWatchdog.register(:w, dummy_pid(), 50, notifier(test))

    assert_receive {:alert, :w}, 1_000
    assert :ok = RecurringWatchdog.unregister(:w)

    refute_receive {:alert, :w}, 300
    assert {:error, :not_registered} = RecurringWatchdog.status(:w)
  end

  test "re-registering replaces the previous registration" do
    test = self()
    :ok = RecurringWatchdog.register(:w, dummy_pid(), 10_000, notifier(test, :old))
    :ok = RecurringWatchdog.register(:w, dummy_pid(), 50, notifier(test, :new))

    assert_receive {:new, :w}, 1_000
    refute_receive {:old, :w}, 100
  end

  test "heartbeat and status for unknown names" do
    assert :ok = RecurringWatchdog.heartbeat(:nope)
    assert {:error, :not_registered} = RecurringWatchdog.status(:nope)
  end

  # ------------------------------------------------------------------
  # Custom :name option
  # ------------------------------------------------------------------

  test "start_link accepts a :name option" do
    # TODO
  end

  test "replacing a registration with a longer interval retires the old short timer" do
    test = self()
    :ok = RecurringWatchdog.register(:w, dummy_pid(), 50, notifier(test, :old))
    :ok = RecurringWatchdog.register(:w, dummy_pid(), 10_000, notifier(test, :new))

    # The replaced 50 ms deadline must never fire, and the fresh 10 s one is far away.
    refute_receive {:old, :w}, 300
    refute_receive {:new, :w}, 100
    assert {:ok, :healthy} = RecurringWatchdog.status(:w)
  end

  test "replacing an alerting registration resets its health back to healthy" do
    test = self()
    :ok = RecurringWatchdog.register(:w, dummy_pid(), 50, notifier(test, :old))

    assert_receive {:old, :w}, 1_000
    assert {:ok, :alerting} = RecurringWatchdog.status(:w)

    :ok = RecurringWatchdog.register(:w, dummy_pid(), 10_000, notifier(test, :new))
    assert {:ok, :healthy} = RecurringWatchdog.status(:w)
    refute_receive {:old, :w}, 200
    refute_receive {:new, :w}, 50
  end

  test "unregister before the first alert cancels the armed timer" do
    test = self()
    :ok = RecurringWatchdog.register(:w, dummy_pid(), 200, notifier(test))
    assert :ok = RecurringWatchdog.unregister(:w)

    refute_receive {:alert, :w}, 500
    assert {:error, :not_registered} = RecurringWatchdog.status(:w)
  end

  test "heartbeat and unregister on one name leave another name alerting" do
    test = self()
    :ok = RecurringWatchdog.register(:a, dummy_pid(), 10_000, notifier(test, :a_alert))
    :ok = RecurringWatchdog.register(:b, dummy_pid(), 50, notifier(test, :b_alert))

    assert :ok = RecurringWatchdog.heartbeat(:a)
    assert :ok = RecurringWatchdog.unregister(:a)

    assert_receive {:b_alert, :b}, 1_000
    assert_receive {:b_alert, :b}, 1_000
    assert {:ok, :alerting} = RecurringWatchdog.status(:b)
    refute_receive {:a_alert, :a}, 50
  end

  test "a dead registered pid stays healthy while heartbeats keep arriving" do
    test = self()
    pid = dummy_pid()
    :ok = RecurringWatchdog.register(:w, pid, 150, notifier(test))

    ref = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^ref, :process, ^pid, :killed}, 500

    for _ <- 1..4 do
      assert :ok = RecurringWatchdog.heartbeat(:w)
      refute_receive {:alert, :w}, 50
    end

    assert {:ok, :healthy} = RecurringWatchdog.status(:w)
  end
end
```
