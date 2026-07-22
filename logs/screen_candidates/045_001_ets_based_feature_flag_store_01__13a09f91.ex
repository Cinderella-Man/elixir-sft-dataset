defmodule FeatureFlags do
  @moduledoc """
  A feature flag store backed by ETS for fast, lock-free reads and a `GenServer`
  for serialised writes.

  The `GenServer` owns a named ETS table (type `:set`, `read_concurrency: true`),
  so read functions such as `enabled?/1` and `enabled_for?/2` perform a direct
  `:ets.lookup/2` from the calling process and never block on the server.

  Flags are stored as `{flag_name, state}` where `state` is one of:

    * `:on` — enabled for everyone
    * `:off` — disabled for everyone
    * `{:percentage, percentage}` — enabled for a deterministic subset of users

  Percentage rollouts are deterministic: bucketing is derived from
  `:erlang.phash2({flag_name, user_id}, 100)`, so the same `{flag_name, user_id}`
  pair always resolves the same way.

  ## Example

      iex> {:ok, _pid} = FeatureFlags.start_link(table_name: :demo_flags, name: :demo)
      iex> FeatureFlags.enable(:new_ui, :demo)
      :ok
      iex> FeatureFlags.enabled?(:new_ui, :demo_flags)
      true

  """

  use GenServer

  @default_table :feature_flags

  @type flag_name :: atom() | String.t()
  @type percentage :: 0..100
  @type flag_state :: :on | :off | {:percentage, percentage()}

  # ----------------------------------------------------------------------------
  # Public API
  # ----------------------------------------------------------------------------

  @doc """
  Starts the feature flag server.

  ## Options

    * `:table_name` — the name of the ETS table to create and own.
      Defaults to `#{inspect(@default_table)}`.
    * `:name` — the name to register the `GenServer` under. Defaults to
      `FeatureFlags`.

  Any other options are passed through to `GenServer.start_link/3`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    table_name = Keyword.get(opts, :table_name, @default_table)

    GenServer.start_link(__MODULE__, %{table_name: table_name}, name: name)
  end

  @doc """
  Returns the default ETS table name used when none is supplied.
  """
  @spec default_table() :: atom()
  def default_table, do: @default_table

  @doc """
  Enables `flag_name` for everyone.

  The write is serialised through the `GenServer` identified by `server`.
  """
  @spec enable(flag_name(), GenServer.server()) :: :ok
  def enable(flag_name, server \\ __MODULE__) do
    GenServer.call(server, {:put, flag_name, :on})
  end

  @doc """
  Disables `flag_name` for everyone.

  The write is serialised through the `GenServer` identified by `server`.
  """
  @spec disable(flag_name(), GenServer.server()) :: :ok
  def disable(flag_name, server \\ __MODULE__) do
    GenServer.call(server, {:put, flag_name, :off})
  end

  @doc """
  Enables `flag_name` for a `percentage` (an integer between `0` and `100`) of users.

  A percentage of `0` is stored as `:off` and `100` is stored as `:on`, so those
  values behave exactly like `disable/2` and `enable/2` respectively.

  Raises `ArgumentError` if `percentage` is not an integer in `0..100`.
  """
  @spec enable_for_percentage(flag_name(), percentage(), GenServer.server()) :: :ok
  def enable_for_percentage(flag_name, percentage, server \\ __MODULE__)
      when is_integer(percentage) and percentage >= 0 and percentage <= 100 do
    GenServer.call(server, {:put, flag_name, normalise_percentage(percentage)})
  end

  @doc """
  Returns `true` when `flag_name` is fully enabled (`:on`).

  Flags that are `:off`, in `:percentage` mode, or unknown return `false`.

  This reads directly from the ETS table and does not involve the `GenServer`.
  """
  @spec enabled?(flag_name(), atom()) :: boolean()
  def enabled?(flag_name, table_name \\ @default_table) do
    lookup(table_name, flag_name) == :on
  end

  @doc """
  Returns `true` when `flag_name` is enabled for `user_id`.

  A flag that is `:on` is enabled for everyone. A flag in `:percentage` mode is
  enabled when `:erlang.phash2({flag_name, user_id}, 100)` — a value in `0..99` —
  is strictly less than the configured percentage, which makes the decision
  deterministic for a given `{flag_name, user_id}` pair. Flags that are `:off` or
  unknown always return `false`.

  This reads directly from the ETS table and does not involve the `GenServer`.
  """
  @spec enabled_for?(flag_name(), term(), atom()) :: boolean()
  def enabled_for?(flag_name, user_id, table_name \\ @default_table) do
    case lookup(table_name, flag_name) do
      :on -> true
      {:percentage, percentage} -> bucket(flag_name, user_id) < percentage
      _other -> false
    end
  end

  # ----------------------------------------------------------------------------
  # GenServer callbacks
  # ----------------------------------------------------------------------------

  @impl GenServer
  def init(%{table_name: table_name}) do
    table =
      :ets.new(table_name, [
        :set,
        :named_table,
        :protected,
        read_concurrency: true
      ])

    {:ok, %{table_name: table}}
  end

  @impl GenServer
  def handle_call({:put, flag_name, state}, _from, %{table_name: table_name} = server_state) do
    true = :ets.insert(table_name, {flag_name, state})
    {:reply, :ok, server_state}
  end

  # ----------------------------------------------------------------------------
  # Internal helpers
  # ----------------------------------------------------------------------------

  @spec lookup(atom(), flag_name()) :: flag_state() | :unknown
  defp lookup(table_name, flag_name) do
    case :ets.lookup(table_name, flag_name) do
      [{^flag_name, state}] -> state
      [] -> :unknown
    end
  rescue
    ArgumentError -> :unknown
  end

  @spec bucket(flag_name(), term()) :: 0..99
  defp bucket(flag_name, user_id) do
    :erlang.phash2({flag_name, user_id}, 100)
  end

  @spec normalise_percentage(percentage()) :: flag_state()
  defp normalise_percentage(0), do: :off
  defp normalise_percentage(100), do: :on
  defp normalise_percentage(percentage), do: {:percentage, percentage}
end