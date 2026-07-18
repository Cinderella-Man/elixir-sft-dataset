  defp new_stream do
    %{
      # newest-first
      values: [],
      max_period: 0,
      # %{period => %{raw_buffer: [float]}}
      hma: %{}
    }
  end