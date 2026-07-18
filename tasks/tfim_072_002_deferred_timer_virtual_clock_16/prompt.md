# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule Clock do
  @moduledoc """
  Behaviour and dispatcher for clock implementations.

  This variation pairs the readable `now/0` with a deterministic virtual-time
  scheduler (`Clock.Fake`) that can register deferred callbacks. Application
  code accepts a `:clock` option and calls `Clock.now/1` uniformly.
  """

  @doc "Returns the current datetime."
  @callback now() :: DateTime.t()

  @doc "Dispatches `now/0` to the correct implementation."
  @spec now(module() | GenServer.server()) :: DateTime.t()
  def now(clock) when is_atom(clock) do
    if function_exported?(clock, :now, 0) do
      clock.now()
    else
      Clock.Fake.now(clock)
    end
  end

  def now(clock), do: Clock.Fake.now(clock)
end

# ---------------------------------------------------------------------------

defmodule Clock.Real do
  @moduledoc "Production clock — delegates straight to the OS."

  @behaviour Clock

  @impl Clock
  @spec now() :: DateTime.t()
  def now, do: DateTime.utc_now()
end

# ---------------------------------------------------------------------------

defmodule Clock.Fake do
  @moduledoc """
  A controllable, process-based virtual clock with a deferred-timer scheduler.

  Timers registered with `schedule/3` never fire on their own — they fire only
  when `advance/2` moves virtual time to or past their due instant, in strict
  chronological order (ties broken by registration order).

  Note: callback functions run inside the clock process, so they must not call
  back into the same clock synchronously (that would deadlock). In tests they
  typically `send/2` a message to the test process.
  """

  use GenServer

  @default_initial ~U[2024-01-01 00:00:00Z]

  defstruct time: nil, timers: [], next_seq: 0, next_ref: 0

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {initial, opts} = Keyword.pop(opts, :initial, @default_initial)
    {name_opt, _rest} = Keyword.pop(opts, :name)
    gen_opts = if name_opt, do: [name: name_opt], else: []
    GenServer.start_link(__MODULE__, initial, gen_opts)
  end

  @doc "Returns the current virtual `DateTime`."
  @spec now(GenServer.server()) :: DateTime.t()
  def now(server), do: GenServer.call(server, :now)

  @doc """
  Registers `fun` (0-arity) to run when virtual time reaches `now + duration`.
  Returns a unique integer timer ref. Timers only fire during `advance/2`.
  """
  @spec schedule(GenServer.server(), keyword(), (-> any())) :: non_neg_integer()
  def schedule(server, duration, fun) when is_list(duration) and is_function(fun, 0),
    do: GenServer.call(server, {:schedule, duration, fun})

  @doc "Cancels a pending timer. Returns `:ok` if it was pending, `:error` otherwise."
  @spec cancel(GenServer.server(), non_neg_integer()) :: :ok | :error
  def cancel(server, ref), do: GenServer.call(server, {:cancel, ref})

  @doc "Returns the number of timers not yet fired or cancelled."
  @spec pending(GenServer.server()) :: non_neg_integer()
  def pending(server), do: GenServer.call(server, :pending)

  @doc """
  Moves virtual time forward by `duration` and fires every due timer in
  chronological order. Returns the list of fired timer refs, in fire order.
  """
  @spec advance(GenServer.server(), keyword()) :: [non_neg_integer()]
  def advance(server, duration) when is_list(duration),
    do: GenServer.call(server, {:advance, duration})

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init(%DateTime{} = initial), do: {:ok, %__MODULE__{time: initial}}

  @impl GenServer
  def handle_call(:now, _from, state), do: {:reply, state.time, state}

  def handle_call(:pending, _from, state), do: {:reply, length(state.timers), state}

  def handle_call({:schedule, duration, fun}, _from, state) do
    at = apply_duration(state.time, duration)
    ref = state.next_ref
    timer = %{ref: ref, at: at, seq: state.next_seq, fun: fun}

    state = %{
      state
      | timers: [timer | state.timers],
        next_seq: state.next_seq + 1,
        next_ref: ref + 1
    }

    {:reply, ref, state}
  end

  def handle_call({:cancel, ref}, _from, state) do
    {removed, remaining} = Enum.split_with(state.timers, &(&1.ref == ref))
    reply = if removed == [], do: :error, else: :ok
    {:reply, reply, %{state | timers: remaining}}
  end

  def handle_call({:advance, duration}, _from, state) do
    new_time = apply_duration(state.time, duration)

    {due, remaining} =
      Enum.split_with(state.timers, fn t ->
        DateTime.compare(t.at, new_time) in [:lt, :eq]
      end)

    ordered = Enum.sort_by(due, fn t -> {DateTime.to_unix(t.at, :microsecond), t.seq} end)
    Enum.each(ordered, fn t -> t.fun.() end)

    fired = Enum.map(ordered, & &1.ref)
    {:reply, fired, %{state | time: new_time, timers: remaining}}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  @unit_seconds %{
    second: 1,
    seconds: 1,
    minute: 60,
    minutes: 60,
    hour: 3600,
    hours: 3600,
    day: 86_400,
    days: 86_400
  }

  # Convert the whole duration to seconds, then apply once — robust across
  # Elixir versions regardless of which units DateTime.add/3 supports natively.
  defp apply_duration(datetime, duration) do
    total =
      Enum.reduce(duration, 0, fn {unit, amount}, acc ->
        acc + amount * Map.fetch!(@unit_seconds, unit)
      end)

    DateTime.add(datetime, total, :second)
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule ClockV1Test do
  use ExUnit.Case, async: false

  # Collect `n` messages from the mailbox in FIFO (delivery) order, so we can
  # assert on the *order* in which scheduled callbacks fired.
  defp drain(0), do: []

  defp drain(n) do
    receive do
      msg -> [msg | drain(n - 1)]
    after
      500 -> flunk("timed out waiting for #{n} more message(s)")
    end
  end

  # -------------------------------------------------------
  # Clock.Real
  # -------------------------------------------------------

  describe "Clock.Real" do
    test "now/0 returns a DateTime close to the actual current UTC time" do
      before = DateTime.utc_now()
      result = Clock.Real.now()
      after_ = DateTime.utc_now()

      assert %DateTime{} = result
      assert DateTime.compare(result, before) in [:gt, :eq]
      assert DateTime.compare(result, after_) in [:lt, :eq]
    end
  end

  # -------------------------------------------------------
  # Clock.Fake — basic time control
  # -------------------------------------------------------

  describe "Clock.Fake basics" do
    setup do
      initial = ~U[2024-06-15 12:00:00Z]
      {:ok, pid} = Clock.Fake.start_link(initial: initial)
      %{clock: pid, initial: initial}
    end

    test "now/1 returns the frozen datetime", %{clock: clock, initial: initial} do
      assert Clock.Fake.now(clock) == initial
    end

    test "advance moves virtual time forward", %{clock: clock, initial: initial} do
      Clock.Fake.advance(clock, hours: 1, minutes: 30)
      assert Clock.Fake.now(clock) == DateTime.add(initial, 90 * 60, :second)
    end

    test "advance is cumulative", %{clock: clock, initial: initial} do
      Clock.Fake.advance(clock, seconds: 10)
      Clock.Fake.advance(clock, seconds: 20)
      assert Clock.Fake.now(clock) == DateTime.add(initial, 30, :second)
    end
  end

  # -------------------------------------------------------
  # Clock.Fake — deferred timers
  # -------------------------------------------------------

  describe "Clock.Fake deferred timers" do
    setup do
      {:ok, pid} = Clock.Fake.start_link(initial: ~U[2024-01-01 00:00:00Z])
      %{clock: pid}
    end

    test "a timer fires only once virtual time reaches its due instant", %{clock: clock} do
      test = self()
      Clock.Fake.schedule(clock, [seconds: 10], fn -> send(test, :fired) end)

      Clock.Fake.advance(clock, seconds: 5)
      refute_receive :fired, 50

      Clock.Fake.advance(clock, seconds: 5)
      assert_receive :fired
    end

    test "advance returns the refs of timers it fired", %{clock: clock} do
      test = self()
      ref = Clock.Fake.schedule(clock, [seconds: 3], fn -> send(test, :ok) end)
      assert Clock.Fake.advance(clock, seconds: 5) == [ref]
    end

    test "timers fire in chronological order regardless of registration order", %{clock: clock} do
      test = self()
      # Registered late-first, then early — firing must reorder to :b before :a.
      Clock.Fake.schedule(clock, [seconds: 10], fn -> send(test, :a) end)
      Clock.Fake.schedule(clock, [seconds: 5], fn -> send(test, :b) end)

      fired = Clock.Fake.advance(clock, seconds: 20)
      assert length(fired) == 2
      assert drain(2) == [:b, :a]
    end

    test "cancel prevents a pending timer from firing", %{clock: clock} do
      test = self()
      ref = Clock.Fake.schedule(clock, [seconds: 5], fn -> send(test, :should_not_fire) end)

      assert Clock.Fake.cancel(clock, ref) == :ok
      assert Clock.Fake.advance(clock, seconds: 10) == []
      refute_receive :should_not_fire, 50
    end

    test "cancel returns :error for an unknown or already-fired ref", %{clock: clock} do
      ref = Clock.Fake.schedule(clock, [seconds: 1], fn -> :ok end)
      Clock.Fake.advance(clock, seconds: 2)
      assert Clock.Fake.cancel(clock, ref) == :error
      assert Clock.Fake.cancel(clock, 9999) == :error
    end

    test "pending/1 tracks outstanding timers", %{clock: clock} do
      Clock.Fake.schedule(clock, [seconds: 5], fn -> :ok end)
      Clock.Fake.schedule(clock, [seconds: 10], fn -> :ok end)
      assert Clock.Fake.pending(clock) == 2

      Clock.Fake.advance(clock, seconds: 5)
      assert Clock.Fake.pending(clock) == 1

      Clock.Fake.advance(clock, seconds: 10)
      assert Clock.Fake.pending(clock) == 0
    end
  end

  # -------------------------------------------------------
  # Clock.now/1 dispatch
  # -------------------------------------------------------

  describe "Clock.now/1 unified dispatch" do
    test "dispatches to Clock.Real when given the module atom" do
      assert %DateTime{} = Clock.now(Clock.Real)
    end

    test "dispatches to Clock.Fake when given a pid" do
      target = ~U[2025-03-20 09:30:00Z]
      {:ok, pid} = Clock.Fake.start_link(initial: target)
      assert Clock.now(pid) == target
    end

    test "dispatches to Clock.Fake when given a registered name" do
      target = ~U[2025-03-20 09:30:00Z]
      {:ok, _pid} = Clock.Fake.start_link(initial: target, name: :v1_named_clock)
      assert Clock.now(:v1_named_clock) == target
    end
  end

  # -------------------------------------------------------
  # Isolation
  # -------------------------------------------------------

  describe "isolation" do
    test "two clocks and their timers are independent" do
      test = self()
      {:ok, a} = Clock.Fake.start_link(initial: ~U[2024-01-01 00:00:00Z])
      {:ok, b} = Clock.Fake.start_link(initial: ~U[2024-01-01 00:00:00Z])

      Clock.Fake.schedule(a, [seconds: 5], fn -> send(test, :a_fired) end)
      Clock.Fake.schedule(b, [seconds: 5], fn -> send(test, :b_fired) end)

      Clock.Fake.advance(a, seconds: 10)
      assert_receive :a_fired
      refute_receive :b_fired, 50
      assert Clock.Fake.pending(b) == 1
      assert Clock.Fake.now(b) == ~U[2024-01-01 00:00:00Z]
    end
  end

  # -------------------------------------------------------
  # Injection pattern
  # -------------------------------------------------------

  describe "dependency injection pattern" do
    defmodule Reminder do
      @doc "Schedules a reminder callback `after` a delay, driven by the injected clock."
      def remind_in(clock, duration, fun), do: Clock.Fake.schedule(clock, duration, fun)
    end

    test "a scheduled reminder fires at the right virtual time" do
      # TODO
    end
  end

  test "timers due at the same instant fire in registration order" do
    test = self()
    {:ok, clock} = Clock.Fake.start_link(initial: ~U[2024-01-01 00:00:00Z])

    r1 = Clock.Fake.schedule(clock, [seconds: 5], fn -> send(test, :first) end)
    r2 = Clock.Fake.schedule(clock, [seconds: 5], fn -> send(test, :second) end)

    assert Clock.Fake.advance(clock, seconds: 5) == [r1, r2]
    assert drain(2) == [:first, :second]
  end

  test "a zero-duration timer stays pending until an advance call fires it" do
    test = self()
    {:ok, clock} = Clock.Fake.start_link(initial: ~U[2024-01-01 00:00:00Z])

    ref = Clock.Fake.schedule(clock, [seconds: 0], fn -> send(test, :now_due) end)
    refute_receive :now_due, 50
    assert Clock.Fake.pending(clock) == 1

    assert Clock.Fake.advance(clock, seconds: 0) == [ref]
    assert_receive :now_due
  end

  test "start_link without :initial starts at the documented default instant" do
    {:ok, clock} = Clock.Fake.start_link([])
    assert Clock.Fake.now(clock) == ~U[2024-01-01 00:00:00Z]
  end

  test "advance returns fired refs chronologically rather than by registration order" do
    {:ok, clock} = Clock.Fake.start_link(initial: ~U[2024-01-01 00:00:00Z])

    late = Clock.Fake.schedule(clock, [seconds: 10], fn -> :ok end)
    early = Clock.Fake.schedule(clock, [seconds: 5], fn -> :ok end)

    assert Clock.Fake.advance(clock, seconds: 20) == [early, late]
  end

  test "advance supports singular unit names and day units" do
    {:ok, clock} = Clock.Fake.start_link(initial: ~U[2024-01-01 00:00:00Z])

    Clock.Fake.advance(clock, day: 1, hour: 1, minute: 1, second: 1)
    assert Clock.Fake.now(clock) == ~U[2024-01-02 01:01:01Z]

    Clock.Fake.advance(clock, days: 2, minutes: 1)
    assert Clock.Fake.now(clock) == ~U[2024-01-04 01:02:01Z]
  end

  test "schedule hands out unique integer refs across cancelled and fired timers" do
    {:ok, clock} = Clock.Fake.start_link(initial: ~U[2024-01-01 00:00:00Z])

    a = Clock.Fake.schedule(clock, [seconds: 1], fn -> :ok end)
    b = Clock.Fake.schedule(clock, [seconds: 2], fn -> :ok end)
    assert Clock.Fake.cancel(clock, b) == :ok
    assert Clock.Fake.advance(clock, seconds: 5) == [a]
    c = Clock.Fake.schedule(clock, [seconds: 1], fn -> :ok end)

    refs = [a, b, c]
    assert Enum.all?(refs, &is_integer/1)
    assert Enum.uniq(refs) == refs
  end
end
```
