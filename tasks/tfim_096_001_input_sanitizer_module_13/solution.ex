    test "classic XSS vector is neutralised" do
      input = ~s[<img src=x onerror="alert('XSS')">]
      refute Sanitizer.html(input) =~ "onerror"
      refute Sanitizer.html(input) =~ "alert"
    end