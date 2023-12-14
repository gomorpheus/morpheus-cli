FROM ruby:2.7.5

RUN gem install morpheus-cli -v 6.3.3

ENTRYPOINT ["morpheus"]