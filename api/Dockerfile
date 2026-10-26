# api: Node.js con Express. Sigue las seis reglas del LAB-02:
# tag fijo, dependencias antes que código, sin root, sin secretos, imagen chica, un proceso.
FROM node:22-alpine

# Parchea los paquetes del sistema de la imagen base antes de instalar nada.
# Se hace aquí, como root, porque más abajo el contenedor baja al uid 1000.
RUN apk upgrade --no-cache

ENV NODE_ENV=production
WORKDIR /app

COPY package*.json ./
RUN npm ci --omit=dev

COPY app.js server.js ./

# npm sirve para INSTALAR; en ejecución la app solo necesita "node". Dejarlo dentro
# arrastra las vulnerabilidades de sus propias dependencias (pacote, sigstore,
# brace-expansion...), que nunca se ejecutan aquí. Se elimina de la imagen final.
RUN rm -rf /usr/local/lib/node_modules/npm /usr/local/bin/npm /usr/local/bin/npx

# node es el uid 1000 en la imagen oficial. Numérico para que Kubernetes pueda verificar runAsNonRoot.
USER 1000
EXPOSE 3000

HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
  CMD ["wget", "-qO-", "http://127.0.0.1:3000/api/health"]

CMD ["node", "server.js"]
