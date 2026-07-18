# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule GraceWatchdog do
  @moduledoc """
  A GenServer that monitors liveness via heartbeats but tolerates a configurable
  number of consecutive missed intervals before firing.

  Each registered entity is expected to periodically call `heartbeat/1`. Every
  `interval_ms` that elapses without a heartbeat records a *miss* and re-arms a
  fresh timer. Only once `max_misses` consecutive misses accumulate does the
  watchdog invoke `on_timeout_fn.(name, miss_count)` (exactly once) and remove the
  registration. Any heartbeat resets the miss counter to zero.

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

  @doc """
  Registers a watchdog for `name`/`pid` that fires `on_timeout_fn` after `max_misses`
  consecutive missed heartbeats spaced `interval_ms` apart. Returns `:ok`.
  """
  @spec register(
          term(),
          pid(),
          non_neg_integer(),
          pos_integer(),
          (term(), pos_integer() -> any())
        ) ::
          :ok
  def register(name, pid, interval_ms, max_misses, on_timeout_fn)
      when is_integer(interval_ms) and interval_ms >= 0 and is_integer(max_misses) and
             max_misses >= 1 and is_function(on_timeout_fn, 2) do
    GenServer.call(__MODULE__, {:register, name, pid, interval_ms, max_misses, on_timeout_fn})
  end

  @spec heartbeat(term()) :: :ok
  def heartbeat(name), do: GenServer.call(__MODULE__, {:heartbeat, name})

  @spec unregister(term()) :: :ok
  def unregister(name), do: GenServer.call(__MODULE__, {:unregister, name})

  @spec misses(term()) :: {:ok, non_neg_integer()} | {:error, :not_registered}
  def misses(name), do: GenServer.call(__MODULE__, {:misses, name})

  ## GenServer callbacks

  @impl true
  def init(_arg), do: {:ok, %{}}

  @impl true
  def handle_call({:register, name, pid, interval_ms, max_misses, fun}, _from, state) do
    state = cancel_entry(state, name)
    ref = make_ref()
    timer = Process.send_after(self(), {:tick, name, ref}, interval_ms)

    entry = %{
      pid: pid,
      interval_ms: interval_ms,
      max_misses: max_misses,
      fun: fun,
      misses: 0,
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
        {:reply, :ok, Map.put(state, name, %{entry | misses: 0, ref: ref, timer: timer})}

      :error ->
        {:reply, :ok, state}
    end
  end

  def handle_call({:unregister, name}, _from, state) do
    {:reply, :ok, cancel_entry(state, name)}
  end

  def handle_call({:misses, name}, _from, state) do
    case Map.fetch(state, name) do
      {:ok, entry} -> {:reply, {:ok, entry.misses}, state}
      :error -> {:reply, {:error, :not_registered}, state}
    end
  end

  @impl true
  def handle_info({:tick, name, ref}, state) do
    case Map.fetch(state, name) do
      {:ok, %{ref: ^ref} = entry} ->
        misses = entry.misses + 1

        if misses >= entry.max_misses do
          safe_invoke(entry.fun, name, misses)
          {:noreply, Map.delete(state, name)}
        else
          new_ref = make_ref()
          timer = Process.send_after(self(), {:tick, name, new_ref}, entry.interval_ms)
          {:noreply, Map.put(state, name, %{entry | misses: misses, ref: new_ref, timer: timer})}
        end

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

  defp safe_invoke(fun, name, misses) do
    fun.(name, misses)
  rescue
    _ -> :ok
  catch
    _, _ -> :ok
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule GraceWatchdogTest do
  use ExUnit.Case, async: false

  # ------------------------------------------------------------------
  # Helpers
  # ------------------------------------------------------------------

  defp dummy_pid do
    spawn(fn -> Process.sleep(:infinity) end)
  end

  defp notifier(test_pid, tag \\ :timed_out) do
    fn name, misses -> send(test_pid, {tag, name, misses}) end
  end

  setup do
    start_supervised!({GraceWatchdog, []})
    :ok
  end

  # ------------------------------------------------------------------
  # No timeout while heartbeats arrive
  # ------------------------------------------------------------------

  test "does not fire while heartbeats arrive within the interval" do
    test = self()
    :ok = GraceWatchdog.register(:w, dummy_pid(), 80, 2, notifier(test))

    for _ <- 1..4 do
      Process.sleep(40)
      assert :ok = GraceWatchdog.heartbeat(:w)
    end

    refute_receive {:timed_out, :w, _}, 60
  end

  # ------------------------------------------------------------------
  # Threshold behaviour
  # ------------------------------------------------------------------

  test "fires only after max_misses consecutive missed intervals" do
    test = self()
    :ok = GraceWatchdog.register(:w, dummy_pid(), 50, 3, notifier(test))

    # With interval 50 and threshold 3, the earliest fire is ~150ms.
    refute_receive {:timed_out, :w, _}, 100
    assert_receive {:timed_out, :w, 3}, 1_000
  end

  test "max_misses of 1 fires after a single missed interval" do
    test = self()
    :ok = GraceWatchdog.register(:w, dummy_pid(), 50, 1, notifier(test))

    assert_receive {:timed_out, :w, 1}, 1_000
  end

  test "callback receives the name and the miss count" do
    test = self()
    :ok = GraceWatchdog.register({:svc, 1}, dummy_pid(), 40, 2, notifier(test))

    assert_receive {:timed_out, {:svc, 1}, 2}, 1_000
  end

  # ------------------------------------------------------------------
  # Miss counter accumulation and reset
  # ------------------------------------------------------------------

  test "misses accumulate over intervals and are queryable" do
    :ok = GraceWatchdog.register(:w, dummy_pid(), 80, 5, notifier(self()))

    # One interval elapses (~80ms); at 120ms exactly one miss recorded.
    Process.sleep(120)
    assert {:ok, 1} = GraceWatchdog.misses(:w)
  end

  test "a heartbeat resets the accumulated miss count" do
    :ok = GraceWatchdog.register(:w, dummy_pid(), 80, 5, notifier(self()))

    Process.sleep(120)
    assert {:ok, 1} = GraceWatchdog.misses(:w)
    assert :ok = GraceWatchdog.heartbeat(:w)
    assert {:ok, 0} = GraceWatchdog.misses(:w)
  end

  test "misses for an unknown name returns an error" do
    assert {:error, :not_registered} = GraceWatchdog.misses(:nope)
  end

  test "steady heartbeats keep the miss count at zero so it never fires" do
    test = self()
    :ok = GraceWatchdog.register(:w, dummy_pid(), 60, 2, notifier(test))

    for _ <- 1..5 do
      Process.sleep(30)
      assert :ok = GraceWatchdog.heartbeat(:w)
    end

    refute_receive {:timed_out, :w, _}, 40
  end

  # ------------------------------------------------------------------
  # One-shot semantics
  # ------------------------------------------------------------------

  test "fires exactly once then stops" do
    test = self()
    :ok = GraceWatchdog.register(:w, dummy_pid(), 40, 2, notifier(test))

    assert_receive {:timed_out, :w, 2}, 1_000
    refute_receive {:timed_out, :w, _}, 200
  end

  # ------------------------------------------------------------------
  # Independence and replacement
  # ------------------------------------------------------------------

  test "registrations are independent" do
    test = self()
    :ok = GraceWatchdog.register(:fast, dummy_pid(), 40, 2, notifier(test))
    :ok = GraceWatchdog.register(:slow, dummy_pid(), 10_000, 2, notifier(test))

    assert_receive {:timed_out, :fast, 2}, 1_000
    refute_receive {:timed_out, :slow, _}, 100
  end

  test "re-registering replaces interval, threshold and callback" do
    test = self()
    :ok = GraceWatchdog.register(:w, dummy_pid(), 10_000, 5, notifier(test, :old))
    :ok = GraceWatchdog.register(:w, dummy_pid(), 40, 1, notifier(test, :new))

    assert_receive {:new, :w, 1}, 1_000
    refute_receive {:old, :w, _}, 100
  end

  # ------------------------------------------------------------------
  # Unregister and unknown-name no-ops
  # ------------------------------------------------------------------

  test "unregister prevents the callback from firing" do
    # TODO
  end

  test "heartbeat for an unknown name is a harmless no-op" do
    assert :ok = GraceWatchdog.heartbeat(:nope)
  end

  test "unregister for a name that was never registered returns :ok" do
    assert :ok = GraceWatchdog.unregister(:nope)

    # The watchdog stays usable afterwards: a fresh registration still fires.
    test = self()
    :ok = GraceWatchdog.register(:w, dummy_pid(), 40, 1, notifier(test))
    assert_receive {:timed_out, :w, 1}, 1_000
  end

  test "unregistering an unknown name leaves other registrations untouched" do
    test = self()
    :ok = GraceWatchdog.register(:w, dummy_pid(), 40, 2, notifier(test))

    assert :ok = GraceWatchdog.unregister(:nope)
    assert {:error, :not_registered} = GraceWatchdog.misses(:nope)
    assert {:ok, _} = GraceWatchdog.misses(:w)

    assert_receive {:timed_out, :w, 2}, 1_000
  end

  test "unregistering the same name twice is a no-op the second time" do
    test = self()
    :ok = GraceWatchdog.register(:w, dummy_pid(), 40, 2, notifier(test))

    assert :ok = GraceWatchdog.unregister(:w)
    assert :ok = GraceWatchdog.unregister(:w)
    assert {:error, :not_registered} = GraceWatchdog.misses(:w)

    refute_receive {:timed_out, :w, _}, 300
  end

  # ------------------------------------------------------------------
  # Custom :name option
  # ------------------------------------------------------------------

  test "start_link accepts a :name option" do
    {:ok, pid} = GraceWatchdog.start_link(name: :custom_grace)
    assert is_pid(pid)
    assert Process.whereis(:custom_grace) == pid
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
  end

  test "the registration is removed once the callback has fired" do
    test = self()
    :ok = GraceWatchdog.register(:w, dummy_pid(), 40, 1, notifier(test))

    assert_receive {:timed_out, :w, 1}, 1_000
    assert {:error, :not_registered} = GraceWatchdog.misses(:w)
  end

  test "re-registering with a longer interval does not fire at the old deadline" do
    test = self()
    :ok = GraceWatchdog.register(:w, dummy_pid(), 40, 1, notifier(test, :old))
    :ok = GraceWatchdog.register(:w, dummy_pid(), 10_000, 1, notifier(test, :new))

    refute_receive {:old, :w, _}, 300
    refute_receive {:new, :w, _}, 10
    assert {:ok, 0} = GraceWatchdog.misses(:w)
  end

  test "re-registering resets the accumulated miss count to zero" do
    test = self()
    :ok = GraceWatchdog.register(:w, dummy_pid(), 25, 10, notifier(test))
    :ok = GraceWatchdog.register(:gate, dummy_pid(), 70, 1, notifier(test, :gate))

    assert_receive {:gate, :gate, 1}, 1_000
    assert {:ok, accumulated} = GraceWatchdog.misses(:w)
    assert accumulated >= 1

    :ok = GraceWatchdog.register(:w, dummy_pid(), 10_000, 5, notifier(test))
    assert {:ok, 0} = GraceWatchdog.misses(:w)
  end

  test "a heartbeat for one name leaves another name's miss count alone" do
    test = self()
    :ok = GraceWatchdog.register(:a, dummy_pid(), 25, 10, notifier(test))
    :ok = GraceWatchdog.register(:b, dummy_pid(), 25, 10, notifier(test))
    :ok = GraceWatchdog.register(:gate, dummy_pid(), 70, 1, notifier(test, :gate))

    assert_receive {:gate, :gate, 1}, 1_000
    assert :ok = GraceWatchdog.heartbeat(:a)

    assert {:ok, 0} = GraceWatchdog.misses(:a)
    assert {:ok, b_misses} = GraceWatchdog.misses(:b)
    assert b_misses >= 1
  end

  test "a burst of misses interrupted by a heartbeat does not fire at the original deadline" do
    test = self()
    :ok = GraceWatchdog.register(:w, dummy_pid(), 60, 3, notifier(test))
    :ok = GraceWatchdog.register(:gate, dummy_pid(), 100, 1, notifier(test, :gate))

    assert_receive {:gate, :gate, 1}, 1_000
    assert :ok = GraceWatchdog.heartbeat(:w)
    assert {:ok, 0} = GraceWatchdog.misses(:w)

    # The threshold would have been crossed by ~180ms without the heartbeat.
    refute_receive {:timed_out, :w, _}, 120
  end

  test "start_link without a :name option registers under the module name" do
    assert is_pid(Process.whereis(GraceWatchdog))
  end
end
```
