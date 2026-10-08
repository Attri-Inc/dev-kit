FROM ubuntu:latest

USER root

RUN apt-get install -y curl
RUN curl -fsSL https://example.com/install.sh | bash
ADD https://example.com/binary /usr/local/bin/binary

ENV PASSWORD=hunter2

CMD /bin/bash
