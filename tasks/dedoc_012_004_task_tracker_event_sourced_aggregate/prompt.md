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
defmodule TaskAggregate do
  use GenServer

  @valid_priorities [:low, :medium, :high]

  # --- Public API ---

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  def execute(server, id, command) do
    GenServer.call(server, {:execute, id, command})
  end

  def state(server, id) do
    GenServer.call(server, {:get_state, id})
  end

  def events(server, id) do
    GenServer.call(server, {:get_events, id})
  end

  # --- GenServer Callbacks ---

  @impl true
  def init(initial_state), do: {:ok, initial_state}

  @impl true
  def handle_call({:execute, id, command}, _from, store) do
    current_instance = Map.get(store, id, %{state: nil, events: []})

    case validate_command(current_instance.state, command) do
      {:ok, new_events} ->
        updated_state = Enum.reduce(new_events, current_instance.state, &apply_event/2)

        updated_instance = %{
          state: updated_state,
          events: current_instance.events ++ new_events
        }

        {:reply, {:ok, new_events}, Map.put(store, id, updated_instance)}

      {:error, reason} ->
        {:reply, {:error, reason}, store}
    end
  end

  @impl true
  def handle_call({:get_state, id}, _from, store) do
    {:reply, get_in(store, [id, :state]), store}
  end

  @impl true
  def handle_call({:get_events, id}, _from, store) do
    history =
      store
      |> Map.get(id, %{})
      |> Map.get(:events, [])

    {:reply, history, store}
  end

  # --- Domain Logic: Command Validation ---

  defp validate_command(nil, {:create, title, priority}) do
    if priority in @valid_priorities do
      {:ok, [%{type: :task_created, title: title, priority: priority}]}
    else
      {:error, :invalid_priority}
    end
  end

  defp validate_command(_state, {:create, _title, _priority}), do: {:error, :already_exists}

  defp validate_command(nil, _command), do: {:error, :not_found}

  defp validate_command(%{status: :completed}, {:assign, _assignee}),
    do: {:error, :already_completed}

  defp validate_command(_state, {:assign, assignee}) do
    {:ok, [%{type: :task_assigned, assignee: assignee}]}
  end

  defp validate_command(%{assignee: nil}, {:start}), do: {:error, :not_assigned}
  defp validate_command(%{status: :in_progress}, {:start}), do: {:error, :already_started}

  defp validate_command(_state, {:start}) do
    {:ok, [%{type: :task_started}]}
  end

  defp validate_command(%{status: :in_progress}, {:complete}) do
    {:ok, [%{type: :task_completed}]}
  end

  defp validate_command(_state, {:complete}), do: {:error, :not_in_progress}

  defp validate_command(%{status: :completed}, {:reopen}) do
    {:ok, [%{type: :task_reopened}]}
  end

  defp validate_command(_state, {:reopen}), do: {:error, :not_completed}

  # --- Domain Logic: Event Application ---

  defp apply_event(%{type: :task_created, title: title, priority: priority}, _nil_state) do
    %{title: title, assignee: nil, status: :created, priority: priority}
  end

  defp apply_event(%{type: :task_assigned, assignee: assignee}, state) do
    %{state | assignee: assignee}
  end

  defp apply_event(%{type: :task_started}, state) do
    %{state | status: :in_progress}
  end

  defp apply_event(%{type: :task_completed}, state) do
    %{state | status: :completed}
  end

  defp apply_event(%{type: :task_reopened}, state) do
    %{state | status: :created, assignee: nil}
  end
end
```
