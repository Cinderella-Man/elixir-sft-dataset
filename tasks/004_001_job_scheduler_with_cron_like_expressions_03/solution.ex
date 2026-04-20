# A part is either a range/value optionally followed by /step, or * optionally
# followed by /step.
defp parse_part(part, lo, hi) do
  case String.split(part, "/") do
    [base] ->
      parse_range_or_star(base, lo, hi)

    [base, step_str] ->
      with {:ok, step} <- parse_int(step_str),
            true <- step > 0 || :error,
            {:ok, values} <- parse_range_or_star(base, lo, hi) do
        # apply step: keep only values whose offset from the range start is
        # divisible by the step.
        sorted = Enum.sort(values)
        start = List.first(sorted)

        filtered =
          Enum.filter(sorted, fn v -> rem(v - start, step) == 0 end)

        {:ok, MapSet.new(filtered)}
      else
        _ -> :error
      end

    _ ->
      :error
  end
end
