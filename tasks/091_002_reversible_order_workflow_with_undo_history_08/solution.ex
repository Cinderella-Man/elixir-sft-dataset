  @spec history(map()) :: [atom()]
  def history(%{history: history}) do
    history
    |> Enum.reverse()
    |> Enum.map(fn {event, _from, _to} -> event end)
  end