use "time"

primitive _HttpDate
  """
  Format epoch seconds as an RFC 7231 IMF-fixdate HTTP-date.

  The output is always 29 characters in the form:
  `Thu, 01 Jan 1970 00:00:00 GMT`

  Uses `PosixDate` from stdlib. Despite the `PosixDate` docstring claiming
  "Monday is 1", the C runtime copies `tm_wday` directly (verified in
  `ponyc/src/libponyrt/lang/time.c`), so `day_of_week` is 0=Sunday,
  1=Monday, ..., 6=Saturday.
  """
  fun apply(seconds: I64): String =>
    let date = PosixDate(seconds)

    // tm_wday: 0=Sunday, 1=Monday, ..., 6=Saturday
    let days = ["Sun"; "Mon"; "Tue"; "Wed"; "Thu"; "Fri"; "Sat"]
    // PosixDate.month is 1-indexed
    let months = [
      "Jan"; "Feb"; "Mar"; "Apr"; "May"; "Jun"
      "Jul"; "Aug"; "Sep"; "Oct"; "Nov"; "Dec"
    ]

    let day_name = try
      days(date.day_of_week.usize())?
    else
      _Unreachable()
      ""
    end

    let month_name = try
      months((date.month - 1).usize())?
    else
      _Unreachable()
      ""
    end

    let day_str = _pad(date.day_of_month)
    let hour_str = _pad(date.hour)
    let min_str = _pad(date.min)
    let sec_str = _pad(date.sec)

    recover val
      String(29)
        .>append(day_name)
        .>append(", ")
        .>append(day_str)
        .>push(' ')
        .>append(month_name)
        .>push(' ')
        .>append(date.year.string())
        .>push(' ')
        .>append(hour_str)
        .>push(':')
        .>append(min_str)
        .>push(':')
        .>append(sec_str)
        .>append(" GMT")
    end

  fun _pad(value: I32): String =>
    if value < 10 then
      "0" + value.string()
    else
      value.string()
    end
