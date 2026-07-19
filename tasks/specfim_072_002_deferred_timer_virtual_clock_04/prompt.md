# Write the missing @spec

Below is a complete, working module — except that the `@spec` for
`schedule/3` has been removed; its place is marked `# TODO: @spec`.
Write exactly that typespec: one `@spec` attribute for `schedule/3`,
consistent with the function's arguments, guards, and every return shape
the implementation can produce. Change nothing else.

## The module with the `@spec` for `schedule/3` missing

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
  # TODO: @spec
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

Give me only the `@spec` attribute — the attribute alone (however many
lines it spans), not the whole module.
