<file path="lib/entity_transition.ex">
defmodule EntityTransition do
  @moduledoc """
  Ecto schema representing a single persisted state-machine transition.

  Each row records that a given `entity_id` moved from `from_state` to
  `to_state` in response to `event`, at time `inserted_at`. The atom values
  for events and states are serialised as strings in the database.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          entity_id: String.t() | nil,
          event: String.t() | nil,
          from_state: String.t() | nil,
          to_state: String.t() | nil,
          inserted_at: DateTime.t() | nil
        }

  schema "entity_transitions" do
    field :entity_id, :string
    field :event, :string
    field :from_state, :string
    field :to_state, :string
    field :inserted_at, :utc_datetime_usec
  end

  @doc """
  Builds a changeset validating that all transition fields are present.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(transition, attrs) do
    transition
    |> cast(attrs, [:entity_id, :event, :from_state, :to_state, :inserted_at])
    |> validate_required([:entity_id, :event, :from_state, :to_state, :inserted_at])
  end
end
</file>
<file path="lib/state_machine.ex">
defmodule StateMachine do
  @moduledoc """
  A GenServer managing the lifecycle of stateful entities.

  It implements an order-processing state machine, persists every valid
  transition to a database via an injected Ecto repo, and re-hydrates an
  entity's current state from the database on demand (e.g. after a restart,
  when the in-memory map has been reset).

  ## States

    * `:pending`, `:confirmed`, `:shipped`, `:delivered`, `:cancelled`

  ## Valid transitions

    * `:pending`   + `:confirm` -> `:confirmed`
    * `:confirmed` + `:ship`    -> `:shipped`
    * `:shipped`   + `:deliver` -> `:delivered`
    * `:pending`   + `:cancel`  -> `:cancelled`
    * `:confirmed` + `:cancel`  -> `:cancelled`

  Any other `(state, event)` combination is invalid.
  """

  use GenServer

  import Ecto.Query

  @typedoc "A valid state-machine state."
  @type state :: :pending | :confirmed | :shipped | :delivered | :cancelled

  @typedoc "An event that may drive a transition."
  @type event :: :confirm | :ship | :deliver | :cancel

  @transitions %{
    {:pending, :confirm} => :confirmed,
    {:confirmed, :ship} => :shipped,
    {:shipped, :deliver} => :delivered,
    {:pending, :cancel} => :cancelled,
    {:confirmed, :cancel} => :cancelled
  }

  # ── Public API ────────────────────────────────────────────────────────────

  @doc """
  Starts the state-machine server.

  Options:

    * `:repo` (required) — a configured Ecto repo module used for persistence.
    * `:name` (optional) — a name under which to register the process.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name, init_opts} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, init_opts, gen_opts)
  end

  @doc """
  Loads the latest persisted state for `entity_id` into the server.

  If no record exists, the entity starts in `:pending`. Returns
  `{:ok, current_state}`.
  """
  @spec start(GenServer.server(), String.t()) :: {:ok, state()}
  def start(server, entity_id) do
    GenServer.call(server, {:start, entity_id})
  end

  @doc """
  Returns `{:ok, current_state}` for a previously started entity, or
  `{:error, :not_found}` if it has never been started in this session.
  """
  @spec get_state(GenServer.server(), String.t()) :: {:ok, state()} | {:error, :not_found}
  def get_state(server, entity_id) do
    GenServer.call(server, {:get_state, entity_id})
  end

  @doc """
  Attempts to transition `entity_id` via `event`.

  Returns `{:ok, new_state}` on success, `{:error, :invalid_transition}` for a
  disallowed `(state, event)` pair, `{:error, :not_found}` if the entity was
  never started, or `{:error, {:db_error, reason}}` if persistence fails.
  """
  @spec transition(GenServer.server(), String.t(), event()) ::
          {:ok, state()}
          | {:error, :invalid_transition | :not_found | {:db_error, term()}}
  def transition(server, entity_id, event) do
    GenServer.call(server, {:transition, entity_id, event})
  end

  @doc """
  Returns `{:ok, list}` of every recorded transition for `entity_id` in
  chronological order, each a map with `:event`, `:from_state`, `:to_state`
  and `:inserted_at`.
  """
  @spec history(GenServer.server(), String.t()) :: {:ok, [map()]}
  def history(server, entity_id) do
    GenServer.call(server, {:history, entity_id})
  end

  # ── GenServer callbacks ───────────────────────────────────────────────────

  @impl true
  @spec init(keyword()) :: {:ok, map()}
  def init(opts) do
    repo = Keyword.fetch!(opts, :repo)
    {:ok, %{repo: repo, entities: %{}}}
  end

  @impl true
  def handle_call({:start, entity_id}, _from, %{repo: repo, entities: entities} = state) do
    current = load_latest_state(repo, entity_id)
    new_entities = Map.put(entities, entity_id, current)
    {:reply, {:ok, current}, %{state | entities: new_entities}}
  end

  def handle_call({:get_state, entity_id}, _from, %{entities: entities} = state) do
    case Map.fetch(entities, entity_id) do
      {:ok, current} -> {:reply, {:ok, current}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:transition, entity_id, event}, _from, state) do
    %{repo: repo, entities: entities} = state

    case Map.fetch(entities, entity_id) do
      :error ->
        {:reply, {:error, :not_found}, state}

      {:ok, current} ->
        handle_transition(state, repo, entities, entity_id, current, event)
    end
  end

  def handle_call({:history, entity_id}, _from, %{repo: repo} = state) do
    {:reply, {:ok, load_history(repo, entity_id)}, state}
  end

  # ── Internal helpers ──────────────────────────────────────────────────────

  @spec handle_transition(map(), module(), map(), String.t(), state(), event()) ::
          {:reply, term(), map()}
  defp handle_transition(state, repo, entities, entity_id, current, event) do
    case Map.get(@transitions, {current, event}) do
      nil ->
        {:reply, {:error, :invalid_transition}, state}

      next ->
        case persist(repo, entity_id, event, current, next) do
          {:ok, _record} ->
            new_entities = Map.put(entities, entity_id, next)
            {:reply, {:ok, next}, %{state | entities: new_entities}}

          {:error, reason} ->
            {:reply, {:error, {:db_error, reason}}, state}
        end
    end
  end

  @spec persist(module(), String.t(), event(), state(), state()) ::
          {:ok, EntityTransition.t()} | {:error, term()}
  defp persist(repo, entity_id, event, from_state, to_state) do
    record = %EntityTransition{
      entity_id: entity_id,
      event: Atom.to_string(event),
      from_state: Atom.to_string(from_state),
      to_state: Atom.to_string(to_state),
      inserted_at: DateTime.utc_now()
    }

    try do
      repo.insert(record)
    rescue
      error -> {:error, error}
    end
  end

  @spec load_latest_state(module(), String.t()) :: state()
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

  @spec load_history(module(), String.t()) :: [map()]
  defp load_history(repo, entity_id) do
    query =
      from t in EntityTransition,
        where: t.entity_id == ^entity_id,
        order_by: [asc: t.inserted_at, asc: t.id]

    repo.all(query)
    |> Enum.map(fn t ->
      %{
        event: String.to_existing_atom(t.event),
        from_state: String.to_existing_atom(t.from_state),
        to_state: String.to_existing_atom(t.to_state),
        inserted_at: t.inserted_at
      }
    end)
  end
end
</file>
<file path="priv/repo/migrations/20260709000000_create_entity_transitions.exs">
defmodule Repo.Migrations.CreateEntityTransitions do
  @moduledoc """
  Creates the `entity_transitions` table backing the `StateMachine` server.
  """

  use Ecto.Migration

  @doc """
  Creates the table and its index on `entity_id`.
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