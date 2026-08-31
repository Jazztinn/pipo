import { initHorizontalScroll } from "./horizontal-scroll.js";
import {
  BOAT_WAVE_HEIGHT,
  BOAT_WAVE_WIDTH,
  createBoatWavePath,
  sampleBoatWave,
} from "./boat-wave.js";

const clickSound = new Audio("/pipoclick.mp3");
clickSound.preload = "auto";
clickSound.volume = 0.35;
const cartoonSound = document.querySelector("#pipo-cartoon-sound");
const installGuide = document.querySelector("[data-install-guide]");
const desktopDownloadGuide = window.matchMedia("(min-width: 1024px)");
const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
let downloadGuideTrigger = null;
let installGuideCloseTimer = null;
const finishInstallGuideClose = () => {
  window.clearTimeout(installGuideCloseTimer);
  installGuideCloseTimer = null;
  installGuide?.classList.remove("is-open", "is-closing");
  installGuide?.close();
  window.requestAnimationFrame(() => downloadGuideTrigger?.focus());
};
const closeInstallGuide = () => {
  if (!installGuide?.open || installGuide.classList.contains("is-closing")) return;
  if (reducedMotion.matches) {
    finishInstallGuideClose();
    return;
  }
  installGuide.classList.add("is-closing");
  installGuide.classList.remove("is-open");
  installGuideCloseTimer = window.setTimeout(finishInstallGuideClose, 170);
};
const openInstallGuide = () => {
  if (!installGuide || installGuide.open) return;
  window.clearTimeout(installGuideCloseTimer);
  installGuide.classList.remove("is-open", "is-closing");
  installGuide.showModal();
  if (reducedMotion.matches) {
    installGuide.classList.add("is-open");
    return;
  }
  window.requestAnimationFrame(() => {
    window.requestAnimationFrame(() => {
      if (installGuide.open) installGuide.classList.add("is-open");
    });
  });
};
const playCartoonSound = () => {
  if (!cartoonSound) return Promise.resolve();
  cartoonSound.currentTime = 0;
  return cartoonSound.play().catch(() => {});
};
document.addEventListener("click", (event) => {
  if (!(event.target instanceof Element)) return;
  if (event.target.closest(".brand")) {
    playCartoonSound();
    return;
  }
  const link = event.target.closest("a");
  if (link?.matches("[data-download-guide]")) {
    playCartoonSound();
    if (desktopDownloadGuide.matches && installGuide) {
      downloadGuideTrigger = link;
      openInstallGuide();
    }
    return;
  }
  if (!event.target.closest("button, a")) return;
  clickSound.currentTime = 0;
  clickSound.play().catch(() => {});
}, true);

installGuide?.querySelectorAll("[data-install-guide-close]").forEach((button) => {
  button.addEventListener("click", closeInstallGuide);
});

installGuide?.addEventListener("click", (event) => {
  if (event.target === installGuide) closeInstallGuide();
});

installGuide?.addEventListener("cancel", (event) => {
  event.preventDefault();
  closeInstallGuide();
});

installGuide?.addEventListener("keydown", (event) => {
  if (event.key !== "Escape") return;
  event.preventDefault();
  closeInstallGuide();
});

const visitCounter = document.querySelector("[data-visit-count]");
const visitNumber = document.querySelector("[data-visit-number]");

if ("scrollRestoration" in history) {
  history.scrollRestoration = "manual";
}
window.scrollTo({ top: 0, left: 0, behavior: "auto" });

function countVisit() {
  const seedVisits = 50;
  let visits = seedVisits;

  try {
    const storedVisits = Number.parseInt(localStorage.getItem("pipo-visits") ?? "", 10);
    if (sessionStorage.getItem("pipo-visit-recorded")) {
      visits = Number.isFinite(storedVisits) ? Math.max(seedVisits, storedVisits) : seedVisits;
    } else {
      visits = Number.isFinite(storedVisits) && storedVisits >= seedVisits
        ? storedVisits + 1
        : seedVisits;
      localStorage.setItem("pipo-visits", String(visits));
      sessionStorage.setItem("pipo-visit-recorded", "true");
    }
  } catch {
    visits = seedVisits;
  }

  if (visitNumber) visitNumber.textContent = visits.toLocaleString();
  if (visitCounter && !visitNumber) visitCounter.textContent = `Pipo has had ${visits.toLocaleString()} visits`;
}

countVisit();

function initBlurReveal() {
  const elements = [...document.querySelectorAll("[data-blur-reveal]")];
  if (!elements.length) return () => {};

  elements.forEach((element) => {
    element.classList.add("blur-reveal");
    const order = Number.parseInt(element.dataset.revealOrder ?? "", 10);
    if (Number.isFinite(order)) {
      element.style.setProperty("--blur-reveal-delay", `${order * 90}ms`);
    }
  });

  if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
    elements.forEach((element) => element.classList.add("is-revealed"));
    return () => {};
  }

  if (!("IntersectionObserver" in window)) {
    elements.forEach((element) => element.classList.add("is-revealed"));
    return () => {};
  }

  document.documentElement.classList.add("has-blur-reveal");

  let observer;
  const reveal = (element) => {
    element.classList.add("is-revealed");
    observer.unobserve(element);
  };

  observer = new IntersectionObserver((entries) => {
    entries.forEach((entry) => {
      if (entry.isIntersecting) reveal(entry.target);
    });
  }, {
    threshold: 0.15,
    rootMargin: "0px -6% -8% 0px",
  });

  elements.forEach((element) => observer.observe(element));

  return () => {
    observer.disconnect();
    document.documentElement.classList.remove("has-blur-reveal");
  };
}

const destroyBlurReveal = initBlurReveal();
window.addEventListener("pagehide", destroyBlurReveal, { once: true });

function initShowcaseVideo() {
  const video = document.querySelector(".showcase-video");
  if (!video) return () => {};

  const playWhenVisible = () => {
    if (document.visibilityState === "visible") video.play().catch(() => {});
  };
  const observer = new IntersectionObserver(([entry]) => {
    if (entry.isIntersecting) playWhenVisible();
    else video.pause();
  }, { threshold: 0.2 });

  observer.observe(video);
  document.addEventListener("visibilitychange", playWhenVisible);
  return () => {
    observer.disconnect();
    document.removeEventListener("visibilitychange", playWhenVisible);
  };
}

const destroyShowcaseVideo = initShowcaseVideo();
window.addEventListener("pagehide", destroyShowcaseVideo, { once: true });

function createPanelProgress(panels) {
  if (panels.length < 2) return null;

  const motionPreference = window.matchMedia("(prefers-reduced-motion: reduce)");
  const boatEdgeInset = 20;
  const maxBoatRotation = 8;

  const progress = document.createElement("nav");
  progress.className = "panel-progress";
  progress.dataset.panelProgress = "";
  progress.setAttribute("aria-label", "Page sections");

  const wave = document.createElement("span");
  wave.className = "panel-progress__wave";
  wave.setAttribute("aria-hidden", "true");
  wave.innerHTML = `<svg viewBox="0 0 ${BOAT_WAVE_WIDTH} ${BOAT_WAVE_HEIGHT}" preserveAspectRatio="none"><path class="panel-progress__wave-underlay" /><path class="panel-progress__wave-surface" /></svg>`;
  progress.append(wave);

  const wavePaths = [...wave.querySelectorAll("path")];

  const boatMotion = document.createElement("span");
  boatMotion.className = "panel-progress__boat-motion";
  boatMotion.setAttribute("aria-hidden", "true");

  const boat = document.createElement("img");
  boat.className = "panel-progress__boat";
  boat.src = "/rowboat.png";
  boat.alt = "";
  boatMotion.append(boat);
  progress.append(boatMotion);

  const layout = { width: 0, height: 0 };
  const state = {
    progress: 0,
    progressVelocity: 0,
    buoyancy: 0,
    buoyancyVelocity: 0,
    rotation: 0,
    rotationVelocity: 0,
  };
  let targetProgress = 0;
  let elapsed = 0;
  let lastFrameTime = 0;
  let boatFrame = 0;
  let stateReady = false;

  const stepSpring = (valueKey, velocityKey, target, stiffness, damping, deltaTime) => {
    const acceleration = (target - state[valueKey]) * stiffness
      - state[velocityKey] * damping;
    state[velocityKey] += acceleration * deltaTime;
    state[valueKey] += state[velocityKey] * deltaTime;
  };

  const render = (deltaTime = 0) => {
    if (!layout.width || !layout.height) return;

    const reduced = motionPreference.matches;
    if (reduced) state.progress = targetProgress;
    else stepSpring("progress", "progressVelocity", targetProgress, 82, 18, deltaTime);

    const waveTime = reduced ? 0 : elapsed;
    const x = boatEdgeInset
      + state.progress * (BOAT_WAVE_WIDTH - boatEdgeInset * 2);
    const surface = sampleBoatWave(x, waveTime);
    const scaleX = layout.width / BOAT_WAVE_WIDTH;
    const scaleY = layout.height / BOAT_WAVE_HEIGHT;
    const bob = reduced ? 0 : Math.sin(elapsed * 1.45 + state.progress * 1.7) * 0.32;
    const rock = reduced ? 0 : Math.sin(elapsed * 0.92 + 0.6) * 0.48;
    const surfaceAngle = Math.atan2(surface.slope * scaleY, scaleX) * (180 / Math.PI);
    const targetRotation = Math.max(
      -maxBoatRotation,
      Math.min(maxBoatRotation, surfaceAngle * 0.72 + rock),
    );

    if (!stateReady || reduced) {
      state.buoyancy = bob;
      state.buoyancyVelocity = 0;
      state.rotation = targetRotation;
      state.rotationVelocity = 0;
      stateReady = true;
    } else {
      stepSpring("buoyancy", "buoyancyVelocity", bob, 125, 21, deltaTime);
      stepSpring("rotation", "rotationVelocity", targetRotation, 68, 15, deltaTime);
    }

    const pathData = createBoatWavePath(waveTime);
    wavePaths.forEach((path) => path.setAttribute("d", pathData));
    boatMotion.style.transform = `translate3d(${(x * scaleX).toFixed(2)}px, ${((surface.y + state.buoyancy) * scaleY).toFixed(2)}px, 0) rotate(${state.rotation.toFixed(2)}deg)`;
  };

  const animateBoat = (frameTime) => {
    const deltaTime = lastFrameTime
      ? Math.min((frameTime - lastFrameTime) / 1000, 1 / 30)
      : 1 / 60;
    lastFrameTime = frameTime;
    elapsed += deltaTime;
    render(deltaTime);
    boatFrame = requestAnimationFrame(animateBoat);
  };

  const measure = () => {
    const bounds = progress.getBoundingClientRect();
    layout.width = bounds.width;
    layout.height = bounds.height;
    render();
  };

  const handleMotionPreference = () => {
    cancelAnimationFrame(boatFrame);
    boatFrame = 0;
    lastFrameTime = 0;
    stateReady = false;
    state.progressVelocity = 0;
    state.buoyancyVelocity = 0;
    state.rotationVelocity = 0;
    render();
    if (!motionPreference.matches) boatFrame = requestAnimationFrame(animateBoat);
  };

  let navigateToPanel = () => {};
  const steps = panels.map((panel, index) => {
    const step = document.createElement("button");
    const labelId = panel.getAttribute("aria-labelledby");
    const label = labelId
      ? document.getElementById(labelId)?.textContent.trim()
      : null;

    step.type = "button";
    step.className = "panel-progress__step";
    step.dataset.panelProgressStep = String(index);
    step.setAttribute("aria-label", `Go to ${label || `section ${index + 1}`}`);
    step.addEventListener("click", () => navigateToPanel(index));

    progress.append(step);
    return step;
  });

  document.body.append(progress);
  const resizeObserver = new ResizeObserver(measure);
  resizeObserver.observe(progress);
  motionPreference.addEventListener("change", handleMotionPreference);
  measure();
  if (!motionPreference.matches) boatFrame = requestAnimationFrame(animateBoat);

  return {
    setProgress(value) {
      targetProgress = Math.min(1, Math.max(0, value));
      if (motionPreference.matches) render();
    },
    setActive(index) {
      steps.forEach((step, stepIndex) => {
        const isActive = stepIndex === index;
        step.classList.toggle("is-active", isActive);
        if (isActive) step.setAttribute("aria-current", "step");
        else step.removeAttribute("aria-current");
      });
    },
    setNavigator(nextNavigator) {
      navigateToPanel = nextNavigator;
    },
    destroy() {
      cancelAnimationFrame(boatFrame);
      resizeObserver.disconnect();
      motionPreference.removeEventListener("change", handleMotionPreference);
      progress.remove();
    },
  };
}

const horizontalStage = document.querySelector("[data-horizontal-stage]");
const horizontalTrack = document.querySelector("[data-horizontal-track]");
const horizontalPanels = [...(horizontalTrack?.querySelectorAll("[data-panel]:not([hidden])") ?? [])];
const desktopExperience = window.matchMedia("(min-width: 1024px)");
const panelProgress = desktopExperience.matches ? createPanelProgress(horizontalPanels) : null;
panelProgress?.setActive(0);

const destroyHorizontalScroll = desktopExperience.matches
  ? initHorizontalScroll(horizontalStage, horizontalTrack, {
      onPanelChange: (index) => panelProgress?.setActive(index),
      onPanelProgress: (value) => panelProgress?.setProgress(value),
      onNavigateReady: (navigateToPanel) => panelProgress?.setNavigator(navigateToPanel),
    })
  : () => {};

const reloadAtExperienceBreakpoint = () => {
  destroyHorizontalScroll();
  panelProgress?.destroy();
  window.setTimeout(() => window.location.reload(), 120);
};
desktopExperience.addEventListener("change", reloadAtExperienceBreakpoint);

window.addEventListener("pagehide", () => {
  desktopExperience.removeEventListener("change", reloadAtExperienceBreakpoint);
  destroyHorizontalScroll();
  panelProgress?.destroy();
}, { once: true });

document.querySelector('.brand[href="#top"]')?.addEventListener("click", (event) => {
  event.preventDefault();
  window.scrollTo({ top: 0, behavior: "auto" });
  history.replaceState(null, "", `${location.pathname}${location.search}`);
});

const feedbackForm = document.querySelector("[data-feedback-form]");
const feedbackText = feedbackForm?.querySelector("textarea");
const characterCount = feedbackForm?.querySelector("[data-character-count]");
const feedbackStatus = feedbackForm?.querySelector("[data-feedback-status]");
const feedbackSubmit = feedbackForm?.querySelector("button[type='submit']");

feedbackText?.addEventListener("input", () => {
  if (characterCount) characterCount.textContent = `${feedbackText.value.length}/4000`;
});

feedbackForm?.addEventListener("submit", (event) => {
  event.preventDefault();
  if (!feedbackForm.reportValidity()) return;

  const message = feedbackText.value.trim();
  if (!message) return;

  if (feedbackSubmit) {
    feedbackSubmit.disabled = true;
    feedbackSubmit.setAttribute("aria-busy", "true");
  }
  if (feedbackStatus) feedbackStatus.textContent = "Sending…";

  fetch("/api/feedback", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ message }),
  })
    .then(async (response) => {
      const result = await response.json().catch(() => null);
      if (!response.ok || !result?.ok) throw new Error("Feedback request failed");
      feedbackText.value = "";
      if (characterCount) characterCount.textContent = "0/4000";
      if (feedbackStatus) feedbackStatus.textContent = "Feedback sent anonymously. Thanks.";
    })
    .catch(() => {
      if (feedbackStatus) feedbackStatus.textContent = "Couldn’t send feedback right now. Please try again.";
    })
    .finally(() => {
      if (feedbackSubmit) {
        feedbackSubmit.disabled = false;
        feedbackSubmit.removeAttribute("aria-busy");
      }
    });
});
