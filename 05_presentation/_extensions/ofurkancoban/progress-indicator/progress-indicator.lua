-- progress-indicator.lua
-- Quarto Lua filter for Progress Indicator extension.
-- CSS and JS are embedded directly so no external files are needed.

local css = [====[
/* progress-indicator styles */
:root {
    --progress-position: bottom; /* top or bottom */
    --primary-color: #0d4770;
    --completed-color: #0d4770;
    --dot-size: 8px;
    --section-spacing: 15px;
    --progress-alignment: center; /* left, center, right */
    --dim-inactive: true; /* true or false */
    --hide-on-title: true; /* true or false */
    --inactive-color: #bbbbbb; /* Improved visibility for inactive dots */
}

/* Hide default Reveal.js progress bar */
.reveal .progress {
    display: none !important;
}

/* Ensure slide number is visible */
.reveal .slide-number {
    display: block !important;
    z-index: 2000 !important;
    position: fixed !important;
    /* Color fix in case of theme conflict */
    color: inherit; 
}

/* Speaker View Iframe protection */
body.is-iframe .indicator-settings-btn,
body.is-iframe .indicator-settings-panel {
    display: none !important;
    pointer-events: none !important;
}

/* Menu Item Hover Fix */
.slide-menu-items .slide-tool-item.progress-settings-item a:hover {
    background-color: rgba(0, 0, 0, 0.05); /* Light theme hover */
    text-decoration: none;
    border-radius: 4px; /* Optional rounded corners */
}
.reveal.has-dark-background .slide-menu-items .slide-tool-item.progress-settings-item a:hover {
    background-color: rgba(255, 255, 255, 0.15); /* Dark theme hover */
}

.progress-indicator {
    position: fixed;
    left: 0;
    right: 0;
    width: auto;
    height: 60px; /* Increased from 45px to prevent clipping */
    box-sizing: border-box;
    background: var(--indicator-bg, rgba(255, 255, 255, 0.9));
    backdrop-filter: blur(5px);
    display: flex;
    justify-content: center !important; /* Force center */
    align-items: center;
    z-index: 1000;
    font-family: 'Helvetica Neue', Helvetica, Arial, sans-serif;
    padding: 5px 20px 15px 20px; /* Shift content UP: less top, more bottom */
    border-radius: 0; /* Full width shouldn't have radius */
    white-space: nowrap;
    pointer-events: none;
    opacity: 0;
    transform: translateY(0); /* Default state (will be overridden by position specific transforms) */
    transition: opacity 0.3s cubic-bezier(0.4, 0, 0.2, 1), transform 0.3s cubic-bezier(0.4, 0, 0.2, 1);
    z-index: 10; /* Lower than UI controls (menu, buttons) but higher than content */
    box-shadow: 0 4px 15px rgba(0,0,0,0.1);
}

.progress-indicator.visible {
    opacity: 1;
    transform: translateY(0) !important;
}

/* Position-specific entrance animations and padding */
.progress-indicator[data-position="bottom"] {
    bottom: 0;
    top: auto;
    border-top: 1px solid rgba(0, 0, 0, 0.1);
    border-bottom: none;
    transform: translateY(100%); /* Start off-screen */
    padding: 0 20px;
}

.progress-indicator[data-position="top"] {
    top: 0;
    bottom: auto;
    border-bottom: 1px solid rgba(0, 0, 0, 0.1);
    border-top: none;
    transform: translateY(-100%); /* Start off-screen */
    padding: 0 20px;
}

.reveal {
    transition: top 0.3s ease, bottom 0.3s ease, height 0.3s ease, margin-top 0.4s ease, margin-bottom 0.4s ease;
}

.indicator-section {
    pointer-events: auto; /* Make sections interactive */
    display: flex;
    flex-direction: column;
    align-items: center;
    margin: 0 var(--section-spacing);
}

.section-label {
    font-size: 10px;
    color: var(--label-color, #888);
    margin-bottom: 8px; /* Balanced spacing */
    text-transform: uppercase;
    letter-spacing: 1px;
    white-space: nowrap;
    transition: opacity 0.3s ease, color 0.3s ease;
}

/* Dimming feature */
.progress-indicator[data-dim="true"] .indicator-section {
    opacity: 0.7;
    transition: opacity 0.3s ease;
}

.progress-indicator[data-dim="true"] .indicator-section.active {
    opacity: 1;
}

.progress-indicator[data-dim="true"] .indicator-section.active .section-label {
    color: var(--primary-color);
    font-weight: bold;
}

.dots-container {
    display: flex;
    gap: 8px;
    transition: all 0.3s ease;
}

/* Animations */
.anim-pulse .indicator-dot.active {
    animation: ind-pulse 1.5s infinite ease-in-out;
}

@keyframes ind-pulse {
    0% { transform: scale(1.4); opacity: 1; }
    50% { transform: scale(1.8); opacity: 0.7; }
    100% { transform: scale(1.4); opacity: 1; }
}

.anim-glow .indicator-dot.active {
    animation: ind-glow 1.5s infinite alternate;
}

@keyframes ind-glow {
    from { box-shadow: 0 0 2px var(--primary-color); }
    to { box-shadow: 0 0 10px var(--primary-color), 0 0 15px var(--primary-color); }
}

.anim-bounce .indicator-dot.active {
    animation: ind-bounce 0.6s infinite alternate ease-in-out;
}

@keyframes ind-bounce {
    from { transform: scale(1.4) translateY(0); }
    to { transform: scale(1.4) translateY(-5px); }
}


/* Dark mode support - Automatic */
.progress-indicator.theme-dark {
    background: rgba(0, 0, 0, 0.8);
    border-color: rgba(255, 255, 255, 0.1);
}

.progress-indicator.theme-dark .section-label {
    color: #aaa;
}

.progress-indicator.theme-dark .indicator-dot {
    border-color: var(--primary-color);
}

/* Tooltip Styling */
.indicator-tooltip {
    position: fixed; /* Fixed relative to viewport, not parent */
    background: #333;
    color: #fff;
    font-family: 'Helvetica Neue', Helvetica, Arial, sans-serif !important;
    padding: 6px 10px;
    border-radius: 4px;
    font-size: 11px;
    font-weight: 600;
    letter-spacing: 0.5px;
    text-transform: uppercase;
    white-space: nowrap;
    pointer-events: none;
    opacity: 0;
    transform: translate(-50%, 10px);
    transition: opacity 0.2s ease, transform 0.2s ease;
    z-index: 3000; /* Higher than everything */
    box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1), 0 2px 4px -1px rgba(0, 0, 0, 0.06);
}

.indicator-tooltip.visible {
    opacity: 1;
    transform: translate(-50%, 0);
}

.indicator-tooltip.bottom {
    transform: translate(-50%, -10px);
}

.indicator-tooltip.bottom.visible {
    transform: translate(-50%, 0);
}

.indicator-tooltip.theme-dark {
    background: #fff;
    color: #333;
}

/* Transitions and Hover Effects */

.indicator-dot {
    width: var(--dot-size);
    height: var(--dot-size);
    border-radius: 50%;
    border: 1.5px solid var(--inactive-color); /* Use inactive color */
    transition: background-color 0.3s ease, border-color 0.3s ease, transform 0.2s cubic-bezier(0.175, 0.885, 0.32, 1.275);
}

.indicator-dot:hover {
    transform: scale(1.5);
    border-color: var(--primary-color); /* Highlight on hover */
}

.indicator-dot.filled {
    background-color: var(--completed-color);
    border-color: var(--completed-color);
}

.indicator-dot:hover {
    transform: scale(1.5);
}

.indicator-dot.filled {
    background-color: var(--completed-color);
    border-color: var(--completed-color);
}

.indicator-dot.active {
    transform: scale(1.4);
    /* box-shadow removed for flat style */
}

.section-label:hover {
    color: var(--primary-color);
    opacity: 1 !important;
}

/* Bar Style */
.dots-container.bar-style {
    gap: 2px;
    width: 100%; /* Fill available space */
}

.dots-container.bar-style .indicator-dot {
    border-radius: 1px;
    border: none;
    background-color: var(--inactive-color);
    width: auto;
    height: 6px; /* Thinner bar */
    flex-grow: 1; /* Expand to fill */
    transform: none !important; /* No scaling on hover for bar */
    transition: background-color 0.3s ease, flex-grow 0.3s ease;
}

.dots-container.bar-style .indicator-dot:hover {
    background-color: var(--primary-color);
    opacity: 0.8;
}

.dots-container.bar-style .indicator-dot.active {
    background-color: var(--primary-color);
}

.dots-container.bar-style .indicator-dot.filled {
    background-color: var(--completed-color);
}

/* Responsive Design */
@media (max-width: 768px) {
    .section-label {
        display: none;
    }
    
    .indicator-section {
        margin: 0 5px;
    }
    
    .progress-indicator {
        height: 30px;
        padding: 5px;
    }
    
    .reveal.has-bottom-indicator {
        bottom: 30px !important;
        height: calc(100% - 30px) !important;
    }
    
    .reveal.has-top-indicator {
        top: 30px !important;
        height: calc(100% - 30px) !important;
    }
}
/* Settings Menu Styles */
.indicator-settings-btn {
    display: none; /* Hidden to avoid blocking laser pointer – use 'i' key instead */
}

.indicator-settings-panel {
    position: fixed;
    bottom: 70px;
    left: 20px;
    right: auto;
    width: 340px;
    background: rgba(255, 255, 255, 0.95);
    backdrop-filter: blur(10px);
    border-radius: 12px;
    box-shadow: 0 5px 25px rgba(0,0,0,0.15);
    padding: 0;
    z-index: 3001;
    transform: translateY(20px);
    opacity: 0;
    pointer-events: none;
    transition: opacity 0.3s ease, transform 0.3s ease;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    color: #333;
    overflow: hidden;
    display: flex;
    flex-direction: column;
    max-height: 80vh;
}

.indicator-scroll-content {
    flex: 1;
    overflow-y: auto;
    overflow-x: hidden;
    padding: 10px 20px 20px 20px;
    -webkit-overflow-scrolling: touch;
}

.indicator-scroll-content::-webkit-scrollbar {
    width: 5px;
}
.indicator-scroll-content::-webkit-scrollbar-track {
    background: transparent;
}
.indicator-scroll-content::-webkit-scrollbar-thumb {
    background: rgba(0,0,0,0.1);
    border-radius: 3px;
}
.indicator-scroll-content::-webkit-scrollbar-thumb:hover {
    background: rgba(0,0,0,0.2);
}

.indicator-settings-panel.visible {
    transform: translateY(0);
    opacity: 1;
    pointer-events: auto;
}
.theme-swatch-group {
    display: flex;
    flex-wrap: nowrap;
    justify-content: center;
    gap: 6px;
    padding-top: 5px;
}
.theme-swatch {
    width: 28px;
    height: 28px;
    border-radius: 50%;
    border: 2px solid #eee;
    cursor: pointer;
    position: relative;
    overflow: hidden;
    transition: all 0.2s ease;
    box-shadow: 0 2px 5px rgba(0,0,0,0.05);
}
.theme-swatch:hover {
    transform: scale(1.1);
    border-color: #3366ff;
}
.theme-swatch.active {
    border-color: #3366ff;
    box-shadow: 0 0 0 2px rgba(51, 102, 255, 0.2);
}
.theme-swatch .swatch-active {
    position: absolute;
    top: 0;
    left: 0;
    width: 33.33%;
    height: 100%;
}
.theme-swatch .swatch-inactive {
    position: absolute;
    top: 0;
    left: 33.33%;
    width: 33.33%;
    height: 100%;
}
.theme-swatch .swatch-bg {
    position: absolute;
    top: 0;
    right: 0;
    width: 33.34%;
    height: 100%;
}
.theme-swatch-label {
    position: absolute;
    bottom: -18px;
    left: 50%;
    transform: translateX(-50%);
    font-size: 8px;
    font-weight: bold;
    color: #666;
    text-transform: uppercase;
    letter-spacing: 0.5px;
    white-space: nowrap;
    pointer-events: none;
    opacity: 0;
    transition: opacity 0.2s ease;
}
.theme-swatch:hover .theme-swatch-label {
    opacity: 1;
}

.indicator-settings-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 0;
    font-weight: 600;
    font-size: 14px;
    text-transform: uppercase;
    letter-spacing: 0.5px;
    border-bottom: 1px solid rgba(0,0,0,0.1);
    padding: 20px 20px 15px 20px;
    flex-shrink: 0;
    background: inherit;
    z-index: 2;
}

.indicator-setting-item {
    margin-bottom: 15px;
}

.indicator-setting-label {
    display: block;
    font-size: 12px;
    margin-bottom: 5px;
    font-weight: 500;
    color: #666;
}

/* Controls */
.indicator-btn-group {
    display: flex;
    gap: 5px;
    background: #f0f0f0;
    padding: 3px;
    border-radius: 6px;
}

.indicator-btn-option {
    flex: 1;
    border: none;
    background: transparent;
    padding: 6px;
    font-size: 11px;
    border-radius: 4px;
    cursor: pointer;
    transition: background 0.2s;
    color: #666;
}

.indicator-btn-option.active {
    background: #fff;
    box-shadow: 0 1px 3px rgba(0,0,0,0.1);
    color: #333;
    font-weight: 600;
}

input[type="range"] {
    width: 100%;
    height: 4px;
    background: #e0e0e0;
    border-radius: 2px;
    appearance: none;
}

input[type="range"]::-webkit-slider-thumb {
    appearance: none;
    width: 16px;
    height: 16px;
    background: var(--primary-color);
    border-radius: 50%;
    cursor: pointer;
    border: 2px solid #fff;
    box-shadow: 0 1px 3px rgba(0,0,0,0.2);
}

input[type="color"] {
    width: 100%;
    height: 30px;
    border: none;
    cursor: pointer;
    background: transparent;
}

.indicator-color-btn {
    width: 24px;
    height: 24px;
    border-radius: 50%;
    border: 2px solid rgba(0,0,0,0.1);
    cursor: pointer;
    transition: transform 0.2s, border-color 0.2s;
}

.indicator-color-btn:hover {
    transform: scale(1.1);
}

.indicator-color-btn.active {
    border-color: #333;
    transform: scale(1.1);
    box-shadow: 0 0 0 2px rgba(255,255,255,0.8) inset;
}

/* Info Icon Styling */
.indicator-info-btn {
    width: 20px;
    height: 20px;
    border-radius: 50%;
    background: #f0f0f0;
    color: #666;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 12px;
    font-weight: bold;
    cursor: pointer;
    transition: all 0.2s ease;
    margin-right: 8px;
    border: 1px solid #ddd;
}
.indicator-info-btn:hover {
    background: #3366ff;
    color: #fff;
    border-color: #3366ff;
}

/* Info Overlay */
.indicator-info-overlay {
    position: absolute;
    top: 0;
    left: 0;
    width: 100%;
    height: 100%;
    background: rgba(255, 255, 255, 0.98);
    backdrop-filter: blur(5px);
    z-index: 3005;
    padding: 20px;
    box-sizing: border-box;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    text-align: center;
    transform: translateX(100%);
    transition: transform 0.3s cubic-bezier(0.4, 0, 0.2, 1);
    border-radius: 12px;
}
.indicator-info-overlay.visible {
    transform: translateX(0);
}
.indicator-info-title {
    font-weight: bold;
    font-size: 16px;
    margin-bottom: 5px;
    color: #333;
}
.indicator-info-dev {
    font-size: 12px;
    color: #666;
    margin-bottom: 20px;
}
.indicator-info-links {
    display: flex;
    flex-direction: column;
    gap: 10px;
    width: 100%;
}
.indicator-info-link {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 8px;
    padding: 10px;
    background: #f8f9fa;
    border: 1px solid #eee;
    border-radius: 8px;
    text-decoration: none;
    color: #333;
    font-size: 12px;
    font-weight: 600;
    transition: all 0.2s ease;
}
.indicator-info-link:hover {
    background: #eef2ff;
    border-color: #cbd5e1;
    color: #3366ff;
}
.indicator-info-close {
    position: absolute;
    top: 15px;
    right: 15px;
    cursor: pointer;
    font-size: 18px;
    color: #999;
}
.indicator-info-close:hover {
    color: #333;
}

]====]

local js = [====[
(function() {
    function initProgressIndicator() {
        console.log("Initializing Quarto Progress Indicator...");
        try {
            let isUpcoming = false;
            if (window.self !== window.top) {
                document.body.classList.add('is-iframe');
                if (window.frameElement && (window.frameElement.id === 'upcoming-slide' || window.frameElement.classList.contains('future'))) {
                    isUpcoming = true;
                }
            }
            if (isUpcoming) return; // Completely disable in the upcoming slide iframe

            if (document.querySelector('.progress-indicator')) {
                console.log("Indicator already exists, skipping.");
                return;
            }

        const reveal = Reveal;
        // Use querySelectorAll instead of getSlides() because getSlides() omits 'uncounted' slides, 
        // which prevents the indicator from reading the H1 section dividers.
        const slides = Array.from(document.querySelectorAll('.reveal .slides section:not(.stack)'));
        
        // Configuration from Reveal.js config (set in YAML under format: revealjs: progress-indicator: ...)
        const config = (reveal.getConfig && (reveal.getConfig()['progress-indicator'] || reveal.getConfig().progressIndicator)) || {};
        
        const indicatorContainer = document.createElement('div');
        indicatorContainer.className = 'progress-indicator';
        
        // Read position and visibility from CSS variables (can be overridden by YAML)
        const style = getComputedStyle(document.documentElement);
        const position = config.position || style.getPropertyValue('--progress-position').trim() || 'bottom';
        indicatorContainer.setAttribute('data-position', position);
        
        if (position === 'top') {
            document.querySelector('.reveal').classList.add('has-top-indicator');
        } else {
            document.querySelector('.reveal').classList.add('has-bottom-indicator');
        }

        const alignment = config.alignment || style.getPropertyValue('--progress-alignment').trim() || 'center';
        indicatorContainer.setAttribute('data-alignment', alignment);
        // Force center justification if alignment is center
        if (alignment === 'center') {
            indicatorContainer.style.justifyContent = 'center';
        } else if (alignment === 'left') {
            indicatorContainer.style.justifyContent = 'flex-start';
        } else if (alignment === 'right') {
            indicatorContainer.style.justifyContent = 'flex-end';
        }

        const dimInactive = config['dim-inactive'] !== undefined ? config['dim-inactive'] : (style.getPropertyValue('--dim-inactive').trim() === 'true');
        indicatorContainer.setAttribute('data-dim', dimInactive);

        let hideOnTitle = config['hide-on-title'] !== undefined ? config['hide-on-title'] : (style.getPropertyValue('--hide-on-title').trim() === 'true');
        
        const styleConfig = config.style || 'dots'; // 'dots' or 'bar'
        
        const isClickable = config.clickable !== false; // Default true (if undefined, it's true)
        let showTooltips = config.tooltips !== false; // Default true
        let dotPageCount = false; // If true, slide number shows count among dots only
        let settingsKey = 'i';    // Key to open/close settings panel
        let toggleKey   = 'x';    // Key to toggle indicator visibility
        let autoHide    = false;  // Fade out indicator when mouse/keyboard idle
        
        document.body.appendChild(indicatorContainer);

        let hiddenIndicatorSlides = new Set(); // Stores slide indices where indicator bar is hidden
        let omittedSlides = new Set(); // Stores slide indices manually omitted from dots

        // Tooltip Element - Append to BODY to avoid clipping
        let tooltip = null;
        
        function createTooltip() {
            if (!tooltip) {
                tooltip = document.createElement('div');
                tooltip.className = 'indicator-tooltip';
                document.body.appendChild(tooltip);
            }
        }

        if (showTooltips) {
            createTooltip();
        }

        function buildDots() {
            indicatorContainer.querySelectorAll('.indicator-section').forEach(el => el.remove());
            const slides = Array.from(document.querySelectorAll('.reveal .slides section:not(.stack)'));
            
            let sections = [];
            let currentSection = null;

            slides.forEach((slide, index) => {
                const h1 = slide.querySelector('h1');
                const h2 = slide.querySelector('h2');
                const slideTitle = h1 ? h1.innerText : (h2 ? h2.innerText : "");
                
                if (h1 || currentSection === null) {
                    const sectionTitle = h1 ? h1.innerText : (currentSection ? currentSection.title : "Introduction");
                    currentSection = {
                        title: sectionTitle,
                        dots: []
                    };
                    sections.push(currentSection);
                }

                const isCoverSlide = (index === 0) && (
                    slide.classList.contains('title-slide') || 
                    slide.id === 'title-slide' ||
                    (slide.querySelector('.quarto-title-block') || slide.querySelector('h1.title'))
                );
                
                if (hideOnTitle && isCoverSlide) return;

                if (currentSection.startIndex === undefined || index < currentSection.startIndex) currentSection.startIndex = index;
                if (currentSection.endIndex === undefined || index > currentSection.endIndex) currentSection.endIndex = index;

                if (slide.classList.contains('section-slide') || slide.classList.contains('skip-progress')) return;
                
                if (omittedSlides.has(index)) return;

                const indices = reveal.getIndices(slide);
                
                currentSection.dots.push({
                    index: index,
                    h: indices.h,
                    v: indices.v,
                    title: slideTitle || `Slide ${index + 1}`
                });
            });

            let renderedSectionCount = 0;
            sections.forEach(section => {
                if (section.dots.length === 0) return;

                const sectionDiv = document.createElement('div');
                sectionDiv.className = 'indicator-section';
                sectionDiv.setAttribute('data-section-index', renderedSectionCount++);
                sectionDiv.setAttribute('data-start-index', section.startIndex);
                sectionDiv.setAttribute('data-end-index', section.endIndex);

                const label = document.createElement('div');
                label.className = 'section-label';
                label.innerText = section.title;
                
                if (isClickable) {
                    label.style.cursor = 'pointer';
                    label.style.pointerEvents = 'auto'; 
                    label.addEventListener('click', (e) => {
                        e.preventDefault();
                        e.stopPropagation();
                        e.stopImmediatePropagation();
                        const target = section.dots[0];
                        if (target.h !== undefined && target.v !== undefined) {
                            reveal.slide(target.h, target.v);
                        } else {
                            reveal.slide(target.index);
                        }
                    }, true);
                }
                
                sectionDiv.appendChild(label);

                const dotsContainer = document.createElement('div');
                dotsContainer.className = 'dots-container';
                const currentStyleConfig = indicatorContainer.getAttribute('data-style') || styleConfig;
                if (currentStyleConfig === 'bar') {
                    dotsContainer.classList.add('bar-style');
                }

                section.dots.forEach(dotData => {
                    const dot = document.createElement('div');
                    dot.className = 'indicator-dot';
                    dot.setAttribute('data-slide-index', dotData.index);
                    
                    if (isClickable) {
                        dot.style.cursor = 'pointer';
                        dot.style.pointerEvents = 'auto'; 
                        dot.addEventListener('click', (e) => {
                            e.preventDefault();
                            e.stopPropagation();
                            e.stopImmediatePropagation();
                            if (dotData.h !== undefined && dotData.v !== undefined) {
                                reveal.slide(dotData.h, dotData.v);
                            } else {
                                reveal.slide(dotData.index);
                            }
                        }, true);
                    }

                    dot.addEventListener('mouseenter', (e) => {
                        if (!showTooltips) return;
                        tooltip.innerText = dotData.title;
                        tooltip.classList.add('visible');
                        const rect = dot.getBoundingClientRect();
                        const tooltipHeight = tooltip.offsetHeight || 30;
                        
                        tooltip.style.left = (rect.left + rect.width/2) + 'px';
                        
                        const curPos = indicatorContainer.getAttribute('data-position') || position;
                        if (curPos === 'top') {
                            tooltip.style.top = (rect.bottom + 8) + 'px';
                            tooltip.classList.add('bottom');
                        } else {
                            tooltip.style.top = (rect.top - tooltipHeight - 8) + 'px'; 
                            tooltip.classList.remove('bottom');
                        }
                    });
                    
                    dot.addEventListener('mouseleave', () => {
                        tooltip.classList.remove('visible');
                    });

                    dotsContainer.appendChild(dot);
                });

                sectionDiv.appendChild(dotsContainer);
                indicatorContainer.appendChild(sectionDiv);
            });
            
            const panel = document.querySelector('.indicator-settings-panel');
            if(panel) {
                const anim = panel.querySelector('.indicator-btn-group[data-setting="animation"] .active')?.getAttribute('data-value');
                if (anim && anim !== 'none') {
                    document.querySelectorAll('.dots-container').forEach(dc => dc.classList.add(`anim-${anim}`));
                }
            }
        }
        buildDots();

        // --- Theme accent-color inheritance ---
        // Scans common Reveal.js CSS variables to auto-seed --primary-color
        // Only runs when no user-saved color exists
        function inheritThemeColor() {
            const saved = localStorage.getItem('quarto-indicator-settings');
            if (saved) {
                try {
                    const s = JSON.parse(saved);
                    if (s.primaryColor) return; // User has an explicit preference
                } catch(e) {}
            }
            const cs = getComputedStyle(document.documentElement);
            const candidates = [
                '--r-link-color',        // Reveal.js default
                '--link-color',          // Some third-party themes
                '--accent',              // Generic accent
                '--r-selection-color',   // Reveal selection highlight
                '--c-accent',            // clean-revealjs
                '--highlightColor'       // moon/night themes
            ];
            for (const v of candidates) {
                const val = cs.getPropertyValue(v).trim();
                if (val && val !== 'transparent' && val !== 'none' && val !== '') {
                    document.documentElement.style.setProperty('--primary-color', val);
                    document.documentElement.style.setProperty('--completed-color', val);
                    console.log('[ProgressIndicator] Inherited theme color', v, '=', val);
                    break;
                }
            }
        }

        function updateTheme() {
            // Detect theme brightness by looking at background color
            let el = document.querySelector('.reveal');
            let background = getComputedStyle(el).backgroundColor;
            
            // If transparent, look at parents
            while (background === 'rgba(0, 0, 0, 0)' || background === 'transparent' || background === 'rgba(0,0,0,0)') {
                if (!el.parentElement) break;
                el = el.parentElement;
                background = getComputedStyle(el).backgroundColor;
            }

            const rgb = background.match(/\d+/g);
            if (rgb) {
                const brightness = (parseInt(rgb[0]) * 299 + parseInt(rgb[1]) * 587 + parseInt(rgb[2]) * 114) / 1000;
                if (brightness < 128) {
                    indicatorContainer.classList.add('theme-dark');
                    if (tooltip) tooltip.classList.add('theme-dark');
                } else {
                    indicatorContainer.classList.remove('theme-dark');
                    if (tooltip) tooltip.classList.remove('theme-dark');
                }
            }
        }

        // Helper: compute the dot-number (1-based position of currentIndex among dot indices)
        function getDotPosition(currentIndex) {
            const allDots = document.querySelectorAll('.indicator-dot');
            let pos = 0;
            allDots.forEach(dot => {
                const idx = parseInt(dot.getAttribute('data-slide-index'));
                if (idx <= currentIndex) pos++;
            });
            return pos;
        }

        // Helper: total dot count
        function getTotalDots() {
            return document.querySelectorAll('.indicator-dot').length;
        }

        // Override or restore Reveal's slide number text
        function updateSlideNumber(currentIndex) {
            const el = document.querySelector('.reveal .slide-number');
            if (!el) return;
            if (dotPageCount) {
                const pos = getDotPosition(currentIndex);
                const total = getTotalDots();
                if (total > 0) {
                    el.textContent = `${pos} / ${total}`;
                }
            } else {
                // Let Reveal.js re-generate the original number
                el.textContent = '';
            }
        }

        function updateDots(event) {
            updateTheme();
            const revealEl = document.querySelector('.reveal');
            
            // Calculate absolute flat index using the DOM array to match dot generation logic,
            // ignoring Reveal's internal count which skips 'uncounted' slides.
            const currentSlide = reveal.getCurrentSlide();
            const allSlides = Array.from(document.querySelectorAll('.reveal .slides section:not(.stack)'));
            const currentIndex = allSlides.indexOf(currentSlide);
            
            console.log(`DEBUG: updateDots - Current: ${currentIndex}`);
            
            // Hide on title slide logic + .hide-progress support + manual hide
            const isExplicitlyHidden = currentSlide && (
                currentSlide.classList.contains('hide-progress') || 
                (currentSlide.parentElement && currentSlide.parentElement.tagName === 'SECTION' && currentSlide.parentElement.classList.contains('hide-progress'))
            );
            
            // Check if hidden by index in settings
            const isManuallyHidden = hiddenIndicatorSlides.has(currentIndex);

            if ((hideOnTitle && currentIndex === 0) || isExplicitlyHidden || isManuallyHidden) {
                indicatorContainer.classList.remove('visible');
                indicatorContainer.style.pointerEvents = 'none';

                const viewportEl = document.querySelector('.reveal-viewport') || document.body;

                // Reset screen shift
                revealEl.style.removeProperty('padding-top'); 
                viewportEl.style.removeProperty('height');
                viewportEl.style.removeProperty('margin-top');
                viewportEl.style.removeProperty('margin-bottom');
                viewportEl.style.removeProperty('box-sizing');
                viewportEl.style.removeProperty('position');
                
                // Reset ALL elements that we previously forced to absolute
                // Uses a data attribute to track which elements were modified
                document.querySelectorAll('[data-pi-original-position]').forEach(el => {
                    const orig = el.getAttribute('data-pi-original-position');
                    el.style.setProperty('position', orig);
                    el.removeAttribute('data-pi-original-position');
                    el.style.removeProperty('top');
                    el.style.removeProperty('bottom');
                    el.style.removeProperty('z-index');
                    el.style.removeProperty('transition');
                });
            } else {
                indicatorContainer.classList.add('visible');
                indicatorContainer.style.pointerEvents = 'auto';
                
                const viewportEl = document.querySelector('.reveal-viewport') || document.body;
                const isTop = indicatorContainer.getAttribute('data-position') === 'top';
                const barHeight = indicatorContainer.offsetHeight || 50;
                const offset = barHeight; // bar height only

                // Canvas Resize Logic to prevent overlap (theme-agnostic)
                viewportEl.style.setProperty('height', `calc(100vh - ${offset}px)`, 'important');
                viewportEl.style.setProperty('box-sizing', 'border-box', 'important');
                viewportEl.style.setProperty('position', 'relative', 'important');
                
                if (isTop) {
                     viewportEl.style.setProperty('margin-top', `${offset}px`, 'important');
                     viewportEl.style.setProperty('margin-bottom', '0px', 'important');
                } else {
                     viewportEl.style.setProperty('margin-top', '0px', 'important');
                     viewportEl.style.setProperty('margin-bottom', `${offset}px`, 'important');
                }
                
                // Theme-agnostic: find ALL position:fixed elements and convert them
                // This works across any Reveal.js theme (clean-revealjs, simple, moon, etc.)
                document.querySelectorAll('body *').forEach(el => {
                    // Skip the indicator itself and its children
                    if (indicatorContainer.contains(el)) return;
                    // Skip elements inside .reveal .slides (actual slide content)
                    if (el.closest('.slides')) return;
                    // Skip tooltip and settings panel - they need position:fixed to render properly
                    if (el.classList.contains('indicator-tooltip')) return;
                    if (el.classList.contains('indicator-settings-panel')) return;
                    
                    const computed = window.getComputedStyle(el);
                    if (computed.position === 'fixed') {
                        // Save original position so we can restore it later
                        if (!el.hasAttribute('data-pi-original-position')) {
                            el.setAttribute('data-pi-original-position', 'fixed');
                        }
                        el.style.setProperty('position', 'absolute', 'important');
                    }
                });
                
                // Remove legacy padding if it existed
                revealEl.style.removeProperty('padding-top');
            }
            
            // Trigger layout update
            if (reveal.layout) reveal.layout();

            // Update slide number override
            updateSlideNumber(currentIndex);

            const allDots = document.querySelectorAll('.indicator-dot');
            let activeSectionIndex = -1;
            
            // 1. Update Dots status (Filled/Active)
            allDots.forEach(dot => {
                const slideIndex = parseInt(dot.getAttribute('data-slide-index'));
                if (slideIndex < currentIndex) {
                    dot.classList.add('filled');
                    dot.classList.remove('active');
                } else if (slideIndex === currentIndex) {
                    dot.classList.add('filled');
                    dot.classList.add('active');
                } else {
                    dot.classList.remove('filled');
                    dot.classList.remove('active');
                }
            });

            // 2. Identify Active Section using Range Logic (Robust)
            document.querySelectorAll('.indicator-section').forEach((sectionDiv, idx) => {
                const start = parseInt(sectionDiv.getAttribute('data-start-index'));
                const end = parseInt(sectionDiv.getAttribute('data-end-index'));
                
                // If current index is within this section's range
                if (currentIndex >= start && currentIndex <= end) {
                    sectionDiv.classList.add('active');
                } else {
                    sectionDiv.classList.remove('active');
                }
            });
        }

    // Settings Menu Logic
    function createSettingsMenu(container, config) {
        // 3. Create Settings Panel & Menu Integration
        // We'll wait for the menu to be ready or fallback to floating
        const panel = document.createElement('div'); // Declare panel here so it's accessible
        panel.className = 'indicator-settings-panel';

        function initSettingsButton() {
            // Find the panel that is NOT the slides panel
            // This is usually the 'Tools' or 'Custom' panel
            const panels = document.querySelectorAll('.slide-menu-panel');
            let targetPanel = null;
            
            panels.forEach(p => {
                if (p.getAttribute('data-panel') !== 'Slides') {
                    targetPanel = p;
                }
            });

            // Define the click handler
            const togglePanel = () => {
                const isVisible = panel.classList.toggle('visible');
                // When panel opens, turn off the laser pointer if it's active
                if (isVisible && typeof window.laserPointerSetPower === 'function') {
                    window.laserPointerSetPower(false);
                }
                // Find our list item to toggle state

                const myItem = document.querySelector('.slide-tool-item.progress-settings-item');
                if (myItem) {
                     if (isVisible) {
                        myItem.classList.add('selected');
                     } else {
                        myItem.classList.remove('selected');
                     }
                }
            };

            // Declared outside the block below so the "Initial Sync" check
            // after it can see it -- a `const` scoped to that `if` threw
            // "li is not defined" whenever no Tools/Custom menu panel was
            // found (targetPanel falsy), aborting the rest of this function
            // on every single page load.
            let li = null;

            if (targetPanel) {
                // We found a non-Slides panel (Tools/Custom)
                // Check if it has a list, if not create one or append to existing
                let list = targetPanel.querySelector('ul.slide-menu-items');
                if (!list) {
                    list = targetPanel.querySelector('ul'); // Any list?
                }

                // If the panel is empty or has no list, we might need to be careful
                // But usually 'Tools' has a list of links

                if (targetPanel.querySelector('.progress-settings-item')) return;

                li = document.createElement('li');
                li.className = 'slide-tool-item progress-settings-item'; // Match 'slide-tool-item' class
                li.setAttribute('data-item', 'custom');
                
                const link = document.createElement('a');
                link.href = '#';
                link.onclick = (e) => { e.preventDefault(); togglePanel(); };
                
                // Structure: <kbd>i</kbd> Label
                link.innerHTML = '<kbd>i</kbd> Progress Indicator Settings';
                
                li.appendChild(link);
                
                if (list) {
                    list.appendChild(li);
                } else {
                    // No list found, append a new list to the panel
                    const newList = document.createElement('ul');
                    newList.className = 'slide-menu-items';
                    newList.appendChild(li);
                    targetPanel.appendChild(newList);
                }
                
            }
            // Note: if no Reveal menu plugin is found, the panel is still accessible via the 'i' keyboard shortcut.
            
            // Initial Sync
            if (li) {
                // If the panel is visible on load (unlikely but possible), sync state
                if (panel.classList.contains('visible')) {
                    li.classList.add('selected');
                }
            }
        }

        // Try to init button, retrying if menu loads late
        setTimeout(initSettingsButton, 500); 
        setTimeout(initSettingsButton, 2000); // Retry later logic just in case
        reveal.on('ready', initSettingsButton); // Also on ready

        panel.innerHTML = `
            <div class="indicator-settings-header">
                <div style="display: flex; align-items: center;">
                    <div class="indicator-info-btn" id="indicatorInfoBtn">
                        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"></circle><line x1="12" y1="16" x2="12" y2="12"></line><line x1="12" y1="8" x2="12.01" y2="8"></line></svg>
                    </div>
                    <span>Display Settings</span>
                </div>
                <span style="cursor:pointer;" onclick="this.closest('.indicator-settings-panel').classList.remove('visible')">✕</span>
            </div>

            <!-- Developer Info Overlay -->
            <div class="indicator-info-overlay" id="indicatorInfoOverlay">
                <div class="indicator-info-close" id="indicatorInfoClose">✕</div>
                <div class="indicator-info-title">Quarto Progress Indicator</div>
                <div class="indicator-info-dev">Developed by ofurkancoban</div>
                
                <div class="indicator-info-links">
                    <a href="https://github.com/ofurkancoban/QuartoProgressIndicator" target="_blank" class="indicator-info-link">
                        <svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor"><path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z"></path></svg>
                        GitHub Repository
                    </a>
                    <a href="https://github.com/ofurkancoban" target="_blank" class="indicator-info-link">
                        <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor"><path d="M12 0c-6.626 0-12 5.373-12 12 0 5.302 3.438 9.8 8.207 11.387.599.111.793-.261.793-.577v-2.234c-3.338.726-4.042-1.61-4.042-1.61C4.422 18.07 3.633 17.7 3.633 17.7c-1.087-.744.084-.729.084-.729 1.205.084 1.838 1.236 1.838 1.236 1.07 1.835 2.809 1.305 3.495.998.108-.776.417-1.305.76-1.605-2.665-.3-5.466-1.332-5.466-5.93 0-1.31.465-2.38 1.235-3.22-.135-.303-.54-1.523.105-3.176 0 0 1.005-.322 3.3 1.23.96-.267 1.98-.399 3-.405 1.02.006 2.04.138 3 .405 2.28-1.552 3.285-1.23 3.285-1.23.645 1.653.24 2.873.12 3.176.765.84 1.23 1.91 1.23 3.22 0 4.61-2.805 5.625-5.475 5.92.42.36.81 1.096.81 2.22v3.293c0 .319.192.694.805.576 4.765-1.589 8.199-6.086 8.199-11.386 0-6.627-5.373-12-12-12z"/></svg>
                        Follow on GitHub
                    </a>
                    <a href="https://www.linkedin.com/in/ofurkancoban/" target="_blank" class="indicator-info-link">
                         <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor"><path d="M19 0h-14c-2.761 0-5 2.239-5 5v14c0 2.761 2.239 5 5 5h14c2.762 0 5-2.239 5-5v-14c0-2.761-2.238-5-5-5zm-11 19h-3v-11h3v11zm-1.5-12.268c-.966 0-1.75-.79-1.75-1.764s.784-1.764 1.75-1.764 1.75.79 1.75 1.764-.783 1.764-1.75 1.764zm13.5 12.268h-3v-5.604c0-3.368-4-3.113-4 0v5.604h-3v-11h3v1.765c1.396-2.586 7-2.777 7 2.476v6.759z"/></svg>
                        LinkedIn
                    </a>
                    <a href="https://www.kaggle.com/ofurkancoban" target="_blank" class="indicator-info-link">
                        <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor"><path d="M18.825 23.859c-.022.092-.117.141-.285.141h-2.969c-.167 0-.319-.064-.456-.191l-6.793-6.938-1.597 1.517v5.421c0 .16-.051.298-.152.414-.102.115-.228.173-.379.173h-3.03c-.152 0-.279-.058-.379-.173-.101-.116-.152-.254-.152-.414V.559c0-.16.051-.297.152-.413.101-.116.228-.174.379-.174h3.03c.152 0 .278.058.379.174.102.116.152.253.152.413v15.975l8.361-8.527c.137-.126.289-.19.456-.19h3.763c.247 0 .375.143.385.428.006.071-.023.14-.085.208l-6.49 5.865 6.645 8.973c.091.125.126.216.105.274z"/></svg>
                        Kaggle
                    </a>
                </div>
            </div>
            
            <div class="indicator-scroll-content">
                <div class="indicator-setting-item">
                    <span class="indicator-setting-label">Position</span>
                    <div class="indicator-btn-group" data-setting="position">
                        <button class="indicator-btn-option" data-value="top">Top</button>
                        <button class="indicator-btn-option" data-value="bottom">Bottom</button>
                    </div>
                </div>

                <div class="indicator-setting-item">
                    <span class="indicator-setting-label">Alignment</span>
                    <div class="indicator-btn-group" data-setting="alignment">
                        <button class="indicator-btn-option" data-value="left">Left</button>
                        <button class="indicator-btn-option" data-value="center">Center</button>
                        <button class="indicator-btn-option" data-value="right">Right</button>
                    </div>
                </div>

                <div class="indicator-setting-item">
                    <span class="indicator-setting-label">Edit Color For</span>
                    <div class="indicator-btn-group" data-setting="color-target">
                        <button class="indicator-btn-option active" data-value="primary">Active Dots</button>
                        <button class="indicator-btn-option" data-value="inactive">Inactive Dots</button>
                    </div>
                </div>

                <div class="indicator-setting-item">
                    <span class="indicator-setting-label">Theme Palettes</span>
                    <div class="theme-swatch-group" data-setting="theme-preset">
                        <!-- Themes will be injected here -->
                    </div>
                </div>

                <div class="indicator-setting-item">
                    <span class="indicator-setting-label" id="colorPickerLabel">Active Color</span>
                    <div style="display: flex; align-items: center; gap: 10px;">
                        <input type="color" id="indicatorColorPicker" style="flex: 1;">
                        <span id="colorValueDisplay" style="font-size: 10px; color: #666; font-family: monospace;"></span>
                    </div>
                </div>

                <div class="indicator-setting-item">
                    <span class="indicator-setting-label">Background Color</span>
                    <div style="display: flex; align-items: center; gap: 10px;">
                        <input type="color" id="indicatorBgColorPicker" value="#ffffff" style="flex: 1;">
                        <span id="bgColorValueDisplay" style="font-size: 10px; color: #666; font-family: monospace;">#ffffff</span>
                    </div>
                </div>

                <div class="indicator-setting-item">
                    <span class="indicator-setting-label">Style</span>
                    <div class="indicator-btn-group" data-setting="style">
                        <button class="indicator-btn-option ${styleConfig === 'dots' ? 'active' : ''}" data-value="dots">Dots</button>
                        <button class="indicator-btn-option ${styleConfig === 'bar' ? 'active' : ''}" data-value="bar">Bar</button>
                    </div>
                </div>

                <div class="indicator-setting-item">
                    <span class="indicator-setting-label">Dot Size</span>
                    <input type="range" min="4" max="20" value="8" id="indicatorSizeSlider">
                </div>

                <div class="indicator-setting-item">
                    <span class="indicator-setting-label">Spacing</span>
                    <input type="range" min="5" max="50" value="15" id="indicatorSpacingSlider">
                </div>

                <div class="indicator-setting-item">
                    <span class="indicator-setting-label">Animation</span>
                    <div class="indicator-btn-group" data-setting="animation">
                        <button class="indicator-btn-option" data-value="none">None</button>
                        <button class="indicator-btn-option" data-value="pulse">Pulse</button>
                        <button class="indicator-btn-option" data-value="glow">Glow</button>
                        <button class="indicator-btn-option" data-value="bounce">Bounce</button>
                    </div>
                </div>

                <div class="indicator-setting-item" style="display: flex; align-items: center; justify-content: space-between;">
                    <span class="indicator-setting-label" style="margin: 0;">Show on Title Slide</span>
                    <input type="checkbox" id="indicatorTitleToggle" style="width: 20px; height: 20px; cursor: pointer;">
                </div>

                <div class="indicator-setting-item" style="display: flex; align-items: center; justify-content: space-between;">
                    <span class="indicator-setting-label" style="margin: 0;">Show Tooltips</span>
                    <input type="checkbox" id="indicatorTooltipToggle" style="width: 20px; height: 20px; cursor: pointer;">
                </div>

                <div class="indicator-setting-item" style="display: flex; align-items: center; justify-content: space-between;">
                    <span class="indicator-setting-label" style="margin: 0;">Page Number: Dots Only</span>
                    <input type="checkbox" id="indicatorDotPageCount" style="width: 20px; height: 20px; cursor: pointer;">
                </div>

                <div class="indicator-setting-item" style="display: flex; align-items: center; justify-content: space-between;">
                    <span class="indicator-setting-label" style="margin: 0;">Auto-hide on Idle</span>
                    <input type="checkbox" id="indicatorAutoHide" style="width: 20px; height: 20px; cursor: pointer;">
                </div>

                <!-- Keyboard Shortcuts -->
                <div class="indicator-settings-header" style="margin-top: 15px; padding: 10px 0; border: none;">
                    <span>Keyboard Shortcuts</span>
                </div>
                <div class="indicator-setting-item" style="display: flex; align-items: center; justify-content: space-between;">
                    <span class="indicator-setting-label" style="margin: 0;">Open Settings</span>
                    <input type="text" id="indicatorSettingsKey" maxlength="1"
                        style="width: 36px; height: 28px; text-align: center; font-size: 14px; font-weight: bold; border: 1px solid #ddd; border-radius: 6px; background: #f8f8f8; text-transform: uppercase; cursor: pointer;">
                </div>
                <div class="indicator-setting-item" style="display: flex; align-items: center; justify-content: space-between;">
                    <span class="indicator-setting-label" style="margin: 0;">Toggle Visibility</span>
                    <input type="text" id="indicatorToggleKey" maxlength="1"
                        style="width: 36px; height: 28px; text-align: center; font-size: 14px; font-weight: bold; border: 1px solid #ddd; border-radius: 6px; background: #f8f8f8; text-transform: uppercase; cursor: pointer;">
                </div>

                <!-- Slide Visibility Manager -->
                <div class="indicator-settings-header" style="margin-top: 15px; padding: 10px 0; border: none;">
                    <span>Slide Visibility</span>
                </div>
                <div id="indicatorSlideList" style="max-height: 200px; overflow-y: auto; background: #fff; border: 1px solid #ddd; border-radius: 4px; padding: 5px;">
                    <!-- Populated via JS -->
                    <div style="font-size: 11px; color: #999; text-align: center; padding: 10px;">Loading slides...</div>
                </div>

                <button id="indicatorResetBtn" style="width: 100%; margin-top: 15px; background: #fee; color: #d33; border: 1px solid #fcc; padding: 8px; border-radius: 6px; cursor: pointer; font-size: 11px; font-weight: 600;">
                    🔄 Reset to Defaults
                </button>
            </div>
        `;
        document.body.appendChild(panel);

        // Toggle
        // btn.addEventListener('click', () => panel.classList.toggle('visible')); // Button might not exist
        
        // Close event listener on X button (needs to toggle state back)
        panel.querySelector('.indicator-settings-header span[onclick]').onclick = (e) => {
             panel.classList.remove('visible');
             const myItem = document.querySelector('.slide-tool-item.progress-settings-item');
             if (myItem) myItem.classList.remove('selected');
        };

        // Logic
        const root = document.documentElement;
        
        // 1. Position
        const currentPos = container.getAttribute('data-position') || 'bottom';
        panel.querySelector(`.indicator-btn-group[data-setting="position"] [data-value="${currentPos}"]`)?.classList.add('active');
        
        panel.querySelectorAll('.indicator-btn-group[data-setting="position"] .indicator-btn-option').forEach(opt => {
            opt.addEventListener('click', (e) => {
                panel.querySelectorAll('.indicator-btn-group[data-setting="position"] .indicator-btn-option').forEach(b => b.classList.remove('active'));
                e.target.classList.add('active');
                
                const newPos = e.target.getAttribute('data-value');
                const oldPos = container.getAttribute('data-position') || 'bottom';
                
                // Skip animation if same position
                if (newPos === oldPos) return;
                
                // Exit animation: slide out in current direction
                const exitTransform = oldPos === 'bottom' ? 'translateY(100%)' : 'translateY(-100%)';
                container.style.transform = exitTransform;
                container.style.opacity = '0';
                
                // After exit completes, swap position and enter from new direction
                setTimeout(() => {
                    container.setAttribute('data-position', newPos);
                    root.style.setProperty('--progress-position', newPos);
                    
                    // Force the new position's off-screen state before entering
                    const enterStart = newPos === 'top' ? 'translateY(-100%)' : 'translateY(100%)';
                    container.style.transition = 'none'; // Disable transition for instant repositioning
                    container.style.transform = enterStart;
                    
                    // Force reflow to apply the instant repositioning
                    container.offsetHeight;
                    
                    // Re-enable transition and animate entrance
                    container.style.transition = '';
                    container.style.transform = 'translateY(0)';
                    container.style.opacity = '1';
                    
                    // Re-apply viewport resize logic
                    updateDots();
                }, 300); // Match the CSS transition duration
            });
        });

        // 2. Alignment
        const currentAlign = container.getAttribute('data-alignment') || 'center';
        panel.querySelector(`.indicator-btn-group[data-setting="alignment"] [data-value="${currentAlign}"]`)?.classList.add('active');

        panel.querySelectorAll('.indicator-btn-group[data-setting="alignment"] .indicator-btn-option').forEach(opt => {
            opt.addEventListener('click', (e) => {
                panel.querySelectorAll('.indicator-btn-group[data-setting="alignment"] .indicator-btn-option').forEach(b => b.classList.remove('active'));
                e.target.classList.add('active');
                
                const val = e.target.getAttribute('data-value');
                container.setAttribute('data-alignment', val);
                
                if (val === 'center') container.style.justifyContent = 'center';
                else if (val === 'left') container.style.justifyContent = 'flex-start';
                else if (val === 'right') container.style.justifyContent = 'flex-end';
                
                root.style.setProperty('--progress-alignment', val);
            });
        });

        // 2.5 Style
        const currentStyle = styleConfig; // Use the one we resolved earlier
        panel.querySelector(`.indicator-btn-group[data-setting="style"] [data-value="${currentStyle}"]`)?.classList.add('active');

        panel.querySelectorAll('.indicator-btn-group[data-setting="style"] .indicator-btn-option').forEach(opt => {
            opt.addEventListener('click', (e) => {
                panel.querySelectorAll('.indicator-btn-group[data-setting="style"] .indicator-btn-option').forEach(b => b.classList.remove('active'));
                e.target.classList.add('active');
                
                const val = e.target.getAttribute('data-value');
                
                document.querySelectorAll('.dots-container').forEach(dc => {
                    if (val === 'bar') dc.classList.add('bar-style');
                    else dc.classList.remove('bar-style');
                });
                
                // Update config for export
                container.setAttribute('data-style', val);
            });
        });

        // 3. Color Logic (Unified)
        const colorPicker = panel.querySelector('#indicatorColorPicker');
        const colorLabel = panel.querySelector('#colorPickerLabel');
        const colorValueDisplay = panel.querySelector('#colorValueDisplay');
        let colorMode = 'primary'; // 'primary' or 'inactive'

        function getColorVar() {
            return colorMode === 'primary' ? '--primary-color' : '--inactive-color';
        }

        function syncUI() {
            const cssVar = getColorVar();
            let val = getComputedStyle(root).getPropertyValue(cssVar).trim();
            // Handle empty or invalid
            if (!val) val = (colorMode === 'primary' ? '#3366ff' : '#e0e0e0');
            
            colorPicker.value = val;
            colorValueDisplay.innerText = val;
            colorLabel.innerText = colorMode === 'primary' ? 'Active Color' : 'Inactive Color';

            // Highlight appropriate preset if matches
            panel.querySelectorAll('.indicator-color-btn').forEach(btn => {
                const btnColor = btn.getAttribute('data-color').toLowerCase();
                btn.classList.toggle('active', btnColor === val.toLowerCase());
            });
        }

        // 3b. Background Color Picker
        const bgColorPicker = panel.querySelector('#indicatorBgColorPicker');
        const bgColorValueDisplay = panel.querySelector('#bgColorValueDisplay');
        
        // Init bg color from current computed style
        const currentBg = getComputedStyle(root).getPropertyValue('--indicator-bg').trim() || 'rgba(255, 255, 255, 0.9)';
        // Try to set picker value (only works with hex)
        if (currentBg.startsWith('#')) {
            bgColorPicker.value = currentBg;
            bgColorValueDisplay.innerText = currentBg;
        }

        bgColorPicker.addEventListener('input', (e) => {
            const hex = e.target.value;
            root.style.setProperty('--indicator-bg', hex);
            bgColorValueDisplay.innerText = hex;
            saveSettings();
        });

        // 3. Theme Palettes - Popular color schemes (light & dark mix)
        const themes = {
            ocean:      { name: 'Ocean',       primary: '#0077B6', inactive: '#CAF0F8', bg: '#FFFFFF', label: '#5A7D8A', size: '10px' },
            emerald:    { name: 'Emerald',     primary: '#059669', inactive: '#D1FAE5', bg: '#F0FDF4', label: '#4B7A5E', size: '10px' },
            sunset:     { name: 'Sunset',      primary: '#EA580C', inactive: '#FED7AA', bg: '#FFFBEB', label: '#9A6B4A', size: '10px' },
            lavender:   { name: 'Lavender',    primary: '#7C3AED', inactive: '#DDD6FE', bg: '#F5F3FF', label: '#7A6B99', size: '10px' },
            dracula:    { name: 'Dracula',     primary: '#BD93F9', inactive: '#6272A4', bg: '#282A36', label: '#A8A8C0', size: '10px' },
            nord:       { name: 'Nord',        primary: '#88C0D0', inactive: '#4C566A', bg: '#2E3440', label: '#9EAAB8', size: '10px' },
            gruvbox:    { name: 'Gruvbox',     primary: '#FABD2F', inactive: '#928374', bg: '#282828', label: '#BDAE93', size: '10px' },
            tokyonight: { name: 'Tokyo Night', primary: '#7AA2F7', inactive: '#565F89', bg: '#1A1B26', label: '#9AA5CE', size: '10px' }
        };

        const themeContainer = panel.querySelector('.theme-swatch-group');
        Object.keys(themes).forEach(id => {
            const t = themes[id];
            const swatch = document.createElement('div');
            swatch.className = 'theme-swatch';
            swatch.setAttribute('data-value', id);
            swatch.title = t.name;
            swatch.innerHTML = `
                <div class="swatch-active" style="background: ${t.primary}"></div>
                <div class="swatch-inactive" style="background: ${t.inactive}"></div>
                <div class="swatch-bg" style="background: ${t.bg}"></div>
                <span class="theme-swatch-label">${t.name}</span>
            `;
            
            swatch.addEventListener('click', () => {
                root.style.setProperty('--primary-color', t.primary);
                root.style.setProperty('--completed-color', t.primary);
                root.style.setProperty('--inactive-color', t.inactive);
                root.style.setProperty('--indicator-bg', t.bg);
                root.style.setProperty('--label-color', t.label);
                root.style.setProperty('--dot-size', t.size);
                
                // Update dots immediately
                updateDots();
                
                // Sync color pickers
                if (colorMode === 'primary') {
                    colorPicker.value = t.primary;
                    colorValueDisplay.textContent = t.primary.toUpperCase();
                } else {
                    colorPicker.value = t.inactive;
                    colorValueDisplay.textContent = t.inactive.toUpperCase();
                }
                bgColorPicker.value = t.bg;
                bgColorValueDisplay.innerText = t.bg;
                panel.querySelector('#indicatorSizeSlider').value = parseInt(t.size);

                // Update active state in UI
                themeContainer.querySelectorAll('.theme-swatch').forEach(s => s.classList.remove('active'));
                swatch.classList.add('active');
                
                saveSettings();
            });
            themeContainer.appendChild(swatch);
        });
    
        // 4. Color Logic (Unified)
        
        function applyColor(color, modeOverride) {
            const mode = modeOverride || colorMode;
            if (mode === 'primary') {
                root.style.setProperty('--primary-color', color);
                root.style.setProperty('--completed-color', color);
            } else {
                root.style.setProperty('--inactive-color', color);
            }
            syncUI(); 
        }

        // Target Switcher
        panel.querySelectorAll('.indicator-btn-group[data-setting="color-target"] .indicator-btn-option').forEach(opt => {
            opt.addEventListener('click', (e) => {
                panel.querySelectorAll('.indicator-btn-group[data-setting="color-target"] .indicator-btn-option').forEach(b => b.classList.remove('active'));
                e.target.classList.add('active');
                colorMode = e.target.getAttribute('data-value');
                syncUI();
            });
        });

        // Initialize
        syncUI();
        
        // Picker Event
        colorPicker.addEventListener('input', (e) => {
            applyColor(e.target.value);
        });

        // Preset Events
        panel.querySelectorAll('.indicator-color-btn').forEach(btn => {
            btn.addEventListener('click', (e) => {
                applyColor(e.target.getAttribute('data-color'));
            });
        });
        // 5. Size
        const sizeSlider = panel.querySelector('#indicatorSizeSlider');
        sizeSlider.addEventListener('input', (e) => {
            root.style.setProperty('--dot-size', e.target.value + 'px');
        });

        // 6. Spacing
        const spacingSlider = panel.querySelector('#indicatorSpacingSlider');
        spacingSlider.addEventListener('input', (e) => {
            root.style.setProperty('--section-spacing', e.target.value + 'px');
        });

        // 7. Animation Logic
        panel.querySelectorAll('.indicator-btn-group[data-setting="animation"] .indicator-btn-option').forEach(opt => {
            opt.addEventListener('click', (e) => {
                const anim = e.target.getAttribute('data-value');
                document.querySelectorAll('.dots-container').forEach(dc => {
                    dc.classList.remove('anim-pulse', 'anim-glow', 'anim-bounce');
                    if (anim !== 'none') dc.classList.add(`anim-${anim}`);
                });
                panel.querySelectorAll('.indicator-btn-group[data-setting="animation"] .indicator-btn-option').forEach(b => b.classList.remove('active'));
                e.target.classList.add('active');
                saveSettings();
            });
        });



        // 7. Title Slide Toggle
        const titleToggle = panel.querySelector('#indicatorTitleToggle');
        titleToggle.checked = !hideOnTitle; // Checkbox means "Show", so inverted
        
        titleToggle.addEventListener('change', (e) => {
            hideOnTitle = !e.target.checked; // If checked (Show), then hideOnTitle is false
            updateDots();
            saveSettings();
        });

        // 7.5 Slide Visibility List
        const slideListContainer = panel.querySelector('#indicatorSlideList');
        function renderSlideList() {
            slideListContainer.innerHTML = '';
            
            const allSlides = Array.from(document.querySelectorAll('.reveal .slides section:not(.stack)'));
            
            const header = document.createElement('div');
            header.style.display = 'flex';
            header.style.justifyContent = 'space-between';
            header.style.alignItems = 'center';
            header.style.fontSize = '10px';
            header.style.fontWeight = 'bold';
            header.style.color = '#666';
            header.style.padding = '4px 8px';
            header.style.borderBottom = '1px solid #ddd';
            header.style.marginBottom = '2px';
            header.innerHTML = `<span style="flex:1;">Slide</span> <span style="width: 30px; text-align:center;" title="Include as a dot in progress indicator">Dot</span> <span style="width: 30px; text-align:center;" title="Show indicator bar when on this slide">Bar</span>`;
            slideListContainer.appendChild(header);

            allSlides.forEach((slide, idx) => {
                const h1 = slide.querySelector('h1');
                const h2 = slide.querySelector('h2');
                const h3 = slide.querySelector('h3');
                const title = slide.getAttribute('data-menu-title') || 
                              (h1 ? h1.innerText : (h2 ? h2.innerText : (h3 ? h3.innerText : `Slide ${idx + 1}`)));
                
                const item = document.createElement('div');
                item.style.display = 'flex';
                item.style.alignItems = 'center';
                item.style.justifyContent = 'space-between';
                item.style.padding = '4px 8px';
                item.style.fontSize = '12px';
                item.style.borderBottom = '1px solid #f0f0f0';
                
                const label = document.createElement('span');
                label.innerText = `${idx + 1}. ${title.length > 20 ? title.substring(0, 18) + '...' : title}`;
                label.title = title;
                label.style.flex = '1';
                item.appendChild(label);
                
                const dotDiv = document.createElement('div');
                dotDiv.style.width = '30px';
                dotDiv.style.textAlign = 'center';
                const dotCheck = document.createElement('input');
                dotCheck.type = 'checkbox';
                dotCheck.checked = !omittedSlides.has(idx);
                dotCheck.style.cursor = 'pointer';
                dotCheck.addEventListener('change', (e) => {
                    if (e.target.checked) omittedSlides.delete(idx);
                    else omittedSlides.add(idx);
                    buildDots();    
                    updateDots();   
                    saveSettings();
                });
                dotDiv.appendChild(dotCheck);
                item.appendChild(dotDiv);

                const barDiv = document.createElement('div');
                barDiv.style.width = '30px';
                barDiv.style.textAlign = 'center';
                const barCheck = document.createElement('input');
                barCheck.type = 'checkbox';
                barCheck.checked = !hiddenIndicatorSlides.has(idx);
                barCheck.style.cursor = 'pointer';
                barCheck.addEventListener('change', (e) => {
                    if (e.target.checked) hiddenIndicatorSlides.delete(idx);
                    else hiddenIndicatorSlides.add(idx);
                    updateDots();
                    saveSettings();
                });
                barDiv.appendChild(barCheck);
                item.appendChild(barDiv);

                slideListContainer.appendChild(item);
            });
        }
        
        // 0.2 Tooltip Toggle
        const tooltipToggle = panel.querySelector('#indicatorTooltipToggle');
        tooltipToggle.checked = showTooltips;
        
        tooltipToggle.addEventListener('change', (e) => {
            showTooltips = e.target.checked;
            if (showTooltips) {
                createTooltip();
            }
            saveSettings();
        });

        // Dot Page Count Toggle
        const dotPageCountToggle = panel.querySelector('#indicatorDotPageCount');
        dotPageCountToggle.checked = dotPageCount;
        dotPageCountToggle.addEventListener('change', (e) => {
            dotPageCount = e.target.checked;
            const currentSlide = reveal.getCurrentSlide();
            const allSlides = Array.from(document.querySelectorAll('.reveal .slides section:not(.stack)'));
            const currentIndex = allSlides.indexOf(currentSlide);
            updateSlideNumber(currentIndex);
            saveSettings();
        });

        // Auto-hide on idle
        const autoHideToggle = panel.querySelector('#indicatorAutoHide');
        autoHideToggle.checked = autoHide;
        let idleTimer = null;
        const IDLE_DELAY = 2500; // ms before fading

        function applyAutoHide() {
            // Ensure the container has a CSS transition
            container.style.transition = 'opacity 0.6s ease, transform 0.3s ease';
            if (!autoHide) {
                clearTimeout(idleTimer);
                container.style.opacity = '';
                container.style.pointerEvents = '';
                return;
            }
            // Start idle timer
            function resetIdle() {
                clearTimeout(idleTimer);
                container.style.opacity = '1';
                container.style.pointerEvents = 'auto';
                idleTimer = setTimeout(() => {
                    // Don't hide if settings panel is open
                    if (!panel.classList.contains('visible')) {
                        container.style.opacity = '0.08';
                        container.style.pointerEvents = 'none';
                    }
                }, IDLE_DELAY);
            }
            document.addEventListener('mousemove', resetIdle);
            document.addEventListener('keydown', resetIdle);
            document.addEventListener('mousedown', resetIdle);
            // Kick off immediately
            resetIdle();
            // Store cleanup so we can remove listeners when disabled
            autoHideToggle._cleanup = () => {
                clearTimeout(idleTimer);
                document.removeEventListener('mousemove', resetIdle);
                document.removeEventListener('keydown', resetIdle);
                document.removeEventListener('mousedown', resetIdle);
            };
        }

        autoHideToggle.addEventListener('change', (e) => {
            if (!autoHide && autoHideToggle._cleanup) {
                autoHideToggle._cleanup();
                autoHideToggle._cleanup = null;
            }
            autoHide = e.target.checked;
            applyAutoHide();
            saveSettings();
        });

        // Keyboard Shortcut Customization
        const settingsKeyInput = panel.querySelector('#indicatorSettingsKey');
        const toggleKeyInput   = panel.querySelector('#indicatorToggleKey');
        settingsKeyInput.value = settingsKey.toUpperCase();
        toggleKeyInput.value   = toggleKey.toUpperCase();

        // Reveal.js built-in keys that must not be overridden
        const REVEAL_RESERVED = new Set([
            'arrowright','arrowleft','arrowup','arrowdown',
            ' ','n','l','j','p','h','k',           // navigation
            'b','.',                                 // pause
            'f',                                     // fullscreen
            'g',                                     // jump to slide
            'escape','o',                            // overview
            'e',                                     // pdf export
            'm',                                     // menu
            'r',                                     // scroll view
            's',                                     // speaker notes
        ]);

        const REVEAL_LABELS = {
            ' ': 'Space (Next slide)', n: 'N (Next)', l: 'L (Next)', j: 'J (Next)',
            p: 'P (Prev)', h: 'H (Prev)', k: 'K (Prev)',
            b: 'B (Pause)', '.': '. (Pause)', f: 'F (Fullscreen)',
            g: 'G (Jump to slide)', escape: 'ESC (Overview)', o: 'O (Overview)',
            e: 'E (PDF export)', m: 'M (Menu)', r: 'R (Scroll view)', s: 'S (Speaker notes)',
        };

        let keyWarningEl = null;
        function showKeyWarning(input, message) {
            input.style.borderColor = '#f66';
            input.style.background  = '#fff0f0';
            if (!keyWarningEl) {
                keyWarningEl = document.createElement('div');
                keyWarningEl.style.cssText = [
                    'position:absolute',
                    'background:#1e1e2e',
                    'color:#f8f8f2',
                    'font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif',
                    'font-size:11px',
                    'font-weight:500',
                    'line-height:1.4',
                    'padding:5px 10px',
                    'border-radius:6px',
                    'box-shadow:0 4px 12px rgba(0,0,0,0.3)',
                    'pointer-events:none',
                    'white-space:nowrap',
                    'letter-spacing:0.2px',
                    'z-index:99999'
                ].join(';') + ';';
                document.body.appendChild(keyWarningEl);
            }
            keyWarningEl.textContent = '⚠️ ' + message;
            const rect = input.getBoundingClientRect();
            keyWarningEl.style.left = rect.left + 'px';
            keyWarningEl.style.top  = (rect.bottom + 4) + 'px';
            keyWarningEl.style.display = 'block';
        }
        function clearKeyWarning(input) {
            input.style.borderColor = '#ddd';
            input.style.background  = '#f8f8f8';
            if (keyWarningEl) keyWarningEl.style.display = 'none';
        }

        function validateKey(k, otherKey, input) {
            if (k.length !== 1)        { showKeyWarning(input, 'Enter a single character'); return false; }
            if (k === otherKey)        { showKeyWarning(input, 'Conflicts with the other shortcut'); return false; }
            if (REVEAL_RESERVED.has(k))  { showKeyWarning(input, 'Reserved by Reveal.js: ' + (REVEAL_LABELS[k] || k.toUpperCase())); return false; }
            clearKeyWarning(input);
            return true;
        }

        settingsKeyInput.addEventListener('input', (e) => {
            const k = e.target.value.trim().toLowerCase();
            e.target.value = k.toUpperCase();
            if (validateKey(k, toggleKey, settingsKeyInput)) {
                settingsKey = k;
                saveSettings();
            }
        });

        toggleKeyInput.addEventListener('input', (e) => {
            const k = e.target.value.trim().toLowerCase();
            e.target.value = k.toUpperCase();
            if (validateKey(k, settingsKey, toggleKeyInput)) {
                toggleKey = k;
                saveSettings();
            }
        });

        // Hide warning when input loses focus
        [settingsKeyInput, toggleKeyInput].forEach(inp => {
            inp.addEventListener('blur', () => { if (keyWarningEl) keyWarningEl.style.display = 'none'; });
        });

        // Populate initially
        renderSlideList();

        // 8. Export Config
        const exportBtn = document.createElement('button');
        exportBtn.className = 'indicator-btn-option';
        exportBtn.style.width = '100%';
        exportBtn.style.marginTop = '15px';
        exportBtn.style.background = '#333';
        exportBtn.style.color = '#fff';
        exportBtn.style.fontWeight = 'bold';
        exportBtn.innerText = '📋 Copy & Save Configuration';
        
        exportBtn.addEventListener('click', () => {
            const pos = container.getAttribute('data-position');
            const align = container.getAttribute('data-alignment');
            const style = container.getAttribute('data-style') || 'dots';
            const primary = getComputedStyle(root).getPropertyValue('--primary-color').trim();
            const inactive = getComputedStyle(root).getPropertyValue('--inactive-color').trim();
            const size = getComputedStyle(root).getPropertyValue('--dot-size').trim();
            const spacing = getComputedStyle(root).getPropertyValue('--section-spacing').trim();
            
            const yamlConfig = `
# Quarto Progress Indicator Configuration
# Paste this into your _quarto.yml file or inside a <style> block

# Option 1: YAML (for basic settings)
progress-indicator:
  position: ${pos}
  alignment: ${align}
  style: ${style}
  hide-on-title: ${!hideOnTitle}

# Option 2: CSS (for colors/sizes)
/* Add to your CSS or styling block */
:root {
  --primary-color: ${primary};
  --inactive-color: ${inactive};
  --dot-size: ${size};
  --section-spacing: ${spacing};
}
`;
            navigator.clipboard.writeText(yamlConfig).then(() => {
                const originalText = exportBtn.innerText;
                exportBtn.innerText = '✅ Copied!';
                exportBtn.style.background = '#00cc66';
                setTimeout(() => {
                    exportBtn.innerText = originalText;
                    exportBtn.style.background = '#333';
                }, 2000);
            }).catch(err => {
                console.error('Failed to copy config:', err);
                exportBtn.innerText = '❌ Error';
            });
        });
        
        panel.querySelector('.indicator-scroll-content').appendChild(exportBtn);

        // 8.5 JSON Import/Export
        const jsonGroup = document.createElement('div');
        jsonGroup.className = 'indicator-btn-group';
        jsonGroup.style.display = 'flex';
        jsonGroup.style.gap = '8px';
        jsonGroup.style.marginTop = '8px';

        const exportJsonBtn = document.createElement('button');
        exportJsonBtn.className = 'indicator-btn-option';
        exportJsonBtn.style.flex = '1';
        exportJsonBtn.innerText = '💾 Export JSON';
        exportJsonBtn.title = 'Download current settings as a JSON file';
        
        exportJsonBtn.addEventListener('click', () => {
            const settings = {
                position: container.getAttribute('data-position'),
                alignment: container.getAttribute('data-alignment'),
                primaryColor: getComputedStyle(root).getPropertyValue('--primary-color').trim(),
                inactiveColor: getComputedStyle(root).getPropertyValue('--inactive-color').trim(),
                bgColor: getComputedStyle(root).getPropertyValue('--indicator-bg').trim(),
                size: getComputedStyle(root).getPropertyValue('--dot-size').trim(),
                spacing: getComputedStyle(root).getPropertyValue('--section-spacing').trim(),
                style: container.getAttribute('data-style') || 'dots',
                animation: panel.querySelector('.indicator-btn-group[data-setting="animation"] .active')?.getAttribute('data-value') || 'none',
                theme: themeContainer.querySelector('.theme-swatch.active')?.getAttribute('data-value') || 'none',
                hideOnTitle: hideOnTitle,
                hiddenIndicatorSlides: Array.from(hiddenIndicatorSlides),
                omittedSlides: Array.from(omittedSlides)
            };
            const blob = new Blob([JSON.stringify(settings, null, 2)], { type: 'application/json' });
            const url = URL.createObjectURL(blob);
            const a = document.createElement('a');
            a.href = url;
            a.download = 'progress-indicator-settings.json';
            a.click();
            URL.revokeObjectURL(url);
        });

        const importJsonBtn = document.createElement('button');
        importJsonBtn.className = 'indicator-btn-option';
        importJsonBtn.style.flex = '1';
        importJsonBtn.innerText = '📂 Import JSON';
        importJsonBtn.title = 'Upload a previously exported JSON settings file';

        const fileInput = document.createElement('input');
        fileInput.type = 'file';
        fileInput.accept = '.json';
        fileInput.style.display = 'none';
        
        importJsonBtn.addEventListener('click', () => fileInput.click());
        
        fileInput.addEventListener('change', (e) => {
            const file = e.target.files[0];
            if (!file) return;
            const reader = new FileReader();
            reader.onload = (event) => {
                try {
                    const settings = JSON.parse(event.target.result);
                    applySettings(settings);
                    saveSettings();
                    alert('Settings imported successfully!');
                } catch (err) {
                    console.error('Failed to parse JSON:', err);
                    alert('Invalid JSON file.');
                }
            };
            reader.readAsText(file);
        });

        jsonGroup.appendChild(exportJsonBtn);
        jsonGroup.appendChild(importJsonBtn);
        panel.querySelector('.indicator-scroll-content').appendChild(jsonGroup);
        panel.querySelector('.indicator-scroll-content').appendChild(fileInput);

        // 8.6 Info Overlay Logic
        const infoBtn = panel.querySelector('#indicatorInfoBtn');
        const infoOverlay = panel.querySelector('#indicatorInfoOverlay');
        const infoClose = panel.querySelector('#indicatorInfoClose');

        infoBtn.addEventListener('click', () => infoOverlay.classList.add('visible'));
        infoClose.addEventListener('click', () => infoOverlay.classList.remove('visible'));

            // 8. Persistence (LocalStorage)
            function saveSettings() {
                const settings = {
                    position: container.getAttribute('data-position'),
                    alignment: container.getAttribute('data-alignment'),
                    primaryColor: getComputedStyle(root).getPropertyValue('--primary-color').trim(),
                    inactiveColor: getComputedStyle(root).getPropertyValue('--inactive-color').trim(),
                    bgColor: getComputedStyle(root).getPropertyValue('--indicator-bg').trim(),
                    size: getComputedStyle(root).getPropertyValue('--dot-size').trim(),
                    spacing: getComputedStyle(root).getPropertyValue('--section-spacing').trim(),
                    style: container.getAttribute('data-style') || 'dots',
                    animation: panel.querySelector('.indicator-btn-group[data-setting="animation"] .active')?.getAttribute('data-value') || 'none',
                    theme: themeContainer.querySelector('.theme-swatch.active')?.getAttribute('data-value') || 'none',
                    hideOnTitle: hideOnTitle,
                    showTooltips: showTooltips,
                    dotPageCount: dotPageCount,
                    settingsKey: settingsKey,
                    toggleKey: toggleKey,
                    autoHide: autoHide,
                    hiddenIndicatorSlides: Array.from(hiddenIndicatorSlides),
                    omittedSlides: Array.from(omittedSlides)
                };
                localStorage.setItem('quarto-indicator-settings', JSON.stringify(settings));
            }

            function applySettings(s) {
                if (!s) return;
                if (s.position) {
                    container.setAttribute('data-position', s.position);
                    root.style.setProperty('--progress-position', s.position);
                    // Update UI buttons
                    panel.querySelectorAll('.indicator-btn-group[data-setting="position"] .indicator-btn-option').forEach(btn => {
                        btn.classList.toggle('active', btn.getAttribute('data-value') === s.position);
                    });
                }
                if (s.alignment) {
                    container.setAttribute('data-alignment', s.alignment);
                    root.style.setProperty('--progress-alignment', s.alignment);
                    if (s.alignment === 'center') container.style.justifyContent = 'center';
                    else if (s.alignment === 'left') container.style.justifyContent = 'flex-start';
                    else if (s.alignment === 'right') container.style.justifyContent = 'flex-end';
                    // Update UI buttons
                    panel.querySelectorAll('.indicator-btn-group[data-setting="alignment"] .indicator-btn-option').forEach(btn => {
                        btn.classList.toggle('active', btn.getAttribute('data-value') === s.alignment);
                    });
                }
                if (s.theme) {
                    themeContainer.querySelectorAll('.theme-swatch').forEach(swatch => {
                        swatch.classList.toggle('active', swatch.getAttribute('data-value') === s.theme);
                    });
                }
                if (s.primaryColor) {
                    root.style.setProperty('--primary-color', s.primaryColor);
                    root.style.setProperty('--completed-color', s.primaryColor);
                    // Update picker
                    panel.querySelector('#indicatorColorPicker').value = s.primaryColor;
                    panel.querySelector('#colorValueDisplay').innerText = s.primaryColor;
                }
                if (s.inactiveColor) {
                    root.style.setProperty('--inactive-color', s.inactiveColor);
                }
                if (s.labelColor) {
                    root.style.setProperty('--label-color', s.labelColor);
                }
                if (s.bgColor) {
                    root.style.setProperty('--indicator-bg', s.bgColor);
                    const bgPicker = panel.querySelector('#indicatorBgColorPicker');
                    const bgDisplay = panel.querySelector('#bgColorValueDisplay');
                    if (bgPicker) bgPicker.value = s.bgColor;
                    if (bgDisplay) bgDisplay.innerText = s.bgColor;
                }
                
                // Tooltip Toggle
                if (s.dotPageCount !== undefined) {
                    dotPageCount = s.dotPageCount;
                    const dotPageCountToggle = panel.querySelector('#indicatorDotPageCount');
                    if (dotPageCountToggle) dotPageCountToggle.checked = dotPageCount;
                }
                if (s.settingsKey) {
                    settingsKey = s.settingsKey;
                    const el = panel.querySelector('#indicatorSettingsKey');
                    if (el) el.value = settingsKey.toUpperCase();
                }
                if (s.toggleKey) {
                    toggleKey = s.toggleKey;
                    const el = panel.querySelector('#indicatorToggleKey');
                    if (el) el.value = toggleKey.toUpperCase();
                }
                if (s.autoHide !== undefined) {
                    autoHide = s.autoHide;
                    const el = panel.querySelector('#indicatorAutoHide');
                    if (el) el.checked = autoHide;
                    if (autoHide) applyAutoHide();
                }
                if (s.showTooltips !== undefined) {
                    showTooltips = s.showTooltips;
                    const tooltipToggle = panel.querySelector('#indicatorTooltipToggle');
                    if (tooltipToggle) tooltipToggle.checked = showTooltips;
                    
                    if (showTooltips) {
                        createTooltip();
                    } else if (tooltip) {
                        tooltip.remove();
                        tooltip = null;
                    }
                }

                if (s.size) {
                    root.style.setProperty('--dot-size', s.size);
                    const slider = panel.querySelector('#indicatorSizeSlider');
                    if (slider) slider.value = parseInt(s.size);
                }
                if (s.spacing) {
                    root.style.setProperty('--section-spacing', s.spacing);
                    const slider = panel.querySelector('#indicatorSpacingSlider');
                    if (slider) slider.value = parseInt(s.spacing);
                }
                if (s.hideOnTitle !== undefined) {
                    hideOnTitle = s.hideOnTitle;
                    const toggle = panel.querySelector('#indicatorTitleToggle');
                    if (toggle) toggle.checked = !hideOnTitle;
                }
                if (s.style) {
                    container.setAttribute('data-style', s.style);
                    document.querySelectorAll('.dots-container').forEach(dc => {
                        if (s.style === 'bar') dc.classList.add('bar-style');
                        else dc.classList.remove('bar-style');
                    });
                    panel.querySelectorAll('.indicator-btn-group[data-setting="style"] .indicator-btn-option').forEach(btn => {
                        btn.classList.toggle('active', btn.getAttribute('data-value') === s.style);
                    });
                }
                if (s.hiddenSlides) { // backwards compatibility
                    hiddenIndicatorSlides = new Set(s.hiddenSlides);
                }
                if (s.hiddenIndicatorSlides) {
                    hiddenIndicatorSlides = new Set(s.hiddenIndicatorSlides);
                }
                if (s.omittedSlides) {
                    omittedSlides = new Set(s.omittedSlides);
                }
                if (s.hiddenSlides || s.hiddenIndicatorSlides || s.omittedSlides) {
                    if (typeof buildDots === 'function') buildDots();
                    if (typeof renderSlideList === 'function') renderSlideList();
                }
                if (s.animation) {
                    document.querySelectorAll('.dots-container').forEach(dc => {
                        dc.classList.remove('anim-pulse', 'anim-glow', 'anim-bounce');
                        if (s.animation !== 'none') dc.classList.add(`anim-${s.animation}`);
                    });
                    panel.querySelectorAll('.indicator-btn-group[data-setting="animation"] .indicator-btn-option').forEach(btn => {
                        btn.classList.toggle('active', btn.getAttribute('data-value') === s.animation);
                    });
                }
                
                if (typeof syncUI === 'function') syncUI();
                if (typeof updateDots === 'function') updateDots();
            }

            function loadSettings() {
                const saved = localStorage.getItem('quarto-indicator-settings');
                if (saved) {
                    try {
                        applySettings(JSON.parse(saved));
                    } catch (e) {
                        console.error('Error loading settings:', e);
                    }
                }
            }
            
            // Load immediately
            loadSettings();

            // Update save triggers
             panel.querySelectorAll('.indicator-btn-option, .indicator-color-btn').forEach(btn => {
                btn.addEventListener('click', saveSettings);
            });
            panel.querySelectorAll('input').forEach(input => {
                input.addEventListener('input', saveSettings);
                input.addEventListener('change', saveSettings);
            });

            // 8.5 Reset Button Logic
            const resetBtn = panel.querySelector('#indicatorResetBtn');
            resetBtn.addEventListener('click', () => {
                if (confirm('Are you sure you want to reset all settings to defaults?')) {
                    localStorage.removeItem('quarto-indicator-settings');
                    window.location.reload(); // Simplest way to restore all defaults
                }
            });
            window.addEventListener('keydown', (e) => {
                // Ignore if typing in an input text field
                if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA' || e.target.isContentEditable) return;
                
                if (e.key.toLowerCase() === settingsKey) {
                    const isVisible = panel.classList.toggle('visible');
                    if (isVisible) {
                        // Panel opening: remember if laser was active, then turn it off
                        window._laserWasActiveBeforePanel = document.body.classList.contains('laser-active');
                        if (window._laserWasActiveBeforePanel && typeof window.laserPointerSetPower === 'function') {
                            window.laserPointerSetPower(false);
                        }
                    } else {
                        // Panel closing: restore laser if it was active before
                        if (window._laserWasActiveBeforePanel && typeof window.laserPointerSetPower === 'function') {
                            window.laserPointerSetPower(true);
                        }
                        window._laserWasActiveBeforePanel = false;
                    }
                    const myItem = document.querySelector('.slide-tool-item.progress-settings-item');
                    if (myItem) {
                        if (isVisible) myItem.classList.add('selected');
                        else myItem.classList.remove('selected');
                    }
                }
                if (e.key.toLowerCase() === toggleKey) {
                    container.classList.toggle('visible');
                    // Ensure it stays hidden/visible by overriding logic efficiently
                    const isVisible = container.classList.contains('visible');
                    container.style.opacity = isVisible ? '1' : '0';
                    container.style.pointerEvents = isVisible ? 'auto' : 'none';
                }
            });

        }

    reveal.on('slidechanged', updateDots);
        reveal.on('ready', updateDots);
        
        // Initialize Settings Menu if not already present
        if (!document.querySelector('.indicator-settings-panel')) {
             createSettingsMenu(indicatorContainer, config);
        }

        // Initial update
        updateDots();
        inheritThemeColor(); // Auto-seed from theme if no saved preference
        console.log("Progress Indicator Initialized Successfully.");
        
        } catch (e) {
            console.error("Quarto Progress Indicator Error:", e);
        }
    }

    if (window.Reveal && window.Reveal.isReady()) {
        initProgressIndicator();
    } else {
        document.addEventListener('DOMContentLoaded', () => {
            if (window.Reveal) {
                if (window.Reveal.isReady()) {
                    initProgressIndicator();
                } else {
                    window.Reveal.on('ready', initProgressIndicator);
                }
            }
        });
    }
})();

]====]

function Pandoc(doc)
  if not quarto.doc.is_format('revealjs') then
    return doc
  end

  quarto.doc.include_text(
    'after-body',
    '<style>\n' .. css .. '\n</style>\n' ..
    '<script>\n' .. js  .. '\n</script>'
  )

  return doc
end