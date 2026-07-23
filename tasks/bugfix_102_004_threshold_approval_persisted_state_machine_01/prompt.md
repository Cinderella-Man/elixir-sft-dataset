# Fix the bug

The module below was written for the task that follows, but ONE behavior bug
slipped in. The test suite (not shown) fails with the report at the bottom.
Find the bug and fix it — change as little as possible; do not restructure
working code. Reply with the complete corrected module.

## The task the module implements

Hey — I need you to build out a piece of our change-request review system, and I'd rather describe it than write a spec, so bear with me.

What I'm after is an Elixir GenServer module called `StateMachine` that manages the lifecycle of stateful entities, persists every state transition to a database, and drives a multi-approval workflow: the `:approve` event carries a persisted approval counter, and the entity only advances to `:approved` once a configured number of approvals has been reached.

The lifecycle I want modelled is our change-request review flow. The states are `:draft`, `:in_review`, `:approved`, `:rejected`, `:withdrawn`, and on top of the state each entity also carries a non-negative integer approval count. The transitions (current_state + event → next_state), along with what each does to the approval count, are:

  - :draft      + :submit   → :in_review   (approval count reset to 0)
  - :in_review  + :approve  → depends on the count (I'll explain below)
  - :in_review  + :reject   → :rejected    (approval count unchanged)
  - :draft      + :withdraw → :withdrawn   (approval count unchanged)
  - :in_review  + :withdraw → :withdrawn   (approval count unchanged)

Any other (state, event) combination is invalid — I don't want any of them quietly succeeding.

Now the interesting one. `:approve` is only valid from `:in_review`. Applying it increments the approval count by 1, and then it splits two ways. If the new count is less than the configured required number of approvals, the entity stays in `:in_review` — but I still want a transition row recorded for it, with `from_state` and `to_state` both `:in_review` and the new count. If the new count is greater than or equal to the required number of approvals, the entity transitions to `:approved` with that count. The required number of approvals is configured on the server; see what I want out of `start_link/1` below.

For the public API, here's what I need to be able to call:

  - `StateMachine.start_link(opts)` — starts the GenServer. It should accept a `:repo` option (an Ecto repo module), an optional `:required_approvals` option (a positive integer, and I want it to default to 2 when it isn't supplied), and an optional `:name` option for process registration.

  - `StateMachine.start(server, entity_id)` — loads the latest persisted state and approval count for the given entity out of the database. If there's no record at all, the entity starts in the `:draft` state with an approval count of 0. It returns `{:ok, current_state, approval_count}`.

  - `StateMachine.get_state(server, entity_id)` — returns `{:ok, current_state, approval_count}` for an entity that was previously started, or `{:error, :not_found}` if the entity has never been started in this session.

  - `StateMachine.transition(server, entity_id, event)` — attempts to apply `event`. When it's valid, it persists a transition row (new state + event + resulting approval count), updates the in-memory state, and returns `{:ok, new_state, new_approval_count}`. When the (state, event) pair isn't valid, it returns `{:error, :invalid_transition}` and writes nothing at all. And when the entity hasn't been started yet, it returns `{:error, :not_found}`.

  - `StateMachine.history(server, entity_id)` — returns `{:ok, list}`, where the list is every recorded transition for that entity in chronological (insertion) order. Each entry should be a map with the keys `:event`, `:from_state`, `:to_state`, `:approvals`, and `:inserted_at`. I want `:event`, `:from_state`, and `:to_state` to come back as atoms — the actual event/state atoms, not the strings they were persisted as — with `:approvals` being the integer count after that transition and `:inserted_at` being the stored timestamp. This one reads straight from the database and shouldn't require the entity to have been started; an entity with no recorded transitions just yields `{:ok, []}`.

Persistence goes through Ecto, and you can assume the caller hands us a configured Ecto repo. The table we care about is `entity_transitions`, with these columns:

  - `id` — bigint primary key (auto-increment)
  - `entity_id` — string, non-null, indexed
  - `event` — string (the atom serialised as a string), non-null
  - `from_state` — string, non-null
  - `to_state` — string, non-null
  - `approvals` — integer, non-null (the approval count *after* this transition)
  - `inserted_at` — utc_datetime_usec, non-null

So there are three things I need from you: the `EntityTransition` Ecto schema module, an Ecto migration file that creates the table, and the `StateMachine` GenServer module itself.

Internally, the GenServer should keep an in-memory map of `%{entity_id => {current_state, approval_count}}`. On `start/2` it queries the DB for the most recent row for that entity and derives both the current `to_state` and the current `approvals` value from it. That way, on restart the in-memory map is empty and the next `start/2` re-hydrates from the DB — including a partially-approved entity's mid-review count.

One thing I'm firm on for concurrency: `transition/3` has to be implemented as a `call`, not a cast, so concurrent callers serialize through the GenServer. Because the increment-and-check happens inside `handle_call`, a burst of concurrent `:approve` calls gets applied one at a time — the count climbs deterministically and the entity flips to `:approved` on exactly the call that reaches the required threshold, and any further `:approve` calls after that (coming from the terminal `:approved` state) are `:invalid_transition`.

On errors: if a DB write fails in `transition/3`, return `{:error, {:db_error, reason}}`, and make sure it does NOT update the in-memory state.

Please give me all three modules/files in clearly separated blocks, and stick to Ecto (plus its adapters) as the only external dependency — no additional libraries.

Last thing, about how this gets exercised on our side. The test environment provides a real, already-configured SQLite Ecto repo and injects it into your GenServer via the `repo:` option, so do NOT define a repo module or any repo configuration yourself. Your migration file has to live at a `priv/repo/migrations/<name>.exs` path: it gets executed against that repo before the tests run, so the schema/migration must be valid for SQLite — plain `Ecto.Migration`, no database-specific SQL. And the migration module must be named exactly `Repo.Migrations.CreateEntityTransitions` and written as a `change/0` migration, because the test suite loads and runs it by that exact name.

## The buggy module

```elixir
defmodule EntityTransition do
  @moduledoc """
  Ecto schema for a single persisted state-machine transition.

  Every successful `StateMachine.transition/3` (and every intermediate
  approval step) writes exactly one row into the `entity_transitions`
  table. A row captures the event that was applied, the state the entity
  moved from and to, and the approval counter *after* the transition.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "entity_transitions" do
    field(:entity_id, :string)
    field(:event, :string)
    field(:from_state, :string)
    field(:to_state, :string)
    field(:approvals, :integer)
    field(:inserted_at, :utc_datetime_usec)
  end
end

defmodule Repo.Migrations.CreateEntityTransitions do
  @moduledoc """
  Migration that creates the `entity_transitions` table used to persist
  every state-machine transition, together with an index on `entity_id`
  so per-entity look-ups stay fast.

  Written with plain `Ecto.Migration` primitives so it is valid across
  adapters (including SQLite) with no database-specific SQL.
  """

  use Ecto.Migration

  @doc """
  Create the `entity_transitions` table and its `entity_id` index.
  """
  def change do
    create table(:entity_transitions) do
      add(:entity_id, :string, null: false)
      add(:event, :string, null: false)
      add(:from_state, :string, null: false)
      add(:to_state, :string, null: false)
      add(:approvals, :integer, null: false)
      add(:inserted_at, :utc_datetime_usec, null: false)
    end

    create(index(:entity_transitions, [:entity_id]))

    :ok
  end
end

defmodule StateMachine do
  @moduledoc """
  GenServer that manages the lifecycle of stateful entities following a
  change-request review workflow, persisting every transition to a
  database via an injected Ecto repo.

  ## States

    * `:draft`
    * `:in_review`
    * `:approved`
    * `:rejected`
    * `:withdrawn`

  Each entity also carries a non-negative integer approval count.

  ## Transitions

    * `:draft`     + `:submit`   -> `:in_review` (count reset to 0)
    * `:in_review` + `:approve`  -> increments the count, then either
      stays in `:in_review` (count below the required threshold) or
      moves to `:approved` (count at/above the threshold)
    * `:in_review` + `:reject`   -> `:rejected` (count unchanged)
    * `:draft`     + `:withdraw` -> `:withdrawn` (count unchanged)
    * `:in_review` + `:withdraw` -> `:withdrawn` (count unchanged)

  Any other `(state, event)` pair is invalid.

  The number of approvals required to reach `:approved` is configured on
  the server via `start_link/1` (defaults to `2`).

  The server keeps an in-memory map of
  `%{entity_id => {current_state, approval_count}}`. On restart the map is
  empty, so the next `start/2` re-hydrates from the database — including a
  partially-approved entity's mid-review count.
  """

  use GenServer

  import Ecto.Query, only: [from: 2]

  @type state_name :: :draft | :in_review | :approved | :rejected | :withdrawn
  @type event :: :submit | :approve | :reject | :withdraw
  @type server :: GenServer.server()

  @default_required_approvals 2

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Start the state-machine server.

  Options:

    * `:repo` (required) — a configured Ecto repo module used for all
      persistence.
    * `:required_approvals` — a positive integer number of approvals
      needed to reach `:approved`. Defaults to `2`.
    * `:name` — optional process name for registration.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name, init_opts} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, init_opts, gen_opts)
  end

  @doc """
  Load the latest persisted state and approval count for `entity_id`.

  If no record exists, the entity starts in `:draft` with an approval
  count of `0`. Returns `{:ok, current_state, approval_count}`.
  """
  @spec start(server(), String.t()) :: {:ok, state_name(), non_neg_integer()}
  def start(server, entity_id) do
    GenServer.call(server, {:start, entity_id})
  end

  @doc """
  Return `{:ok, current_state, approval_count}` for a previously started
  entity, or `{:error, :not_found}` if it has never been started in this
  session.
  """
  @spec get_state(server(), String.t()) ::
          {:ok, state_name(), non_neg_integer()} | {:error, :not_found}
  def get_state(server, entity_id) do
    GenServer.call(server, {:get_state, entity_id})
  end

  @doc """
  Attempt to apply `event` to `entity_id`.

  On a valid transition, persists a transition row (new state + event +
  resulting approval count), updates the in-memory state and returns
  `{:ok, new_state, new_approval_count}`.

  Returns `{:error, :invalid_transition}` (writing nothing) for an invalid
  `(state, event)` pair, `{:error, :not_found}` if the entity has not been
  started, or `{:error, {:db_error, reason}}` if persistence fails (the
  in-memory state is left unchanged in that case).
  """
  @spec transition(server(), String.t(), event()) ::
          {:ok, state_name(), non_neg_integer()}
          | {:error, :invalid_transition | :not_found | {:db_error, term()}}
  def transition(server, entity_id, event) do
    GenServer.call(server, {:transition, entity_id, event})
  end

  @doc """
  Return `{:ok, list}` with every recorded transition for `entity_id` in
  chronological (insertion) order.

  Each entry is a map with keys `:event`, `:from_state`, `:to_state`,
  `:approvals` and `:inserted_at`.
  """
  @spec history(server(), String.t()) :: {:ok, [map()]}
  def history(server, entity_id) do
    GenServer.call(server, {:history, entity_id})
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  @spec init(keyword()) :: {:ok, map()}
  def init(opts) do
    repo = Keyword.fetch!(opts, :repo)
    required = Keyword.get(opts, :required_approvals, @default_required_approvals)

    {:error, %{repo: repo, required: required, entities: %{}}}
  end

  @impl true
  def handle_call({:start, entity_id}, _from, state) do
    {current_state, approvals} = load_latest(state.repo, entity_id)
    entities = Map.put(state.entities, entity_id, {current_state, approvals})

    {:reply, {:ok, current_state, approvals}, %{state | entities: entities}}
  end

  def handle_call({:get_state, entity_id}, _from, state) do
    case Map.fetch(state.entities, entity_id) do
      {:ok, {current_state, approvals}} ->
        {:reply, {:ok, current_state, approvals}, state}

      :error ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:transition, entity_id, event}, _from, state) do
    case Map.fetch(state.entities, entity_id) do
      :error ->
        {:reply, {:error, :not_found}, state}

      {:ok, {current_state, approvals}} ->
        do_transition(entity_id, event, current_state, approvals, state)
    end
  end

  def handle_call({:history, entity_id}, _from, state) do
    {:reply, {:ok, fetch_history(state.repo, entity_id)}, state}
  end

  # ---------------------------------------------------------------------------
  # Internal helpers
  # ---------------------------------------------------------------------------

  @spec do_transition(String.t(), event(), state_name(), non_neg_integer(), map()) ::
          {:reply, term(), map()}
  defp do_transition(entity_id, event, current_state, approvals, state) do
    case next_state(current_state, event, approvals, state.required) do
      :error ->
        {:reply, {:error, :invalid_transition}, state}

      {:ok, new_state, new_approvals} ->
        persist(entity_id, event, current_state, new_state, new_approvals, state)
    end
  end

  @spec persist(
          String.t(),
          event(),
          state_name(),
          state_name(),
          non_neg_integer(),
          map()
        ) :: {:reply, term(), map()}
  defp persist(entity_id, event, from_state, to_state, approvals, state) do
    record = %EntityTransition{
      entity_id: entity_id,
      event: Atom.to_string(event),
      from_state: Atom.to_string(from_state),
      to_state: Atom.to_string(to_state),
      approvals: approvals,
      inserted_at: DateTime.utc_now()
    }

    case state.repo.insert(record) do
      {:ok, _row} ->
        entities = Map.put(state.entities, entity_id, {to_state, approvals})
        {:reply, {:ok, to_state, approvals}, %{state | entities: entities}}

      {:error, reason} ->
        {:reply, {:error, {:db_error, reason}}, state}
    end
  end

  @spec next_state(state_name(), event(), non_neg_integer(), pos_integer()) ::
          {:ok, state_name(), non_neg_integer()} | :error
  defp next_state(:draft, :submit, _approvals, _required), do: {:ok, :in_review, 0}

  defp next_state(:in_review, :approve, approvals, required) do
    new_approvals = approvals + 1

    if new_approvals >= required do
      {:ok, :approved, new_approvals}
    else
      {:ok, :in_review, new_approvals}
    end
  end

  defp next_state(:in_review, :reject, approvals, _required),
    do: {:ok, :rejected, approvals}

  defp next_state(:draft, :withdraw, approvals, _required),
    do: {:ok, :withdrawn, approvals}

  defp next_state(:in_review, :withdraw, approvals, _required),
    do: {:ok, :withdrawn, approvals}

  defp next_state(_state, _event, _approvals, _required), do: :error

  @spec load_latest(module(), String.t()) :: {state_name(), non_neg_integer()}
  defp load_latest(repo, entity_id) do
    query =
      from(t in EntityTransition,
        where: t.entity_id == ^entity_id,
        order_by: [desc: t.id],
        limit: 1
      )

    case repo.one(query) do
      nil -> {:draft, 0}
      row -> {String.to_atom(row.to_state), row.approvals}
    end
  end

  @spec fetch_history(module(), String.t()) :: [map()]
  defp fetch_history(repo, entity_id) do
    query =
      from(t in EntityTransition,
        where: t.entity_id == ^entity_id,
        order_by: [asc: t.id]
      )

    query
    |> repo.all()
    |> Enum.map(fn row ->
      %{
        event: String.to_atom(row.event),
        from_state: String.to_atom(row.from_state),
        to_state: String.to_atom(row.to_state),
        approvals: row.approvals,
        inserted_at: row.inserted_at
      }
    end)
  end
end
```

## Failing test report

```
18 of 18 test(s) failed:

  * test start/2 returns :draft with 0 approvals for a brand-new entity
      no match of right hand side value:
      
          {:error, %{required: 2, repo: StateMachine.Repo, entities: %{}}}
      

  * test get_state/2 returns :not_found for unknown entity
      no match of right hand side value:
      
          {:error, %{required: 2, repo: StateMachine.Repo, entities: %{}}}
      

  * test submit moves draft to in_review with count reset to 0
      no match of right hand side value:
      
          {:error, %{required: 2, repo: StateMachine.Repo, entities: %{}}}
      

  * test approve stays in_review until the required count, then flips to approved
      no match of right hand side value:
      
          {:error, %{required: 2, repo: StateMachine.Repo, entities: %{}}}
      

  (…14 more)
```
