  defp build_report(acc) do
    %{
      per_metric: finalize_metrics(acc.per_metric),
      total_samples: acc.total,
      time_range: acc.timestamps,
      samples_per_hour: acc.samples_per_hour,
      unique_tags: acc.unique_tags,
      malformed_count: acc.malformed
    }
  end