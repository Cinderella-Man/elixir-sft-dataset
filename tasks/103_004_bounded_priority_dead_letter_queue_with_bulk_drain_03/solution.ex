  # highest priority first, then FIFO (ascending id = insertion order)
  defp ordered(entries) do
    Enum.sort_by(entries, fn e -> {-Map.fetch!(@rank, e.priority), e.id} end)
  end