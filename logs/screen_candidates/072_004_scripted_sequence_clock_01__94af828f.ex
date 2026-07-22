defmodule Clock do
  @moduledoc """
  A behaviour describing a source of the current time, plus a dispatching helper.

  Application code that needs the current time should accept a `:clock` option and call
  `Clock.now/1` with whatever it was given. In production that value is the module
  `Clock.Real`; in tests it is a PID (or registered name) of a `Clock.Fake` process that
  hands out a scripted sequence of timestamps.

      def do_work(opts) do
        clock = Keyword.get(opts, :clock, Clock.Real)
        started_at = Clock.now(clock)
        # ...
      end

  See `Clock.Real` and `Clock.Fake` for the two bundled implementations.
  """

  @doc """
  Returns the current time as a `DateTime`.
  """
  @callback now() :: DateTime.t()

  @typedoc """
  Anything `Clock.now/1` knows how to read the time from: a module implementing the
  `Clock` behaviour, or a `Clock.Fake` server reference.
  """
  @type t :: module() | GenServer.server()

  @doc """
  Reads the current time from `clock`.

  When `clock` is an atom that is a loaded (or loadable) module exporting `now/0`, that
  function is called. Otherwise `clock` is treated as a `Clock.Fake` server reference —
  a PID, a registered name, or a `{:via, _, _}` / `{:global, _}` tuple.

  ## Examples

      iex> %DateTime{} = Clock.now(Clock.Real)

      iex> {:ok, pid} = Clock.Fake.start_link(script: [~U[2024-05-01 12:00:00Z]])
      iex> Clock.now(pid)
      ~U[2024-05-01 12:00:00Z]
  """
  @spec now(t()) :: DateTime.t()
  def now(clock) when is_atom(clock) do
    if module_clock?(clock) do
      clock.now()
    else
      Clock.Fake.now(clock)
    end
  end

  def now(clock), do: Clock.Fake.now(clock)

  @spec module_clock?(atom()) :: boolean()
  defp module_clock?(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :now, 0)
  end
end

defmodule Clock.Real do
  @moduledoc """
  The production `Clock` implementation: reads the real system clock in UTC.
  """

  @behaviour Clock

  @doc """
  Returns the current UTC time via `DateTime.utc_now/0`.

  ## Examples

      iex> %DateTime{} = Clock.Real.now()
  """
  @impl Clock
  @spec now() :: DateTime.t()
  def now, do: DateTime.utc_now()
end

defmodule Clock.Fake do
  @moduledoc """
  A scripted `Clock` implementation for tests.

  Unlike a frozen clock, a `Clock.Fake` process is given a *script*: a non-empty list of
  `DateTime`s that are handed out one per `now/1` call. This makes it easy to test code
  that reads the clock several times (for example to measure a duration) without sleeping
  or stubbing globally.

      {:ok, clock} =
        Clock.Fake.start_link(
          script: [~U[2024-01-01 00:00:00Z], ~U[2024-01-01 00:00:05Z]]
        )

      Clock.Fake.now(clock)
      #=> ~U[2024-01-01 00:00:00Z]
      Clock.Fake.now(clock)
      #=> ~U[2024-01-01 00:00:05Z]

  Once the script is consumed, the `:on_exhaust` policy decides what happens next:

    * `:repeat_last` (default) — keep returning the last scripted value forever;
    * `:cycle` — wrap around and replay the script from the beginning;
    * `:raise` — every further call to `now/1` raises a `RuntimeError` in the *calling*
      process, leaving the clock itself alive.

  The script can be rewound with `reset/1` and extended with `push/2`.
  """

  use GenServer

  @behaviour Clock

  @default_script [~U[2024-01-01 00:00:00Z]]
  @policies [:repeat_last, :cycle, :raise]

  @typedoc "What happens once every scripted value has been handed out."
  @type policy :: :repeat_last | :cycle | :raise

  @typedoc "Options accepted by `start_link/1`."
  @type option ::
          {:script, [DateTime.t()]}
          | {:on_exhaust, policy()}
          | {:name, GenServer.name()}

  defmodule State do
    @moduledoc false

    @enforce_keys [:script, :on_exhaust, :cursor]
    defstruct [:script, :on_exhaust, :cursor]

    @type t :: %__MODULE__{
            script: [DateTime.t()],
            on_exhaust: Clock.Fake.policy(),
            cursor: non_neg_integer()
          }
  end

  @doc """
  Starts a scripted fake clock.

  ## Options

    * `:script` — a non-empty list of `DateTime`s handed out one per `now/1` call.
      Defaults to `#{inspect(@default_script)}`.
    * `:on_exhaust` — `:repeat_last` (default), `:cycle` or `:raise`; see the module
      documentation.
    * `:name` — an optional name to register the process under.

  Returns `{:error, :empty_script}` for an empty script, `{:error, :invalid_script}` when
  the script contains something other than a `DateTime`, and `{:error, :invalid_policy}`
  for an unknown `:on_exhaust` value.

  ## Examples

      iex> {:ok, _pid} = Clock.Fake.start_link(script: [~U[2024-01-01 00:00:00Z]])

      iex> Clock.Fake.start_link(script: [])
      {:error, :empty_script}

      iex> Clock.Fake.start_link(on_exhaust: :explode)
      {:error, :invalid_policy}
  """
  @spec start_link([option()]) :: GenServer.on_start()
  def start_link(opts \\ []) do
    script = Keyword.get(opts, :script, @default_script)
    policy = Keyword.get(opts, :on_exhaust, :repeat_last)

    with :ok <- validate_script(script),
         :ok <- validate_policy(policy) do
      server_opts = Keyword.take(opts, [:name])
      GenServer.start_link(__MODULE__, {script, policy}, server_opts)
    end
  end

  @doc """
  Returns the next scripted `DateTime` and advances the cursor.

  Once the script is exhausted the configured `:on_exhaust` policy applies. Under
  `:raise` this function raises a `RuntimeError` in the calling process; the clock
  process itself stays alive.

  ## Examples

      iex> {:ok, clock} = Clock.Fake.start_link(script: [~U[2024-01-01 00:00:00Z]])
      iex> Clock.Fake.now(clock)
      ~U[2024-01-01 00:00:00Z]
      iex> Clock.Fake.now(clock)
      ~U[2024-01-01 00:00:00Z]
  """
  @spec now(GenServer.server()) :: DateTime.t()
  def now(server) do
    case GenServer.call(server, :now) do
      {:ok, %DateTime{} = datetime} ->
        datetime

      {:error, :exhausted} ->
        raise "Clock.Fake script exhausted: no scripted DateTime left to hand out"
    end
  end

  @doc """
  Returns the current time from the fake clock registered under `Clock.Fake`.

  This exists so that `Clock.Fake` itself satisfies the `Clock` behaviour; it requires a
  process registered under the module name. Prefer `now/1` with an explicit server.

  ## Examples

      iex> {:ok, _pid} = Clock.Fake.start_link(name: Clock.Fake)
      iex> Clock.Fake.now()
      ~U[2024-01-01 00:00:00Z]
  """
  @impl Clock
  @spec now() :: DateTime.t()
  def now, do: now(__MODULE__)

  @doc """
  Returns how many scripted values have not been consumed yet.

  The result is never negative: it is `0` once the script has been exhausted, regardless
  of the `:on_exhaust` policy.

  ## Examples

      iex> {:ok, clock} =
      ...>   Clock.Fake.start_link(
      ...>     script: [~U[2024-01-01 00:00:00Z], ~U[2024-01-01 00:00:01Z]]
      ...>   )
      iex> Clock.Fake.remaining(clock)
      2
      iex> Clock.Fake.now(clock)
      ~U[2024-01-01 00:00:00Z]
      iex> Clock.Fake.remaining(clock)
      1
  """
  @spec remaining(GenServer.server()) :: non_neg_integer()
  def remaining(server), do: GenServer.call(server, :remaining)

  @doc """
  Rewinds the cursor so the script is replayed from its first value.

  ## Examples

      iex> {:ok, clock} = Clock.Fake.start_link(script: [~U[2024-01-01 00:00:00Z]])
      iex> Clock.Fake.now(clock)
      ~U[2024-01-01 00:00:00Z]
      iex> Clock.Fake.reset(clock)
      :ok
      iex> Clock.Fake.remaining(clock)
      1
  """
  @spec reset(GenServer.server()) :: :ok
  def reset(server), do: GenServer.call(server, :reset)

  @doc """
  Appends `datetimes` to the end of the script.

  Useful to keep a test going past the values supplied at start-up. Raises an
  `ArgumentError` if any element is not a `DateTime`.

  ## Examples

      iex> {:ok, clock} = Clock.Fake.start_link(script: [~U[2024-01-01 00:00:00Z]])
      iex> Clock.Fake.push(clock, [~U[2024-01-01 00:00:10Z]])
      :ok
      iex> Clock.Fake.remaining(clock)
      2
  """
  @spec push(GenServer.server(), [DateTime.t()]) :: :ok
  def push(server, datetimes) when is_list(datetimes) do
    unless Enum.all?(datetimes, &match?(%DateTime{}, &1)) do
      raise ArgumentError, "expected a list of DateTime structs, got: #{inspect(datetimes)}"
    end

    GenServer.call(server, {:push, datetimes})
  end

  @impl GenServer
  @spec init({[DateTime.t()], policy()}) :: {:ok, State.t()}
  def init({script, policy}) do
    {:ok, %State{script: script, on_exhaust: policy, cursor: 0}}
  end

  @impl GenServer
  def handle_call(:now, _from, %State{} = state) do
    case fetch(state) do
      {:ok, datetime, new_state} -> {:reply, {:ok, datetime}, new_state}
      :exhausted -> {:reply, {:error, :exhausted}, state}
    end
  end

  def handle_call(:remaining, _from, %State{} = state) do
    {:reply, max(length(state.script) - state.cursor, 0), state}
  end

  def handle_call(:reset, _from, %State{} = state) do
    {:reply, :ok, %State{state | cursor: 0}}
  end

  def handle_call({:push, datetimes}, _from, %State{} = state) do
    {:reply, :ok, %State{state | script: state.script ++ datetimes}}
  end

  @spec fetch(State.t()) :: {:ok, DateTime.t(), State.t()} | :exhausted
  defp fetch(%State{script: script, cursor: cursor} = state) when cursor < length(script) do
    {:ok, Enum.at(script, cursor), %State{state | cursor: cursor + 1}}
  end

  defp fetch(%State{on_exhaust: :repeat_last, script: script} = state) do
    {:ok, List.last(script), state}
  end

  defp fetch(%State{on_exhaust: :cycle, script: script} = state) do
    {:ok, hd(script), %State{state | cursor: 1}}
  end

  defp fetch(%State{on_exhaust: :raise}), do: :exhausted

  @spec validate_script(term()) :: :ok | {:error, :empty_script | :invalid_script}
  defp validate_script([]), do: {:error, :empty_script}

  defp validate_script(script) when is_list(script) do
    if Enum.all?(script, &match?(%DateTime{}, &1)) do
      :ok
    else
      {:error, :invalid_script}
    end
  end

  defp validate_script(_script), do: {:error, :invalid_script}

  @spec validate_policy(term()) :: :ok | {:error, :invalid_policy}
  defp validate_policy(policy) when policy in @policies, do: :ok
  defp validate_policy(_policy), do: {:error, :invalid_policy}
end