  defp do_cleanup(state) do
    now = state.clock.()
    cutoff = -Integer.floor_div(-(now - state.max_window_ms), state.bucket_ms)

    fresh_keys =
      Enum.reduce(state.keys, %{}, fn {key, buckets}, acc ->
        live = Map.filter(buckets, fn {b, _cnt} -> b >= cutoff end)

        if map_size(live) == 0 do
          # Drop the whole key — no live buckets remain.
          acc
        else
          Map.put(acc, key, live)
        end
      end)

    %{state | keys: fresh_keys}
  end