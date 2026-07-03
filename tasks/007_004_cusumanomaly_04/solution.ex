defp welford_stddev(%{samples: 0}), do: 0.0
defp welford_stddev(%{samples: n, m2: m2}), do: :math.sqrt(m2 / n)