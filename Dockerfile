FROM ruby:2.5.1

RUN gem install morpheus-cli -v 5.3.2.3

ENTRYPOINT ["morpheus"]