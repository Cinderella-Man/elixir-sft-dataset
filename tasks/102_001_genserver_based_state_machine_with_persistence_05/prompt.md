# Implement the missing file

Below is the complete specification of a task, followed by its working,
fully tested multi-file solution — except that the entire content of
`lib/entity_transition.ex` has been blanked to `# TODO`. Write that file so the whole
bundle passes the task's full test suite again. Change nothing else —
every other file must stay exactly as shown.

## The task

Write me an Elixir GenServer module called `StateMachine` that manages the lifecycle of
stateful entities, persists every state transition to a database, and recovers state on restart.

## State Machine Definition

Use the following order-processing lifecycle:

States: `:pending`, `:confirmed`, `:shipped`, `:delivered`, `:cancelled`

Valid transitions (current_state + event → next_state):
  - :pending    + :confirm  → :confirmed
  - :confirmed  + :ship     → :shipped
  - :shipped    + :deliver  → :delivered
  - :pending    + :cancel   → :cancelled
  - :confirmed  + :cancel   → :cancelled

Any other (state, event) combination is invalid.

## Public API

- `StateMachine.start_link(opts)` — starts the GenServer. Accepts a `:repo` option (an Ecto
  repo module) and a `:name` option for process registration.

- `StateMachine.start(server, entity_id)` — loads the latest persisted state for the given
  entity from the database. If no record exists, the entity starts in the `:pending` state.
  Returns `{:ok, current_state}`.

- `StateMachine.get_state(server, entity_id)` — returns `{:ok, current_state}` for a
  previously started entity, or `{:error, :not_found}` if the entity has never been started
  in this server session.

- `StateMachine.transition(server, entity_id, event)` — attempts to transition the entity.
  - If valid: persists the new state + the event to the DB, updates in-memory state,
    returns `{:ok, new_state}`.
  - If the (state, event) pair is not a valid transition: returns
    `{:error, :invalid_transition}` and writes nothing to the DB.
  - If the entity has not been started yet: returns `{:error, :not_found}`.

- `StateMachine.history(server, entity_id)` — returns `{:ok, list}` where list is every
  recorded transition for that entity in chronological order. Each entry is a map with keys
  `:event`, `:from_state`, `:to_state`, and `:inserted_at`.

## Persistence

Use Ecto. Assume the caller supplies a configured Ecto repo. The relevant table is
`entity_transitions` with these columns:

  - `id` — bigint primary key (auto-increment)
  - `entity_id` — string, non-null, indexed
  - `event` — string (the atom serialised as a string), non-null
  - `from_state` — string, non-null
  - `to_state` — string, non-null
  - `inserted_at` — utc_datetime_usec, non-null

Provide:
  1. The `EntityTransition` Ecto schema module.
  2. An Ecto migration file that creates the table.
  3. The `StateMachine` GenServer module.

The GenServer must keep an in-memory map of `%{entity_id => current_state}` as its state.
On `start/2`, it queries the DB for the most recent `to_state` for that entity. On restart,
the in-memory map is empty, so the next `start/2` call re-hydrates from the DB.

## Concurrency

`transition/3` must be implemented as a `call` (not a cast) so that concurrent callers
serialize through the GenServer and there are no race conditions. The in-memory update and
the DB write must both happen inside the `handle_call` callback before the reply is sent.

## Error Handling

- DB write failures in `transition/3` should return `{:error, {:db_error, reason}}` and
  must NOT update the in-memory state.
- Use `Ecto.Multi` or a plain `Repo.insert` wrapped in a try/rescue; your choice.

## Deliverables

Give me all three modules/files in a single code block or clearly separated blocks. Use only
Ecto (plus its adapters) as the external dependency — no additional libraries.
## Additional interface contract

- The test environment provides a real, already-configured SQLite Ecto repo and injects it into your GenServer via the `repo:` option — do NOT define a repo module or any repo configuration. Your migration file must be at a `priv/repo/migrations/<name>.exs` path: it is executed against that repo before the tests run, so the schema/migration must be valid for SQLite (plain `Ecto.Migration`, no database-specific SQL).

## The bundle with `lib/entity_transition.ex` missing

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

# TODO

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

  # :start — hydrate from DB (or seed with :pending), cache in map
  @impl true
  def handle_call({:start, entity_id}, _from, state) do
    current = load_latest_state(state.repo, entity_id)
    new_entities = Map.put(state.entities, entity_id, current)
    {:reply, {:ok, current}, %{state | entities: new_entities}}
  end

  # :get_state — pure in-memory lookup
  @impl true
  def handle_call({:get_state, entity_id}, _from, state) do
    reply =
      case Map.fetch(state.entities, entity_id) do
        {:ok, current} -> {:ok, current}
        :error -> {:error, :not_found}
      end

    {:reply, reply, state}
  end

  # :transition — serialised call; in-memory update only after DB write succeeds
  @impl true
  def handle_call({:transition, entity_id, event}, _from, state) do
    with {:found, current} <- entity_lookup(state.entities, entity_id),
         {:valid, next_state} <- resolve_transition(current, event),
         {:persisted, _record} <- persist(state.repo, entity_id, event, current, next_state) do
      new_entities = Map.put(state.entities, entity_id, next_state)
      {:reply, {:ok, next_state}, %{state | entities: new_entities}}
    else
      {:not_found} -> {:reply, {:error, :not_found}, state}
      {:invalid} -> {:reply, {:error, :invalid_transition}, state}
      {:db_error, reason} -> {:reply, {:error, {:db_error, reason}}, state}
    end
  end

  # :history — fetch rows from DB, deserialise string columns back to atoms
  @impl true
  def handle_call({:history, entity_id}, _from, state) do
    query =
      from(t in EntityTransition,
        where: t.entity_id == ^entity_id,
        order_by: [asc: t.inserted_at]
      )

    result =
      try do
        rows = state.repo.all(query)

        history =
          Enum.map(rows, fn row ->
            %{
              event: String.to_existing_atom(row.event),
              from_state: String.to_existing_atom(row.from_state),
              to_state: String.to_existing_atom(row.to_state),
              inserted_at: row.inserted_at
            }
          end)

        {:ok, history}
      rescue
        e -> {:error, Exception.message(e)}
      end

    {:reply, result, state}
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

Give me only the complete content of `lib/entity_transition.ex` — that one file, nothing
else.
