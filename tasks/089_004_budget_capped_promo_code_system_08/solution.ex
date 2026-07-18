  def remaining_budget(code_string) when is_binary(code_string) do
    GenServer.call(__MODULE__, {:remaining_budget, code_string})
  end