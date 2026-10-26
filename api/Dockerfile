# api: Node.js con Express. Sigue las seis reglas del LAB-02:
# tag fijo, dependencias antes que código, sin root, sin secretos, imagen chica, un proceso.
# Node 24 es el LTS vigente (Krypton). Dependabot propuso el 25 y su PR paso los
# doce jobs en verde, pero el 25 es linea "current": deja de recibir parches
# mucho antes. Que las pruebas pasen dice que el codigo es compatible, no que la
# version sea una buena base para servir algo.
FROM node:24-alpine

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
