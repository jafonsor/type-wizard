// The renderer's JS executor (spec section 5; Haskell side: renderer/src/Renderer*).
//
// It owns the WebGL2 context, the canvas backing-store size, the glyph atlas
// and the requestAnimationFrame loop. Haskell owns the scene: once per frame
// this file calls the Haskell frame callback (a `wrapper sync` export, so it
// runs inside this rAF task), and Haskell answers with exactly one call,
// `draw(handle, memory, ptr, count)`, which reads a packed Float32 buffer
// straight out of wasm memory.
//
// Buffer layout (must match Renderer.Internal.packScene):
//   header, 18 floats: world matrix (column-major 3x3), overlay matrix (same).
//   then `count` instances of 13 floats:
//     kind (0 square, 1 triangle, 2 dot, 3 glyph), glyph index, space (0 world,
//     1 overlay), affine a b c d tx ty, colour r g b a (straight, 0..1).
//
// Test and measurement hooks: `TypeWizardRenderer.stats` (frames, draws,
// loops started and stopped, and, with `?bench` in the page URL, the time
// spent inside the frame callback).
(function () {
  "use strict";

  var HEADER_FLOATS = 18;
  var INSTANCE_FLOATS = 13;
  var STRIDE = INSTANCE_FLOATS * 4;
  var GLYPH_ASPECT = 0.6; // glyph cell width over height; Renderer.Internal.glyphAspect
  var FIRST_GLYPH = 33; // '!'
  var GLYPH_COUNT = 94; // '!' .. '~'
  var ATLAS_COLS = 16;
  var ATLAS_ROWS = Math.ceil(GLYPH_COUNT / ATLAS_COLS);
  var CELL_H = 64;
  var CELL_W = Math.round(CELL_H * GLYPH_ASPECT);
  var WAIT_FRAMES = 120; // frames a canvas may take to be attached before its loop gives up
  var FONT_FAMILY = 'ui-monospace, Menlo, Consolas, "DejaVu Sans Mono", "Courier New", monospace';

  var bench = /[?&]bench\b/.test(window.location.search);
  var stats = { created: 0, started: 0, stopped: 0, frames: 0, draws: 0, errors: 0, callbackMs: 0, drawMs: 0 };
  var states = [];

  var VERT = [
    "#version 300 es",
    "layout(location=0) in vec2 a_corner;",
    "layout(location=1) in vec3 i_kind;",  // kind, glyph, space
    "layout(location=2) in vec4 i_aff;",   // a b c d
    "layout(location=3) in vec2 i_t;",     // tx ty
    "layout(location=4) in vec4 i_col;",
    "uniform mat3 u_world;",
    "uniform mat3 u_overlay;",
    "uniform vec2 u_atlas;",               // columns, rows
    "out vec2 v_local;",
    "out vec2 v_uv;",
    "out vec4 v_col;",
    "flat out float v_kind;",
    "void main() {",
    "  vec2 c = a_corner;",
    "  if (i_kind.x > 0.5 && i_kind.x < 1.5 && c.x > 0.0) { c.y = 0.0; }",  // triangle: apex on the right edge
    "  vec2 p = vec2(i_aff.x * c.x + i_aff.z * c.y + i_t.x, i_aff.y * c.x + i_aff.w * c.y + i_t.y);",
    "  mat3 m = i_kind.z > 0.5 ? u_overlay : u_world;",
    "  gl_Position = vec4((m * vec3(p, 1.0)).xy, 0.0, 1.0);",
    "  v_local = a_corner;",
    "  float col = mod(i_kind.y, u_atlas.x);",
    "  float row = floor(i_kind.y / u_atlas.x);",
    "  v_uv = vec2(col + a_corner.x + 0.5, row + 0.5 - a_corner.y) / u_atlas;",
    "  v_col = i_col;",
    "  v_kind = i_kind.x;",
    "}"
  ].join("\n");

  var FRAG = [
    "#version 300 es",
    "precision mediump float;",
    "in vec2 v_local;",
    "in vec2 v_uv;",
    "in vec4 v_col;",
    "flat in float v_kind;",
    "uniform sampler2D u_tex;",
    "out vec4 o;",
    "void main() {",
    "  float cover = 1.0;",
    "  if (v_kind > 1.5 && v_kind < 2.5) {",
    "    float d = length(v_local * 2.0);",
    "    float w = max(fwidth(d), 1e-4);",
    "    cover = 1.0 - smoothstep(1.0 - w, 1.0, d);",
    "  } else if (v_kind > 2.5) {",
    "    cover = texture(u_tex, v_uv).a;",
    "  }",
    "  float a = v_col.a * cover;",
    "  o = vec4(v_col.rgb * a, a);",   // premultiplied, as the canvas expects
    "}"
  ].join("\n");

  function compile(gl, type, src) {
    var s = gl.createShader(type);
    gl.shaderSource(s, src);
    gl.compileShader(s);
    if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) {
      throw new Error("shader: " + gl.getShaderInfoLog(s));
    }
    return s;
  }

  function buildProgram(gl) {
    var p = gl.createProgram();
    gl.attachShader(p, compile(gl, gl.VERTEX_SHADER, VERT));
    gl.attachShader(p, compile(gl, gl.FRAGMENT_SHADER, FRAG));
    gl.linkProgram(p);
    if (!gl.getProgramParameter(p, gl.LINK_STATUS)) {
      throw new Error("program: " + gl.getProgramInfoLog(p));
    }
    return p;
  }

  // The glyph atlas: printable ASCII, one monospace font, drawn once with
  // canvas 2D into cells of GLYPH_ASPECT:1 and uploaded as a texture. Until
  // `document.fonts.ready` resolves the texture is empty, so text is simply
  // not visible for the first moments.
  function buildAtlas(s) {
    var gl = s.gl;
    var c = document.createElement("canvas");
    c.width = ATLAS_COLS * CELL_W;
    c.height = ATLAS_ROWS * CELL_H;
    var g = c.getContext("2d");
    var size = CELL_H * 0.8;
    g.font = size + "px " + FONT_FAMILY;
    var m = g.measureText("M").width;
    if (m > CELL_W * 0.95) {
      size = size * (CELL_W * 0.95) / m;
      g.font = size + "px " + FONT_FAMILY;
    }
    g.textAlign = "center";
    g.textBaseline = "middle";
    g.fillStyle = "#fff";
    for (var i = 0; i < GLYPH_COUNT; i++) {
      var col = i % ATLAS_COLS;
      var row = Math.floor(i / ATLAS_COLS);
      g.fillText(String.fromCharCode(FIRST_GLYPH + i), col * CELL_W + CELL_W / 2, row * CELL_H + CELL_H / 2);
    }
    gl.bindTexture(gl.TEXTURE_2D, s.atlasTex);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, c);
    gl.generateMipmap(gl.TEXTURE_2D);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    s.atlasReady = true;
  }

  // Backing store = CSS size x devicePixelRatio. Called every frame because
  // the ratio can change without the CSS size changing (moving the window to
  // another screen, zooming); the resize observer keeps the CSS size.
  function syncSize(s) {
    var dpr = window.devicePixelRatio || 1;
    var w = Math.max(1, Math.round(s.cssW * dpr));
    var h = Math.max(1, Math.round(s.cssH * dpr));
    if (s.canvas.width !== w || s.canvas.height !== h) {
      s.canvas.width = w;
      s.canvas.height = h;
    }
  }

  function create(canvas) {
    try {
      var gl = canvas.getContext("webgl2", { alpha: true, premultipliedAlpha: true, antialias: false });
      if (!gl) {
        return { ok: false, error: "WebGL is not available in this browser, so the game cannot be drawn." };
      }
      var program = buildProgram(gl);
      var vao = gl.createVertexArray();
      gl.bindVertexArray(vao);

      var corners = gl.createBuffer();
      gl.bindBuffer(gl.ARRAY_BUFFER, corners);
      gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-0.5, -0.5, -0.5, 0.5, 0.5, -0.5, 0.5, 0.5]), gl.STATIC_DRAW);
      gl.enableVertexAttribArray(0);
      gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 0, 0);

      var inst = gl.createBuffer();
      gl.bindBuffer(gl.ARRAY_BUFFER, inst);
      var layout = [[1, 3, 0], [2, 4, 12], [3, 2, 28], [4, 4, 36]]; // location, size, byte offset
      layout.forEach(function (a) {
        gl.enableVertexAttribArray(a[0]);
        gl.vertexAttribPointer(a[0], a[1], gl.FLOAT, false, STRIDE, a[2]);
        gl.vertexAttribDivisor(a[0], 1);
      });

      var atlasTex = gl.createTexture();
      gl.bindTexture(gl.TEXTURE_2D, atlasTex);
      gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, 1, 1, 0, gl.RGBA, gl.UNSIGNED_BYTE, new Uint8Array([0, 0, 0, 0]));

      var s = {
        canvas: canvas, gl: gl, program: program, vao: vao, inst: inst, atlasTex: atlasTex,
        atlasReady: false, instCap: 0,
        uWorld: gl.getUniformLocation(program, "u_world"),
        uOverlay: gl.getUniformLocation(program, "u_overlay"),
        uAtlas: gl.getUniformLocation(program, "u_atlas"),
        uTex: gl.getUniformLocation(program, "u_tex"),
        cssW: canvas.clientWidth, cssH: canvas.clientHeight,
        cb: null, running: false, observer: null
      };
      var rect = canvas.getBoundingClientRect();
      if (!(s.cssW > 0)) s.cssW = rect.width;
      if (!(s.cssH > 0)) s.cssH = rect.height;

      if (typeof ResizeObserver === "function") {
        s.observer = new ResizeObserver(function (entries) {
          var r = entries[entries.length - 1].contentRect;
          s.cssW = r.width;
          s.cssH = r.height;
        });
        s.observer.observe(canvas);
      }
      syncSize(s);

      var ready = (document.fonts && document.fonts.ready) || Promise.resolve();
      ready.then(function () { buildAtlas(s); }, function () { buildAtlas(s); });

      states.push(s);
      stats.created++;
      return { ok: true, handle: states.length - 1 };
    } catch (e) {
      return { ok: false, error: "The renderer could not start: " + e };
    }
  }

  function viewport(handle) {
    var s = states[handle];
    return { width: s.cssW, height: s.cssH };
  }

  // The rAF loop. It stops itself the first frame the canvas is not in the
  // document, and releases what it holds; entering the page again makes a new
  // canvas, a new `create` and a new loop.
  //
  // Reflex builds a widget in a detached fragment and attaches it a moment
  // later, so the loop can start before the canvas is in the document. A
  // canvas that has not been connected yet is given WAIT_FRAMES frames to
  // arrive; one that never does is dropped like one that left.
  function start(handle, cb) {
    var s = states[handle];
    if (s.running) return;
    s.cb = cb;
    s.running = true;
    s.seenConnected = false;
    s.waited = 0;
    stats.started++;
    function stop() {
      s.running = false;
      s.cb = null;
      if (s.observer) s.observer.disconnect();
      stats.stopped++;
    }
    function frame(ts) {
      if (!s.canvas.isConnected) {
        if (s.seenConnected || ++s.waited > WAIT_FRAMES) return stop();
        requestAnimationFrame(frame);
        return;
      }
      s.seenConnected = true;
      requestAnimationFrame(frame); // before the callback, so a failing frame cannot end the loop
      stats.frames++;
      try {
        if (!(s.cssW > 0) || !(s.cssH > 0)) {
          var r = s.canvas.getBoundingClientRect();
          s.cssW = r.width;
          s.cssH = r.height;
        }
        syncSize(s);
        var t0 = bench ? performance.now() : 0;
        s.cb(ts / 1000, s.cssW, s.cssH);
        if (bench) stats.callbackMs += performance.now() - t0;
      } catch (e) {
        stats.errors++;
        console.error("renderer frame failed:", e);
      }
    }
    requestAnimationFrame(frame);
  }

  // The one draw call of a frame. `memory` is wasm memory's current buffer:
  // it is passed fresh on every call because growing memory detaches the old
  // one.
  function draw(handle, memory, ptr, count) {
    var s = states[handle];
    var t0 = bench ? performance.now() : 0;
    var gl = s.gl;
    var floats = new Float32Array(memory, ptr, HEADER_FLOATS + count * INSTANCE_FLOATS);
    gl.viewport(0, 0, s.canvas.width, s.canvas.height);
    gl.clearColor(0, 0, 0, 0);
    gl.clear(gl.COLOR_BUFFER_BIT);
    if (count > 0) {
      gl.useProgram(s.program);
      gl.bindVertexArray(s.vao);
      gl.enable(gl.BLEND);
      gl.blendFunc(gl.ONE, gl.ONE_MINUS_SRC_ALPHA);
      gl.uniformMatrix3fv(s.uWorld, false, floats.subarray(0, 9));
      gl.uniformMatrix3fv(s.uOverlay, false, floats.subarray(9, 18));
      gl.uniform2f(s.uAtlas, ATLAS_COLS, ATLAS_ROWS);
      gl.activeTexture(gl.TEXTURE0);
      gl.bindTexture(gl.TEXTURE_2D, s.atlasTex);
      gl.uniform1i(s.uTex, 0);
      gl.bindBuffer(gl.ARRAY_BUFFER, s.inst);
      gl.bufferData(gl.ARRAY_BUFFER, floats.subarray(HEADER_FLOATS), gl.DYNAMIC_DRAW);
      gl.drawArraysInstanced(gl.TRIANGLE_STRIP, 0, 4, count);
    }
    stats.draws++;
    if (bench) stats.drawMs += performance.now() - t0;
  }

  window.TypeWizardRenderer = {
    create: create, viewport: viewport, start: start, draw: draw, stats: stats
  };
})();
