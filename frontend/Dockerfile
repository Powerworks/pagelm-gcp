# --- Stage 1: Build Vite App ---
FROM node:22-alpine AS builder
WORKDIR /app

# Enable pnpm
RUN corepack enable && corepack prepare pnpm@latest --activate

COPY frontend/package.json frontend/pnpm-lock.yaml ./

# Bypass interactive build script approvals in pnpm v10
RUN pnpm install --ignore-scripts

COPY frontend/ ./
RUN pnpm exec vite build

# --- Stage 2: Serve via Nginx ---
FROM nginx:alpine
COPY --from=builder /app/dist /usr/share/nginx/html
COPY frontend/nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
