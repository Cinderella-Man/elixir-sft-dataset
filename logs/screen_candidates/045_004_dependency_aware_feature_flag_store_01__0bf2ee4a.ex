defmodule FeatureFlags do
  @moduledoc """
  Feature flag store with ETS-backed reads and GenServer-serialized writes.

  Each flag has:

    * an own state — `:on`, `:off`, or `{:percentage, 0..100}`;
    * a list of prerequisite flags — flags that must themselves be enabled for
      this flag to be considered enabled.

  Prerequisites are evaluated transitively: a flag is enabled only when its own
  state evaluates to true *and* every prerequisite (and every prerequisite of a
  prerequisite, and so on) also evaluates to true. Prerequisite edges are kept
  acyclic; `set_prerequisites/2` rejects any change that would introduce a cycle
  (self-dependency included) and leaves the graph untouched.

  Reads (`enabled?/1`, `enabled_for?/2`, `prerequisites/1`) run in the calling
  process directly against a named, `read_concurrency: true` ETS `:set` table —
  no GenServer round-trip, even for the recursive dependency walk. All writes go
  through the GenServer, which owns the table and performs cycle detection before
  committing.

  Percentage rollouts bucket users deterministically via
  `:erlang.phash2({flag_name, user_id}, 100)`, so the same `{flag, user}` pair
  always lands in the same bucket.

  ## Example

      {:ok, _pid} = FeatureFlags.start_link([])

      :ok = FeatureFlags.enable(:new_billing)
      :ok = FeatureFlags.set_prerequisites(:new_invoices, [:new_billing])
      :ok = FeatureFlags.enable(:new_invoices)

      FeatureFlags.enabled?(:new_invoices)
      #=> true

      :ok = FeatureFlags.disable(:new_billing)
      FeatureFlags.enabled?(:new_invoices)
      #=> false (prerequisite is off)
  """

  use GenServer

  @default_table :feature_flags

  @typedoc "The name of a feature flag."
  @type flag_name :: atom()

  @typedoc "A flag's own state, ignoring prerequisites."
  @type state :: :on | :off | {:percentage, 0..100}

  @typedoc "An opaque user identifier used for percentage bucketing."
  @type user_id :: term()

  # ETS row: {flag_name, state, prereqs}

  ## Public API

  @doc """
  Starts the feature flag server and creates its ETS table.

  ## Options

    * `:table_name` — name of the ETS table to create (default `#{inspect(@default_table)}`).
    * `:name` — name to register the process under (default `FeatureFlags`); pass
      `nil` to start the process unregistered.

  Any other options are passed through to `GenServer.start_link/3`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {table_name, opts} = Keyword.pop(opts, :table_name, @default_table)
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)

    server_opts = if is_nil(name), do: opts, else: Keyword.put(opts, :name, name)
    GenServer.start_link(__MODULE__, %{table_name: table_name}, server_opts)
  end

  @doc """
  Sets the flag's own state to `:on`, preserving its prerequisites.

  The flag may still evaluate to `false` if a prerequisite is not enabled.
  """
  @spec enable(flag_name()) :: :ok
  def enable(flag_name) when is_atom(flag_name) do
    GenServer.call(__MODULE__, {:set_state, flag_name, :on})
  end

  @doc """
  Sets the flag's own state to `:off`, preserving its prerequisites.
  """
  @spec disable(flag_name()) :: :ok
  def disable(flag_name) when is_atom(flag_name) do
    GenServer.call(__MODULE__, {:set_state, flag_name, :off})
  end

  @doc """
  Puts the flag into percentage rollout mode for `percentage` percent of users.

  `percentage` must be an integer between 0 and 100. Prerequisites are preserved.
  Note that `enabled?/1` (which has no user context) is `false` for a flag in
  percentage mode; use `enabled_for?/2`.
  """
  @spec enable_for_percentage(flag_name(), 0..100) :: :ok
  def enable_for_percentage(flag_name, percentage)
      when is_atom(flag_name) and is_integer(percentage) and percentage >= 0 and percentage <= 100 do
    GenServer.call(__MODULE__, {:set_state, flag_name, {:percentage, percentage}})
  end

  @doc """
  Declares that `flag_name` requires every flag in `prereqs` to be enabled.

  Returns `{:error, :cycle}` — leaving the graph unchanged — if the new edges
  would create a cycle, including a self-dependency or a transitive loop through
  existing prerequisites. Otherwise returns `:ok`. The flag's own state is
  preserved (unknown flags default to `:off`).
  """
  @spec set_prerequisites(flag_name(), [flag_name()]) :: :ok | {:error, :cycle}
  def set_prerequisites(flag_name, prereqs) when is_atom(flag_name) and is_list(prereqs) do
    GenServer.call(__MODULE__, {:set_prerequisites, flag_name, prereqs})
  end

  @doc """
  Returns the declared prerequisite list for `flag_name`, or `[]` if it has none.
  """
  @spec prerequisites(flag_name()) :: [flag_name()]
  def prerequisites(flag_name) when is_atom(flag_name) do
    prerequisites(@default_table, flag_name)
  end

  @doc """
  Returns the prerequisite list for `flag_name` in the given ETS table.
  """
  @spec prerequisites(:ets.table(), flag_name()) :: [flag_name()]
  def prerequisites(table, flag_name) when is_atom(flag_name) do
    {_state, prereqs} = lookup(table, flag_name)
    prereqs
  end

  @doc """
  Returns `true` when the flag's own state is `:on` and every prerequisite is
  itself `enabled?/1` (evaluated recursively).

  Unknown flags, disabled flags, and flags in percentage mode return `false`.
  Read straight from ETS in the calling process.
  """
  @spec enabled?(flag_name()) :: boolean()
  def enabled?(flag_name) when is_atom(flag_name) do
    enabled?(@default_table, flag_name)
  end

  @doc """
  Returns `true` when `flag_name` is enabled in the given ETS table.
  """
  @spec enabled?(:ets.table(), flag_name()) :: boolean()
  def enabled?(table, flag_name) when is_atom(flag_name) do
    {state, prereqs} = lookup(table, flag_name)

    state == :on and Enum.all?(prereqs, &enabled?(table, &1))
  end

  @doc """
  Returns `true` when `flag_name` evaluates to true for `user_id`.

  The flag's own state must evaluate true — `:on`, or `{:percentage, p}` with
  `:erlang.phash2({flag_name, user_id}, 100) < p` — and every prerequisite must
  itself be `enabled_for?/2` for the same `user_id`, recursively. `:off` and
  unknown flags return `false`. Bucketing is deterministic per
  `{flag_name, user_id}` pair. Read straight from ETS in the calling process.
  """
  @spec enabled_for?(flag_name(), user_id()) :: boolean()
  def enabled_for?(flag_name, user_id) when is_atom(flag_name) do
    enabled_for?(@default_table, flag_name, user_id)
  end

  @doc """
  Returns `true` when `flag_name` evaluates to true for `user_id` in the given
  ETS table.
  """
  @spec enabled_for?(:ets.table(), flag_name(), user_id()) :: boolean()
  def enabled_for?(table, flag_name, user_id) when is_atom(flag_name) do
    {state, prereqs} = lookup(table, flag_name)

    state_enabled_for?(state, flag_name, user_id) and
      Enum.all?(prereqs, &enabled_for?(table, &1, user_id))
  end

  ## GenServer callbacks

  @impl true
  def init(%{table_name: table_name}) do
    table =
      :ets.new(table_name, [
        :set,
        :named_table,
        :protected,
        read_concurrency: true
      ])

    {:ok, %{table: table}}
  end

  @impl true
  def handle_call({:set_state, flag_name, state}, _from, %{table: table} = server_state) do
    {_old_state, prereqs} = lookup(table, flag_name)
    :ets.insert(table, {flag_name, state, prereqs})
    {:reply, :ok, server_state}
  end

  def handle_call({:set_prerequisites, flag_name, prereqs}, _from, %{table: table} = server_state) do
    prereqs = Enum.uniq(prereqs)

    if creates_cycle?(table, flag_name, prereqs) do
      {:reply, {:error, :cycle}, server_state}
    else
      {state, _old_prereqs} = lookup(table, flag_name)
      :ets.insert(table, {flag_name, state, prereqs})
      {:reply, :ok, server_state}
    end
  end

  ## Internal helpers

  # Returns the flag's row as `{state, prereqs}`, defaulting unknown flags to
  # `{:off, []}`.
  @spec lookup(:ets.table(), flag_name()) :: {state(), [flag_name()]}
  defp lookup(table, flag_name) do
    case :ets.lookup(table, flag_name) do
      [{^flag_name, state, prereqs}] -> {state, prereqs}
      [] -> {:off, []}
    end
  end

  @spec state_enabled_for?(state(), flag_name(), user_id()) :: boolean()
  defp state_enabled_for?(:on, _flag_name, _user_id), do: true
  defp state_enabled_for?(:off, _flag_name, _user_id), do: false

  defp state_enabled_for?({:percentage, percentage}, flag_name, user_id) do
    :erlang.phash2({flag_name, user_id}, 100) < percentage
  end

  # A cycle appears iff `flag_name` is reachable from any of the proposed
  # prerequisites through the *existing* edges (a proposed self-edge is the
  # degenerate case, caught because `flag_name` is trivially reachable from
  # itself).
  @spec creates_cycle?(:ets.table(), flag_name(), [flag_name()]) :: boolean()
  defp creates_cycle?(table, flag_name, prereqs) do
    Enum.any?(prereqs, fn prereq -> reaches?(table, prereq, flag_name, MapSet.new()) end)
  end

  # Depth-first search over existing prerequisite edges: does `from` reach
  # `target`? `seen` guards against pathological input (the stored graph is
  # already acyclic, but the guard keeps this total).
  @spec reaches?(:ets.table(), flag_name(), flag_name(), MapSet.t(flag_name())) :: boolean()
  defp reaches?(_table, target, target, _seen), do: true

  defp reaches?(table, from, target, seen) do
    if MapSet.member?(seen, from) do
      false
    else
      seen = MapSet.put(seen, from)
      {_state, prereqs} = lookup(table, from)
      Enum.any?(prereqs, fn next -> reaches?(table, next, target, seen) end)
    end
  end
end