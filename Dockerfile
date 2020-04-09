FROM ruby:2.5.1

RUN gem install morpheus-cli -v 4.2.7

ENTRYPOINT ["morpheus"]