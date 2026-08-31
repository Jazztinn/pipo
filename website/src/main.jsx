import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { MacOSDesktop } from "./macos/MacOSDesktop.jsx";
import { MobileSite } from "./mobile/MobileSite.jsx";
import "./mobile/mobile.css";
import "./main.js";

createRoot(document.getElementById("mobile-site-root")).render(
  <StrictMode>
    <MobileSite />
  </StrictMode>,
);

createRoot(document.getElementById("macos-hero-root")).render(
  <StrictMode>
    <MacOSDesktop />
  </StrictMode>,
);

requestAnimationFrame(() => {
  requestAnimationFrame(() => document.documentElement.classList.remove("page-loading"));
});
