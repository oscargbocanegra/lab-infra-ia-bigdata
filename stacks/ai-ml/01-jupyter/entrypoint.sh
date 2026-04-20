#!/bin/bash
set -e

echo "==> Iniciando configuración de Jupyter..."

# ── Leer credenciales MinIO desde Docker Secrets ─────────────
# AWS_ACCESS_KEY_ID_FILE / AWS_SECRET_ACCESS_KEY_FILE NO son variables
# estándar reconocidas por boto3, s3fs ni PySpark.
# Leemos los secrets y los exportamos como las vars estándar que SÍ leen.
if [ -f /run/secrets/minio_access_key ]; then
    export AWS_ACCESS_KEY_ID
    AWS_ACCESS_KEY_ID=$(cat /run/secrets/minio_access_key)
fi

if [ -f /run/secrets/minio_secret_key ]; then
    export AWS_SECRET_ACCESS_KEY
    AWS_SECRET_ACCESS_KEY=$(cat /run/secrets/minio_secret_key)
fi

# Endpoint MinIO para boto3/s3fs (s3:// sin prefijo s3a)
export AWS_ENDPOINT_URL=http://minio:9000

# ── Configurar jupyter-ai con Ollama como provider ───────────
# JARVIS_MODEL viene como variable de entorno desde stack.yml.
# Desde Portainer: Services → jupyter_jupyter_ogiovanni/odavid
#                  → Environment → JARVIS_MODEL → cambiar valor → Update
# Fallback: qwen2.5-coder:7b si la variable no está seteada
JARVIS_MODEL="${JARVIS_MODEL:-ollama:qwen2.5-coder:7b}"
JUPYTER_CONFIG_DIR="/home/jovyan/.jupyter"
mkdir -p "$JUPYTER_CONFIG_DIR"

# jupyter_lab_config.py — Jupyter lo carga pero nunca lo regenera
# Siempre lo escribimos para garantizar que la config de Ollama esté activa
cat > "$JUPYTER_CONFIG_DIR/jupyter_lab_config.py" << EOF
# ── jupyter-ai: Ollama provider (LAN, sin cloud) ──────────────
# Modelo activo: ${JARVIS_MODEL}
# Endpoint: http://ollama:11434 (red internal de Docker Swarm)
# NOTA: initial_language_model es el traitlet correcto en jupyter-ai 2.x
c.AiExtension.initial_language_model = "${JARVIS_MODEL}"
c.AiExtension.allowed_providers = ["ollama"]

# ── jupyter-lsp: Language Server Protocol ─────────────────────
c.LanguageServerManager.autodetect = True
EOF
echo "==> [jupyter-ai] jupyter_lab_config.py escrito (modelo: ${JARVIS_MODEL}) ✓"

# jupyter_jupyter_ai_config.json — config persistente del chat panel
# Nombre correcto según la doc oficial de jupyter-ai 2.x
# Solo se crea si no existe para respetar cambios del usuario
AI_CONFIG="$JUPYTER_CONFIG_DIR/jupyter_jupyter_ai_config.json"
if [ ! -f "$AI_CONFIG" ]; then
    cat > "$AI_CONFIG" << 'EOF'
{
  "model_provider_id": "ollama:qwen2.5-coder:7b",
  "fields": {
    "base_url": "http://ollama:11434"
  }
}
EOF
    echo "==> [jupyter-ai] jupyter_ai_config.json creado ✓"
fi

echo "==> Ejecutando init de kernels..."

# Ejecutar script de inicialización de kernels
if [ -f /tmp/init-kernels.sh ]; then
    bash /tmp/init-kernels.sh
fi

# ── JupyterLab settings: autocompletado continuo (as-you-type) ─
# jupyterlab-lsp por default requiere Tab para mostrar completions.
# Con continuousHinting: true se activa el modo automático (Hinterland mode).
# El archivo va en el Settings directory de JupyterLab (persistido en NVMe).
LAB_SETTINGS_DIR="/home/jovyan/.jupyter/lab/user-settings"
mkdir -p "$LAB_SETTINGS_DIR/@jupyter-lsp/jupyterlab-lsp"

LSP_COMPLETION_SETTINGS="$LAB_SETTINGS_DIR/@jupyter-lsp/jupyterlab-lsp/completion.jupyterlab-settings"
if [ ! -f "$LSP_COMPLETION_SETTINGS" ]; then
    cat > "$LSP_COMPLETION_SETTINGS" << 'EOF'
{
  "continuousHinting": true,
  "suppressContinuousHintingIn": ["Comment", "BlockComment", "LineComment", "String"],
  "theme": "vscode",
  "layout": "side-by-side",
  "waitForBusyKernel": true
}
EOF
    echo "==> [lsp] continuousHinting configurado ✓"
fi

# ── JupyterLab completer nativo: habilitar autoCompletion ──────
# JupyterLab 4.x tiene su propio completer (@jupyterlab/completer-extension)
# con autoCompletion: false por defecto. Sin esto, continuousHinting del LSP
# no se activa — el schema del LSP lo dice explícitamente:
#   "Requires enabling autocompletion in the other 'Code completion' settings"
mkdir -p "$LAB_SETTINGS_DIR/@jupyterlab/completer-extension"
COMPLETER_SETTINGS="$LAB_SETTINGS_DIR/@jupyterlab/completer-extension/manager.jupyterlab-settings"
if [ ! -f "$COMPLETER_SETTINGS" ]; then
    cat > "$COMPLETER_SETTINGS" << 'EOF'
{
  "autoCompletion": true
}
EOF
    echo "==> [completer] autoCompletion nativo habilitado ✓"
fi


# ── IPython startup: auto-cargar jupyter_ai_magics en todos los kernels ──
# Los archivos en ~/.ipython/profile_default/startup/ se ejecutan
# automáticamente al iniciar cualquier kernel IPython (python3, llm, ia, bigdata).
# Esto evita tener que correr %load_ext jupyter_ai_magics manualmente.
IPYTHON_STARTUP="/home/jovyan/.ipython/profile_default/startup"
mkdir -p "$IPYTHON_STARTUP"

MAGIC_STARTUP="$IPYTHON_STARTUP/00-jupyter-ai-magics.py"
# Siempre sobreescribir — el modelo viene de $JARVIS_MODEL (env var), se actualiza en cada arranque
cat > "$MAGIC_STARTUP" << EOF
# ── Jarvis: magic personalizado para jupyter-ai ───────────────────────────────
# Modelo activo: ${JARVIS_MODEL}
# Para cambiar el modelo: Portainer → Service → Environment → JARVIS_MODEL
#
# Uso rápido (celda magic):
#   %%JARVIS
#   crea una función que calcule fibonacci
#
# Uso con panel Iron Man (estilo Copilot):
#   jarvis_panel()   ← botón rojo → click → escribe → ⚡ Ejecutar
#   jarvis()         ← alias corto
# ─────────────────────────────────────────────────────────────────────────────
JARVIS_MODEL = "${JARVIS_MODEL}"

try:
    _ip = get_ipython()
    _ip.run_line_magic('load_ext', 'jupyter_ai_magics')

    from IPython.display import display

    def JARVIS(line, cell):
        """Magic %%JARVIS / %%jarvis — envía el prompt al modelo configurado en JARVIS_MODEL."""
        result = _ip.run_cell_magic('ai', JARVIS_MODEL, cell)
        if result is not None:
            display(result)

    # Registrar ambas variantes — IPython es case-sensitive
    _ip.register_magic_function(JARVIS, magic_kind='cell', magic_name='JARVIS')
    _ip.register_magic_function(JARVIS, magic_kind='cell', magic_name='jarvis')

except Exception:
    pass  # Silencioso si jupyter_ai_magics no está disponible en este kernel
EOF
echo "==> [ipython] Magic %%JARVIS configurado (modelo: ${JARVIS_MODEL}) ✓"

# ── JARVIS Widget: panel Iron Man estilo Copilot ──────────────
# Archivo de startup 01-jarvis-widget.py:
#   - Botón nativo widgets.Button (Python events — no JS bridge)
#   - Icono neon Iron Man SVG + casco azul
#   - Sin texto en el botón — solo el icono
#   - Input editable con sugerencias slash "/" al tipear
#   - /explain /fix /comments /optimize /test /refactor
#   - Seleccionar un comando lo pone en el input (sobreescribible)
#   - Enter o botón → ejecuta (expand slash a prompt completo)
WIDGET_STARTUP="$IPYTHON_STARTUP/01-jarvis-widget.py"
cat > "$WIDGET_STARTUP" << 'WIDGET_EOF'
# ── JARVIS Widget — neon Iron Man, estilo Fabric Copilot ─────────────────────
# Uso:
#   jarvis()         → muestra el panel
#   jarvis_panel()   → alias largo
#
# Slash commands disponibles (tipear "/" para ver sugerencias):
#   /explain   /fix   /comments   /optimize   /test   /refactor   /document
# El input es editable — podés sobreescribir el comando con texto libre.
# ─────────────────────────────────────────────────────────────────────────────

_JARVIS_SLASH_COMMANDS = [
    ("/explain",   "Explain code",          "Explain this code in detail, step by step"),
    ("/fix",       "Fix errors",            "Find and fix all bugs and errors in this code"),
    ("/comments",  "Add comments",          "Add clear docstrings and inline comments to this code"),
    ("/optimize",  "Optimize",              "Optimize this code for performance and readability"),
    ("/test",      "Write tests",           "Write comprehensive unit tests for this code using pytest"),
    ("/refactor",  "Refactor",              "Refactor this code following SOLID and clean code principles"),
    ("/document",  "Document",              "Write complete API documentation for this function or class"),
]

_JARVIS_IRON_MAN_SVG = """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 80 80" width="36" height="36">
  <defs>
    <radialGradient id="bgGrad" cx="50%" cy="50%" r="50%">
      <stop offset="0%" style="stop-color:#0a1628;stop-opacity:1"/>
      <stop offset="100%" style="stop-color:#020810;stop-opacity:1"/>
    </radialGradient>
    <filter id="neonGlow">
      <feGaussianBlur stdDeviation="1.5" result="blur"/>
      <feMerge><feMergeNode in="blur"/><feMergeNode in="SourceGraphic"/></feMerge>
    </filter>
  </defs>
  <!-- fondo circular -->
  <circle cx="40" cy="40" r="38" fill="url(#bgGrad)" stroke="#00d4ff" stroke-width="1.5"/>
  <!-- casco exterior -->
  <path d="M40 8 C24 8 16 20 16 32 L16 50 C16 62 26 72 40 72
           C54 72 64 62 64 50 L64 32 C64 20 56 8 40 8Z"
        fill="#0d2040" stroke="#00d4ff" stroke-width="1.2" filter="url(#neonGlow)"/>
  <!-- placa frontal -->
  <path d="M27 34 L27 50 C27 57 33 64 40 64 C47 64 53 57 53 50 L53 34Z"
        fill="#071830" stroke="#00aaff" stroke-width="0.8"/>
  <!-- visor izquierdo -->
  <path d="M18 30 L28 28 L28 38 L18 40Z"
        fill="#00d4ff" opacity="0.85" filter="url(#neonGlow)"/>
  <!-- visor derecho -->
  <path d="M62 30 L52 28 L52 38 L62 40Z"
        fill="#00d4ff" opacity="0.85" filter="url(#neonGlow)"/>
  <!-- brillo visor izq -->
  <path d="M19 31 L26 30 L26 32 L19 33Z" fill="white" opacity="0.5"/>
  <!-- brillo visor der -->
  <path d="M61 31 L54 30 L54 32 L61 33Z" fill="white" opacity="0.5"/>
  <!-- reactor pecho (círculo central neon) -->
  <circle cx="40" cy="54" r="5" fill="none" stroke="#00d4ff" stroke-width="1.2"
          filter="url(#neonGlow)"/>
  <circle cx="40" cy="54" r="2.5" fill="#00d4ff" opacity="0.9"/>
  <!-- líneas HUD decorativas -->
  <line x1="28" y1="46" x2="28" y2="50" stroke="#00d4ff" stroke-width="0.7" opacity="0.6"/>
  <line x1="52" y1="46" x2="52" y2="50" stroke="#00d4ff" stroke-width="0.7" opacity="0.6"/>
</svg>
"""

def jarvis_panel():
    """
    Panel JARVIS estilo Iron Man / Fabric Copilot.

    Click en el botón neon → abre el input.
    Tipear '/' → muestra slash commands seleccionables.
    El input es editable — sobreescribí el comando con tu propio texto.
    Enter o [Send] → ejecuta.

    Slash commands: /explain /fix /comments /optimize /test /refactor /document
    """
    try:
        import ipywidgets as widgets
        from IPython.display import display as _display
        import IPython

        _ip = IPython.get_ipython()
        if _ip is None:
            print("Requires an IPython kernel.")
            return

        # ── Toggle button: neon SVG + widgets.Button superpuesto ─────────
        # widgets.HTML para el visual, widgets.Button (oculto pero clickeable)
        # montados en un Stack — el Button captura el click, el SVG es decorativo.
        # PERO: widgets.HTML no dispara eventos Python.
        # Solución limpia: widgets.Button con icon vacío + HTML del SVG como
        # descripción via layout trick. Usamos widgets.Button nativo.

        toggle_btn = widgets.Button(
            description="",
            tooltip="Ask JARVIS",
            layout=widgets.Layout(
                width="60px", height="60px",
                border="2px solid #00d4ff",
                border_radius="50%",
                padding="0",
            ),
        )
        toggle_btn.style.button_color = "#050520"

        # Overlay el SVG encima del botón vía HTML widget al lado
        icon_html = widgets.HTML(
            value=f'<div style="pointer-events:none;margin-left:-66px;margin-top:2px">'
                  f'{_JARVIS_IRON_MAN_SVG}</div>'
        )

        # ── Placeholder "Ask JARVIS..." con hint de slash ─────────────────
        hint_html = widgets.HTML(
            value='<span style="color:#4a9eff;font-size:13px;margin-left:6px">'
                  'Ask JARVIS... or type <b style="color:#00d4ff">/</b> for commands</span>',
            layout=widgets.Layout(display="none"),
        )

        # ── Input de texto ────────────────────────────────────────────────
        prompt_input = widgets.Text(
            placeholder='Ask JARVIS... (type "/" for commands)',
            layout=widgets.Layout(
                width="100%", height="36px", display="none",
            ),
        )

        # ── Slash command chips ───────────────────────────────────────────
        cmd_chips = []
        for cmd, label, _ in _JARVIS_SLASH_COMMANDS:
            chip = widgets.Button(
                description=f"{cmd}  —  {label}",
                layout=widgets.Layout(
                    width="100%", height="30px",
                    border_radius="0px",
                    border="none",
                    border_bottom="1px solid #0a2040",
                    text_align="left",
                    padding="0 12px",
                ),
            )
            chip.style.button_color = "#071828"
            chip._jarvis_cmd = cmd
            chip._jarvis_full = _  # full prompt expansion

            def _make_cmd_click(c):
                def _on_cmd(b):
                    prompt_input.value = c._jarvis_cmd + " "
                    _set_cmd_box_visible(False)
                    prompt_input.focus()
                return _on_cmd

            chip.on_click(_make_cmd_click(chip))
            cmd_chips.append(chip)

        cmd_box = widgets.VBox(
            cmd_chips,
            layout=widgets.Layout(
                display="none",
                border="1px solid #00d4ff",
                border_radius="8px",
                overflow="hidden",
                margin="4px 0 0 0",
                background_color="#050d1a",
            ),
        )

        def _set_cmd_box_visible(visible):
            cmd_box.layout.display = "" if visible else "none"

        # Mostrar/ocultar cmd_box cuando se tipea "/"
        def _on_input_change(change):
            val = change["new"]
            if val == "/":
                _set_cmd_box_visible(True)
            elif not val.startswith("/"):
                _set_cmd_box_visible(False)

        prompt_input.observe(_on_input_change, names="value")

        # ── Send + Close ──────────────────────────────────────────────────
        send_btn = widgets.Button(
            description="Send ↵",
            layout=widgets.Layout(
                display="none", width="80px", height="36px",
                border_radius="6px",
            ),
        )
        send_btn.style.button_color = "#003d5c"

        close_btn = widgets.Button(
            description="✕",
            layout=widgets.Layout(
                display="none", width="36px", height="36px",
                border_radius="6px",
            ),
        )
        close_btn.style.button_color = "#1a0a0a"

        status_html = widgets.HTML(value="", layout=widgets.Layout(display="none"))

        output_area = widgets.Output(
            layout=widgets.Layout(
                display="none",
                border="1px solid #0a2040",
                border_radius="6px",
                padding="8px",
                margin="6px 0 0 0",
                max_height="400px",
                overflow_y="auto",
            )
        )

        _open = [False]

        # ── Toggle ────────────────────────────────────────────────────────
        def _on_toggle(b):
            _open[0] = not _open[0]
            show = "" if _open[0] else "none"
            prompt_input.layout.display = show
            send_btn.layout.display = show
            close_btn.layout.display = show
            hint_html.layout.display = "none"
            if _open[0]:
                _set_cmd_box_visible(True)  # mostrar slash commands al abrir

        toggle_btn.on_click(_on_toggle)

        # ── Send logic ────────────────────────────────────────────────────
        def _do_send(_):
            raw = prompt_input.value.strip()
            if not raw:
                return

            # Expandir slash command → prompt completo
            full_prompt = raw
            for cmd, _, expansion in _JARVIS_SLASH_COMMANDS:
                if raw.startswith(cmd):
                    suffix = raw[len(cmd):].strip()
                    full_prompt = expansion + (f". Context: {suffix}" if suffix else "")
                    break

            prompt_input.value = ""
            _set_cmd_box_visible(False)
            output_area.layout.display = ""
            status_html.value = '<span style="color:#00d4ff">⚡ Processing...</span>'
            status_html.layout.display = ""

            with output_area:
                output_area.clear_output(wait=True)
                try:
                    _ip.run_cell_magic("JARVIS", "", full_prompt)
                except Exception as e:
                    from IPython.display import display as _d, HTML as _H
                    _d(_H(f'<span style="color:#ff4444">❌ Error: {e}</span>'))

            status_html.value = '<span style="color:#27ae60">✅ Done</span>'

        send_btn.on_click(_do_send)
        prompt_input.on_submit(_do_send)

        # ── Close ─────────────────────────────────────────────────────────
        def _on_close(_):
            for w in [prompt_input, send_btn, close_btn,
                      cmd_box, status_html, output_area]:
                w.layout.display = "none"
            _open[0] = False

        close_btn.on_click(_on_close)

        # ── Layout final ──────────────────────────────────────────────────
        header_row = widgets.HBox(
            [toggle_btn, icon_html, hint_html],
            layout=widgets.Layout(align_items="center"),
        )
        input_row = widgets.HBox(
            [prompt_input, send_btn, close_btn],
            layout=widgets.Layout(gap="6px", margin="6px 0 0 0",
                                  align_items="center"),
        )
        panel = widgets.VBox(
            [header_row, input_row, cmd_box, status_html, output_area],
            layout=widgets.Layout(
                border="1px solid #00d4ff",
                border_radius="12px",
                padding="10px 12px",
                background_color="#030d1a",
                max_width="900px",
                box_shadow="0 0 18px rgba(0,212,255,0.25)",
            ),
        )
        _display(panel)

    except ImportError:
        print("ipywidgets not available. Use %%JARVIS directly.")
    except Exception as exc:
        print(f"jarvis_panel error: {exc}")
        print("Use %%JARVIS directly.")


# ── Alias ─────────────────────────────────────────────────────────────────────
jarvis = jarvis_panel
WIDGET_EOF
echo "==> [jarvis] Widget Iron Man Copilot (v2 — Python-native) configurado ✓"

# ── Data Wrangler: display() inteligente estilo Fabric ────────
# Archivo de startup 02-data-wrangler.py:
#   - Sobrescribe display() para DataFrames: tabla itables + panel Inspect
#   - panel_inspect(df) → stats por columna al estilo sidebar de Fabric
#   - profile(df)       → reporte completo ydata-profiling embebido
#   - Siempre sobreescribir (idempotente, no depende de estado previo)
DW_STARTUP="$IPYTHON_STARTUP/02-data-wrangler.py"
cat > "$DW_STARTUP" << 'DW_EOF'
# ── Data Wrangler — display inteligente estilo Fabric ────────────────────────
# Funciones disponibles en todos los kernels:
#
#   display(df)          → tabla interactiva itables (reemplaza al default)
#   panel_inspect(df)    → tabla + sidebar stats (Missing/Unique/histograma)
#   profile(df)          → reporte completo ydata-profiling embebido
#   dw(df)               → alias corto de panel_inspect
# ─────────────────────────────────────────────────────────────────────────────

def panel_inspect(df, max_rows=500, title=None):
    """
    Muestra un DataFrame con tabla interactiva + panel Inspect lateral,
    igual al Data Wrangler de Microsoft Fabric.

    Uso:
        panel_inspect(df)
        dw(df)           # alias corto
    """
    try:
        import pandas as pd
        import numpy as np
        import ipywidgets as widgets
        from IPython.display import display as _display, HTML
        import math

        if not isinstance(df, pd.DataFrame):
            try:
                df = pd.DataFrame(df)
            except Exception:
                _display(df)
                return

        nrows, ncols = df.shape

        # ── Tabla interactiva (itables) ────────────────────────────────────
        try:
            from itables import to_html_datatable
            table_html = to_html_datatable(
                df.head(max_rows),
                style="width:100%;font-size:13px",
                classes="display compact",
                lengthMenu=[10, 25, 50],
                pageLength=10,
            )
            table_widget = widgets.HTML(value=f"""
            <div style="overflow-x:auto;max-height:380px;overflow-y:auto">
            {table_html}
            </div>
            """)
        except ImportError:
            # fallback: tabla HTML estática si itables no disponible
            table_widget = widgets.HTML(
                value=df.head(max_rows).to_html(
                    classes="dataframe",
                    border=0,
                    max_rows=50
                )
            )

        # ── Panel Inspect (sidebar derecho) ────────────────────────────────
        col_widgets = []

        for col in df.columns:
            series = df[col]
            dtype  = str(series.dtype)
            n      = len(series)

            missing  = int(series.isna().sum())
            unique   = int(series.nunique())
            miss_pct = f"{missing/n*100:.0f}%" if n > 0 else "0%"
            uniq_pct = f"{unique/n*100:.0f}%"  if n > 0 else "0%"

            # Tipo label con color
            type_color = {
                'object': '#f0b429', 'string': '#f0b429',
                'int64': '#4fc3f7',  'int32': '#4fc3f7',
                'float64': '#81c784','float32': '#81c784',
                'bool': '#ce93d8',   'datetime': '#ffb74d',
            }.get(dtype.split('[')[0], '#aaaaaa')

            # Mini barra de completitud
            fill_pct = max(0, 100 - (missing/n*100 if n>0 else 0))
            bar_filled = f'width:{fill_pct:.0f}%;background:#27ae60'
            bar_empty  = f'width:{100-fill_pct:.0f}%;background:#c0392b'

            # Rango numérico o top valores
            extra_html = ''
            if pd.api.types.is_numeric_dtype(series):
                valid = series.dropna()
                if len(valid) > 0:
                    mn, mx = valid.min(), valid.max()
                    mn_s = f"{mn:.2f}" if isinstance(mn, float) else str(mn)
                    mx_s = f"{mx:.2f}" if isinstance(mx, float) else str(mx)
                    extra_html = f"""
                    <div style="display:flex;justify-content:space-between;
                                font-size:11px;color:#aaa;margin-top:3px">
                        <span>Min {mn_s}</span><span>Max {mx_s}</span>
                    </div>"""
            elif dtype == 'object' or dtype == 'string':
                top = series.value_counts().head(3)
                if len(top) > 0:
                    items = ' · '.join(str(v) for v in top.index)
                    extra_html = f"""
                    <div style="font-size:11px;color:#aaa;margin-top:3px;
                                white-space:nowrap;overflow:hidden;text-overflow:ellipsis"
                         title="{items}">↑ {items}</div>"""

            col_html = f"""
            <div style="border-bottom:1px solid #2d2d2d;padding:8px 0;min-width:180px">
              <div style="display:flex;align-items:center;gap:6px;margin-bottom:4px">
                <span style="background:{type_color};color:#000;font-size:10px;
                             padding:1px 5px;border-radius:3px;font-weight:bold">
                    {dtype[:6]}
                </span>
                <span style="font-weight:600;font-size:13px;color:#eee">{col}</span>
              </div>
              <div style="display:flex;justify-content:space-between;font-size:12px;color:#ccc">
                <span>Missing: <b>{missing} ({miss_pct})</b></span>
                <span>Unique: <b>{unique} ({uniq_pct})</b></span>
              </div>
              <div style="display:flex;height:6px;border-radius:3px;
                          overflow:hidden;margin-top:4px;background:#333">
                <div style="{bar_filled}"></div>
                <div style="{bar_empty}"></div>
              </div>
              {extra_html}
            </div>"""
            col_widgets.append(col_html)

        header_title = title or f"Table view"
        inspect_html = f"""
        <div style="font-weight:700;font-size:14px;color:#eee;
                    padding:8px 0 4px;border-bottom:2px solid #c0392b;
                    margin-bottom:6px">
            🔍 Inspect
        </div>
        {''.join(col_widgets)}
        """

        inspect_panel = widgets.HTML(
            value=f"""
            <div style="background:#1a1a2e;padding:10px;border-radius:8px;
                        height:420px;overflow-y:auto;min-width:220px">
                {inspect_html}
            </div>
            """
        )

        # ── Header con metadata ────────────────────────────────────────────
        header_html = widgets.HTML(value=f"""
        <div style="display:flex;align-items:center;gap:12px;
                    background:#1a1a2e;padding:6px 10px;border-radius:6px;
                    border-left:3px solid #c0392b;margin-bottom:6px">
            <span style="font-weight:700;color:#eee">{header_title}</span>
            <span style="background:#2d2d3a;color:#aaa;font-size:12px;
                         padding:2px 8px;border-radius:10px">
                {nrows:,} rows × {ncols} cols
            </span>
            <span style="color:#666;font-size:11px">
                💡 <code>profile(df)</code> para reporte completo
            </span>
        </div>
        """)

        # ── Layout final: tabla izquierda + inspect derecha ───────────────
        main_row = widgets.HBox(
            [
                widgets.Box(
                    [table_widget],
                    layout=widgets.Layout(flex='1 1 auto', overflow='hidden')
                ),
                inspect_panel,
            ],
            layout=widgets.Layout(gap='10px', align_items='flex-start', width='100%')
        )

        full_view = widgets.VBox(
            [header_html, main_row],
            layout=widgets.Layout(
                border='1px solid #2d2d2d',
                border_radius='10px',
                padding='10px',
                background_color='#0d0d1a',
                width='100%'
            )
        )

        _display(full_view)

    except ImportError as e:
        # Fallback limpio si ipywidgets no disponible
        from IPython.display import display as _display
        _display(df)
        print(f"💡 Instalá ipywidgets para el panel completo: {e}")
    except Exception as exc:
        from IPython.display import display as _display
        _display(df)
        print(f"⚠️  panel_inspect error: {exc}")


def profile(df, title="DataFrame Profile", minimal=False):
    """
    Genera un reporte completo con ydata-profiling embebido en el notebook.
    Equivalente al análisis detallado de Fabric Data Wrangler.

    Args:
        df       : pandas DataFrame
        title    : título del reporte
        minimal  : True = reporte rápido (sin correlaciones ni interacciones)

    Uso:
        profile(df)
        profile(df, minimal=True)   # más rápido para DataFrames grandes
    """
    try:
        from ydata_profiling import ProfileReport
        from IPython.display import display as _display

        report = ProfileReport(
            df,
            title=title,
            minimal=minimal,
            explorative=not minimal,
            progress_bar=False,
        )
        _display(report.to_widgets())

    except ImportError:
        print("⚠️  ydata-profiling no disponible en este kernel.")
        print("     Alternativa rápida: panel_inspect(df)")
    except Exception as exc:
        print(f"⚠️  profile() error: {exc}")
        print("     Alternativa rápida: panel_inspect(df)")


# ── Alias cortos ──────────────────────────────────────────────────────────────
dw = panel_inspect

# ── Override display() para DataFrames ───────────────────────────────────────
# Cuando el usuario hace display(df) o pone df al final de una celda,
# se usa panel_inspect automáticamente.
# Se guarda el display original para tipos no-DataFrame.
try:
    import builtins
    import pandas as pd
    from IPython.display import display as _ipython_display

    _original_display = _ipython_display

    def display(*args, **kwargs):
        """
        display() mejorado: DataFrames → panel_inspect (itables + Inspect sidebar).
        Otros tipos → display original de IPython.
        """
        for obj in args:
            if isinstance(obj, pd.DataFrame):
                panel_inspect(obj)
            else:
                _original_display(obj, **kwargs)

    # Inyectar en builtins para que funcione sin importar
    builtins.display = display

except Exception:
    pass  # Silencioso — el display original sigue funcionando
DW_EOF
echo "==> [data-wrangler] panel_inspect + profile + display() override configurados ✓"

echo "==> Iniciando Jupyter Lab..."

# Ejecutar el comando original de Jupyter
exec start-notebook.sh "$@"

