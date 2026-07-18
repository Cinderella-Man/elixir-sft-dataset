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
  @policies [:repeat_last, :cycle, :raise]

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def start_link(opts \\ []) do
    {script, opts} = Keyword.pop(opts, :script, [@default_initial])
    {policy, opts} = Keyword.pop(opts, :on_exhaust, :repeat_last)
    {name_opt, _rest} = Keyword.pop(opts, :name)
    gen_opts = if name_opt, do: [name: name_opt], else: []
    GenServer.start_link(__MODULE__, {script, policy}, gen_opts)
  end

  def now(server) do
    case GenServer.call(server, :now) do
      {:ok, dt} -> dt
      {:error, :exhausted} -> raise "Clock.Fake: scripted time sequence exhausted"
    end
  end

  def remaining(server), do: GenServer.call(server, :remaining)

  def reset(server), do: GenServer.call(server, :reset)

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
