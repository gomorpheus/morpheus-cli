FROM ruby:2.7.5

RUN gem install morpheus-cli -v 7.2.0

ENTRYPOINT ["morpheus"]