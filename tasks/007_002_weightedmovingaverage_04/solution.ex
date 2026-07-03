  defp push_value(stream, value) do
    value = value * 1.0
    new_values = [value | stream.values]

    new_hma =
      Map.new(stream.hma, fn {period, hma_state} ->
        wma1_period = div(period, 2)
        wma2_period = period

        # Use the NEW values list (includes this push).
        wma1 = compute_wma(new_values, wma1_period)
        wma2 = compute_wma(new_values, wma2_period)
        raw = 2 * wma1 - wma2

        buffer_size = round(:math.sqrt(period))
        new_buffer = [raw | hma_state.raw_buffer] |> Enum.take(buffer_size)

        {period, %{hma_state | raw_buffer: new_buffer}}
      end)

    %{stream | values: new_values, hma: new_hma}
  end