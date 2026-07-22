defmodule TaskAggregate do
  @moduledoc """
  An event-sourced aggregate for a simple task / issue tracking domain.

  `TaskAggregate` is a `GenServer` that holds, for every aggregate id, both the
  current projected state and the ordered list of events that produced it.

  Handling a command follows the classic event-sourcing cycle:

    1. **Validate** the command against the aggregate's current state.
    2. **Decide** — produce zero or more events (never mutate state directly).
    3. **Apply** each event, in order, to the current state.
    4. **Persist** the events by appending them to the aggregate's history.

  Every aggregate id is tracked independently: commands issued against
  `"task:1"` have no effect on `"task:2"`.

  ## Commands

    * `{:create, title, priority}` — priority is `:low`, `:medium` or `:high`
    * `{:assign, assignee_name}`
    * `{:start}`
    * `{:complete}`
    * `{:reopen}`

  ## Events

  Events are plain maps carrying at least a `:type` key. The emitted types are
  `:task_created`, `:task_assigned`, `:task_started`, `:task_completed` and
  `:task_reopened`.

  ## Example

      {:ok, pid} = TaskAggregate.start_link([])
      {:ok, [%{type: :task_created}]} =
        TaskAggregate.execute(pid, "task:1", {:create, "Ship it", :high})
      {:ok, _} = TaskAggregate.execute(pid, "task:1", {:assign, "ada"})
      {:ok, _} = TaskAggregate.execute(pid, "task:1", {:start})
      %{status: :in_progress} = TaskAggregate.state(pid, "task:1")

  """

  use GenServer

  @typedoc "Identifier of a single aggregate instance."
  @type id :: term()

  @typedoc "Allowed task priorities."
  @type priority :: :low | :medium | :high

  @typedoc "Lifecycle status of a task."
  @type status :: :created | :in_progress | :completed

  @typedoc "Commands accepted by `execute/3`."
  @type command ::
          {:create, String.t(), priority()}
          | {:assign, String.t()}
          | {:start}
          | {:complete}
          | {:reopen}

  @typedoc "An event produced by a successful command."
  @type event :: %{required(:type) => atom(), optional(atom()) => term()}

  @typedoc "The projected state of a single aggregate."
  @type task_state :: %{
          title: String.t(),
          assignee: String.t() | nil,
          status: status(),
          priority: priority()
        }

  @typedoc "Reasons a command can be rejected."
  @type error_reason ::
          :already_exists
          | :invalid_priority
          | :not_found
          | :already_completed
          | :not_assigned
          | :already_started
          | :not_in_progress
          | :not_completed
          | :unknown_command

  @priorities [:low, :medium, :high]

  # ── Public API ──────────────────────────────────────────────────────────────

  @doc """
  Starts the aggregate server.

  Supported options:

    * `:name` — a name used to register the process (passed straight through to
      `GenServer.start_link/3`).

  Any other option is forwarded to `GenServer.start_link/3` untouched.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)
    server_opts = if name, do: [{:name, name} | opts], else: opts
    GenServer.start_link(__MODULE__, :ok, server_opts)
  end

  @doc """
  Executes `command` against the aggregate identified by `id`.

  The command is validated against the aggregate's current state; on success the
  resulting events are applied to the state and appended to the event history,
  and `{:ok, events}` is returned with only the events produced by *this*
  command. On failure `{:error, reason}` is returned and nothing is persisted.
  """
  @spec execute(GenServer.server(), id(), command()) ::
          {:ok, [event()]} | {:error, error_reason()}
  def execute(server, id, command) do
    GenServer.call(server, {:execute, id, command})
  end

  @doc """
  Returns the current projected state of the aggregate identified by `id`, or
  `nil` when no command has ever been applied to it.
  """
  @spec state(GenServer.server(), id()) :: task_state() | nil
  def state(server, id) do
    GenServer.call(server, {:state, id})
  end

  @doc """
  Returns the full ordered event history of the aggregate identified by `id`,
  oldest event first. Unknown aggregates yield an empty list.
  """
  @spec events(GenServer.server(), id()) :: [event()]
  def events(server, id) do
    GenServer.call(server, {:events, id})
  end

  # ── GenServer callbacks ─────────────────────────────────────────────────────

  @impl GenServer
  def init(:ok) do
    {:ok, %{states: %{}, events: %{}}}
  end

  @impl GenServer
  def handle_call({:execute, id, command}, _from, server_state) do
    current = Map.get(server_state.states, id)

    case decide(current, command) do
      {:ok, new_events} ->
        new_state = Enum.reduce(new_events, current, &apply_event(&2, &1))
        history = Map.get(server_state.events, id, []) ++ new_events

        server_state = %{
          server_state
          | states: Map.put(server_state.states, id, new_state),
            events: Map.put(server_state.events, id, history)
        }

        {:reply, {:ok, new_events}, server_state}

      {:error, reason} ->
        {:reply, {:error, reason}, server_state}
    end
  end

  def handle_call({:state, id}, _from, server_state) do
    {:reply, Map.get(server_state.states, id), server_state}
  end

  def handle_call({:events, id}, _from, server_state) do
    {:reply, Map.get(server_state.events, id, []), server_state}
  end

  # ── Decide: validate a command and emit events ──────────────────────────────

  @spec decide(task_state() | nil, command()) :: {:ok, [event()]} | {:error, error_reason()}
  defp decide(nil, {:create, title, priority}) when priority in @priorities do
    {:ok, [%{type: :task_created, title: title, priority: priority}]}
  end

  defp decide(nil, {:create, _title, _priority}), do: {:error, :invalid_priority}

  defp decide(%{}, {:create, _title, priority}) when priority not in @priorities do
    {:error, :invalid_priority}
  end

  defp decide(%{}, {:create, _title, _priority}), do: {:error, :already_exists}

  defp decide(nil, {:assign, _assignee}), do: {:error, :not_found}

  defp decide(%{status: :completed}, {:assign, _assignee}), do: {:error, :already_completed}

  defp decide(%{}, {:assign, assignee}) do
    {:ok, [%{type: :task_assigned, assignee: assignee}]}
  end

  defp decide(nil, {:start}), do: {:error, :not_found}
  defp decide(%{status: :in_progress}, {:start}), do: {:error, :already_started}
  defp decide(%{assignee: nil}, {:start}), do: {:error, :not_assigned}
  defp decide(%{}, {:start}), do: {:ok, [%{type: :task_started}]}

  defp decide(nil, {:complete}), do: {:error, :not_found}
  defp decide(%{status: :in_progress}, {:complete}), do: {:ok, [%{type: :task_completed}]}
  defp decide(%{}, {:complete}), do: {:error, :not_in_progress}

  defp decide(nil, {:reopen}), do: {:error, :not_found}
  defp decide(%{status: :completed}, {:reopen}), do: {:ok, [%{type: :task_reopened}]}
  defp decide(%{}, {:reopen}), do: {:error, :not_completed}

  defp decide(_state, _command), do: {:error, :unknown_command}

  # ── Apply: fold an event into the state ─────────────────────────────────────

  @spec apply_event(task_state() | nil, event()) :: task_state()
  defp apply_event(nil, %{type: :task_created, title: title, priority: priority}) do
    %{title: title, assignee: nil, status: :created, priority: priority}
  end

  defp apply_event(state, %{type: :task_assigned, assignee: assignee}) do
    %{state | assignee: assignee}
  end

  defp apply_event(state, %{type: :task_started}) do
    %{state | status: :in_progress}
  end

  defp apply_event(state, %{type: :task_completed}) do
    %{state | status: :completed}
  end

  defp apply_event(state, %{type: :task_reopened}) do
    %{state | status: :created, assignee: nil}
  end

  defp apply_event(state, _event), do: state
end