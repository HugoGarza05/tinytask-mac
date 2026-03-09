export default {
  content: [
    "./index.html",
    "./download/macos/index.html",
    "./privacy/index.html",
    "./support/index.html",
    "./src/**/*.{js,css}"
  ],
  theme: {
    extend: {
      colors: {
        ink: "#031115",
        abyss: "#071d22",
        panel: "#0d2a31",
        cyan: "#57f5ff",
        teal: "#12b8c4",
        ember: "#ff8471",
        sand: "#d5eff4"
      },
      fontFamily: {
        display: ["Avenir Next", "Avenir", "Segoe UI", "Helvetica Neue", "sans-serif"],
        body: ["Avenir Next", "Avenir", "Segoe UI", "Helvetica Neue", "sans-serif"]
      },
      boxShadow: {
        glow: "0 24px 64px rgba(18, 184, 196, 0.22)",
        panel: "0 30px 80px rgba(0, 0, 0, 0.4)"
      }
    }
  },
  plugins: []
};
