defmodule WorkflowServer do
  @moduledoc """
  A live, per-ticket workflow process that enforces SLA deadlines.

  Each `WorkflowServer` is a `GenServer` owning the lifecycle of exactly one
  ticket. A ticket moves through the manual transition table

      triage → assigned → working → resolved → closed

  with an automatic escalation edge `S → :escalated` fired by a per-state
  deadline timer, and a manual re-entry edge `escalated → assigned`.

  `:closed` is terminal. `:escalated` is reachable only through an automatic
  timeout, never through a manual event, and is left only via `:assign`.

  Deadlines are supplied as a `state => milliseconds` map. Entering a state
  (re-)arms that state's deadline from scratch; leaving a state cancels its
  pending deadline so a stale timer can never trigger a later escalation.

  Stale deadline messages are additionally distinguished by a per-timer
  reference tag: a message whose tag does not match the currently armed timer
  is ignored, so a timer that fired just as the ticket left its state can never
  cause a spurious escalation.
  """

  use GenServer

  @type state ::
          :triage | :assigned | :working | :resolved | :closed | :escalated
  @type event :: :assign | :begin | :resolve | :close

  @manual_edges %{
    {:triage, :assign} => :assigned,
    {:escalated, :assign} => :assigned,
    {:assigned, :begin} => :working,
    {:working, :resolve} => :resolved,
    {:resolved, :close} => :closed
  }

  @no_deadline_states [:escalated, :closed]

  # ── Public API ────────────────────────────────────────────────────────────

  @doc """
  Start a workflow server for a single ticket, beginning in `:triage`.

  Options:

    * `:deadlines` — a `%{state => milliseconds}` map (default `%{}`).
    * `:notify` — a 1-arity function called on every transition (default none).
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc "Return the current state atom of the ticket."
  @spec current(GenServer.server()) :: state()
  def current(server) do
    GenServer.call(server, :current)
  end

  @doc """
  Return the sorted list of manual events that would succeed right now.

  Never contains `:timeout`. From `:closed` it is `[]`; from `:escalated` it is
  `[:assign]`.
  """
  @spec allowed(GenServer.server()) :: [event()]
  def allowed(server) do
    GenServer.call(server, :allowed)
  end

  @doc """
  Attempt to apply a manual `event`.

  Returns `{:ok, new_state}` on success, or
  `{:error, :invalid_transition, current_state, event}` when `event` is not a
  valid manual edge out of the current state (including any event from
  `:closed`, an unknown event, or the reserved `:timeout` event).
  """
  @spec fire(GenServer.server(), atom()) ::
          {:ok, state()} | {:error, :invalid_transition, state(), atom()}
  def fire(server, event) do
    GenServer.call(server, {:fire, event})
  end

  @doc "Stop the workflow server."
  @spec stop(GenServer.server()) :: :ok
  def stop(server) do
    GenServer.stop(server)
  end

  # ── GenServer callbacks ───────────────────────────────────────────────────

  @impl true
  def init(opts) do
    deadlines = Keyword.get(opts, :deadlines, %{})
    notify = Keyword.get(opts, :notify, nil)

    data = %{
      state: :triage,
      deadlines: deadlines,
      notify: notify,
      timer_ref: nil,
      timer_tag: nil
    }

    {:ok, enter_state(data, :triage)}
  end

  @impl true
  def handle_call(:current, _from, data) do
    {:reply, data.state, data}
  end

  def handle_call(:allowed, _from, data) do
    {:reply, allowed_events(data.state), data}
  end

  def handle_call({:fire, event}, _from, data) do
    case Map.fetch(@manual_edges, {data.state, event}) do
      {:ok, to} ->
        new_data = transition(data, to, event)
        {:reply, {:ok, to}, new_data}

      :error ->
        {:reply, {:error, :invalid_transition, data.state, event}, data}
    end
  end

  @impl true
  def handle_info({:deadline, tag}, data) do
    if tag == data.timer_tag and schedule?(data.state, data.deadlines) do
      {:noreply, transition(data, :escalated, :timeout)}
    else
      {:noreply, data}
    end
  end

  def handle_info(_msg, data) do
    {:noreply, data}
  end

  # ── Internals ─────────────────────────────────────────────────────────────

  @spec transition(map(), state(), atom()) :: map()
  defp transition(data, to, event) do
    data
    |> notify_transition(to, event)
    |> Map.put(:state, to)
    |> enter_state(to)
  end

  # Invokes the notify callback (if any) for `data.state -> to`, isolating any
  # failure, and returns `data` unchanged so the caller can keep threading it.
  @spec notify_transition(map(), state(), atom()) :: map()
  defp notify_transition(%{notify: nil} = data, _to, _event), do: data

  defp notify_transition(%{notify: fun} = data, to, event) do
    try do
      fun.({data.state, to, event})
      data
    catch
      _kind, _reason -> data
    end
  end

  @spec enter_state(map(), state()) :: map()
  defp enter_state(data, state) do
    data = cancel_timer(data)

    if schedule?(state, data.deadlines) do
      ms = Map.fetch!(data.deadlines, state)
      tag = make_ref()
      ref = Process.send_after(self(), {:deadline, tag}, ms)
      %{data | timer_ref: ref, timer_tag: tag}
    else
      %{data | timer_ref: nil, timer_tag: nil}
    end
  end

  @spec cancel_timer(map()) :: map()
  defp cancel_timer(%{timer_ref: nil} = data), do: data

  defp cancel_timer(%{timer_ref: ref} = data) do
    Process.cancel_timer(ref)
    %{data | timer_ref: nil, timer_tag: nil}
  end

  @spec schedule?(state(), map()) :: boolean()
  defp schedule?(state, deadlines) do
    Map.has_key?(deadlines, state) and state not in @no_deadline_states
  end

  @spec allowed_events(state()) :: [event()]
  defp allowed_events(state) do
    @manual_edges
    |> Enum.filter(fn {{from, _event}, _to} -> from == state end)
    |> Enum.map(fn {{_from, event}, _to} -> event end)
    |> Enum.sort()
  end
end
