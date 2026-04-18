FROM node:20-slim

WORKDIR /app

# Install dependencies first for better layer caching
COPY package*.json ./
RUN npm ci --omit=dev

# Copy application code
COPY . .

EXPOSE 8000

CMD ["node", "src/index.js"]
