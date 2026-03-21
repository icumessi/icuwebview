// icuwebview.odin - dynamic loader for icuwebview.dll
package icuwebview

import "core:c"
import "core:os"
import "core:fmt"
import "core:strings"
import "core:sys/windows"

// ── Types ─────────────────────────────────────────────────────────────────────

webview :: rawptr

Error :: enum c.int {
    Missing_Dependency = -5,
    Canceled           = -4,
    Invalid_State      = -3,
    Invalid_Argument   = -2,
    Unspecified        = -1,
    Ok                 = 0,
    Duplicate          = 1,
    Not_Found          = 2,
}

Hint :: enum c.int {
    None  = 0,
    Min   = 1,
    Max   = 2,
    Fixed = 3,
}

Native_Handle_Kind :: enum c.int {
    Ui_Window          = 0,
    Browser_Controller = 1,
}

// ── Corners ───────────────────────────────────────────────────────────────────

Corners :: struct {
    TopLeft:     [2]c.int,
    TopRight:    [2]c.int,
    BottomLeft:  [2]c.int,
    BottomRight: [2]c.int,
}

// Returns a Corners struct with screen-edge positions for a window of the
// given size. Pass your width and height (same values you gave set_size).
//
// Example:
//   corners := ui.get_corners(520, 400) // these would be the values you used in set_size
//   ui.set_position(corners.TopRight)
get_corners :: proc(win_width, win_height: c.int) -> Corners {
    screen_w := windows.GetSystemMetrics(windows.SM_CXSCREEN)
    screen_h := windows.GetSystemMetrics(windows.SM_CYSCREEN)
    right  := c.int(screen_w) - win_width
    bottom := c.int(screen_h) - win_height
    return Corners {
        TopLeft     = {0,     0},
        TopRight    = {right, 0},
        BottomLeft  = {0,     bottom},
        BottomRight = {right, bottom},
    }
}

// ── String helper ─────────────────────────────────────────────────────────────

@(private)
_s :: #force_inline proc(s: string) -> cstring {
    return strings.clone_to_cstring(s, context.temp_allocator)
}

// ── Internal ──────────────────────────────────────────────────────────────────

@(private) _dll: windows.HMODULE

@(private) _fn :: proc(name: cstring) -> rawptr {
    p := windows.GetProcAddress(_dll, name)
    if p == nil do fmt.eprintln("[icuwebview] missing symbol:", name)
    return p
}

// ── Function pointer types ────────────────────────────────────────────────────

@(private) Fn_free_string        :: #type proc "c" (s: cstring)
@(private) Fn_set_data_dir       :: #type proc "c" (path: cstring)
@(private) Fn_create             :: #type proc "c" (debug: bool, window: rawptr) -> webview
@(private) Fn_destroy            :: #type proc "c" (w: webview) -> Error
@(private) Fn_run                :: #type proc "c" (w: webview) -> Error
@(private) Fn_terminate          :: #type proc "c" (w: webview) -> Error
@(private) Fn_dispatch           :: #type proc "c" (fn: proc "c"(w: webview, arg: rawptr), arg: rawptr, w: webview) -> Error
@(private) Fn_get_window         :: #type proc "c" (w: webview) -> rawptr
@(private) Fn_get_native_handle  :: #type proc "c" (kind: Native_Handle_Kind, w: webview) -> rawptr
@(private) Fn_get_hwnd           :: #type proc "c" (w: webview) -> int
@(private) Fn_set_title          :: #type proc "c" (title: cstring, w: webview) -> Error
@(private) Fn_set_size           :: #type proc "c" (width, height: c.int, hints: Hint, w: webview) -> Error
@(private) Fn_set_position       :: #type proc "c" (x, y: c.int, w: webview) -> Error
@(private) Fn_set_resizable      :: #type proc "c" (resizable: bool, w: webview) -> Error
@(private) Fn_set_frameless      :: #type proc "c" (frameless: bool, w: webview) -> Error
@(private) Fn_set_timeout        :: #type proc "c" (seconds: u32, w: webview) -> Error
@(private) Fn_show               :: #type proc "c" (w: webview) -> Error
@(private) Fn_hide               :: #type proc "c" (w: webview) -> Error
@(private) Fn_navigate           :: #type proc "c" (url: cstring, w: webview) -> Error
@(private) Fn_set_html           :: #type proc "c" (html: cstring, w: webview) -> Error
@(private) Fn_init               :: #type proc "c" (js: cstring, w: webview) -> Error
@(private) Fn_eval               :: #type proc "c" (js: cstring, w: webview) -> Error
@(private) Fn_eval_result        :: #type proc "c" (js: cstring, w: webview) -> cstring
@(private) Fn_bind               :: #type proc "c" (name: cstring, fn: proc "c"(seq, req: cstring, arg: rawptr), arg: rawptr, w: webview) -> Error
@(private) Fn_unbind             :: #type proc "c" (name: cstring, w: webview) -> Error
@(private) Fn_return_val         :: #type proc "c" (seq: cstring, result: cstring, status: c.int, w: webview) -> Error
@(private) Fn_set_swipe_navigation :: #type proc "c" (enabled: bool, w: webview) -> Error
@(private) Fn_wait_for_page_load   :: #type proc "c" (timeout_ms: u32, w: webview) -> bool
@(private) Fn_is_visible         :: #type proc "c" (w: webview) -> bool
@(private) Fn_is_running         :: #type proc "c" () -> bool
@(private) Fn_wait_until_closed  :: #type proc "c" ()

// ── Loaded pointers ───────────────────────────────────────────────────────────

@(private) _free_string:         Fn_free_string
@(private) _set_data_dir:        Fn_set_data_dir
@(private) _create:              Fn_create
@(private) _destroy:             Fn_destroy
@(private) _run:                 Fn_run
@(private) _terminate:           Fn_terminate
@(private) _dispatch:            Fn_dispatch
@(private) _get_window:          Fn_get_window
@(private) _get_native_handle:   Fn_get_native_handle
@(private) _get_hwnd:            Fn_get_hwnd
@(private) _set_title:           Fn_set_title
@(private) _set_size:            Fn_set_size
@(private) _set_position:        Fn_set_position
@(private) _set_resizable:       Fn_set_resizable
@(private) _set_frameless:       Fn_set_frameless
@(private) _set_timeout:         Fn_set_timeout
@(private) _show:                Fn_show
@(private) _hide:                Fn_hide
@(private) _navigate:            Fn_navigate
@(private) _set_html:            Fn_set_html
@(private) _init:                Fn_init
@(private) _eval:                Fn_eval
@(private) _eval_result:         Fn_eval_result
@(private) _bind:                Fn_bind
@(private) _unbind:              Fn_unbind
@(private) _return_val:          Fn_return_val
@(private) _set_swipe_navigation: Fn_set_swipe_navigation
@(private) _wait_for_page_load:   Fn_wait_for_page_load
@(private) _is_visible:          Fn_is_visible
@(private) _is_running:          Fn_is_running
@(private) _wait_until_closed:   Fn_wait_until_closed

// ── load / load_from / unload ─────────────────────────────────────────────────

// Fyi, if ur changing the path of the .dll, then you should change the path below
icuwebview_dll_bytes :: #load("./icuwebview.dll")
webviewLoaded : bool = false

load :: proc() -> bool {
    tmp := fmt.tprintf("%s\\icuwebview.dll", os.get_env("TEMP"))
    if !os.exists(tmp) do os.remove(tmp)
    // rewrite for future updates
    os.write_entire_file(tmp, icuwebview_dll_bytes)
    return load_from(tmp)
}

load_from :: proc(path: string) -> bool {
    _dll = windows.LoadLibraryW(windows.utf8_to_wstring(path))
    if _dll == nil {
        fmt.eprintln("[icuwebview] failed to load:", path)
        return false
    }

    _free_string        = auto_cast _fn("free_string")
    _set_data_dir       = auto_cast _fn("set_data_dir")
    _create             = auto_cast _fn("create")
    _destroy            = auto_cast _fn("destroy")
    _run                = auto_cast _fn("run")
    _terminate          = auto_cast _fn("terminate")
    _dispatch           = auto_cast _fn("dispatch")
    _get_window         = auto_cast _fn("get_window")
    _get_native_handle  = auto_cast _fn("get_native_handle")
    _get_hwnd           = auto_cast _fn("get_hwnd")
    _set_title          = auto_cast _fn("set_title")
    _set_size           = auto_cast _fn("set_size")
    _set_position       = auto_cast _fn("set_position")
    _set_resizable      = auto_cast _fn("set_resizable")
    _set_frameless      = auto_cast _fn("set_frameless")
    _set_timeout        = auto_cast _fn("set_timeout")
    _show               = auto_cast _fn("show")
    _hide               = auto_cast _fn("hide")
    _navigate           = auto_cast _fn("navigate")
    _set_html           = auto_cast _fn("set_html")
    _init               = auto_cast _fn("init")
    _eval               = auto_cast _fn("eval")
    _eval_result        = auto_cast _fn("eval_result")
    _bind               = auto_cast _fn("webview_bind")  // exported as webview_bind (Winsock clash)
    _unbind             = auto_cast _fn("unbind")
    _return_val         = auto_cast _fn("return_val")
    _set_swipe_navigation = auto_cast _fn("set_swipe_navigation")
    _wait_for_page_load   = auto_cast _fn("wait_for_page_load")
    _is_visible         = auto_cast _fn("is_visible")
    _is_running         = auto_cast _fn("is_running")
    _wait_until_closed  = auto_cast _fn("wait_until_closed")

    return true
}

unload :: proc() {
    if _dll != nil {
        windows.FreeLibrary(_dll)
        _dll = nil
    }
}

// ── Public API ────────────────────────────────────────────────────────────────

free_string :: proc(s: cstring) {
    if _free_string != nil do _free_string(s)
}

set_data_dir :: proc(path: string) {
    if _set_data_dir != nil do _set_data_dir(_s(path))
}

create :: proc(debug: bool, window: rawptr = nil, dontAutoLoad : bool = false) -> webview {
    if !webviewLoaded {
        if dontAutoLoad {
            fmt.eprintf("[icuwebview] - Please make sure .load is called!")
            return nil
        } else {
            result := load()
            if !result {
                fmt.eprintf("[icuwebview] - Failed to load .dll module, please make sure it exist!")
                return nil
            }
        }
    }
    if _create == nil do return nil
    return _create(debug, window)
}

destroy :: proc(w: webview = nil) -> Error {
    if _destroy == nil do return .Unspecified
    return _destroy(w)
}

run :: proc(w: webview = nil) -> Error {
    if _run == nil do return .Unspecified
    return _run(w)
}

terminate :: proc(w: webview = nil) -> Error {
    if _terminate == nil do return .Unspecified
    return _terminate(w)
}

dispatch :: proc(fn: proc "c"(w: webview, arg: rawptr), arg: rawptr, w: webview = nil) -> Error {
    if _dispatch == nil do return .Unspecified
    return _dispatch(fn, arg, w)
}

get_window :: proc(w: webview = nil) -> rawptr {
    if _get_window == nil do return nil
    return _get_window(w)
}

get_native_handle :: proc(kind: Native_Handle_Kind, w: webview = nil) -> rawptr {
    if _get_native_handle == nil do return nil
    return _get_native_handle(kind, w)
}

get_hwnd :: proc(w: webview = nil) -> int {
    if _get_hwnd == nil do return 0
    return _get_hwnd(w)
}

set_title :: proc(title: string, w: webview = nil) -> Error {
    if _set_title == nil do return .Unspecified
    return _set_title(_s(title), w)
}

set_size :: proc(width, height: c.int, hints: Hint = .None, w: webview = nil) -> Error {
    if _set_size == nil do return .Unspecified
    return _set_size(width, height, hints, w)
}

// set_position accepts either two ints or a corner from get_corners():
//   ui.set_position(100, 200)
//   ui.set_position(corners.BottomRight)
set_position :: proc { _set_position_xy, _set_position_corner }

_set_position_xy :: proc(x, y: c.int, w: webview = nil) -> Error {
    if _set_position == nil do return .Unspecified
    return _set_position(x, y, w)
}

_set_position_corner :: proc(pos: [2]c.int, w: webview = nil) -> Error {
    if _set_position == nil do return .Unspecified
    return _set_position(pos[0], pos[1], w)
}

set_resizable :: proc(resizable: bool, w: webview = nil) -> Error {
    if _set_resizable == nil do return .Unspecified
    return _set_resizable(resizable, w)
}

set_frameless :: proc(frameless: bool, w: webview = nil) -> Error {
    if _set_frameless == nil do return .Unspecified
    return _set_frameless(frameless, w)
}

set_timeout :: proc(seconds: u32, w: webview = nil) -> Error {
    if _set_timeout == nil do return .Unspecified
    return _set_timeout(seconds, w)
}

show :: proc(w: webview = nil) -> Error {
    if _show == nil do return .Unspecified
    return _show(w)
}

hide :: proc(w: webview = nil) -> Error {
    if _hide == nil do return .Unspecified
    return _hide(w)
}

navigate :: proc(url: string, w: webview = nil) -> Error {
    if _navigate == nil do return .Unspecified
    return _navigate(_s(url), w)
}

set_html :: proc(html: string, w: webview = nil) -> Error {
    if _set_html == nil do return .Unspecified
    return _set_html(_s(html), w)
}

init :: proc(js: string, w: webview = nil) -> Error {
    if _init == nil do return .Unspecified
    return _init(_s(js), w)
}

eval :: proc(js: string, w: webview = nil) -> Error {
    if _eval == nil do return .Unspecified
    return _eval(_s(js), w)
}

// This returns the result as a JSON-encoded Odin string (e.g. "42", "\"hello\"", "null").
// Do NOT call this from inside a bind callback! It's gonna deadlock.
eval_result :: proc(js: string, w: webview = nil) -> string {
    if _eval_result == nil do return ""
    raw := _eval_result(_s(js), w)
    if raw == nil do return ""
    result := strings.clone(string(raw))
    free_string(raw)
    return result
}

// JS calls window._icu.name(args...) -> server calls ur bind -> you must call return_val(seq, ...) to resolve, else it yeilds for 15s or depending on set_timeout
//
//   bind("greet", proc "c"(seq, req: cstring, arg: rawptr) {
//       return_val(seq, "\"Hello!\"")
//   })
bind :: proc(name: string, fn: proc "c"(seq, req: cstring, arg: rawptr), arg: rawptr = nil, w: webview = nil) -> Error {
    if _bind == nil do return .Unspecified
    return _bind(_s(name), fn, arg, w)
}

unbind :: proc(name: string, w: webview = nil) -> Error {
    if _unbind == nil do return .Unspecified
    return _unbind(_s(name), w)
}

// seq    - the sequence id received in your bind callback, pass it back as-is
// result - JSON value: "\"hello\"" / "42" / "true" / "null" / "[1,2,3]"
// status - 0 = resolve (default), if ur returning anything other than 0, it means an error
return_val :: proc(seq: cstring, result: cstring, status: c.int = 0, w: webview = nil) -> Error {
    if _return_val == nil do return .Unspecified
    return _return_val(seq, result, status, w)
}

// Enable or disable the swipe-to-navigate gesture (dragging from the left/right
// screen edge to go back/forward). WebView2 enables this by default.
// Call any time after create().
//
// Example:
//   ui.set_swipe_navigation(false)  // disable — recommended for app-style UIs
//   ui.set_swipe_navigation(true)   // re-enable if you want browser-like behaviour
set_swipe_navigation :: proc(enabled: bool, w: webview = nil) -> Error {
    if _set_swipe_navigation == nil do return .Unspecified
    return _set_swipe_navigation(enabled, w)
}

// Blocks until the page's DOMContentLoaded event fires, or until timeout_ms elapses.
// Call this after set_html() or navigate() to ensure the DOM and all bind shims
//
// Example:
//   ui.set_html(HTML)
//   if !ui.wait_for_page_load() {
//       fmt.eprintln("page load timed out")
//   }
//   ui.eval(`document.getElementById("status").textContent = "Ready!"`)
// timeout_ms - how long to wait in milliseconds (default 5000). Pass 0 to wait forever.
// Do NOT call from inside a bind callback — it will deadlock.
wait_for_page_load :: proc(timeout_ms: u32 = 5000, w: webview = nil) -> bool {
    if _wait_for_page_load == nil do return false
    return _wait_for_page_load(timeout_ms, w)
}

is_visible :: proc(w: webview = nil) -> bool {
    if _is_visible == nil do return false
    return _is_visible(w)
}

is_running :: proc() -> bool {
    if _is_running == nil do return false
    return _is_running()
}

wait_until_closed :: proc() {
    if _wait_until_closed != nil do _wait_until_closed()
}
