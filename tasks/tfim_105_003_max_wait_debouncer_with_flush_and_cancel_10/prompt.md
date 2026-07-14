# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule MaxWaitDebouncer do
  @moduledoc """
  A `GenServer` debouncer with a maximum-wait guarantee and manual flush/cancel.

  Like a normal debouncer it coalesces rapid same-key calls (resetting the timer
  and replacing the pending func), but it also guarantees the pending func fires
  no later than `max_ms` after the burst's first call — so a sustained burst
  can't starve execution forever. `flush/1` runs the pending func immediately;
  `cancel/1` drops it.
  """

  use GenServer

  @doc """
  Starts the debouncer. Accepts a `:name` option, defaulting to `MaxWaitDebouncer`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  @doc """
  Schedules `func` for `key`, coalescing with `delay_ms` but guaranteeing a fire
  within `max_ms` of the burst's first call. Returns `:ok` promptly.
  """
  @spec call(term(), non_neg_integer(), non_neg_integer(), (-> any())) :: :ok
  def call(key, delay_ms, max_ms, func)
      when is_integer(delay_ms) and delay_ms >= 0 and is_integer(max_ms) and
             max_ms >= delay_ms and
             is_function(func, 0) do
    GenServer.cast(__MODULE__, {:debounce, key, delay_ms, max_ms, func})
  end

  @doc "Immediately runs the pending func for `key` (if any) and clears state."
  @spec flush(term()) :: :ok
  def flush(key), do: GenServer.call(__MODULE__, {:flush, key})

  @doc "Discards the pending func for `key` without running it."
  @spec cancel(term()) :: :ok
  def cancel(key), do: GenServer.call(__MODULE__, {:cancel, key})

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_cast({:debounce, key, delay_ms, max_ms, func}, state) do
    now = mono_ms()

    first_at =
      case Map.get(state, key) do
        %{timer: ref, first_at: at} ->
          Process.cancel_timer(ref)
          at

        nil ->
          now
      end

    remaining_until_max = max(0, first_at + max_ms - now)
    fire_in = max(0, min(delay_ms, remaining_until_max))
    ref = Process.send_after(self(), {:fire, key}, fire_in)

    entry = %{timer: ref, func: func, first_at: first_at}
    {:noreply, Map.put(state, key, entry)}
  end

  @impl true
  def handle_call({:flush, key}, _from, state) do
    case Map.pop(state, key) do
      {%{timer: ref, func: func}, new_state} ->
        Process.cancel_timer(ref)
        run(func)
        {:reply, :ok, new_state}

      {nil, new_state} ->
        {:reply, :ok, new_state}
    end
  end

  def handle_call({:cancel, key}, _from, state) do
    case Map.pop(state, key) do
      {%{timer: ref}, new_state} ->
        Process.cancel_timer(ref)
        {:reply, :ok, new_state}

      {nil, new_state} ->
        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_info({:fire, key}, state) do
    case Map.pop(state, key) do
      {%{func: func}, new_state} ->
        run(func)
        {:noreply, new_state}

      {nil, new_state} ->
        {:noreply, new_state}
    end
  end

  defp run(func), do: spawn(fn -> func.() end)

  defp mono_ms, do: System.monotonic_time(:millisecond)
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule MaxWaitDebouncerTest do
  use ExUnit.Case, async: false

  setup do
    start_supervised!(MaxWaitDebouncer)
    :ok
  end

  defp notify(tag) do
    test = self()
    fn -> send(test, tag) end
  end

  # -------------------------------------------------------
  # Basic coalescing + delay
  # -------------------------------------------------------

  test "coalesces to the last func after the delay when the burst settles" do
    MaxWaitDebouncer.call("k", 150, 1000, notify({:ran, 1}))
    MaxWaitDebouncer.call("k", 150, 1000, notify({:ran, 2}))
    MaxWaitDebouncer.call("k", 150, 1000, notify({:ran, 3}))

    assert_receive {:ran, 3}, 600
    refute_received {:ran, 1}
    refute_received {:ran, 2}
  end

  test "does not run before the delay elapses" do
    MaxWaitDebouncer.call("k", 200, 1000, notify(:done))
    refute_receive :done, 120
    assert_receive :done, 400
  end

  # -------------------------------------------------------
  # Max-wait guarantee
  # -------------------------------------------------------

  test "fires by max_ms even though the delay timer keeps resetting" do
    # delay=150, max=250. A plain debouncer would keep pushing the fire to
    # ~last_call + 150; the max-wait bound forces a fire at ~first_call + 250.
    MaxWaitDebouncer.call("k", 150, 250, notify(:fired))
    Process.sleep(100)
    # t=100: resets delay timer (would fire at ~250 anyway)
    MaxWaitDebouncer.call("k", 150, 250, notify(:fired))
    Process.sleep(100)
    # t=200: delay would push fire to ~350, but max deadline is ~250.
    MaxWaitDebouncer.call("k", 150, 250, notify(:fired))

    # From here (~t=200) the max deadline (~250) is only ~50ms away, well before
    # the ~350 the delay timer would give.
    assert_receive :fired, 175
  end

  test "single call within max simply obeys the normal delay" do
    MaxWaitDebouncer.call("k", 100, 1000, notify(:one))
    assert_receive :one, 400
    refute_receive :one, 200
  end

  # -------------------------------------------------------
  # flush / cancel
  # -------------------------------------------------------

  test "flush runs the pending func immediately" do
    MaxWaitDebouncer.call("k", 500, 5000, notify(:flushed))
    assert :ok = MaxWaitDebouncer.flush("k")

    # Runs well before the 500ms delay would have.
    assert_receive :flushed, 200
    # And does not run a second time.
    refute_receive :flushed, 600
  end

  test "flush with nothing pending is a no-op returning :ok" do
    assert :ok = MaxWaitDebouncer.flush("absent")
    refute_receive _, 100
  end

  test "cancel discards the pending func" do
    MaxWaitDebouncer.call("k", 200, 1000, notify(:cancelled))
    assert :ok = MaxWaitDebouncer.cancel("k")

    refute_receive :cancelled, 400
  end

  # -------------------------------------------------------
  # Independence + fresh bursts + contract
  # -------------------------------------------------------

  test "different keys are independent" do
    MaxWaitDebouncer.call("a", 100, 1000, notify({:key, "a"}))
    MaxWaitDebouncer.call("b", 100, 1000, notify({:key, "b"}))

    assert_receive {:key, "a"}, 400
    assert_receive {:key, "b"}, 400
  end

  test "a fresh call after firing starts a new max-wait window" do
    # TODO
  end

  test "call/4 returns :ok promptly even with a blocking func" do
    slow = fn -> Process.sleep(300) end
    {micros, :ok} = :timer.tc(fn -> MaxWaitDebouncer.call("s", 50, 500, slow) end)
    assert micros < 100_000
  end

  test "accepts max_ms equal to delay_ms and fires once" do
    # The contract is `max_ms >= delay_ms`, so equality must be accepted.
    assert :ok = MaxWaitDebouncer.call("k", 100, 100, notify(:equal))

    assert_receive :equal, 400
    refute_receive :equal, 200
  end

  test "accepts a zero delay and fires promptly" do
    # delay_ms is a non-negative duration; 0 satisfies `max_ms >= delay_ms`.
    assert :ok = MaxWaitDebouncer.call("k", 0, 500, notify(:zero))

    assert_receive :zero, 400
    refute_receive :zero, 200
  end

  # -------------------------------------------------------
  # Max-wait deadline is anchored to the burst's first call
  # -------------------------------------------------------

  test "the max-wait fire lands near first_call + max_ms, not last_call + delay" do
    # delay=200, max=250. Calls land at roughly t=0, t=80, t=165, each one
    # resetting the delay timer. A debouncer that only honours delay_ms would
    # fire at ~165 + 200 = ~365; the max-wait bound pins the fire at ~250,
    # i.e. within ~85ms of the final call. The window below expires at ~305,
    # so only an implementation that respects max_ms can satisfy it.
    MaxWaitDebouncer.call("k", 200, 250, notify(:fired))
    refute_receive :fired, 80
    MaxWaitDebouncer.call("k", 200, 250, notify(:fired))
    refute_receive :fired, 80
    MaxWaitDebouncer.call("k", 200, 250, notify(:fired))

    assert_receive :fired, 140
  end

  # -------------------------------------------------------
  # start_link/1 registration
  # -------------------------------------------------------

  test "start_link/1 registers the process under a custom :name" do
    # The default name is already covered by the suite's setup; here the
    # :name option must actually drive registration.
    name = :"max_wait_debouncer_#{System.pid()}_#{System.unique_integer([:positive])}"

    assert {:ok, pid} = MaxWaitDebouncer.start_link(name: name)
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)

    assert Process.alive?(pid)
    assert Process.whereis(name) == pid
  end
end
```
