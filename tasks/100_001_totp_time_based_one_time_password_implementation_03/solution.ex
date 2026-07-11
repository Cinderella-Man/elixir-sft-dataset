def generate_code(secret, time \\ :os.system_time(:second)) do
  key = base32_decode!(secret)
  step = div(time, @period)
  counter = <<step::big-unsigned-integer-size(64)>>

  :hmac
  |> :crypto.mac(:sha, key, counter)
  |> dynamic_truncate()
  |> rem(1_000_000)
  |> Integer.to_string()
  |> String.pad_leading(@digits, "0")
end