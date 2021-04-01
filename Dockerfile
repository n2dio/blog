FROM thibaultmorin/zola:0.13.0 AS builder
COPY . /workdir
RUN ["/usr/bin/zola", "build"]

FROM nginx
COPY --from=builder /workdir/public/ /usr/share/nginx/html/
EXPOSE 80
CMD ["nginx","-g","daemon off;"]