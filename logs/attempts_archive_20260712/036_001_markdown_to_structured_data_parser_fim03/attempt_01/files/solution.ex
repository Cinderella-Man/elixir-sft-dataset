  # A new H2 heading: flush current category (if any), open a new one.
  defp process_line({:heading, name}, %{categories: cats, current: current}) do
    cats =
      if current do
        [finalise(current) | cats]
      else
        cats
      end

    %{categories: cats, current: %{category: name, items: []}}
  end

  # A valid bullet item: append to the current category (discard if no heading yet).
  defp process_line({:item, item}, %{categories: cats, current: current}) do
    if current do
      updated = Map.update!(current, :items, fn items -> [item | items] end)
      %{categories: cats, current: updated}
    else
      %{categories: cats, current: nil}
    end
  end

  # Anything else: skip.
  defp process_line(:ignore, state), do: state