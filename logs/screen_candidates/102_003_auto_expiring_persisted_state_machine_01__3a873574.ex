defmodule StateMachine.Repo do
  @moduledoc """
  The Ecto repository used by `StateMachine` to persist entity transitions.

  This module is intentionally *bare*: it is not configured and not started here. The host
  application (or the test environment) supplies the configuration — database path, pool,
  sandbox settings — and starts the repo, then injects it into `StateMachine.start_link/1`
  via the `:repo` option.
  """

  use Ecto.Repo, otp_app: :state_machine, adapter: Ecto.Adapters.SQLite3
end

defmodule EntityTransition do
  @moduledoc """
  Ecto schema for a single persisted state transition of an entity.

  Every row is an immutable, append-only record of one `from_state -> to_state` move that was
  caused by `event`. Rows are ordered chronologically by their auto-incrementing `id`, which
  makes the most recent row for an entity the authoritative source of its current state.

  States and events are stored as strings (the serialised form of the corresponding atoms).
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: pos_integer() | nil,
          entity_id: String.t() | nil,
          event: String.t() | nil,
          from_state: String.t() | nil,
          to_state: String.t() | nil,
          inserted_at: DateTime.t() | nil
        }

  @required_fields [:entity_id, :event, :from_state, :to_state, :inserted_at]

  schema "entity_transitions" do
    field(:entity_id, :string)
    field(:event, :string)
    field(:from_state, :string)
    field(:to_state, :string)
    field(:inserted_at, :utc_datetime_usec)
  end

  @doc """
  Builds a changeset for an `EntityTransition` row.

  All fields (`:entity_id`, `:event`, `:from_state`, `:to_state` and `:inserted_at`) are
  required, mirroring the `NOT NULL` constraints on the table.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = transition, attrs) do
    transition
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
  end
end

defmodule Repo.Migrations.CreateEntityTransitions do
  @moduledoc """
  Migration creating the `entity_transitions` table plus an index on `entity_id`.

  Written with plain `Ecto.Migration` primitives only, so it is valid for SQLite as well as
  for other adapters.
  """

  use Ecto.Migration

  @doc """
  Creates the `entity_transitions` table and the `entity_id` index.
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
  A `GenServer` that manages the lifecycle of stateful entities (orders) and persists every
  state transition to the database via an Ecto repo.

  ## Lifecycle

  States: `:pending`, `:confirmed`, `:shipped`, `:delivered`, `:cancelled`.

  Valid transitions:

      :pending   + :confirm -> :confirmed
      :confirmed + :ship    -> :shipped
      :shipped   + :deliver -> :delivered
      :pending   + :cancel  -> :cancelled
      :confirmed + :cancel  -> :cancelled
      :pending   + :expire  -> :cancelled

  Any other `{state, event}` pair is invalid and yields `{:error, :invalid_transition}` without
  touching the database.

  ## Automatic expiry

  When started with a `:pending_ttl_ms` option, every entity that is `:pending` at the moment
  `start/2` runs gets an expiry check scheduled `pending_ttl_ms` milliseconds later. The check
  runs *inside* the server process, so it serialises against manual transitions: if the entity
  is still `:pending` it is transitioned to `:cancelled` with the `:expire` event (persisted
  exactly like a manual transition); if it has moved on in the meantime the check is a no-op
  and writes nothing. Omitting the option (or passing `nil`) disables automatic expiry.

  ## Persistence

  The server keeps an in-memory map of `%{entity_id => current_state}`. It is a cache only —
  the database is the source of truth. After a restart the map is empty, so the next `start/2`
  re-hydrates the entity from the most recent persisted `to_state`, including entities that
  were automatically expired.
  """

  use GenServer

  import Ecto.Query, only: [from: 2]

  @type entity_id :: String.t()
  @type state :: :pending | :confirmed | :shipped | :delivered | :cancelled
  @type event :: :confirm | :ship | :deliver | :cancel | :expire
  @type server :: GenServer.server()

  @type history_entry :: %{
          event: String.t(),
          from_state: String.t(),
          to_state: String.t(),
          inserted_at: DateTime.t()
        }

  @states [:pending, :confirmed, :shipped, :delivered, :cancelled]

  @transitions %{
    {:pending, :confirm} => :confirmed,
    {:confirmed, :ship} => :shipped,
    {:shipped, :deliver} => :delivered,
    {:pending, :cancel} => :cancelled,
    {:confirmed, :cancel} => :cancelled,
    {:pending, :expire} => :cancelled
  }

  # ----------------------------------------------------------------------------------------
  # Public API
  # ----------------------------------------------------------------------------------------

  @doc """
  Starts the state machine server.

  Options:

    * `:repo` — required, the configured Ecto repo module used for persistence.
    * `:pending_ttl_ms` — optional non-negative integer. When given, entities found in the
      `:pending` state by `start/2` are automatically expired (`:pending -> :cancelled`) after
      this many milliseconds. When absent or `nil`, automatic expiry is disabled.
    * `:name` — optional process registration name, forwarded to `GenServer.start_link/3`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name], else: []

    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  @doc """
  Loads (or seeds) an entity and returns its current state as `{:ok, state}`.

  The most recent persisted `to_state` for `entity_id` is used; if the entity has no persisted
  history it starts in `:pending`. When the entity is `:pending` and a `:pending_ttl_ms` was
  configured, an automatic expiry check is scheduled at this point.
  """
  @spec start(server(), entity_id()) :: {:ok, state()}
  def start(server, entity_id) when is_binary(entity_id) do
    GenServer.call(server, {:start, entity_id})
  end

  @doc """
  Returns `{:ok, state}` for an entity previously loaded with `start/2`.

  Returns `{:error, :not_found}` when the entity has not been started in this server session.
  """
  @spec get_state(server(), entity_id()) :: {:ok, state()} | {:error, :not_found}
  def get_state(server, entity_id) when is_binary(entity_id) do
    GenServer.call(server, {:get_state, entity_id})
  end

  @doc """
  Applies `event` to `entity_id`.

  Returns `{:ok, new_state}` when the transition is valid and was persisted successfully.
  Returns `{:error, :invalid_transition}` when the `{state, event}` pair is not allowed (no
  database write happens), `{:error, :not_found}` when the entity was never started, and
  `{:error, {:db_error, reason}}` when persistence fails — in which case the in-memory state
  is left untouched.

  Implemented as a `call`, so concurrent callers serialise through the server process.
  """
  @spec transition(server(), entity_id(), event()) ::
          {:ok, state()}
          | {:error, :invalid_transition}
          | {:error, :not_found}
          | {:error, {:db_error, term()}}
  def transition(server, entity_id, event) when is_binary(entity_id) and is_atom(event) do
    GenServer.call(server, {:transition, entity_id, event})
  end

  @doc """
  Returns `{:ok, list}` with every persisted transition for `entity_id`, oldest first.

  Each entry is a map with the keys `:event`, `:from_state`, `:to_state` (strings, as stored)
  and `:inserted_at` (a `DateTime`).
  """
  @spec history(server(), entity_id()) :: {:ok, [history_entry()]}
  def history(server, entity_id) when is_binary(entity_id) do
    GenServer.call(server, {:history, entity_id})
  end

  # ----------------------------------------------------------------------------------------
  # GenServer callbacks
  # ----------------------------------------------------------------------------------------

  @impl GenServer
  def init(opts) do
    repo = Keyword.fetch!(opts, :repo)
    ttl = Keyword.get(opts, :pending_ttl_ms)

    if not (is_nil(ttl) or (is_integer(ttl) and ttl >= 0)) do
      {:stop, {:invalid_option, :pending_ttl_ms}}
    else
      {:ok, %{repo: repo, pending_ttl_ms: ttl, entities: %{}, timers: %{}}}
    end
  end

  @impl GenServer
  def handle_call({:start, entity_id}, _from, state) do
    current = load_state(state.repo, entity_id)

    state =
      state
      |> put_in([:entities, entity_id], current)
      |> maybe_schedule_expiry(entity_id, current)

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
        case apply_event(state, entity_id, current, event) do
          {:ok, new_state, next} -> {:reply, {:ok, next}, new_state}
          {:error, reason} -> {:reply, {:error, reason}, state}
        end
    end
  end

  def handle_call({:history, entity_id}, _from, state) do
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

    {:reply, {:ok, state.repo.all(query)}, state}
  end

  @impl GenServer
  def handle_info({:expire_check, entity_id}, state) do
    state = %{state | timers: Map.delete(state.timers, entity_id)}

    case Map.fetch(state.entities, entity_id) do
      {:ok, :pending} ->
        case apply_event(state, entity_id, :pending, :expire) do
          {:ok, new_state, _next} -> {:noreply, new_state}
          {:error, _reason} -> {:noreply, state}
        end

      _other ->
        {:noreply, state}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  # ----------------------------------------------------------------------------------------
  # Internals
  # ----------------------------------------------------------------------------------------

  @spec apply_event(map(), entity_id(), state(), event()) ::
          {:ok, map(), state()} | {:error, :invalid_transition | {:db_error, term()}}
  defp apply_event(state, entity_id, current, event) do
    case Map.fetch(@transitions, {current, event}) do
      :error ->
        {:error, :invalid_transition}

      {:ok, next} ->
        case persist(state.repo, entity_id, event, current, next) do
          {:ok, _row} ->
            {:ok, put_in(state, [:entities, entity_id], next), next}

          {:error, reason} ->
            {:error, {:db_error, reason}}
        end
    end
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

  @spec load_state(module(), entity_id()) :: state()
  defp load_state(repo, entity_id) do
    query =
      from(t in EntityTransition,
        where: t.entity_id == ^entity_id,
        order_by: [desc: t.id],
        limit: 1,
        select: t.to_state
      )

    case repo.one(query) do
      nil -> :pending
      to_state -> parse_state(to_state)
    end
  end

  @spec parse_state(String.t()) :: state()
  defp parse_state(to_state) do
    Enum.find(@states, :pending, fn known -> Atom.to_string(known) == to_state end)
  end

  @spec maybe_schedule_expiry(map(), entity_id(), state()) :: map()
  defp maybe_schedule_expiry(%{pending_ttl_ms: nil} = state, _entity_id, _current), do: state

  defp maybe_schedule_expiry(state, entity_id, :pending) do
    state = cancel_timer(state, entity_id)
    timer = Process.send_after(self(), {:expire_check, entity_id}, state.pending_ttl_ms)

    %{state | timers: Map.put(state.timers, entity_id, timer)}
  end

  defp maybe_schedule_expiry(state, entity_id, _current), do: cancel_timer(state, entity_id)

  @spec cancel_timer(map(), entity_id()) :: map()
  defp cancel_timer(state, entity_id) do
    case Map.pop(state.timers, entity_id) do
      {nil, _timers} ->
        state

      {timer, timers} ->
        Process.cancel_timer(timer)
        %{state | timers: timers}
    end
  end
end