import gsap from "gsap";
import { ScrollTrigger } from "gsap/ScrollTrigger";

export function initHorizontalScroll(
  stage,
  track,
  { onPanelChange, onPanelProgress, onNavigateReady } = {},
) {
  if (!stage || !track) return () => {};

  gsap.registerPlugin(ScrollTrigger);
  const media = gsap.matchMedia();
  const panels = [...track.querySelectorAll("[data-panel]:not([hidden])")];
  const lastPanelIndex = Math.max(0, panels.length - 1);
  let refreshFrame = 0;
  const refresh = () => {
    cancelAnimationFrame(refreshFrame);
    refreshFrame = requestAnimationFrame(() => ScrollTrigger.refresh());
  };

  media.add("(prefers-reduced-motion: no-preference)", () => {
    const distance = () => Math.max(0, track.scrollWidth - window.innerWidth);
    const tween = gsap.to(track, {
      x: () => -distance(),
      ease: "none",
      scrollTrigger: {
        trigger: stage,
        start: "top top",
        end: () => `+=${distance()}`,
        pin: true,
        scrub: 0.6,
        invalidateOnRefresh: true,
        snap: lastPanelIndex > 0 ? {
          snapTo: 1 / lastPanelIndex,
          delay: 2,
          duration: { min: 0.25, max: 0.65 },
          ease: "power2.out",
          directional: false,
        } : false,
        onUpdate(self) {
          onPanelProgress?.(self.progress);
          const panelIndex = Math.round(self.progress * lastPanelIndex);
          onPanelChange?.(panelIndex);
        },
      },
    });

    const navigateToPanel = (index, behavior = "smooth") => {
      const trigger = tween.scrollTrigger;
      if (!trigger || lastPanelIndex === 0) return;

      const safeIndex = Math.min(lastPanelIndex, Math.max(0, index));
      const progress = safeIndex / lastPanelIndex;
      const targetScroll = trigger.start + (trigger.end - trigger.start) * progress;
      window.scrollTo({ top: targetScroll, behavior });
    };

    onNavigateReady?.(navigateToPanel);
    onPanelProgress?.(0);
    onPanelChange?.(0);

    const normalizeWheelDelta = (event, delta) => {
      if (event.deltaMode === 1) return delta * 16;
      if (event.deltaMode === 2) return delta * window.innerHeight;
      return delta;
    };

    const canScrollInside = (target, delta) => {
      if (!(target instanceof Element)) return false;
      const scrollable = target.closest("textarea, [data-scrollable]");
      if (!scrollable || scrollable.scrollHeight <= scrollable.clientHeight) return false;
      return delta < 0
        ? scrollable.scrollTop > 0
        : scrollable.scrollTop + scrollable.clientHeight < scrollable.scrollHeight - 1;
    };

    const handleWheel = (event) => {
      if (event.ctrlKey) return;

      const trigger = tween.scrollTrigger;
      if (!trigger) return;

      const horizontalGesture = Math.abs(event.deltaX) > Math.abs(event.deltaY);
      const rawDelta = horizontalGesture ? event.deltaX : event.deltaY;
      const delta = normalizeWheelDelta(event, rawDelta);
      if (delta === 0) return;
      if (!horizontalGesture && canScrollInside(event.target, delta)) return;

      const scrollingElement = document.scrollingElement ?? document.documentElement;
      const current = scrollingElement.scrollTop;
      const next = Math.min(trigger.end, Math.max(trigger.start, current + delta));

      if (event.cancelable) event.preventDefault();
      if (next !== current) scrollingElement.scrollTop = next;
    };

    const keepFocusedSceneVisible = (event) => {
      const scene = event.target.closest("[data-panel]");
      const trigger = tween.scrollTrigger;
      if (!scene || !trigger || distance() === 0) return;

      const progress = Math.min(1, Math.max(0, scene.offsetLeft / distance()));
      const targetScroll = trigger.start + (trigger.end - trigger.start) * progress;
      window.scrollTo({ top: targetScroll, behavior: "auto" });
    };

    stage.addEventListener("focusin", keepFocusedSceneVisible);
    window.addEventListener("wheel", handleWheel, { passive: false, capture: true });

    return () => {
      stage.removeEventListener("focusin", keepFocusedSceneVisible);
      window.removeEventListener("wheel", handleWheel, { capture: true });
      tween.kill();
    };
  });

  media.add("(prefers-reduced-motion: reduce)", () => {
    const getPanelIndex = () => {
      if (panels.length < 2) return 0;
      return panels.reduce((closestIndex, panel, index) => {
        const closestDistance = Math.abs(panels[closestIndex].offsetLeft - window.scrollX);
        const panelDistance = Math.abs(panel.offsetLeft - window.scrollX);
        return panelDistance < closestDistance ? index : closestIndex;
      }, 0);
    };

    const navigateToPanel = (index) => {
      const safeIndex = Math.min(lastPanelIndex, Math.max(0, index));
      window.scrollTo({ left: panels[safeIndex]?.offsetLeft ?? 0, behavior: "auto" });
    };

    const updateActivePanel = () => {
      const panelIndex = getPanelIndex();
      onPanelProgress?.(lastPanelIndex ? panelIndex / lastPanelIndex : 0);
      onPanelChange?.(panelIndex);
    };

    onNavigateReady?.(navigateToPanel);
    updateActivePanel();
    window.addEventListener("scroll", updateActivePanel, { passive: true });

    return () => window.removeEventListener("scroll", updateActivePanel);
  });

  const observer = new ResizeObserver(refresh);
  observer.observe(track);
  window.addEventListener("load", refresh, { once: true });
  document.fonts?.ready.then(refresh);

  return () => {
    cancelAnimationFrame(refreshFrame);
    observer.disconnect();
    media.revert();
  };
}
