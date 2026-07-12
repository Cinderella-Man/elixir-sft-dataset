# Fix the bug

The module below was written for the task that follows, but ONE behavior bug
slipped in. The test suite (not shown) fails with the report at the bottom.
Find the bug and fix it — change as little as possible; do not restructure
working code. Reply with the complete corrected module.

## The task the module implements

Write me an Elixir `Clock` behaviour and two implementations — one for production, one for testing — in a single file. This variation is about **monotonic elapsed-time measurement** rather than wall-clock timestamps: the clock exposes a monotonically increasing integer counter (like `System.monotonic_time/1`) and a helper to measure how much time a function "takes".

The behaviour should define one callback: `monotonic/1`, which takes a time unit and returns the current monotonic time as an `integer` in that unit.

The production implementation `Clock.Real` should implement `monotonic/1` by delegating to `System.monotonic_time/1`.

The test implementation `Clock.Fake` should be a `GenServer` with the following public API:
- `Clock.Fake.start_link(opts)` — starts the process. Accepts an optional `:initial` integer offset **in milliseconds** (defaults to `0`) and an optional `:name` for registration.
- `Clock.Fake.monotonic(server, unit \\ :millisecond)` — returns the current monotonic value converted to `unit`. Support at least `:second`, `:millisecond`, `:microsecond`, and `:nanosecond`.
- `Clock.Fake.advance(server, duration)` — moves the counter forward. `duration` is a keyword list like `[milliseconds: 250]` or `[seconds: 2, milliseconds: 500]` (supported units: `:microsecond(s)`, `:millisecond(s)`, `:second(s)`, `:minute(s)`, `:hour(s)`).

Additionally, provide a top-level `Clock` module with:
- `Clock.monotonic(clock, unit \\ :millisecond)` — dispatches to `Clock.Real.monotonic(unit)` when given the `Clock.Real` module atom, or to `Clock.Fake.monotonic(server, unit)` when given a `Clock.Fake` PID/registered name.
- `Clock.measure(clock, fun)` — reads the monotonic clock (in microseconds) before and after invoking the 0-arity `fun`, and returns `{result, elapsed_milliseconds}` where `result` is `fun`'s return value and `elapsed_milliseconds` is the integer millisecond delta. With `Clock.Fake`, `fun` advancing the clock makes elapsed time fully deterministic.

Give me the complete implementation in a single file with no external dependencies, using only the Elixir standard library and OTP.

## The buggy module

```elixir
defmodule Clock do
  @moduledoc """
  Behaviour and dispatcher for monotonic clock implementations.

  Unlike a wall-clock helper, this exposes a monotonically increasing integer
  counter (like `System.monotonic_time/1`) plus `measure/2`, so tests can drive
  elapsed-time measurement deterministically.

  ## Usage

      # Production
      Clock.monotonic(Clock.Real, :millisecond)

      # Tests — advance a fake to control measured durations
      {:ok, c} = Clock.Fake.start_link([])
      {result, ms} = Clock.measure(c, fn ->
        Clock.Fake.advance(c, milliseconds: 250)
        :ok
      end)
      # => {:ok, 250}
  """

  @doc "Returns the current monotonic time as an integer in `unit`."
  @callback monotonic(unit :: System.time_unit()) :: integer()

  @doc "Dispatches `monotonic/1` to the correct implementation."
  @spec monotonic(module() | GenServer.server(), System.time_unit()) :: integer()
  def monotonic(clock, unit \\ :millisecond)

  def monotonic(clock, unit) when is_atom(clock) do
    if function_exported?(clock, :monotonic, 2) do
      clock.monotonic(unit)
    else
      Clock.Fake.monotonic(clock, unit)
    end
  end

  def monotonic(clock, unit), do: Clock.Fake.monotonic(clock, unit)

  @doc """
  Measures how much monotonic time `fun` consumes.

  Reads the clock in microseconds before and after `fun`, and returns
  `{fun_result, elapsed_milliseconds}` (integer millisecond delta).
  """
  @spec measure(module() | GenServer.server(), (-> any())) :: {any(), non_neg_integer()}
  def measure(clock, fun) when is_function(fun, 0) do
    t0 = monotonic(clock, :microsecond)
    result = fun.()
    t1 = monotonic(clock, :microsecond)
    {result, div(t1 - t0, 1000)}
  end
end

# ---------------------------------------------------------------------------

defmodule Clock.Real do
  @moduledoc "Production monotonic clock — delegates straight to the VM."

  @behaviour Clock

  @impl Clock
  @spec monotonic(System.time_unit()) :: integer()
  def monotonic(unit), do: System.monotonic_time(unit)
end

# ---------------------------------------------------------------------------

defmodule Clock.Fake do
  @moduledoc """
  A controllable, process-based monotonic clock for tests.

  The counter is held internally in microseconds and only moves when you call
  `advance/2`, so measured durations are fully deterministic.

  ## Starting

      {:ok, c} = Clock.Fake.start_link([])                 # starts at 0
      {:ok, c} = Clock.Fake.start_link(initial: 1000)      # starts at 1000 ms
  """

  use GenServer

  @default_initial_ms 0

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {initial_ms, opts} = Keyword.pop(opts, :initial, @default_initial_ms)
    {name_opt, _rest} = Keyword.pop(opts, :name)
    gen_opts = if name_opt, do: [name: name_opt], else: []
    # Store the counter in microseconds internally.
    GenServer.start_link(__MODULE__, initial_ms * 1000, gen_opts)
  end

  @doc "Returns the current monotonic value converted to `unit`."
  @spec monotonic(GenServer.server(), System.time_unit()) :: integer()
  def monotonic(server, unit \\ :millisecond), do: GenServer.call(server, {:monotonic, unit})

  @doc "Moves the counter forward by `duration` (a keyword list of time units)."
  @spec advance(GenServer.server(), keyword()) :: :ok
  def advance(server, duration) when is_list(duration),
    do: GenServer.call(server, {:advance, duration})

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init(micros) when is_integer(micros), do: {:ok, micros}

  @impl GenServer
  def handle_call({:monotonic, unit}, _from, micros) do
    {:reply, convert(micros, unit), micros}
  end

  def handle_call({:advance, duration}, _from, micros) do
    {:reply, :ok, micros + duration_to_micros(duration)}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp convert(micros, :microsecond), do: micros
  defp convert(micros, :millisecond), do: div(micros, 1_000)
  defp convert(micros, :second), do: div(micros, 1_000_000)
  defp convert(micros, :nanosecond), do: micros * 1_000

  @unit_micros %{
    microsecond: 1,
    microseconds: 1,
    millisecond: 1_000,
    milliseconds: 1_000,
    second: 1_000_000,
    seconds: 1_000_000,
    minute: 60_000_000,
    minutes: 60_000_000,
    hour: 3_600_000_000,
    hours: 3_600_000_000
  }

  defp duration_to_micros(duration) do
    Enum.reduce(duration, 0, fn {unit, amount}, acc ->
      acc + amount * Map.fetch!(@unit_micros, unit)
    end)
  end
end
```

## Failing test report

```
2 of 18 test(s) failed:

  * test Clock.measure/2 works with the real clock and yields a non-negative elapsed
      :exit: {:noproc, {GenServer, :call, [Clock.Real, {:monotonic, :microsecond}, 5000]}}

  * test Clock.monotonic/2 unified dispatch dispatches to Clock.Real when given the module atom
      :exit: {:noproc, {GenServer, :call, [Clock.Real, {:monotonic, :second}, 5000]}}
```
