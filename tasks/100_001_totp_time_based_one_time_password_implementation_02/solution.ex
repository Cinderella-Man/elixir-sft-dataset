defp dynamic_truncate(<<_::binary-size(19), last::8>> = hmac) do
  offset = last &&& 0x0F
  <<_::binary-size(^offset), b0, b1, b2, b3, _::binary>> = hmac

  (b0 &&& 0x7F) <<< 24 ||| b1 <<< 16 ||| b2 <<< 8 ||| b3
end