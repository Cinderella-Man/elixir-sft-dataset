Implement the private `load_history/2` function.

It takes an Ecto repo module and an `entity_id` string, and returns a list of
maps describing every recorded transition for that entity in chronological
(insertion) order.

Build an `Ecto.Query` (using the imported `from/2`) over `EntityTransition` that
selects all rows whose `entity_id` matches the given `entity_id`, ordered by the
row `id` ascending (insertion order). Run the query with `repo.all/1`, then map
each `EntityTransition` struct into a plain map with exactly these keys:

  - `:event` — the stored `event` string converted back to an atom via
    `String.to_existing_atom/1`
  - `:from_state` — the stored `from_state` string converted with
    `String.to_existing_atom/1`
  - `:to_state` — the stored `to_state` string converted with
    `String.to_existing_atom/1`
  - `:version` — the row's integer `version`, unchanged
  - `:inserted_at` — the row's `inserted_at` timestamp, unchanged

The function returns the resulting list of maps.

```elixir
defmodule EntityTransition do
  @moduledoc """
  Ecto schema for a single persisted state-machine transition.

  Each row records one successful transition of an entity: the event that was
  applied, the state it moved from, the state it moved to, the entity's version
  *after* the transition, and the timestamp at which it was inserted.

  The `entity_transitions` table uses an auto-incrementing bigint primary key and
  a manually-managed `inserted_at` column (no `updated_at`), so the schema
  declares `inserted_at` as a plain field rather than using `timestamps/1`.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "entity_transitions" do
    field(:entity_id, :string)
    field(:event, :string)
    field(:from_state, :string)
    field(:to_state, :string)
    field(:version, :integer)
    field(:inserted_at, :utc_datetime_usec)
  end
end

defmodule Repo.Migrations.CreateEntityTransitions do
  @moduledoc """
  Migration creating the `entity_transitions` table.

  The table stores the full transition history for every entity. `entity_id` is
  indexed because both history lookups and latest-state hydration query by it.
  Uses only portable `Ecto.Migration` primitives so it runs cleanly on SQLite.
  """

  use Ecto.Migration

  @doc """
  Creates the `entity_transitions` table and its `entity_id` index.
  """
  @spec change() :: :ok
  def change do
    create table(:entity_transitions) do
      add(:entity_id, :string, null: false)
      add(:event, :string, null: false)
      add(:from_state, :string, null: false)
      add(:to_state, :string, null: false)
      add(:version, :integer, null: false)
      add(:inserted_at, :utc_datetime_usec, null: false)
    end

    create(index(:entity_transitions, [:entity_id]))
  end
end

defmodule StateMachine do
  @moduledoc """
  GenServer managing the lifecycle of stateful order-processing entities with
  optimistic concurrency control.

  Every entity carries a monotonically increasing version number. A brand-new
  entity (with no persisted history) starts in the `:pending` state at version 0.
  Each successful transition increments the version by 1 and persists the new
  state, event, and version to the database.

  A caller invoking `transition/4` must present the version it expects to be
  operating on. If that expected version does not match the entity's current
  version, the write is rejected as stale and nothing is persisted. Because the
  version is checked inside `handle_call`, concurrent callers racing to apply the
  same event at the same expected version serialize through the GenServer: exactly
  one succeeds and the rest observe the incremented version and receive
  `{:error, {:stale_version, current_version}}`.

  The GenServer holds an in-memory map of
  `%{entity_id => {current_state, current_version}}`. On restart this map is empty,
  so the next `start/2` call re-hydrates the entity from the database.
  """

  use GenServer

  import Ecto.Query, only: [from: 2]

  @typedoc "A valid state in the order-processing lifecycle."
  @type state_name :: :pending | :confirmed | :shipped | :delivered | :cancelled

  @typedoc "An event that may drive a transition."
  @type event :: :confirm | :ship | :deliver | :cancel

  @initial_state :pending

  @transitions %{
    {:pending, :confirm} => :confirmed,
    {:confirmed, :ship} => :shipped,
    {:shipped, :deliver} => :delivered,
    {:pending, :cancel} => :cancelled,
    {:confirmed, :cancel} => :cancelled
  }

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the state-machine GenServer.

  Accepts a required `:repo` option (an Ecto repo module) and an optional `:name`
  option for process registration.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name, init_opts} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, init_opts, gen_opts)
  end

  @doc """
  Loads the latest persisted state and version for `entity_id` from the database.

  If no record exists, the entity starts in the `:pending` state at version 0.
  Returns `{:ok, current_state, current_version}`.
  """
  @spec start(GenServer.server(), String.t()) :: {:ok, state_name(), non_neg_integer()}
  def start(server, entity_id) do
    GenServer.call(server, {:start, entity_id})
  end

  @doc """
  Returns `{:ok, current_state, current_version}` for a previously started entity,
  or `{:error, :not_found}` if the entity has never been started in this session.
  """
  @spec get_state(GenServer.server(), String.t()) ::
          {:ok, state_name(), non_neg_integer()} | {:error, :not_found}
  def get_state(server, entity_id) do
    GenServer.call(server, {:get_state, entity_id})
  end

  @doc """
  Attempts to transition `entity_id` via `event`, given `expected_version`.

  Checks are applied in order: not-started, stale-version, invalid-transition,
  then the successful transition. On success persists the new state, event, and
  version, updates in-memory state, and returns `{:ok, new_state, new_version}`.
  """
  @spec transition(GenServer.server(), String.t(), event(), non_neg_integer()) ::
          {:ok, state_name(), non_neg_integer()}
          | {:error, :not_found}
          | {:error, {:stale_version, non_neg_integer()}}
          | {:error, :invalid_transition}
          | {:error, {:db_error, term()}}
  def transition(server, entity_id, event, expected_version) do
    GenServer.call(server, {:transition, entity_id, event, expected_version})
  end

  @doc """
  Returns `{:ok, list}` of every recorded transition for `entity_id` in
  chronological (insertion) order.

  Each entry is a map with keys `:event`, `:from_state`, `:to_state`, `:version`,
  and `:inserted_at`.
  """
  @spec history(GenServer.server(), String.t()) :: {:ok, [map()]}
  def history(server, entity_id) do
    GenServer.call(server, {:history, entity_id})
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  @spec init(keyword()) :: {:ok, map()}
  def init(opts) do
    repo = Keyword.fetch!(opts, :repo)
    {:ok, %{repo: repo, entities: %{}}}
  end

  @impl true
  def handle_call({:start, entity_id}, _from, state) do
    {cur_state, cur_version} = load_latest(state.repo, entity_id)
    entities = Map.put(state.entities, entity_id, {cur_state, cur_version})
    {:reply, {:ok, cur_state, cur_version}, %{state | entities: entities}}
  end

  def handle_call({:get_state, entity_id}, _from, state) do
    case Map.fetch(state.entities, entity_id) do
      {:ok, {cur_state, cur_version}} ->
        {:reply, {:ok, cur_state, cur_version}, state}

      :error ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:transition, entity_id, event, expected_version}, _from, state) do
    case Map.fetch(state.entities, entity_id) do
      :error ->
        {:reply, {:error, :not_found}, state}

      {:ok, {cur_state, cur_version}} ->
        do_transition(state, entity_id, event, expected_version, cur_state, cur_version)
    end
  end

  def handle_call({:history, entity_id}, _from, state) do
    rows = load_history(state.repo, entity_id)
    {:reply, {:ok, rows}, state}
  end

  # ---------------------------------------------------------------------------
  # Internal helpers
  # ---------------------------------------------------------------------------

  @spec do_transition(
          map(),
          String.t(),
          event(),
          non_neg_integer(),
          state_name(),
          non_neg_integer()
        ) :: {:reply, term(), map()}
  defp do_transition(state, entity_id, event, expected_version, cur_state, cur_version) do
    cond do
      expected_version != cur_version ->
        {:reply, {:error, {:stale_version, cur_version}}, state}

      not Map.has_key?(@transitions, {cur_state, event}) ->
        {:reply, {:error, :invalid_transition}, state}

      true ->
        next_state = Map.fetch!(@transitions, {cur_state, event})
        new_version = cur_version + 1
        commit(state, entity_id, event, cur_state, next_state, new_version)
    end
  end

  @spec commit(map(), String.t(), event(), state_name(), state_name(), non_neg_integer()) ::
          {:reply, term(), map()}
  defp commit(state, entity_id, event, from_state, to_state, new_version) do
    case persist(state.repo, entity_id, event, from_state, to_state, new_version) do
      {:ok, _record} ->
        entities = Map.put(state.entities, entity_id, {to_state, new_version})
        {:reply, {:ok, to_state, new_version}, %{state | entities: entities}}

      {:error, reason} ->
        {:reply, {:error, {:db_error, reason}}, state}
    end
  end

  @spec persist(module(), String.t(), event(), state_name(), state_name(), non_neg_integer()) ::
          {:ok, EntityTransition.t()} | {:error, term()}
  defp persist(repo, entity_id, event, from_state, to_state, version) do
    attrs = %{
      entity_id: entity_id,
      event: Atom.to_string(event),
      from_state: Atom.to_string(from_state),
      to_state: Atom.to_string(to_state),
      version: version,
      inserted_at: DateTime.utc_now()
    }

    %EntityTransition{}
    |> Ecto.Changeset.change(attrs)
    |> repo.insert()
  end

  @spec load_latest(module(), String.t()) :: {state_name(), non_neg_integer()}
  defp load_latest(repo, entity_id) do
    query =
      from(t in EntityTransition,
        where: t.entity_id == ^entity_id,
        order_by: [desc: t.version, desc: t.id],
        limit: 1
      )

    case repo.one(query) do
      nil ->
        {@initial_state, 0}

      %EntityTransition{to_state: to_state, version: version} ->
        {String.to_existing_atom(to_state), version}
    end
  end

  defp load_history(repo, entity_id) do
    # TODO
  end
end

```