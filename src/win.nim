import os

import winim/inc/[windef, winbase, winuser], winim/winstr

import "."/globals

type
  WinState = object
    editor: HWND
    command: HWND

var
  gWin: WinState

proc createWindows*() =
  gWin.editor = CreateWindow("Scintilla", "", WS_OVERLAPPEDWINDOW, 10, 10, 800, 600, 0, 0, GetModuleHandleW(nil), nil)
  gWin.command = CreateWindow("Scintilla", "", WS_OVERLAPPED, 10, 610, 800, 180, gWin.editor, 0, GetModuleHandleW(nil), nil)

  if gWin.editor.IsWindow() == 0 or gWin.command.IsWindow() == 0:
    raise newException(Exception, "IsWindow() failed with " & $GetLastError())

  discard gWin.editor.ShowWindow(SW_SHOW)
  discard gWin.command.ShowWindow(SW_SHOW)

  if gWin.editor.UpdateWindow() == 0 or gWin.command.UpdateWindow() == 0:
    raise newException(Exception, "UpdateWindow() failed with " & $GetLastError())

proc eMsg*(msgID: int, wparam: pointer = nil, lparam: pointer = nil): int {.discardable.} =
  return gWin.editor.SendMessage(cast[UINT](msgID), cast[WPARAM](wparam), cast[LPARAM](lparam))

proc cMsg*(msgID: int, wparam: pointer = nil, lparam: pointer = nil): int {.discardable.} =
  return gWin.command.SendMessage(cast[UINT](msgID), cast[WPARAM](wparam), cast[LPARAM](lparam))

proc messageLoop*(commandCallback: Callback, pluginCallback: Callback, ctx: var Ctx) =
  var
    msg: MSG
    lpmsg = cast[LPMSG](addr msg)

  while gWin.editor.IsWindow() != 0:
    while PeekMessageW(lpmsg, 0, 0, 0, PM_REMOVE) > 0:
      if msg.hwnd == gWin.command and msg.message == WM_KEYDOWN:
        if msg.wparam == VK_RETURN:
          ctx.commandCallback()
      discard TranslateMessage(addr msg)
      discard DispatchMessageW(addr msg)

      ctx.pluginCallback()

    sleep(10)

proc setEditorTitle*(title: string) =
  gWin.editor.SetWindowText(title.newWideCString)

proc setCommandTitle*(title: string) =
  gWin.command.SetWindowText(title.newWideCString)

proc exitWindow*() =
  gWin.editor.DestroyWindow()