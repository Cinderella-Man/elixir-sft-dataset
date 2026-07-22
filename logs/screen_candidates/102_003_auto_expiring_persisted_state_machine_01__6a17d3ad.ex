defmodule EntityTransition do
  @moduledoc """
  Ecto schema for the `entity_transitions` table.

  Every row records a single state transition of a stateful entity: the event that was
  applied, the state the entity was in before the event (`from_state`), the state it moved
  to (`to_state`) and the time the row was inserted.

  Rows are append-only: the most recently inserted row for an `entity_id` describes the
  entity's current state.
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

  @required_fields [:entity_id, :event, :from_state, :to_state, :inserted_at]

  schema "entity_transitions" do
    field :entity_id, :string
    field :event, :string
    field :from_state, :string
    field :to_state, :string
    field :inserted_at, :utc_datetime_usec
  end

  @doc """
  Builds a changeset for a transition row.

  All fields (`:entity_id`, `:event`, `:from_state`, `:to_state`, `:inserted_at`) are
  required, mirroring the non-null constraints of the underlying table.
  """
  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(transition \\ %__MODULE__{}, attrs) do
    transition
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
  end
end

defmodule Repo.Migrations.CreateEntityTransitions do
  @moduledoc """
  Migration creating the `entity_transitions` table used by `StateMachine`.

  The table stores an append-only log of state transitions, with an index on `entity_id`
  so the latest state and full history of an entity can be fetched cheaply.
  """

  use Ecto.Migration

  @doc """
  Creates the `entity_transitions` table and the index on `entity_id`.
  """
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

defmodule StateMachine do
  @moduledoc """
  A `GenServer` that manages the lifecycle of stateful entities (an order-processing state
  machine), persisting every state transition to the database via an injected Ecto repo.

  ## States and transitions

      :pending   + :confirm  -> :confirmed
      :confirmed + :ship     -> :shipped
      :shipped   + :deliver  -> :delivered
      :pending   + :cancel   -> :cancelled
      :confirmed + :cancel   -> :cancelled
      :pending   + :expire   -> :cancelled

  Any other `{state, event}` pair is invalid and is rejected with
  `{:error, :invalid_transition}` without writing anything.

  ## Automatic expiry

  When started with a non-negative `:pending_ttl_ms` option, an entity that is `:pending`
  at the time `start/2` is called has an expiry check scheduled `pending_ttl_ms`
  milliseconds later. When the check fires *inside the server process*, and the entity is
  still `:pending`, the `:expire` event is applied: the entity becomes `:cancelled` and a
  transition row with event `"expire"` is persisted, exactly as for a manual transition.
  If the entity moved on in the meantime the check is a no-op and writes nothing.

  Because both manual transitions and expiry checks are handled by the server process,
  they serialize against each other: whichever happens first wins and the other becomes a
  no-op or an `{:error, :invalid_transition}`.

  ## In-memory state

  The server keeps a map of `%{entity_id => current_state}`. It is rebuilt lazily: on
  restart the map is empty and the next `start/2` call re-hydrates the entity from the
  database (including entities that were automatically expired).
  """

  use GenServer

  import Ecto.Query, only: [from: 2]

  @typedoc "A state of the order lifecycle."
  @type state :: :pending | :confirmed | :shipped | :delivered | :cancelled

  @typedoc "An event that may be applied to an entity."
  @type event :: :confirm | :ship | :deliver | :cancel | :expire

  @typedoc "A recorded transition, as returned by `history/2`."
  @type history_entry :: %{
          event: String.t(),
          from_state: String.t(),
          to_state: String.t(),
          inserted_at: DateTime.t()
        }

  @transitions %{
    {:pending, :confirm} => :confirmed,
    {:confirmed, :ship} => :shipped,
    {:shipped, :deliver} => :delivered,
    {:pending, :cancel} => :cancelled,
    {:confirmed, :cancel} => :cancelled,
    {:pending, :expire} => :cancelled
  }

  @states [:pending, :confirmed, :shipped, :delivered, :cancelled]
  @state_by_string Map.new(@states, fn state -> {Atom.to_string(state), state} end)

  # Internal server state.
  defstruct repo: nil, pending_ttl_ms: nil, entities: %{}

  ## Public API

  @doc """
  Starts the state machine server.

  ## Options

    * `:repo` — required, a configured `Ecto.Repo` module used for persistence.
    * `:pending_ttl_ms` — optional non-negative integer. When given, entities that are
      `:pending` when `start/2` is called are automatically transitioned to `:cancelled`
      after this many milliseconds (unless they left `:pending` first). When omitted or
      `nil`, automatic expiry is disabled.
    * `:name` — optional process name for registration.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name], else: []

    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  @doc """
  Loads (or seeds) the entity identified by `entity_id` and returns its current state.

  The most recent persisted `to_state` for the entity is used; if the entity has no
  persisted transitions it starts in `:pending`. When a `:pending_ttl_ms` was configured
  and the loaded state is `:pending`, an expiry check is scheduled at this point.
  """
  @spec start(GenServer.server(), String.t()) :: {:ok, state()}
  def start(server, entity_id) when is_binary(entity_id) do
    GenServer.call(server, {:start, entity_id})
  end

  @doc """
  Returns `{:ok, current_state}` for an entity previously loaded with `start/2`, or
  `{:error, :not_found}` when the entity has never been started in this session.
  """
  @spec get_state(GenServer.server(), String.t()) :: {:ok, state()} | {:error, :not_found}
  def get_state(server, entity_id) when is_binary(entity_id) do
    GenServer.call(server, {:get_state, entity_id})
  end

  @doc """
  Applies `event` to the entity, persisting the resulting transition.

  Returns `{:ok, new_state}` on success, `{:error, :invalid_transition}` when the
  `{current_state, event}` pair is not part of the state machine (nothing is written),
  `{:error, :not_found}` when the entity was never started, and
  `{:error, {:db_error, reason}}` when persistence fails (the in-memory state is left
  untouched).

  Implemented as a `GenServer.call/3` so that concurrent callers serialize through the
  server process.
  """
  @spec transition(GenServer.server(), String.t(), event()) ::
          {:ok, state()}
          | {:error, :invalid_transition}
          | {:error, :not_found}
          | {:error, {:db_error, term()}}
  def transition(server, entity_id, event) when is_binary(entity_id) and is_atom(event) do
    GenServer.call(server, {:transition, entity_id, event})
  end

  @doc """
  Returns `{:ok, list}` with every persisted transition of the entity, in chronological
  (insertion) order. Each entry is a map with the keys `:event`, `:from_state`,
  `:to_state` and `:inserted_at`.
  """
  @spec history(GenServer.server(), String.t()) :: {:ok, [history_entry()]}
  def history(server, entity_id) when is_binary(entity_id) do
    GenServer.call(server, {:history, entity_id})
  end

  ## GenServer callbacks

  @impl GenServer
  def init(opts) do
    repo = Keyword.fetch!(opts, :repo)
    ttl = Keyword.get(opts, :pending_ttl_ms)

    unless is_nil(ttl) or (is_integer(ttl) and ttl >= 0) do
      raise ArgumentError,
            ":pending_ttl_ms must be nil or a non-negative integer, got: #{inspect(ttl)}"
    end

    {:ok, %__MODULE__{repo: repo, pending_ttl_ms: ttl, entities: %{}}}
  end

  @impl GenServer
  def handle_call({:start, entity_id}, _from, state) do
    current = load_state(state.repo, entity_id)
    state = put_in(state.entities[entity_id], current)

    maybe_schedule_expiry(state, entity_id, current)

    {:reply, {:ok, current}, state}
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
        apply_event(state, entity_id, current, event)
    end
  end

  def handle_call({:history, entity_id}, _from, state) do
    {:reply, {:ok, load_history(state.repo, entity_id)}, state}
  end

  @impl GenServer
  def handle_info({:expiry_check, entity_id}, state) do
    case Map.get(state.entities, entity_id) do
      :pending ->
        {_reply, state} =
          case apply_event(state, entity_id, :pending, :expire) do
            {:reply, reply, new_state} -> {reply, new_state}
          end

        {:noreply, state}

      _other ->
        {:noreply, state}
    end
  end

  def handle_info(_message, state) do
    {:noreply, state}
  end

  ## Internals

  # Applies `event` to `current`, persisting the transition on success. Returns a
  # `handle_call/3`-shaped reply so it can be reused by the expiry check.
  defp apply_event(state, entity_id, current, event) do
    case Map.fetch(@transitions, {current, event}) do
      :error ->
        {:reply, {:error, :invalid_transition}, state}

      {:ok, next} ->
        case persist(state.repo, entity_id, event, current, next) do
          :ok ->
            {:reply, {:ok, next}, put_in(state.entities[entity_id], next)}

          {:error, reason} ->
            {:reply, {:error, {:db_error, reason}}, state}
        end
    end
  end

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
      {:ok, _row} -> :ok
      {:error, reason} -> {:error, reason}
    end
  rescue
    exception -> {:error, exception}
  catch
    :exit, reason -> {:error, reason}
  end

  defp load_state(repo, entity_id) do
    query =
      from t in EntityTransition,
        where: t.entity_id == ^entity_id,
        order_by: [desc: t.id],
        limit: 1,
        select: t.to_state

    case repo.one(query) do
      nil -> :pending
      to_state -> Map.get(@state_by_string, to_state, :pending)
    end
  end

  defp load_history(repo, entity_id) do
    query =
      from t in EntityTransition,
        where: t.entity_id == ^entity_id,
        order_by: [asc: t.id],
        select: %{
          event: t.event,
          from_state: t.from_state,
          to_state: t.to_state,
          inserted_at: t.inserted_at
        }

    repo.all(query)
  end

  defp maybe_schedule_expiry(%__MODULE__{pending_ttl_ms: ttl}, entity_id, :pending)
       when is_integer(ttl) do
    Process.send_after(self(), {:expiry_check, entity_id}, ttl)
    :ok
  end

  defp maybe_schedule_expiry(_state, _entity_id, _current), do: :ok
end