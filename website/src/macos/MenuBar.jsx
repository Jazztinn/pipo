import React, { useEffect, useRef, useState } from 'react';

const MENUS = [
  { label: '', accessibleLabel: 'Apple', items: [{ label: 'About This Mac', action: 'about-mac' }, { divider: true }, { label: 'Restart…', action: 'restart' }, { label: 'Shut Down…', action: 'shutdown' }] },
  { label: 'Pipo', items: [{ label: 'About Pipo', action: 'about-pipo' }, { divider: true }, { label: 'Services', submenu: [{ label: 'No Services Apply' }] }, { divider: true }, { label: 'Hide Pipo', action: 'hide-pipo', shortcut: '⌘H' }, { label: 'Hide Others', action: 'hide-others', shortcut: '⌥⌘H' }, { divider: true }, { label: 'Quit Pipo', action: 'quit-pipo', shortcut: '⌘Q' }] },
  { label: 'Window', items: [{ label: 'Close All Windows', action: 'close-all' }, { label: 'Open All Windows', action: 'open-all' }] },
  { label: 'Help', items: [
    { label: 'Search' },
    { divider: true },
    { label: 'Privacy', action: 'privacy' },
    { label: 'Terms', action: 'terms' },
    { label: 'Releases', action: 'releases' },
    { label: 'Docs', action: 'docs' },
  ] },
];

const errorSound = new Audio("/error.mp3");
errorSound.preload = "auto";
errorSound.volume = 0.35;

function MenuItem({ item, onClose, onOpenSubmenu, isSubmenuOpen, onAction }) {
  if (item.divider) return <div className="macos-menu-divider" role="separator" />;
  const hasSubmenu = Array.isArray(item.submenu);
  return <div className="macos-menu-item-wrap">
    <button type="button" className="macos-menu-item" role="menuitem" aria-haspopup={hasSubmenu ? 'menu' : undefined} aria-expanded={hasSubmenu ? isSubmenuOpen : undefined} onMouseEnter={() => hasSubmenu && onOpenSubmenu(item)} onFocus={() => hasSubmenu && onOpenSubmenu(item)} onClick={() => { if (hasSubmenu) onOpenSubmenu(item); else { if (item.action) onAction(item.action); onClose(); } }}>
      <span>{item.label}</span><span className="macos-menu-meta">{item.shortcut || (hasSubmenu ? '›' : '')}</span>
    </button>
    {hasSubmenu && isSubmenuOpen && <div className="macos-submenu" role="menu">{item.submenu.map((child) => <button type="button" className="macos-menu-item" role="menuitem" key={child.label} onClick={onClose}>{child.label}</button>)}</div>}
  </div>;
}

function Menu({ menu, index, openIndex, setOpenIndex, menuButtonRefs, onAction }) {
  const [submenu, setSubmenu] = useState(null);
  const open = openIndex === index;
  const menuRef = useRef(null);
  const close = () => { setOpenIndex(null); setSubmenu(null); };
  const moveTop = (delta) => menuButtonRefs.current[(index + delta + MENUS.length) % MENUS.length]?.focus();

  useEffect(() => { if (!open) setSubmenu(null); }, [open]);
  return <div className="macos-menu-wrap" onMouseEnter={() => openIndex !== null && setOpenIndex(index)}>
    <button
      ref={(node) => { menuButtonRefs.current[index] = node; }}
      type="button"
      className={`macos-menu-trigger${open ? ' is-open' : ''}`}
      aria-label={menu.accessibleLabel}
      aria-expanded={open}
      aria-haspopup="menu"
      onClick={() => setOpenIndex(index)}
      onKeyDown={(event) => {
        if (event.key === 'ArrowRight') { event.preventDefault(); moveTop(1); if (open) setOpenIndex((index + 1) % MENUS.length); }
        if (event.key === 'ArrowLeft') { event.preventDefault(); moveTop(-1); if (open) setOpenIndex((index - 1 + MENUS.length) % MENUS.length); }
        if (event.key === 'ArrowDown' || event.key === 'Enter' || event.key === ' ') { event.preventDefault(); setOpenIndex(index); requestAnimationFrame(() => menuRef.current?.querySelector('[role="menuitem"]:not(.macos-menu-divider)')?.focus()); }
        if (event.key === 'Escape') close();
      }}
    >{menu.label}</button>
    {open && <div ref={menuRef} className="macos-menu-panel" role="menu" aria-label={`${menu.accessibleLabel || menu.label} menu`} onKeyDown={(event) => {
      const items = [...menuRef.current.querySelectorAll(':scope > .macos-menu-item-wrap > .macos-menu-item')];
      const current = items.indexOf(document.activeElement);
      if (event.key === 'ArrowDown' || event.key === 'ArrowUp') { event.preventDefault(); items[(current + (event.key === 'ArrowDown' ? 1 : -1) + items.length) % items.length]?.focus(); }
      if (event.key === 'ArrowRight') { const item = items[current]; const data = menu.items.find((entry) => entry.label === item?.textContent?.replace(/›$/, '').trim()); if (data?.submenu) { event.preventDefault(); setSubmenu(data); } }
      if (event.key === 'ArrowLeft' || event.key === 'Escape') { event.preventDefault(); setSubmenu(null); menuButtonRefs.current[index]?.focus(); }
      if (event.key === 'Escape') close();
    }}>{menu.items.map((item, itemIndex) => <MenuItem key={item.label || `divider-${itemIndex}`} item={item} onClose={close} onOpenSubmenu={setSubmenu} isSubmenuOpen={submenu?.label === item.label} onAction={onAction} />)}</div>}
  </div>;
}

export function MenuBar({ onAboutPipo, onAboutMac, onOpenPipo, onSystemPower, onCloseAllWindows, onOpenAllWindows, onHidePipo, onHideOthers, onQuitPipo }) {
  const [openIndex, setOpenIndex] = useState(null);
  const [now, setNow] = useState(() => new Date());
  const menuButtonRefs = useRef([]);
  const barRef = useRef(null);

  useEffect(() => { const timer = window.setInterval(() => setNow(new Date()), 1000); return () => window.clearInterval(timer); }, []);
  useEffect(() => {
    const onPointerDown = (event) => { if (!barRef.current?.contains(event.target)) setOpenIndex(null); };
    const onKeyDown = (event) => { if (event.key === 'Escape') { setOpenIndex(null); } };
    document.addEventListener('pointerdown', onPointerDown); document.addEventListener('keydown', onKeyDown);
    return () => { document.removeEventListener('pointerdown', onPointerDown); document.removeEventListener('keydown', onKeyDown); };
  }, []);
  const date = now.toLocaleDateString(undefined, { weekday: 'short', month: 'short', day: 'numeric' });
  const time = now.toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' });
  const handleAction = (action) => {
    if (action === 'about-pipo') onAboutPipo?.();
    if (action === 'about-mac') onAboutMac?.();
    if (action === 'restart' || action === 'shutdown') onSystemPower?.();
    if (action === 'close-all') onCloseAllWindows?.();
    if (action === 'open-all') onOpenAllWindows?.();
    if (action === 'hide-pipo') onHidePipo?.();
    if (action === 'hide-others') onHideOthers?.();
    if (action === 'quit-pipo') onQuitPipo?.();
    if (action === 'error-sound') {
      errorSound.currentTime = 0;
      errorSound.play().catch(() => {});
    }
    const links = {
      privacy: './privacy.html',
      terms: './terms.html',
      releases: 'https://github.com/Jazztinn/pipo/releases',
      docs: 'https://github.com/Jazztinn/pipo#readme',
    };
    if (links[action]) window.open(links[action], '_blank', 'noopener,noreferrer');
  };
  return <header ref={barRef} className="macos-menubar">
    <nav className="macos-menu-list" aria-label="Menu bar">{MENUS.map((menu, index) => <Menu key={menu.label} {...{ menu, index, openIndex, setOpenIndex, menuButtonRefs }} onAction={handleAction} />)}</nav>
    <div className="macos-status" aria-label="System status"><button className="macos-menu-pipo-button" type="button" aria-label="Open Pipo" onClick={onOpenPipo}><img className="macos-menu-pipo-icon" src="./macos-icons/pipo-hollow.png" alt="" /></button><time dateTime={now.toISOString()}>{date}: {time}</time></div>
  </header>;
}

export default MenuBar;
