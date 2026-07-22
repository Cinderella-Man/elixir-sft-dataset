defmodule FeatureFlags do
  @moduledoc """
  A feature flag store with ETS-backed reads, GenServer-serialised writes, and a
  full, immutable change history that supports rollback.

  ## Design

  Two ETS tables are created (and owned) by the `FeatureFlags` GenServer in
  `init/1`:

    * the *primary* table (default `:feature_flags`), a `:set` with
      `read_concurrency: true`, holding one `{flag_name, state, version}` record
      per flag. This is the table read by `enabled?/1`, `enabled_for?/2` and
      `version/1` directly from the calling process — no GenServer round-trip.

    * the *history* table, named after the primary table (e.g.
      `:feature_flags_history`), an `:ordered_set` keyed by
      `{flag_name, version}`, holding every version ever written. This makes
      `history/1` a cheap, ordered range read.

  Every state change (`enable/1`, `disable/1`, `enable_for_percentage/2`,
  `rollback/1`) goes through the GenServer with `GenServer.call/3` so version
  numbers stay consistent under concurrent writers.

  ## Versions

  The first write to a flag produces version `1`; each subsequent write
  increments the version by one. Nothing is ever mutated or deleted in the
  history: `rollback/1` re-applies the immediately preceding state as a *new*
  version, so the audit log only ever grows.

  ## Flag states

    * `{:on}` — enabled for everyone
    * `{:off}` — disabled for everyone
    * `{:percentage, n}` — enabled for a deterministic `n`% bucket of users

  ## Example

      iex> {:ok, _pid} = FeatureFlags.start_link(table_name: :demo_flags, name: nil)
      iex> :ok = FeatureFlags.enable(:new_ui)
      iex> FeatureFlags.enabled?(:new_ui)
      true
  """

  use GenServer

  @default_table :feature_flags

  @typedoc "The name of a feature flag. Any term may be used."
  @type flag_name :: term()

  @typedoc "The persisted state of a flag."
  @type state :: {:on} | {:off} | {:percentage, 0..100}

  @typedoc "A single entry of a flag's audit log."
  @type history_entry :: {pos_integer(), state()}

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the feature flag server and creates the backing ETS tables.

  ## Options

    * `:table_name` — the name of the primary ETS table. Defaults to
      `#{inspect(@default_table)}`. The history table is derived from it by
      appending `_history`.
    * `:name` — the name under which the process is registered. Defaults to
      `FeatureFlags`. Pass `nil` to skip registration entirely.

  Returns the usual `GenServer.on_start/0` result.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    table_name = Keyword.get(opts, :table_name, @default_table)
    name = Keyword.get(opts, :name, __MODULE__)

    server_opts = if is_nil(name), do: [], else: [name: name]
    GenServer.start_link(__MODULE__, %{table_name: table_name}, server_opts)
  end

  @doc """
  Turns `flag_name` fully on, recording a new version.

  Always returns `:ok`.
  """
  @spec enable(flag_name()) :: :ok
  def enable(flag_name), do: put_state(flag_name, {:on})

  @doc """
  Turns `flag_name` fully off, recording a new version.

  Always returns `:ok`.
  """
  @spec disable(flag_name()) :: :ok
  def disable(flag_name), do: put_state(flag_name, {:off})

  @doc """
  Enables `flag_name` for a deterministic `percentage`% of users.

  `percentage` must be an integer between `0` and `100` inclusive; anything else
  raises `FunctionClauseError`. Recording a percentage creates a new version.

  Always returns `:ok`.
  """
  @spec enable_for_percentage(flag_name(), 0..100) :: :ok
  def enable_for_percentage(flag_name, percentage)
      when is_integer(percentage) and percentage >= 0 and percentage <= 100 do
    put_state(flag_name, {:percentage, percentage})
  end

  @doc """
  Returns `true` only when `flag_name` is fully `:on`.

  Flags in `:percentage` mode, flags that are `:off`, and flags that were never
  set all return `false`. Read straight from ETS — no GenServer round-trip.
  """
  @spec enabled?(flag_name()) :: boolean()
  def enabled?(flag_name) do
    case lookup(flag_name) do
      {:ok, {:on}, _version} -> true
      _other -> false
    end
  end

  @doc """
  Returns `true` when `flag_name` is enabled for the given `user_id`.

  A flag that is `:on` is enabled for everyone. A flag in `:percentage` mode is
  enabled when `:erlang.phash2({flag_name, user_id}, 100) < percentage`, which
  is stable for a given `{flag_name, user_id}` pair. `:off` flags and unknown
  flags return `false`.
  """
  @spec enabled_for?(flag_name(), term()) :: boolean()
  def enabled_for?(flag_name, user_id) do
    case lookup(flag_name) do
      {:ok, {:on}, _version} ->
        true

      {:ok, {:percentage, percentage}, _version} ->
        :erlang.phash2({flag_name, user_id}, 100) < percentage

      _other ->
        false
    end
  end

  @doc """
  Returns the current version of `flag_name`.

  The first write yields `1` and each subsequent write (including a rollback)
  increments it. Flags that were never set return `0`.
  """
  @spec version(flag_name()) :: non_neg_integer()
  def version(flag_name) do
    case lookup(flag_name) do
      {:ok, _state, version} -> version
      :error -> 0
    end
  end

  @doc """
  Returns the full audit log of `flag_name` as `{version, state}` tuples.

  Entries are sorted by ascending version. Unknown flags return `[]`.
  """
  @spec history(flag_name()) :: [history_entry()]
  def history(flag_name) do
    table = history_table(current_table())

    case :ets.whereis(table) do
      :undefined ->
        []

      _tid ->
        table
        |> :ets.match({{flag_name, :"$1"}, :"$2"})
        |> Enum.map(fn [version, state] -> {version, state} end)
        |> Enum.sort_by(&elem(&1, 0))
    end
  end

  @doc """
  Reverts `flag_name` to its immediately preceding state.

  The rollback is append-only: the previous state is written back as a brand-new
  version, so the history keeps growing and never loses information.

  Returns `:ok` on success, `{:error, :no_previous_version}` when the flag has
  only ever had one version, and `{:error, :unknown_flag}` when the flag was
  never set.
  """
  @spec rollback(flag_name()) :: :ok | {:error, :no_previous_version | :unknown_flag}
  def rollback(flag_name), do: GenServer.call(server(), {:rollback, flag_name})

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init(%{table_name: table_name}) do
    :ets.new(table_name, [
      :set,
      :named_table,
      :public,
      read_concurrency: true
    ])

    :ets.new(history_table(table_name), [
      :ordered_set,
      :named_table,
      :public,
      read_concurrency: true
    ])

    {:ok, %{table_name: table_name}}
  end

  @impl GenServer
  def handle_call({:put, flag_name, new_state}, _from, %{table_name: table} = server_state) do
    version = next_version(table, flag_name)
    write(table, flag_name, new_state, version)
    {:reply, :ok, server_state}
  end

  def handle_call({:rollback, flag_name}, _from, %{table_name: table} = server_state) do
    reply =
      case :ets.lookup(table, flag_name) do
        [] ->
          {:error, :unknown_flag}

        [{^flag_name, _state, current_version}] when current_version <= 1 ->
          {:error, :no_previous_version}

        [{^flag_name, _state, current_version}] ->
          previous_version = current_version - 1
          history = history_table(table)

          case :ets.lookup(history, {flag_name, previous_version}) do
            [{{^flag_name, ^previous_version}, previous_state}] ->
              write(table, flag_name, previous_state, current_version + 1)
              :ok

            [] ->
              {:error, :no_previous_version}
          end
      end

    {:reply, reply, server_state}
  end

  # ---------------------------------------------------------------------------
  # Internal helpers
  # ---------------------------------------------------------------------------

  @spec put_state(flag_name(), state()) :: :ok
  defp put_state(flag_name, new_state) do
    GenServer.call(server(), {:put, flag_name, new_state})
  end

  @spec write(atom(), flag_name(), state(), pos_integer()) :: :ok
  defp write(table, flag_name, new_state, version) do
    :ets.insert(history_table(table), {{flag_name, version}, new_state})
    :ets.insert(table, {flag_name, new_state, version})
    :ok
  end

  @spec next_version(atom(), flag_name()) :: pos_integer()
  defp next_version(table, flag_name) do
    case :ets.lookup(table, flag_name) do
      [{^flag_name, _state, version}] -> version + 1
      [] -> 1
    end
  end

  @spec lookup(flag_name()) :: {:ok, state(), pos_integer()} | :error
  defp lookup(flag_name) do
    table = current_table()

    case :ets.whereis(table) do
      :undefined ->
        :error

      _tid ->
        case :ets.lookup(table, flag_name) do
          [{^flag_name, state, version}] -> {:ok, state, version}
          [] -> :error
        end
    end
  end

  @spec current_table() :: atom()
  defp current_table, do: @default_table

  @spec history_table(atom()) :: atom()
  defp history_table(table_name), do: :"#{table_name}_history"

  @spec server() :: GenServer.server()
  defp server, do: __MODULE__
end