const VKTable = {
  "F1": 112, "F2": 113, "F3": 114, "F4": 115, "F5": 116, "F6": 117, "F7": 118, "F8": 119, "F9": 120, "F10": 121,
  "F11": 122, "F12": 123, "F13": 124, "F14": 125, "F15": 126, "F16": 127, "F17": 128, "F18": 129, "F19": 130, "F20": 131,
  "F21": 132, "F22": 133, "F23": 134, "F24": 135, "Tab": 9, "PgDn": 34, "PgUp": 35, "Home": 36, "End": 35
}.toTable()

proc hotkey(plg: var Plugin) {.feudCallback.} =
  var
    windows = plg.getWindows()
  if plg.ctx.cmdParam.len == 0:
    var hout = ""

    for hotkey in windows.hotkeys.keys():
      hout &= windows.hotkeys[hotkey].hotkey & " = " & windows.hotkeys[hotkey].callback & "\n"

    if hout.len != 0:
      plg.ctx.notify(plg.ctx, hout[0 .. ^2])
  else:
    for param in plg.getParam():
      let
        (hotkey, val) = param.splitCmd()

      var
        global = false
        fsModifiers: UINT
        vk: char
        spec = ""
        id = 0
        ret = 0

      for i in 0 .. hotkey.len-1:
        case hotkey[i]:
          of '*':
            global = true
          of '#':
            fsModifiers = fsModifiers or MOD_WIN
          of '^':
            fsModifiers = fsModifiers or MOD_CONTROL
          of '!':
            fsModifiers = fsModifiers or MOD_ALT
          of '+':
            fsModifiers = fsModifiers or MOD_SHIFT
          else:
            if spec.len != 0 or i != hotkey.len-1:
              spec &= hotkey[i]
            else:
              vk = hotkey[i].toUpperAscii

      if spec.len != 0:
        if VKTable.hasKey(spec):
          vk = VKTable[spec].char
        else:
          plg.ctx.notify(plg.ctx, strformat.`&`("Invalid key '{spec}' specified for hotkey"))
          return

      id = fsModifiers or (vk.int shl 8)

      if val.len != 0:
        ret =
          if global:
            RegisterHotKey(0, id.int32, fsModifiers or MOD_NOREPEAT, vk.UINT)
          else:
            1

        if ret != 1:
          plg.ctx.notify(plg.ctx, strformat.`&`("Failed to register hotkey {hotkey}"))
        else:
          windows.hotkeys[id] = (hotkey, val)
      else:
        ret =
          if global:
            UnregisterHotKey(0, id.int32)
          else:
            1

        if ret != 1:
          plg.ctx.notify(plg.ctx, strformat.`&`("Failed to unregister hotkey {hotkey}"))
        else:
          windows.hotkeys.del(id)