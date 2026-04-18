@impl true
def handle_info(:cleanup, %State{} = state) do
  now = state.clock.()

  buckets =
    state.buckets
    |> Enum.reject(fn {_name, bucket} ->
      now - bucket.last_access > state.cleanup_ttl_ms
    end)
    |> Map.new()

  schedule_cleanup(state.cleanup_interval_ms)

  {:noreply, %State{state | buckets: buckets}}
end
