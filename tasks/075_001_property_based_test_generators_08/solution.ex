  # Produces a string in the format "<local>@<domain>.<tld>" where each
  # segment is a non-empty lowercase alphanumeric string (1–20 chars).
  defp email do
    SD.bind(alnum_segment(), fn local ->
      SD.bind(alnum_segment(), fn domain ->
        SD.bind(alnum_segment(), fn tld ->
          SD.constant("#{local}@#{domain}.#{tld}")
        end)
      end)
    end)
  end