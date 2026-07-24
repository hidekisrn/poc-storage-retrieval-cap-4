# Simulador de motores de armazenamento (DDIA — Storage & Retrieval)
# Página estática autocontida servida por nginx.
FROM nginx:1.27-alpine

# Config do nginx com charset UTF-8 (evita mojibake em acentos/travessões)
COPY default.conf /etc/nginx/conf.d/default.conf

# Serve o simulador na raiz (index.html)
COPY lsm-simulator.html /usr/share/nginx/html/index.html

# nginx já expõe a 80 e sobe sozinho via imagem base
EXPOSE 80

# Healthcheck simples: a página responde?
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s \
  CMD wget -qO- http://localhost/ >/dev/null 2>&1 || exit 1
