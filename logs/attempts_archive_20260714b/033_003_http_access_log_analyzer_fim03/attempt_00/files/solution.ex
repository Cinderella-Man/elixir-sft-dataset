  defp compute_top_paths(path_counts) do
    path_counts
    |> Enum.sort(fn {path_a, cnt_a}, {path_b, cnt_b} ->
      cond do
        cnt_a != cnt_b -> cnt_a > cnt_b
        true -> path_a <= path_b
      end
    end)
    |> Enum.take(10)
  end