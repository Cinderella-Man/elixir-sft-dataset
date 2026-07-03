  @impl true
  def handle_info({:revalidate_complete, key, task_ref, new_value}, state) do
    case {Map.fetch(state.entries, key), Map.fetch(state.in_flight, key)} do
      {{:ok, entry}, {:ok, ^task_ref}} ->
        now = state.clock.()

        updated = %{
          entry
          | value: new_value,
            fresh_until: now + entry.fresh_ms,
            hard_expires_at: now + entry.fresh_ms + entry.stale_ms
        }

        {:noreply,
         %{
           state
           | entries: Map.put(state.entries, key, updated),
             in_flight: Map.delete(state.in_flight, key)
         }}

      _ ->
        # Stale result from a no-longer-tracked revalidation.
        new_in_flight =
          case Map.fetch(state.in_flight, key) do
            {:ok, ^task_ref} -> Map.delete(state.in_flight, key)
            _ -> state.in_flight
          end

        {:noreply, %{state | in_flight: new_in_flight}}
    end
  end

  def handle_info({:revalidate_failed, key, task_ref, _reason}, state) do
    new_in_flight =
      case Map.fetch(state.in_flight, key) do
        {:ok, ^task_ref} -> Map.delete(state.in_flight, key)
        _ -> state.in_flight
      end

    {:noreply, %{state | in_flight: new_in_flight}}
  end

  def handle_info(:sweep, state) do
    now = state.clock.()

    pruned =
      state.entries
      |> Enum.reject(fn {_k, %{hard_expires_at: h}} -> now >= h end)
      |> Map.new()

    new_in_flight =
      state.in_flight
      |> Enum.filter(fn {k, _ref} -> Map.has_key?(pruned, k) end)
      |> Map.new()

    schedule_sweep(state.sweep_interval_ms)
    {:noreply, %{state | entries: pruned, in_flight: new_in_flight}}
  end

  def handle_info(_msg, state), do: {:noreply, state}