  defp active_doc(state, id, now) do
    case Map.get(state.docs, id) do
      nil -> nil
      doc -> if status(doc, now, state.retention) == :active, do: doc, else: nil
    end
  end