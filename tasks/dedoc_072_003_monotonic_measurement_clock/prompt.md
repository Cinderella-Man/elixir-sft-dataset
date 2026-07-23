# Restore the documentation

The module below works and is fully tested — its behavior is final. What it
lost is every piece of documentation. Put it back:

- a `@moduledoc` covering purpose and usage,
- a `@doc` on each public function,
- a `@spec` on each public function (plus `@type`s where they clarify).

And keep your hands off the code itself: no renames, no refactors, no added
or removed functions, identical behavior everywhere. Return the whole
documented module in one file.

## The module

```elixir
defmodule Clock do
  @callback monotonic(unit :: System.time_unit()) :: integer()

  def monotonic(clock, unit \\ :millisecond)

  def monotonic(clock, unit) when is_atom(clock) do
    if function_exported?(clock, :monotonic, 1) do
      clock.monotonic(unit)
    else
      Clock.Fake.monotonic(clock, unit)
    end
  end

  def monotonic(clock, unit), do: Clock.Fake.monotonic(clock, unit)

  def measure(clock, fun) when is_function(fun, 0) do
    t0 = monotonic(clock, :microsecond)
    result = fun.()
    t1 = monotonic(clock, :microsecond)
    {result, div(t1 - t0, 1000)}
  end
end

# ---------------------------------------------------------------------------

defmodule Clock.Real do
  @behaviour Clock

  @impl Clock
  def monotonic(unit), do: System.monotonic_time(unit)
end

# ---------------------------------------------------------------------------

defmodule Clock.Fake do
  use GenServer

  @default_initial_ms 0

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def start_link(opts \\ []) do
    {initial_ms, opts} = Keyword.pop(opts, :initial, @default_initial_ms)
    {name_opt, _rest} = Keyword.pop(opts, :name)
    gen_opts = if name_opt, do: [name: name_opt], else: []
    # Store the counter in microseconds internally.
    GenServer.start_link(__MODULE__, initial_ms * 1000, gen_opts)
  end

  def monotonic(server, unit \\ :millisecond), do: GenServer.call(server, {:monotonic, unit})

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
