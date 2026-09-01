FROM node:20-alpine

WORKDIR /app

# Copy workspace manifests
COPY package.json package-lock.json* ./
COPY backend/package.json ./backend/package.json
COPY shared/package.json ./shared/package.json
COPY frontend/package.json ./frontend/package.json

# Install all workspaces (backend+shared)
RUN npm install --workspaces --include-workspace-root

# Copy source
COPY backend ./backend
COPY shared ./shared
COPY frontend ./frontend

WORKDIR /app/backend

RUN npm run build

EXPOSE 3000

CMD ["npm", "start"]
