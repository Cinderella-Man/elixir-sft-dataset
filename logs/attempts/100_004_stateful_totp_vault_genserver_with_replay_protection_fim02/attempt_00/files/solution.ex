  defp match_step(secret, code, base, window) do
    lo = max(base - window, 0)
    hi = base + window
    Enum.find(lo..hi, fn step -> hotp(secret, step) == code end)
  end