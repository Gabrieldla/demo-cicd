# web: nginx sirviendo la página y reenviando /api/ al backend.
# Imagen "unprivileged": corre como usuario nginx (uid 101) y escucha en 8080.
FROM nginxinc/nginx-unprivileged:1.29-alpine

# La imagen base arrastra 45 vulnerabilidades HIGH con parche disponible (curl,
# c-ares, brotli, libxml2...). apk upgrade las lleva a la versión corregida del
# repositorio de Alpine. Hay que subir a root para instalar y volver a bajar:
# la imagen unprivileged corre como el usuario nginx (uid 101).
USER root
RUN apk upgrade --no-cache
USER 101

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY public/ /usr/share/nginx/html/

EXPOSE 8080
