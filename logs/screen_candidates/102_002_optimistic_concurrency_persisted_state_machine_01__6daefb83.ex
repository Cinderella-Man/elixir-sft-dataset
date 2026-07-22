defmodule EntityTransition do
  @moduledoc """
  Ecto schema for a single persisted state-machine transition.

  Each row records the event that was applied, the state the entity moved from,
  the state it moved to, and the entity's version *after* the transition was
  applied. Rows are inserted in chronological order and are never updated.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "entity_transitions" do
    field(:entity_id, :string)
    field(:event, :string)
    field(:from_state, :string)
    field(:to_state, :string)
    field(:version, :integer)
    field(:inserted_at, :utc_datetime_usec)
  end

  @required_fields [:entity_id, :event, :from_state, :to_state, :version, :inserted_at]

  @doc """
  Builds a changeset for inserting a transition record.

  All fields are required; `version` must be non-negative.
  """
  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(transition, attrs) do
    transition
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
    |> validate_number(:version, greater_than_or_equal_to: 0)
  end
end

defmodule Repo.Migrations.CreateEntityTransitions do
  @moduledoc """
  Creates the `entity_transitions` table used to persist state-machine
  transitions, along with an index on `entity_id` for fast per-entity lookups.
  """

  use Ecto.Migration

  @doc """
  Creates the `entity_transitions` table and its `entity_id` index.
  """
  @spec change() :: any()
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
  A `GenServer` that manages the lifecycle of stateful entities with optimistic
  concurrency control.

  Entities follow an order-processing lifecycle:

      :pending    + :confirm  -> :confirmed
      :confirmed  + :ship     -> :shipped
      :shipped    + :deliver  -> :delivered
      :pending    + :cancel   -> :cancelled
      :confirmed  + :cancel   -> :cancelled

  Every entity carries a monotonically increasing version. A brand-new entity
  (with no persisted history) starts in the `:pending` state at version 0, and
  every successful transition increments the version by one. Callers of
  `transition/4` must present the version they expect the entity to be at; a
  mismatch is rejected as a stale write and nothing is persisted.

  Every successful transition is persisted to the `entity_transitions` table
  before the in-memory state is updated, so a failed database write leaves the
  in-memory state and version untouched. The GenServer holds an in-memory map of
  `%{entity_id => {current_state, current_version}}`; on restart that map is
  empty and the next `start/2` call re-hydrates it from the database.
  """

  use GenServer

  import Ecto.Query, only: [from: 2]

  @type state :: :pending | :confirmed | :shipped | :delivered | :cancelled
  @type event :: :confirm | :ship | :deliver | :cancel
  @type entity_id :: String.t()
  @type version :: non_neg_integer()

  @initial_state :pending
  @initial_version 0

  @transitions %{
    {:pending, :confirm} => :confirmed,
    {:confirmed, :ship} => :shipped,
    {:shipped, :deliver} => :delivered,
    {:pending, :cancel} => :cancelled,
    {:confirmed, :cancel} => :cancelled
  }

  # Public API

  @doc """
  Starts the state machine server.

  ## Options

    * `:repo` - (required) a configured Ecto repo module used for persistence.
    * `:name` - (optional) a name to register the process under.

  Any other options are passed through to `GenServer.start_link/3`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {repo, opts} = Keyword.pop!(opts, :repo)
    {name, opts} = Keyword.pop(opts, :name)

    server_opts = if name, do: Keyword.put(opts, :name, name), else: opts

    GenServer.start_link(__MODULE__, %{repo: repo}, server_opts)
  end

  @doc """
  Starts tracking `entity_id`, loading its latest persisted state and version.

  If the entity has no persisted history it begins in the `:pending` state at
  version 0. Returns `{:ok, current_state, current_version}`.
  """
  @spec start(GenServer.server(), entity_id()) :: {:ok, state(), version()}
  def start(server, entity_id) do
    GenServer.call(server, {:start, entity_id})
  end

  @doc """
  Returns `{:ok, current_state, current_version}` for a previously started
  entity, or `{:error, :not_found}` if it has never been started in this
  server session.
  """
  @spec get_state(GenServer.server(), entity_id()) ::
          {:ok, state(), version()} | {:error, :not_found}
  def get_state(server, entity_id) do
    GenServer.call(server, {:get_state, entity_id})
  end

  @doc """
  Attempts to apply `event` to `entity_id`, which must currently be at
  `expected_version`.

  Checks are applied in order:

    1. `{:error, :not_found}` if the entity was never started in this session.
    2. `{:error, {:stale_version, current_version}}` if `expected_version` does
       not match the entity's current version.
    3. `{:error, :invalid_transition}` if the `(state, event)` pair is invalid.
    4. Otherwise the transition is persisted and
       `{:ok, new_state, new_version}` is returned.

  A database write failure returns `{:error, {:db_error, reason}}` and leaves
  the in-memory state and version unchanged.
  """
  @spec transition(GenServer.server(), entity_id(), event(), version()) ::
          {:ok, state(), version()}
          | {:error, :not_found}
          | {:error, :invalid_transition}
          | {:error, {:stale_version, version()}}
          | {:error, {:db_error, term()}}
  def transition(server, entity_id, event, expected_version) do
    GenServer.call(server, {:transition, entity_id, event, expected_version})
  end

  @doc """
  Returns `{:ok, list}` with every recorded transition for `entity_id` in
  chronological (insertion) order.

  Each entry is a map with the keys `:event`, `:from_state`, `:to_state`,
  `:version` and `:inserted_at`.
  """
  @spec history(GenServer.server(), entity_id()) :: {:ok, [map()]}
  def history(server, entity_id) do
    GenServer.call(server, {:history, entity_id})
  end

  # GenServer callbacks

  @impl GenServer
  def init(%{repo: repo}) do
    {:ok, %{repo: repo, entities: %{}}}
  end

  @impl GenServer
  def handle_call({:start, entity_id}, _from, state) do
    {current_state, current_version} = load_entity(state.repo, entity_id)
    entities = Map.put(state.entities, entity_id, {current_state, current_version})

    {:reply, {:ok, current_state, current_version}, %{state | entities: entities}}
  end

  def handle_call({:get_state, entity_id}, _from, state) do
    case Map.fetch(state.entities, entity_id) do
      {:ok, {current_state, current_version}} -> {:reply, {:ok, current_state, current_version}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:transition, entity_id, event, expected_version}, _from, state) do
    with {:ok, {current_state, current_version}} <- fetch_entity(state.entities, entity_id),
         :ok <- check_version(current_version, expected_version),
         {:ok, next_state} <- next_state(current_state, event) do
      new_version = current_version + 1

      case persist(state.repo, entity_id, event, current_state, next_state, new_version) do
        :ok ->
          entities = Map.put(state.entities, entity_id, {next_state, new_version})
          {:reply, {:ok, next_state, new_version}, %{state | entities: entities}}

        {:error, reason} ->
          {:reply, {:error, {:db_error, reason}}, state}
      end
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:history, entity_id}, _from, state) do
    {:reply, {:ok, load_history(state.repo, entity_id)}, state}
  end

  # Internal helpers

  @spec fetch_entity(map(), entity_id()) ::
          {:ok, {state(), version()}} | {:error, :not_found}
  defp fetch_entity(entities, entity_id) do
    case Map.fetch(entities, entity_id) do
      {:ok, entry} -> {:ok, entry}
      :error -> {:error, :not_found}
    end
  end

  @spec check_version(version(), term()) :: :ok | {:error, {:stale_version, version()}}
  defp check_version(current_version, expected_version) do
    if current_version === expected_version do
      :ok
    else
      {:error, {:stale_version, current_version}}
    end
  end

  @spec next_state(state(), event()) :: {:ok, state()} | {:error, :invalid_transition}
  defp next_state(current_state, event) do
    case Map.fetch(@transitions, {current_state, event}) do
      {:ok, next} -> {:ok, next}
      :error -> {:error, :invalid_transition}
    end
  end

  @spec load_entity(module(), entity_id()) :: {state(), version()}
  defp load_entity(repo, entity_id) do
    query =
      from(t in EntityTransition,
        where: t.entity_id == ^entity_id,
        order_by: [desc: t.version, desc: t.id],
        limit: 1,
        select: {t.to_state, t.version}
      )

    case repo.one(query) do
      nil -> {@initial_state, @initial_version}
      {to_state, version} -> {String.to_existing_atom(to_state), version}
    end
  end

  @spec load_history(module(), entity_id()) :: [map()]
  defp load_history(repo, entity_id) do
    query =
      from(t in EntityTransition,
        where: t.entity_id == ^entity_id,
        order_by: [asc: t.id],
        select: %{
          event: t.event,
          from_state: t.from_state,
          to_state: t.to_state,
          version: t.version,
          inserted_at: t.inserted_at
        }
      )

    query
    |> repo.all()
    |> Enum.map(fn row ->
      %{
        event: String.to_existing_atom(row.event),
        from_state: String.to_existing_atom(row.from_state),
        to_state: String.to_existing_atom(row.to_state),
        version: row.version,
        inserted_at: row.inserted_at
      }
    end)
  end

  @spec persist(module(), entity_id(), event(), state(), state(), version()) ::
          :ok | {:error, term()}
  defp persist(repo, entity_id, event, from_state, to_state, version) do
    attrs = %{
      entity_id: entity_id,
      event: Atom.to_string(event),
      from_state: Atom.to_string(from_state),
      to_state: Atom.to_string(to_state),
      version: version,
      inserted_at: DateTime.utc_now()
    }

    changeset = EntityTransition.changeset(%EntityTransition{}, attrs)

    try do
      case repo.insert(changeset) do
        {:ok, _record} -> :ok
        {:error, reason} -> {:error, reason}
      end
    rescue
      exception -> {:error, exception}
    catch
      :exit, reason -> {:error, reason}
    end
  end
end