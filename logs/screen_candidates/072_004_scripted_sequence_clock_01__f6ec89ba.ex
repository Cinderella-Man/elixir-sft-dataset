defmodule Clock do
  @moduledoc """
  A tiny clock abstraction for dependency injection.

  The `Clock` behaviour defines a single callback, `c:now/0`, which returns the current time
  as a `DateTime`. Two implementations ship in this file:

    * `Clock.Real` — production; delegates to `DateTime.utc_now/0`.
    * `Clock.Fake` — test; a `GenServer` that hands out a *scripted* sequence of timestamps,
      one per read, which makes it easy to test code that reads the clock several times.

  Application code should accept a `:clock` option and call `Clock.now/1` with it, so the very
  same call site works with either implementation:

      def expire?(deadline, opts) do
        clock = Keyword.get(opts, :clock, Clock.Real)
        DateTime.compare(Clock.now(clock), deadline) == :gt
      end

  ## Examples

      iex> %DateTime{} = Clock.now(Clock.Real)
      iex> {:ok, pid} = Clock.Fake.start_link(script: [~U[2024-01-01 00:00:00Z]])
      iex> Clock.now(pid)
      ~U[2024-01-01 00:00:00Z]

  """

  @doc """
  Returns the current time.

  Implementations must return a `DateTime` struct. `Clock.Real` returns the actual wall clock
  time; `Clock.Fake` returns the next value from its script.
  """
  @callback now() :: DateTime.t()

  @typedoc """
  Anything `now/1` can dispatch on: a module implementing the behaviour (such as `Clock.Real`),
  or a `Clock.Fake` server reference (pid, registered name, or `{:via, _, _}` tuple).
  """
  @type t :: module() | GenServer.server()

  @doc """
  Reads the current time from `clock`.

  Dispatches on the shape of the argument:

    * an atom module that exports `now/0` (e.g. `Clock.Real`) — calls `clock.now()`;
    * anything else (a pid, a registered name, or a `{:via, _, _}` tuple) — treats it as a
      `Clock.Fake` server and calls `Clock.Fake.now/1`.

  Note that a registered `Clock.Fake` name is also an atom; it is distinguished from a clock
  module by the absence of an exported `now/0` function.

  ## Examples

      iex> %DateTime{} = Clock.now(Clock.Real)
      iex> {:ok, _} = Clock.Fake.start_link(name: :dispatch_demo, script: [~U[2030-05-05 05:05:05Z]])
      iex> Clock.now(:dispatch_demo)
      ~U[2030-05-05 05:05:05Z]

  """
  @spec now(t()) :: DateTime.t()
  def now(clock) when is_atom(clock) do
    if clock_module?(clock) do
      clock.now()
    else
      Clock.Fake.now(clock)
    end
  end

  def now(server), do: Clock.Fake.now(server)

  @spec clock_module?(atom()) :: boolean()
  defp clock_module?(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :now, 0)
  end
end

defmodule Clock.Real do
  @moduledoc """
  The production `Clock` implementation.

  `now/0` simply delegates to `DateTime.utc_now/0`, so it always reflects the real wall clock
  in UTC.
  """

  @behaviour Clock

  @doc """
  Returns the current UTC time from the system clock.

  ## Examples

      iex> %DateTime{time_zone: "Etc/UTC"} = Clock.Real.now()

  """
  @impl Clock
  @spec now() :: DateTime.t()
  def now, do: DateTime.utc_now()
end

defmodule Clock.Fake do
  @moduledoc """
  A scripted `Clock` implementation for tests.

  Instead of freezing a single instant, the fake clock is handed a *script*: a non-empty list of
  `DateTime`s that it returns one at a time, one per call to `now/1`. This makes it trivial to
  test code that reads the clock several times (measuring durations, timing out, retrying, …).

  What happens once the script is consumed is governed by the `:on_exhaust` policy:

    * `:repeat_last` (default) — keep returning the last scripted value forever;
    * `:cycle` — wrap around to the beginning of the script;
    * `:raise` — raise a `RuntimeError`, so an over-eager reader fails loudly.

  ## Examples

      iex> script = [~U[2024-01-01 00:00:00Z], ~U[2024-01-01 00:00:05Z]]
      iex> {:ok, pid} = Clock.Fake.start_link(script: script, on_exhaust: :cycle)
      iex> Clock.Fake.now(pid)
      ~U[2024-01-01 00:00:00Z]
      iex> Clock.Fake.now(pid)
      ~U[2024-01-01 00:00:05Z]
      iex> Clock.Fake.now(pid)
      ~U[2024-01-01 00:00:00Z]

  """

  use GenServer

  @behaviour Clock

  @typedoc "Policy applied once every scripted value has been consumed."
  @type on_exhaust :: :repeat_last | :cycle | :raise

  @typedoc "Options accepted by `start_link/1`."
  @type option ::
          {:script, [DateTime.t()]}
          | {:on_exhaust, on_exhaust()}
          | {:name, GenServer.name()}

  @default_script [~U[2024-01-01 00:00:00Z]]
  @policies [:repeat_last, :cycle, :raise]

  defmodule State do
    @moduledoc false

    @enforce_keys [:script, :on_exhaust, :cursor]
    defstruct [:script, :on_exhaust, :cursor]

    @type t :: %__MODULE__{
            script: [DateTime.t()],
            on_exhaust: Clock.Fake.on_exhaust(),
            cursor: non_neg_integer()
          }
  end

  @doc """
  Starts a scripted fake clock.

  ## Options

    * `:script` — a non-empty list of `DateTime`s handed out one per `now/1` call. Defaults to
      `[~U[2024-01-01 00:00:00Z]]`.
    * `:on_exhaust` — one of `:repeat_last` (default), `:cycle`, or `:raise`; see the module
      documentation.
    * `:name` — an optional name to register the process under.

  Returns `{:error, reason}` when the script is empty, contains a non-`DateTime` element, or the
  policy is unknown.

  ## Examples

      iex> {:ok, pid} = Clock.Fake.start_link([])
      iex> Clock.Fake.now(pid)
      ~U[2024-01-01 00:00:00Z]

      iex> Clock.Fake.start_link(script: [])
      {:error, {:invalid_script, :empty}}

  """
  @spec start_link([option()]) :: GenServer.on_start()
  def start_link(opts \\ []) when is_list(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name], else: []

    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  @doc """
  Returns the next scripted `DateTime` and advances the cursor.

  Once the script is exhausted, the configured `:on_exhaust` policy decides the result: the last
  value is repeated, the script cycles, or a `RuntimeError` is raised (in the caller, via an exit
  from the server).

  ## Examples

      iex> {:ok, pid} = Clock.Fake.start_link(script: [~U[2024-03-01 12:00:00Z]])
      iex> Clock.Fake.now(pid)
      ~U[2024-03-01 12:00:00Z]
      iex> Clock.Fake.now(pid)
      ~U[2024-03-01 12:00:00Z]

  """
  @spec now(GenServer.server()) :: DateTime.t()
  def now(server), do: GenServer.call(server, :now)

  @doc """
  Returns how many scripted values have not yet been consumed.

  The count never goes below zero, regardless of the `:on_exhaust` policy.

  ## Examples

      iex> {:ok, pid} = Clock.Fake.start_link(script: [~U[2024-01-01 00:00:00Z]])
      iex> Clock.Fake.remaining(pid)
      1
      iex> _ = Clock.Fake.now(pid)
      iex> Clock.Fake.remaining(pid)
      0

  """
  @spec remaining(GenServer.server()) :: non_neg_integer()
  def remaining(server), do: GenServer.call(server, :remaining)

  @doc """
  Rewinds the cursor to the beginning of the script.

  The script itself (including anything appended with `push/2`) is left untouched.

  ## Examples

      iex> {:ok, pid} = Clock.Fake.start_link(script: [~U[2024-01-01 00:00:00Z]])
      iex> _ = Clock.Fake.now(pid)
      iex> :ok = Clock.Fake.reset(pid)
      iex> Clock.Fake.remaining(pid)
      1

  """
  @spec reset(GenServer.server()) :: :ok
  def reset(server), do: GenServer.call(server, :reset)

  @doc """
  Appends `datetimes` to the end of the script.

  Accepts a single `DateTime` or a list of them. Raises `ArgumentError` if any element is not a
  `DateTime`.

  ## Examples

      iex> {:ok, pid} = Clock.Fake.start_link(script: [~U[2024-01-01 00:00:00Z]])
      iex> :ok = Clock.Fake.push(pid, [~U[2024-01-01 00:00:01Z]])
      iex> Clock.Fake.remaining(pid)
      2

  """
  @spec push(GenServer.server(), DateTime.t() | [DateTime.t()]) :: :ok
  def push(server, %DateTime{} = datetime), do: push(server, [datetime])

  def push(server, datetimes) when is_list(datetimes) do
    case validate_script(datetimes, :allow_empty) do
      {:ok, valid} -> GenServer.call(server, {:push, valid})
      {:error, reason} -> raise ArgumentError, "invalid datetimes to push: #{inspect(reason)}"
    end
  end

  # -- GenServer callbacks ---------------------------------------------------------------------

  @impl GenServer
  def init(opts) do
    script = Keyword.get(opts, :script, @default_script)
    on_exhaust = Keyword.get(opts, :on_exhaust, :repeat_last)

    with {:ok, script} <- validate_script(script, :require_non_empty),
         {:ok, on_exhaust} <- validate_policy(on_exhaust) do
      {:ok, %State{script: script, on_exhaust: on_exhaust, cursor: 0}}
    end
  end

  @impl GenServer
  def handle_call(:now, _from, %State{} = state) do
    case next(state) do
      {:ok, datetime, state} ->
        {:reply, datetime, state}

      {:error, :exhausted} ->
        {:reply, {:error, :exhausted}, state}
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

  # -- Internals -------------------------------------------------------------------------------

  @spec next(State.t()) :: {:ok, DateTime.t(), State.t()} | {:error, :exhausted}
  defp next(%State{script: script, cursor: cursor} = state) when cursor < length(script) do
    {:ok, Enum.at(script, cursor), %State{state | cursor: cursor + 1}}
  end

  defp next(%State{on_exhaust: :repeat_last, script: script} = state) do
    {:ok, List.last(script), state}
  end

  defp next(%State{on_exhaust: :cycle, script: script} = state) do
    {:ok, hd(script), %State{state | cursor: 1}}
  end

  defp next(%State{on_exhaust: :raise}) do
    {:error, :exhausted}
  end

  @spec validate_script(term(), :require_non_empty | :allow_empty) ::
          {:ok, [DateTime.t()]} | {:error, term()}
  defp validate_script([], :require_non_empty), do: {:error, {:invalid_script, :empty}}
  defp validate_script([], :allow_empty), do: {:ok, []}

  defp validate_script(script, _mode) when is_list(script) do
    case Enum.reject(script, &match?(%DateTime{}, &1)) do
      [] -> {:ok, script}
      [bad | _] -> {:error, {:invalid_script, {:not_a_datetime, bad}}}
    end
  end

  defp validate_script(other, _mode), do: {:error, {:invalid_script, {:not_a_list, other}}}

  @spec validate_policy(term()) :: {:ok, on_exhaust()} | {:error, term()}
  defp validate_policy(policy) when policy in @policies, do: {:ok, policy}
  defp validate_policy(other), do: {:error, {:invalid_on_exhaust, other}}

  @doc """
  Returns the current time from a fake clock registered under the module's own name.

  This exists so that `Clock.Fake` also satisfies the `Clock` behaviour: a fake clock started as
  `Clock.Fake.start_link(name: Clock.Fake)` can be used wherever a clock *module* is expected.
  Prefer `now/1` with an explicit server reference in tests.

  ## Examples

      iex> {:ok, _} = Clock.Fake.start_link(name: Clock.Fake)
      iex> Clock.Fake.now()
      ~U[2024-01-01 00:00:00Z]

  """
  @impl Clock
  @spec now() :: DateTime.t()
  def now, do: now(__MODULE__)
end