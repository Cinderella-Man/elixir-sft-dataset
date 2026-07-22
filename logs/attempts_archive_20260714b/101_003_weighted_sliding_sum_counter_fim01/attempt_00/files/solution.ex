  defp cleanup(state) do
    now = state.clock.()
    cutoff = now - @max_window_ms

    keys =
      state.keys
      |> Enum.reduce(%{}, fn {key, buckets}, acc ->
        kept =
          Enum.filter(buckets, fn {bucket, _sum} ->
            bucket * state.bucket_ms >= cutoff
          end)

        if kept == [], do: acc, else: Map.put(acc, key, Map.new(kept))
      end)

    %{state | keys: keys}
  end