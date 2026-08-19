# base
FROM node:22.16.0-alpine AS base

ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"

RUN npm i -g pnpm@10.13.1

WORKDIR /app

# deps
FROM base AS deps

COPY package*.json pnpm*.yaml ./

RUN pnpm i --frozen-lockfile

# build
FROM base AS build

ARG VITE_BACKEND_URL
ARG VITE_TIMEOUT
ENV VITE_BACKEND_URL=$VITE_BACKEND_URL
ENV VITE_TIMEOUT=$VITE_TIMEOUT

COPY --from=deps /app/node_modules ./node_modules
COPY . .

RUN pnpm build

# runtime
FROM base AS runtime

COPY --from=build /app/dist ./dist

RUN npm install -g serve

EXPOSE 8080
ENV PORT=8080

CMD ["sh", "-c", "serve -s dist -l tcp://0.0.0.0:${PORT}"]
