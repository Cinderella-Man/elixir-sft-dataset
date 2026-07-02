defp arm(entry, name) do
  ref = make_ref()
  warn_timer = Process.send_after(self(), {:warn, name, ref}, entry.warn_ms)
  timeout_timer = Process.send_after(self(), {:timeout, name, ref}, entry.timeout_ms)

  Map.merge(entry, %{
    ref: ref,
    phase: :healthy,
    warn_timer: warn_timer,
    timeout_timer: timeout_timer
  })
end