import { useEffect, useRef, useState } from "react";

const SOURCE_DESKTOP_WIDTH = 1440;
const SOURCE_DESKTOP_HEIGHT = 1080;

export function PipoWindow({ onClose, onInteract, isExiting = false, onExitComplete }) {
  const shellRef = useRef(null);
  const frameRef = useRef(null);
  const [scale, setScale] = useState(1);

  useEffect(() => {
    shellRef.current?.focus();
    const onKeyDown = (event) => event.key === "Escape" && onClose();
    document.addEventListener("keydown", onKeyDown);
    return () => document.removeEventListener("keydown", onKeyDown);
  }, [onClose]);

  useEffect(() => {
    const frame = frameRef.current;
    const bindFrame = () => frame?.contentDocument?.addEventListener("pointerdown", onInteract, { once: true });
    frame?.addEventListener("load", bindFrame);
    bindFrame();
    return () => {
      frame?.removeEventListener("load", bindFrame);
      frame?.contentDocument?.removeEventListener("pointerdown", onInteract);
    };
  }, [onInteract]);

  useEffect(() => {
    if (!isExiting) return undefined;
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      onExitComplete?.();
      return undefined;
    }
    const timeout = window.setTimeout(() => onExitComplete?.(), 280);
    return () => window.clearTimeout(timeout);
  }, [isExiting, onExitComplete]);

  useEffect(() => {
    const desktop = shellRef.current?.closest(".macos-desktop");
    if (!desktop) return undefined;
    const updateScale = () => setScale(Math.min(
      desktop.clientWidth / SOURCE_DESKTOP_WIDTH,
      desktop.clientHeight / SOURCE_DESKTOP_HEIGHT,
    ));
    updateScale();
    const observer = new ResizeObserver(updateScale);
    observer.observe(desktop);
    return () => observer.disconnect();
  }, []);

  const frameStyle = {
    width: SOURCE_DESKTOP_WIDTH,
    height: SOURCE_DESKTOP_HEIGHT,
    transform: `scale(${scale})`,
  };

  return (
    <section className={`pipo-demo-shell${isExiting ? " pipo-demo-shell--exiting" : ""}`} role="dialog" aria-label="Pipo demo" tabIndex="-1" ref={shellRef}>
      <iframe
        ref={frameRef}
        className="pipo-demo-frame"
        src="./pipo-menu/index.html?embedded=1&mode=demo&cursor=9"
        title="Pipo menu bar app demo"
        scrolling="no"
        style={frameStyle}
      />
    </section>
  );
}
