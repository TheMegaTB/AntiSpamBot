FROM webserverhu/spamassassin:latest

RUN printf "deb http://archive.debian.org/debian/ jessie main\ndeb-src http://archive.debian.org/debian/ jessie main\ndeb http://security.debian.org jessie/updates main\ndeb-src http://security.debian.org jessie/updates main" > /etc/apt/sources.list

RUN apt-get update && \
    apt-get install --no-install-recommends --yes build-essential && \
    apt-get autoclean && apt-get --yes autoremove && apt-get clean && \
    rm -rf /var/lib/apt/lists/*

COPY progress.cpp /
RUN g++ /progress.cpp -o /progress

FROM webserverhu/spamassassin:latest

COPY --from=0 /progress /usr/bin/progress
COPY ./checkMBox.sh /usr/bin

ENTRYPOINT ["/usr/bin/checkMBox.sh"]
