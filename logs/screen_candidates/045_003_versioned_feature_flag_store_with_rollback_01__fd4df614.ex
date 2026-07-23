defmodule FeatureFlags do
  @moduledoc """
  A feature-flag store with fast ETS-backed reads and serialised, versioned writes.

  Reads (`enabled?/1`, `enabled_for?/2`, `version/1`, `history/1`) hit ETS directly with
  no GenServer round-trip. All state-changing operations (`enable/1`, `disable/1`,
  `enable_for_percentage/2`, `rollback/1`) are funnelled through a GenServer so that
  version numbers stay consistent under concurrent callers.

  Every write records a new immutable version in an append-only history table, which makes
  it possible to inspect how a flag evolved over time and to roll it back. A rollback does
  not mutate or drop history — it re-applies the immediately preceding state as a brand-new
  version, so the audit log only ever grows.

  A flag's state is one of:

    * `{:on}` — fully enabled
    * `{:off}` — fully disabled
    * `{:percentage, n}` — enabled for roughly `n`% of users, bucketed deterministically

  The public read/write API targets the default table (`:feature_flags`) and default process
  name (`FeatureFlags`). Custom `:table_name`/`:name` values are supported by `start_link/1`
  primarily for supervised or isolated setups.
  """

  use GenServer

  @default_table :feature_flags
  @default_history :feature_flags_history
  @server __MODULE__

  @typedoc "A feature-flag identifier."
  @type flag :: term()

  @typedoc "The immutable state of a flag at a given version."
  @type state :: {:on} | {:off} | {:percentage, 0..100}

  @doc """
  Starts the feature-flag GenServer and creates its ETS tables.

  Options:

    * `:table_name` — name of the primary `:set` table (default `#{inspect(@default_table)}`).
    * `:name` — process registration name (default `#{inspect(__MODULE__)}`); pass `nil` to
      start without registering.

  A companion history table named `"<table_name>_history"` is created alongside the primary
  table.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    table_name = Keyword.get(opts, :table_name, @default_table)
    name = Keyword.get(opts, :name, __MODULE__)
    gen_opts = if is_nil(name), do: [], else: [name: name]
    GenServer.start_link(__MODULE__, table_name, gen_opts)
  end

  @doc """
  Enables `flag_name` fully, setting its state to `{:on}`.

  Records a new version and returns `:ok`.
  """
  @spec enable(flag()) :: :ok
  def enable(flag_name), do: GenServer.call(@server, {:write, flag_name, {:on}})

  @doc """
  Disables `flag_name` fully, setting its state to `{:off}`.

  Records a new version and returns `:ok`.
  """
  @spec disable(flag()) :: :ok
  def disable(flag_name), do: GenServer.call(@server, {:write, flag_name, {:off}})

  @doc """
  Puts `flag_name` into percentage-rollout mode for the given `percentage` (0–100).

  Records a new version and returns `:ok`.
  """
  @spec enable_for_percentage(flag(), 0..100) :: :ok
  def enable_for_percentage(flag_name, percentage)
      when is_integer(percentage) and percentage >= 0 and percentage <= 100 do
    GenServer.call(@server, {:write, flag_name, {:percentage, percentage}})
  end

  @doc """
  Returns `true` only when `flag_name` is fully `:on`.

  Percentage, `:off`, and unknown flags return `false`.
  """
  @spec enabled?(flag()) :: boolean()
  def enabled?(flag_name) do
    case lookup_state(flag_name) do
      {:on} -> true
      _ -> false
    end
  end

  @doc """
  Returns whether `flag_name` is enabled for the given `user_id`.

  Returns `true` if the flag is `:on`, or if it is in `:percentage` mode and the user falls
  into the enabled bucket (`:erlang.phash2({flag_name, user_id}, 100) < percentage`). The
  bucket is deterministic per `{flag_name, user_id}` pair. `:off` and unknown flags return
  `false`.
  """
  @spec enabled_for?(flag(), term()) :: boolean()
  def enabled_for?(flag_name, user_id) do
    case lookup_state(flag_name) do
      {:on} -> true
      {:percentage, n} -> :erlang.phash2({flag_name, user_id}, 100) < n
      _ -> false
    end
  end

  @doc """
  Returns the current integer version of `flag_name`.

  The first write produces version `1` and each subsequent write increments it. Unknown
  flags return `0`.
  """
  @spec version(flag()) :: non_neg_integer()
  def version(flag_name) do
    case :ets.lookup(@default_table, flag_name) do
      [{_flag, _state, version}] -> version
      [] -> 0
    end
  end

  @doc """
  Returns the full history of `flag_name` as `{version, state}` tuples.

  The list is in ascending version order. Unknown flags return `[]`.
  """
  @spec history(flag()) :: [{pos_integer(), state()}]
  def history(flag_name) do
    match = [{{{flag_name, :"$1"}, :"$2"}, [], [{{:"$1", :"$2"}}]}]

    @default_history
    |> :ets.select(match)
    |> Enum.sort()
  end

  @doc """
  Reverts `flag_name` to its immediately preceding state.

  Rollback is append-only: the previous state is written as a brand-new version, so the
  history grows. Returns `:ok` on success, `{:error, :no_previous_version}` if the flag has
  only one version, and `{:error, :unknown_flag}` if the flag was never set.
  """
  @spec rollback(flag()) :: :ok | {:error, :no_previous_version | :unknown_flag}
  def rollback(flag_name), do: GenServer.call(@server, {:rollback, flag_name})

  @impl GenServer
  @spec init(atom()) :: {:ok, map()}
  def init(table_name) do
    history_table = history_table_name(table_name)

    :ets.new(table_name, [:set, :named_table, :protected, read_concurrency: true])
    :ets.new(history_table, [:ordered_set, :named_table, :protected, read_concurrency: true])

    {:ok, %{table: table_name, history: history_table}}
  end

  @impl GenServer
  def handle_call({:write, flag, state}, _from, s) do
    _version = do_write(s, flag, state)
    {:reply, :ok, s}
  end

  def handle_call({:rollback, flag}, _from, s) do
    case current(s.table, flag) do
      nil ->
        {:reply, {:error, :unknown_flag}, s}

      {_state, 1} ->
        {:reply, {:error, :no_previous_version}, s}

      {_state, version} ->
        previous = fetch_history(s.history, flag, version - 1)
        _version = do_write(s, flag, previous)
        {:reply, :ok, s}
    end
  end

  # Writes `state` as the next version for `flag`, updating both tables. Returns the version.
  @spec do_write(map(), flag(), state()) :: pos_integer()
  defp do_write(%{table: table, history: history}, flag, state) do
    version = current_version(table, flag) + 1
    :ets.insert(table, {flag, state, version})
    :ets.insert(history, {{flag, version}, state})
    version
  end

  # Returns the stored state for `flag_name` from the primary table, or `nil` if unknown.
  @spec lookup_state(flag()) :: state() | nil
  defp lookup_state(flag_name) do
    case :ets.lookup(@default_table, flag_name) do
      [{_flag, state, _version}] -> state
      [] -> nil
    end
  end

  # Returns `{state, version}` for `flag` from `table`, or `nil` if the flag is unknown.
  @spec current(atom(), flag()) :: {state(), pos_integer()} | nil
  defp current(table, flag) do
    case :ets.lookup(table, flag) do
      [{_flag, state, version}] -> {state, version}
      [] -> nil
    end
  end

  # Returns the current version number for `flag` in `table`, or `0` if unknown.
  @spec current_version(atom(), flag()) :: non_neg_integer()
  defp current_version(table, flag) do
    case :ets.lookup(table, flag) do
      [{_flag, _state, version}] -> version
      [] -> 0
    end
  end

  # Returns the historical state recorded for `flag` at `version`.
  @spec fetch_history(atom(), flag(), pos_integer()) :: state()
  defp fetch_history(history, flag, version) do
    [{_key, state}] = :ets.lookup(history, {flag, version})
    state
  end

  # Derives the history table name for a given primary `table_name`.
  @spec history_table_name(atom()) :: atom()
  defp history_table_name(@default_table), do: @default_history
  defp history_table_name(table_name), do: :"#{table_name}_history"
end