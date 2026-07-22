  defp compute_top_accounts(volume_by_account) do
    volume_by_account
    |> Enum.sort(fn {id_a, vol_a}, {id_b, vol_b} ->
      cond do
        vol_a != vol_b -> vol_a > vol_b
        true -> id_a <= id_b
      end
    end)
    |> Enum.take(5)
    |> Enum.map(fn {id, vol} -> {id, vol / 1} end)
  end