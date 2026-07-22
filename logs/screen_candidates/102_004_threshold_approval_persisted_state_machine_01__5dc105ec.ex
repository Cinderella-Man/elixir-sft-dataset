defmodule EntityTransition do
  @moduledoc """
  Ecto schema for a single persisted state-machine transition.

  Every row records the event that was applied, the state the entity was in before the
  event (`from_state`), the state it ended up in (`to_state`) and the approval counter
  *after* the transition was applied (`approvals`).

  Rows are append-only: the newest row for an `entity_id` (highest `id`) describes the
  entity's current state and approval count, which is what allows the `StateMachine`
  GenServer to re-hydrate an entity after a restart — including an entity that is still
  mid-review with a partially accumulated approval count.
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
    field :entity_id, :string
    field :event, :string
    field :from_state, :string
    field :to_state, :string
    field :approvals, :integer
    field :inserted_at, :utc_datetime_usec
  end

  @doc """
  Builds a changeset for a transition row.

  All fields are required and `approvals` must be a non-negative integer.
  """
  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(transition, attrs) do
    transition
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
    |> validate_number(:approvals, greater_than_or_equal_to: 0)
  end
end

defmodule StateMachine do
  @moduledoc """
  A GenServer that drives the lifecycle of change-request entities and persists every
  state transition to a database through an injected Ecto repo.

  ## Lifecycle

  States: `:draft`, `:in_review`, `:approved`, `:rejected`, `:withdrawn`.

  Each entity additionally carries a non-negative integer approval count.

      :draft     + :submit   -> :in_review  (approval count reset to 0)
      :in_review + :approve  -> see below   (approval count incremented by 1)
      :in_review + :reject   -> :rejected   (approval count unchanged)
      :draft     + :withdraw -> :withdrawn  (approval count unchanged)
      :in_review + :withdraw -> :withdrawn  (approval count unchanged)

  Every other `{state, event}` pair is invalid and yields `{:error, :invalid_transition}`
  without writing anything to the database.

  ## Multi-approval workflow

  `:approve` is only valid from `:in_review`. It increments the approval count by one and
  then compares the new count against the configured `:required_approvals` threshold
  (default `2`):

    * below the threshold — the entity stays in `:in_review`, but a transition row is
      still recorded with `from_state` and `to_state` both `"in_review"` and the new
      count;
    * at or above the threshold — the entity moves to `:approved` with that count.

  Because `transition/3` is a `GenServer.call/3`, a burst of concurrent `:approve` calls
  serialises through the server: the count climbs deterministically and the entity flips
  to `:approved` on exactly the call that reaches the threshold. Any further `:approve`
  from the terminal `:approved` state is an `:invalid_transition`.

  ## Persistence

  The server keeps an in-memory map of `%{entity_id => {current_state, approval_count}}`.
  It is populated lazily by `start/2`, which reads the most recent `entity_transitions`
  row for the entity and derives both the current state and the current approval count
  (falling back to `{:draft, 0}` when the entity has no history). After a restart the map
  is empty, so the next `start/2` re-hydrates from the database.
  """

  use GenServer

  import Ecto.Query, only: [from: 2]

  @typedoc "A state of the change-request lifecycle."
  @type state :: :draft | :in_review | :approved | :rejected | :withdrawn

  @typedoc "An event that may be applied to an entity."
  @type event :: :submit | :approve | :reject | :withdraw

  @typedoc "A recorded transition, as returned by `history/2`."
  @type history_entry :: %{
          event: event(),
          from_state: state(),
          to_state: state(),
          approvals: non_neg_integer(),
          inserted_at: DateTime.t()
        }

  @default_required_approvals 2

  # ----------------------------------------------------------------------------------
  # Public API
  # ----------------------------------------------------------------------------------

  @doc """
  Starts the state machine server.

  ## Options

    * `:repo` — required, the configured `Ecto.Repo` module used for persistence;
    * `:required_approvals` — optional positive integer, the number of `:approve` events
      needed to move an entity from `:in_review` to `:approved` (defaults to `2`);
    * `:name` — optional process name used for registration.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    {name, init_opts} = Keyword.pop(opts, :name)
    server_opts = if is_nil(name), do: [], else: [name: name]

    GenServer.start_link(__MODULE__, init_opts, server_opts)
  end

  @doc """
  Loads the latest persisted state and approval count for `entity_id` into memory.

  When the entity has no persisted history it starts in `:draft` with an approval count of
  `0`. Always returns `{:ok, current_state, approval_count}`.
  """
  @spec start(GenServer.server(), String.t()) :: {:ok, state(), non_neg_integer()}
  def start(server, entity_id) do
    GenServer.call(server, {:start, entity_id})
  end

  @doc """
  Returns `{:ok, current_state, approval_count}` for an entity previously loaded with
  `start/2`, or `{:error, :not_found}` when the entity was never started in this session.
  """
  @spec get_state(GenServer.server(), String.t()) ::
          {:ok, state(), non_neg_integer()} | {:error, :not_found}
  def get_state(server, entity_id) do
    GenServer.call(server, {:get_state, entity_id})
  end

  @doc """
  Applies `event` to `entity_id`.

  Returns `{:ok, new_state, new_approval_count}` when the event is valid — the transition
  row is persisted first and the in-memory state is only updated on a successful write.

  Returns `{:error, :invalid_transition}` (writing nothing) when the `{state, event}` pair
  is not part of the lifecycle, `{:error, :not_found}` when the entity has not been
  started, and `{:error, {:db_error, reason}}` when persistence fails — in which case the
  in-memory state is left untouched.
  """
  @spec transition(GenServer.server(), String.t(), event()) ::
          {:ok, state(), non_neg_integer()}
          | {:error, :invalid_transition | :not_found | {:db_error, term()}}
  def transition(server, entity_id, event) do
    GenServer.call(server, {:transition, entity_id, event})
  end

  @doc """
  Returns `{:ok, list}` with every persisted transition for `entity_id`, in chronological
  (insertion) order.

  Each entry is a map with the keys `:event`, `:from_state`, `:to_state`, `:approvals` and
  `:inserted_at`.
  """
  @spec history(GenServer.server(), String.t()) :: {:ok, [history_entry()]}
  def history(server, entity_id) do
    GenServer.call(server, {:history, entity_id})
  end

  # ----------------------------------------------------------------------------------
  # GenServer callbacks
  # ----------------------------------------------------------------------------------

  @impl GenServer
  def init(opts) do
    repo = Keyword.fetch!(opts, :repo)
    required = Keyword.get(opts, :required_approvals, @default_required_approvals)

    if not (is_integer(required) and required > 0) do
      {:stop, {:invalid_option, :required_approvals}}
    else
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
        apply_event(state, entity_id, event, current_state, approvals)
    end
  end

  def handle_call({:history, entity_id}, _from, state) do
    {:reply, {:ok, load_history(state.repo, entity_id)}, state}
  end

  # ----------------------------------------------------------------------------------
  # Internals
  # ----------------------------------------------------------------------------------

  @spec apply_event(map(), String.t(), event(), state(), non_neg_integer()) ::
          {:reply, term(), map()}
  defp apply_event(state, entity_id, event, current_state, approvals) do
    case next(current_state, event, approvals, state.required_approvals) do
      :error ->
        {:reply, {:error, :invalid_transition}, state}

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
            reply = {:ok, next_state, next_approvals}
            {:reply, reply, %{state | entities: entities}}

          {:error, reason} ->
            {:reply, {:error, {:db_error, reason}}, state}
        end
    end
  end

  @spec next(state(), event(), non_neg_integer(), pos_integer()) ::
          {:ok, state(), non_neg_integer()} | :error
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

  @spec load_entity(module(), String.t()) :: {state(), non_neg_integer()}
  defp load_entity(repo, entity_id) do
    query =
      from t in EntityTransition,
        where: t.entity_id == ^entity_id,
        order_by: [desc: t.id],
        limit: 1

    case repo.one(query) do
      nil -> {:draft, 0}
      row -> {to_state_atom(row.to_state), row.approvals}
    end
  end

  @spec load_history(module(), String.t()) :: [history_entry()]
  defp load_history(repo, entity_id) do
    query =
      from t in EntityTransition,
        where: t.entity_id == ^entity_id,
        order_by: [asc: t.id]

    query
    |> repo.all()
    |> Enum.map(fn row ->
      %{
        event: to_event_atom(row.event),
        from_state: to_state_atom(row.from_state),
        to_state: to_state_atom(row.to_state),
        approvals: row.approvals,
        inserted_at: row.inserted_at
      }
    end)
  end

  @spec to_state_atom(String.t()) :: state()
  defp to_state_atom("draft"), do: :draft
  defp to_state_atom("in_review"), do: :in_review
  defp to_state_atom("approved"), do: :approved
  defp to_state_atom("rejected"), do: :rejected
  defp to_state_atom("withdrawn"), do: :withdrawn

  @spec to_event_atom(String.t()) :: event()
  defp to_event_atom("submit"), do: :submit
  defp to_event_atom("approve"), do: :approve
  defp to_event_atom("reject"), do: :reject
  defp to_event_atom("withdraw"), do: :withdraw
end