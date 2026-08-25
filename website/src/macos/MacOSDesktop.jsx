import { useEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { Dock } from "./Dock.jsx";
import { MenuBar } from "./MenuBar.jsx";
import { PipoWindow } from "./PipoWindow.jsx";

const CUSTOM_CURSOR_ENABLED = false;

function SmoothCursor() {
  const cursorRef = useRef(null);

  useEffect(() => {
    const screen = document.querySelector(".macbook-screen");
    const hitbox = screen?.querySelector(".macos-cursor-hitbox");
    const frame = screen?.querySelector(".pipo-demo-frame");
    const pointerQuery = window.matchMedia("(any-hover: hover) and (any-pointer: fine)");
    const reducedMotionQuery = window.matchMedia("(prefers-reduced-motion: reduce)");
    if (!screen || !hitbox || !pointerQuery.matches) return undefined;
    const target = { x: 0, y: 0, angle: 0, visible: false };
    const current = { x: 0, y: 0, angle: 0 };
    let hasPosition = false;
    let raf = 0;
    let lastInput = null;
    const pointInHitbox = (x, y) => {
      const rect = hitbox.getBoundingClientRect();
      return x >= rect.left && x <= rect.right && y >= rect.top && y <= rect.bottom;
    };
    const receivePoint = (x, y) => {
      if (lastInput && !reducedMotionQuery.matches) {
        const dx = x - lastInput.x;
        const dy = y - lastInput.y;
        if (Math.hypot(dx, dy) > 3) target.angle = Math.atan2(dy, dx) * (180 / Math.PI) + 90;
      }
      lastInput = { x, y };
      target.x = x; target.y = y; target.visible = true;
      if (!hasPosition) {
        current.x = x; current.y = y;
        hasPosition = true;
      }
      if (!raf) raf = requestAnimationFrame(tick);
    };
    const handlePointerMove = (event) => {
      if (event.pointerType === "touch") return;
      if (pointInHitbox(event.clientX, event.clientY)) {
        receivePoint(event.clientX, event.clientY);
      } else {
        hide();
      }
    };
    const handleFrameMessage = (event) => {
      if (event.origin !== window.location.origin || event.source !== frame?.contentWindow || event.data?.type !== "pipo:pointermove") return;
      const rect = frame.getBoundingClientRect();
      receivePoint(
        rect.left + event.data.x * (rect.width / frame.clientWidth),
        rect.top + event.data.y * (rect.height / frame.clientHeight),
      );
    };
    const hide = () => {
      target.visible = false;
      lastInput = null;
      cursorRef.current?.classList.remove("is-visible");
    };
    const tick = () => {
      if (reducedMotionQuery.matches) {
        current.x = target.x; current.y = target.y;
      } else {
        current.x += (target.x - current.x) * 0.45;
        current.y += (target.y - current.y) * 0.45;
        const angleDelta = ((target.angle - current.angle + 540) % 360) - 180;
        current.angle += angleDelta * 0.18;
      }
      if (cursorRef.current) {
        cursorRef.current.style.transform = `translate3d(${current.x - 12.5}px, ${current.y - 3.4}px, 0) rotate(${current.angle}deg)`;
        cursorRef.current.classList.toggle("is-visible", target.visible);
      }
      const settling = Math.abs(target.x - current.x) + Math.abs(target.y - current.y) > 0.1;
      const rotating = Math.abs(((target.angle - current.angle + 540) % 360) - 180) > 0.1;
      raf = target.visible && (settling || rotating) ? requestAnimationFrame(tick) : 0;
    };
    window.addEventListener("pointermove", handlePointerMove, { passive: true });
    window.addEventListener("message", handleFrameMessage);
    return () => {
      cancelAnimationFrame(raf);
      window.removeEventListener("pointermove", handlePointerMove);
      window.removeEventListener("message", handleFrameMessage);
    };
  }, []);

  return createPortal(
    <span ref={cursorRef} className="smooth-cursor" aria-hidden="true"><svg viewBox="0 0 50 54" focusable="false"><path d="M42.6817 41.1495 27.5103 6.79925C26.7269 5.02557 24.2082 5.02558 23.3927 6.79925L7.59814 41.1495C6.75833 42.9759 8.52712 44.8902 10.4125 44.1954L24.3757 39.0496C24.8829 38.8627 25.4385 38.8627 25.9422 39.0496L39.8121 44.1954C41.6849 44.8902 43.4884 42.9759 42.6817 41.1495Z" /></svg></span>,
    document.body,
  );
}

function AboutPipo({ onClose }) {
  const layerRef = useRef(null);
  const windowRef = useRef(null);
  const [position, setPosition] = useState(null);
  const dragRef = useRef(null);

  useEffect(() => {
    windowRef.current?.focus();
    const handleKeyDown = (event) => { if (event.key === "Escape") onClose(); };
    document.addEventListener("keydown", handleKeyDown);
    return () => document.removeEventListener("keydown", handleKeyDown);
  }, [onClose]);

  const handlePointerDown = (event) => {
    if (event.button !== 0 || event.target.closest("button")) return;
    const layer = layerRef.current;
    const modal = windowRef.current;
    if (!layer || !modal) return;
    const layerRect = layer.getBoundingClientRect();
    const windowRect = modal.getBoundingClientRect();
    const left = windowRect.left - layerRect.left;
    const top = windowRect.top - layerRect.top;
    setPosition({ left, top });
    dragRef.current = {
      pointerId: event.pointerId,
      startX: event.clientX,
      startY: event.clientY,
      left,
      top,
      width: windowRect.width,
      height: windowRect.height,
      layerWidth: layerRect.width,
      layerHeight: layerRect.height,
    };
    event.currentTarget.setPointerCapture?.(event.pointerId);
    globalThis.window.addEventListener('pointermove', handlePointerMove);
    globalThis.window.addEventListener('pointerup', stopDragging, { once: true });
    globalThis.window.addEventListener('pointercancel', stopDragging, { once: true });
    event.preventDefault();
  };

  const handlePointerMove = (event) => {
    const drag = dragRef.current;
    if (!drag || drag.pointerId !== event.pointerId) return;
    const left = Math.max(0, Math.min(drag.layerWidth - drag.width, drag.left + event.clientX - drag.startX));
    const top = Math.max(0, Math.min(drag.layerHeight - drag.height, drag.top + event.clientY - drag.startY));
    setPosition({ left, top });
  };

  const stopDragging = (event) => {
    if (dragRef.current?.pointerId === event.pointerId) {
      dragRef.current = null;
      globalThis.window.removeEventListener('pointermove', handlePointerMove);
    }
  };

  return (
    <div ref={layerRef} className="macos-about-layer" onPointerDown={(event) => { if (event.target === event.currentTarget) onClose(); }} onPointerMove={handlePointerMove} onPointerUp={stopDragging} onPointerCancel={stopDragging}>
      <section
        ref={windowRef}
        className="macos-about-window"
        style={position ? { position: "absolute", left: position.left, top: position.top } : undefined}
        role="dialog"
        aria-modal="true"
        aria-labelledby="macos-about-title"
        tabIndex="-1"
      >
        <div className="macos-about-titlebar" onPointerDownCapture={handlePointerDown} onPointerMove={handlePointerMove}>
          <div className="macos-window-controls" aria-label="Window controls" onPointerDown={(event) => event.stopPropagation()}>
            <button className="macos-window-control macos-window-close" type="button" aria-label="Close About Pipo" title="Close" onClick={onClose}>
              <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M18 6 6 18M6 6l12 12" /></svg>
            </button>
            <span className="macos-window-control" aria-hidden="true" />
            <span className="macos-window-control" aria-hidden="true" />
          </div>
          <strong>About Pipo</strong>
        </div>
        <img className="macos-about-icon" src="./pipo-logo.png" alt="" draggable="false" />
        <h2 id="macos-about-title">Pipo</h2>
        <p>Version 0.4.1 (9)</p>
        <p className="macos-about-copyright">Copyright 2026 Jazztinn. Pipo is an unofficial student utility.</p>
      </section>
    </div>
  );
}

function AboutMac({ onClose }) {
  const layerRef = useRef(null);
  const windowRef = useRef(null);
  const [position, setPosition] = useState(null);
  const dragRef = useRef(null);

  useEffect(() => {
    const handleKeyDown = (event) => { if (event.key === "Escape") onClose(); };
    document.addEventListener("keydown", handleKeyDown);
    return () => document.removeEventListener("keydown", handleKeyDown);
  }, [onClose]);

  const handlePointerDown = (event) => {
    if (event.button !== 0 || event.target.closest("button")) return;
    const layer = layerRef.current;
    const modal = windowRef.current;
    if (!layer || !modal) return;
    const layerRect = layer.getBoundingClientRect();
    const windowRect = modal.getBoundingClientRect();
    const left = windowRect.left - layerRect.left;
    const top = windowRect.top - layerRect.top;
    setPosition({ left, top });
    dragRef.current = { pointerId: event.pointerId, startX: event.clientX, startY: event.clientY, left, top, width: windowRect.width, height: windowRect.height, layerWidth: layerRect.width, layerHeight: layerRect.height };
    event.currentTarget.setPointerCapture?.(event.pointerId);
    globalThis.window.addEventListener("pointermove", handlePointerMove);
    globalThis.window.addEventListener("pointerup", stopDragging, { once: true });
    globalThis.window.addEventListener("pointercancel", stopDragging, { once: true });
    event.preventDefault();
  };

  const handlePointerMove = (event) => {
    const drag = dragRef.current;
    if (!drag || drag.pointerId !== event.pointerId) return;
    setPosition({
      left: Math.max(0, Math.min(drag.layerWidth - drag.width, drag.left + event.clientX - drag.startX)),
      top: Math.max(0, Math.min(drag.layerHeight - drag.height, drag.top + event.clientY - drag.startY)),
    });
  };

  const stopDragging = (event) => {
    if (dragRef.current?.pointerId === event.pointerId) {
      dragRef.current = null;
      globalThis.window.removeEventListener("pointermove", handlePointerMove);
    }
  };

  return (
    <div ref={layerRef} className="macos-about-layer" onPointerMove={handlePointerMove} onPointerUp={stopDragging} onPointerCancel={stopDragging}>
      <section ref={windowRef} className="macos-about-window macos-about-mac-window" style={position ? { position: "absolute", left: position.left, top: position.top } : undefined} role="dialog" aria-modal="true" aria-labelledby="macos-about-mac-title" tabIndex="-1">
        <div className="macos-about-titlebar" onPointerDownCapture={handlePointerDown} onPointerMove={handlePointerMove}>
          <div className="macos-window-controls" aria-label="Window controls" onPointerDown={(event) => event.stopPropagation()}>
            <button className="macos-window-control macos-window-close" type="button" aria-label="Close About This Mac" title="Close" onClick={onClose}>
              <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M18 6 6 18M6 6l12 12" /></svg>
            </button>
            <span className="macos-window-control" aria-hidden="true" />
            <span className="macos-window-control" aria-hidden="true" />
          </div>
          <strong>About This Mac</strong>
        </div>
        <img className="macos-about-mac-image" src="./macbook-pro-13.svg" alt="MacBook" draggable="false" />
        <h2 id="macos-about-mac-title">MacBook Pro</h2>
        <p className="macos-about-mac-model">M2, 2022</p>
        <dl className="macos-about-specs">
          <dt>Chip</dt><dd>M2, 8-core neural goblin</dd>
          <dt>Memory</dt><dd>67 GB</dd>
          <dt>Startup disk</dt><dd>Dragonstone</dd>
          <dt>Serial number</dt><dd>00000001</dd>
          <dt>macOS</dt><dd>Tahoe 26.2</dd>
        </dl>
      </section>
    </div>
  );
}

export function MacOSDesktop() {
  const [aboutOpen, setAboutOpen] = useState(true);
  const [aboutMacOpen, setAboutMacOpen] = useState(false);
  const [pipoOpen, setPipoOpen] = useState(true);
  const [isPoweringOff, setIsPoweringOff] = useState(false);

  const handleSystemPower = () => {
    if (isPoweringOff) return;
    const sound = new Audio("./preview_4.mp3");
    sound.volume = 0.35;
    sound.play().catch(() => {});
    setIsPoweringOff(true);

    const dustLayer = document.createElement("div");
    dustLayer.className = "snap-dust-layer";
    dustLayer.setAttribute("aria-hidden", "true");

    const componentSelectors = [
      ".site-nav > *",
      ".macbook-device-frame",
      ".macbook-screen",
      ".demo-slot-hero",
      ".macos-wallpaper",
      ".macos-wallpaper-tone",
      ".macos-menubar",
      ".macos-try-pipo",
      ".pipo-demo-shell",
      ".pipo-demo-frame",
      ".macos-dock",
      ".macos-about-window",
      ".macos-screen-corners",
      ".hero-copy > *",
      ".showcase-panel > *",
      ".feedback-copy > *",
      ".feedback-form > *",
      ".closing-copy > *",
      ".footer-links > *",
    ];
    const components = [...document.querySelectorAll(componentSelectors.join(","))];
    let longestAnimation = 0;

    components.forEach((component, componentIndex) => {
      const rect = component.getBoundingClientRect();
      const delay = componentIndex === components.length - 1
        ? 1.85
        : Math.max(0, Math.random() * 1.75 - (componentIndex % 4 === 0 ? 0.25 : 0));
      const duration = 0.75 + Math.random() * 0.65;
      longestAnimation = Math.max(longestAnimation, delay + duration);
      component.classList.add("snap-component");
      component.style.setProperty("--snap-delay", `${delay}s`);
      component.style.setProperty("--snap-duration", `${duration}s`);

      if (rect.width <= 0 || rect.height <= 0 || rect.right < 0 || rect.left > window.innerWidth) return;
      const particleCount = Math.max(5, Math.min(16, Math.round((rect.width * rect.height) / 18000)));
      for (let index = 0; index < particleCount; index += 1) {
        const particle = document.createElement("i");
        const x = rect.left + Math.random() * rect.width;
        const y = rect.top + Math.random() * rect.height;
        const size = 1 + Math.random() * 4;
        const driftX = 30 + Math.random() * 120;
        const driftY = -65 + Math.random() * 130;
        const particleDelay = delay + Math.random() * 0.35;
        const particleDuration = duration + 0.35 + Math.random() * 0.45;
        longestAnimation = Math.max(longestAnimation, particleDelay + particleDuration);
        particle.style.cssText = `--x:${x}px;--y:${y}px;--size:${size}px;--drift-x:${driftX}px;--drift-y:${driftY}px;--delay:${particleDelay}s;--duration:${particleDuration}s`;
        dustLayer.appendChild(particle);
      }
    });

    document.body.appendChild(dustLayer);
    // Leave snapped surface empty. Reloading recreated iframe's black canvas after effect finished.
    window.setTimeout(() => dustLayer.remove(), (longestAnimation + 0.2) * 1000);
  };

  return (
    <div className="macos-desktop" aria-label="macOS desktop">
      <img
        className="macos-wallpaper"
        src="./lpubg-statue.png"
        alt=""
        draggable="false"
      />
      <div className="macos-wallpaper-tone" aria-hidden="true" />
      <MenuBar
        onAboutPipo={() => setAboutOpen(true)}
        onAboutMac={() => setAboutMacOpen(true)}
        onOpenPipo={() => setPipoOpen((open) => !open)}
        onSystemPower={handleSystemPower}
        onCloseAllWindows={() => { setAboutOpen(false); setAboutMacOpen(false); setPipoOpen(false); }}
        onOpenAllWindows={() => { setAboutOpen(true); setAboutMacOpen(true); setPipoOpen(true); }}
        onHidePipo={() => setPipoOpen(false)}
        onHideOthers={() => { setAboutOpen(false); setAboutMacOpen(false); }}
        onQuitPipo={() => { setAboutOpen(false); setAboutMacOpen(false); setPipoOpen(false); }}
      />
      <div className="macos-try-pipo" aria-hidden="true">
        <svg className="macos-try-pipo-arrow" viewBox="0 0 190 185" focusable="false">
          <path d="M20 169C24 123 43 85 76 55C99 34 124 23 157 22" />
          <path d="M137 8L158 22L143 43" />
        </svg>
        <span>try pipo</span>
      </div>
      {pipoOpen && <PipoWindow onClose={() => setPipoOpen(false)} />}
      <Dock />
      {aboutOpen && <AboutPipo onClose={() => setAboutOpen(false)} />}
      {aboutMacOpen && <AboutMac onClose={() => setAboutMacOpen(false)} />}
      {CUSTOM_CURSOR_ENABLED && <div className="macos-cursor-hitbox" aria-hidden="true" />}
      {CUSTOM_CURSOR_ENABLED && <SmoothCursor />}
    </div>
  );
}
