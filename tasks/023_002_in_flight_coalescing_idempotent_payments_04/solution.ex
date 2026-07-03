defp finalize(state, params, :ok) do
  counter = state.counter + 1
  id = "pay_#{counter}"

  response = %{
    id: id,
    amount: params.amount,
    currency: params.currency,
    recipient: params.recipient,
    status: "completed",
    created_at: state.clock.()
  }

  state = %{state | counter: counter, payments: [response | state.payments]}
  {{:ok, response}, state}
end

defp finalize(state, _params, {:error, reason}) do
  {{:error, reason}, state}
end