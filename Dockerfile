FROM alpine:latest

LABEL maintainer="Lambert Lum"
LABEL description="Getting perl to work"

COPY server0.pl /root

RUN  apk add g++ make wget curl perl-dev perl-app-cpanminus \
  && cpanm Socket Fcntl POSIX Readonly::XS List::Util autodie \
  && apk del g++ make wget curl perl-dev perl-app-cpanminus \
  && rm -rf /root/.cpanm/* /usr/local/share/man/*


WORKDIR /root
ENTRYPOINT ["./server0.pl"]

EXPOSE 4020/tcp
