defmodule EntityTransition do
  @moduledoc """
  Ecto schema for the `entity_transitions` table.

  Each row records a single successful state transition of an entity: the event that was
  applied, the state the entity was in before the event (`from_state`), the state it moved
  to (`to_state`), and the entity's version *after* the transition.

  Atoms are serialised as strings in the database; the `StateMachine` GenServer converts
  them back into atoms when it re-hydrates an entity or builds its history.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          entity_id: String.t() | nil,
          event: String.t() | nil,
          from_state: String.t() | nil,
          to_state: String.t() | nil,
          version: integer() | nil,
          inserted_at: DateTime.t() | nil
        }

  @required_fields [:entity_id, :event, :from_state, :to_state, :version, :inserted_at]

  schema "entity_transitions" do
    field(:entity_id, :string)
    field(:event, :string)
    field(:from_state, :string)
    field(:to_state, :string)
    field(:version, :integer)
    field(:inserted_at, :utc_datetime_usec)
  end

  @doc """
  Builds a changeset for an `EntityTransition` row.

  All fields are required. `version` must be greater than or equal to 1, since version 0 is
  the implicit starting version of a brand-new entity and is never persisted.
  """
  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(transition, attrs) do
    transition
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
    |> validate_number(:version, greater_than_or_equal_to: 1)
  end
end

defmodule StateMachine do
  @moduledoc """
  A `GenServer` that manages the lifecycle of stateful entities with optimistic concurrency
  control, persisting every state transition to a database via Ecto.

  ## State machine

  The order-processing lifecycle is:

      :pending    + :confirm  -> :confirmed
      :confirmed  + :ship     -> :shipped
      :shipped    + :deliver  -> :delivered
      :pending    + :cancel   -> :cancelled
      :confirmed  + :cancel   -> :cancelled

  Any other `{state, event}` pair is an invalid transition.

  ## Versioning

  Every entity carries a monotonically increasing version. A brand-new entity (with no
  persisted history) starts in `:pending` at version `0`. Each successful transition
  increments the version by one and persists the new version alongside the transition, so
  after `n` successful transitions the entity is at version `n`.

  Callers must present the version they expect to operate on. `transition/4` applies its
  checks in a fixed order:

    1. unknown entity (never started in this session) -> `{:error, :not_found}`
    2. version mismatch -> `{:error, {:stale_version, current_version}}`
    3. invalid `{state, event}` pair -> `{:error, :invalid_transition}`
    4. otherwise the transition is persisted and applied

  Because the version check precedes the validity check, a caller presenting a stale version
  always sees `{:error, {:stale_version, current_version}}`, even when the event would also
  have been invalid.

  Since `transition/4` is a `GenServer.call/3`, concurrent callers serialise through the
  server: when many race to apply the same event at the same expected version, exactly one
  succeeds and every other caller observes the now-incremented current version.

  ## In-memory state

  The server keeps `%{entity_id => {current_state, current_version}}`. On restart this map is
  empty, so the next `start/2` call re-hydrates the entity from the database.
  """

  use GenServer

  import Ecto.Query, only: [from: 2]

  @typedoc "A state of the order-processing lifecycle."
  @type state :: :pending | :confirmed | :shipped | :delivered | :cancelled

  @typedoc "An event that may be applied to an entity."
  @type event :: :confirm | :ship | :deliver | :cancel

  @typedoc "The identifier of an entity."
  @type entity_id :: String.t()

  @typedoc "An entity's version number."
  @type version :: non_neg_integer()

  @typedoc "A single recorded transition, as returned by `history/2`."
  @type history_entry :: %{
          event: event(),
          from_state: state(),
          to_state: state(),
          version: pos_integer(),
          inserted_at: DateTime.t()
        }

  @initial_state :pending
  @initial_version 0

  @states [:pending, :confirmed, :shipped, :delivered, :cancelled]
  @events [:confirm, :ship, :deliver, :cancel]

  @transitions %{
    {:pending, :confirm} => :confirmed,
    {:confirmed, :ship} => :shipped,
    {:shipped, :deliver} => :delivered,
    {:pending, :cancel} => :cancelled,
    {:confirmed, :cancel} => :cancelled
  }

  # ── Public API ────────────────────────────────────────────────────────────────────────

  @doc """
  Starts the state machine server.

  ## Options

    * `:repo` — required. The configured `Ecto.Repo` module used for persistence.
    * `:name` — optional. A name to register the process under; any valid `GenServer` name.

  Returns `{:ok, pid}` on success.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    repo = Keyword.fetch!(opts, :repo)
    {name, _rest} = Keyword.pop(opts, :name)

    case name do
      nil -> GenServer.start_link(__MODULE__, %{repo: repo})
      name -> GenServer.start_link(__MODULE__, %{repo: repo}, name: name)
    end
  end

  @doc """
  Loads the latest persisted state and version of `entity_id` into the server session.

  Queries the database for the most recent transition row for the entity and derives the
  current state (its `to_state`) and version. If no row exists, the entity starts in
  `:pending` at version `0`.

  Returns `{:ok, current_state, current_version}`.
  """
  @spec start(GenServer.server(), entity_id()) :: {:ok, state(), version()}
  def start(server, entity_id) do
    GenServer.call(server, {:start, entity_id})
  end

  @doc """
  Returns `{:ok, current_state, current_version}` for an entity previously started in this
  server session, or `{:error, :not_found}` if it has never been started.
  """
  @spec get_state(GenServer.server(), entity_id()) ::
          {:ok, state(), version()} | {:error, :not_found}
  def get_state(server, entity_id) do
    GenServer.call(server, {:get_state, entity_id})
  end

  @doc """
  Attempts to apply `event` to `entity_id`, which the caller expects to be at
  `expected_version`.

  Checks are applied in order:

    1. `{:error, :not_found}` if the entity has not been started in this session;
    2. `{:error, {:stale_version, current_version}}` if `expected_version` differs from the
       entity's current version;
    3. `{:error, :invalid_transition}` if the `{state, event}` pair is not valid;
    4. otherwise the transition is persisted and `{:ok, new_state, new_version}` is returned,
       where `new_version == current_version + 1`.

  Nothing is written to the database unless the transition succeeds. If the database write
  fails, `{:error, {:db_error, reason}}` is returned and the in-memory state is left intact.
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
  Returns `{:ok, list}` with every recorded transition for `entity_id`, in chronological
  (insertion) order.

  Each entry is a map with the keys `:event`, `:from_state`, `:to_state`, `:version` and
  `:inserted_at`.
  """
  @spec history(GenServer.server(), entity_id()) :: {:ok, [history_entry()]}
  def history(server, entity_id) do
    GenServer.call(server, {:history, entity_id})
  end

  # ── GenServer callbacks ───────────────────────────────────────────────────────────────

  @impl GenServer
  @spec init(map()) :: {:ok, map()}
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
      {:ok, {current_state, current_version}} ->
        {:reply, {:ok, current_state, current_version}, state}

      :error ->
        {:reply, {:error, :not_found}, state}
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
      {:error, _reason} = error -> {:reply, error, state}
    end
  end

  def handle_call({:history, entity_id}, _from, state) do
    {:reply, {:ok, load_history(state.repo, entity_id)}, state}
  end

  # ── Internals ─────────────────────────────────────────────────────────────────────────

  @spec fetch_entity(%{optional(entity_id()) => {state(), version()}}, entity_id()) ::
          {:ok, {state(), version()}} | {:error, :not_found}
  defp fetch_entity(entities, entity_id) do
    case Map.fetch(entities, entity_id) do
      {:ok, entity} -> {:ok, entity}
      :error -> {:error, :not_found}
    end
  end

  @spec check_version(version(), version()) :: :ok | {:error, {:stale_version, version()}}
  defp check_version(current_version, current_version), do: :ok
  defp check_version(current_version, _expected), do: {:error, {:stale_version, current_version}}

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
      {to_state, version} -> {to_atom(to_state, @states), version}
    end
  end

  @spec load_history(module(), entity_id()) :: [history_entry()]
  defp load_history(repo, entity_id) do
    query =
      from(t in EntityTransition,
        where: t.entity_id == ^entity_id,
        order_by: [asc: t.id]
      )

    query
    |> repo.all()
    |> Enum.map(fn row ->
      %{
        event: to_atom(row.event, @events),
        from_state: to_atom(row.from_state, @states),
        to_state: to_atom(row.to_state, @states),
        version: row.version,
        inserted_at: row.inserted_at
      }
    end)
  end

  @spec persist(module(), entity_id(), event(), state(), state(), pos_integer()) ::
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

    case repo.insert(changeset) do
      {:ok, _record} -> :ok
      {:error, reason} -> {:error, reason}
    end
  rescue
    exception -> {:error, exception}
  end

  @spec to_atom(String.t(), [atom()]) :: atom()
  defp to_atom(value, allowed) do
    Enum.find(allowed, fn candidate -> Atom.to_string(candidate) == value end) ||
      String.to_atom(value)
  end
end