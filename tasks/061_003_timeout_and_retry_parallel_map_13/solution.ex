  defp drain(ref) do
    receive do
      {^ref, _} -> :ok
    after
      0 -> :ok
    end
  end