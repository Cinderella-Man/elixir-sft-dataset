  defp throughput(processed, elapsed_ms) do
    if elapsed_ms == 0 do
      0.0
    else
      processed / (elapsed_ms / 1000)
    end
  end