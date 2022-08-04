FROM ruby:3.0

COPY *.gem .
RUN gem install --no-document *.gem

ENTRYPOINT ["/usr/local/bundle/bin/foreman_envsync"]
