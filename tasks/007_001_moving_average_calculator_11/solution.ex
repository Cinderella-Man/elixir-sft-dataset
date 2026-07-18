  defp new_stream do
    %{
      # newest-first plain list; never trimmed during push
      values: [],
      max_period: 0,
      total_count: 0,
      ema: %{}
    }
  end