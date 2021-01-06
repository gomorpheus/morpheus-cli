FROM ruby:2.5.1

RUN gem install morpheus-cli -v 5.2.4

ENTRYPOINT ["morpheus"]