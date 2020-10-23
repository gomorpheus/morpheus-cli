FROM ruby:2.5.1

RUN gem install morpheus-cli -v 5.0.2

ENTRYPOINT ["morpheus"]