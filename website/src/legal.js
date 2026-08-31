const visitNumber = document.querySelector("[data-visit-number]");
const sections = [...document.querySelectorAll(".legal-content section")];
const tocLinks = [...document.querySelectorAll(".legal-toc a")];
const cartoonSound = document.querySelector("#pipo-cartoon-sound");

document.addEventListener("click", (event) => {
  if (!(event.target instanceof Element)) return;
  const link = event.target.closest("a");
  if (!link?.matches("[data-pipo-download]")) return;

  if (!cartoonSound) return;
  cartoonSound.currentTime = 0;
  cartoonSound.play().catch(() => {});
}, true);

try {
  const seedVisits = 50;
  const stored = Number.parseInt(localStorage.getItem("pipo-visits") ?? "", 10);
  const visits = Number.isFinite(stored) ? Math.max(seedVisits, stored) : seedVisits;
  if (visitNumber) visitNumber.textContent = visits.toLocaleString();
} catch {
  if (visitNumber) visitNumber.textContent = "50";
}

const updateActiveSection = () => {
  let activeId = sections[0]?.id;
  for (const section of sections) {
    if (section.getBoundingClientRect().top <= window.innerHeight * 0.38) activeId = section.id;
  }
  tocLinks.forEach((link) => link.classList.toggle("is-active", link.getAttribute("href") === `#${activeId}`));
};

updateActiveSection();
window.addEventListener("scroll", updateActiveSection, { passive: true });
window.addEventListener("resize", updateActiveSection);
