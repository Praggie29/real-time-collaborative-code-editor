# Stage 1: Build the Frontend
FROM node:20-alpine AS frontend-builder

WORKDIR /app

COPY ./Frontend/package.json ./Frontend/package-lock.json ./

RUN npm ci

COPY ./Frontend ./

RUN npm run build

# Stage 2: Build the Backend & serve
FROM node:20-alpine

ENV NODE_ENV=production

WORKDIR /app

COPY ./Backend/package.json ./Backend/package-lock.json ./

RUN npm ci --omit=dev

COPY ./Backend ./

# Copy built frontend into backend's public directory
COPY --from=frontend-builder /app/dist ./public

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:3000/health || exit 1

CMD ["node", "server.js"]