  def code_at(config, unix_time) when is_integer(unix_time) do
    step = div(unix_time, config.period)
    counter = <<step::unsigned-big-integer-size(64)>>
    key = base32_decode(config.secret)
    hmac = :crypto.mac(:hmac, hash_for(config.algorithm), key, counter)

    offset = rem(:binary.last(hmac), 16)

    <<_high_bit::size(1), truncated::unsigned-big-integer-size(31)>> =
      :binary.part(hmac, offset, 4)

    truncated
    |> rem(Integer.pow(10, config.digits))
    |> Integer.to_string()
    |> String.pad_leading(config.digits, "0")
  end