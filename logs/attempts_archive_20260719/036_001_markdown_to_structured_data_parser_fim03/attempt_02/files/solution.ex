  # A new H2 heading: flush the current category (if any), then open a new one.
  defp process_line({:heading, name}, %{categories: cats, current: current}) do
    cats = if current, do: [finalise(current) | cats], else: cats
    %{categories: cats, current: %{category: name, items: []}}
  end

  # A valid bullet item: prepend it to the current category's items.
  # If no heading has been seen yet, discard the item and leave the state unchanged.
  defp process_line({:item, item}, %{categories: cats, current: current} = state) do
    if current do
      %{categories: cats, current: Map.update!(current, :items, &[item | &1])}
    else
      state
    end
  end

  # Anything else (ignored lines): leave the state unchanged.
  defp process_line(:ignore, state), do: state