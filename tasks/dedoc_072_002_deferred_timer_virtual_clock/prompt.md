# Document this module

Below is a complete, working, tested Elixir module. Its behavior is correct
and must not change — but every piece of documentation has been stripped.

Add the missing documentation and typespecs:

- a `@moduledoc` that explains what the module does and how it is used,
- a `@doc` for every public function,
- a `@spec` for every public function (add `@type`s where they make the
  specs clearer).

Do not change any behavior: every function clause, guard, and expression
must keep working exactly as it does now. Do not rename anything, do not
"improve" the code, and do not add or remove functions. Give me the
complete documented module in a single file.

## The module

```elixir
defmodule Clock do
  @callback now() :: DateTime.t()

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
  @behaviour Clock

  @impl Clock
  def now, do: DateTime.utc_now()
end

# ---------------------------------------------------------------------------

defmodule Clock.Fake do
  use GenServer

  @default_initial ~U[2024-01-01 00:00:00Z]

  defstruct time: nil, timers: [], next_seq: 0, next_ref: 0

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def start_link(opts \\ []) do
    {initial, opts} = Keyword.pop(opts, :initial, @default_initial)
    {name_opt, _rest} = Keyword.pop(opts, :name)
    gen_opts = if name_opt, do: [name: name_opt], else: []
    GenServer.start_link(__MODULE__, initial, gen_opts)
  end

  def now(server), do: GenServer.call(server, :now)

  def schedule(server, duration, fun) when is_list(duration) and is_function(fun, 0),
    do: GenServer.call(server, {:schedule, duration, fun})

  def cancel(server, ref), do: GenServer.call(server, {:cancel, ref})

  def pending(server), do: GenServer.call(server, :pending)

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
