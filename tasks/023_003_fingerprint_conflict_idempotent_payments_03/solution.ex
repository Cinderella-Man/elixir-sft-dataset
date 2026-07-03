  defp do_process(state, params) do
    if valid_params?(params) do
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

      {{:ok, response}, %{state | counter: counter, payments: [response | state.payments]}}
    else
      {{:error, :invalid_params}, state}
    end
  end