# Debug and repair this module

A colleague shipped the module below for the task described next, and one
behavior bug made it through review. The test suite (not shown here)
produces the failure report at the bottom. Track the bug down and repair
it — keep the diff minimal and leave working code exactly as it is. Reply
with the complete corrected module.

## What the module is supposed to do

Write me an Elixir `Clock` behaviour and two implementations — one for production, one for testing — in a single file. This variation adds a **deterministic virtual-time scheduler**: the fake clock can register deferred callbacks that fire when virtual time is advanced past their due instant.

The behaviour should define one callback: `now/0`, returning the current time as a `DateTime`.

The production implementation `Clock.Real` should implement `now/0` by delegating to `DateTime.utc_now()`.

The test implementation `Clock.Fake` should be a `GenServer` with the following public API:
- `Clock.Fake.start_link(opts)` — starts the process. Accepts an optional `:initial` datetime (defaults to `~U[2024-01-01 00:00:00Z]`) and an optional `:name` for registration.
- `Clock.Fake.now(server)` — returns the current virtual datetime.
- `Clock.Fake.advance(server, duration)` — moves virtual time forward. `duration` is a keyword list like `[seconds: 30]` or `[hours: 1, minutes: 30]` (supported units: `:second(s)`, `:minute(s)`, `:hour(s)`, `:day(s)`). Advancing must **fire every registered timer whose due instant is at or before the new virtual time**, executing their functions in chronological order (ties broken by registration order). It returns the list of fired timer refs, in fire order.
- `Clock.Fake.schedule(server, duration, fun)` — registers a 0-arity function `fun` to run when virtual time reaches `now + duration`. Returns a unique integer timer ref. Timers only ever fire during an `advance/2` call (never at scheduling time).
- `Clock.Fake.cancel(server, ref)` — cancels a still-pending timer. Returns `:ok` if it was pending, `:error` otherwise.
- `Clock.Fake.pending(server)` — returns the count of timers not yet fired or cancelled.

Additionally, provide a top-level `Clock` module with a `now/1` function that accepts a module name (`Clock.Real`) or a `Clock.Fake` PID/registered name and dispatches correctly — calling `Clock.Real.now()` or `Clock.Fake.now(server)` depending on the argument. This lets application code accept a `:clock` dependency-injection option and call `Clock.now(clock)` uniformly.

Give me the complete implementation in a single file with no external dependencies, using only the Elixir standard library and OTP.

## The buggy module

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
    # ensure_loaded?/1 first: function_exported?/3 deliberately does NOT load
    # the module, so under lazy loading a real clock module's first use would
    # fall through to the Fake branch and exit :noproc.
    if Code.ensure_loaded?(clock) and function_exported?(clock, :now, 0) do
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
  def init(%DateTime{} = initial), do: {:error, %__MODULE__{time: initial}}

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

## Failing test report

```
19 of 21 test(s) failed:

  * test Clock.Fake basics now/1 returns the frozen datetime
      no match of right hand side value:
      
          {:error,
           %Clock.Fake{
             time: ~U[2024-06-15 12:00:00Z],
             timers: [],
             next_seq: 0,
             next_ref: 0
           }}
      

  * test Clock.Fake basics advance moves virtual time forward
      no match of right hand side value:
      
          {:error,
           %Clock.Fake{
             time: ~U[2024-06-15 12:00:00Z],
             timers: [],
             next_seq: 0,
             next_ref: 0
           }}
      

  * test Clock.Fake basics advance is cumulative
      no match of right hand side value:
      
          {:error,
           %Clock.Fake{
             time: ~U[2024-06-15 12:00:00Z],
             timers: [],
             next_seq: 0,
             next_ref: 0
           }}
      

  * test Clock.Fake deferred timers a timer fires only once virtual time reaches its due instant
      no match of right hand side value:
      
          {:error,
           %Clock.Fake{
             time: ~U[2024-01-01 00:00:00Z],
             timers: [],
             next_seq: 0,
             next_ref: 0
           }}
      

  (…15 more)
```
