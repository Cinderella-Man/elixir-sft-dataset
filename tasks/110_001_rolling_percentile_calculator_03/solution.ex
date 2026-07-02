defp live_samples(samples, _now, nil), do: samples

defp live_samples(samples, now, window_ms) do
  Enum.filter(samples, fn {t, _v} -> now - t < window_ms end)
end