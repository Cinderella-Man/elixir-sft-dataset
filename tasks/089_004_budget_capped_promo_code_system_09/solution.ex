  def dispensed(code_string) when is_binary(code_string) do
    GenServer.call(__MODULE__, {:dispensed, code_string})
  end