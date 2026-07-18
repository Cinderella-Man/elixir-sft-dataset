  defp put_hma(stream, period, hma_state) do
    %{stream | hma: Map.put(stream.hma, period, hma_state)}
  end