import { resolve } from "node:path";
import { defineConfig } from "vite";

export default defineConfig({
  server: {
    host: "0.0.0.0",
    port: 4173
  },
  build: {
    outDir: "dist",
    rollupOptions: {
      input: {
        main: resolve(__dirname, "index.html"),
        download: resolve(__dirname, "download/macos/index.html"),
        privacy: resolve(__dirname, "privacy/index.html"),
        support: resolve(__dirname, "support/index.html")
      }
    }
  }
});
