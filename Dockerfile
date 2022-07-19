FROM ruby:2.5.1

RUN gem install morpheus-cli -v 5.5.2

ENTRYPOINT ["morpheus"]