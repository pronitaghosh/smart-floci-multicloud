FROM node:20-alpine

WORKDIR /app

# --chown/--chmod are required: COPY otherwise preserves the host file mode,
# and a 0600 source file becomes unreadable once we drop to the node user.
COPY --chown=node:node --chmod=644 package.json ./
RUN npm install --omit=dev && npm cache clean --force

COPY --chown=node:node --chmod=644 server.js ./

# node:20-alpine ships an unprivileged 'node' user; don't run as root.
USER node

ENV NODE_ENV=production PORT=4000
EXPOSE 4000

CMD ["node", "server.js"]
