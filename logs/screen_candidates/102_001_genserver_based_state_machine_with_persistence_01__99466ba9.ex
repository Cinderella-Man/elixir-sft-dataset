<file path="lib/entity_transition.ex">
defmodule EntityTransition do
  @moduledoc """
  Ecto schema for a single persisted state-machine transition.

  Each row records one successful transition of an entity: the event that
  triggered it, the state it moved from, the state it moved to, and the
  timestamp at which it was written. Rows are append-only and, read in
  chronological order, form the complete history of an entity's lifecycle.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "entity_transitions" do
    field :entity_id, :string
    field :event, :string
    field :from_state, :string
    field :to_state, :string
    field :inserted_at, :utc_datetime_usec
  end

  @required [:entity_id, :event, :from_state, :to_state, :inserted_at]

  @doc """
  Builds a changeset for inserting a transition row.

  All fields are required and validated for presence.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = transition, attrs) do
    transition
    |> cast(attrs, @required)
    |> validate_required(@required)
  end
end
</file>
<file path="lib/state_machine.ex">
defmodule StateMachine do
  @moduledoc """
  A `GenServer` that manages the lifecycle of stateful order entities.

  The server enforces a fixed order-processing state machine, persists every
  valid transition to a database via an injected Ecto repo, and re-hydrates an
  entity's current state from that database whenever it is (re)started.

  In-memory, the server keeps a map of `%{entity_id => current_state}`. This map
  is empty after a restart; the next `start/2` call for an entity reloads its
  most recent state from the persisted transition log.

  ## State machine

  States: `:pending`, `:confirmed`, `:shipped`, `:delivered`, `:cancelled`.

  Valid transitions:

    * `:pending` + `:confirm` -> `:confirmed`
    * `:confirmed` + `:ship` -> `:shipped`
    * `:shipped` + `:deliver` -> `:delivered`
    * `:pending` + `:cancel` -> `:cancelled`
    * `:confirmed` + `:cancel` -> `:cancelled`

  Any other `{state, event}` pair is invalid.
  """

  use GenServer

  import Ecto.Query, only: [from: 2]

  @type server :: GenServer.server()
  @type entity_id :: String.t()
  @type state :: :pending | :confirmed | :shipped | :delivered | :cancelled
  @type event :: :confirm | :ship | :deliver | :cancel

  @transitions %{
    {:pending, :confirm} => :confirmed,
    {:confirmed, :ship} => :shipped,
    {:shipped, :deliver} => :delivered,
    {:pending, :cancel} => :cancelled,
    {:confirmed, :cancel} => :cancelled
  }

  # ── Public API ──────────────────────────────────────────────────────────────

  @doc """
  Starts the state-machine server.

  Options:

    * `:repo` (required) — a configured Ecto repo module used for persistence.
    * `:name` (optional) — a name under which to register the process.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc """
  Loads the latest persisted state for `entity_id` into the server session.

  If no transitions exist for the entity, it starts in the `:pending` state.
  Always returns `{:ok, current_state}`.
  """
  @spec start(server(), entity_id()) :: {:ok, state()}
  def start(server, entity_id) do
    GenServer.call(server, {:start, entity_id})
  end

  @doc """
  Returns the in-memory current state for a previously started entity.

  Returns `{:error, :not_found}` if the entity has not been started in this
  server session.
  """
  @spec get_state(server(), entity_id()) :: {:ok, state()} | {:error, :not_found}
  def get_state(server, entity_id) do
    GenServer.call(server, {:get_state, entity_id})
  end

  @doc """
  Attempts to transition `entity_id` via `event`.

    * On a valid transition, persists the new state and event, updates in-memory
      state, and returns `{:ok, new_state}`.
    * On an invalid `{state, event}` pair, returns `{:error, :invalid_transition}`
      and writes nothing.
    * If the entity has not been started, returns `{:error, :not_found}`.
    * On a database write failure, returns `{:error, {:db_error, reason}}` and
      leaves the in-memory state unchanged.
  """
  @spec transition(server(), entity_id(), event()) ::
          {:ok, state()}
          | {:error, :invalid_transition | :not_found | {:db_error, term()}}
  def transition(server, entity_id, event) do
    GenServer.call(server, {:transition, entity_id, event})
  end

  @doc """
  Returns `{:ok, list}` of every recorded transition for `entity_id` in
  chronological order.

  Each entry is a map with keys `:event`, `:from_state`, `:to_state`, and
  `:inserted_at`.
  """
  @spec history(server(), entity_id()) :: {:ok, [map()]}
  def history(server, entity_id) do
    GenServer.call(server, {:history, entity_id})
  end

  # ── GenServer callbacks ─────────────────────────────────────────────────────

  @impl GenServer
  @spec init(keyword()) :: {:ok, map()}
  def init(opts) do
    repo = Keyword.fetch!(opts, :repo)
    {:ok, %{repo: repo, entities: %{}}}
  end

  @impl GenServer
  def handle_call({:start, entity_id}, _from, state) do
    current = load_latest_state(state.repo, entity_id)
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
    query =
      from t in EntityTransition,
        where: t.entity_id == ^entity_id,
        order_by: [asc: t.inserted_at, asc: t.id]

    entries =
      query
      |> state.repo.all()
      |> Enum.map(fn t ->
        %{
          event: String.to_existing_atom(t.event),
          from_state: String.to_existing_atom(t.from_state),
          to_state: String.to_existing_atom(t.to_state),
          inserted_at: t.inserted_at
        }
      end)

    {:reply, {:ok, entries}, state}
  end

  # ── Internal helpers ────────────────────────────────────────────────────────

  @spec do_transition(entity_id(), event(), state(), map()) ::
          {:reply, term(), map()}
  defp do_transition(entity_id, event, current, state) do
    case Map.get(@transitions, {current, event}) do
      nil ->
        {:reply, {:error, :invalid_transition}, state}

      next ->
        case persist(state.repo, entity_id, event, current, next) do
          :ok ->
            entities = Map.put(state.entities, entity_id, next)
            {:reply, {:ok, next}, %{state | entities: entities}}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end

  @spec load_latest_state(module(), entity_id()) :: state()
  defp load_latest_state(repo, entity_id) do
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

  @spec persist(module(), entity_id(), event(), state(), state()) ::
          :ok | {:error, {:db_error, term()}}
  defp persist(repo, entity_id, event, from, to) do
    attrs = %{
      entity_id: entity_id,
      event: Atom.to_string(event),
      from_state: Atom.to_string(from),
      to_state: Atom.to_string(to),
      inserted_at: DateTime.utc_now()
    }

    changeset = EntityTransition.changeset(%EntityTransition{}, attrs)

    try do
      case repo.insert(changeset) do
        {:ok, _record} -> :ok
        {:error, reason} -> {:error, {:db_error, reason}}
      end
    rescue
      exception -> {:error, {:db_error, exception}}
    end
  end
end
</file>
<file path="priv/repo/migrations/20260723000000_create_entity_transitions.exs">
defmodule Repo.Migrations.CreateEntityTransitions do
  @moduledoc """
  Creates the `entity_transitions` table used to persist state-machine
  transitions, plus an index on `entity_id` for history/latest-state lookups.
  """

  use Ecto.Migration

  @spec change() :: any()
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