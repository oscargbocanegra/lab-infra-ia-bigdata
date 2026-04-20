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

