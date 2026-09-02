-- Quarto Laser Pointer Extension
-- Consolidated into a single Lua filter

local html_content = [===[
<style>
        :root {
            --background: #020617;
            --foreground: #f8fafc;
            --primary: #ef4444;
            --primary-foreground: #ffffff;
            --secondary: #1e293b;
            --muted: #334155;
            --muted-foreground: #94a3b8;
            --border: #334155;
            --radius: 0.75rem;
        }



        #laser-container {
            position: fixed;
            inset: 0;
            z-index: 999999;
            pointer-events: none;
        }

        body.laser-active #laser-container {
            cursor: none;
        }

        .toolbar, .cursor-dropdown {
            cursor: default !important;
        }

        .btn, .color-btn, .size-btn, .cursor-opt, .custom-color-input {
            cursor: pointer !important;
        }

        .reveal .controls {
            z-index: 2000000 !important;
            pointer-events: none !important;
        }
        .reveal .controls button,
        .reveal .controls .controls-arrow {
            pointer-events: auto !important;
        }

        .reveal .progress, 
        .reveal .slide-number,
        .reveal .pause-overlay,
        .indicator-settings-btn,
        .indicator-tooltip {
            z-index: 2000000 !important;
            pointer-events: auto !important;
        }

        /* Ensure menu and chalkboard elements are above our elevated controls (2,000,000) */
        .slide-menu-overlay,
        .chalkboard-canvas,
        .chalkboard-palette {
            z-index: 3000000 !important;
            pointer-events: auto !important;
        }
        
        .slide-menu,
        .slide-menu-wrapper,
        .chalkboard-button {
            z-index: 3000001 !important;
            pointer-events: auto !important;
        }

        /* Clean-revealjs theme makes these containers viewport-sized with
           pointer-events:none and only children clickable. We must respect
           that pattern: elevate z-index but keep container transparent. */
        .slide-chalkboard-buttons,
        .slide-menu-button {
            z-index: 2000001 !important;
            pointer-events: none !important;
        }

        /* Only the actual button icons inside should be clickable */
        .slide-chalkboard-buttons > *,
        .slide-menu-button > * {
            pointer-events: auto !important;
            cursor: pointer !important;
        }
        
        /* Only give pointer-events to the panel when it's actually visible */
        .indicator-settings-panel.visible {
            z-index: 2000000 !important;
            pointer-events: auto !important;
        }
        
        .reveal .controls button,
        .reveal .progress, 
        .reveal .slide-number,
        .indicator-section,
        .indicator-dot,
        .indicator-settings-btn {
            cursor: pointer !important;
            pointer-events: auto !important;
        }

        /* Panel-internal buttons: only interactive when laser is active (to avoid overriding panel's pointer-events:none) */
        body.laser-active .indicator-btn-option,
        body.laser-active .indicator-color-btn,
        body.laser-active .theme-swatch {
            cursor: pointer !important;
            pointer-events: auto !important;
        }

        /* Hide indicator settings panel when laser is active to avoid z-index conflicts */
        body.laser-active .indicator-settings-panel {
            display: none !important;
            pointer-events: none !important;
        }

        body.slide-menu-active #laser-container,
        body.slide-menu-active .toolbar,
        body.chalkboard-active #laser-container,
        body.notes-active #laser-container {
            display: none !important;
            pointer-events: none !important;
        }



        /* Hide laser pointer in the "Next Slide" preview of the Speaker View */
        .speaker-controls-notes-window .speaker-controls-next #laser-container,
        .reveal .slides section.future #laser-container {
            display: none !important;
        }

        /* Hide the toolbar completely when running inside an iframe (like Speaker View) to prevent overlap bugs */
        body.is-iframe .toolbar {
            display: none !important;
        }

        body.laser-active #laser-canvas {
            cursor: none !important;
        }

        #laser-canvas {
            position: absolute;
            inset: 0;
            pointer-events: auto;
            touch-action: none;
            z-index: 1; /* Ensure canvas stays below indicator panels */
        }

        .grid-pattern {
            position: absolute;
            inset: 0;
            opacity: 0.04;
            background-image: 
                linear-gradient(rgba(255,255,255,0.1) 1px, transparent 1px), 
                linear-gradient(90deg, rgba(255,255,255,0.1) 1px, transparent 1px);
            background-size: 40px 40px;
            pointer-events: none;
        }

        .toolbar {
            position: absolute;
            bottom: 24px;
            left: 50%;
            transform: translateX(-50%);
            display: flex;
            align-items: center;
            gap: 12px;
            padding: 12px 20px;
            border-radius: 1.25rem;
            background: rgba(255, 255, 255, 0.9);
            backdrop-filter: blur(16px);
            border: 1px solid rgba(0, 0, 0, 0.1);
            box-shadow: 0 10px 30px -5px rgba(0, 0, 0, 0.1), 0 20px 25px -5px rgba(0, 0, 0, 0.05);
            pointer-events: auto;
            user-select: none;
            z-index: 1000000;
            transition: opacity 0.3s, transform 0.3s;
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
        }

        .toolbar.hidden {
            opacity: 0;
            pointer-events: none;
        }

        .divider {
            width: 1px;
            height: 28px;
            background: rgba(0, 0, 0, 0.1);
        }

        .mode-toggle {
            display: flex;
            gap: 4px;
            padding: 2px;
            background: rgba(0, 0, 0, 0.05);
            border-radius: 0.5rem;
        }

        .btn {
            display: flex;
            align-items: center;
            gap: 6px;
            padding: 6px 12px;
            border-radius: 0.375rem;
            font-size: 12px;
            font-weight: 500;
            border: none;
            cursor: pointer !important;
            transition: all 0.2s;
            color: #64748b;
            background: transparent;
        }

        .btn span {
            display: inline;
        }

        @media (max-width: 700px) {
            .btn span { display: none; }
            .toolbar { gap: 8px; padding: 10px 14px; }
            .divider { height: 20px; }
        }

        .btn:hover {
            color: var(--foreground);
        }

        .btn.active {
            background: #ef4444; 
            color: white;
            box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1);
        }

        .btn.power-off {
            background: #64748b !important;
            color: white !important;
            opacity: 0.6;
        }

        .btn.power-on {
            background: #22c55e !important;
            color: white !important;
        }

        @media (max-width: 600px) {
            .toolbar {
                gap: 8px;
                padding: 8px 12px;
                bottom: 12px;
            }
            .btn {
                padding: 6px 8px;
            }
            .btn span, .btn text-node { /* Hide text if we had spans, but we have text nodes */
                display: none;
            }
            /* Target text inside buttons */
            .btn { font-size: 0; }
            .btn svg { margin: 0; }
            .divider { height: 20px; }
        }

        @media (max-width: 400px) {
            .toolbar {
                gap: 4px;
                padding: 4px 8px;
            }
            .color-btn, .custom-color-wrapper {
                width: 24px;
                height: 24px;
            }
            .size-btn {
                width: 28px;
                height: 28px;
            }
            .color-group { gap: 4px; }
        }

        .color-group {
            display: flex;
            gap: 8px;
            align-items: center;
        }

        .color-btn {
            width: 28px;
            height: 28px;
            border-radius: 50%;
            border: 2px solid transparent;
            cursor: pointer !important;
            transition: transform 0.2s;
        }

        .color-btn:hover {
            transform: scale(1.1);
        }

        .color-btn.active {
            transform: scale(1.15);
            border-color: white;
            box-shadow: 0 0 12px rgba(255, 45, 45, 0.6);
        }

        .custom-color-wrapper {
            position: relative;
            width: 28px;
            height: 28px;
            border-radius: 50%;
            overflow: hidden;
            background: conic-gradient(#ff2d2d, #ffdd2d, #2dff6d, #2d9cff, #a855f7, #ff2d2d);
            cursor: pointer;
            display: flex;
            align-items: center;
            justify-content: center;
        }

        .custom-color-input {
            position: absolute;
            inset: 0;
            width: 100%;
            height: 100%;
            opacity: 0;
            cursor: pointer !important;
        }

        .size-group {
            display: flex;
            gap: 6px;
        }

        .size-btn {
            width: 32px;
            height: 32px;
            border-radius: 0.5rem;
            display: flex;
            align-items: center;
            justify-content: center;
            font-size: 11px;
            font-weight: 600;
            background: transparent;
            color: #64748b;
            border: none;
            cursor: pointer !important;
        }

        .size-btn:hover {
            background: rgba(0, 0, 0, 0.05);
        }

        .size-btn.active {
            background: var(--primary);
            color: white;
        }

        .cursor-dropdown {
            position: absolute;
            bottom: 80px;
            left: 50%;
            transform: translateX(-50%);
            display: flex;
            gap: 8px;
            padding: 12px 16px;
            background: rgba(30, 41, 59, 0.9);
            backdrop-filter: blur(16px);
            border: 1px solid rgba(148, 163, 184, 0.2);
            border-radius: 0.75rem;
            box-shadow: 0 20px 25px -5px rgba(0, 0, 0, 0.3);
            pointer-events: auto;
            display: none;
            cursor: pointer !important;
            z-index: 1000001;
        }

        .cursor-dropdown.show {
            display: flex;
        }

        .cursor-opt {
            display: flex;
            flex-direction: column;
            align-items: center;
            gap: 6px;
            padding: 8px;
            border-radius: 0.5rem;
            background: transparent;
            border: none;
            cursor: pointer !important;
            transition: all 0.2s;
        }

        .cursor-opt:hover {
            background: rgba(255, 255, 255, 0.1);
        }

        .cursor-opt.active {
            background: rgba(239, 68, 68, 0.2);
            outline: 2px solid #ef4444;
        }

        .cursor-opt span {
            font-size: 10px;
            color: var(--muted-foreground);
        }

        .hint {
            position: absolute;
            top: 24px;
            left: 50%;
            transform: translateX(-50%);
            color: rgba(148, 163, 184, 0.5);
            font-size: 14px;
            font-weight: 500;
            pointer-events: none;
            letter-spacing: 0.025em;
        }

        svg {
            pointer-events: none;
        }
    </style>

    <div id="laser-container">
        <div class="grid-pattern"></div>
        <canvas id="laser-canvas"></canvas>

        <div class="cursor-dropdown" id="cursor-dropdown" onmousedown="event.stopPropagation()">
            <!-- Populated by JS -->
        </div>

        <div class="toolbar hidden" id="toolbar" onmousedown="event.stopPropagation()">
            <button class="btn power-off" id="btn-power" onclick="togglePower()">
                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M18.36 6.64a9 9 0 1 1-12.73 0"/><line x1="12" y1="2" x2="12" y2="12"/></svg>
                <span>OFF</span>
            </button>

            <div class="divider"></div>

            <div class="mode-toggle">
                <button class="btn active" id="mode-laser" onclick="setMode('laser')">
                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="3"/><line x1="12" y1="3" x2="12" y2="6"/><line x1="12" y1="18" x2="12" y2="21"/><line x1="3" y1="12" x2="6" y2="12"/><line x1="18" y1="12" x2="21" y2="12"/></svg>
                    <span>Laser</span>
                </button>
                <button class="btn" id="mode-highlighter" onclick="setMode('highlighter')">
                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 20h9"/><path d="M16.376 3.622a1 1 0 0 1 3.002 3.002L7.368 18.635a2 2 0 0 1-.855.506l-2.872.838a.5.5 0 0 1-.62-.62l.838-2.872a2 2 0 0 1 .506-.854z"/></svg>
                    <span>Highlight</span>
                </button>
            </div>

            <div class="divider"></div>

            <div class="color-group" id="color-presets">
                <!-- Populated by JS -->
                <div class="custom-color-wrapper" id="custom-color-wrapper">
                    <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="3"><path d="M12 5v14M5 12h14"/></svg>
                    <input type="color" class="custom-color-input" id="custom-color" value="#ff2d2d">
                </div>
            </div>

            <div class="divider"></div>

            <div class="size-group">
                <button class="size-btn" onclick="setSize(0)">S</button>
                <button class="size-btn active" onclick="setSize(1)">M</button>
                <button class="size-btn" onclick="setSize(2)">L</button>
            </div>

            <div class="divider"></div>

            <button class="btn" onclick="toggleCursorPicker()" id="cursor-picker-btn">
                <div id="current-cursor-preview"></div>
                <span>Cursor</span>
            </button>

            <div class="divider"></div>

            <button class="btn" onclick="clearAll()">
                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M3 6h18M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2"/></svg>
                <span>Clear</span>
            </button>
        </div>
    </div>

    <script>
        const canvas = document.getElementById('laser-canvas');
        const ctx = canvas.getContext('2d');
        const toolbar = document.getElementById('toolbar');
        const hintText = document.getElementById('hint-text');
        const cursorDropdown = document.getElementById('cursor-dropdown');
        const customColorInput = document.getElementById('custom-color');

        const FADE_DURATION = 1500;
        const FADE_DELAY = 1500;
        const STROKE_LIFETIME = FADE_DELAY + FADE_DURATION;
        const CURSOR_IDLE_TIMEOUT = 5000;
        const HIGHLIGHTER_OPACITY = 0.35;
        const HIGHLIGHTER_WIDTH_MULTIPLIER = 8;

        const PRESET_COLORS = [
            { name: "Red", value: "#ff2d2d", glow: "rgba(255, 45, 45, 0.6)" },
            { name: "Blue", value: "#2d9cff", glow: "rgba(45, 156, 255, 0.6)" },
            { name: "Green", value: "#2dff6d", glow: "rgba(45, 255, 109, 0.6)" },
            { name: "Yellow", value: "#ffdd2d", glow: "rgba(255, 221, 45, 0.6)" },
            { name: "Orange", value: "#ff8c2d", glow: "rgba(255, 140, 45, 0.6)" },
        ];

        const SIZES = [2, 4, 7];
        const CURSORS = ["dot", "crosshair", "ring"];

        let state = {
            strokes: [],
            isDrawing: false,
            currentPoints: [],
            mousePos: { x: -100, y: -100 },
            isMouseOnCanvas: false,
            lastMoveTime: Date.now(),
            activeTool: 'laser',
            selectedColorIndex: 0,
            activeColor: PRESET_COLORS[0],
            selectedSizeIndex: 1,
            selectedCursor: 'dot',
            isCustomColor: false,
            isToolbarVisible: false,
            isEnabled: false,
            qTimer: null,
            syncChannel: new BroadcastChannel('quarto-laser-sync-' + (window.location.pathname || 'default')),
            isUiHover: false,
            isThemeLight: false
        };

        function checkThemeBrightness() {
            const el = document.querySelector('.reveal') || document.body;
            const computedColor = window.getComputedStyle(el).color;
            // E.g., rgb(34, 34, 34)
            const match = computedColor.match(/\d+/g);
            if (match && match.length >= 3) {
                // Approximate brightness based on text color.
                // If text is dark (Y < 128), it's a light theme.
                const brightness = (parseInt(match[0]) * 299 + parseInt(match[1]) * 587 + parseInt(match[2]) * 114) / 1000;
                state.isThemeLight = brightness < 128;
            }
        }
        setInterval(checkThemeBrightness, 1000);
        checkThemeBrightness();

        function getRevealContainer() {
            // Table IV's zoomed lightbox popup: using the viewport (or
            // body) as the coordinate basis was still wrong across two
            // windows with different resolutions/aspect ratios, because
            // the image inside the popup is centered and letterboxed
            // (`max-width:92vw; max-height:92vh`) -- how much empty space
            // surrounds it depends on THAT window's own aspect ratio, so
            // a fraction-of-viewport normalization lands on a different
            // point of the image in a window with different letterboxing.
            // The <img> element's own getBoundingClientRect() already
            // accounts for all of that (centering, max-width/height,
            // actual aspect ratio) and gives the image's true on-screen
            // box directly -- using it as the basis makes a normalized
            // [0,1] fraction land on the same point of the image in any
            // window, regardless of that window's own resolution.
            const openLightboxImg = document.querySelector('.lightbox-overlay.is-open img');
            if (openLightboxImg) return openLightboxImg;
            // In Speaker View, the notes window is structured as .speaker-controls-notes-window > .current-slide > .reveal > .slides
            // The `.slides` layer has the transform: scale() applied.
            const speakerNotesSlides = document.querySelector('.speaker-controls-notes-window .current-slide .reveal .slides');
            if (speakerNotesSlides) return speakerNotesSlides;
            return document.querySelector('.reveal .slides') || document.querySelector('.reveal') || document.body;
        }

        function getContainerRect(container) {
            return container.getBoundingClientRect();
        }

        state.syncChannel.onmessage = (event) => {
            const msg = event.data;

            // Only process drawing events if they were meant for the exact same slide (fixes upcoming-slide iframe bug)
            const currentHash = window.location.hash || '#/';
            if (msg.slide && msg.slide !== currentHash) return;

            const container = getRevealContainer();
            const rect = getContainerRect(container);

            switch (msg.type) {
                case 'move':
                    state.mousePos = { x: msg.x * rect.width, y: msg.y * rect.height };
                    state.lastMoveTime = Date.now();
                    break;
                case 'start-draw':
                    state.isDrawing = true;
                    state.currentPoints = [{ x: msg.x * rect.width, y: msg.y * rect.height }];
                    break;
                case 'stroke-point':
                    if (state.isDrawing) {
                        state.currentPoints.push({ x: msg.x * rect.width, y: msg.y * rect.height });
                    }
                    break;
                case 'end-draw':
                    state.isDrawing = false;
                    if (state.currentPoints.length > 1) {
                        state.strokes.push({
                            points: [...state.currentPoints],
                            createdAt: Date.now(),
                            color: msg.color,
                            tool: msg.tool,
                            lineWidth: msg.lineWidth
                        });
                    }
                    state.currentPoints = [];
                    break;
                case 'tool':
                    if (msg.mode) setMode(msg.mode, true);
                    if (msg.sizeIndex !== undefined) setSize(msg.sizeIndex, true);
                    if (msg.cursor) selectCursor(msg.cursor, true);
                    if (msg.color) {
                        state.activeColor = msg.color;
                        state.isCustomColor = msg.isCustom;
                        state.selectedColorIndex = msg.colorIndex;
                        updateColorUI();
                    }
                    break;
                case 'clear':
                    state.strokes = [];
                    break;
                case 'power':
                    setPower(msg.enabled, true);
                    break;
            }
        };

        function broadcast(data) {
            data.slide = window.location.hash || '#/';
            state.syncChannel.postMessage(data);
        }

        function initUI() {
            const presetsContainer = document.getElementById('color-presets');
            PRESET_COLORS.forEach((color, index) => {
                const btn = document.createElement('div');
                btn.className = 'color-btn' + (index === 0 ? ' active' : '');
                btn.style.backgroundColor = color.value;
                btn.onclick = () => selectPresetColor(index);
                presetsContainer.insertBefore(btn, document.getElementById('custom-color-wrapper'));
            });

            const cursorDropdown = document.getElementById('cursor-dropdown');
            CURSORS.forEach(type => {
                const opt = document.createElement('button');
                opt.className = 'cursor-opt' + (type === 'dot' ? ' active' : '');
                opt.onclick = () => selectCursor(type);
                opt.innerHTML = `<div class="preview-svg">${getCursorSVG(type, 18, true)}</div><span>${type.charAt(0).toUpperCase() + type.slice(1)}</span>`;
                cursorDropdown.appendChild(opt);
            });
            updateCursorPreview();
        }

        function hexToGlow(hex) {
            const r = parseInt(hex.slice(1, 3), 16);
            const g = parseInt(hex.slice(3, 5), 16);
            const b = parseInt(hex.slice(5, 7), 16);
            return `rgba(${r}, ${g}, ${b}, 0.6)`;
        }

        function selectPresetColor(index) {
            state.selectedColorIndex = index;
            state.isCustomColor = false;
            state.activeColor = PRESET_COLORS[index];
            updateColorUI();
            broadcast({ type: 'tool', color: state.activeColor, isCustom: false, colorIndex: index });
        }

        customColorInput.oninput = (e) => {
            state.isCustomColor = true;
            const val = e.target.value;
            state.activeColor = { name: "Custom", value: val, glow: hexToGlow(val) };
            updateColorUI();
            broadcast({ type: 'tool', color: state.activeColor, isCustom: true });
        };

        function updateColorUI() {
            document.querySelectorAll('.color-btn').forEach((btn, i) => { btn.classList.toggle('active', !state.isCustomColor && state.selectedColorIndex === i); });
            const wrapper = document.getElementById('custom-color-wrapper');
            wrapper.style.boxShadow = state.isCustomColor ? `0 0 0 2px var(--background), 0 0 0 4px ${state.activeColor.value}, 0 0 12px ${state.activeColor.glow}` : 'none';
            wrapper.style.background = state.isCustomColor ? state.activeColor.value : '';
            document.documentElement.style.setProperty('--primary', state.activeColor.value);
            updateCursorPreview();
        }

        function setMode(mode, remote = false) {
            state.activeTool = mode;
            document.getElementById('mode-laser').classList.toggle('active', mode === 'laser');
            document.getElementById('mode-highlighter').classList.toggle('active', mode === 'highlighter');
            hintText.innerText = mode === 'laser' ? "Click and drag to draw" : "Click and drag to highlight";
            if (!remote) broadcast({ type: 'tool', mode });
        }

        function setSize(index, remote = false) {
            state.selectedSizeIndex = index;
            document.querySelectorAll('.size-btn').forEach((btn, i) => { btn.classList.toggle('active', i === index); });
            if (!remote) broadcast({ type: 'tool', sizeIndex: index });
        }

        function toggleCursorPicker() { cursorDropdown.classList.toggle('show'); }

        function selectCursor(type, remote = false) {
            state.selectedCursor = type;
            document.querySelectorAll('.cursor-opt').forEach(opt => { opt.classList.toggle('active', opt.querySelector('span').innerText.toLowerCase() === type); });
            cursorDropdown.classList.remove('show');
            updateCursorPreview();
            if (!remote) broadcast({ type: 'tool', cursor: type });
        }

        function updateCursorPreview() { document.getElementById('current-cursor-preview').innerHTML = getCursorSVG(state.selectedCursor, 18, true); }

        function togglePower() {
            setPower(!state.isEnabled);
        }

        function setPower(enabled, remote = false) {
            state.isEnabled = enabled;
            document.body.classList.toggle('laser-active', enabled);
            const btn = document.getElementById('btn-power');
            if (btn) {
                btn.classList.toggle('power-on', enabled);
                btn.classList.toggle('power-off', !enabled);
                btn.innerHTML = enabled ? 
                    `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M18.36 6.64a9 9 0 1 1-12.73 0"/><line x1="12" y1="2" x2="12" y2="12"/></svg> <span>ON</span>` :
                    `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M18.36 6.64a9 9 0 1 1-12.73 0"/><line x1="12" y1="2" x2="12" y2="12"/></svg> <span>OFF</span>`;
            }
            
            canvas.style.pointerEvents = enabled ? 'auto' : 'none';
            if (!enabled) {
                state.isDrawing = false;
                state.currentPoints = [];
            }
            
            if (!remote) broadcast({ type: 'power', enabled });
        }
        // Expose globally so other extensions (e.g. progress-indicator) can turn off the laser
        window.laserPointerSetPower = setPower;

        function getCursorSVG(type, s, active) {
            const color = active ? state.activeColor.value : "currentColor";
            const innerDotFill = state.isThemeLight ? color : "white";
            const innerDotOpacity = state.isThemeLight ? "1" : "0.9";
            const cx = s / 2, cy = s / 2;
            switch (type) {
                case "dot": return `<svg width="${s}" height="${s}" viewBox="0 0 ${s} ${s}"><circle cx="${cx}" cy="${cy}" r="4" fill="${color}" /><circle cx="${cx}" cy="${cy}" r="1.5" fill="${innerDotFill}" opacity="${innerDotOpacity}" /></svg>`;
                case "crosshair": return `<svg width="${s}" height="${s}" viewBox="0 0 ${s} ${s}"><line x1="${cx}" y1="2" x2="${cx}" y2="6" stroke="${color}" stroke-width="1.5" stroke-linecap="round"/><line x1="${cx}" y1="${s-6}" x2="${cx}" y2="${s-2}" stroke="${color}" stroke-width="1.5" stroke-linecap="round"/><line x1="2" y1="${cy}" x2="6" y2="${cy}" stroke="${color}" stroke-width="1.5" stroke-linecap="round"/><line x1="${s-6}" y1="${cy}" x2="${s-2}" y2="${cy}" stroke="${color}" stroke-width="1.5" stroke-linecap="round"/><circle cx="${cx}" cy="${cy}" r="1" fill="${innerDotFill}" opacity="${innerDotOpacity}"/></svg>`;
                case "ring": return `<svg width="${s}" height="${s}" viewBox="0 0 ${s} ${s}"><circle cx="${cx}" cy="${cy}" r="6" fill="none" stroke="${color}" stroke-width="1.5" /><circle cx="${cx}" cy="${cy}" r="1" fill="${innerDotFill}" opacity="${innerDotOpacity}" /></svg>`;
            }
        }

        function clearAll(remote = false) {
            state.strokes = [];
            if (!remote) broadcast({ type: 'clear' });
        }

        function resize() {
            const container = getRevealContainer();
            const rect = getContainerRect(container);
            const laserContainer = document.getElementById('laser-container');
            laserContainer.style.width = rect.width + 'px';
            laserContainer.style.height = rect.height + 'px';
            const scrollTop = window.pageYOffset || document.documentElement.scrollTop;
            const scrollLeft = window.pageXOffset || document.documentElement.scrollLeft;
            laserContainer.style.top = (rect.top + scrollTop) + 'px';
            laserContainer.style.left = (rect.left + scrollLeft) + 'px';
            const dpr = window.devicePixelRatio || 1;
            canvas.width = rect.width * dpr;
            canvas.height = rect.height * dpr;
            canvas.style.width = rect.width + 'px';
            canvas.style.height = rect.height + 'px';
            ctx.scale(dpr, dpr);
        }

        window.addEventListener('resize', resize);
        if (typeof window.ResizeObserver !== 'undefined') {
            const ro = new ResizeObserver(() => resize());
            window.addEventListener('DOMContentLoaded', () => ro.observe(document.body));
        }
        resize();

        // getRevealContainer() switches container (.slides <-> full
        // viewport) the instant a lightbox popup opens or closes, but
        // nothing else re-triggers resize() at that moment on its own --
        // without this, the canvas keeps the stale size/position from
        // whichever container was active when it was last computed, which
        // is exactly what produced the offset. Watched here via the
        // overlay's own class toggle (add/remove "is-open"), on every
        // .lightbox-overlay present at load (they're static elements in
        // the slide markup, just reparented to <body> on first open, so
        // observing them now covers that reparenting too).
        function watchLightboxResize() {
            document.querySelectorAll('.lightbox-overlay').forEach(function (el) {
                const mo = new MutationObserver(function () { resize(); });
                mo.observe(el, { attributes: true, attributeFilter: ['class'] });
            });
        }
        if (document.readyState === 'loading') {
            window.addEventListener('DOMContentLoaded', watchLightboxResize);
        } else {
            watchLightboxResize();
        }

        function getPoint(e) {
            const container = getRevealContainer();
            const rect = getContainerRect(container);
            const clientX = e.touches ? e.touches[0].clientX : e.clientX;
            const clientY = e.touches ? e.touches[0].clientY : e.clientY;
            
            return { 
                x: clientX - rect.left,
                y: clientY - rect.top 
            };
        }

        function isPointerOverUI(e) {
            let x, y;
            if (e.touches && e.touches.length > 0) {
                x = e.touches[0].clientX;
                y = e.touches[0].clientY;
            } else {
                x = e.clientX;
                y = e.clientY;
            }

            const elements = document.elementsFromPoint(x, y);
            // Find the first element that is NOT part of the laser pointer UI itself
            const target = elements.find(el => 
                el.id !== 'laser-canvas' && 
                el.id !== 'laser-container' && 
                !el.classList.contains('grid-pattern')
            );

            if (!target) return false;

            // EXPLICITLY EXCLUDE tab content area from being treated as UI 
            // so the laser works correctly over the tabbed content.
            if (target.closest('.tab-content')) return false;

            return !!(
                target.closest('.toolbar') ||
                target.closest('.cursor-dropdown') ||
                target.closest('.slide-menu-button') ||
                target.closest('.slide-chalkboard-buttons') ||
                target.closest('.slide-menu-wrapper') ||
                target.closest('.reveal-chalkboard') ||
                target.closest('.controls') ||
                target.closest('.progress') ||
                target.closest('.slide-number') ||
                target.closest('.nav-tabs') ||
                target.closest('.tabby-tabs') ||
                target.closest('[role="tablist"]') ||
                target.closest('[role="tab"]') ||
                target.closest('.indicator-settings-btn') ||
                target.closest('.indicator-settings-panel') ||
                target.closest('.indicator-tooltip') ||
                target.closest('.progress-indicator') ||
                // Table IV's zoomable header icons (Empirical Framework:
                // Geographic Extent slide): without this, the laser canvas
                // sits on top of them (z-index 999999) and swallows the
                // click as a laser stroke instead of letting it reach the
                // underlying onclick="" handler, so they were completely
                // unclickable whenever the laser was active.
                target.closest('a[onclick*="erdoganZoomOpen"]') ||
                // The popup's own close (X) button -- kept clickable so a
                // laser-pointer user can still dismiss the popup. The
                // enlarged image itself is deliberately NOT in this list:
                // while the popup is open, the laser should draw normally
                // over the image (so the presenter can point things out on
                // it), the same as it does over any other slide content.
                target.closest('.lightbox-close')
            );
        }

        canvas.addEventListener('mousedown', (e) => {
            if (!state.isEnabled || isPointerOverUI(e)) return;
            state.isDrawing = true;
            const p = getPoint(e);
            state.currentPoints = [p];
            const container = getRevealContainer();
            const rect = getContainerRect(container);
            broadcast({ type: 'start-draw', x: p.x / rect.width, y: p.y / rect.height });
        });

        window.addEventListener('mousemove', (e) => {
            if (!state.isEnabled && !state.isToolbarVisible) return;
            
            state.isUiHover = isPointerOverUI(e);
            
            // DYNAMIC POINTER EVENTS: 
            // If hovering over UI (buttons, menu, chalkboard), make canvas transparent 
            // to events so clicks and cursors pass through to the elements below.
            if (state.isEnabled) {
                canvas.style.pointerEvents = state.isUiHover ? 'none' : 'auto';
            }
            
            if (state.isUiHover) {
                if (state.isDrawing) finishDrawing();
                return;
            }

            const p = getPoint(e);
            state.mousePos = p;
            state.isMouseOnCanvas = true;
            state.lastMoveTime = Date.now();
            
            const container = getRevealContainer();
            const rect = getContainerRect(container);
            broadcast({ type: 'move', x: p.x / rect.width, y: p.y / rect.height });
            
            if (state.isDrawing) {
                state.currentPoints.push(p);
                broadcast({ type: 'stroke-point', x: p.x / rect.width, y: p.y / rect.height });
            }
        });

        function finishDrawing() {
            if (!state.isDrawing) return;
            const lw = SIZES[state.selectedSizeIndex];
            if (state.currentPoints.length > 1) {
                state.strokes.push({
                    points: [...state.currentPoints],
                    createdAt: Date.now(),
                    color: state.activeColor.value,
                    tool: state.activeTool,
                    lineWidth: state.activeTool === 'highlighter' ? lw * HIGHLIGHTER_WIDTH_MULTIPLIER : lw
                });
            }
            broadcast({ type: 'end-draw', color: state.activeColor.value, tool: state.activeTool, lineWidth: state.activeTool === 'highlighter' ? lw * HIGHLIGHTER_WIDTH_MULTIPLIER : lw });
            state.isDrawing = false;
            state.currentPoints = [];
        }

        window.addEventListener('mouseup', () => {
            finishDrawing();
        });

        canvas.addEventListener('touchstart', (e) => {
            if (!state.isEnabled || isPointerOverUI(e)) return;
            e.preventDefault(); // Only prevent default if we're actually going to draw
            state.isDrawing = true;
            const p = getPoint(e);
            const container = getRevealContainer();
            const rect = getContainerRect(container);
            state.currentPoints = [p];
            broadcast({ type: 'start-draw', x: p.x / rect.width, y: p.y / rect.height });
        }, { passive: false });

        canvas.addEventListener('touchmove', (e) => {
            if (isPointerOverUI(e)) {
                if (state.isDrawing) finishDrawing();
                return;
            }
            e.preventDefault(); // Prevent scrolling only while drawing
            const p = getPoint(e);
            const container = getRevealContainer();
            const rect = getContainerRect(container);
            state.mousePos = p;
            state.lastMoveTime = Date.now();
            if (state.isDrawing) {
                state.currentPoints.push(p);
                broadcast({ type: 'stroke-point', x: p.x / rect.width, y: p.y / rect.height });
            }
        }, { passive: false });

        canvas.addEventListener('touchend', () => {
             finishDrawing();
        });

        function drawSmoothLine(points, color, glowColor, opacity, lineWidth, tool) {
            if (points.length < 2) return;
            ctx.save();
            
            // Draw an underlying dark shadow on light themes for contrast
            if (state.isThemeLight && tool !== 'highlighter') {
                ctx.globalAlpha = opacity * 0.4;
                ctx.strokeStyle = 'rgba(0, 0, 0, 0.6)';
                ctx.lineWidth = lineWidth + 4;
                ctx.lineCap = 'round'; ctx.lineJoin = 'round';
                ctx.beginPath();
                ctx.moveTo(points[0].x, points[0].y);
                for (let i = 1; i < points.length - 1; i++) {
                    const midX = (points[i].x + points[i + 1].x) / 2;
                    const midY = (points[i].y + points[i + 1].y) / 2;
                    ctx.quadraticCurveTo(points[i].x, points[i].y, midX, midY);
                }
                ctx.lineTo(points[points.length - 1].x, points[points.length - 1].y);
                ctx.stroke();
            }

            if (tool === 'highlighter') {
                ctx.globalAlpha = opacity * HIGHLIGHTER_OPACITY;
                ctx.strokeStyle = color;
                ctx.lineWidth = lineWidth;
                ctx.lineCap = 'round'; ctx.lineJoin = 'round';
            } else {
                ctx.globalAlpha = opacity;
                ctx.shadowColor = glowColor; ctx.shadowBlur = 20 * opacity;
                ctx.strokeStyle = color; ctx.lineWidth = lineWidth;
                ctx.lineCap = 'round'; ctx.lineJoin = 'round';
            }
            ctx.beginPath();
            ctx.moveTo(points[0].x, points[0].y);
            for (let i = 1; i < points.length - 1; i++) {
                const midX = (points[i].x + points[i + 1].x) / 2;
                const midY = (points[i].y + points[i + 1].y) / 2;
                ctx.quadraticCurveTo(points[i].x, points[i].y, midX, midY);
            }
            ctx.lineTo(points[points.length - 1].x, points[points.length - 1].y);
            ctx.stroke();
            if (tool === 'laser') {
                ctx.shadowBlur = 8 * opacity;
                ctx.lineWidth = lineWidth * 0.5;
                // Use a solid color on light themes instead of white for the core
                ctx.strokeStyle = state.isThemeLight ? `rgba(${hexToRgb(color)}, ${0.9 * opacity})` : `rgba(255, 255, 255, ${0.6 * opacity})`;
                ctx.stroke();
            }
            ctx.restore();
        }

        // Helper to get RGB for core tinting
        function hexToRgb(hex) {
            let result = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(hex);
            return result ? `${parseInt(result[1], 16)}, ${parseInt(result[2], 16)}, ${parseInt(result[3], 16)}` : null;
        }

        function drawCursor(pos, color, glowColor, size, opacity, cursorType, tool) {
            if (opacity <= 0) return;
            ctx.save();
            ctx.globalAlpha = opacity;
            
            // Shared styling for the inner 1.5px dot
            const innerDotFill = state.isThemeLight ? color : "rgba(255,255,255,0.9)";
            const shadowBase = state.isThemeLight ? "rgba(0,0,0,0.5)" : color;

            if (tool === 'highlighter') {
                const hlRadius = (size * HIGHLIGHTER_WIDTH_MULTIPLIER) / 2;
                ctx.globalAlpha = opacity * 0.25;
                ctx.fillStyle = color;
                ctx.beginPath(); ctx.arc(pos.x, pos.y, hlRadius, 0, Math.PI * 2); ctx.fill();
                ctx.restore(); return;
            }
            
            // Outer fade ring
            const gradient = ctx.createRadialGradient(pos.x, pos.y, 0, pos.x, pos.y, 24 + size * 2);
            gradient.addColorStop(0, glowColor);
            gradient.addColorStop(0.4, glowColor.replace("0.6", "0.2"));
            gradient.addColorStop(1, "rgba(0,0,0,0)");
            ctx.fillStyle = gradient;
            ctx.beginPath(); ctx.arc(pos.x, pos.y, 24 + size * 2, 0, Math.PI * 2); ctx.fill();
            
            // Main shape shadow
            ctx.shadowColor = shadowBase; 
            ctx.shadowBlur = 15;
            
            switch (cursorType) {
                case "dot":
                    ctx.fillStyle = color; ctx.beginPath(); ctx.arc(pos.x, pos.y, 3 + size * 0.5, 0, Math.PI * 2); ctx.fill();
                    ctx.shadowBlur = 0; ctx.fillStyle = innerDotFill;
                    ctx.beginPath(); ctx.arc(pos.x, pos.y, 1.5, 0, Math.PI * 2); ctx.fill();
                    break;
                case "crosshair":
                    const arm = 10 + size * 2, gap = 4;
                    ctx.strokeStyle = color; ctx.lineWidth = 2; ctx.lineCap = "round";
                    ctx.beginPath(); ctx.moveTo(pos.x, pos.y - gap); ctx.lineTo(pos.x, pos.y - arm); ctx.moveTo(pos.x, pos.y + gap); ctx.lineTo(pos.x, pos.y + arm); ctx.moveTo(pos.x - gap, pos.y); ctx.lineTo(pos.x - arm, pos.y); ctx.moveTo(pos.x + gap, pos.y); ctx.lineTo(pos.x + arm, pos.y); ctx.stroke();
                    ctx.shadowBlur = 0; ctx.fillStyle = innerDotFill; ctx.beginPath(); ctx.arc(pos.x, pos.y, 1.5, 0, Math.PI * 2); ctx.fill();
                    break;
                case "ring":
                    ctx.strokeStyle = color; ctx.lineWidth = 2.5;
                    ctx.beginPath(); ctx.arc(pos.x, pos.y, 8 + size * 1.5, 0, Math.PI * 2); ctx.stroke();
                    ctx.shadowBlur = 0; ctx.fillStyle = innerDotFill; ctx.beginPath(); ctx.arc(pos.x, pos.y, 1.5, 0, Math.PI * 2); ctx.fill();
                    break;
            }
            ctx.restore();
        }

        function animate() {
            ctx.clearRect(0, 0, canvas.width, canvas.height);
            if (!state.isEnabled) {
                requestAnimationFrame(animate);
                return;
            }
            const now = Date.now();
            state.strokes = state.strokes.filter(s => now - s.createdAt < STROKE_LIFETIME);
            state.strokes.forEach(s => {
                const elapsed = now - s.createdAt;
                const opacity = elapsed > FADE_DELAY ? 1 - (elapsed - FADE_DELAY) / FADE_DURATION : 1;
                drawSmoothLine(s.points, s.color, hexToGlow(s.color), Math.max(0, opacity), s.lineWidth, s.tool);
            });
            if (state.isDrawing && state.currentPoints.length > 1) {
                const lw = SIZES[state.selectedSizeIndex];
                const currentLw = state.activeTool === 'highlighter' ? lw * HIGHLIGHTER_WIDTH_MULTIPLIER : lw;
                drawSmoothLine(state.currentPoints, state.activeColor.value, state.activeColor.glow, 1, currentLw, state.activeTool);
            }
            const idleTime = now - state.lastMoveTime;
            if (idleTime < CURSOR_IDLE_TIMEOUT && !state.isUiHover) {
                const fadeStart = CURSOR_IDLE_TIMEOUT - FADE_DURATION;
                const opacity = idleTime > fadeStart ? 1 - (idleTime - fadeStart) / FADE_DURATION : 1;
                drawCursor(state.mousePos, state.activeColor.value, state.activeColor.glow, SIZES[state.selectedSizeIndex], Math.max(0, opacity), state.selectedCursor, state.activeTool);
            }
            requestAnimationFrame(animate);
        }

        window.addEventListener('keydown', (e) => { 
            if (e.key.toLowerCase() === 'q') { 
                if (state.qTimer) {
                    // Double tap QQ: Toggle Toolbar
                    clearTimeout(state.qTimer);
                    state.qTimer = null;
                    state.isToolbarVisible = !state.isToolbarVisible; 
                    toolbar.classList.toggle('hidden', !state.isToolbarVisible); 
                } else {
                    // First press: Start timer for single tap (Toggle Power)
                    state.qTimer = setTimeout(() => {
                        togglePower();
                        state.qTimer = null;
                    }, 250);
                }
            } 
        });
        // Close menu if clicking outside or handle other shortcuts if needed
        setInterval(() => { if (!state.isToolbarVisible) return; const idle = Date.now() - state.lastMoveTime; const shouldHide = idle > 5000 && !state.isDrawing; toolbar.classList.toggle('hidden', shouldHide); }, 1000);
        function startLaserPointer() {
            if (window._laserPointerInitialized) return;
            window._laserPointerInitialized = true;
            console.log("Initializing Quarto Laser Pointer...");
            
            let isUpcoming = false;
            try {
                if (window.self !== window.top) {
                    document.body.classList.add('is-iframe');
                    if (window.frameElement && (window.frameElement.id === 'upcoming-slide' || window.frameElement.classList.contains('future'))) {
                        isUpcoming = true;
                    }
                }
            } catch (e) {}

            if (isUpcoming) {
                 console.log("Quarto Laser Pointer: Upcoming slide detected, skipping.");
                 return;
            }

            const container = document.getElementById('laser-container'); 
            if (container && container.parentElement !== document.body) { 
                document.body.appendChild(container); 
            } 
            
            initUI();
            setPower(state.isEnabled, true);
            animate();

            // Clear drawings automatically when the slide changes
            if (typeof Reveal !== 'undefined') {
                if (Reveal.isReady()) {
                    Reveal.on('slidechanged', () => clearAll(true));
                } else {
                    Reveal.on('ready', () => {
                         console.log("Quarto Laser Pointer: Reveal.js is ready.");
                         Reveal.on('slidechanged', () => clearAll(true));
                    });
                }
            }
        }

        if (document.readyState === 'loading') {
            window.addEventListener('DOMContentLoaded', startLaserPointer);
        } else {
            startLaserPointer();
        }
        
        // Final fallback for Reveal.js environments that load dynamically
        if (typeof Reveal !== 'undefined' && !Reveal.isReady()) {
            Reveal.on('ready', startLaserPointer);
        }
    </script>
]===]

function Pandoc(doc)
  if not quarto.doc.is_format("html:js") then
    return doc
  end
  -- Append the laser pointer HTML directly into the document blocks
  table.insert(doc.blocks, pandoc.RawBlock('html', html_content))
  return doc
end
