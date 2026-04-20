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
#   - Define jarvis_panel() disponible en todos los kernels
#   - Botón Iron Man (rojo/dorado) — click → expande input
#   - Submit → llama %%JARVIS y muestra respuesta inline
#   - Siempre sobreescribir: contiene JARVIS_MODEL embebido
WIDGET_STARTUP="$IPYTHON_STARTUP/01-jarvis-widget.py"
cat > "$WIDGET_STARTUP" << 'WIDGET_EOF'
# ── JARVIS Widget — estilo Copilot con casco Iron Man ────────────────────────
# Uso: en cualquier celda, llamar jarvis_panel() para mostrar el widget.
# El botón 🔴 Iron Man abre el input inline — mismo flow que Fabric Copilot.
# ─────────────────────────────────────────────────────────────────────────────

def jarvis_panel():
    """
    Muestra el panel JARVIS estilo Iron Man Copilot.
    Hace click en el botón rojo para abrir el input — igual que Fabric Copilot.

    Uso:
        jarvis_panel()
    """
    try:
        import ipywidgets as widgets
        from IPython.display import display, HTML
        import IPython

        _ip = IPython.get_ipython()
        if _ip is None:
            print("⚠️  JARVIS panel requiere un kernel IPython activo.")
            return

        # ── Iron Man SVG (casco minimalista, rojo/dorado) ──────────────────
        IRONMAN_SVG = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" width="28" height="28">
          <!-- casco -->
          <path d="M32 4 C16 4 10 16 10 28 L10 40 C10 50 20 60 32 60
                   C44 60 54 50 54 40 L54 28 C54 16 48 4 32 4Z"
                fill="#c0392b" stroke="#922b21" stroke-width="1.5"/>
          <!-- frente dorada -->
          <path d="M20 28 L20 38 C20 44 25 50 32 50
                   C39 50 44 44 44 38 L44 28 Z"
                fill="#f0b429" stroke="#d4952a" stroke-width="1"/>
          <!-- visor izquierdo -->
          <path d="M14 26 L22 24 L22 32 L14 33 Z"
                fill="#4fc3f7" opacity="0.9"/>
          <!-- visor derecho -->
          <path d="M50 26 L42 24 L42 32 L50 33 Z"
                fill="#4fc3f7" opacity="0.9"/>
          <!-- brillo visor -->
          <path d="M15 27 L20 26 L20 28 L15 29 Z"
                fill="white" opacity="0.4"/>
          <path d="M49 27 L44 26 L44 28 L49 29 Z"
                fill="white" opacity="0.4"/>
        </svg>
        """

        # ── Layout ─────────────────────────────────────────────────────────
        HIDDEN  = widgets.Layout(display='none')
        VISIBLE = widgets.Layout(display='')

        ironman_btn = widgets.HTML(
            value=f"""
            <button id="jarvis-toggle" title="Ask JARVIS"
              style="background:#c0392b;border:none;border-radius:8px;
                     padding:4px 8px;cursor:pointer;display:flex;
                     align-items:center;gap:6px;color:white;
                     font-weight:bold;font-size:13px;
                     box-shadow:0 2px 6px rgba(0,0,0,0.3);">
              {IRONMAN_SVG}
              <span style="color:#f0b429;">J.A.R.V.I.S</span>
            </button>
            """,
            layout=widgets.Layout(margin='0 0 0 0')
        )

        toggle_btn = widgets.Button(
            description='',
            tooltip='Ask JARVIS',
            layout=widgets.Layout(width='0px', height='0px', visibility='hidden')
        )

        prompt_input = widgets.Textarea(
            placeholder='Preguntale a JARVIS... ej: "crea una función que filtre nulls en un DataFrame"',
            layout=widgets.Layout(
                width='100%', height='72px',
                display='none',
                border='1px solid #c0392b',
                border_radius='6px'
            )
        )

        send_btn = widgets.Button(
            description='⚡ Ejecutar',
            button_style='danger',
            tooltip='Enviar a JARVIS',
            layout=widgets.Layout(display='none', width='120px')
        )

        close_btn = widgets.Button(
            description='✕',
            button_style='',
            tooltip='Cerrar',
            layout=widgets.Layout(display='none', width='40px')
        )

        status_label = widgets.HTML(
            value='',
            layout=widgets.Layout(display='none', margin='4px 0 0 0')
        )

        output_area = widgets.Output(
            layout=widgets.Layout(
                border='1px solid #2d2d2d',
                border_radius='6px',
                padding='8px',
                margin='6px 0 0 0',
                display='none',
                background_color='#1a1a2e'
            )
        )

        panel_open = [False]

        # ── Event: toggle panel ────────────────────────────────────────────
        def on_toggle(event):
            panel_open[0] = not panel_open[0]
            vis = '' if panel_open[0] else 'none'
            prompt_input.layout.display  = vis
            send_btn.layout.display      = vis
            close_btn.layout.display     = vis
            status_label.layout.display  = vis
            if panel_open[0]:
                prompt_input.focus()

        # ── Event: send prompt ─────────────────────────────────────────────
        def on_send(b):
            prompt = prompt_input.value.strip()
            if not prompt:
                status_label.value = '<span style="color:#e74c3c">⚠️ Escribí algo primero</span>'
                status_label.layout.display = ''
                return

            status_label.value = '<span style="color:#f0b429">⚡ JARVIS procesando...</span>'
            status_label.layout.display = ''
            output_area.layout.display  = ''

            prompt_input.value = ''

            with output_area:
                output_area.clear_output(wait=True)
                try:
                    _ip.run_cell_magic('JARVIS', '', prompt)
                except Exception as e:
                    from IPython.display import display as _display
                    _display(HTML(f'<span style="color:#e74c3c">❌ Error: {e}</span>'))

            status_label.value = '<span style="color:#27ae60">✅ Listo</span>'

        # ── Event: close ───────────────────────────────────────────────────
        def on_close(b):
            prompt_input.layout.display  = 'none'
            send_btn.layout.display      = 'none'
            close_btn.layout.display     = 'none'
            status_label.layout.display  = 'none'
            output_area.layout.display   = 'none'
            panel_open[0] = False

        # Usar toggle_btn como receptor (ironman_btn es HTML puro)
        # Workaround: observar value change en un IntText oculto via JS
        toggle_trigger = widgets.IntText(value=0, layout=HIDDEN)

        def on_trigger_change(change):
            on_toggle(None)

        toggle_trigger.observe(on_trigger_change, names='value')

        # Inyectar JS para conectar el botón HTML con el trigger ipywidgets
        js_glue = widgets.HTML(value="""
        <script>
        (function() {
          function attachHandler() {
            var btn = document.getElementById('jarvis-toggle');
            if (!btn) { setTimeout(attachHandler, 300); return; }
            btn.addEventListener('click', function() {
              // Buscar el input oculto del toggle_trigger y cambiar su valor
              var inputs = document.querySelectorAll('.widget-text input');
              inputs.forEach(function(inp) {
                if (inp.closest('.widget-box') && inp.type === 'number') {
                  inp.value = parseInt(inp.value || 0) + 1;
                  inp.dispatchEvent(new Event('change', {bubbles: true}));
                }
              });
            });
          }
          attachHandler();
        })();
        </script>
        """)

        send_btn.on_click(on_send)
        close_btn.on_click(on_close)

        # ── Render ─────────────────────────────────────────────────────────
        header = widgets.HBox(
            [ironman_btn, toggle_trigger, js_glue],
            layout=widgets.Layout(align_items='center', gap='8px')
        )
        action_row = widgets.HBox(
            [send_btn, close_btn],
            layout=widgets.Layout(gap='6px', margin='4px 0 0 0')
        )
        full_panel = widgets.VBox(
            [header, prompt_input, action_row, status_label, output_area],
            layout=widgets.Layout(
                border='2px solid #c0392b',
                border_radius='10px',
                padding='10px',
                background_color='#0d0d1a',
                width='100%',
                max_width='900px'
            )
        )

        display(full_panel)

    except ImportError:
        print("⚠️  ipywidgets no disponible en este kernel.")
        print("     Usá %%JARVIS directamente en la celda.")
    except Exception as exc:
        print(f"⚠️  JARVIS panel error: {exc}")
        print("     Fallback: usá %%JARVIS directamente en la celda.")


# ── Alias corto ───────────────────────────────────────────────────────────────
jarvis = jarvis_panel
WIDGET_EOF
echo "==> [jarvis] Widget Iron Man Copilot configurado ✓"

echo "==> Iniciando Jupyter Lab..."

# Ejecutar el comando original de Jupyter
exec start-notebook.sh "$@"

