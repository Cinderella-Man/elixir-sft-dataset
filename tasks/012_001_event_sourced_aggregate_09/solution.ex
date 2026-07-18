  defp apply_event(%{type: :account_opened, name: name}, _nil_state) do
    %{name: name, balance: 0, status: :open}
  end

  defp apply_event(%{type: :amount_deposited, amount: amount}, state) do
    %{state | balance: state.balance + amount}
  end

  defp apply_event(%{type: :amount_withdrawn, amount: amount}, state) do
    %{state | balance: state.balance - amount}
  end