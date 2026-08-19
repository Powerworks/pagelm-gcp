# --- Stage 1: Build Vite App ---
FROM node:22-alpine AS builder
WORKDIR /app

RUN corepack enable && corepack prepare pnpm@latest --activate

COPY frontend/package.json frontend/pnpm-lock.yaml ./
RUN pnpm install --ignore-scripts

COPY frontend/ ./

# Pass build arg to Vite environment
ARG VITE_API_URL
ENV VITE_API_URL=$VITE_API_URL

RUN pnpm exec vite build

# --- Stage 2: Serve via Nginx ---
FROM nginx:alpine
COPY --from=builder /app/dist /usr/share/nginx/html
COPY frontend/nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
