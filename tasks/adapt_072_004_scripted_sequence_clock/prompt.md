# Adapt existing code to a new specification

Below is a complete, working, tested Elixir solution to a related task. Do not
start from scratch: treat it as the codebase you have been asked to change.
Modify it to satisfy the new specification that follows — keep whatever carries
over, and change, add, or remove whatever the new specification requires.

Where the existing code and the new specification disagree (module name, public
API, behavior, constraints, output format), the new specification wins. Give me
the complete final result.

## Existing code (your starting point)

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

## New specification

Write me an Elixir `Clock` behaviour and two implementations — one for production, one for testing — in a single file. This variation makes the fake clock **scripted**: instead of a single frozen value, it returns a predetermined sequence of timestamps, one per read, which is ideal for testing code that reads the clock several times.

The behaviour should define one callback: `now/0`, returning the current time as a `DateTime`.

The production implementation `Clock.Real` should implement `now/0` by delegating to `DateTime.utc_now()`.

The test implementation `Clock.Fake` should be a `GenServer` with the following public API:
- `Clock.Fake.start_link(opts)` — starts the process. Accepts:
  - `:script` — a non-empty list of `DateTime`s to hand out, one per `now/1` call (defaults to `[~U[2024-01-01 00:00:00Z]]`).
  - `:on_exhaust` — the policy applied once the script is consumed. One of `:repeat_last` (default — keep returning the final value), `:cycle` (wrap around to the start), or `:raise` (raise a `RuntimeError`).
  - `:name` — an optional registration name.
  - Starting with an empty script, a non-`DateTime` element, or an unknown policy must fail to start.
- `Clock.Fake.now(server)` — returns the next scripted `DateTime`, advancing the internal cursor. Behaviour after the script is exhausted follows `:on_exhaust`.
- `Clock.Fake.remaining(server)` — returns how many scripted values have not yet been consumed.
- `Clock.Fake.reset(server)` — rewinds the cursor to the beginning of the script.
- `Clock.Fake.push(server, datetimes)` — appends more `DateTime`s to the end of the script.

Additionally, provide a top-level `Clock` module with a `now/1` function that accepts a module name (`Clock.Real`) or a `Clock.Fake` PID/registered name and dispatches correctly — calling `Clock.Real.now()` or `Clock.Fake.now(server)` depending on the argument. This lets application code accept a `:clock` dependency-injection option and call `Clock.now(clock)` uniformly.

Give me the complete implementation in a single file with no external dependencies, using only the Elixir standard library and OTP.
