Implement the `handle_call/3` GenServer callback for `Clock.Fake`. It is the
message-handling core of the virtual clock and must cover five distinct calls
(one clause per message):

1. `:now` — reply with the current virtual time (`state.time`) and leave the
   state unchanged.

2. `:pending` — reply with the number of timers still registered (the length of
   `state.timers`), leaving the state unchanged.

3. `{:schedule, duration, fun}` — compute the due instant by applying `duration`
   to the current time via the `apply_duration/2` helper. Take the next timer
   ref from `state.next_ref`, build a timer map `%{ref: ref, at: at, seq:
   state.next_seq, fun: fun}`, and prepend it to `state.timers`. Increment both
   `next_seq` and `next_ref` in the updated state. Reply with the new `ref`.

4. `{:cancel, ref}` — split `state.timers` into the timer(s) matching `ref` and
   the rest. Reply `:ok` if something matched, otherwise `:error`, and keep only
   the remaining timers in the state.

5. `{:advance, duration}` — compute the new virtual time by applying `duration`
   to the current time. Split the timers into those that are due (their `at` is
   at or before the new time — `DateTime.compare/2` returns `:lt` or `:eq`) and
   those still pending. Order the due timers chronologically, breaking ties by
   registration order, using `{DateTime.to_unix(at, :microsecond), seq}` as the
   sort key. Execute each due timer's `fun` in that order. Reply with the list
   of fired refs (in fire order) and update the state's `time` to the new time
   and `timers` to the remaining pending timers.

Annotate your `handle_call/3` clauses with `@impl GenServer` (the first clause is
enough) to stay consistent with the already-annotated `init/1` callback.

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
  def init(%DateTime{} = initial), do: {:ok, %__MODULE__{time: initial}}

  def handle_call(:now, _from, state) do
    # TODO
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