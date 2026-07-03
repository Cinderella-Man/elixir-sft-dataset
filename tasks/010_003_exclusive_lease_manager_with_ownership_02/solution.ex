  @spec fetch_live_lease(%{resource() => lease()}, resource(), integer()) ::
          {:ok, lease()} | :expired | :missing
  defp fetch_live_lease(leases, resource, now) do
    case Map.fetch(leases, resource) do
      {:ok, lease} ->
        if expired?(lease, now), do: :expired, else: {:ok, lease}

      :error ->
        :missing
    end
  end