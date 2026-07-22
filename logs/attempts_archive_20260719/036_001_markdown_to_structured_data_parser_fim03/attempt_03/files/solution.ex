  # A new H2 heading: flush the current category (if any), then open a new one.
  defp process_line({:heading, name}, %{categories: cats, current: current}) do
    cats = if current, do: [finalise(current) | cats], else: cats
    %{categories: cats, current: %{category: name, items: []}}
  end

  # A valid bullet item that appears before the first heading is discarded;
  # the state is returned unchanged.
  defp process_line({:item, _item}, %{current: nil} = state), do: state

  # A valid bullet item beneath a heading: prepend it to the current category's
  # items and leave `categories` unchanged.
  defp process_line({:item, item}, %{current: current} = state) do
    %{state | current: Map.update!(current, :items, &[item | &1])}
  end

  # Anything else (ignored lines): leave the state unchanged.
  defp process_line(:ignore, state), do: state