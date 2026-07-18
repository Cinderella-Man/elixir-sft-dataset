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
defmodule RateMonitor do
  use GenServer

  # ---------------------------------------------------------------------------
  # Types
  # ---------------------------------------------------------------------------

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def start_link(opts \\ []) do
    {name_opt, gen_opts} =
      case Keyword.fetch(opts, :name) do
        {:ok, name} -> {[name: name], []}
        :error -> {[], []}
      end

    GenServer.start_link(__MODULE__, opts, gen_opts ++ name_opt)
  end

  def register(server, service_name, check_func, interval_ms, opts \\ []) do
    GenServer.call(server, {:register, service_name, check_func, interval_ms, opts})
  end

  def status(server, service_name) do
    GenServer.call(server, {:status, service_name})
  end

  def statuses(server) do
    GenServer.call(server, :statuses)
  end

  def deregister(server, service_name) do
    GenServer.call(server, {:deregister, service_name})
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    notify = Keyword.get(opts, :notify, nil)

    {:ok, %{services: %{}, clock: clock, notify: notify}}
  end

  @impl GenServer
  def handle_call({:register, name, check_func, interval_ms, opts}, _from, state) do
    if Map.has_key?(state.services, name) do
      {:reply, {:error, :already_registered}, state}
    else
      window_size = Keyword.get(opts, :window_size, 5)
      threshold = Keyword.get(opts, :threshold, 0.6)

      service = %{
        check_func: check_func,
        interval_ms: interval_ms,
        window_size: window_size,
        threshold: threshold,
        status: :pending,
        last_check_at: nil,
        history: [],
        notified_down: false
      }

      schedule_check(name, interval_ms)

      {:reply, :ok, put_in(state.services[name], service)}
    end
  end

  def handle_call({:status, name}, _from, state) do
    case Map.fetch(state.services, name) do
      {:ok, service} -> {:reply, {:ok, to_status_info(service)}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call(:statuses, _from, state) do
    result = Map.new(state.services, fn {name, svc} -> {name, to_status_info(svc)} end)
    {:reply, result, state}
  end

  def handle_call({:deregister, name}, _from, state) do
    {:reply, :ok, %{state | services: Map.delete(state.services, name)}}
  end

  @impl GenServer
  def handle_info({:check, name}, state) do
    case Map.fetch(state.services, name) do
      :error ->
        # Service was deregistered; discard stale message.
        {:noreply, state}

      {:ok, service} ->
        now = state.clock.()
        result = service.check_func.()

        {new_service, notify?} = apply_check_result(service, result, now)

        schedule_check(name, service.interval_ms)

        new_state = put_in(state.services[name], new_service)

        if notify? do
          fire_notify(state.notify, name, compute_failure_rate(new_service.history))
        end

        {:noreply, new_state}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp apply_check_result(service, result, now) do
    outcome =
      case result do
        :ok -> :ok
        {:error, _} -> :error
      end

    # Append to history, bounded by window_size.
    new_history =
      (service.history ++ [outcome])
      |> Enum.take(-service.window_size)

    failure_rate = compute_failure_rate(new_history)
    window_full = length(new_history) >= service.window_size

    new_status =
      cond do
        window_full && failure_rate >= service.threshold -> :down
        window_full -> :up
        # Window not yet full: if there are no errors so far, show :up;
        # otherwise stay :pending.
        failure_rate == 0.0 && length(new_history) > 0 -> :up
        true -> service.status |> maybe_upgrade_pending(outcome)
      end

    # Notification fires exactly on the transition into :down.
    notify? = new_status == :down && !service.notified_down && service.status != :down

    notified_down =
      cond do
        new_status == :down -> service.notified_down || notify?
        # When recovering from :down, reset the flag so future transitions
        # trigger a fresh notification.
        service.status == :down -> false
        true -> service.notified_down
      end

    new_service = %{
      service
      | status: new_status,
        last_check_at: now,
        history: new_history,
        notified_down: notified_down
    }

    {new_service, notify?}
  end

  # If pending and we just got an :ok, move to :up. Otherwise keep current.
  defp maybe_upgrade_pending(:pending, :ok), do: :up
  defp maybe_upgrade_pending(current, _), do: current

  defp compute_failure_rate([]), do: 0.0

  defp compute_failure_rate(history) do
    errors = Enum.count(history, &(&1 == :error))
    errors / length(history)
  end

  defp schedule_check(name, interval_ms) do
    Process.send_after(self(), {:check, name}, interval_ms)
  end

  defp to_status_info(service) do
    %{
      status: service.status,
      last_check_at: service.last_check_at,
      failure_rate: compute_failure_rate(service.history),
      checks_in_window: length(service.history)
    }
  end

  defp fire_notify(nil, _name, _rate), do: :ok
  defp fire_notify(notify_fn, name, rate), do: notify_fn.(name, rate)
end
```
