defmodule StateMachine.Repo do
  @moduledoc """
  Ecto repository used by `StateMachine` to persist entity transitions.

  This module is intentionally a bare repo definition: its configuration
  (database path, pool, sandbox settings) and its supervision are supplied by the
  host application (or the test environment), which then injects the repo module
  into `StateMachine.start_link/1` via the `:repo` option.
  """

  use Ecto.Repo,
    otp_app: :state_machine,
    adapter: Ecto.Adapters.SQLite3
end

defmodule EntityTransition do
  @moduledoc """
  Ecto schema for the `entity_transitions` table.

  Every row records a single state-machine transition for an entity: the event that
  triggered it, the state the entity moved from, the state it moved to, and the
  timestamp at which the row was inserted.

  Atoms (`event`, `from_state`, `to_state`) are stored as strings in the database and
  are deserialised back into atoms by `StateMachine.history/2`.
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

  @primary_key {:id, :id, autogenerate: true}
  schema "entity_transitions" do
    field(:entity_id, :string)
    field(:event, :string)
    field(:from_state, :string)
    field(:to_state, :string)
    field(:inserted_at, :utc_datetime_usec)
  end

  @required_fields [:entity_id, :event, :from_state, :to_state, :inserted_at]

  @doc """
  Builds a changeset for an `EntityTransition` row.

  All of `:entity_id`, `:event`, `:from_state`, `:to_state` and `:inserted_at` are
  required; the string columns must additionally be non-empty.
  """
  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(transition, attrs) do
    transition
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
    |> validate_length(:entity_id, min: 1)
    |> validate_length(:event, min: 1)
    |> validate_length(:from_state, min: 1)
    |> validate_length(:to_state, min: 1)
  end
end

defmodule Repo.Migrations.CreateEntityTransitions do
  @moduledoc """
  Migration creating the `entity_transitions` table plus an index on `entity_id`.

  Written with plain `Ecto.Migration` primitives only, so it is valid for SQLite as
  well as other adapters.
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
      add(:inserted_at, :utc_datetime_usec, null: false)
    end

    create(index(:entity_transitions, [:entity_id]))
  end
end

defmodule StateMachine do
  @moduledoc """
  A `GenServer` managing the lifecycle of stateful entities, persisting every state
  transition to the database and expiring stale `:pending` entities automatically.

  ## Lifecycle

  States: `:pending`, `:confirmed`, `:shipped`, `:delivered`, `:cancelled`.

  Valid transitions:

      :pending   + :confirm -> :confirmed
      :confirmed + :ship    -> :shipped
      :shipped   + :deliver -> :delivered
      :pending   + :cancel  -> :cancelled
      :confirmed + :cancel  -> :cancelled
      :pending   + :expire  -> :cancelled

  Every other `{state, event}` pair is invalid and yields `{:error, :invalid_transition}`
  without touching the database.

  ## Automatic expiry

  When started with a non-negative integer `:pending_ttl_ms`, the server schedules an
  expiry check whenever `start/2` loads or seeds an entity that is currently `:pending`.
  When the check fires inside the server process, the entity is transitioned with the
  `:expire` event if — and only if — it is still `:pending`; otherwise the check is a
  silent no-op that writes nothing. Because the check runs in the server process, it
  serialises against manual `transition/3` calls: whichever runs first wins and the
  other becomes a no-op or an `{:error, :invalid_transition}`.

  ## State

  The server keeps an in-memory map of `%{entity_id => current_state}`. It is empty on
  restart, so the next `start/2` re-hydrates the entity from the most recent persisted
  `to_state` — including entities that were expired automatically.
  """

  use GenServer

  import Ecto.Query, only: [from: 2]

  @typedoc "A lifecycle state of an entity."
  @type state :: :pending | :confirmed | :shipped | :delivered | :cancelled

  @typedoc "An event that may drive a transition."
  @type event :: :confirm | :ship | :deliver | :cancel | :expire

  @typedoc "The identifier of a managed entity."
  @type entity_id :: String.t()

  @typedoc "A single history entry as returned by `history/2`."
  @type history_entry :: %{
          event: event(),
          from_state: state(),
          to_state: state(),
          inserted_at: DateTime.t()
        }

  @typedoc "Anything acceptable as a `GenServer` destination."
  @type server :: GenServer.server()

  @initial_state :pending

  @transitions %{
    {:pending, :confirm} => :confirmed,
    {:confirmed, :ship} => :shipped,
    {:shipped, :deliver} => :delivered,
    {:pending, :cancel} => :cancelled,
    {:confirmed, :cancel} => :cancelled,
    {:pending, :expire} => :cancelled
  }

  @states [:pending, :confirmed, :shipped, :delivered, :cancelled]
  @events [:confirm, :ship, :deliver, :cancel, :expire]

  defmodule State do
    @moduledoc false

    @enforce_keys [:repo]
    defstruct repo: nil, pending_ttl_ms: nil, entities: %{}

    @type t :: %__MODULE__{
            repo: module(),
            pending_ttl_ms: non_neg_integer() | nil,
            entities: %{optional(String.t()) => atom()}
          }
  end

  # ----------------------------------------------------------------------------
  # Public API
  # ----------------------------------------------------------------------------

  @doc """
  Starts the state machine server.

  ## Options

    * `:repo` — required; a configured and already-started `Ecto.Repo` module.
    * `:pending_ttl_ms` — optional non-negative integer; when given, entities that are
      `:pending` at `start/2` time are automatically expired after this many
      milliseconds. When absent or `nil`, automatic expiry is disabled.
    * `:name` — optional process registration name, forwarded to `GenServer.start_link/3`.

  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name], else: []

    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  @doc """
  Loads (or seeds) an entity into the server's in-memory map.

  The latest persisted `to_state` for `entity_id` becomes its current state; when no
  transition has ever been recorded, the entity starts in `:pending`.

  If the resulting state is `:pending` and a `:pending_ttl_ms` was configured, an expiry
  check is scheduled to fire after that many milliseconds.

  Always returns `{:ok, current_state}`.
  """
  @spec start(server(), entity_id()) :: {:ok, state()} | {:error, {:db_error, term()}}
  def start(server, entity_id) when is_binary(entity_id) do
    GenServer.call(server, {:start, entity_id})
  end

  @doc """
  Returns `{:ok, current_state}` for an entity previously loaded via `start/2`.

  Returns `{:error, :not_found}` when the entity has not been started in this session.
  """
  @spec get_state(server(), entity_id()) :: {:ok, state()} | {:error, :not_found}
  def get_state(server, entity_id) when is_binary(entity_id) do
    GenServer.call(server, {:get_state, entity_id})
  end

  @doc """
  Attempts to apply `event` to the entity identified by `entity_id`.

  Implemented as a `GenServer.call/3` so that concurrent callers serialise through the
  server process and no race conditions are possible.

  Returns:

    * `{:ok, new_state}` when the transition is valid and was persisted.
    * `{:error, :invalid_transition}` when the `{state, event}` pair is not valid;
      nothing is written.
    * `{:error, :not_found}` when the entity has not been started yet.
    * `{:error, {:db_error, reason}}` when persistence fails; the in-memory state is
      left untouched.

  """
  @spec transition(server(), entity_id(), event()) ::
          {:ok, state()}
          | {:error, :not_found}
          | {:error, :invalid_transition}
          | {:error, {:db_error, term()}}
  def transition(server, entity_id, event) when is_binary(entity_id) and is_atom(event) do
    GenServer.call(server, {:transition, entity_id, event})
  end

  @doc """
  Returns `{:ok, list}` with every recorded transition for `entity_id`, oldest first.

  Each entry is a map with `:event`, `:from_state`, `:to_state` (all atoms, deserialised
  from their string columns) and `:inserted_at` (a `DateTime`).
  """
  @spec history(server(), entity_id()) ::
          {:ok, [history_entry()]} | {:error, {:db_error, term()}}
  def history(server, entity_id) when is_binary(entity_id) do
    GenServer.call(server, {:history, entity_id})
  end

  # ----------------------------------------------------------------------------
  # GenServer callbacks
  # ----------------------------------------------------------------------------

  @impl GenServer
  def init(opts) do
    repo = Keyword.fetch!(opts, :repo)
    ttl = Keyword.get(opts, :pending_ttl_ms)

    if not (is_nil(ttl) or (is_integer(ttl) and ttl >= 0)) do
      raise ArgumentError,
            ":pending_ttl_ms must be nil or a non-negative integer, got: #{inspect(ttl)}"
    end

    {:ok, %State{repo: repo, pending_ttl_ms: ttl, entities: %{}}}
  end

  @impl GenServer
  def handle_call({:start, entity_id}, _from, %State{} = state) do
    case load_current_state(state.repo, entity_id) do
      {:ok, current} ->
        state = %State{state | entities: Map.put(state.entities, entity_id, current)}
        maybe_schedule_expiry(state, entity_id, current)
        {:reply, {:ok, current}, state}

      {:error, reason} ->
        {:reply, {:error, {:db_error, reason}}, state}
    end
  end

  def handle_call({:get_state, entity_id}, _from, %State{} = state) do
    case Map.fetch(state.entities, entity_id) do
      {:ok, current} -> {:reply, {:ok, current}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:transition, entity_id, event}, _from, %State{} = state) do
    case Map.fetch(state.entities, entity_id) do
      :error ->
        {:reply, {:error, :not_found}, state}

      {:ok, current} ->
        do_transition(state, entity_id, current, event)
    end
  end

  def handle_call({:history, entity_id}, _from, %State{} = state) do
    case fetch_history(state.repo, entity_id) do
      {:ok, entries} -> {:reply, {:ok, entries}, state}
      {:error, reason} -> {:reply, {:error, {:db_error, reason}}, state}
    end
  end

  @impl GenServer
  def handle_info({:expire_check, entity_id}, %State{} = state) do
    case Map.fetch(state.entities, entity_id) do
      {:ok, :pending} ->
        case do_transition(state, entity_id, :pending, :expire) do
          {:reply, {:ok, _new_state}, new_state} -> {:noreply, new_state}
          {:reply, {:error, _reason}, unchanged} -> {:noreply, unchanged}
        end

      _other ->
        {:noreply, state}
    end
  end

  def handle_info(_message, %State{} = state) do
    {:noreply, state}
  end

  # ----------------------------------------------------------------------------
  # Internals
  # ----------------------------------------------------------------------------

  @spec do_transition(State.t(), entity_id(), state(), event()) ::
          {:reply, term(), State.t()}
  defp do_transition(%State{} = state, entity_id, current, event) do
    case next_state(current, event) do
      :error ->
        {:reply, {:error, :invalid_transition}, state}

      {:ok, next} ->
        case persist(state.repo, entity_id, event, current, next) do
          {:ok, _row} ->
            entities = Map.put(state.entities, entity_id, next)
            {:reply, {:ok, next}, %State{state | entities: entities}}

          {:error, reason} ->
            {:reply, {:error, {:db_error, reason}}, state}
        end
    end
  end

  @spec next_state(state(), event()) :: {:ok, state()} | :error
  defp next_state(current, event) do
    Map.fetch(@transitions, {current, event})
  end

  @spec persist(module(), entity_id(), event(), state(), state()) ::
          {:ok, EntityTransition.t()} | {:error, term()}
  defp persist(repo, entity_id, event, from_state, to_state) do
    attrs = %{
      entity_id: entity_id,
      event: Atom.to_string(event),
      from_state: Atom.to_string(from_state),
      to_state: Atom.to_string(to_state),
      inserted_at: DateTime.utc_now()
    }

    changeset = EntityTransition.changeset(%EntityTransition{}, attrs)

    try do
      repo.insert(changeset)
    rescue
      exception -> {:error, exception}
    catch
      :exit, reason -> {:error, reason}
    end
  end

  @spec load_current_state(module(), entity_id()) :: {:ok, state()} | {:error, term()}
  defp load_current_state(repo, entity_id) do
    query =
      from(t in EntityTransition,
        where: t.entity_id == ^entity_id,
        order_by: [desc: t.id],
        limit: 1,
        select: t.to_state
      )

    try do
      case repo.one(query) do
        nil -> {:ok, @initial_state}
        to_state -> {:ok, to_atom(to_state, @states, @initial_state)}
      end
    rescue
      exception -> {:error, exception}
    catch
      :exit, reason -> {:error, reason}
    end
  end

  @spec fetch_history(module(), entity_id()) :: {:ok, [history_entry()]} | {:error, term()}
  defp fetch_history(repo, entity_id) do
    query =
      from(t in EntityTransition,
        where: t.entity_id == ^entity_id,
        order_by: [asc: t.id],
        select: %{
          event: t.event,
          from_state: t.from_state,
          to_state: t.to_state,
          inserted_at: t.inserted_at
        }
      )

    try do
      entries = repo.all(query)
      {:ok, Enum.map(entries, &decode_entry/1)}
    rescue
      exception -> {:error, exception}
    catch
      :exit, reason -> {:error, reason}
    end
  end

  @spec decode_entry(map()) :: history_entry()
  defp decode_entry(%{} = row) do
    %{
      event: to_atom(row.event, @events, nil),
      from_state: to_atom(row.from_state, @states, nil),
      to_state: to_atom(row.to_state, @states, nil),
      inserted_at: row.inserted_at
    }
  end

  # Deserialises a string column back into an atom, restricted to the known atoms so
  # that hostile or corrupted rows cannot exhaust the atom table.
  @spec to_atom(String.t() | atom(), [atom()], atom() | nil) :: atom() | nil
  defp to_atom(value, _allowed, _fallback) when is_atom(value), do: value

  defp to_atom(value, allowed, fallback) when is_binary(value) do
    Enum.find(allowed, fallback, fn known -> Atom.to_string(known) == value end)
  end

  @spec maybe_schedule_expiry(State.t(), entity_id(), state()) :: :ok
  defp maybe_schedule_expiry(%State{pending_ttl_ms: ttl}, entity_id, :pending)
       when is_integer(ttl) and ttl >= 0 do
    Process.send_after(self(), {:expire_check, entity_id}, ttl)
    :ok
  end

  defp maybe_schedule_expiry(%State{}, _entity_id, _current_state), do: :ok
end