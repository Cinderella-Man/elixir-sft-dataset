  defp reset_stream do
    %{samples: 0, mean: 0.0, m2: 0.0, s_high: 0.0, s_low: 0.0}
  end