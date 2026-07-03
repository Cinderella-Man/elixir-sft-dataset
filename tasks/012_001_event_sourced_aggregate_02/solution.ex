defp validate_command(nil, {:open, name}) do
  {:ok, [%{type: :account_opened, name: name}]}
end

defp validate_command(_state, {:open, _name}), do: {:error, :already_open}

defp validate_command(nil, _command), do: {:error, :account_not_open}

defp validate_command(_state, {:deposit, amount}) do
  cond do
    amount <= 0 -> {:error, :invalid_amount}
    true -> {:ok, [%{type: :amount_deposited, amount: amount}]}
  end
end

defp validate_command(state, {:withdraw, amount}) do
  cond do
    amount <= 0 -> {:error, :invalid_amount}
    state.balance < amount -> {:error, :insufficient_balance}
    true -> {:ok, [%{type: :amount_withdrawn, amount: amount}]}
  end
end