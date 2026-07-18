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
  @behaviour Clock

  @impl Clock
  def now, do: DateTime.utc_now()
end

# ---------------------------------------------------------------------------

defmodule Clock.Fake do
  use GenServer

  @default_initial ~U[2024-01-01 00:00:00Z]

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

  def freeze(server, %DateTime{} = datetime),
    do: GenServer.call(server, {:freeze, datetime})

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
