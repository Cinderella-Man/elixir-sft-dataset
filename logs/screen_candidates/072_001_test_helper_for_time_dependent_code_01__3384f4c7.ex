defmodule Clock do
  @moduledoc """
  A behaviour for obtaining the current time, plus a dispatching helper.

  Two implementations are provided in this file:

    * `Clock.Real` — delegates to `DateTime.utc_now/0`, intended for production.
    * `Clock.Fake` — a `GenServer` holding a frozen `DateTime` that tests can
      freeze and advance deterministically.

  Application code takes a `:clock` dependency-injection option and calls
  `Clock.now/1` with whatever it was given:

      def process(opts) do
        clock = Keyword.get(opts, :clock, Clock.Real)
        timestamp = Clock.now(clock)
        # ...
      end

  In production the caller passes `Clock.Real`; in tests it passes the pid or
  registered name of a `Clock.Fake` process. `Clock.now/1` dispatches on the
  argument type, so callers never care which implementation is underneath.
  """

  @doc """
  Returns the current time as a `DateTime`.
  """
  @callback now() :: DateTime.t()

  @typedoc """
  Anything `Clock.now/1` can dispatch on: a module implementing the `Clock`
  behaviour, or a pid / registered name of a `Clock.Fake` process.
  """
  @type t :: module() | pid() | GenServer.name()

  @doc """
  Returns the current time from `clock`.

  When `clock` is an atom module (such as `Clock.Real`) its `now/0` callback is
  invoked. When `clock` is a pid or a `{:via, _, _}` / `{:global, _}` tuple it is
  treated as a running `Clock.Fake` server and `Clock.Fake.now/1` is called.

  A registered `Clock.Fake` name is also an atom, so it is disambiguated from a
  behaviour module by checking whether the module exports `now/0`.

  ## Examples

      iex> %DateTime{} = Clock.now(Clock.Real)

      iex> {:ok, pid} = Clock.Fake.start_link(initial: ~U[2024-03-01 12:00:00Z])
      iex> Clock.now(pid)
      ~U[2024-03-01 12:00:00Z]

  """
  @spec now(t()) :: DateTime.t()
  def now(clock) when is_atom(clock) do
    if clock_module?(clock) do
      clock.now()
    else
      Clock.Fake.now(clock)
    end
  end

  def now(clock) when is_pid(clock) or is_tuple(clock) do
    Clock.Fake.now(clock)
  end

  @spec clock_module?(atom()) :: boolean()
  defp clock_module?(clock) do
    Code.ensure_loaded?(clock) and function_exported?(clock, :now, 0)
  end
end

defmodule Clock.Real do
  @moduledoc """
  The production `Clock` implementation: reads the actual system clock in UTC.
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
  A controllable `Clock` implementation for tests.

  The process holds a single frozen `DateTime` that never moves on its own.
  Tests move it explicitly with `freeze/2` (jump to an absolute time) or
  `advance/2` (step forward by a duration).

      {:ok, clock} = Clock.Fake.start_link(initial: ~U[2024-06-01 09:00:00Z])
      Clock.Fake.now(clock)
      #=> ~U[2024-06-01 09:00:00Z]

      Clock.Fake.advance(clock, hours: 1, minutes: 30)
      Clock.Fake.now(clock)
      #=> ~U[2024-06-01 10:30:00Z]

  """

  use GenServer

  @default_initial ~U[2024-01-01 00:00:00Z]

  @typedoc """
  A reference to a running `Clock.Fake` process.
  """
  @type server :: pid() | GenServer.name()

  @typedoc """
  A duration as a keyword list of unit/amount pairs, for example
  `[seconds: 30]` or `[hours: 1, minutes: 30]`. Supported units are those
  accepted by `DateTime.add/4`: `:day`, `:hour`, `:minute`, `:second`,
  `:millisecond`, `:microsecond` and `:nanosecond`, each also accepted in its
  plural form.
  """
  @type duration :: keyword(integer())

  @units %{
    day: :day,
    days: :day,
    hour: :hour,
    hours: :hour,
    minute: :minute,
    minutes: :minute,
    second: :second,
    seconds: :second,
    millisecond: :millisecond,
    milliseconds: :millisecond,
    microsecond: :microsecond,
    microseconds: :microsecond,
    nanosecond: :nanosecond,
    nanoseconds: :nanosecond
  }

  @doc """
  Starts a fake clock process.

  ## Options

    * `:initial` — the `DateTime` the clock starts frozen at. Defaults to
      `#{inspect(@default_initial)}`.
    * `:name` — an optional name to register the process under, passed through
      to `GenServer.start_link/3`.

  Any other options are ignored.

  ## Examples

      iex> {:ok, pid} = Clock.Fake.start_link([])
      iex> Clock.Fake.now(pid)
      ~U[2024-01-01 00:00:00Z]

  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    initial = Keyword.get(opts, :initial, @default_initial)
    server_opts = opts |> Keyword.take([:name]) |> Keyword.take([:name])

    GenServer.start_link(__MODULE__, initial, server_opts)
  end

  @doc """
  Returns the currently frozen `DateTime` held by `server`.

  ## Examples

      iex> {:ok, pid} = Clock.Fake.start_link(initial: ~U[2024-05-05 05:05:05Z])
      iex> Clock.Fake.now(pid)
      ~U[2024-05-05 05:05:05Z]

  """
  @spec now(server()) :: DateTime.t()
  def now(server), do: GenServer.call(server, :now)

  @doc """
  Freezes `server` at `datetime`, discarding whatever time it held before.

  Time may move backwards; no ordering is enforced.

  ## Examples

      iex> {:ok, pid} = Clock.Fake.start_link([])
      iex> :ok = Clock.Fake.freeze(pid, ~U[2030-12-25 00:00:00Z])
      iex> Clock.Fake.now(pid)
      ~U[2030-12-25 00:00:00Z]

  """
  @spec freeze(server(), DateTime.t()) :: :ok
  def freeze(server, %DateTime{} = datetime) do
    GenServer.call(server, {:freeze, datetime})
  end

  @doc """
  Advances the clock held by `server` forward by `duration`.

  `duration` is a keyword list of unit/amount pairs, each applied in turn via
  `DateTime.add/4` — for example `[seconds: 30]` or `[hours: 1, minutes: 30]`.
  Negative amounts move the clock backwards.

  Returns the new `DateTime`. Raises `ArgumentError` if a unit is unknown.

  ## Examples

      iex> {:ok, pid} = Clock.Fake.start_link(initial: ~U[2024-01-01 00:00:00Z])
      iex> Clock.Fake.advance(pid, hours: 1, minutes: 30)
      ~U[2024-01-01 01:30:00Z]

  """
  @spec advance(server(), duration()) :: DateTime.t()
  def advance(server, duration) when is_list(duration) do
    :ok = validate_duration!(duration)
    GenServer.call(server, {:advance, duration})
  end

  @impl GenServer
  def init(%DateTime{} = initial), do: {:ok, initial}

  @impl GenServer
  def handle_call(:now, _from, datetime), do: {:reply, datetime, datetime}

  def handle_call({:freeze, new_datetime}, _from, _datetime) do
    {:reply, :ok, new_datetime}
  end

  def handle_call({:advance, duration}, _from, datetime) do
    new_datetime = apply_duration(datetime, duration)
    {:reply, new_datetime, new_datetime}
  end

  @spec apply_duration(DateTime.t(), duration()) :: DateTime.t()
  defp apply_duration(datetime, duration) do
    Enum.reduce(duration, datetime, fn {unit, amount}, acc ->
      DateTime.add(acc, amount, Map.fetch!(@units, unit))
    end)
  end

  @spec validate_duration!(duration()) :: :ok
  defp validate_duration!(duration) do
    Enum.each(duration, fn
      {unit, amount} when is_atom(unit) and is_integer(amount) ->
        if not Map.has_key?(@units, unit) do
          raise ArgumentError,
                "unknown duration unit #{inspect(unit)}, expected one of: " <>
                  (@units |> Map.keys() |> Enum.sort() |> Enum.map_join(", ", &inspect/1))
        end

      other ->
        raise ArgumentError,
              "expected a keyword list of unit/integer pairs, got: #{inspect(other)}"
    end)
  end
end