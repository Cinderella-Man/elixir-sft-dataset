defmodule EntityTransition do
  @moduledoc """
  Ecto schema for a single persisted state-machine transition.

  Each row records the event that was applied, the state the entity was in before the event
  (`from_state`), the state it ended up in (`to_state`), and the approval counter *after* the
  transition was applied (`approvals`).

  Rows are append-only: the latest row (highest `id`) for an `entity_id` describes the entity's
  current state and current approval count. When no row exists for an entity, the entity is
  considered to be in the `:draft` state with an approval count of `0`.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          entity_id: String.t() | nil,
          event: String.t() | nil,
          from_state: String.t() | nil,
          to_state: String.t() | nil,
          approvals: non_neg_integer() | nil,
          inserted_at: DateTime.t() | nil
        }

  @required_fields [:entity_id, :event, :from_state, :to_state, :approvals, :inserted_at]

  schema "entity_transitions" do
    field(:entity_id, :string)
    field(:event, :string)
    field(:from_state, :string)
    field(:to_state, :string)
    field(:approvals, :integer)
    field(:inserted_at, :utc_datetime_usec)
  end

  @doc """
  Builds a changeset for an `EntityTransition` row.

  All fields are required and `approvals` must be a non-negative integer.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = transition, attrs) do
    transition
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
    |> validate_number(:approvals, greater_than_or_equal_to: 0)
  end
end

defmodule Repo.Migrations.CreateEntityTransitions do
  @moduledoc """
  Creates the append-only `entity_transitions` table backing `StateMachine`.

  Written with plain `Ecto.Migration` primitives only, so it runs unchanged on SQLite, Postgres
  and MySQL. `inserted_at` is managed explicitly by the application rather than by Ecto's
  automatic timestamps, so it is declared as a regular column.
  """

  use Ecto.Migration

  @doc """
  Creates the `entity_transitions` table and the index on `entity_id`.
  """
  @spec change() :: any()
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
  end
end

defmodule StateMachine do
  @moduledoc """
  A `GenServer` that drives a change-request review lifecycle for stateful entities and persists
  every transition to a database via Ecto.

  ## States

  `:draft`, `:in_review`, `:approved`, `:rejected`, `:withdrawn`. Each entity also carries a
  non-negative integer approval count.

  ## Transitions

    * `:draft` + `:submit` -> `:in_review` (approval count reset to `0`)
    * `:in_review` + `:approve` -> increments the approval count, then either stays in
      `:in_review` (count below the required threshold) or moves to `:approved` (count at or
      above the threshold)
    * `:in_review` + `:reject` -> `:rejected` (count unchanged)
    * `:draft` + `:withdraw` -> `:withdrawn` (count unchanged)
    * `:in_review` + `:withdraw` -> `:withdrawn` (count unchanged)

  Every other `{state, event}` pair is invalid and yields `{:error, :invalid_transition}` without
  touching the database.

  ## Multi-approval workflow

  The number of approvals required to reach `:approved` is configured per server through the
  `:required_approvals` option (defaults to `2`). Every `:approve` event writes a transition row,
  including the intermediate ones where `from_state` and `to_state` are both `:in_review`; that
  row carries the newly incremented count, so a partially-approved entity can be re-hydrated from
  the database after a restart.

  ## Concurrency

  `transition/3` is a `GenServer.call/3`, so concurrent callers serialize through the server
  process. The increment-and-check for `:approve` happens inside `handle_call/3`, which means a
  burst of concurrent approvals is applied one at a time: the count climbs deterministically and
  the entity flips to `:approved` on exactly the call that reaches the threshold. Any later
  `:approve` call operates from the terminal `:approved` state and is rejected with
  `{:error, :invalid_transition}`.

  ## State

  The server holds `%{entity_id => {current_state, approval_count}}` in memory. Because that map
  is empty after a restart, the next `start/2` call re-hydrates the entity from the most recent
  persisted row.
  """

  use GenServer

  import Ecto.Query, only: [from: 2]

  @type state :: :draft | :in_review | :approved | :rejected | :withdrawn
  @type event :: :submit | :approve | :reject | :withdraw
  @type entity_id :: String.t()
  @type approvals :: non_neg_integer()

  @typep server_state :: %{
           repo: module(),
           required_approvals: pos_integer(),
           entities: %{optional(entity_id()) => {state(), approvals()}}
         }

  @default_required_approvals 2
  @initial_state :draft
  @initial_approvals 0

  @states [:draft, :in_review, :approved, :rejected, :withdrawn]

  # --------------------------------------------------------------------------------------------
  # Public API
  # --------------------------------------------------------------------------------------------

  @doc """
  Starts the state-machine server.

  ## Options

    * `:repo` (required) - the configured `Ecto.Repo` module used to persist transitions.
    * `:required_approvals` - a positive integer; the number of `:approve` events needed to move
      an entity from `:in_review` to `:approved`. Defaults to `2`.
    * `:name` - optional process registration name, forwarded to `GenServer.start_link/3`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name], else: []

    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  @doc """
  Loads (re-hydrates) an entity from the database and tracks it in memory.

  Reads the most recent persisted transition for `entity_id` and derives the current state from
  its `to_state` and the current approval count from its `approvals`. When the entity has no
  persisted rows it starts in `:draft` with an approval count of `0`.

  Returns `{:ok, current_state, approval_count}`.
  """
  @spec start(GenServer.server(), entity_id()) :: {:ok, state(), approvals()}
  def start(server, entity_id) when is_binary(entity_id) do
    GenServer.call(server, {:start, entity_id})
  end

  @doc """
  Returns `{:ok, current_state, approval_count}` for an entity previously loaded with `start/2`.

  Returns `{:error, :not_found}` when the entity has not been started in this session.
  """
  @spec get_state(GenServer.server(), entity_id()) ::
          {:ok, state(), approvals()} | {:error, :not_found}
  def get_state(server, entity_id) when is_binary(entity_id) do
    GenServer.call(server, {:get_state, entity_id})
  end

  @doc """
  Applies `event` to `entity_id`.

  On a valid transition the resulting row is persisted first and the in-memory state is only
  updated once the write succeeds, returning `{:ok, new_state, new_approval_count}`.

  Returns:

    * `{:error, :not_found}` when the entity has not been started in this session;
    * `{:error, :invalid_transition}` when the `{state, event}` pair is not allowed - nothing is
      written;
    * `{:error, {:db_error, reason}}` when the database write fails - the in-memory state is left
      untouched.

  Implemented as a `call` so that concurrent callers serialize through the server.
  """
  @spec transition(GenServer.server(), entity_id(), event()) ::
          {:ok, state(), approvals()}
          | {:error, :not_found}
          | {:error, :invalid_transition}
          | {:error, {:db_error, term()}}
  def transition(server, entity_id, event) when is_binary(entity_id) and is_atom(event) do
    GenServer.call(server, {:transition, entity_id, event})
  end

  @doc """
  Returns `{:ok, list}` with every persisted transition for `entity_id`, oldest first.

  Each entry is a map with the keys `:event`, `:from_state`, `:to_state`, `:approvals` and
  `:inserted_at`. States and events are returned as atoms.
  """
  @spec history(GenServer.server(), entity_id()) :: {:ok, [map()]}
  def history(server, entity_id) when is_binary(entity_id) do
    GenServer.call(server, {:history, entity_id})
  end

  # --------------------------------------------------------------------------------------------
  # GenServer callbacks
  # --------------------------------------------------------------------------------------------

  @impl GenServer
  @spec init(keyword()) :: {:ok, server_state()} | {:stop, term()}
  def init(opts) do
    repo = Keyword.get(opts, :repo)
    required = Keyword.get(opts, :required_approvals, @default_required_approvals)

    cond do
      not is_atom(repo) or is_nil(repo) ->
        {:stop, {:invalid_option, :repo}}

      not (is_integer(required) and required > 0) ->
        {:stop, {:invalid_option, :required_approvals}}

      true ->
        {:ok, %{repo: repo, required_approvals: required, entities: %{}}}
    end
  end

  @impl GenServer
  def handle_call({:start, entity_id}, _from, state) do
    {current_state, approvals} = load_entity(state.repo, entity_id)
    entities = Map.put(state.entities, entity_id, {current_state, approvals})

    {:reply, {:ok, current_state, approvals}, %{state | entities: entities}}
  end

  def handle_call({:get_state, entity_id}, _from, state) do
    case Map.fetch(state.entities, entity_id) do
      {:ok, {current_state, approvals}} -> {:reply, {:ok, current_state, approvals}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:transition, entity_id, event}, _from, state) do
    case Map.fetch(state.entities, entity_id) do
      :error ->
        {:reply, {:error, :not_found}, state}

      {:ok, {current_state, approvals}} ->
        do_transition(state, entity_id, event, current_state, approvals)
    end
  end

  def handle_call({:history, entity_id}, _from, state) do
    {:reply, {:ok, load_history(state.repo, entity_id)}, state}
  end

  # --------------------------------------------------------------------------------------------
  # Transition logic
  # --------------------------------------------------------------------------------------------

  @spec do_transition(server_state(), entity_id(), event(), state(), approvals()) ::
          {:reply, term(), server_state()}
  defp do_transition(state, entity_id, event, current_state, approvals) do
    case next(current_state, event, approvals, state.required_approvals) do
      {:ok, next_state, next_approvals} ->
        attrs = %{
          entity_id: entity_id,
          event: Atom.to_string(event),
          from_state: Atom.to_string(current_state),
          to_state: Atom.to_string(next_state),
          approvals: next_approvals,
          inserted_at: DateTime.utc_now()
        }

        case insert_transition(state.repo, attrs) do
          :ok ->
            entities = Map.put(state.entities, entity_id, {next_state, next_approvals})
            {:reply, {:ok, next_state, next_approvals}, %{state | entities: entities}}

          {:error, reason} ->
            {:reply, {:error, {:db_error, reason}}, state}
        end

      :error ->
        {:reply, {:error, :invalid_transition}, state}
    end
  end

  @spec next(state(), event(), approvals(), pos_integer()) ::
          {:ok, state(), approvals()} | :error
  defp next(:draft, :submit, _approvals, _required), do: {:ok, :in_review, 0}

  defp next(:in_review, :approve, approvals, required) do
    new_approvals = approvals + 1

    if new_approvals >= required do
      {:ok, :approved, new_approvals}
    else
      {:ok, :in_review, new_approvals}
    end
  end

  defp next(:in_review, :reject, approvals, _required), do: {:ok, :rejected, approvals}
  defp next(:draft, :withdraw, approvals, _required), do: {:ok, :withdrawn, approvals}
  defp next(:in_review, :withdraw, approvals, _required), do: {:ok, :withdrawn, approvals}
  defp next(_state, _event, _approvals, _required), do: :error

  # --------------------------------------------------------------------------------------------
  # Persistence helpers
  # --------------------------------------------------------------------------------------------

  @spec insert_transition(module(), map()) :: :ok | {:error, term()}
  defp insert_transition(repo, attrs) do
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

  @spec load_entity(module(), entity_id()) :: {state(), approvals()}
  defp load_entity(repo, entity_id) do
    query =
      from(t in EntityTransition,
        where: t.entity_id == ^entity_id,
        order_by: [desc: t.id],
        limit: 1,
        select: {t.to_state, t.approvals}
      )

    case repo.one(query) do
      {to_state, approvals} -> {to_atom(to_state), approvals || @initial_approvals}
      nil -> {@initial_state, @initial_approvals}
    end
  end

  @spec load_history(module(), entity_id()) :: [map()]
  defp load_history(repo, entity_id) do
    query =
      from(t in EntityTransition,
        where: t.entity_id == ^entity_id,
        order_by: [asc: t.id]
      )

    repo.all(query)
    |> Enum.map(fn row ->
      %{
        event: to_atom(row.event),
        from_state: to_atom(row.from_state),
        to_state: to_atom(row.to_state),
        approvals: row.approvals,
        inserted_at: row.inserted_at
      }
    end)
  end

  @spec to_atom(String.t() | atom() | nil) :: atom() | nil
  defp to_atom(value) when is_atom(value), do: value

  defp to_atom(value) when is_binary(value) do
    known = @states ++ [:submit, :approve, :reject, :withdraw]

    Enum.find(known, fn candidate -> Atom.to_string(candidate) == value end) ||
      String.to_atom(value)
  end
end