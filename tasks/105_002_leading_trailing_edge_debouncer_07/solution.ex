  # Arm the burst's timer under a fresh token; {:fire, key, token} only acts
  # while the entry still carries this exact token.
  defp arm(key, delay_ms) do
    token = make_ref()
    %{timer: Process.send_after(self(), {:fire, key, token}, delay_ms), token: token}
  end