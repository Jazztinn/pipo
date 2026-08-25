import { useRef, useState } from "react";

const APPS = [
  ["finder", "Finder", "./macos-icons/finder.png"],
  ["pipo", "Pipo", "./pipo-logo.png"],
  ["system-settings", "System Settings", "./macos-icons/system-settings.png"],
  ["adobe-photoshop", "Adobe Photoshop", "./macos-icons/adobe-photoshop.png"],
  ["trash", "Trash", "./macos-icons/trash.png"],
];

export function Dock() {
  const dockRef = useRef(null);
  const [pointerX, setPointerX] = useState(null);

  const handlePointerMove = (event) => setPointerX(event.clientX);
  const resetMagnification = () => setPointerX(null);
  const scaleFor = (index) => {
    const button = dockRef.current?.querySelector(`[data-dock-index="${index}"]`);
    if (pointerX === null || !button) return 1;
    const bounds = button.getBoundingClientRect();
    const distance = Math.abs(pointerX - (bounds.left + bounds.width / 2));
    return 1 + Math.max(0, 1 - distance / 92) * 0.22;
  };

  return <nav className="macos-dock" aria-label="Applications">
    <ul className="macos-dock-list" ref={dockRef} onPointerMove={handlePointerMove} onPointerLeave={resetMagnification}>
      {APPS.map(([name, label, source], index) => <li className={name === "trash" ? "macos-dock-item macos-dock-trash" : "macos-dock-item"} key={name}>
        {name === "trash" && <span className="macos-dock-separator" aria-hidden="true" />}
        <button className="macos-dock-button" type="button" data-dock-index={index} aria-label={label} style={{ "--macos-dock-scale": scaleFor(index) }} onFocus={resetMagnification}>
          {name === "pipo" ? <span className="macos-dock-pipo-icon" aria-hidden="true">
            <img src={source} alt="" draggable="false" />
          </span> : <img src={source} alt="" aria-hidden="true" draggable="false" style={{ display: "block", width: "100%", height: "100%", filter: "drop-shadow(0 3px 2px rgba(0, 0, 0, 0.2))" }} />}
        </button>
      </li>)}
    </ul>
  </nav>;
}
