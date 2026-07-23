<file path="lib/entity_transition.ex">
defmodule EntityTransition do
  @moduledoc """
  Ecto schema for a single persisted state-machine transition.

  Each row records that some `entity_id` moved from `from_state` to
  `to_state` in response to `event` at time `inserted_at`. The atom
  values used by the state machine are serialised to strings here.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @castable_fields [:entity_id, :event, :from_state, :to_state, :inserted_at]

  schema "entity_transitions" do
    field :entity_id, :string
    field :event, :string
    field :from_state, :string
    field :to_state, :string
    field :inserted_at, :utc_datetime_usec
  end

  @doc """
  Builds a changeset for inserting a transition row.

  All fields are required; `event`, `from_state` and `to_state` are the
  string serialisations of the corresponding atoms.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(struct, attrs) do
    struct
    |> cast(attrs, @castable_fields)
    |> validate_required(@castable_fields)
  end
end
</file>
<file path="lib/state_machine.ex">
defmodule StateMachine do
  @moduledoc """
  A `GenServer` that manages the lifecycle of stateful order entities.

  It enforces a fixed order-processing state machine, persists every
  valid transition to the database through a caller-supplied Ecto repo,
  and re-hydrates an entity's current state from the database the first
  time it is started within a server session.

  In-memory the server keeps a `%{entity_id => current_state}` map. On
  restart that map is empty, so the next `start/2` call rebuilds the
  state for an entity by reading its most recent persisted `to_state`.

  All state-changing work (the in-memory update and the DB write) happens
  inside `handle_call/3`, so concurrent callers serialise through the
  process and cannot race.
  """

  use GenServer

  import Ecto.Query, only: [from: 2]

  @typedoc "A valid lifecycle state."
  @type state :: :pending | :confirmed | :shipped | :delivered | :cancelled

  @typedoc "A valid lifecycle event."
  @type event :: :confirm | :ship | :deliver | :cancel

  @typedoc "A started or registered server reference."
  @type server :: GenServer.server()

  @transitions %{
    {:pending, :confirm} => :confirmed,
    {:confirmed, :ship} => :shipped,
    {:shipped, :deliver} => :delivered,
    {:pending, :cancel} => :cancelled,
    {:confirmed, :cancel} => :cancelled
  }

  # ------------------------------------------------------------------
  # Public API
  # ------------------------------------------------------------------

  @doc """
  Starts the state-machine server.

  Options:

    * `:repo` (required) — a configured Ecto repo module.
    * `:name` (optional) — a name for process registration.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    repo = Keyword.fetch!(opts, :repo)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, %{repo: repo}, gen_opts)
  end

  @doc """
  Loads (or initialises) the current state for `entity_id`.

  Reads the most recent persisted `to_state` for the entity. If no record
  exists the entity starts in `:pending`. Always returns `{:ok, state}`.
  """
  @spec start(server(), String.t()) :: {:ok, state()}
  def start(server, entity_id) do
    GenServer.call(server, {:start, entity_id})
  end

  @doc """
  Returns the current in-memory state for a previously started entity.

  Returns `{:error, :not_found}` if the entity was never started in this
  server session.
  """
  @spec get_state(server(), String.t()) :: {:ok, state()} | {:error, :not_found}
  def get_state(server, entity_id) do
    GenServer.call(server, {:get_state, entity_id})
  end

  @doc """
  Attempts to transition `entity_id` via `event`.

  On a valid transition the new state and event are persisted, the
  in-memory state is updated, and `{:ok, new_state}` is returned.

  Returns `{:error, :invalid_transition}` (writing nothing) for an invalid
  `(state, event)` pair, `{:error, :not_found}` if the entity has not been
  started, and `{:error, {:db_error, reason}}` if persistence fails.
  """
  @spec transition(server(), String.t(), event()) ::
          {:ok, state()}
          | {:error, :invalid_transition}
          | {:error, :not_found}
          | {:error, {:db_error, term()}}
  def transition(server, entity_id, event) do
    GenServer.call(server, {:transition, entity_id, event})
  end

  @doc """
  Returns every recorded transition for `entity_id` in chronological order.

  Each entry is a map with keys `:event`, `:from_state`, `:to_state` and
  `:inserted_at`.
  """
  @spec history(server(), String.t()) :: {:ok, [map()]}
  def history(server, entity_id) do
    GenServer.call(server, {:history, entity_id})
  end

  # ------------------------------------------------------------------
  # GenServer callbacks
  # ------------------------------------------------------------------

  @impl GenServer
  @spec init(%{repo: module()}) :: {:ok, map()}
  def init(%{repo: repo}) do
    {:ok, %{repo: repo, entities: %{}}}
  end

  @impl GenServer
  def handle_call({:start, entity_id}, _from, state) do
    current = load_state(state.repo, entity_id)
    entities = Map.put(state.entities, entity_id, current)
    {:reply, {:ok, current}, %{state | entities: entities}}
  end

  def handle_call({:get_state, entity_id}, _from, state) do
    case Map.fetch(state.entities, entity_id) do
      {:ok, current} -> {:reply, {:ok, current}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:transition, entity_id, event}, _from, state) do
    case Map.fetch(state.entities, entity_id) do
      :error ->
        {:reply, {:error, :not_found}, state}

      {:ok, current} ->
        do_transition(entity_id, event, current, state)
    end
  end

  def handle_call({:history, entity_id}, _from, state) do
    {:reply, {:ok, load_history(state.repo, entity_id)}, state}
  end

  # ------------------------------------------------------------------
  # Internal helpers
  # ------------------------------------------------------------------

  @spec do_transition(String.t(), event(), state(), map()) ::
          {:reply, term(), map()}
  defp do_transition(entity_id, event, current, state) do
    case Map.fetch(@transitions, {current, event}) do
      :error ->
        {:reply, {:error, :invalid_transition}, state}

      {:ok, next} ->
        case persist(state.repo, entity_id, event, current, next) do
          :ok ->
            entities = Map.put(state.entities, entity_id, next)
            {:reply, {:ok, next}, %{state | entities: entities}}

          {:error, reason} ->
            {:reply, {:error, {:db_error, reason}}, state}
        end
    end
  end

  @spec load_state(module(), String.t()) :: state()
  defp load_state(repo, entity_id) do
    query =
      from t in EntityTransition,
        where: t.entity_id == ^entity_id,
        order_by: [desc: t.inserted_at, desc: t.id],
        limit: 1,
        select: t.to_state

    case repo.one(query) do
      nil -> :pending
      to_state -> String.to_existing_atom(to_state)
    end
  end

  @spec load_history(module(), String.t()) :: [map()]
  defp load_history(repo, entity_id) do
    query =
      from t in EntityTransition,
        where: t.entity_id == ^entity_id,
        order_by: [asc: t.inserted_at, asc: t.id],
        select: %{
          event: t.event,
          from_state: t.from_state,
          to_state: t.to_state,
          inserted_at: t.inserted_at
        }

    repo.all(query)
  end

  @spec persist(module(), String.t(), event(), state(), state()) ::
          :ok | {:error, term()}
  defp persist(repo, entity_id, event, from_state, to_state) do
    attrs = %{
      entity_id: entity_id,
      event: Atom.to_string(event),
      from_state: Atom.to_string(from_state),
      to_state: Atom.to_string(to_state),
      inserted_at: DateTime.utc_now()
    }

    changeset = EntityTransition.changeset(%EntityTransition{}, attrs)

    case repo.insert(changeset) do
      {:ok, _record} -> :ok
      {:error, changeset} -> {:error, changeset}
    end
  rescue
    exception -> {:error, exception}
  end
end
</file>
<file path="priv/repo/migrations/20260723000000_create_entity_transitions.exs">
defmodule Repo.Migrations.CreateEntityTransitions do
  @moduledoc """
  Creates the `entity_transitions` table used to persist state-machine
  transitions.
  """

  use Ecto.Migration

  @doc """
  Creates the table and its `entity_id` index.
  """
  def change do
    create table(:entity_transitions) do
      add :entity_id, :string, null: false
      add :event, :string, null: false
      add :from_state, :string, null: false
      add :to_state, :string, null: false
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create index(:entity_transitions, [:entity_id])
  end
end
</file>