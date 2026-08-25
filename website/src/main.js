import { initHorizontalScroll } from "./horizontal-scroll.js";

const clickSound = new Audio("/pipoclick.mp3");
clickSound.preload = "auto";
clickSound.volume = 0.35;
const cartoonSound = document.querySelector("#pipo-cartoon-sound");
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
  if (link?.href.includes("/releases/latest")) {
    event.preventDefault();
    playCartoonSound().then(() => {
      window.setTimeout(() => { window.location.href = link.href; }, 220);
    });
    return;
  }
  if (!event.target.closest("button, a")) return;
  clickSound.currentTime = 0;
  clickSound.play().catch(() => {});
}, true);

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

function createPanelProgress(panels) {
  if (panels.length < 2) return null;

  const progress = document.createElement("nav");
  progress.className = "panel-progress";
  progress.dataset.panelProgress = "";
  progress.setAttribute("aria-label", "Page sections");

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

    const marker = document.createElement("span");
    marker.className = "panel-progress__marker";
    marker.setAttribute("aria-hidden", "true");
    step.append(marker);
    progress.append(step);
    return step;
  });

  document.body.append(progress);

  return {
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
      progress.remove();
    },
  };
}

const horizontalStage = document.querySelector("[data-horizontal-stage]");
const horizontalTrack = document.querySelector("[data-horizontal-track]");
const horizontalPanels = [...(horizontalTrack?.querySelectorAll("[data-panel]") ?? [])];
const panelProgress = createPanelProgress(horizontalPanels);
panelProgress?.setActive(0);

const destroyHorizontalScroll = initHorizontalScroll(horizontalStage, horizontalTrack, {
  onPanelChange: (index) => panelProgress?.setActive(index),
  onNavigateReady: (navigateToPanel) => panelProgress?.setNavigator(navigateToPanel),
});

window.addEventListener("pagehide", () => {
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
const feedbackEmail = feedbackForm?.querySelector('input[type="email"]');
const characterCount = feedbackForm?.querySelector("[data-character-count]");
const feedbackTypes = [...(feedbackForm?.querySelectorAll("[data-feedback-type]") ?? [])];
const githubSubmit = feedbackForm?.querySelector("[data-github-submit]");
let feedbackType = "Feedback";

feedbackTypes.forEach((button) => {
  button.addEventListener("click", () => {
    feedbackType = button.dataset.feedbackType;
    feedbackTypes.forEach((option) => {
      option.setAttribute("aria-pressed", String(option === button));
    });
  });
});

feedbackText?.addEventListener("input", () => {
  if (characterCount) characterCount.textContent = `${feedbackText.value.length}/4000`;
});

feedbackForm?.addEventListener("submit", (event) => {
  event.preventDefault();
  if (!feedbackForm.reportValidity()) return;

  const subject = encodeURIComponent(`Pipo ${feedbackType}`);
  const emailLine = feedbackEmail?.value.trim() ? `\n\nReply to: ${feedbackEmail.value.trim()}` : "";
  const body = encodeURIComponent(`${feedbackText.value.trim()}${emailLine}`);
  window.location.href = `mailto:legaspijazztinnkyle@gmail.com?subject=${subject}&body=${body}`;
});

githubSubmit?.addEventListener("click", () => {
  if (!feedbackForm?.reportValidity()) return;

  const title = encodeURIComponent(`${feedbackType}: `);
  const emailLine = feedbackEmail?.value.trim() ? `\n\nContact: ${feedbackEmail.value.trim()}` : "";
  const body = encodeURIComponent(`${feedbackText.value.trim()}${emailLine}`);
  window.open(`https://github.com/Jazztinn/pipo/issues/new?title=${title}&body=${body}`, "_blank", "noopener,noreferrer");
});
