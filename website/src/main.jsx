import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { MacOSDesktop } from "./macos/MacOSDesktop.jsx";
import "./main.js";

createRoot(document.getElementById("macos-hero-root")).render(
  <StrictMode>
    <MacOSDesktop />
  </StrictMode>,
);

requestAnimationFrame(() => {
  requestAnimationFrame(() => document.documentElement.classList.remove("page-loading"));
});
