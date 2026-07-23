# Implement the missing function

The specification below is followed by its complete, tested solution —
minus `reset`, whose clause bodies are all `# TODO`. Supply that one
function; the rest of the module is fixed and must stay exactly as shown.

## The task

Write me an Elixir `Clock` behaviour and two implementations — one for production, one for testing — in a single file. This variation makes the fake clock **scripted**: instead of a single frozen value, it returns a predetermined sequence of timestamps, one per read, which is ideal for testing code that reads the clock several times.

The behaviour should define one callback: `now/0`, returning the current time as a `DateTime`.

The production implementation `Clock.Real` should implement `now/0` by delegating to `DateTime.utc_now()`.

The test implementation `Clock.Fake` should be a `GenServer` with the following public API:
- `Clock.Fake.start_link(opts)` — starts the process. Accepts:
  - `:script` — a non-empty list of `DateTime`s to hand out, one per `now/1` call (defaults to `[~U[2024-01-01 00:00:00Z]]`).
  - `:on_exhaust` — the policy applied once the script is consumed. One of `:repeat_last` (default — keep returning the final value), `:cycle` (wrap around to the start), or `:raise` — every further `now/1` call raises a `RuntimeError` **in the process calling `now/1`**. Implement `:raise` by having the server reply that the script is exhausted and letting the `now/1` client function raise: a raise inside the GenServer callback would crash the clock and turn the caller's call into an exit rather than a catchable raise.
  - `:name` — an optional registration name.
  - Starting must fail (`start_link` returns an `{:error, reason}` tuple) when validation fails: an empty script returns `{:error, :empty_script}`, a script containing a non-`DateTime` element returns `{:error, :invalid_script}`, and an unknown `:on_exhaust` policy returns `{:error, :invalid_policy}`.
- `Clock.Fake.now(server)` — returns the next scripted `DateTime`, advancing the internal cursor. Behaviour after the script is exhausted follows `:on_exhaust`.
- `Clock.Fake.remaining(server)` — returns how many scripted values have not yet been consumed (never negative; `0` once exhausted).
- `Clock.Fake.reset(server)` — rewinds the cursor to the beginning of the script.
- `Clock.Fake.push(server, datetimes)` — appends more `DateTime`s to the end of the script.

Additionally, provide a top-level `Clock` module with a `now/1` function that accepts a module name (`Clock.Real`) or a `Clock.Fake` PID/registered name and dispatches correctly — calling `Clock.Real.now()` or `Clock.Fake.now(server)` depending on the argument. This lets application code accept a `:clock` dependency-injection option and call `Clock.now(clock)` uniformly.

Give me the complete implementation in a single file with no external dependencies, using only the Elixir standard library and OTP.

## The module with `reset` missing

```elixir
defmodule Clock do
  @moduledoc """
  Behaviour and dispatcher for clock implementations.

  In this variation the fake clock is *scripted*: it hands out a predetermined
  sequence of timestamps, one per read. Application code accepts a `:clock`
  option and calls `Clock.now/1` uniformly, unaware of what backs it.

  ## Usage

      {:ok, c} = Clock.Fake.start_link(script: [
        ~U[2024-06-01 12:00:00Z],
        ~U[2024-06-01 12:00:42Z]
      ])
      Clock.now(c)   #=> ~U[2024-06-01 12:00:00Z]
      Clock.now(c)   #=> ~U[2024-06-01 12:00:42Z]
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
  A scripted, process-based clock for tests.

  Each call to `now/1` returns the next `DateTime` in the script and advances an
  internal cursor. Once the script is consumed, the `:on_exhaust` policy decides
  what happens next: `:repeat_last`, `:cycle`, or `:raise`.

  ## Starting

      {:ok, c} = Clock.Fake.start_link(
        script: [~U[2024-01-01 00:00:00Z], ~U[2024-01-01 00:00:05Z]],
        on_exhaust: :cycle
      )
  """

  use GenServer

  @default_initial ~U[2024-01-01 00:00:00Z]
  @policies [:repeat_last, :cycle, :raise]

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {script, opts} = Keyword.pop(opts, :script, [@default_initial])
    {policy, opts} = Keyword.pop(opts, :on_exhaust, :repeat_last)
    {name_opt, _rest} = Keyword.pop(opts, :name)
    gen_opts = if name_opt, do: [name: name_opt], else: []
    GenServer.start_link(__MODULE__, {script, policy}, gen_opts)
  end

  @doc "Returns the next scripted `DateTime`, advancing the cursor."
  @spec now(GenServer.server()) :: DateTime.t()
  def now(server) do
    case GenServer.call(server, :now) do
      {:ok, dt} -> dt
      {:error, :exhausted} -> raise "Clock.Fake: scripted time sequence exhausted"
    end
  end

  @doc "Returns how many scripted values have not yet been consumed."
  @spec remaining(GenServer.server()) :: non_neg_integer()
  def remaining(server), do: GenServer.call(server, :remaining)

  def reset(server) do
    # TODO
  end

  @doc "Appends more `DateTime`s to the end of the script."
  @spec push(GenServer.server(), [DateTime.t()]) :: :ok
  def push(server, datetimes) when is_list(datetimes),
    do: GenServer.call(server, {:push, datetimes})

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init({script, policy}) do
    cond do
      script == [] -> {:stop, :empty_script}
      not Enum.all?(script, &match?(%DateTime{}, &1)) -> {:stop, :invalid_script}
      policy not in @policies -> {:stop, :invalid_policy}
      true -> {:ok, %{script: script, index: 0, policy: policy}}
    end
  end

  @impl GenServer
  def handle_call(:now, _from, %{script: script, index: index, policy: policy} = state) do
    len = length(script)

    cond do
      index < len ->
        {:reply, {:ok, Enum.at(script, index)}, %{state | index: index + 1}}

      policy == :repeat_last ->
        {:reply, {:ok, List.last(script)}, state}

      policy == :cycle ->
        {:reply, {:ok, Enum.at(script, rem(index, len))}, %{state | index: index + 1}}

      policy == :raise ->
        {:reply, {:error, :exhausted}, state}
    end
  end

  def handle_call(:remaining, _from, %{script: script, index: index} = state) do
    {:reply, max(0, length(script) - index), state}
  end

  def handle_call(:reset, _from, state), do: {:reply, :ok, %{state | index: 0}}

  def handle_call({:push, datetimes}, _from, state) do
    {:reply, :ok, %{state | script: state.script ++ datetimes}}
  end
end
```

Output only `reset` (with any `@doc`/`@spec`/`@impl` lines that belong
directly above it) — the single function, not the module.
