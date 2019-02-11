import cligen

when defined(Windows):
  import "src"/sci

proc main(
    remote: bool = false,
  ) =
 feudStart(remote)

when isMainModule:
  dispatch(main, help = {
    "remote": "Allow remote connections",
  }, short = {
    "remote": 'r',
  })
