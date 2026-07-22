# Task: implement `handle_call/3` for `StateMachine`

The module below is a complete `StateMachine` GenServer (plus its `EntityTransition`
Ecto schema and migration). Everything is implemented **except** the `handle_call/3`
callback clauses, which have been replaced with `# TODO`.

Implement `handle_call/3`. It needs four clauses, one per public API message, and each
one must use the private helpers that are already present in the module.

**1. `{:start, entity_id}`** — hydrate the entity from the database. Use
`load_latest_state/2` with the repo held in the server state to fetch the entity's
most recent `to_state` (this helper already falls back to `:pending` when no rows
exist). Cache the resulting state under `entity_id` in the `:entities` map and reply
`{:ok, current_state}`.

**2. `{:get_state, entity_id}`** — a pure in-memory lookup with no database access.
Reply `{:ok, current_state}` if `entity_id` is present in the `:entities` map, or
`{:error, :not_found}` if it is not. The state is unchanged.

**3. `{:transition, entity_id, event}`** — the serialised transition. Chain the three
helpers, short-circuiting on the first failure:

  - `entity_lookup/2` — returns `{:found, current_state}` or `{:not_found}`.
  - `resolve_transition/2` — returns `{:valid, next_state}` or `{:invalid}`.
  - `persist/5` — writes the row (repo, entity_id, event, from_state, to_state) and
    returns `{:persisted, record}` or `{:db_error, reason}`.

Only when all three succeed do you update the in-memory map (`entity_id => next_state`)
and reply `{:ok, next_state}`. Otherwise the in-memory state must be left **completely
untouched** and the reply is `{:error, :not_found}`, `{:error, :invalid_transition}`, or
`{:error, {:db_error, reason}}` respectively. Note in particular that a failed database
write must not advance the cached state, and an invalid transition must not write
anything to the database.

**4. `{:history, entity_id}`** — query `EntityTransition` for every row whose
`entity_id` matches, ordered ascending by `inserted_at`, and run it through the repo in
the server state. Map each row to a plain map with keys `:event`, `:from_state`,
`:to_state` and `:inserted_at`, converting the three string columns back to atoms with
`String.to_existing_atom/1` and passing `inserted_at` through as-is. Reply
`{:ok, history}`. Wrap the query and mapping in a `try/rescue` so that a raising repo
yields `{:error, Exception.message(e)}` instead of crashing the server. The state is
unchanged.

All four clauses reply synchronously and return the (possibly updated) server state,
which has the shape `%{repo: repo_module, entities: %{entity_id => state_atom}}`.

```elixir
defmodule Repo.Migrations.CreateEntityTransitions do
  use Ecto.Migration

  def change do
    create table(:entity_transitions) do
      add(:entity_id, :string, null: false)
      add(:event, :string, null: false)
      add(:from_state, :string, null: false)
      add(:to_state, :string, null: false)
      add(:inserted_at, :utc_datetime_usec, null: false)
    end

    create(index(:entity_transitions, [:entity_id]))
    create(index(:entity_transitions, [:entity_id, :inserted_at]))
  end
end

defmodule EntityTransition do
  use Ecto.Schema
  import Ecto.Changeset

  @moduledoc """
  Persisted record of a single state-machine transition for one entity.

  Fields
  ------
  entity_id   – domain ID of the tracked entity
  event       – the triggering event atom serialised as a string ("confirm", …)
  from_state  – state before the transition ("pending", …)
  to_state    – state after the transition ("confirmed", …)
  inserted_at – microsecond-precision UTC timestamp, set by the repo on insert
  """

  # Suppress updated_at; we only need a single insertion timestamp.
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "entity_transitions" do
    field(:entity_id, :string)
    field(:event, :string)
    field(:from_state, :string)
    field(:to_state, :string)

    timestamps()
  end

  @required [:entity_id, :event, :from_state, :to_state]

  @doc "Validates and wraps insertion attrs in a changeset."
  def changeset(transition \\ %__MODULE__{}, attrs) do
    transition
    |> cast(attrs, @required)
    |> validate_required(@required)
    |> validate_length(:entity_id, min: 1)
  end
end

defmodule StateMachine do
  use GenServer
  require Logger

  import Ecto.Query, only: [from: 2]

  @moduledoc """
  GenServer that manages the in-memory lifecycle state of entities and
  durably persists every valid transition to an Ecto-backed database.

  ## State machine

      :pending    + :confirm  → :confirmed
      :confirmed  + :ship     → :shipped
      :shipped    + :deliver  → :delivered
      :pending    + :cancel   → :cancelled
      :confirmed  + :cancel   → :cancelled

  Any other (state, event) pair is rejected as `:invalid_transition`.

  ## Example

      {:ok, pid} = StateMachine.start_link(repo: MyRepo, name: :orders)

      {:ok, :pending}   = StateMachine.start(pid, "order-1")
      {:ok, :confirmed} = StateMachine.transition(pid, "order-1", :confirm)
      {:ok, :shipped}   = StateMachine.transition(pid, "order-1", :ship)
      {:ok, history}    = StateMachine.history(pid, "order-1")
  """

  # ---------------------------------------------------------------------------
  # Transition table — pure data, lookup is O(1) map fetch
  # ---------------------------------------------------------------------------

  @transitions %{
    {:pending, :confirm} => :confirmed,
    {:confirmed, :ship} => :shipped,
    {:shipped, :deliver} => :delivered,
    {:pending, :cancel} => :cancelled,
    {:confirmed, :cancel} => :cancelled
  }

  # All valid state atoms must exist at compile time for String.to_existing_atom/1
  # to be safe when deserialising DB rows.
  @states [:pending, :confirmed, :shipped, :delivered, :cancelled]
  @initial_state :pending

  # Ensure the compiler keeps the atoms alive.
  def __states__, do: @states

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the GenServer.

  Options
  - `:repo`  (required) – Ecto repo module, e.g. `MyApp.Repo`
  - `:name`  (optional) – forwarded to `GenServer.start_link/3`
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name_opts, server_opts} =
      case Keyword.pop(opts, :name) do
        {nil, rest} -> {[], rest}
        {name, rest} -> {[name: name], rest}
      end

    GenServer.start_link(__MODULE__, server_opts, name_opts)
  end

  @doc """
  Loads the latest persisted state for `entity_id` from the DB and caches it.
  Falls back to `:pending` when no record exists yet.
  Returns `{:ok, current_state}`.
  """
  @spec start(GenServer.server(), String.t()) :: {:ok, atom()}
  def start(server, entity_id),
    do: GenServer.call(server, {:start, entity_id})

  @doc """
  Returns `{:ok, current_state}` for a previously started entity, or
  `{:error, :not_found}` if the entity was never started in this session.
  """
  @spec get_state(GenServer.server(), String.t()) ::
          {:ok, atom()} | {:error, :not_found}
  def get_state(server, entity_id),
    do: GenServer.call(server, {:get_state, entity_id})

  @doc """
  Attempts to apply `event` to `entity_id`.

  - `{:ok, new_state}`              – transition valid; DB write succeeded.
  - `{:error, :invalid_transition}` – no matching (state, event) in the table; DB unchanged.
  - `{:error, :not_found}`          – entity not started in this session.
  - `{:error, {:db_error, reason}}` – Ecto write failed; in-memory state unchanged.
  """
  @spec transition(GenServer.server(), String.t(), atom()) ::
          {:ok, atom()}
          | {:error, :invalid_transition}
          | {:error, :not_found}
          | {:error, {:db_error, any()}}
  def transition(server, entity_id, event),
    do: GenServer.call(server, {:transition, entity_id, event})

  @doc """
  Returns `{:ok, list}` of every recorded transition for `entity_id` in
  chronological order. Each entry is:

      %{event: :confirm, from_state: :pending, to_state: :confirmed, inserted_at: ~U[…]}
  """
  @spec history(GenServer.server(), String.t()) :: {:ok, [map()]} | {:error, any()}
  def history(server, entity_id),
    do: GenServer.call(server, {:history, entity_id})

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(opts) do
    repo = Keyword.fetch!(opts, :repo)
    # in-memory map: %{ entity_id => current_state_atom }
    {:ok, %{repo: repo, entities: %{}}}
  end

  def handle_call({:start, entity_id}, _from, state) do
    # TODO
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Fetches the most recent to_state for entity_id from the DB and converts
  # it from a string back to an atom. Returns @initial_state when no rows exist.
  #
  # Note: we deliberately avoid a `select:` clause and load full
  # %EntityTransition{} structs — pattern-matching on the whole struct keeps the
  # query portable across any injected repo implementation.
  @spec load_latest_state(module(), String.t()) :: atom()
  defp load_latest_state(repo, entity_id) do
    query =
      from(t in EntityTransition,
        where: t.entity_id == ^entity_id,
        order_by: [desc: t.inserted_at],
        limit: 1
      )

    case repo.one(query) do
      nil -> @initial_state
      record -> String.to_existing_atom(record.to_state)
    end
  end

  @spec entity_lookup(map(), String.t()) :: {:found, atom()} | {:not_found}
  defp entity_lookup(entities, entity_id) do
    case Map.fetch(entities, entity_id) do
      {:ok, state} -> {:found, state}
      :error -> {:not_found}
    end
  end

  @spec resolve_transition(atom(), atom()) :: {:valid, atom()} | {:invalid}
  defp resolve_transition(current_state, event) do
    case Map.fetch(@transitions, {current_state, event}) do
      {:ok, next} -> {:valid, next}
      :error -> {:invalid}
    end
  end

  # Inserts one row. Returns {:persisted, record} or {:db_error, reason}.
  # The caller must NOT update in-memory state on anything other than :persisted.
  @spec persist(module(), String.t(), atom(), atom(), atom()) ::
          {:persisted, EntityTransition.t()} | {:db_error, any()}
  defp persist(repo, entity_id, event, from_state, to_state) do
    attrs = %{
      entity_id: entity_id,
      event: Atom.to_string(event),
      from_state: Atom.to_string(from_state),
      to_state: Atom.to_string(to_state)
    }

    changeset = EntityTransition.changeset(attrs)

    try do
      case repo.insert(changeset) do
        {:ok, record} -> {:persisted, record}
        {:error, changeset} -> {:db_error, changeset}
      end
    rescue
      e ->
        Logger.error("[StateMachine] DB write failed: #{Exception.message(e)}")
        {:db_error, Exception.message(e)}
    end
  end
end
```