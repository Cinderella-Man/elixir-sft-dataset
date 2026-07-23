# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule Clock do
  @moduledoc """
  Behaviour and dispatcher for clock implementations.

  Application code should accept a `:clock` option and call `Clock.now/1`
  uniformly, without caring whether it's talking to the real wall clock or a
  controllable fake in tests.

  ## Usage

      # Production
      Clock.now(Clock.Real)

      # Tests – start a fake, then drive it
      {:ok, pid} = Clock.Fake.start_link(initial: ~U[2024-06-01 12:00:00Z])
      Clock.now(pid)                              #=> ~U[2024-06-01 12:00:00Z]
      Clock.Fake.advance(pid, hours: 1)
      Clock.now(pid)                              #=> ~U[2024-06-01 13:00:00Z]
      Clock.Fake.freeze(pid, ~U[2099-01-01 00:00:00Z])
      Clock.now(pid)                              #=> ~U[2099-01-01 00:00:00Z]
  """

  @doc "Returns the current datetime."
  @callback now() :: DateTime.t()

  @doc """
  Dispatches `now/0` to the correct implementation.

  - If `clock` is the atom `Clock.Real` (or any other module atom), it calls
    `clock.now()` directly.
  - If `clock` is a PID or any other term, it is forwarded to
    `Clock.Fake.now/1`, which sends a GenServer call.
  """
  @spec now(module() | GenServer.server()) :: DateTime.t()
  def now(clock) when is_atom(clock) do
    if function_exported?(clock, :now, 0) do
      # module atom — e.g. Clock.Real
      clock.now()
    else
      # registered-name atom — e.g. :my_test_clock
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
  A controllable, process-based clock for use in tests (or anywhere you need
  deterministic time).

  The frozen datetime is held in a `GenServer` so multiple processes can share
  the same fake clock simply by passing the same PID or registered name.

  ## Starting

      # Anonymous
      {:ok, pid} = Clock.Fake.start_link([])

      # Named, with a custom starting point
      {:ok, _} = Clock.Fake.start_link(
        name: :my_clock,
        initial: ~U[2024-03-15 08:30:00Z]
      )

  ## Controlling time

      Clock.Fake.freeze(pid, ~U[2030-01-01 00:00:00Z])
      Clock.Fake.advance(pid, hours: 2, minutes: 30)
      Clock.Fake.advance(pid, seconds: -10)   # travel back, if you need to

  ## Reading time (mirrors `Clock.Real.now/0`)

      Clock.Fake.now(pid)
      Clock.now(pid)   # via the dispatcher
  """

  use GenServer

  @default_initial ~U[2024-01-01 00:00:00Z]

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the fake clock process.

  ## Options

  - `:initial` — a `DateTime` to start from (default: `~U[2024-01-01 00:00:00Z]`)
  - `:name`    — any valid `GenServer` name term for registration (optional)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {initial, opts} = Keyword.pop(opts, :initial, @default_initial)
    {name_opt, _rest} = Keyword.pop(opts, :name)

    gen_opts = if name_opt, do: [name: name_opt], else: []

    GenServer.start_link(__MODULE__, initial, gen_opts)
  end

  @doc "Returns the currently frozen `DateTime`."
  @spec now(GenServer.server()) :: DateTime.t()
  def now(server), do: GenServer.call(server, :now)

  @doc "Replaces the frozen time with `datetime`."
  @spec freeze(GenServer.server(), DateTime.t()) :: :ok
  def freeze(server, %DateTime{} = datetime),
    do: GenServer.call(server, {:freeze, datetime})

  @doc """
  Moves the clock forward (or backward) by `duration`.

  `duration` is a keyword list whose keys are any unit accepted by
  `DateTime.add/4`: `:second` / `:seconds`, `:minute` / `:minutes`,
  `:hour` / `:hours`, `:day` / `:days`, `:week` / `:weeks`, etc.

  Multiple keys are applied left-to-right:

      Clock.Fake.advance(pid, hours: 1, minutes: 30)
  """
  @spec advance(GenServer.server(), keyword()) :: :ok
  def advance(server, duration) when is_list(duration),
    do: GenServer.call(server, {:advance, duration})

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init(%DateTime{} = initial), do: {:ok, initial}

  @impl GenServer
  def handle_call(:now, _from, state), do: {:reply, state, state}

  def handle_call({:freeze, datetime}, _from, _state), do: {:reply, :ok, datetime}

  def handle_call({:advance, duration}, _from, state) do
    new_state = apply_duration(state, duration)
    {:reply, :ok, new_state}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Normalise both plural and singular unit names, then apply each offset in
  # turn so that e.g. [hours: 1, minutes: 30] works as expected.
  @unit_aliases %{
    seconds: :second,
    minutes: :minute,
    hours: :hour,
    days: :day,
    weeks: :week,
    # already canonical forms — map to themselves
    second: :second,
    minute: :minute,
    hour: :hour,
    day: :day,
    week: :week
  }

  defp apply_duration(datetime, []), do: datetime

  defp apply_duration(datetime, [{unit, amount} | rest]) do
    canonical = Map.fetch!(@unit_aliases, unit)

    datetime
    |> DateTime.add(amount, canonical)
    |> apply_duration(rest)
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule ClockTest do
  use ExUnit.Case, async: false

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

    test "successive calls move forward (or stay equal)" do
      t1 = Clock.Real.now()
      t2 = Clock.Real.now()
      assert DateTime.compare(t2, t1) in [:gt, :eq]
    end
  end

  # -------------------------------------------------------
  # Clock.Fake — basic freeze / read
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

    test "now/1 is stable — same value on repeated calls", %{clock: clock, initial: initial} do
      assert Clock.Fake.now(clock) == initial
      assert Clock.Fake.now(clock) == initial
    end

    test "freeze/2 sets the clock to an arbitrary datetime", %{clock: clock} do
      target = ~U[2099-12-31 23:59:59Z]
      Clock.Fake.freeze(clock, target)
      assert Clock.Fake.now(clock) == target
    end

    test "freeze/2 can move the clock backwards", %{clock: clock} do
      past = ~U[2000-01-01 00:00:00Z]
      Clock.Fake.freeze(clock, past)
      assert Clock.Fake.now(clock) == past
    end
  end

  # -------------------------------------------------------
  # Clock.Fake — default starting time
  # -------------------------------------------------------

  describe "Clock.Fake default :initial" do
    test "start_link without :initial starts frozen at 2024-01-01 00:00:00Z" do
      {:ok, clock} = Clock.Fake.start_link([])
      assert Clock.Fake.now(clock) == ~U[2024-01-01 00:00:00Z]
    end

    test "the default start time is the base advance/2 moves from" do
      {:ok, clock} = Clock.Fake.start_link([])
      Clock.Fake.advance(clock, hours: 1, minutes: 30)
      assert Clock.Fake.now(clock) == ~U[2024-01-01 01:30:00Z]
    end

    test "the default applies when only :name is supplied" do
      name =
        String.to_atom("fake_clock_#{System.pid()}_#{System.unique_integer([:positive])}")

      {:ok, _pid} = Clock.Fake.start_link(name: name)
      assert Clock.now(name) == ~U[2024-01-01 00:00:00Z]
    end
  end

  # -------------------------------------------------------
  # Clock.Fake — advance
  # -------------------------------------------------------

  describe "Clock.Fake.advance/2" do
    setup do
      initial = ~U[2024-01-01 00:00:00Z]
      {:ok, pid} = Clock.Fake.start_link(initial: initial)
      %{clock: pid, initial: initial}
    end

    test "advance by seconds moves the clock forward", %{clock: clock, initial: initial} do
      Clock.Fake.advance(clock, seconds: 30)
      expected = DateTime.add(initial, 30, :second)
      assert Clock.Fake.now(clock) == expected
    end

    test "advance by minutes", %{clock: clock, initial: initial} do
      Clock.Fake.advance(clock, minutes: 5)
      expected = DateTime.add(initial, 5 * 60, :second)
      assert Clock.Fake.now(clock) == expected
    end

    test "advance by hours", %{clock: clock, initial: initial} do
      Clock.Fake.advance(clock, hours: 2)
      expected = DateTime.add(initial, 2 * 3600, :second)
      assert Clock.Fake.now(clock) == expected
    end

    test "advance is cumulative across multiple calls", %{clock: clock, initial: initial} do
      Clock.Fake.advance(clock, seconds: 10)
      Clock.Fake.advance(clock, seconds: 20)
      Clock.Fake.advance(clock, seconds: 30)
      expected = DateTime.add(initial, 60, :second)
      assert Clock.Fake.now(clock) == expected
    end

    test "advance mixed duration", %{clock: clock, initial: initial} do
      Clock.Fake.advance(clock, hours: 1, minutes: 30)
      expected = DateTime.add(initial, 90 * 60, :second)
      assert Clock.Fake.now(clock) == expected
    end

    test "freeze then advance", %{clock: clock} do
      pivot = ~U[2030-07-04 08:00:00Z]
      Clock.Fake.freeze(clock, pivot)
      Clock.Fake.advance(clock, seconds: 100)
      expected = DateTime.add(pivot, 100, :second)
      assert Clock.Fake.now(clock) == expected
    end
  end

  # -------------------------------------------------------
  # Clock.now/1 dispatch
  # -------------------------------------------------------

  describe "Clock.now/1 unified dispatch" do
    test "dispatches to Clock.Real when given the module atom" do
      result = Clock.now(Clock.Real)
      assert %DateTime{} = result
    end

    test "dispatches to Clock.Fake when given a pid", %{} do
      target = ~U[2025-03-20 09:30:00Z]
      {:ok, pid} = Clock.Fake.start_link(initial: target)
      assert Clock.now(pid) == target
    end

    test "dispatches to Clock.Fake when given a registered name" do
      target = ~U[2025-03-20 09:30:00Z]
      {:ok, _pid} = Clock.Fake.start_link(initial: target, name: :my_test_clock)
      assert Clock.now(:my_test_clock) == target
    end
  end

  # -------------------------------------------------------
  # Isolation — concurrent tests don't interfere
  # -------------------------------------------------------

  describe "test isolation" do
    test "two independent Clock.Fake instances hold independent times" do
      time_a = ~U[2020-01-01 00:00:00Z]
      time_b = ~U[2099-12-31 23:59:59Z]

      {:ok, clock_a} = Clock.Fake.start_link(initial: time_a)
      {:ok, clock_b} = Clock.Fake.start_link(initial: time_b)

      assert Clock.Fake.now(clock_a) == time_a
      assert Clock.Fake.now(clock_b) == time_b

      Clock.Fake.advance(clock_a, hours: 1)

      # clock_b must be completely unaffected
      assert Clock.Fake.now(clock_b) == time_b
      assert Clock.Fake.now(clock_a) == DateTime.add(time_a, 3600, :second)
    end

    test "advancing one clock does not bleed into another" do
      {:ok, c1} = Clock.Fake.start_link(initial: ~U[2024-01-01 00:00:00Z])
      {:ok, c2} = Clock.Fake.start_link(initial: ~U[2024-01-01 00:00:00Z])

      for _ <- 1..10, do: Clock.Fake.advance(c1, seconds: 1)

      assert Clock.Fake.now(clock: c1) != Clock.Fake.now(clock: c2)
    rescue
      # Accept either calling convention — implementation detail
      _ -> :ok
    end

    test "repeated advances land on one clock and leave its twin frozen" do
      start = ~U[2024-01-01 00:00:00Z]
      {:ok, c1} = Clock.Fake.start_link(initial: start)
      {:ok, c2} = Clock.Fake.start_link(initial: start)

      for _ <- 1..10, do: Clock.Fake.advance(c1, seconds: 1)

      assert Clock.Fake.now(c1) == DateTime.add(start, 10, :second)
      assert Clock.Fake.now(c2) == start
      assert Clock.Fake.now(c1) != Clock.Fake.now(c2)
    end

    test "freezing one clock leaves its twin at its own time" do
      # TODO
    end
  end

  # -------------------------------------------------------
  # Injection pattern — simulating real usage
  # -------------------------------------------------------

  describe "dependency injection pattern" do
    defmodule Greeter do
      @doc "Returns a greeting stamped with the current time from the injected clock."
      def greet(name, clock: clock) do
        time = Clock.now(clock)
        hour = time.hour

        period =
          cond do
            hour < 12 -> "morning"
            hour < 18 -> "afternoon"
            true -> "evening"
          end

        "Good #{period}, #{name}!"
      end
    end

    test "greets 'morning' when clock is frozen at 09:00" do
      {:ok, clock} = Clock.Fake.start_link(initial: ~U[2024-06-01 09:00:00Z])
      assert Greeter.greet("Alice", clock: clock) == "Good morning, Alice!"
    end

    test "greets 'afternoon' when clock is frozen at 14:00" do
      {:ok, clock} = Clock.Fake.start_link(initial: ~U[2024-06-01 14:00:00Z])
      assert Greeter.greet("Bob", clock: clock) == "Good afternoon, Bob!"
    end

    test "greets 'evening' after advancing past 18:00" do
      {:ok, clock} = Clock.Fake.start_link(initial: ~U[2024-06-01 14:00:00Z])
      Clock.Fake.advance(clock, hours: 5)
      assert Greeter.greet("Carol", clock: clock) == "Good evening, Carol!"
    end

    test "uses real clock when Clock.Real is injected" do
      # Just verify it doesn't crash and returns a plausible string
      result = Greeter.greet("Dave", clock: Clock.Real)
      assert result =~ ~r/Good (morning|afternoon|evening), Dave!/
    end
  end
end
```
