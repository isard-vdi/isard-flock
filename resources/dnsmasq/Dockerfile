FROM alpine:edge
RUN apk update
RUN apk --no-cache add dnsmasq
RUN mkdir -p /etc/default/
RUN echo -e "ENABLED=1\nIGNORE_RESOLVCONF=yes" > /etc/default/dnsmasq
ENTRYPOINT ["dnsmasq","--no-daemon"]

