# One test is missing its body

Module plus harness below; a single `test` body was replaced with
`# TODO`. Reconstruct it from its name and the surrounding suite so the
harness passes for a correct implementation of the module. Touch nothing
else.

## Module under test

```elixir
<file path="priv/repo/migrations/YYYYMMDDHHMMSS_create_entity_transitions.exs">
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
</file>

<file path="lib/entity_transition.ex">
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
</file>

<file path="lib/state_machine.ex">
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
</file>
```

## Test harness — implement the `# TODO` test

```elixir
defmodule StateMachineTest.FailingInsertRepo do
  @moduledoc """
  Repo facade used to exercise the DB-write-failure branch.

  Reads (`all/1,2`, `one/1,2`) are served by the real repo, so entity
  hydration and history still work. Writes fail the way Ecto itself fails a
  write: `insert/1,2` returns `{:error, changeset}` with an invalid changeset
  carrying `action: :insert`, `insert!/1,2` raises
  `Ecto.InvalidChangesetError`, and `transaction/1,2` over an `Ecto.Multi`
  reports the failing insert operation as `{:error, name, changeset, %{}}`.
  A `transaction/1,2` given a function runs against the real repo, so a
  function that calls back into this module still observes the failing write
  and `rollback/1` behaves normally.
  """

  def all(queryable), do: StateMachine.Repo.all(queryable)
  def all(queryable, opts), do: StateMachine.Repo.all(queryable, opts)

  def one(queryable), do: StateMachine.Repo.one(queryable)
  def one(queryable, opts), do: StateMachine.Repo.one(queryable, opts)

  def rollback(value), do: StateMachine.Repo.rollback(value)

  def insert(struct_or_changeset, _opts \\ []) do
    {:error, failed_changeset(struct_or_changeset)}
  end

  def insert!(struct_or_changeset, _opts \\ []) do
    raise Ecto.InvalidChangesetError,
      action: :insert,
      changeset: failed_changeset(struct_or_changeset)
  end

  def transaction(multi_or_fun, opts \\ [])

  def transaction(%Ecto.Multi{} = multi, _opts) do
    {name, changeset} = failing_operation(multi)
    {:error, name, changeset, %{}}
  end

  def transaction(fun, opts) when is_function(fun) do
    StateMachine.Repo.transaction(fun, opts)
  end

  defp failing_operation(multi) do
    Enum.find_value(Ecto.Multi.to_list(multi), {:insert, failed_changeset()}, fn
      {name, {:changeset, %Ecto.Changeset{} = changeset, _op_opts}} ->
        {name, failed_changeset(changeset)}

      {name, {:insert, %Ecto.Changeset{} = changeset, _op_opts}} ->
        {name, failed_changeset(changeset)}

      _other ->
        nil
    end)
  end

  defp failed_changeset do
    {%{}, %{entity_id: :string}}
    |> Ecto.Changeset.cast(%{}, [:entity_id])
    |> failed_changeset()
  end

  defp failed_changeset(%Ecto.Changeset{} = changeset) do
    %{Ecto.Changeset.add_error(changeset, :entity_id, "is invalid") | action: :insert}
  end

  defp failed_changeset(struct) do
    struct
    |> Ecto.Changeset.change()
    |> failed_changeset()
  end
end

defmodule StateMachineTest do
  use ExUnit.Case, async: false

  # ---------------------------------------------------------------------------
  # Real repo: the test environment provides StateMachine.Repo (SQLite),
  # already configured, with this bundle's migration applied. Persistence,
  # query filtering, and order_by are enforced by a real query engine.
  # ---------------------------------------------------------------------------

  # ---------------------------------------------------------------------------
  # Setup
  # ---------------------------------------------------------------------------

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(StateMachine.Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)
    {:ok, pid} = StateMachine.start_link(repo: StateMachine.Repo)
    %{sm: pid}
  end

  # ---------------------------------------------------------------------------
  # Starting entities
  # ---------------------------------------------------------------------------

  test "start/2 returns :pending for a brand-new entity", %{sm: sm} do
    assert {:ok, :pending} = StateMachine.start(sm, "order:1")
  end

  test "start/2 for the same entity twice returns the same state", %{sm: sm} do
    {:ok, :pending} = StateMachine.start(sm, "order:1")
    assert {:ok, :pending} = StateMachine.start(sm, "order:1")
  end

  test "start/2 re-hydrates state from DB after the in-memory map is cleared", %{sm: sm} do
    {:ok, _} = StateMachine.start(sm, "order:42")
    {:ok, :confirmed} = StateMachine.transition(sm, "order:42", :confirm)
    {:ok, :shipped} = StateMachine.transition(sm, "order:42", :ship)

    # Start a *new* GenServer backed by the same database
    {:ok, sm2} = StateMachine.start_link(repo: StateMachine.Repo)

    # Entity was never started in sm2, so it must hydrate from DB
    assert {:ok, :shipped} = StateMachine.start(sm2, "order:42")
  end

  # ---------------------------------------------------------------------------
  # get_state
  # ---------------------------------------------------------------------------

  test "get_state/2 returns :not_found for unknown entity", %{sm: sm} do
    assert {:error, :not_found} = StateMachine.get_state(sm, "order:nope")
  end

  test "get_state/2 reflects the current in-memory state", %{sm: sm} do
    {:ok, _} = StateMachine.start(sm, "order:1")
    {:ok, _} = StateMachine.transition(sm, "order:1", :confirm)
    assert {:ok, :confirmed} = StateMachine.get_state(sm, "order:1")
  end

  # ---------------------------------------------------------------------------
  # Happy-path transitions
  # ---------------------------------------------------------------------------

  test "full happy path: pending → confirmed → shipped → delivered", %{sm: sm} do
    # TODO
  end

  test "cancellation from :pending", %{sm: sm} do
    {:ok, _} = StateMachine.start(sm, "order:2")
    assert {:ok, :cancelled} = StateMachine.transition(sm, "order:2", :cancel)
  end

  test "cancellation from :confirmed", %{sm: sm} do
    {:ok, _} = StateMachine.start(sm, "order:3")
    {:ok, _} = StateMachine.transition(sm, "order:3", :confirm)
    assert {:ok, :cancelled} = StateMachine.transition(sm, "order:3", :cancel)
  end

  # ---------------------------------------------------------------------------
  # Invalid transitions
  # ---------------------------------------------------------------------------

  test "invalid event returns :invalid_transition and does not change state", %{sm: sm} do
    {:ok, _} = StateMachine.start(sm, "order:1")
    {:ok, _} = StateMachine.transition(sm, "order:1", :confirm)

    # :ship from :confirmed is valid, but :deliver from :confirmed is not
    assert {:error, :invalid_transition} =
             StateMachine.transition(sm, "order:1", :deliver)

    # State must be unchanged
    assert {:ok, :confirmed} = StateMachine.get_state(sm, "order:1")
  end

  test "transitioning a terminal state is invalid", %{sm: sm} do
    {:ok, _} = StateMachine.start(sm, "order:1")
    {:ok, _} = StateMachine.transition(sm, "order:1", :cancel)

    assert {:error, :invalid_transition} =
             StateMachine.transition(sm, "order:1", :confirm)

    assert {:ok, :cancelled} = StateMachine.get_state(sm, "order:1")
  end

  test "transition on unknown entity returns :not_found", %{sm: sm} do
    assert {:error, :not_found} =
             StateMachine.transition(sm, "order:unknown", :confirm)
  end

  test "invalid transition does not write to DB", %{sm: sm} do
    {:ok, _} = StateMachine.start(sm, "order:1")

    {:error, :invalid_transition} =
      StateMachine.transition(sm, "order:1", :ship)

    assert {:ok, []} = StateMachine.history(sm, "order:1")
  end

  # ---------------------------------------------------------------------------
  # Persistence / history
  # ---------------------------------------------------------------------------

  test "history/2 records every transition in order", %{sm: sm} do
    {:ok, _} = StateMachine.start(sm, "order:1")
    {:ok, _} = StateMachine.transition(sm, "order:1", :confirm)
    {:ok, _} = StateMachine.transition(sm, "order:1", :ship)

    assert {:ok, [first, second]} = StateMachine.history(sm, "order:1")

    assert first.event == :confirm
    assert first.from_state == :pending
    assert first.to_state == :confirmed

    assert second.event == :ship
    assert second.from_state == :confirmed
    assert second.to_state == :shipped
  end

  test "history/2 for unknown entity returns empty list", %{sm: sm} do
    assert {:ok, []} = StateMachine.history(sm, "order:nobody")
  end

  test "history/2 is scoped per entity", %{sm: sm} do
    {:ok, _} = StateMachine.start(sm, "order:A")
    {:ok, _} = StateMachine.start(sm, "order:B")
    {:ok, _} = StateMachine.transition(sm, "order:A", :confirm)
    {:ok, _} = StateMachine.transition(sm, "order:B", :cancel)

    assert {:ok, [%{event: :confirm}]} = StateMachine.history(sm, "order:A")
    assert {:ok, [%{event: :cancel}]} = StateMachine.history(sm, "order:B")
  end

  # ---------------------------------------------------------------------------
  # State recovery after simulated restart
  # ---------------------------------------------------------------------------

  test "state survives GenServer restart and is recovered from DB", %{sm: sm} do
    {:ok, _} = StateMachine.start(sm, "order:99")
    {:ok, _} = StateMachine.transition(sm, "order:99", :confirm)
    {:ok, _} = StateMachine.transition(sm, "order:99", :ship)

    # Kill the original GenServer (simulate crash/restart)
    GenServer.stop(sm)

    # Boot a fresh one backed by the same repo
    {:ok, sm2} = StateMachine.start_link(repo: StateMachine.Repo)

    # Re-hydrate from DB
    assert {:ok, :shipped} = StateMachine.start(sm2, "order:99")

    # And it should accept further valid transitions from recovered state
    assert {:ok, :delivered} = StateMachine.transition(sm2, "order:99", :deliver)
  end

  # ---------------------------------------------------------------------------
  # Concurrency — concurrent callers serialize correctly
  # ---------------------------------------------------------------------------

  test "concurrent transitions on the same entity serialize without corruption", %{sm: sm} do
    {:ok, _} = StateMachine.start(sm, "order:concurrent")

    # Fire many concurrent callers; only the first :confirm should succeed,
    # the rest should get :invalid_transition (already confirmed) or
    # :invalid_transition (not a valid event from :pending).
    tasks =
      for _ <- 1..20 do
        Task.async(fn ->
          StateMachine.transition(sm, "order:concurrent", :confirm)
        end)
      end

    results = Task.await_many(tasks)

    oks = Enum.filter(results, &match?({:ok, _}, &1))
    errors = Enum.filter(results, &match?({:error, :invalid_transition}, &1))

    # Exactly one transition should have succeeded
    assert length(oks) == 1
    assert {:ok, :confirmed} = hd(oks)

    # All others should have gotten :invalid_transition
    assert length(errors) == 19
  end

  test "concurrent transitions on *different* entities don't interfere", %{sm: sm} do
    for i <- 1..10 do
      StateMachine.start(sm, "order:par:#{i}")
    end

    tasks =
      for i <- 1..10 do
        Task.async(fn ->
          StateMachine.transition(sm, "order:par:#{i}", :confirm)
        end)
      end

    results = Task.await_many(tasks)
    assert Enum.all?(results, &match?({:ok, :confirmed}, &1))
  end

  # ---------------------------------------------------------------------------
  # DB write failures
  # ---------------------------------------------------------------------------

  test "transition/3 reports a failed DB write as {:error, {:db_error, reason}}" do
    {:ok, failing} = StateMachine.start_link(repo: StateMachineTest.FailingInsertRepo)
    id = unique_entity_id("db-error")

    assert {:ok, :pending} = StateMachine.start(failing, id)

    assert {:error, {:db_error, _reason}} =
             StateMachine.transition(failing, id, :confirm)
  end

  test "a failed DB write leaves the in-memory state at its previous value", %{sm: sm} do
    id = unique_entity_id("db-error-state")

    # Persist a real :confirmed state first, so the failing server hydrates to
    # a non-initial state and any reset would be visible.
    {:ok, :pending} = StateMachine.start(sm, id)
    {:ok, :confirmed} = StateMachine.transition(sm, id, :confirm)

    {:ok, failing} = StateMachine.start_link(repo: StateMachineTest.FailingInsertRepo)
    assert {:ok, :confirmed} = StateMachine.start(failing, id)

    assert {:error, {:db_error, _reason}} = StateMachine.transition(failing, id, :ship)

    # The write failed, so :shipped must not have been applied in memory.
    assert {:ok, :confirmed} = StateMachine.get_state(failing, id)
  end

  test "invalid transitions are rejected before any DB write is attempted" do
    {:ok, failing} = StateMachine.start_link(repo: StateMachineTest.FailingInsertRepo)
    id = unique_entity_id("db-error-invalid")

    {:ok, :pending} = StateMachine.start(failing, id)

    # :ship is not valid from :pending and writes nothing, so a repo whose
    # every write fails cannot turn this into a :db_error.
    assert {:error, :invalid_transition} = StateMachine.transition(failing, id, :ship)
  end

  defp unique_entity_id(prefix) do
    "order:#{prefix}:#{System.pid()}:#{System.unique_integer([:positive])}"
  end
end
```
