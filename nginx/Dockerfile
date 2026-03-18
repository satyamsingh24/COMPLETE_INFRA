# ── Bilkul same as pehle — sirf curl install + healthcheck add kiya ──
FROM nginx:latest

# curl install karo — health check ke liye zaroori hai
RUN apt-get update && apt-get install -y curl && \
    rm -rf /var/lib/apt/lists/*

RUN rm /etc/nginx/conf.d/default.conf
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY static/ /usr/share/nginx/html/

# ── Health Check ──────────────────────────────────────────────────
HEALTHCHECK --interval=30s \
            --timeout=10s  \
            --retries=3    \
            --start-period=10s \
  CMD curl -f http://localhost || exit 1

EXPOSE 80

# FROM nginx:latest

# # Copy static frontend files
# COPY ./static /usr/share/nginx/html

# # Use your nginx config (renamed correctly)
# COPY nginx.conf /etc/nginx/conf.d/default.conf

# # Run nginx in foreground
# CMD ["nginx", "-g", "daemon off;"]