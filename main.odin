// By the way, the .dll is already loaded into %TEMP%/embedded into the executable when you build. Check where the load function is called: icuwebview/icuwebview.odin

package main

import "core:fmt"
import "core:strings"
import "base:runtime"
import ui "icuwebview"

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

// ── JSON arg helper ───────────────────────────────────────────────────────────

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

greet_cb :: proc "c" (seq, req: cstring, arg: rawptr) {
    context = runtime.default_context()
    app     := (^App)(arg)
    name    := parse_first_string(req)
    app.name = name
    app.counter += 1

    fmt.println("[odin] greet — name:", name, "visits:", app.counter)

    msg := fmt.ctprintf("%q", fmt.tprintf("Hello, %s! Visit #%d", name, app.counter))
    ui.return_val(seq, msg)
}

increment_cb :: proc "c" (seq, req: cstring, arg: rawptr) {
    context = runtime.default_context()
    app     := (^App)(arg)
    app.counter += 1
    fmt.println("[odin] increment — counter:", app.counter)
    ui.return_val(seq, fmt.ctprintf("%d", app.counter))
}

reset_cb :: proc "c" (seq, req: cstring, arg: rawptr) {
    context = runtime.default_context()
    app     := (^App)(arg)
    app.counter = 0
    fmt.println("[odin] reset")
    ui.return_val(seq, "true")
}

close_cb :: proc "c" (seq, req: cstring, arg: rawptr) {
    context = runtime.default_context()
    fmt.println("[odin] close")
    ui.return_val(seq, "true")
    ui.terminate()
}

// ── Main ──────────────────────────────────────────────────────────────────────

main :: proc() {
    fmt.println("[odin] starting")

    // Verify webview2 is installed
    w := ui.create(false)
    if w == nil {
        fmt.eprintln("[odin] ERROR: Please make sure you have WebView2 Installed: https://developer.microsoft.com/en-us/microsoft-edge/webview2/")
        return
    }

    defer ui.destroy()
    defer ui.run() // since we call this after

    app := App{}

    ui.set_title("My Odin App")
    ui.set_size(520, 400)
    ui.set_position(300, 200)
    ui.set_resizable(false)

    ui.bind("greet",         greet_cb,     &app)
    ui.bind("increment",     increment_cb, &app)
    ui.bind("reset_counter", reset_cb,     &app)
    ui.bind("close",         close_cb,     nil)

    ui.set_html(HTML)

    fmt.println("[odin] window open")
    ui.run()
    fmt.println("[odin] closed — counter:", app.counter, "| last name:", app.name)
}
