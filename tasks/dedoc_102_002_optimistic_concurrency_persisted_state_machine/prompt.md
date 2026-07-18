# Document this module

Below is a complete, working, tested Elixir module. Its behavior is correct
and must not change — but every piece of documentation has been stripped.

Add the missing documentation and typespecs:

- a `@moduledoc` that explains what the module does and how it is used,
- a `@doc` for every public function,
- a `@spec` for every public function (add `@type`s where they make the
  specs clearer).

Do not change any behavior: every function clause, guard, and expression
must keep working exactly as it does now. Do not rename anything, do not
"improve" the code, and do not add or remove functions. Give me the
complete documented module in a single file.

## The module

```elixir
defmodule EntityTransition do
  use Ecto.Schema

  schema "entity_transitions" do
    field(:entity_id, :string)
    field(:event, :string)
    field(:from_state, :string)
    field(:to_state, :string)
    field(:version, :integer)
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
      add(:version, :integer, null: false)
      add(:inserted_at, :utc_datetime_usec, null: false)
    end

    create(index(:entity_transitions, [:entity_id]))
  end
end

defmodule StateMachine do
  use GenServer

  import Ecto.Query, only: [from: 2]

  @initial_state :pending

  @transitions %{
    {:pending, :confirm} => :confirmed,
    {:confirmed, :ship} => :shipped,
    {:shipped, :deliver} => :delivered,
    {:pending, :cancel} => :cancelled,
    {:confirmed, :cancel} => :cancelled
  }

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

  def transition(server, entity_id, event, expected_version) do
    GenServer.call(server, {:transition, entity_id, event, expected_version})
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
    {:ok, %{repo: repo, entities: %{}}}
  end

  @impl true
  def handle_call({:start, entity_id}, _from, state) do
    {cur_state, cur_version} = load_latest(state.repo, entity_id)
    entities = Map.put(state.entities, entity_id, {cur_state, cur_version})
    {:reply, {:ok, cur_state, cur_version}, %{state | entities: entities}}
  end

  def handle_call({:get_state, entity_id}, _from, state) do
    case Map.fetch(state.entities, entity_id) do
      {:ok, {cur_state, cur_version}} ->
        {:reply, {:ok, cur_state, cur_version}, state}

      :error ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:transition, entity_id, event, expected_version}, _from, state) do
    case Map.fetch(state.entities, entity_id) do
      :error ->
        {:reply, {:error, :not_found}, state}

      {:ok, {cur_state, cur_version}} ->
        do_transition(state, entity_id, event, expected_version, cur_state, cur_version)
    end
  end

  def handle_call({:history, entity_id}, _from, state) do
    rows = load_history(state.repo, entity_id)
    {:reply, {:ok, rows}, state}
  end

  # ---------------------------------------------------------------------------
  # Internal helpers
  # ---------------------------------------------------------------------------

  defp do_transition(state, entity_id, event, expected_version, cur_state, cur_version) do
    cond do
      expected_version != cur_version ->
        {:reply, {:error, {:stale_version, cur_version}}, state}

      not Map.has_key?(@transitions, {cur_state, event}) ->
        {:reply, {:error, :invalid_transition}, state}

      true ->
        next_state = Map.fetch!(@transitions, {cur_state, event})
        new_version = cur_version + 1
        commit(state, entity_id, event, cur_state, next_state, new_version)
    end
  end

  defp commit(state, entity_id, event, from_state, to_state, new_version) do
    case persist(state.repo, entity_id, event, from_state, to_state, new_version) do
      {:ok, _record} ->
        entities = Map.put(state.entities, entity_id, {to_state, new_version})
        {:reply, {:ok, to_state, new_version}, %{state | entities: entities}}

      {:error, reason} ->
        {:reply, {:error, {:db_error, reason}}, state}
    end
  end

  defp persist(repo, entity_id, event, from_state, to_state, version) do
    attrs = %{
      entity_id: entity_id,
      event: Atom.to_string(event),
      from_state: Atom.to_string(from_state),
      to_state: Atom.to_string(to_state),
      version: version,
      inserted_at: DateTime.utc_now()
    }

    %EntityTransition{}
    |> Ecto.Changeset.change(attrs)
    |> repo.insert()
  end

  defp load_latest(repo, entity_id) do
    query =
      from(t in EntityTransition,
        where: t.entity_id == ^entity_id,
        order_by: [desc: t.version, desc: t.id],
        limit: 1
      )

    case repo.one(query) do
      nil ->
        {@initial_state, 0}

      %EntityTransition{to_state: to_state, version: version} ->
        {String.to_existing_atom(to_state), version}
    end
  end

  defp load_history(repo, entity_id) do
    query =
      from(t in EntityTransition,
        where: t.entity_id == ^entity_id,
        order_by: [asc: t.id]
      )

    query
    |> repo.all()
    |> Enum.map(fn t ->
      %{
        event: String.to_existing_atom(t.event),
        from_state: String.to_existing_atom(t.from_state),
        to_state: String.to_existing_atom(t.to_state),
        version: t.version,
        inserted_at: t.inserted_at
      }
    end)
  end
end
```
