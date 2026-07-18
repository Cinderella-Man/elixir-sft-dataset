  @impl true
  def init(%{clock: clock}) do
    state = %{
      clock: clock,
      # code_string => code map
      codes: %{},
      # code_string => integer (total successful uses)
      total_uses: %{},
      # {code_string, user_id} => integer (per-user successful uses)
      user_uses: %{}
    }

    {:ok, state}
  end