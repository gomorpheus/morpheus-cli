FROM ruby:2.5.1

RUN gem install morpheus-cli -v 5.2.1

ENTRYPOINT ["morpheus"]