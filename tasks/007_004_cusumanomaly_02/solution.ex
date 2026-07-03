  defp welford_update(stream, value) do
    n = stream.samples + 1
    delta = value - stream.mean
    new_mean = stream.mean + delta / n
    delta2 = value - new_mean
    new_m2 = stream.m2 + delta * delta2
    %{stream | samples: n, mean: new_mean, m2: new_m2}
  end