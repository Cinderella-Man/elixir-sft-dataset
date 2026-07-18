  @impl true
  def init(%{clock: clock}) do
    {:ok, %{clock: clock, codes: %{}, total_uses: %{}, user_uses: %{}, dispensed: %{}}}
  end