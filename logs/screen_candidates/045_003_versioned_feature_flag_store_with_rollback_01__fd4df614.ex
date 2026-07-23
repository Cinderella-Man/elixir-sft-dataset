defmodule FeatureFlags do
  @moduledoc """
  ETS-backed feature flag store with a GenServer serialising writes.

  Reads (`enabled?/1`, `enabled_for?/2`, `version/1`, `history/1`) hit ETS
  directly for speed and never touch the GenServer. Every state-changing
  operation goes through the GenServer via `call/2`, which appends a new
  immutable version to both the primary table and an append-only history
  table. This gives each flag a full audit trail and cheap rollback.

  A flag's `state` is always one of `{:on}`, `{:off}`, or `{:percentage, n}`
  where `n` is an integer in `0..100`.

  The read functions target the default table (`:feature_flags`) so any
  process can query without knowing the owning GenServer. Start the process
  with the default `:table_name` if you rely on these helpers.
  """

  use GenServer

  @default_table :feature_flags

  @typedoc "The persisted state of a feature flag."
  @type flag_state :: {:on} | {:off} | {:percentage, non_neg_integer()}

  # ------------------------------------------------------------------
  # Public API
  # ------------------------------------------------------------------

  @doc """
  Starts the feature flag GenServer and creates the ETS tables.

  Options:

    * `:table_name` - the primary ETS table name (default `:feature_flags`).
    * `:name` - process registration name; pass `nil` to skip registration.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    table_name = Keyword.get(opts, :table_name, @default_table)
    name = Keyword.get(opts, :name, __MODULE__)

    gen_opts = if is_nil(name), do: [], else: [name: name]
    GenServer.start_link(__MODULE__, table_name, gen_opts)
  end

  @doc "Turns `flag_name` fully on, recording a new version."
  @spec enable(term()) :: :ok
  def enable(flag_name), do: GenServer.call(__MODULE__, {:set, flag_name, {:on}})

  @doc "Turns `flag_name` fully off, recording a new version."
  @spec disable(term()) :: :ok
  def disable(flag_name), do: GenServer.call(__MODULE__, {:set, flag_name, {:off}})

  @doc """
  Enables `flag_name` for an integer `percentage` (0-100) of users,
  recording a new version.
  """
  @spec enable_for_percentage(term(), 0..100) :: :ok
  def enable_for_percentage(flag_name, percentage)
      when is_integer(percentage) and percentage >= 0 and percentage <= 100 do
    GenServer.call(__MODULE__, {:set, flag_name, {:percentage, percentage}})
  end

  @doc """
  Returns `true` only when `flag_name` is fully `:on`.

  Unknown flags default to `false`.
  """
  @spec enabled?(term()) :: boolean()
  def enabled?(flag_name) do
    case lookup_state(flag_name) do
      {:on} -> true
      _other -> false
    end
  end

  @doc """
  Returns `true` if `flag_name` is `:on`, or if it is in `:percentage`
  mode and `user_id` falls into the enabled bucket.

  The bucket is deterministic per `{flag_name, user_id}` pair:
  `:erlang.phash2({flag_name, user_id}, 100) < percentage`.

  `:off` and unknown flags return `false`.
  """
  @spec enabled_for?(term(), term()) :: boolean()
  def enabled_for?(flag_name, user_id) do
    case lookup_state(flag_name) do
      {:on} -> true
      {:percentage, n} -> :erlang.phash2({flag_name, user_id}, 100) < n
      _other -> false
    end
  end

  @doc """
  Returns the current integer version of `flag_name`.

  The first write is version `1`; each later write increments it. Unknown
  flags return `0`.
  """
  @spec version(term()) :: non_neg_integer()
  def version(flag_name) do
    case :ets.lookup(@default_table, flag_name) do
      [{^flag_name, version, _state}] -> version
      [] -> 0
    end
  end

  @doc """
  Returns `{version, state}` tuples for `flag_name` in ascending version
  order. Unknown flags return `[]`.
  """
  @spec history(term()) :: [{pos_integer(), flag_state()}]
  def history(flag_name) do
    match = {{flag_name, :"$1"}, :"$2"}
    guard = []
    body = [{{:"$1", :"$2"}}]

    @default_table
    |> history_table()
    |> :ets.select([{match, guard, body}])
    |> Enum.sort_by(fn {version, _state} -> version end)
  end

  @doc """
  Reverts `flag_name` to its immediately preceding state by appending
  that state as a brand-new version (history grows).

  Returns `:ok` on success, `{:error, :no_previous_version}` if the flag
  has only one version, and `{:error, :unknown_flag}` if it was never set.
  """
  @spec rollback(term()) :: :ok | {:error, :no_previous_version | :unknown_flag}
  def rollback(flag_name), do: GenServer.call(__MODULE__, {:rollback, flag_name})

  # ------------------------------------------------------------------
  # GenServer callbacks
  # ------------------------------------------------------------------

  @impl true
  @spec init(atom()) :: {:ok, %{primary: atom(), history: atom()}}
  def init(table_name) do
    primary =
      :ets.new(table_name, [
        :set,
        :named_table,
        :protected,
        read_concurrency: true
      ])

    history =
      :ets.new(history_table(table_name), [
        :ordered_set,
        :named_table,
        :protected,
        read_concurrency: true
      ])

    {:ok, %{primary: primary, history: history}}
  end

  @impl true
  def handle_call({:set, flag_name, state}, _from, tables) do
    :ok = write_version(tables, flag_name, state)
    {:reply, :ok, tables}
  end

  @impl true
  def handle_call({:rollback, flag_name}, _from, tables) do
    reply =
      case :ets.lookup(tables.primary, flag_name) do
        [] ->
          {:error, :unknown_flag}

        [{^flag_name, 1, _state}] ->
          {:error, :no_previous_version}

        [{^flag_name, version, _state}] ->
          [{{^flag_name, _v}, prev_state}] =
            :ets.lookup(tables.history, {flag_name, version - 1})

          write_version(tables, flag_name, prev_state)
      end

    {:reply, reply, tables}
  end

  # ------------------------------------------------------------------
  # Internal helpers
  # ------------------------------------------------------------------

  @spec write_version(%{primary: atom(), history: atom()}, term(), flag_state()) :: :ok
  defp write_version(tables, flag_name, state) do
    next_version =
      case :ets.lookup(tables.primary, flag_name) do
        [{^flag_name, version, _state}] -> version + 1
        [] -> 1
      end

    true = :ets.insert(tables.primary, {flag_name, next_version, state})
    true = :ets.insert(tables.history, {{flag_name, next_version}, state})
    :ok
  end

  @spec lookup_state(term()) :: flag_state() | nil
  defp lookup_state(flag_name) do
    case :ets.lookup(@default_table, flag_name) do
      [{^flag_name, _version, state}] -> state
      [] -> nil
    end
  end

  @spec history_table(atom()) :: atom()
  defp history_table(table_name), do: :"#{table_name}_history"
end