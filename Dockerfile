FROM ruby:2.5.1

RUN gem install morpheus-cli -v 5.3.1

ENTRYPOINT ["morpheus"]