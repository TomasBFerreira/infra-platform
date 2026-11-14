# Image for one Developer-area app (static site). Built by
# .github/workflows/app-provision.yml from the app repo's site/ directory.
# The app repo never supplies a Dockerfile or any build step: developer content
# is only ever copied in as static files.
FROM nginxinc/nginx-unprivileged:1.27-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY site/ /usr/share/nginx/html/
