defp validate_and_deserialize(plaintext, expires_at, opts) do
  if now(opts) < expires_at do
    deserialize(plaintext)
  else
    {:error, :expired}
  end
end