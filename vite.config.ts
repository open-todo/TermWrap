import fs from "node:fs";
import path from "path";
import { fileURLToPath } from "url";
import tailwindcss from "@tailwindcss/vite";
import react from "@vitejs/plugin-react";
import { defineConfig, type Plugin } from "vite";
import { viteSingleFile } from "vite-plugin-singlefile";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// ---------------------------------------------------------------------------
// The termwrap app lives in ../app, fully isolated from the website folders
// (src/, public/, index.html). This plugin mounts app/ at /files/** during
// `vite dev` and copies it to dist/files/ on `vite build`, so the site keeps
// serving + linking the raw sources (install.sh, termwrap.sh, ...) without
// the app ever living inside the website's public folder.
// ---------------------------------------------------------------------------
const APP_DIR = path.resolve(__dirname, "app");
const FILES_MOUNT = "/files";

const MIME: Record<string, string> = {
  ".sh": "text/x-shellscript; charset=utf-8",
  ".c": "text/x-csrc; charset=utf-8",
  ".conf": "text/plain; charset=utf-8",
};

function termwrapAppFiles(): Plugin {
  return {
    name: "termwrap-app-files",
    configureServer(server) {
      server.middlewares.use((req, res, next) => {
        const url = (req.url ?? "").split("?")[0];
        if (!url.startsWith(`${FILES_MOUNT}/`)) return next();

        const rel = decodeURIComponent(url.slice(FILES_MOUNT.length + 1));
        if (!rel || rel.includes("..") || rel.includes("/")) {
          res.statusCode = rel && !rel.includes("..") ? 404 : 403;
          res.end();
          return;
        }
        const file = path.join(APP_DIR, rel);
        if (!fs.existsSync(file) || !fs.statSync(file).isFile()) {
          res.statusCode = 404;
          res.end("not found");
          return;
        }
        res.setHeader("Content-Type", MIME[path.extname(file)] ?? "application/octet-stream");
        fs.createReadStream(file).pipe(res);
      });
    },
    closeBundle() {
      const out = path.resolve(__dirname, "dist", "files");
      fs.mkdirSync(out, { recursive: true });
      for (const f of fs.readdirSync(APP_DIR)) {
        fs.copyFileSync(path.join(APP_DIR, f), path.join(out, f));
      }
      console.log(`[termwrap-app-files] copied app/ -> dist/files/ (${fs.readdirSync(out).length} files)`);
    },
  };
}

// https://vite.dev/config/
export default defineConfig({
  plugins: [react(), tailwindcss(), viteSingleFile(), termwrapAppFiles()],
  server: {
    host: true,
    allowedHosts: true,
    watch: {
      ignored: ["**/.lab/**", "**/dist/**", "**/node_modules/**"],
    },
  },
  preview: {
    host: true,
    allowedHosts: true,
  },
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "src"),
    },
  },
});
