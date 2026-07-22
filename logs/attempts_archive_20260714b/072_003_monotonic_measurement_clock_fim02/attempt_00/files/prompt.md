Implement the public `measure/2` function. It measures how much monotonic time a
0-arity function consumes. Read the monotonic clock in microseconds via
`monotonic(clock, :microsecond)` before invoking `fun`, then invoke `fun` and
capture its return value, then read the microsecond clock again. Return a tuple
`{result, elapsed_milliseconds}` where `result` is `fun`'s return value and
`elapsed_milliseconds` is the integer millisecond delta between the two readings,
computed with `div/2` on the microsecond difference (dividing by 1000). The
function head already guards that `fun` is a 0-arity function; leave that guard
intact.

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
    if function_exported?(clock, :monotonic, 1) do
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
    # TODO
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