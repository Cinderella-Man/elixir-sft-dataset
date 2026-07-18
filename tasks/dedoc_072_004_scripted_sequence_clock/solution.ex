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

  @doc "Rewinds the cursor to the beginning of the script."
  @spec reset(GenServer.server()) :: :ok
  def reset(server), do: GenServer.call(server, :reset)

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
