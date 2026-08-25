import { defineConfig } from "vite";

export default defineConfig({
  base: "./",
  plugins: [
    {
      name: "file-openable-build",
      apply: "build",
      transformIndexHtml: {
        order: "post",
        handler(html) {
          return html
            .replaceAll('<script type="module" crossorigin', '<script defer')
            .replaceAll('<script type="module"', '<script defer')
            .replaceAll('<link rel="stylesheet" crossorigin', '<link rel="stylesheet"')
            .replace(/\s*<link rel="modulepreload"[^>]*>/g, "")
            .replace(/\s*<link rel="manifest"[^>]*>/g, "");
        },
      },
    },
  ],
  build: {
    modulePreload: false,
    outDir: "dist",
    emptyOutDir: true,
    rollupOptions: {
      input: {
        main: "index.html",
        privacy: "privacy.html",
        terms: "terms.html",
      },
    },
  },
  preview: {
    host: "0.0.0.0",
    port: 4173,
  },
});
