  @doc """
  Processes a payment.

  With a `nil` idempotency key a new record is always created. With a key, a
  matching-fingerprint replay returns the cached result, a differing-fingerprint
  replay returns `{:error, :idempotency_key_conflict}`, and an expired/unseen key
  is processed fresh.
  """
  @spec process_payment(GenServer.server(), params(), String.t() | nil) :: process_result()
  def process_payment(server, params, idempotency_key \\ nil) do
    GenServer.call(server, {:process_payment, params, idempotency_key})
  end