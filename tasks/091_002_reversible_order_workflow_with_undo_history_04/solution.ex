@spec undo(map()) :: {:ok, map()} | {:error, :nothing_to_undo}
def undo(%{history: []}), do: {:error, :nothing_to_undo}

def undo(%{history: [{_event, from, _to} | rest]} = record) do
  {:ok, record |> Map.put(:state, from) |> Map.put(:history, rest)}
end