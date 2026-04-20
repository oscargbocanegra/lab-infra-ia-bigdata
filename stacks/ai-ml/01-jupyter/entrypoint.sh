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
# ── JARVIS Widget — Iron Man, estilo VS Code inline chat ─────────────────────
# Uso:
#   jarvis            → muestra el panel (sin paréntesis)
#   jarvis()          → también funciona
#
# Slash commands disponibles (tipear "/" para ver sugerencias):
#   /explain   /fix   /comments   /optimize   /test   /refactor   /document
#
# Diseño adaptativo: sin colores hardcodeados, usa CSS variables de JupyterLab
# ─────────────────────────────────────────────────────────────────────────────

import warnings as _warnings

_JARVIS_SLASH_COMMANDS = [
    ("/explain",   "Explain code",    "Explain this code in detail, step by step"),
    ("/fix",       "Fix errors",      "Find and fix all bugs and errors in this code"),
    ("/comments",  "Add comments",    "Add clear docstrings and inline comments to this code"),
    ("/optimize",  "Optimize",        "Optimize this code for performance and readability"),
    ("/test",      "Write tests",     "Write comprehensive unit tests for this code using pytest"),
    ("/refactor",  "Refactor",        "Refactor this code following SOLID and clean code principles"),
    ("/document",  "Document",        "Write complete API documentation for this function or class"),
]

# ── Iron Man helmet SVG ───────────────────────────────────────────────────────
# Casco Mark XLVI: forma trapezoidal, faceplate con mentón,
# ojos triangulares dorados, reactor arc en el centro.
_JARVIS_IRON_MAN_SVG = """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" width="30" height="30">
  <defs>
    <radialGradient id="jBg" cx="50%" cy="40%" r="60%">
      <stop offset="0%" stop-color="#1a0505"/>
      <stop offset="100%" stop-color="#0a0000"/>
    </radialGradient>
    <radialGradient id="jFace" cx="50%" cy="50%" r="50%">
      <stop offset="0%" stop-color="#c0392b"/>
      <stop offset="100%" stop-color="#7b0f0f"/>
    </radialGradient>
    <filter id="jGlow" x="-20%" y="-20%" width="140%" height="140%">
      <feGaussianBlur stdDeviation="1.8" result="blur"/>
      <feMerge><feMergeNode in="blur"/><feMergeNode in="SourceGraphic"/></feMerge>
    </filter>
    <filter id="jGoldGlow" x="-30%" y="-30%" width="160%" height="160%">
      <feGaussianBlur stdDeviation="2.5" result="blur"/>
      <feMerge><feMergeNode in="blur"/><feMergeNode in="SourceGraphic"/></feMerge>
    </filter>
  </defs>

  <!-- fondo circular oscuro -->
  <circle cx="50" cy="50" r="48" fill="url(#jBg)" stroke="#8b0000" stroke-width="1"/>

  <!-- casco completo: forma trapezoidal tope ancho, mentón estrecho -->
  <path d="M22 18 L78 18 L84 38 L84 62 L72 80 L50 86 L28 80 L16 62 L16 38 Z"
        fill="url(#jFace)" stroke="#600000" stroke-width="1.2"/>

  <!-- placa frente / franja central dorada vertical -->
  <path d="M44 18 L56 18 L58 44 L50 46 L42 44 Z"
        fill="#c8860a" stroke="#f0a020" stroke-width="0.6"/>

  <!-- mejilla izquierda (más oscura) -->
  <path d="M22 18 L44 18 L42 44 L30 52 L16 44 L16 38 Z"
        fill="#9b1e1e" stroke="#600000" stroke-width="0.8"/>

  <!-- mejilla derecha -->
  <path d="M56 18 L78 18 L84 38 L84 44 L70 52 L58 44 Z"
        fill="#9b1e1e" stroke="#600000" stroke-width="0.8"/>

  <!-- ojo izquierdo — trapecio dorado brillante -->
  <path d="M20 30 L40 26 L40 40 L20 44 Z"
        fill="#f0c030" filter="url(#jGoldGlow)" opacity="0.95"/>
  <!-- brillo interior ojo izq -->
  <path d="M22 32 L38 28 L38 34 L22 38 Z"
        fill="white" opacity="0.35"/>

  <!-- ojo derecho -->
  <path d="M80 30 L60 26 L60 40 L80 44 Z"
        fill="#f0c030" filter="url(#jGoldGlow)" opacity="0.95"/>
  <!-- brillo interior ojo der -->
  <path d="M78 32 L62 28 L62 34 L78 38 Z"
        fill="white" opacity="0.35"/>

  <!-- faceplate inferior / mentón -->
  <path d="M30 52 L50 46 L70 52 L72 80 L50 86 L28 80 Z"
        fill="#871515" stroke="#600000" stroke-width="0.8"/>

  <!-- línea de separación faceplate (ranura horizontal) -->
  <line x1="22" y1="52" x2="78" y2="52" stroke="#600000" stroke-width="1.5"/>

  <!-- reactor arc en el mentón -->
  <circle cx="50" cy="67" r="6" fill="none" stroke="#00d4ff" stroke-width="1.5"
          filter="url(#jGlow)"/>
  <circle cx="50" cy="67" r="3" fill="#00d4ff" opacity="0.9" filter="url(#jGlow)"/>

  <!-- pequeños detalles laterales (ventilaciones) -->
  <rect x="17" y="56" width="8" height="2" rx="1" fill="#600000"/>
  <rect x="17" y="60" width="6" height="2" rx="1" fill="#600000"/>
  <rect x="75" y="56" width="8" height="2" rx="1" fill="#600000"/>
  <rect x="77" y="60" width="6" height="2" rx="1" fill="#600000"/>
</svg>
"""

def _jarvis_show():
    """
    Panel JARVIS compacto estilo VS Code inline chat.
    - Diseño de una línea: icono + input + send + close
    - Slash commands como dropdown adaptativo al tema
    - Sin colores hardcodeados — usa CSS vars de JupyterLab
    """
    try:
        import ipywidgets as widgets
        from IPython.display import display as _display, HTML as _HTML
        import IPython

        _ip = IPython.get_ipython()
        if _ip is None:
            print("Requires an IPython kernel.")
            return

        # ── CSS adaptativo — usa variables del tema de JupyterLab ────────
        _display(_HTML("""
        <style>
          /* Chips: fondo transparente, texto del tema, separador sutil */
          .jv-chip button.widget-button {
            background: transparent !important;
            border-top: none !important;
            border-left: none !important;
            border-right: none !important;
            border-bottom: 1px solid var(--jp-border-color2, rgba(128,128,128,0.2)) !important;
            border-radius: 0 !important;
            text-align: left !important;
            padding-left: 14px !important;
            font-size: 13px !important;
            width: 100% !important;
          }
          .jv-chip button.widget-button:hover {
            background: var(--jp-layout-color2, rgba(128,128,128,0.1)) !important;
          }
          /* Contenedor chips: borde sutil del tema, sin bg hardcodeado */
          .jv-cmd-box {
            border: 1px solid var(--jp-border-color1, rgba(128,128,128,0.3)) !important;
            border-radius: 6px !important;
            overflow: hidden !important;
            margin-top: 4px !important;
          }
          /* Panel principal: borde brand, sin bg hardcodeado */
          .jv-panel {
            border: 1px solid var(--jp-brand-color2, #4a90e2) !important;
            border-radius: 8px !important;
            padding: 8px 10px !important;
            max-width: 900px !important;
          }
        </style>
        """))

        # ── Icono Iron Man (pequeño, 30px) ────────────────────────────────
        icon_html = widgets.HTML(
            value=f'<div style="line-height:0;flex-shrink:0">{_JARVIS_IRON_MAN_SVG}</div>',
            layout=widgets.Layout(width="34px", flex="0 0 34px"),
        )

        # ── Label compacto ────────────────────────────────────────────────
        label_html = widgets.HTML(
            value='<span style="color:var(--jp-brand-color1,#4a90e2);'
                  'font-size:12px;font-weight:600;letter-spacing:1.5px;'
                  'font-family:monospace;white-space:nowrap">J.A.R.V.I.S</span>',
            layout=widgets.Layout(flex="0 0 auto", margin="0 6px"),
        )

        # ── Input — ocupa todo el espacio disponible ──────────────────────
        prompt_input = widgets.Text(
            placeholder='Ask JARVIS...  (type "/" for commands)',
            layout=widgets.Layout(flex="1 1 auto", height="32px"),
        )

        # ── Send — sin color: hereda el tema ─────────────────────────────
        send_btn = widgets.Button(
            description="▶",
            tooltip="Send (Enter)",
            layout=widgets.Layout(width="34px", height="32px", border_radius="4px"),
        )

        # ── Close — sin color: hereda el tema ────────────────────────────
        close_btn = widgets.Button(
            description="✕",
            tooltip="Close",
            layout=widgets.Layout(width="30px", height="32px", border_radius="4px"),
        )

        # ── Slash command chips — dos columnas, sin colores hardcodeados ──
        cmd_chips = []
        for cmd, label, expansion in _JARVIS_SLASH_COMMANDS:
            chip = widgets.Button(
                description=f"{cmd:<14}  {label}",
                layout=widgets.Layout(
                    width="100%",
                    height="32px",
                ),
            )
            chip.add_class("jv-chip")
            chip._jv_cmd = cmd

            def _make_click(c):
                def _on(b):
                    prompt_input.value = c._jv_cmd + " "
                    cmd_box.layout.display = "none"
                return _on

            chip.on_click(_make_click(chip))
            cmd_chips.append(chip)

        cmd_box = widgets.VBox(
            cmd_chips,
            layout=widgets.Layout(display="none"),
        )
        cmd_box.add_class("jv-cmd-box")

        # Mostrar chips al tipear "/"
        def _on_input_change(change):
            val = change["new"]
            cmd_box.layout.display = "" if val.startswith("/") else "none"

        prompt_input.observe(_on_input_change, names="value")

        # ── Status + Output ───────────────────────────────────────────────
        status_html = widgets.HTML(value="", layout=widgets.Layout(display="none"))
        output_area = widgets.Output(
            layout=widgets.Layout(
                display="none",
                border="1px solid var(--jp-border-color1, rgba(128,128,128,0.3))",
                border_radius="6px",
                padding="8px",
                margin="6px 0 0 0",
                max_height="400px",
                overflow_y="auto",
            )
        )

        # ── Send logic ────────────────────────────────────────────────────
        def _do_send(_):
            raw = prompt_input.value.strip()
            if not raw:
                return

            full_prompt = raw
            for c, _, exp in _JARVIS_SLASH_COMMANDS:
                if raw.startswith(c):
                    suffix = raw[len(c):].strip()
                    full_prompt = exp + (f". Context: {suffix}" if suffix else "")
                    break

            prompt_input.value = ""
            cmd_box.layout.display = "none"
            output_area.layout.display = ""
            status_html.layout.display = ""
            status_html.value = '<span style="color:var(--jp-brand-color1,#4a90e2)">⚡ Processing...</span>'

            with output_area:
                output_area.clear_output(wait=True)
                try:
                    _ip.run_cell_magic("JARVIS", "", full_prompt)
                except Exception as e:
                    from IPython.display import display as _d, HTML as _H
                    _d(_H(f'<span style="color:var(--jp-error-color1,#e74c3c)">❌ {e}</span>'))

            status_html.value = '<span style="color:var(--jp-success-color1,#27ae60)">✅ Done</span>'

        send_btn.on_click(_do_send)
        with _warnings.catch_warnings():
            _warnings.simplefilter("ignore", DeprecationWarning)
            prompt_input.on_submit(_do_send)

        # ── Close ─────────────────────────────────────────────────────────
        panel_ref = []
        def _on_close(_):
            if panel_ref:
                panel_ref[0].layout.display = "none"
        close_btn.on_click(_on_close)

        # ── Layout compacto: todo en una línea ────────────────────────────
        top_row = widgets.HBox(
            [icon_html, label_html, prompt_input, send_btn, close_btn],
            layout=widgets.Layout(
                align_items="center",
                gap="4px",
                width="100%",
            ),
        )
        panel = widgets.VBox(
            [top_row, cmd_box, status_html, output_area],
            layout=widgets.Layout(width="100%"),
        )
        panel.add_class("jv-panel")
        panel_ref.append(panel)
        _display(panel)

    except ImportError:
        print("ipywidgets not available. Use %%JARVIS directly.")
    except Exception as exc:
        print(f"JARVIS error: {exc}")
        print("Use %%JARVIS directly.")


# ── jarvis: funciona SIN paréntesis (y también CON) ──────────────────────────
# Cuando IPython evalúa un nombre sin llamarlo, invoca _ipython_display_().
# Cuando se llama como función, __call__ delega a _jarvis_show().
class _JARVISProxy:
    """Proxy que permite usar `jarvis` o `jarvis()` indistintamente."""
    def _ipython_display_(self, **kwargs):
        _jarvis_show()
    def __call__(self, *args, **kwargs):
        _jarvis_show()
    def __repr__(self):
        _jarvis_show()
        return ""

jarvis = _JARVISProxy()


# ── /jarvis inline cell transformer ──────────────────────────────────────────
# Permite usar `/jarvis <mensaje>` como primera línea de cualquier celda.
# El resto de la celda se envía como contexto de código — NO se ejecuta.
#
# Ejemplos (read-only):
#   /jarvis analizá este código
#   /jarvis /explain
#   <código...>
#
# Ejemplos (modifying — muestra preview con OK / ✕):
#   /jarvis fix the bug
#   /jarvis /fix
#   /jarvis /refactor
#   def foo(): pass
#
# ⚠️  Registrado en input_transformers_CLEANUP (no _post) para correr
#     ANTES del autocall de IPython — evita que `/jarvis msg` se convierta
#     en `jarvis(msg)` antes de que el transformer lo intercepte.
# ─────────────────────────────────────────────────────────────────────────────

# Comandos que modifican código → flujo preview con OK / ✕
_JARVIS_MODIFYING_CMDS = {'/fix', '/refactor', '/optimize', '/test', '/comments', '/document'}

# Keywords en texto libre que implican modificación
_JARVIS_MODIFYING_KEYWORDS = {
    'fix', 'create', 'write', 'refactor', 'optimize', 'rewrite',
    'generate', 'add', 'implement', 'update', 'change', 'modify',
    'rename', 'delete', 'remove', 'replace',
}

def _jv_is_modifying(raw_msg):
    """True si el mensaje implica modificación de código."""
    msg_lower = raw_msg.lower().strip()
    # Slash command explícito
    for cmd in _JARVIS_MODIFYING_CMDS:
        if msg_lower.startswith(cmd):
            return True
    # Primera palabra del texto libre
    words = msg_lower.split()
    if words and words[0] in _JARVIS_MODIFYING_KEYWORDS:
        return True
    return False


def _jv_run_modifying(prompt, original_code):
    """
    Flujo para comandos modifying:
      1. Corre %%JARVIS en un Output widget (captura la respuesta)
      2. Extrae el primer bloque de código de la respuesta
      3. Muestra preview con botones:
           ✅ Insert cell  → inserta nueva celda debajo con el código
           ✕  Discard      → descarta el preview
    """
    import re
    import IPython
    import ipywidgets as widgets
    from IPython.display import display as _display, Javascript

    _ip = IPython.get_ipython()

    # ── Correr JARVIS y capturar output ──────────────────────────────────
    output_area = widgets.Output(
        layout=widgets.Layout(
            border='1px solid var(--jp-border-color1, rgba(128,128,128,0.3))',
            border_radius='6px',
            padding='8px',
            max_height='400px',
            overflow_y='auto',
            margin='4px 0',
        )
    )
    status = widgets.HTML(
        value='<span style="color:var(--jp-brand-color1,#4a90e2)">⚡ Processing...</span>'
    )
    container = widgets.VBox([status, output_area])
    _display(container)

    with output_area:
        try:
            _ip.run_cell_magic('JARVIS', '', prompt)
        except Exception as e:
            from IPython.display import HTML as _H, display as _d
            _d(_H(f'<span style="color:var(--jp-error-color1,#e74c3c)">❌ {e}</span>'))
            status.value = ''
            return

    # ── Extraer bloque de código de la respuesta ──────────────────────────
    raw_text = ''
    for out in output_area.outputs:
        if out.get('output_type') == 'display_data':
            data = out.get('data', {})
            raw_text += data.get('text/markdown', '') or data.get('text/plain', '')
        elif out.get('output_type') == 'stream':
            raw_text += out.get('text', '')

    # Buscar bloque ```python ... ``` o ``` ... ```
    matches = re.findall(r'```(?:python)?\n(.*?)```', raw_text, re.DOTALL)
    extracted_code = matches[0].strip() if matches else None

    status.value = '<span style="color:var(--jp-success-color1,#27ae60)">✅ Done</span>'

    if not extracted_code:
        # No encontró código limpio — solo mostrar la respuesta, sin preview
        return

    # ── Preview con OK / ✕ ───────────────────────────────────────────────
    preview_label = widgets.HTML(
        value='<b style="font-size:12px;color:var(--jp-ui-font-color1,inherit)">'
              '📋 Suggested code — insert as new cell?</b>'
    )
    code_preview = widgets.Textarea(
        value=extracted_code,
        layout=widgets.Layout(width='100%', height='160px'),
    )
    ok_btn = widgets.Button(
        description='✅ Insert cell',
        button_style='success',
        layout=widgets.Layout(width='140px', height='32px'),
    )
    cancel_btn = widgets.Button(
        description='✕ Discard',
        button_style='danger',
        layout=widgets.Layout(width='110px', height='32px'),
    )
    btn_row = widgets.HBox([ok_btn, cancel_btn], layout=widgets.Layout(gap='8px'))
    preview_box = widgets.VBox(
        [preview_label, code_preview, btn_row],
        layout=widgets.Layout(
            border='1px solid var(--jp-brand-color2, #4a90e2)',
            border_radius='6px',
            padding='10px',
            margin='6px 0 0 0',
        )
    )
    container.children = list(container.children) + [preview_box]

    def _on_insert(_):
        code_to_insert = code_preview.value
        # Escapar para embeber en template literal JS
        escaped = (
            code_to_insert
            .replace('\\', '\\\\')
            .replace('`', '\\`')
            .replace('$', '\\$')
        )
        _display(Javascript(f"""
        (function() {{
            var app = window.jupyterapp || window.app;
            if (!app) return;
            app.commands.execute('notebook:insert-cell-below').then(function() {{
                var nb = app.shell.currentWidget;
                if (nb && nb.content && nb.content.activeCell) {{
                    nb.content.activeCell.model.sharedModel.source = `{escaped}`;
                }}
            }});
        }})();
        """))
        preview_box.layout.display = 'none'

    def _on_discard(_):
        preview_box.layout.display = 'none'

    ok_btn.on_click(_on_insert)
    cancel_btn.on_click(_on_discard)


def _jarvis_cell_transformer(lines):
    """
    IPython input transformer: intercepta celdas que empiecen con /jarvis.
    - Read-only  → ejecuta %%JARVIS directamente
    - Modifying  → llama _jv_run_modifying() que muestra preview con OK/✕
    """
    if not lines:
        return lines

    first = lines[0].rstrip('\n').strip()
    if not first.lower().startswith('/jarvis'):
        return lines

    # Extraer el mensaje (lo que viene después de /jarvis)
    raw_msg = first[len('/jarvis'):].strip()

    # Expandir slash commands si el mensaje empieza con /
    msg = raw_msg
    for cmd, _, expansion in _JARVIS_SLASH_COMMANDS:
        if raw_msg.lower().startswith(cmd):
            suffix = raw_msg[len(cmd):].strip()
            msg = expansion + (f". Context: {suffix}" if suffix else "")
            break

    if not msg:
        msg = "Analyze and explain this code"

    # Código de contexto (resto de la celda — NO se ejecuta)
    code = "".join(lines[1:]).strip()

    if code:
        full_prompt = f"{msg}\n\n```python\n{code}\n```"
    else:
        full_prompt = msg

    if _jv_is_modifying(raw_msg):
        return [
            f"_jv_prompt = {repr(full_prompt)}\n",
            f"_jv_orig   = {repr(code)}\n",
            "_jv_run_modifying(_jv_prompt, _jv_orig)\n",
        ]
    else:
        return [
            f"_jv_inline_prompt = {repr(full_prompt)}\n",
            "get_ipython().run_cell_magic('JARVIS', '', _jv_inline_prompt)\n",
        ]


# ── Registrar en input_transformers_CLEANUP ───────────────────────────────────
# CRÍTICO: cleanup corre ANTES del autocall de IPython.
# Si se registra en input_transformers_post, el autocall convierte
# `/jarvis msg` en `jarvis(msg)` antes de que este transformer lo vea.
try:
    import IPython as _ipython_mod
    _ip_shell = _ipython_mod.get_ipython()
    if _ip_shell is not None:
        # Evitar duplicados si el startup se carga múltiples veces
        _ip_shell.input_transformers_cleanup = [
            t for t in _ip_shell.input_transformers_cleanup
            if getattr(t, '__name__', '') != '_jarvis_cell_transformer'
        ]
        # CRÍTICO: insert(0) para correr ANTES de EscapedCommand (built-in de IPython)
        # que convierte `/jarvis msg` → `jarvis(msg)` si se registra al final.
        _ip_shell.input_transformers_cleanup.insert(0, _jarvis_cell_transformer)
except Exception:
    pass  # Silencioso — no rompe nada si falla
WIDGET_EOF
echo "==> [jarvis] Widget Iron Man Copilot (v5 — /jarvis inline transformer) configurado ✓"

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

