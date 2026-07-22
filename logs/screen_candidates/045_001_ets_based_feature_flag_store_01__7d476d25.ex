defmodule FeatureFlags do
  @moduledoc """
  Feature flag storage with ETS-backed reads and GenServer-serialised writes.

  Flags live in a named ETS `:set` table owned by this GenServer. Reads
  (`enabled?/1`, `enabled_for?/2`) hit the table directly from the calling
  process, so they never queue behind the server. Writes (`enable/1`,
  `disable/1`, `enable_for_percentage/2`) go through `GenServer.call/3` so
  concurrent updates are serialised.

  Each flag is stored as `{flag_name, state}` where `state` is one of:

    * `:on` — enabled for everyone
    * `:off` — disabled for everyone
    * `{:percentage, percentage}` — enabled for a deterministic subset of users

  Percentage bucketing uses `:erlang.phash2({flag_name, user_id}, 100)`, which
  yields a stable value in `0..99` for a given pair. A user is in the bucket
  when that hash is strictly less than the configured percentage, so `0` behaves
  like `:off` and `100` behaves like `:on`.

  ## Example

      iex> {:ok, _pid} = FeatureFlags.start_link(table_name: :demo_flags, name: :demo)
      iex> FeatureFlags.enable(:new_ui)
      :ok
      iex> FeatureFlags.enabled?(:new_ui)
      true

  """

  use GenServer

  @default_table :feature_flags
  @hash_range 100

  @typedoc "The name used to identify a feature flag."
  @type flag_name :: atom() | String.t()

  @typedoc "Any term identifying a user for percentage bucketing."
  @type user_id :: term()

  @typedoc "The stored state of a flag."
  @type flag_state :: :on | :off | {:percentage, 0..100}

  @doc """
  Starts the feature flag server and creates its ETS table.

  ## Options

    * `:table_name` — name of the ETS table to create (default `#{inspect(@default_table)}`)
    * `:name` — name to register the GenServer under (default `FeatureFlags`)

  Any other options are passed through to `GenServer.start_link/3`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {table_name, opts} = Keyword.pop(opts, :table_name, @default_table)
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)

    GenServer.start_link(__MODULE__, %{table_name: table_name}, [{:name, name} | opts])
  end

  @doc """
  Enables `flag_name` for everyone.

  Always returns `:ok`.
  """
  @spec enable(flag_name()) :: :ok
  def enable(flag_name) do
    GenServer.call(__MODULE__, {:put, flag_name, :on})
  end

  @doc """
  Disables `flag_name` for everyone.

  Always returns `:ok`.
  """
  @spec disable(flag_name()) :: :ok
  def disable(flag_name) do
    GenServer.call(__MODULE__, {:put, flag_name, :off})
  end

  @doc """
  Enables `flag_name` for a deterministic `percentage` of users.

  `percentage` must be an integer in `0..100`; anything else raises
  `FunctionClauseError` before any state is stored. `0` is equivalent to
  `disable/1` and `100` is equivalent to `enable/1`.

  Always returns `:ok`.
  """
  @spec enable_for_percentage(flag_name(), 0..100) :: :ok
  def enable_for_percentage(flag_name, percentage)
      when is_integer(percentage) and percentage >= 0 and percentage <= 100 do
    GenServer.call(__MODULE__, {:put, flag_name, {:percentage, percentage}})
  end

  @doc """
  Returns `true` only when `flag_name` is enabled for everyone.

  Flags in `:off` or percentage mode return `false`, as do unknown flags. This
  read goes straight to ETS and does not involve the GenServer.
  """
  @spec enabled?(flag_name()) :: boolean()
  def enabled?(flag_name) do
    lookup(flag_name) == :on
  end

  @doc """
  Returns `true` when `flag_name` is enabled for `user_id`.

  This is the case when the flag is `:on`, or when it is in percentage mode and
  `:erlang.phash2({flag_name, user_id}, 100)` is strictly less than the
  configured percentage. `:off` and unknown flags always return `false`.
  """
  @spec enabled_for?(flag_name(), user_id()) :: boolean()
  def enabled_for?(flag_name, user_id) do
    case lookup(flag_name) do
      :on -> true
      {:percentage, percentage} -> :erlang.phash2({flag_name, user_id}, @hash_range) < percentage
      _other -> false
    end
  end

  @doc """
  Returns the name of the ETS table used by default.
  """
  @spec default_table() :: atom()
  def default_table, do: @default_table

  @impl GenServer
  def init(%{table_name: table_name} = state) do
    :ets.new(table_name, [:set, :named_table, :protected, read_concurrency: true])
    {:ok, state}
  end

  @impl GenServer
  def handle_call({:put, flag_name, flag_state}, _from, %{table_name: table_name} = state) do
    :ets.insert(table_name, {flag_name, flag_state})
    {:reply, :ok, state}
  end

  @spec lookup(flag_name()) :: flag_state() | :unknown
  defp lookup(flag_name) do
    case :ets.lookup(@default_table, flag_name) do
      [{^flag_name, flag_state}] -> flag_state
      [] -> :unknown
    end
  rescue
    ArgumentError -> :unknown
  end
end