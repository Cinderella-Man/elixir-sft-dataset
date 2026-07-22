defmodule EntityTransition do
  @moduledoc """
  Ecto schema for a single persisted state-machine transition.

  Every row records the entity that transitioned, the event that caused it, the state the
  entity was in before the event, the state it moved to, and when the row was inserted.
  Rows are inserted in chronological order, so ordering by `id` yields the entity history.
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

  @fields [:entity_id, :event, :from_state, :to_state, :inserted_at]

  schema "entity_transitions" do
    field(:entity_id, :string)
    field(:event, :string)
    field(:from_state, :string)
    field(:to_state, :string)
    field(:inserted_at, :utc_datetime_usec)
  end

  @doc """
  Builds a changeset for a transition row.

  All of `:entity_id`, `:event`, `:from_state`, `:to_state` and `:inserted_at` are required.
  """
  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(transition \\ %__MODULE__{}, attrs) do
    transition
    |> cast(attrs, @fields)
    |> validate_required(@fields)
  end
end

defmodule StateMachine do
  @moduledoc """
  A `GenServer` that manages the lifecycle of order-like stateful entities.

  ## Lifecycle

  States are `:pending`, `:confirmed`, `:shipped`, `:delivered` and `:cancelled`. The valid
  transitions are:

    * `:pending` + `:confirm` -> `:confirmed`
    * `:confirmed` + `:ship` -> `:shipped`
    * `:shipped` + `:deliver` -> `:delivered`
    * `:pending` + `:cancel` -> `:cancelled`
    * `:confirmed` + `:cancel` -> `:cancelled`
    * `:pending` + `:expire` -> `:cancelled`

  Any other `{state, event}` pair is invalid and is rejected with `{:error,
  :invalid_transition}` without touching the database.

  ## Persistence

  Every applied transition (manual or automatic) is written to the `entity_transitions` table
  through the `Ecto.Repo` module given as the `:repo` option. The GenServer only keeps a
  `%{entity_id => current_state}` map in memory; after a restart that map is empty and the next
  `start/2` call re-hydrates the entity from its most recently persisted `to_state`.

  ## Automatic expiry

  When started with a non-negative `:pending_ttl_ms` option, `start/2` schedules an expiry check
  for any entity that is currently `:pending`. When the check fires inside the server process,
  an entity that is *still* `:pending` is transitioned to `:cancelled` with the `:expire` event
  and that transition is persisted exactly like a manual one. If the entity has meanwhile left
  the `:pending` state, the check is a silent no-op and writes nothing.

  Because both `transition/3` and the expiry check run inside the server process, manual and
  automatic transitions serialize against each other: whichever runs first wins and the other
  becomes a no-op or an `:invalid_transition`.
  """

  use GenServer

  import Ecto.Query, only: [from: 2]

  @typedoc "A state of the order lifecycle."
  @type state :: :pending | :confirmed | :shipped | :delivered | :cancelled

  @typedoc "An event that may drive a transition."
  @type event :: :confirm | :ship | :deliver | :cancel | :expire

  @typedoc "A single recorded transition, as returned by `history/2`."
  @type history_entry :: %{
          event: String.t(),
          from_state: String.t(),
          to_state: String.t(),
          inserted_at: DateTime.t()
        }

  @initial_state :pending

  @transitions %{
    {:pending, :confirm} => :confirmed,
    {:confirmed, :ship} => :shipped,
    {:shipped, :deliver} => :delivered,
    {:pending, :cancel} => :cancelled,
    {:confirmed, :cancel} => :cancelled,
    {:pending, :expire} => :cancelled
  }

  defmodule Server do
    @moduledoc false

    @typedoc false
    @type t :: %__MODULE__{
            repo: module(),
            pending_ttl_ms: non_neg_integer() | nil,
            entities: %{optional(String.t()) => StateMachine.state()}
          }

    defstruct repo: nil, pending_ttl_ms: nil, entities: %{}
  end

  # ------------------------------------------------------------------
  # Public API
  # ------------------------------------------------------------------

  @doc """
  Starts the state machine server.

  ## Options

    * `:repo` — required, the `Ecto.Repo` module used for persistence.
    * `:pending_ttl_ms` — optional non-negative integer. When given, entities found in the
      `:pending` state by `start/2` are automatically expired (`:pending` -> `:cancelled`)
      after this many milliseconds. Omit it (or pass `nil`) to disable automatic expiry.
    * `:name` — optional process name registration, forwarded to `GenServer.start_link/3`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name], else: []

    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  @doc """
  Loads (or seeds) an entity into the server.

  Reads the entity's most recently persisted `to_state` from the database. When no transition
  has ever been recorded, the entity starts in `:pending`. If a `:pending_ttl_ms` was configured
  and the resulting state is `:pending`, an automatic expiry check is scheduled for the entity.

  Always returns `{:ok, current_state}`.
  """
  @spec start(GenServer.server(), String.t()) :: {:ok, state()}
  def start(server, entity_id) when is_binary(entity_id) do
    GenServer.call(server, {:start, entity_id})
  end

  @doc """
  Returns `{:ok, current_state}` for an entity previously loaded with `start/2`.

  Returns `{:error, :not_found}` when the entity has not been started in this server session.
  """
  @spec get_state(GenServer.server(), String.t()) :: {:ok, state()} | {:error, :not_found}
  def get_state(server, entity_id) when is_binary(entity_id) do
    GenServer.call(server, {:get_state, entity_id})
  end

  @doc """
  Applies `event` to the entity.

  On a valid `{state, event}` pair the new state is persisted and kept in memory, and
  `{:ok, new_state}` is returned. An invalid pair returns `{:error, :invalid_transition}` and
  writes nothing. An entity that has not been started returns `{:error, :not_found}`. A database
  write failure returns `{:error, {:db_error, reason}}` and leaves the in-memory state untouched.
  """
  @spec transition(GenServer.server(), String.t(), event()) ::
          {:ok, state()}
          | {:error, :not_found}
          | {:error, :invalid_transition}
          | {:error, {:db_error, term()}}
  def transition(server, entity_id, event) when is_binary(entity_id) and is_atom(event) do
    GenServer.call(server, {:transition, entity_id, event})
  end

  @doc """
  Returns `{:ok, transitions}` with every recorded transition for `entity_id`.

  Transitions are returned in chronological (insertion) order. Each entry is a map with the
  keys `:event`, `:from_state`, `:to_state` and `:inserted_at`.
  """
  @spec history(GenServer.server(), String.t()) :: {:ok, [history_entry()]}
  def history(server, entity_id) when is_binary(entity_id) do
    GenServer.call(server, {:history, entity_id})
  end

  # ------------------------------------------------------------------
  # GenServer callbacks
  # ------------------------------------------------------------------

  @impl GenServer
  def init(opts) do
    repo = Keyword.fetch!(opts, :repo)
    ttl = Keyword.get(opts, :pending_ttl_ms)

    unless is_nil(ttl) or (is_integer(ttl) and ttl >= 0) do
      raise ArgumentError,
            ":pending_ttl_ms must be a non-negative integer or nil, got: #{inspect(ttl)}"
    end

    {:ok, %Server{repo: repo, pending_ttl_ms: ttl, entities: %{}}}
  end

  @impl GenServer
  def handle_call({:start, entity_id}, _from, %Server{} = server) do
    current = load_state(server.repo, entity_id)
    server = %Server{server | entities: Map.put(server.entities, entity_id, current)}

    maybe_schedule_expiry(server, entity_id, current)

    {:reply, {:ok, current}, server}
  end

  def handle_call({:get_state, entity_id}, _from, %Server{} = server) do
    case Map.fetch(server.entities, entity_id) do
      {:ok, current} -> {:reply, {:ok, current}, server}
      :error -> {:reply, {:error, :not_found}, server}
    end
  end

  def handle_call({:transition, entity_id, event}, _from, %Server{} = server) do
    case Map.fetch(server.entities, entity_id) do
      :error ->
        {:reply, {:error, :not_found}, server}

      {:ok, current} ->
        case apply_event(server, entity_id, current, event) do
          {:ok, next, server} -> {:reply, {:ok, next}, server}
          {:error, reason} -> {:reply, {:error, reason}, server}
        end
    end
  end

  def handle_call({:history, entity_id}, _from, %Server{} = server) do
    {:reply, {:ok, load_history(server.repo, entity_id)}, server}
  end

  @impl GenServer
  def handle_info({:expire_check, entity_id}, %Server{} = server) do
    case Map.fetch(server.entities, entity_id) do
      {:ok, @initial_state} ->
        case apply_event(server, entity_id, @initial_state, :expire) do
          {:ok, _next, server} -> {:noreply, server}
          {:error, _reason} -> {:noreply, server}
        end

      _other ->
        {:noreply, server}
    end
  end

  def handle_info(_message, %Server{} = server), do: {:noreply, server}

  # ------------------------------------------------------------------
  # Internals
  # ------------------------------------------------------------------

  @spec apply_event(Server.t(), String.t(), state(), event()) ::
          {:ok, state(), Server.t()} | {:error, :invalid_transition | {:db_error, term()}}
  defp apply_event(%Server{} = server, entity_id, current, event) do
    case Map.fetch(@transitions, {current, event}) do
      :error ->
        {:error, :invalid_transition}

      {:ok, next} ->
        case persist(server.repo, entity_id, event, current, next) do
          {:ok, _row} ->
            entities = Map.put(server.entities, entity_id, next)
            {:ok, next, %Server{server | entities: entities}}

          {:error, reason} ->
            {:error, {:db_error, reason}}
        end
    end
  end

  @spec persist(module(), String.t(), event(), state(), state()) ::
          {:ok, EntityTransition.t()} | {:error, term()}
  defp persist(repo, entity_id, event, from_state, to_state) do
    attrs = %{
      entity_id: entity_id,
      event: Atom.to_string(event),
      from_state: Atom.to_string(from_state),
      to_state: Atom.to_string(to_state),
      inserted_at: DateTime.utc_now()
    }

    attrs
    |> EntityTransition.changeset()
    |> repo.insert()
  rescue
    exception -> {:error, exception}
  end

  @spec load_state(module(), String.t()) :: state()
  defp load_state(repo, entity_id) do
    query =
      from(t in EntityTransition,
        where: t.entity_id == ^entity_id,
        order_by: [desc: t.id],
        limit: 1,
        select: t.to_state
      )

    case repo.one(query) do
      nil -> @initial_state
      to_state -> to_atom_state(to_state)
    end
  end

  @spec load_history(module(), String.t()) :: [history_entry()]
  defp load_history(repo, entity_id) do
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

    repo.all(query)
  end

  @spec maybe_schedule_expiry(Server.t(), String.t(), state()) :: :ok
  defp maybe_schedule_expiry(%Server{pending_ttl_ms: ttl}, entity_id, @initial_state)
       when is_integer(ttl) and ttl >= 0 do
    Process.send_after(self(), {:expire_check, entity_id}, ttl)
    :ok
  end

  defp maybe_schedule_expiry(%Server{}, _entity_id, _state), do: :ok

  @spec to_atom_state(String.t()) :: state()
  defp to_atom_state("pending"), do: :pending
  defp to_atom_state("confirmed"), do: :confirmed
  defp to_atom_state("shipped"), do: :shipped
  defp to_atom_state("delivered"), do: :delivered
  defp to_atom_state("cancelled"), do: :cancelled
end