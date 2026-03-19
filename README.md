# icuwebview

A lightweight Rust DLL that lets you open a native webview window from **any language** that can call C-compatible DLLs. Ships with first-class Odin bindings.

Built on [wry](https://github.com/tauri-apps/wry) + [tao](https://github.com/tauri-apps/tao). Communication between your native code and the page's JavaScript happens over a tiny local HTTP server — no IPC bridge, no `postMessage`, just plain `fetch()`.

---

## Quick Start (Odin)

Below is a complete working example. It opens a window, binds four Odin callbacks to JavaScript, loads an HTML page, and runs the event loop.

```odin
package main

import "core:fmt"
import "core:strings"
import "base:runtime"
import ui "icuwebview"

// App holds whatever state your callbacks need to share.
App :: struct {
    counter: int,
    name:    string,
}

HTML :: `<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <title>Odin App</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: system-ui, sans-serif;
      background: #0f0f0f; color: #e8e8e8;
      height: 100vh; display: flex; flex-direction: column;
      align-items: center; justify-content: center; gap: 12px;
    }
    h1 { font-size: 1.8rem; margin-bottom: 4px; }
    p  { color: #888; font-size: 0.9rem; margin-bottom: 8px; }
    input {
      width: 280px; padding: 9px 14px; font-size: 1rem;
      border-radius: 8px; border: 1px solid #333;
      background: #1a1a1a; color: #eee; outline: none;
    }
    input:focus { border-color: #5a7fff; }
    .row { display: flex; gap: 8px; }
    button {
      padding: 9px 20px; font-size: 0.95rem; border-radius: 8px;
      border: none; background: #4a6fdc; color: #fff; cursor: pointer;
    }
    button:hover { background: #3a5fc8; }
    button.danger { background: #c0392b; }
    button.danger:hover { background: #a93226; }
    #output {
      margin-top: 8px; padding: 10px 18px; background: #1a1a1a;
      border-radius: 8px; color: #7effa0; font-size: 1rem;
      min-width: 280px; text-align: center; min-height: 42px;
    }
  </style>
</head>
<body>
  <h1>Hello from Odin 👋</h1>
  <p>Powered by Rust + wry</p>
  <input id="nameInput" type="text" placeholder="Enter your name..." />
  <div class="row">
    <button onclick="do_greet()">Greet</button>
    <button onclick="do_count()">Count</button>
    <button onclick="do_reset()">Reset</button>
    <button class="danger" onclick="do_quit()">Quit</button>
  </div>
  <div id="output">—</div>
  <script>
    const out = document.getElementById("output")

    async function do_greet() {
      const name = document.getElementById("nameInput").value.trim()
      if (!name) { out.textContent = "Enter a name first!"; return }
      // Call the Odin "greet" callback. Returns a Promise that resolves
      // once Odin calls return_val(seq, ...) on the other side.
      out.textContent = await window._icu.greet(name)
    }

    async function do_count() {
      out.textContent = "Counter: " + await window._icu.increment()
    }

    async function do_reset() {
      await window._icu.reset_counter()
      out.textContent = "Counter reset to 0"
    }

    async function do_quit() {
      out.textContent = "Goodbye!"
      await window._icu.close()
    }
  </script>
</body>
</html>`

// ── Helpers ───────────────────────────────────────────────────────────────────

// JS passes arguments as a JSON array, e.g. ["Alice"].
// This strips the brackets and quotes to give you the plain first string.
parse_first_string :: proc(req: cstring) -> string {
    raw := string(req)
    raw  = strings.trim_space(raw)
    raw  = strings.trim_prefix(raw, "[")
    raw  = strings.trim_suffix(raw, "]")
    raw  = strings.trim_space(raw)
    raw  = strings.trim(raw, "\"")
    return raw
}

// ── Callbacks ─────────────────────────────────────────────────────────────────
// Rules:
//   1. Must use the "c" calling convention.
//   2. Set context = runtime.default_context() so Odin's allocators work inside.
//   3. Always call ui.return_val(seq, <json>) before returning — this resolves
//      the JS Promise. If you forget, the fetch hangs for 10 seconds then
//      returns null.

greet_cb :: proc "c" (seq, req: cstring, arg: rawptr) {
    context = runtime.default_context()
    app     := (^App)(arg)
    name    := parse_first_string(req)
    app.name = name
    app.counter += 1

    // Strings returned to JS must be JSON-encoded — fmt.ctprintf(%q, ...) does that.
    msg := fmt.ctprintf("%q", fmt.tprintf("Hello, %s! Visit #%d", name, app.counter))
    ui.return_val(seq, msg)
}

increment_cb :: proc "c" (seq, req: cstring, arg: rawptr) {
    context = runtime.default_context()
    app     := (^App)(arg)
    app.counter += 1
    // Numbers are returned bare — no quotes needed.
    ui.return_val(seq, fmt.ctprintf("%d", app.counter))
}

reset_cb :: proc "c" (seq, req: cstring, arg: rawptr) {
    context = runtime.default_context()
    app     := (^App)(arg)
    app.counter = 0
    ui.return_val(seq, "true")
}

close_cb :: proc "c" (seq, req: cstring, arg: rawptr) {
    context = runtime.default_context()
    ui.return_val(seq, "true")
    ui.terminate()  // Signals the event loop to exit
}

// ── Main ──────────────────────────────────────────────────────────────────────

main :: proc() {
    // create() loads icuwebview.dll automatically on the first call.
    // Pass true to enable DevTools (right-click → Inspect in the window).
    w := ui.create(true)
    if w == nil {
        fmt.eprintln("ERROR: failed to create webview")
        return
    }
    defer ui.destroy()

    app := App{}

    // Configure the window before loading content.
    ui.set_title("My Odin App")
    ui.set_size(520, 400)
    ui.set_position(300, 200)
    ui.set_resizable(false)

    // Bind JS function names to Odin callbacks.
    // Important: bind() must be called BEFORE set_html() so the JS shims
    // are injected before the page scripts run.
    // The third argument is a rawptr passed to your callback as `arg`.
    ui.bind("greet",         greet_cb,     &app)
    ui.bind("increment",     increment_cb, &app)
    ui.bind("reset_counter", reset_cb,     &app)
    ui.bind("close",         close_cb,     nil)

    // Load the UI. After this, JS can call window._icu.greet("Alice") etc.
    ui.set_html(HTML)

    // Blocks until the window is closed or terminate() is called.
    ui.run()

    fmt.println("closed — counter:", app.counter, "| last name:", app.name)
}
```

### How binding works

When you call `ui.bind("greet", greet_cb, &app)`, icuwebview:

1. Registers `greet_cb` in a lookup table inside the Rust server.
2. Injects a small JavaScript shim that defines `window._icu.greet`:
   ```js
   window._icu.greet = function(...args) {
       return fetch("http://127.0.0.1:<port>/call/greet/<seq>", {
           method: "POST", body: JSON.stringify(args)
       }).then(r => r.json());
   };
   ```
3. When JS calls `window._icu.greet("Alice")`, it POSTs to the local server.
4. The server spawns a thread, calls `greet_cb(seq, "[\"Alice\"]", arg)`.
5. Your callback calls `ui.return_val(seq, "\"Hello, Alice!\"")`.
6. The server responds to the fetch with that JSON value.
7. The JS Promise resolves with `"Hello, Alice!"`.

Calls are fully concurrent — each one runs on its own thread, so spamming a button never queues up.

---

## Multiple Windows

Every function that takes an optional webview handle will default to the **first window created** when that argument is omitted. To target a specific window, pass its handle as the last argument.

```odin
w1 := ui.create(false)
w2 := ui.create(false)

// No handle — targets w1 (the first one created)
ui.set_title("First Window")

// Explicit handle — targets w2
ui.set_title("Second Window", w2)

ui.set_html(html1)       // → w1
ui.set_html(html2, w2)   // → w2

ui.run(w1)  // Blocks until w1 closes
ui.run(w2)  // Then blocks until w2 closes
```

This applies to every function in the API — `set_size`, `set_html`, `bind`, `eval`, `terminate`, and so on.

---

## Strings

All functions that accept text take a plain Odin `string` — no casting or manual conversion needed:

```odin
ui.set_title("My App")
ui.set_html(my_html_string)
ui.navigate("https://example.com")
ui.bind("greet", greet_cb)
ui.eval(`document.body.style.background = "#111"`)
```

The binding layer converts to `cstring` internally using the temp allocator before passing to the DLL. This is effectively free — a bump-pointer allocation plus a memcpy — and is completely invisible to the call site.

The two exceptions that still use `cstring` are intentional:
- `return_val(seq, result)` — `seq` arrives from a C callback parameter and goes straight back to the DLL; `result` is typically produced by `fmt.ctprintf` which already returns a `cstring`.
- `free_string(s)` — receives a pointer allocated by the DLL itself.

---

## API Reference

### Lifecycle

#### `create(debug: bool, window: rawptr = nil) -> webview`
Creates a new webview window and returns its handle. Pass `true` for `debug` to enable DevTools (right-click → Inspect). The first call also sets the global default handle used by all functions when no handle is provided. On the first call, the DLL is loaded automatically unless you've called `load()` yourself.

#### `destroy(w: webview = nil) -> Error`
Destroys the webview and frees its resources. If the data directory was ephemeral (default), it is deleted. Call this after `run()` returns — typically via `defer ui.destroy()`.

#### `run(w: webview = nil) -> Error`
Starts the event loop. **Blocks** until the window is closed or `terminate()` is called. Must be called on the main thread. Call this last, after all your `bind()` and `set_html()` calls.

#### `terminate(w: webview = nil) -> Error`
Signals the event loop to exit. Safe to call from any thread, including from inside a bind callback.

---

### Window

#### `set_title(title: string, w: webview = nil) -> Error`
Sets the window's title bar text.

#### `set_size(width, height: c.int, hints: Hint = .None, w: webview = nil) -> Error`
Resizes the window. The `hints` argument controls behaviour:
- `.None` — free resize, sets current size
- `.Min` — sets minimum size
- `.Max` — sets maximum size
- `.Fixed` — sets size and disables resizing

#### `set_position(x, y: c.int, w: webview = nil) -> Error`
#### `set_position(pos: [2]c.int, w: webview = nil) -> Error`
Moves the window to the given screen coordinates (in physical pixels). Accepts either two separate integers or a corner from `get_corners()`:

```odin
// Plain coordinates
ui.set_position(300, 200)

// Screen corners
corners := ui.get_corners(520, 400)  // pass your window dimensions
ui.set_position(corners.TopLeft)
ui.set_position(corners.TopRight)
ui.set_position(corners.BottomLeft)
ui.set_position(corners.BottomRight)
```

#### `get_corners(win_width, win_height: c.int) -> Corners`
Returns a `Corners` struct containing the four screen-edge positions for a window of the given size. Uses `GetSystemMetrics` to query the current screen resolution. The `Corners` struct has four fields — `TopLeft`, `TopRight`, `BottomLeft`, `BottomRight` — each a `[2]c.int` of `{x, y}`.

#### `set_resizable(resizable: bool, w: webview = nil) -> Error`
Enables or disables the user's ability to resize the window.

#### `set_frameless(frameless: bool, w: webview = nil) -> Error`
Removes or restores the window's title bar and border decorations.

#### `set_timeout(seconds: u32, w: webview = nil) -> Error`
Auto-closes the window after the given number of seconds. Pass `0` to disable.

#### `show(w: webview = nil) -> Error`
Makes the window visible.

#### `hide(w: webview = nil) -> Error`
Hides the window without destroying it.

#### `get_hwnd(w: webview = nil) -> int`
Returns the Win32 `HWND` as an integer. Cast it with `transmute(windows.HWND)(ui.get_hwnd())`.

#### `get_window(w: webview = nil) -> rawptr`
Returns the raw `HWND` as a `rawptr`.

#### `get_native_handle(kind: Native_Handle_Kind, w: webview = nil) -> rawptr`
Returns a platform-specific handle. Currently `.Ui_Window` returns the `HWND`.

---

### Content

#### `navigate(url: string, w: webview = nil) -> Error`
Navigates the webview to a URL (e.g. `"https://example.com"` or `"file:///C:/page.html"`).

#### `set_html(html: string, w: webview = nil) -> Error`
Loads a raw HTML string directly. Always call `bind()` before `set_html()` — bind shims are re-injected automatically after each load, but they must be registered first.

#### `eval(js: string, w: webview = nil) -> Error`
Evaluates a JavaScript string in the webview, fire-and-forget. Use this to push data from Odin into the page at any time.

#### `eval(js: string, w: webview = nil) -> Error`
Evaluates a JavaScript string in the webview, fire-and-forget. Use this to push data from Odin into the page at any time.

#### `eval_result(js: string, w: webview = nil) -> string`
Evaluates a JavaScript expression and blocks until the result comes back. The expression can use `await`. Returns a JSON-encoded Odin `string` — no manual memory management needed.

```odin
title  := ui.eval_result("document.title")        // → "My Odin App"
count  := ui.eval_result("window._icu_counter")   // → "42"
exists := ui.eval_result("typeof window.myFn")    // → ""function""
```

#### `init(js: string, w: webview = nil) -> Error`
Evaluates a JavaScript string immediately. Intended for one-off injections; for persistent init scripts use `with_initialization_script` at the Rust level.

---

### Binding (Odin ↔ JS)

#### `bind(name: string, fn: proc "c"(seq, req: cstring, arg: rawptr), arg: rawptr = nil, w: webview = nil) -> Error`
Binds a JS function name to an Odin callback. After binding, JS can call `window._icu.<name>(args...)` and receive a Promise that resolves when you call `return_val`.

Callback signature:
```odin
my_cb :: proc "c" (seq, req: cstring, arg: rawptr) {
    context = runtime.default_context()
    // seq  — opaque sequence id, pass it back to return_val unchanged
    // req  — JSON array of arguments from JS, e.g. ["Alice", 42]
    // arg  — the rawptr you passed as the third argument to bind()
    ui.return_val(seq, "\"result\"")
}
```

Returns `.Duplicate` if a binding with that name already exists.

#### `unbind(name: string, w: webview = nil) -> Error`
Removes a binding. The JS-side function is deleted from `window._icu`. Returns `.Not_Found` if no binding with that name exists.

#### `return_val(seq: cstring, result: cstring, status: c.int = 0, w: webview = nil) -> Error`
Resolves (or rejects) the JS Promise created by a `window._icu.<name>(...)` call.

- `seq` — pass back the exact `seq` received in your callback, unchanged.
- `result` — a JSON-encoded value: `"\"hello\""`, `"42"`, `"true"`, `"null"`, `"[1,2,3]"`, `"{\"key\":\"val\"}"`, etc.
- `status` — `0` resolves the Promise with `result`; any other value rejects it with `{"error": <result>}`.

You **must** call this inside every bind callback, or the corresponding JS `fetch` will hang for 10 seconds and then resolve to `null`.

---

### Utilities

#### `dispatch(fn: proc "c"(w: webview, arg: rawptr), arg: rawptr, w: webview = nil) -> Error`
Calls a function synchronously with the webview handle and an arbitrary pointer. Useful for bridging with code that expects a C-style callback.

#### `wait_until_closed()`
Blocks the calling thread until the window is closed. Use this when `run()` is on a background thread and you need the main thread to wait.

#### `set_data_dir(path: string)`
Sets the directory used for persistent browser data (cookies, cache, localStorage). Must be called **before** `create()`. Pass `nil` to revert to the default behaviour, which uses a temporary directory that is deleted when `destroy()` is called.

#### `free_string(s: cstring)`
Frees a C string that was allocated by the DLL. Not needed for normal usage — only relevant if you extend the Rust side to return heap-allocated strings.

---

### DLL Loading

#### `load() -> bool`
Extracts `icuwebview.dll` (embedded in the Odin binary via `#load`) to `%TEMP%` and loads it. Called automatically by `create()` on the first use. Returns `false` if loading fails.

#### `load_from(path: string) -> bool`
Loads the DLL from a specific path. Use this if you want to control where the DLL lives (e.g. next to your executable). Call before `create()`.

#### `unload()`
Unloads the DLL. Optional — the OS cleans up on process exit.

---

### Error Values

| Value | Meaning |
|---|---|
| `.Ok` | Success |
| `.Duplicate` | A binding with that name already exists |
| `.Not_Found` | Binding or pending call not found |
| `.Invalid_Argument` | Null or invalid webview handle |
| `.Invalid_State` | Event loop not available (e.g. `run()` called twice) |
| `.Unspecified` | DLL function pointer is nil (DLL not loaded) |
| `.Missing_Dependency` | A required system dependency is missing |
| `.Canceled` | Operation was canceled |

---

## Using from Other Languages

icuwebview exports a plain C ABI, so it can be loaded from **any language** that can call into a Windows DLL — Python (`ctypes`), C/C++, Zig, Nim, Go (`syscall`), Rust (`libloading`), etc.

The Odin binding file `icuwebview.odin` is a useful reference for the exact function signatures, argument order, and type layout:

```odin
// Types
webview :: rawptr   // opaque handle returned by create()

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

// Exported function signatures (C ABI):
//
//   webview  create(bool debug, void* window)
//   Error    destroy(webview w)
//   Error    run(webview w)
//   Error    terminate(webview w)
//   Error    set_title(char* title, webview w)
//   Error    set_size(int width, int height, Hint hints, webview w)
//   Error    set_position(int x, int y, webview w)
//   Error    set_resizable(bool resizable, webview w)
//   Error    set_frameless(bool frameless, webview w)
//   Error    set_timeout(uint32 seconds, webview w)
//   Error    show(webview w)
//   Error    hide(webview w)
//   Error    navigate(char* url, webview w)
//   Error    set_html(char* html, webview w)
//   Error    eval(char* js, webview w)
//   Error    init(char* js, webview w)
//   Error    webview_bind(char* name, BindFn cb, void* arg, webview w)
//   Error    unbind(char* name, webview w)
//   Error    return_val(char* seq, char* result, int status, webview w)
//   void     wait_until_closed()
//   void     set_data_dir(char* path)
//   void     free_string(char* s)
//   void*    get_window(webview w)
//   intptr   get_hwnd(webview w)
//
// BindFn callback type (passed to webview_bind):
//   void callback(char* seq, char* req, void* arg)
//
// Note: the bind function is exported as "webview_bind" (not "bind")
// to avoid a name clash with the Winsock system symbol.
//
// All char* strings are UTF-8. Strings passed INTO the DLL do not need
// to be freed. Strings returned FROM the DLL (if any) should be freed
// with free_string().
```

### Python example (ctypes)

```python
import ctypes, json

lib = ctypes.WinDLL("icuwebview.dll")

lib.create.restype  = ctypes.c_void_p
lib.create.argtypes = [ctypes.c_bool, ctypes.c_void_p]

lib.set_title.argtypes = [ctypes.c_char_p, ctypes.c_void_p]
lib.set_html.argtypes  = [ctypes.c_char_p, ctypes.c_void_p]
lib.run.argtypes       = [ctypes.c_void_p]

BIND_FN = ctypes.CFUNCTYPE(None, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_void_p)

lib.webview_bind.argtypes = [ctypes.c_char_p, BIND_FN, ctypes.c_void_p, ctypes.c_void_p]
lib.return_val.argtypes   = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_int, ctypes.c_void_p]

def on_hello(seq, req, arg):
    args = json.loads(req)
    result = json.dumps(f"Hello from Python, {args[0]}!")
    lib.return_val(seq, result.encode(), 0, None)

cb = BIND_FN(on_hello)  # keep a reference so it isn't GC'd

w = lib.create(False, None)
lib.set_title(b"Python App", None)
lib.webview_bind(b"hello", cb, None, None)
lib.set_html(b'<button onclick="window._icu.hello(\'world\').then(r=>alert(r))">Click</button>', None)
lib.run(None)
```
