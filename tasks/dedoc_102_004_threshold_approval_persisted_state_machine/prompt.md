# Restore the documentation

The module below works and is fully tested — its behavior is final. What it
lost is every piece of documentation. Put it back:

- a `@moduledoc` covering purpose and usage,
- a `@doc` on each public function,
- a `@spec` on each public function (plus `@type`s where they clarify).

And keep your hands off the code itself: no renames, no refactors, no added
or removed functions, identical behavior everywhere. Return the whole
documented module in one file.

## The module

```elixir
defmodule EntityTransition do
  use Ecto.Schema

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
  use Ecto.Migration

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
  use GenServer

  import Ecto.Query, only: [from: 2]

  @default_required_approvals 2

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def start_link(opts) do
    {name, init_opts} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, init_opts, gen_opts)
  end

  def start(server, entity_id) do
    GenServer.call(server, {:start, entity_id})
  end

  def get_state(server, entity_id) do
    GenServer.call(server, {:get_state, entity_id})
  end

  def transition(server, entity_id, event) do
    GenServer.call(server, {:transition, entity_id, event})
  end

  def history(server, entity_id) do
    GenServer.call(server, {:history, entity_id})
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(opts) do
    repo = Keyword.fetch!(opts, :repo)
    required = Keyword.get(opts, :required_approvals, @default_required_approvals)

    {:ok, %{repo: repo, required: required, entities: %{}}}
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

  defp do_transition(entity_id, event, current_state, approvals, state) do
    case next_state(current_state, event, approvals, state.required) do
      :error ->
        {:reply, {:error, :invalid_transition}, state}

      {:ok, new_state, new_approvals} ->
        persist(entity_id, event, current_state, new_state, new_approvals, state)
    end
  end

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
