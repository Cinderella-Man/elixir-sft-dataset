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
      add(:inserted_at, :utc_datetime_usec, null: false)
    end

    create(index(:entity_transitions, [:entity_id]))
  end
end

defmodule StateMachine.Repo do
  use Ecto.Repo,
    otp_app: :state_machine,
    adapter: Ecto.Adapters.SQLite3
end

defmodule StateMachine do
  use GenServer

  import Ecto.Query, only: [from: 2]

  @transitions %{
    {:pending, :confirm} => :confirmed,
    {:confirmed, :ship} => :shipped,
    {:shipped, :deliver} => :delivered,
    {:pending, :cancel} => :cancelled,
    {:confirmed, :cancel} => :cancelled,
    {:pending, :expire} => :cancelled
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
    ttl = Keyword.get(opts, :pending_ttl_ms)
    {:ok, %{repo: repo, ttl: ttl, states: %{}}}
  end

  @impl true
  def handle_call({:start, entity_id}, _from, state) do
    current = load_state(state.repo, entity_id)
    maybe_schedule(current, entity_id, state.ttl)
    new_states = Map.put(state.states, entity_id, current)
    {:reply, {:ok, current}, %{state | states: new_states}}
  end

  def handle_call({:get_state, entity_id}, _from, state) do
    case Map.fetch(state.states, entity_id) do
      {:ok, current} -> {:reply, {:ok, current}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:transition, entity_id, event}, _from, state) do
    case Map.fetch(state.states, entity_id) do
      :error -> {:reply, {:error, :not_found}, state}
      {:ok, current} -> apply_transition(entity_id, current, event, state)
    end
  end

  def handle_call({:history, entity_id}, _from, state) do
    repo = state.repo

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

    rows = Enum.map(repo.all(query), &decode_history_row/1)
    {:reply, {:ok, rows}, state}
  end

  @impl true
  def handle_info({:check_expiry, entity_id}, state) do
    case Map.get(state.states, entity_id) do
      :pending ->
        case persist(state.repo, entity_id, :expire, :pending, :cancelled) do
          :ok ->
            new_states = Map.put(state.states, entity_id, :cancelled)
            {:noreply, %{state | states: new_states}}

          {:error, _reason} ->
            {:noreply, state}
        end

      _other ->
        {:noreply, state}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Internal helpers
  # ---------------------------------------------------------------------------

  defp apply_transition(entity_id, current, event, state) do
    case Map.fetch(@transitions, {current, event}) do
      :error ->
        {:reply, {:error, :invalid_transition}, state}

      {:ok, next} ->
        case persist(state.repo, entity_id, event, current, next) do
          :ok ->
            new_states = Map.put(state.states, entity_id, next)
            {:reply, {:ok, next}, %{state | states: new_states}}

          {:error, reason} ->
            {:reply, {:error, {:db_error, reason}}, state}
        end
    end
  end

  defp decode_history_row(row) do
    %{
      event: String.to_existing_atom(row.event),
      from_state: String.to_existing_atom(row.from_state),
      to_state: String.to_existing_atom(row.to_state),
      inserted_at: row.inserted_at
    }
  end

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
      to_state -> String.to_existing_atom(to_state)
    end
  end

  defp maybe_schedule(:pending, entity_id, ttl) when is_integer(ttl) do
    Process.send_after(self(), {:check_expiry, entity_id}, ttl)
    :ok
  end

  defp maybe_schedule(_state, _entity_id, _ttl), do: :ok

  defp persist(repo, entity_id, event, from_state, to_state) do
    row = %EntityTransition{
      entity_id: entity_id,
      event: Atom.to_string(event),
      from_state: Atom.to_string(from_state),
      to_state: Atom.to_string(to_state),
      inserted_at: DateTime.utc_now()
    }

    case repo.insert(row) do
      {:ok, _record} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
```
