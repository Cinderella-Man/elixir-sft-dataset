  defp trim_values(%{max_period: 0} = stream), do: stream

  defp trim_values(stream) do
    %{stream | values: Enum.take(stream.values, stream.max_period)}
  end